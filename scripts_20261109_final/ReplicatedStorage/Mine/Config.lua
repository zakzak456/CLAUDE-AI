-- Every tuning value for the mine lives here (shared by server and client).
-- Ore moves as pieces. The elevator and the cart carry a number of pieces; each
-- piece is worth its shaft's Value in coins when it reaches the warehouse, so a
-- deeper shaft makes every trip richer without making transport harder.
-- The numbers below were tuned with a purchase simulation (see the notes file):
-- an efficient player opens shafts 2-6 at roughly 8, 13, 23, 37 and 54 minutes
-- (real players will be somewhat slower).
-- Times are seconds; distances are design units (the world is 1000 units wide).

local Config = {}

Config.Title = "Mom, Look! I Can Mine!"
Config.Version = 1

-- LAYOUT (design units; the client scales the world to the screen)
Config.World = {
	Width = 1000,
	SurfaceHeight = 340, -- sky, buildings and ground above the first floor
	GroundY = 280, -- the grass line
	FloorHeight = 180,
	ShaftLeft = 40, ShaftWidth = 130, -- the elevator shaft column
	CrateX = 245, -- the floor's ore crate (where miners drop ore)
	MinerHome = 320, -- where an idle miner waits
	RockX = 870, -- the rock face miners dig at
	ElevatorTopY = 220, -- the cage's resting height at the surface
	PileX = 245, -- the surface pile the elevator fills
	WarehouseDoorX = 760, -- where the transporter loads into the warehouse
	TransporterHome = 720,
}

-- MINESHAFTS: Value = coins per piece of ore (each floor is 10x richer)
Config.Shafts = {
	{ Name = "Copper", Color = Color3.fromRGB(230, 128, 60), Value = 1, UnlockCost = 0, ManagerCost = 50 },
	{ Name = "Iron", Color = Color3.fromRGB(170, 178, 192), Value = 10, UnlockCost = 250, ManagerCost = 120 },
	{ Name = "Silver", Color = Color3.fromRGB(214, 226, 244), Value = 100, UnlockCost = 80000, ManagerCost = 40000 },
	{ Name = "Gold", Color = Color3.fromRGB(255, 205, 60), Value = 1000, UnlockCost = 15000000, ManagerCost = 7500000 },
	{ Name = "Ruby", Color = Color3.fromRGB(235, 50, 85), Value = 10000, UnlockCost = 300000000, ManagerCost = 150000000 },
	{ Name = "Diamond", Color = Color3.fromRGB(110, 225, 255), Value = 100000, UnlockCost = 4000000000, ManagerCost = 2000000000 },
}

-- WORKER STATS (level 1 values and how they grow per level)
Config.Stats = {
	Miner = {
		Ore = 10, OreGrowth = 1.06, OreBonus = 1, -- pieces per trip at Pickaxes level 1 (+6% and +1 per level)
		MineTime = 1.4, MineTimeMul = 0.94, MineTimeMin = 0.35,
		WalkSpeed = 430, WalkSpeedMul = 1.05, WalkSpeedMax = 1100,
	},
	Elevator = {
		Capacity = 30, CapacityGrowth = 1.07, -- pieces per trip
		MoveSpeed = 320, MoveSpeedMul = 1.06, MoveSpeedMax = 1500,
		LoadTime = 0.8, LoadTimeMul = 0.95, LoadTimeMin = 0.2,
		UnloadTime = 0.5,
	},
	Transporter = {
		Capacity = 30, CapacityGrowth = 1.07,
		WalkSpeed = 260, WalkSpeedMul = 1.06, WalkSpeedMax = 900,
		LoadTime = 0.5, UnloadTime = 0.5,
	},
}

-- UPGRADES. cost(level) = Base x Growth^(level-1) (x shaft Value for shafts).
-- Prices grow faster than what a level adds, so every shaft slowly runs out of
-- cheap upgrades and the next, richer shaft becomes the better buy.
-- Miners is a count, with fixed prices for each extra miner.
Config.Upgrades = {
	shaft = {
		{ Id = "pick", Label = "Pickaxes", Info = "More ore per trip", Base = 8, Growth = 1.15, Max = 200 },
		{ Id = "speed", Label = "Boots", Info = "Mine and walk faster", Base = 14, Growth = 1.26, Max = 25 },
		{ Id = "workers", Label = "Miners", Info = "Hire another miner", Prices = { 70, 450, 3000, 20000 }, Max = 5 },
	},
	elevator = {
		{ Id = "cap", Label = "Bigger Cage", Info = "Carry more ore per trip", Base = 15, Growth = 1.14, Max = 200 },
		{ Id = "speed", Label = "Motor", Info = "Move and load faster", Base = 22, Growth = 1.26, Max = 30 },
	},
	warehouse = {
		{ Id = "cap", Label = "Bigger Cart", Info = "Carry more ore per trip", Base = 15, Growth = 1.14, Max = 200 },
		{ Id = "speed", Label = "Sneakers", Info = "Walk faster", Base = 22, Growth = 1.26, Max = 30 },
	},
}

Config.Managers = { Elevator = 100, Warehouse = 150 } -- shaft managers: Config.Shafts[i].ManagerCost

-- OFFLINE EARNINGS (only when the whole chain is automated; bounded)
Config.Offline = { MaxSeconds = 2 * 3600, Rate = 0.5, MinSeconds = 60 }

-- WARNINGS: a pile is "backing up" once it holds more than this many cage loads
Config.BackupLoads = 2

Config.Data = { Store = "MineTycoon_v1", StudioSuffix = "_STUDIO", LoadAttempts = 6, SaveAttempts = 3, LockStale = 90, Autosave = 60 }

Config.Tutorial = { Steps = 14 } -- step numbers live in the client tutorial; the server only stores progress

Config.Sounds = {}

return Config
