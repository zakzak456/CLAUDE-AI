-- MOM, LOOK! I CAN MINE! - server entry point.
-- The server owns money, ore, upgrade levels, managers, unlocks and tutorial
-- progress. Clients only ask (tap a stage, buy, hire, unlock, report tutorial
-- steps); every request is checked here, and the simulation (Sim) runs on the
-- server's clock. Saves go through Profiles with a session lock.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Mine
local Config = require(Shared.Config)
local Remotes = Shared.Remotes

local Profiles = require(script.Profiles)
local Sim = require(script.Sim)

Players.CharacterAutoLoads = false -- the game is played entirely in the 2D view

local sessions = {} -- [Player] = { sim, budget, budgetAt, finished }

local function freshProfile()
	local shafts = {}
	for i in Config.Shafts do
		shafts[i] = { unlocked = i == 1, pick = 1, speed = 1, workers = 1, manager = false, ore = 0 }
	end
	local t = Profiles.now()
	return {
		v = Config.Version, money = 0, totalEarned = 0, pile = 0, pileValue = 0, shafts = shafts,
		elevator = { cap = 1, speed = 1, manager = false },
		warehouse = { cap = 1, speed = 1, manager = false },
		tutorial = { step = 0, done = false },
		created = t, lastOnline = t, fresh = true,
	}
end

local function num(v, lo, hi, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	return math.clamp(math.floor(v), lo, hi)
end

-- Fills gaps and fixes types, so a damaged or older save still loads.
local function sanitize(p)
	local def = freshProfile()
	p.v = Config.Version
	p.money = math.max(0, tonumber(p.money) or 0)
	p.totalEarned = math.max(0, tonumber(p.totalEarned) or 0)
	p.pile = math.max(0, tonumber(p.pile) or 0)
	p.pileValue = if p.pile > 0 then math.max(0, tonumber(p.pileValue) or p.pile) else 0
	local shafts = {}
	local stillOpen = true
	for i, defShaft in def.shafts do
		local old = type(p.shafts) == "table" and type(p.shafts[i]) == "table" and p.shafts[i] or defShaft
		local unlocked = (i == 1) or (stillOpen and old.unlocked == true)
		stillOpen = unlocked
		shafts[i] = {
			unlocked = unlocked,
			pick = num(old.pick, 1, Config.Upgrades.shaft[1].Max, 1),
			speed = num(old.speed, 1, Config.Upgrades.shaft[2].Max, 1),
			workers = num(old.workers, 1, Config.Upgrades.shaft[3].Max, 1),
			manager = unlocked and old.manager == true,
			ore = math.max(0, tonumber(old.ore) or 0),
		}
	end
	p.shafts = shafts
	for _, stage in { "elevator", "warehouse" } do
		local old = type(p[stage]) == "table" and p[stage] or def[stage]
		local defs = Config.Upgrades[stage]
		p[stage] = { cap = num(old.cap, 1, defs[1].Max, 1), speed = num(old.speed, 1, defs[2].Max, 1), manager = old.manager == true }
	end
	local tut = type(p.tutorial) == "table" and p.tutorial or def.tutorial
	p.tutorial = { step = num(tut.step, 0, 99, 0), done = tut.done == true }
	p.created = tonumber(p.created) or def.created
	p.lastOnline = tonumber(p.lastOnline) or def.lastOnline
	return p
end

local function send(player: Player, batch)
	if player.Parent == Players then
		Remotes.Sync:FireClient(player, batch)
	end
end

local function save(player: Player, release: boolean?)
	local s = sessions[player]
	if not s or s.finished then
		return
	end
	local data = s.sim:saveData()
	data.lastOnline = Profiles.now()
	data.fresh = nil
	Profiles.save(player.UserId, data, release)
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("LoadStatus", "Opening your mine...")
	Profiles.waitIdle(player.UserId)
	local profile = Profiles.load(player.UserId, freshProfile, function(text)
		player:SetAttribute("LoadStatus", text)
	end)
	if player.Parent ~= Players then
		if profile then
			Profiles.save(player.UserId, profile, true)
		end
		return
	end
	if not profile then
		player:Kick("Your save couldn't be opened right now, so nothing was changed. Please rejoin in a minute.")
		return
	end
	local isNew = profile.fresh == true
	profile.fresh = nil
	profile = sanitize(profile)
	-- offline earnings: only for a fully automated chain, bounded, counted once
	local offline = nil
	local away = Profiles.now() - profile.lastOnline
	if not isNew and profile.tutorial.done and away >= Config.Offline.MinSeconds then
		local rate = Sim.idleRate(profile) * Config.Offline.Rate
		local seconds = math.min(away, Config.Offline.MaxSeconds)
		local earned = math.floor(rate * seconds)
		if earned > 0 then
			profile.money += earned
			profile.totalEarned += earned
			offline = { earned = earned, seconds = seconds, away = away, capped = away > Config.Offline.MaxSeconds }
		end
	end
	profile.lastOnline = Profiles.now()
	local sim = Sim.new(player, profile, send)
	sessions[player] = { sim = sim, budget = 0, budgetAt = 0, offline = offline }
	Profiles.save(player.UserId, sim:saveData(), false) -- stamps lastOnline now, so offline time can't be counted twice
	player:SetAttribute("LoadStatus", nil)
	player:SetAttribute("MineReady", true)
end

local function onPlayerRemoving(player: Player)
	local s = sessions[player]
	if s then
		save(player, true)
		s.finished = true
		sessions[player] = nil
	end
end

-- REQUESTS ---------------------------------------------------------------------------------

Remotes.Request.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any, c: any, d: any)
	local s = sessions[player]
	if not s or typeof(action) ~= "string" then
		return
	end
	local clock = os.clock()
	if clock - s.budgetAt > 1 then
		s.budgetAt, s.budget = clock, 0
	end
	s.budget += 1
	if s.budget > 30 then
		return -- too many requests this second: ignored, never queued
	end
	local sim = s.sim
	if action == "ready" then
		sim:sendFull()
		if s.offline then
			sim:fx("offline", s.offline.earned, s.offline.seconds, s.offline.capped)
			s.offline = nil
		end
	elseif action == "tap" then
		local ok, why = sim:tap(a, b)
		if not ok and why == "busy" then
			sim:fx("busy", a, b)
		end
	elseif action == "buy" then
		-- d = how many levels (1..200); stops at the first level it can't buy
		local count = num(d, 1, 200, 1)
		local bought, level, why = 0, nil, nil
		for _ = 1, count do
			local ok, res = sim:buy(a, b, c, true)
			if not ok then
				why = res
				break
			end
			bought += 1
			level = res
		end
		if bought > 0 then
			sim:fx("bought", a, b, c, level, bought)
			sim:sendFull()
		else
			sim:fx("deny", why, a, b, c)
		end
	elseif action == "hire" then
		local ok, why = sim:hire(a, b)
		if ok then
			sim:sendFull()
		else
			sim:fx("deny", why, a, b, "manager")
		end
	elseif action == "unlock" then
		local ok, why = sim:unlock(a)
		if ok then
			sim:sendFull()
		else
			sim:fx("deny", why, "unlock", a)
		end
	elseif action == "tut" then
		local step = num(a, 0, 99, nil)
		if step and step > sim.d.tutorial.step then
			sim.d.tutorial.step = step
		end
	elseif action == "tutdone" then
		sim.d.tutorial.done = true
		save(player, false)
	end
	sim:flush()
