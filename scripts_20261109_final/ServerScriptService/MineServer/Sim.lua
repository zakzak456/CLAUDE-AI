-- One player's mine, simulated on the server. Ore only moves through the chain:
--   miners dig it and drop it in their floor's crate  ->  the elevator drops to
--   the deepest floor with ore and fills up on the way back (richest first), then
--   tips it onto the surface pile  ->  the transporter carries the pile into the
--   warehouse, and only then does it become money.
-- Ore is counted in pieces; the pile, the cage and the cart also remember what
-- their pieces are worth, because floors are worth different amounts.
-- Every worker is a small state machine with server-time stamps (t0..t1 per
-- phase); clients draw positions from those stamps, so what they see is the
-- simulation itself. A manual tap runs one full work cycle; a manager keeps a
-- stage cycling on its own (and only that stage).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Mine
local Config = require(Shared.Config)
local F = require(Shared.Formulas)

local W = Config.World

local Sim = {}
Sim.__index = Sim

local function now(): number
	return workspace:GetServerTimeNow()
end

function Sim.new(player: Player, data, send)
	local self = setmetatable({
		player = player, d = data, send = send, out = {}, dirty = true,
		miners = {}, -- [shaft] = { worker, ... }
		elev = { p = "idle", t0 = 0, t1 = 0, fromY = W.ElevatorTopY, toY = W.ElevatorTopY, floor = 0, target = 0, load = 0, value = 0 },
		tr = { p = "idle", t0 = 0, t1 = 0, carry = 0, value = 0 },
	}, Sim)
	for i, sh in data.shafts do
		if sh.unlocked then
			self:ensureMiners(i)
		end
	end
	return self
end

-- MESSAGES --------------------------------------------------------------------------

function Sim:emit(msg)
	table.insert(self.out, msg)
end

function Sim:minerMsg(s: number, w: number)
	local m = self.miners[s][w]
	self:emit({ "m", s, w, m.p, m.t0, m.t1, m.carry })
end

function Sim:elevMsg()
	local e = self.elev
	self:emit({ "e", e.p, e.t0, e.t1, e.fromY, e.toY, e.floor, e.load })
end

function Sim:trMsg()
	local t = self.tr
	self:emit({ "t", t.p, t.t0, t.t1, t.carry })
end

function Sim:fx(...)
	self:emit({ "fx", ... })
end

function Sim:counts()
	local ores = {}
	for i, sh in self.d.shafts do
		ores[i] = sh.ore
	end
	return { "n", self.d.money, ores, self.d.pile, self.d.totalEarned }
end

-- everything the client needs to draw the mine from scratch
function Sim:snapshot()
	local ents = {}
	for s, list in self.miners do
		for w, m in list do
			table.insert(ents, { "m", s, w, m.p, m.t0, m.t1, m.carry })
		end
	end
	local e, t = self.elev, self.tr
	table.insert(ents, { "e", e.p, e.t0, e.t1, e.fromY, e.toY, e.floor, e.load })
	table.insert(ents, { "t", t.p, t.t0, t.t1, t.carry })
	local d = self.d
	local shafts = {}
	for i, sh in d.shafts do
		shafts[i] = { unlocked = sh.unlocked, pick = sh.pick, speed = sh.speed, workers = sh.workers, manager = sh.manager, ore = sh.ore }
	end
	return {
		money = d.money, totalEarned = d.totalEarned, pile = d.pile, shafts = shafts,
		elevator = { cap = d.elevator.cap, speed = d.elevator.speed, manager = d.elevator.manager },
		warehouse = { cap = d.warehouse.cap, speed = d.warehouse.speed, manager = d.warehouse.manager },
		tutorial = { step = d.tutorial.step, done = d.tutorial.done }, ents = ents, serverNow = now(),
	}
end

function Sim:sendFull()
	self:emit({ "full", self:snapshot() })
	self.dirty = false
end

function Sim:flush()
	if self.dirty then
		table.insert(self.out, self:counts())
		self.dirty = false
	end
	if #self.out > 0 then
		local batch = self.out
		self.out = {}
		self.send(self.player, batch)
	end
end

-- MINERS ------------------------------------------------------------------------------

