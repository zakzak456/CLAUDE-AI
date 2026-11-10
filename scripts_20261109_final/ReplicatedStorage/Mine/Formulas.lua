-- Stats and prices from levels (the same numbers on server and client).

local Config = require(script.Parent.Config)

local Formulas = {}

local S = Config.Stats
local W = Config.World

local function growth(base: number, mul: number, level: number): number
	return base * mul ^ (math.max(1, level) - 1)
end

-- Mineshaft i with upgrade levels s = { pick, speed, workers }
function Formulas.shaft(i: number, s)
	local def = Config.Shafts[i]
	local M = S.Miner
	-- pieces per trip: +6% per level, plus one extra piece per level so every level visibly helps
	local ore = math.max(1, math.floor(growth(M.Ore, M.OreGrowth, s.pick) + 0.5) + (math.max(1, s.pick) - 1) * (M.OreBonus or 0))
	local mineTime = math.max(M.MineTimeMin, growth(M.MineTime, M.MineTimeMul, s.speed))
	local walk = math.min(M.WalkSpeedMax, growth(M.WalkSpeed, M.WalkSpeedMul, s.speed))
	local dist = W.RockX - W.MinerHome
	local trip = 2 * dist / walk + mineTime
	local miners = math.clamp(s.workers or 1, 1, 5)
	local perSecond = ore * miners / trip
	return { ore = ore, mineTime = mineTime, walkSpeed = walk, miners = miners, trip = trip, perSecond = perSecond, valuePerSecond = perSecond * def.Value }
end

function Formulas.elevator(e)
	local E = S.Elevator
	return {
		capacity = math.floor(growth(E.Capacity, E.CapacityGrowth, e.cap) + 0.5),
		moveSpeed = math.min(E.MoveSpeedMax, growth(E.MoveSpeed, E.MoveSpeedMul, e.speed)),
		loadTime = math.max(E.LoadTimeMin, growth(E.LoadTime, E.LoadTimeMul, e.speed)),
		unloadTime = E.UnloadTime,
	}
end

function Formulas.warehouse(w)
	local T = S.Transporter
	local walk = math.min(T.WalkSpeedMax, growth(T.WalkSpeed, T.WalkSpeedMul, w.speed))
	local dist = W.TransporterHome - W.PileX
	return {
		capacity = math.floor(growth(T.Capacity, T.CapacityGrowth, w.cap) + 0.5),
		walkSpeed = walk,
		loadTime = T.LoadTime, unloadTime = T.UnloadTime,
		trip = 2 * dist / walk + T.LoadTime + T.UnloadTime,
	}
end

-- Y (design units) of a floor's centre line and of its elevator stop
function Formulas.floorY(i: number): number
	return W.SurfaceHeight + (i - 1) * W.FloorHeight + W.FloorHeight / 2
end

-- How much each stage can move when kept busy, in coins per second.
-- The elevator drops to the deepest floor with ore and fills on the way up, so
-- it always carries the richest ore first. managedOnly counts only shafts that
-- have a manager (used for offline earnings).
function Formulas.rates(d, managedOnly: boolean?)
	local prod, deepest, mining = {}, 0, 0
	for i, sh in d.shafts do
		if sh.unlocked then
			deepest = i
			if sh.manager or not managedOnly then
				local st = Formulas.shaft(i, sh)
				prod[i] = st.perSecond
				mining += st.valuePerSecond
			end
		end
	end
	local e = Formulas.elevator(d.elevator)
	local eTrip = 2 * (Formulas.floorY(math.max(1, deepest)) - W.ElevatorTopY) / e.moveSpeed + math.max(1, deepest) * e.loadTime + e.unloadTime
	local w = Formulas.warehouse(d.warehouse)
	local ePieces, wPieces = e.capacity / eTrip, w.capacity / w.trip
	local function carried(pieces)
		local value, left = 0, pieces
		for i = deepest, 1, -1 do
			local take = math.min(left, prod[i] or 0)
			value += take * Config.Shafts[i].Value
			left -= take
			if left <= 0 then
				break
			end
		end
		return value
	end
	-- what each stage could move at today's ore mix (for the panel and the hint)
	local pieces = 0
	for _, p in prod do
		pieces += p
	end
	local avg = if pieces > 0 then mining / pieces else Config.Shafts[math.max(1, deepest)].Value
	return {
		shafts = mining, elevator = ePieces * avg, warehouse = wPieces * avg,
		income = math.min(mining, carried(math.min(ePieces, wPieces))), -- what actually reaches the warehouse
		eTrip = eTrip, ePieces = ePieces, wPieces = wPieces,
	}
end

-- Price of the next level of an upgrade (nil when maxed). value = shaft Value (1 for others)
function Formulas.price(def, level: number, value: number?): number?
	value = value or 1
	if def.Prices then
		local nextCount = level + 1
		if nextCount > def.Max then
			return nil
		end
		return math.floor(def.Prices[nextCount - 1] * value + 0.5)
	end
	if level >= def.Max then
		return nil
	end
	return math.floor(def.Base * def.Growth ^ (level - 1) * value + 0.5)
end

function Formulas.upgradeDef(stage: string, id: string)
	for _, def in Config.Upgrades[stage] or {} do
		if def.Id == id then
			return def
		end
	end
	return nil
end

-- 1234 -> "1,234"; 1.5e6 -> "1.5M"
local SUFFIX = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
function Formulas.short(n: number): string
	n = math.floor(n + 0.5)
	if n < 10000 then
		local s = tostring(n)
		return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	local i = 0
	local v = n
	while v >= 1000 and i < #SUFFIX do
		v /= 1000
		i += 1
	end
	local text = if v >= 100 then string.format("%d", math.floor(v)) elseif v >= 10 then string.format("%.1f", math.floor(v * 10) / 10) else string.format("%.2f", math.floor(v * 100) / 100)
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return text .. SUFFIX[i]
end

return Formulas
