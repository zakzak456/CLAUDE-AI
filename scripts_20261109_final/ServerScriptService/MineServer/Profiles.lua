-- Player profiles in a DataStore behind a session lock, so a save is only ever
-- open on one server. Saves are ordered (one write per player at a time, only the
-- newest data goes out next) and retried; a profile that failed to load is never
-- written. Studio uses its own store name, or memory when Studio has no API
-- access, so playtests never touch live saves.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Mine.Config)

local Profiles = {}
Profiles.serverId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
Profiles.mode = "datastore" -- "memory" in Studio without API access

local DATA = Config.Data
local store: DataStore?
local memory = {}
local queues = {}

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end
Profiles.now = now

local function key(userId: number): string
	return "u_" .. userId
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, x in v do
		t[k] = deepCopy(x)
	end
	return t
end
Profiles.copy = deepCopy

local function update(k: string, transform)
	if Profiles.mode == "memory" then
		local result = transform(deepCopy(memory[k]))
		if result ~= nil then
			memory[k] = deepCopy(result)
		end
		return true
	end
	if not store then
		return false, "no data store"
	end
	return pcall(store.UpdateAsync, store, k, transform)
end

local function lockedElsewhere(old, t: number, staleAfter: number?): boolean
	if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.server == Profiles.serverId then
		return false
	end
	return staleAfter == nil or t - (tonumber(old.lock.at) or 0) < staleAfter
end

function Profiles.init()
	local name = DATA.Store .. (if RunService:IsStudio() then DATA.StudioSuffix else "")
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	store = if ok then result else nil
	if RunService:IsStudio() then
		local works = store ~= nil and pcall(store.GetAsync, store, "probe")
		if not works then
			Profiles.mode = "memory"
			warn("[Mine] Studio has no DataStore access, so saves live in memory for this test session.")
		end
	end
end

-- Opens a profile and takes its lock (fresh() for first-timers). nil when it can't;
-- nothing is written then.
function Profiles.load(userId: number, fresh, status)
	local k = key(userId)
	for attempt = 1, DATA.LoadAttempts do
		local conflict, loaded = false, nil
		local ok, err = update(k, function(old)
			local t = now()
			if lockedElsewhere(old, t, DATA.LockStale) then
				conflict = true
				return nil
			end
			local p = if type(old) == "table" then old else fresh()
			p.lock = { server = Profiles.serverId, at = t }
			loaded = p
			return p
		end)
		if ok and loaded then
			loaded.lock = nil
			return deepCopy(loaded)
		end
		if status then
			status(if conflict then "Your save is still closing on another server..." else "Waiting for the save servers...")
		end
		if not ok then
			warn("[Mine] profile load failed, retrying:", err)
		end
		if attempt < DATA.LoadAttempts then
			task.wait(math.min(3 * attempt, 15))
		end
	end
	return nil
end

-- Queues a save; release = unlock (session over). The newest data goes out next.
function Profiles.save(userId: number, data, release: boolean?)
	local q = queues[userId]
	if not q then
		q = { busy = false, waiters = {} }
		queues[userId] = q
	end
	q.pending = { data = deepCopy(data), release = release == true or (q.pending ~= nil and q.pending.release) }
	if q.busy then
		return
	end
	q.busy = true
	task.spawn(function()
		while q.pending do
			local job = q.pending
			q.pending = nil
			local written = false
			for attempt = 1, DATA.SaveAttempts do
				local refused = false
				local ok, err = update(key(userId), function(old)
					if lockedElsewhere(old, now(), nil) then
						refused = true
						return nil
					end
					local new = deepCopy(job.data)
					new.seq = (type(old) == "table" and tonumber(old.seq) or 0) + 1
					new.lock = if job.release then nil else { server = Profiles.serverId, at = now() }
					return new
				end)
				if refused then
					warn("[Mine] save skipped: profile", userId, "is locked by another server")
					break
				end
				if ok then
					written = true
					break
				end
				warn("[Mine] save failed, retrying:", err)
				if attempt < DATA.SaveAttempts then
					task.wait(2 * attempt)
				end
			end
			q.lastOk = written
		end
		q.busy = false
		local waiters = q.waiters
		q.waiters = {}
		for _, thread in waiters do
			task.spawn(thread)
		end
	end)
end

function Profiles.waitIdle(userId: number)
	local q = queues[userId]
	if q and q.busy then
		table.insert(q.waiters, coroutine.running())
		coroutine.yield()
	end
end

function Profiles.busy(): boolean
	for _, q in queues do
		if q.busy then
			return true
		end
	end
	return false
end

-- Studio test aids (memory mode)
function Profiles.peek(userId: number)
	return deepCopy(memory[key(userId)])
end

function Profiles.age(userId: number, seconds: number): boolean
	local shifted = false
	update(key(userId), function(old)
		if type(old) ~= "table" then
			return nil
		end
		old.lastOnline = (tonumber(old.lastOnline) or now()) - seconds
		shifted = true
		return old
	end)
	return shifted
end

return Profiles