function Sim:ensureMiners(s: number)
	local sh = self.d.shafts[s]
	local list = self.miners[s]
	if not list then
		list = {}
		self.miners[s] = list
	end
	while #list < sh.workers do
		table.insert(list, { p = "idle", t0 = 0, t1 = 0, carry = 0 })
	end
end

function Sim:startMiner(s: number, w: number, at: number?)
	local st = F.shaft(s, self.d.shafts[s])
	local m = self.miners[s][w]
	-- each extra miner sets off a moment later, so they spread along the tunnel
	local t0 = at or (now() + (w - 1) * 0.18)
	m.p, m.t0, m.t1, m.carry = "out", t0, t0 + (W.RockX - W.MinerHome) / st.walkSpeed, 0
	self:minerMsg(s, w)
end

function Sim:advanceMiner(s: number, w: number)
	local sh = self.d.shafts[s]
	local m = self.miners[s][w]
	local st = F.shaft(s, sh)
	local t = m.t1
	if m.p == "out" then
		m.p, m.t0, m.t1 = "mine", t, t + st.mineTime
	elseif m.p == "mine" then
		m.carry = st.ore
		m.p, m.t0, m.t1 = "back", t, t + (W.RockX - W.MinerHome) / st.walkSpeed
	elseif m.p == "back" then
		sh.ore += m.carry
		self:fx("deposit", s, m.carry)
		m.carry = 0
		self.dirty = true
		if sh.manager then
			self:startMiner(s, w, t)
			return
		end
		m.p, m.t0, m.t1 = "idle", t, t
	else
		return
	end
	self:minerMsg(s, w)
end

-- ELEVATOR ------------------------------------------------------------------------------

local function unlockedCount(d): number
	local n = 0
	for _, sh in d.shafts do
		if sh.unlocked then
			n += 1
		end
	end
	return n
end

-- the deepest floor with ore below `below` (exclusive); nil if none
function Sim:floorWithOreAbove(below: number): number?
	for i = math.min(below - 1, unlockedCount(self.d)), 1, -1 do
		if self.d.shafts[i].ore > 0 then
			return i
		end
	end
	return nil
end

function Sim:moveElevator(toFloor: number, at: number)
	local e = self.elev
	local st = F.elevator(self.d.elevator)
	local fromY = if e.floor > 0 then F.floorY(e.floor) else W.ElevatorTopY
	local toY = if toFloor > 0 then F.floorY(toFloor) else W.ElevatorTopY
	e.p, e.t0, e.t1 = "move", at, at + math.abs(toY - fromY) / st.moveSpeed
	e.fromY, e.toY, e.target = fromY, toY, toFloor
	self:elevMsg()
end

function Sim:startElevator(at: number?): boolean
	local first = self:floorWithOreAbove(math.huge)
	if not first then
		return false
	end
	self.elev.floor, self.elev.load, self.elev.value = 0, 0, 0
	self:moveElevator(first, at or now())
	return true
end

function Sim:advanceElevator()
	local e = self.elev
	local st = F.elevator(self.d.elevator)
	local t = e.t1
	if e.p == "move" then
		e.floor = e.target
		if e.target > 0 then
			local sh = self.d.shafts[e.target]
			local take = math.min(sh.ore, st.capacity - e.load)
			sh.ore -= take
			e.load += take
			e.value += take * Config.Shafts[e.target].Value
			self.dirty = true
			e.p, e.t0, e.t1 = "load", t, t + st.loadTime
			e.fromY, e.toY = F.floorY(e.floor), F.floorY(e.floor)
			self:fx("load", e.floor, take)
		else
			e.p, e.t0, e.t1 = "unload", t, t + st.unloadTime
			e.fromY, e.toY = W.ElevatorTopY, W.ElevatorTopY
		end
	elseif e.p == "load" then
		local nextFloor = if e.load < st.capacity then self:floorWithOreAbove(e.floor) else nil
		self:moveElevator(nextFloor or 0, t)
		return
	elseif e.p == "unload" then
		self.d.pile += e.load
		self.d.pileValue += e.value
		self:fx("unload", e.load)
		e.load, e.value = 0, 0
		self.dirty = true
		if self.d.elevator.manager and self:startElevator(t) then
			return
		end
		e.p, e.t0, e.t1, e.floor = "idle", t, t, 0
	else
		return
	end
	self:elevMsg()
