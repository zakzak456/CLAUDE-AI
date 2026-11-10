-- Shared client state and a tiny event bus, so the HUD, panel, tutorial and
-- cinematic can talk without knowing about each other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Mine"):WaitForChild("Remotes")
local Config = require(ReplicatedStorage.Mine.Config)

local App = {}
App.state = nil -- the latest snapshot (money, shafts, elevator, warehouse, tutorial)
App.ents = {
	miners = {},
	elev = { p = "idle", t0 = 0, t1 = 0, fromY = Config.World.ElevatorTopY, toY = Config.World.ElevatorTopY, floor = 0, load = 0 },
	tr = { p = "idle", t0 = 0, t1 = 0, carry = 0 },
}
App.gate = nil -- the tutorial may set gate(kind, stage, index) -> bool to steer early taps

local handlers = {}

function App.on(name: string, fn)
	handlers[name] = handlers[name] or {}
	table.insert(handlers[name], fn)
	return function()
		local list = handlers[name]
		local i = list and table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end

function App.emit(name: string, ...)
	for _, fn in table.clone(handlers[name] or {}) do
		task.spawn(fn, ...)
	end
end

function App.request(action: string, ...)
	Remotes.Request:FireServer(action, ...)
end

return App