end)

-- START -----------------------------------------------------------------------------------

Profiles.init()
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

local lastTick = 0
RunService.Heartbeat:Connect(function()
	local clock = os.clock()
	if clock - lastTick < 0.05 then
		return
	end
	lastTick = clock
	for player, s in sessions do
		local ok, err = pcall(s.sim.step, s.sim)
		if not ok then
			warn("[Mine] sim error for", player.Name, err)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.Data.Autosave)
		for player in sessions do
			save(player, false)
		end
	end
end)

game:BindToClose(function()
	for player in table.clone(sessions) do
		onPlayerRemoving(player)
	end
	local deadline = os.clock() + 25
	while Profiles.busy() and os.clock() < deadline do
		task.wait(0.2)
	end
end)

-- Studio-only test hook (never live): drive and inspect the game from tests.
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "MineDebug"
	hook.OnInvoke = function(command: string, name: string?, arg: any)
		local player = name and Players:FindFirstChild(name) or Players:GetPlayers()[1]
		local s = player and sessions[player]
		if command == "dump" then
			if not s then
				return "no session"
			end
			local snap = s.sim:snapshot()
			snap.mode = Profiles.mode
			return HttpService:JSONEncode(snap)
		elseif command == "set" and s then
			for k, v in arg do
				s.sim.d[k] = v
			end
			for i, sh in s.sim.d.shafts do
				if sh.unlocked then
					s.sim:ensureMiners(i)
				end
			end
			s.sim.dirty = true
			s.sim:sendFull()
			s.sim:flush()
			return true
		elseif command == "stored" and player then
			return HttpService:JSONEncode(Profiles.peek(player.UserId) or {})
		elseif command == "leave" and player then
			player:SetAttribute("MineReady", false)
			onPlayerRemoving(player)
			Profiles.waitIdle(player.UserId)
			return true
		elseif command == "age" and player then
			return Profiles.age(player.UserId, arg)
		elseif command == "join" and player then
			if sessions[player] then
				return false
			end
			onPlayerAdded(player)
			return sessions[player] ~= nil
		elseif command == "wipe" and player then
			if sessions[player] then
				sessions[player].finished = true
				sessions[player] = nil
			end
			Profiles.waitIdle(player.UserId)
			Profiles.save(player.UserId, freshProfile(), true)
			Profiles.waitIdle(player.UserId)
			return true
		end
		return nil
	end
	hook.Parent = ServerStorage
end