end

-- TRANSPORTER ------------------------------------------------------------------------------

function Sim:startTransporter(at: number?): boolean
	if self.d.pile <= 0 then
		return false
	end
	local st = F.warehouse(self.d.warehouse)
	local tr = self.tr
	local t0 = at or now()
	tr.p, tr.t0, tr.t1, tr.carry, tr.value = "out", t0, t0 + (W.TransporterHome - W.PileX) / st.walkSpeed, 0, 0
	self:trMsg()
	return true
end

function Sim:advanceTransporter()
	local tr = self.tr
	local st = F.warehouse(self.d.warehouse)
	local t = tr.t1
	if tr.p == "out" then
		local d = self.d
		local take = math.min(d.pile, st.capacity)
		local value = if take >= d.pile then d.pileValue else d.pileValue * take / d.pile
		d.pile -= take
		d.pileValue = if d.pile <= 0 then 0 else math.max(0, d.pileValue - value)
		tr.carry, tr.value = take, value
		self.dirty = true
		tr.p, tr.t0, tr.t1 = "load", t, t + st.loadTime
	elseif tr.p == "load" then
		tr.p, tr.t0, tr.t1 = "back", t, t + (W.TransporterHome - W.PileX) / st.walkSpeed
	elseif tr.p == "back" then
		tr.p, tr.t0, tr.t1 = "unload", t, t + st.unloadTime
	elseif tr.p == "unload" then
		local earned = math.floor(tr.value + 0.5)
		self.d.money += earned
		self.d.totalEarned += earned
		self:fx("sell", earned)
		tr.carry, tr.value = 0, 0
		self.dirty = true
		if self.d.warehouse.manager and self:startTransporter(t) then
			return
		end
		tr.p, tr.t0, tr.t1 = "idle", t, t
	else
		return
	end
	self:trMsg()
end

-- TICK ------------------------------------------------------------------------------------

function Sim:step()
	local t = now()
	for guard = 1, 40 do -- catch up if a tick was late (each pass moves one phase)
		local moved = false
		for s, list in self.miners do
			for w, m in list do
				if m.p ~= "idle" and m.t1 <= t then
					self:advanceMiner(s, w)
					moved = true
				end
			end
		end
		if self.elev.p ~= "idle" and self.elev.t1 <= t then
			self:advanceElevator()
			moved = true
		end
		if self.tr.p ~= "idle" and self.tr.t1 <= t then
			self:advanceTransporter()
			moved = true
		end
		if not moved then
			break
		end
	end
	-- managers keep their stage going
	for s, list in self.miners do
		if self.d.shafts[s].manager then
			for w, m in list do
				if m.p == "idle" then
					self:startMiner(s, w)
				end
			end
		end
	end
	if self.d.elevator.manager and self.elev.p == "idle" then
		self:startElevator()
	end
	if self.d.warehouse.manager and self.tr.p == "idle" then
		self:startTransporter()
	end
	self:flush()
end

-- PLAYER ACTIONS ------------------------------------------------------------------------------

-- One manual work cycle. Returns ok, reason.
function Sim:tap(stage: string, index: any): (boolean, string?)
	if stage == "shaft" then
		local s = if typeof(index) == "number" then index else 0
		local sh = self.d.shafts[s]
		if not sh or not sh.unlocked then
			return false, "locked"
		end
		if sh.manager then
			return false, "auto"
		end
		local started = 0
		for w, m in self.miners[s] do
			if m.p == "idle" then
				self:startMiner(s, w)
				started += 1
			end
		end
		return started > 0, if started > 0 then nil else "busy"
	elseif stage == "elevator" then
		if self.d.elevator.manager then
			return false, "auto"
		end
		if self.elev.p ~= "idle" then
			return false, "busy"
		end
		if not self:startElevator() then
			self:fx("empty", "elevator")
			return false, "empty"
		end
		return true
	elseif stage == "warehouse" then
		if self.d.warehouse.manager then
			return false, "auto"
		end
		if self.tr.p ~= "idle" then
			return false, "busy"
		end
		if not self:startTransporter() then
			self:fx("empty", "warehouse")
			return false, "empty"
		end
		return true
	end
	return false, "bad"
end

local function stageData(d, stage: string, index: any)
	if stage == "shaft" then
		local sh = typeof(index) == "number" and d.shafts[index]
		return if sh and sh.unlocked then sh else nil, if sh then Config.Shafts[index].Value else 1
	elseif stage == "elevator" then
		return d.elevator, 1
	elseif stage == "warehouse" then
		return d.warehouse, 1
	end
	return nil, 1
end

function Sim:priceOf(stage: string, index: any, id: string): (number?, any)
	local target, value = stageData(self.d, stage, index)
	local def = typeof(id) == "string" and F.upgradeDef(stage, id)
	if not target or not def then
		return nil, nil
	end
	local key = def.Id
	return F.price(def, target[key], value), def
end

-- Buys one level. Returns ok, message.
function Sim:buy(stage: any, index: any, id: any, quiet: boolean?): (boolean, string?)
	if typeof(stage) ~= "string" or typeof(id) ~= "string" then
		return false, "Invalid"
	end
	local price, def = self:priceOf(stage, index, id)
	if not def then
		return false, "Invalid"
	end
	if not price then
		return false, "Already maxed"
	end
	if self.d.money < price then
		return false, "Not enough money"
	end
	local target = stageData(self.d, stage, index)
	self.d.money -= price
	target[def.Id] += 1
	self.dirty = true
	if stage == "shaft" and def.Id == "workers" then
		self:ensureMiners(index)
	end
	if not quiet then
		self:fx("bought", stage, index, def.Id, target[def.Id], 1)
	end
	return true, target[def.Id]
end

function Sim:managerPrice(stage: string, index: any): number?
	if stage == "shaft" then
		local def = typeof(index) == "number" and Config.Shafts[index]
		return def and def.ManagerCost or nil
	elseif stage == "elevator" then
		return Config.Managers.Elevator
	elseif stage == "warehouse" then
		return Config.Managers.Warehouse
	end
	return nil
end

function Sim:hire(stage: any, index: any): (boolean, string?)
	if typeof(stage) ~= "string" then
		return false, "Invalid"
	end
	local target = stageData(self.d, stage, index)
	local price = self:managerPrice(stage, index)
	if not target or not price then
		return false, "Invalid"
	end
	if target.manager then
		return false, "Already hired"
	end
	if self.d.money < price then
		return false, "Not enough money"
	end
	self.d.money -= price
	target.manager = true
	self.dirty = true
	self:fx("hired", stage, index)
	return true
end

function Sim:unlock(index: any): (boolean, string?)
	local def = typeof(index) == "number" and Config.Shafts[index]
	if not def then
		return false, "Invalid"
	end
	if index ~= unlockedCount(self.d) + 1 then
		return false, "Unlock the floors above first"
	end
	if self.d.money < def.UnlockCost then
		return false, "Not enough money"
	end
	self.d.money -= def.UnlockCost
	local sh = self.d.shafts[index]
	sh.unlocked = true
	self:ensureMiners(index)
	self.dirty = true
	self:fx("unlocked", index)
	return true
end

-- Saved form: ore a worker is carrying goes back into the pile it came from, so a
-- save taken mid-trip neither loses nor duplicates ore.
function Sim:saveData()
	local d = table.clone(self.d)
	d.shafts = {}
	for i, sh in self.d.shafts do
		d.shafts[i] = table.clone(sh)
	end
	d.elevator = table.clone(self.d.elevator)
	d.warehouse = table.clone(self.d.warehouse)
	d.tutorial = table.clone(self.d.tutorial)
	for s, list in self.miners do
		for _, m in list do
			if m.p == "back" then
				d.shafts[s].ore += m.carry
			end
		end
	end
	d.pile += self.elev.load + self.tr.carry
	d.pileValue += self.elev.value + self.tr.value
	return d
end

-- Coins per second the chain earns when every stage is automated (offline earnings)
function Sim.idleRate(d): number
	if not (d.elevator.manager and d.warehouse.manager) then
		return 0
	end
	return F.rates(d, true).income
end

return Sim
