-- Mom, Look! I Can Mine! - client. Draws the 2D mine from the server's simulation
-- (every worker carries server timestamps for its current phase), turns taps into
-- requests, and plays the feedback. The server decides everything that matters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Mine")
local Remotes = Shared:WaitForChild("Remotes")
local Config = require(Shared:WaitForChild("Config"))
local F = require(Shared:WaitForChild("Formulas"))

local App = require(script:WaitForChild("App"))
local Kit = require(script:WaitForChild("Kit"))
local Theme = require(script:WaitForChild("Theme"))
local World = require(script:WaitForChild("World"))
local Hud = require(script:WaitForChild("Hud"))
local Panel = require(script:WaitForChild("Panel"))

local W = Config.World

-- The whole game is drawn in 2D, so the 3D world doesn't need rendering (saves battery on phones).
pcall(function()
	RunService:Set3dRenderingEnabled(false)
end)

for _, kind in { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(kind, false)
	end)
end

-- GUI ---------------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MineGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)
gui.Parent = player:WaitForChild("PlayerGui")

-- Everything draws inside one screen-sized frame. In Studio a FakeViewport
-- attribute on workspace (e.g. 844, 390) shrinks it to test phone layouts.
local screen = Instance.new("Frame")
screen.Name = "Screen"
screen.BackgroundTransparency = 1
screen.Size = UDim2.fromScale(1, 1)
screen.ClipsDescendants = true
screen.Parent = gui
local fake = RunService:IsStudio() and workspace:GetAttribute("FakeViewport")
if typeof(fake) == "Vector2" then
	screen.Size = UDim2.fromOffset(fake.X, fake.Y)
end
App.gui = screen
App.touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled or (RunService:IsStudio() and workspace:GetAttribute("FakeTouch") == true)

World.build(screen)
Hud.build(screen)
Panel.build(screen, Hud.root)
App.World, App.Hud, App.Panel = World, Hud, Panel

local loading = Kit.rect(screen, 0, 0, 0, 0, Theme.Dirt[3], { Name = "Loading", Size = UDim2.fromScale(1, 1), ZIndex = 50 })
Kit.gradient(loading, Theme.Sky[1], Theme.Dirt[3], 90)
local loadingText = Kit.label(loading, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 60), Text = "Loading your mine...", TextSize = 34, ZIndex = 51 })
Kit.outlined(loadingText, Theme.Ink, 3)

local function fit()
	local vp = screen.AbsoluteSize
	if vp.X < 10 then
		return
	end
	World.fit(vp, App.touch)
	local s = Hud.fit(vp)
	Panel.fit(vp / s)
end
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

-- HELPERS -----------------------------------------------------------------------------------

local function toast(text: string, color: Color3?)
	Hud.toast(text, color)
	if color == Theme.Red and App.play then
		App.play("deny")
	end
end
App.on("toast", toast)

local function floorMid(i: number): number
	return World.floorTop(i) + W.FloorHeight / 2
end

local function managerPrice(stage: string, index: number): number
	if stage == "shaft" then
		return Config.Shafts[index].ManagerCost
	elseif stage == "elevator" then
		return Config.Managers.Elevator
	end
	return Config.Managers.Warehouse
end

local function stageData(stage: string, index: number)
	local s = App.state
	if stage == "shaft" then
		return s.shafts[index]
	end
	return s[stage]
end

-- where a stage's feedback appears (world design units)
local function stagePoint(stage: string, index: number): Vector2
	if stage == "shaft" then
		return Vector2.new(W.MinerHome + 60, floorMid(index) - 40)
	elseif stage == "elevator" then
		return Vector2.new(W.ShaftLeft + W.ShaftWidth / 2, 150)
	end
	return Vector2.new(W.TransporterHome, W.GroundY - 70)
end

-- INPUT -------------------------------------------------------------------------------------

World.callbacks.onTap = function(stage: string, index: number)
	if not App.state then
		return
	end
	if App.gate and not App.gate("tap", stage, index) then
		return
	end
	local data = stageData(stage, index)
	if data and data.manager then
		local p = stagePoint(stage, index)
		Hud.popAt(World.fxLayer, p.X, p.Y, "AUTO!", Theme.Green, 22)
		return
	end
	App.request("tap", stage, index)
	App.emit("tapped", stage, index)
end

World.callbacks.onOpen = function(stage: string, index: number)
	if App.gate and not App.gate("open", stage, index) then
		return
	end
	if Panel.isOpen and Panel.stage == stage and Panel.index == index then
		Panel.close()
	else
		Panel.open(stage, index)
	end
end

World.callbacks.onHire = function(stage: string, index: number)
	if not App.state then
		return
	end
	local data = stageData(stage, index)
	if not data then
		return
	end
	if data.manager then
		Panel.open(stage, index)
		return
	end
	local price = managerPrice(stage, index)
	if App.state.money < price then
		toast("A manager costs $" .. F.short(price) .. " (need $" .. F.short(price - App.state.money) .. " more)", Theme.Red)
		return
	end
	if App.gate and not App.gate("hire", stage, index) then
		return
	end
	App.request("hire", stage, index)
end

World.callbacks.onUnlock = function(index: number)
	if not App.state then
		return
	end
	local def = Config.Shafts[index]
	if App.state.money < def.UnlockCost then
		toast("Shaft " .. index .. " costs $" .. F.short(def.UnlockCost) .. " (need $" .. F.short(def.UnlockCost - App.state.money) .. " more)", Theme.Red)
		if World.locked then
			Kit.shake(World.locked.refs.button)
		end
		return
	end
	if App.gate and not App.gate("unlock", "shaft", index) then
		return
	end
	App.request("unlock", index)
end

Hud.onJump = function(where: string)
	if where == "top" then
		World.scrollTo(0, 0)
	else
		World.scrollTo(World.height or 0, 1)
	end
end

Hud.onBottleneck = function(stage: string, index: number)
	if stage == "shaft" then
		World.scrollTo(floorMid(index), 0.5)
	else
		World.scrollTo(0, 0)
	end
	Panel.open(stage, index)
end

-- STATE ------------------------------------------------------------------------------------

local refreshQueued = false
local function queueRefresh()
	refreshQueued = true
end

local function applyEntity(msg)
	local k = msg[1]
	if k == "m" then
		local s, w = msg[2], msg[3]
		App.ents.miners[s] = App.ents.miners[s] or {}
		App.ents.miners[s][w] = { p = msg[4], t0 = msg[5], t1 = msg[6], carry = msg[7] }
	elseif k == "e" then
		if App.play and App.ents.elev.p == "idle" and msg[2] == "move" then
			App.play("chain")
		end
		App.ents.elev = { p = msg[2], t0 = msg[3], t1 = msg[4], fromY = msg[5], toY = msg[6], floor = msg[7], load = msg[8] }
	elseif k == "t" then
		App.ents.tr = { p = msg[2], t0 = msg[3], t1 = msg[4], carry = msg[5] }
	end
end

local firstFull = true
local function applyFull(snap)
	local unlockedBefore = World.unlocked or 0
	App.state = snap
	App.ents.miners = {}
	for _, ent in snap.ents do
		applyEntity(ent)
	end
	World.layout(snap)
	Hud.setMoney(snap.money, firstFull)
	queueRefresh()
	if firstFull then
		firstFull = false
		App.emit("firstFull", snap)
	end
	App.emit("full", snap, unlockedBefore)
end

-- slowest stage hint (after the tutorial)
local function updateBottleneck()
	local s = App.state
	if not s or not s.tutorial.done then
		Hud.setBottleneck(nil)
		return
	end
	local r = Panel.rates(s)
	local list = { { "shafts", r.shafts }, { "elevator", r.elevator }, { "warehouse", r.warehouse } }
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	if list[1][2] > list[2][2] * 0.8 then
		Hud.setBottleneck(nil)
		return
	end
	local key = list[1][1]
	if key == "shafts" then
		local deepest = World.unlocked or 1
		Hud.setBottleneck("Slowest: Mining \u{2192} upgrade a shaft", "shaft", deepest)
	elseif key == "elevator" then
		Hud.setBottleneck("Slowest: Elevator \u{2192} upgrade it", "elevator", 0)
	else
		Hud.setBottleneck("Slowest: Warehouse \u{2192} upgrade it", "warehouse", 0)
	end
end

local function refreshNow()
	refreshQueued = false
	if not App.state then
		return
	end
	World.refresh(App.state)
	Panel.refresh()
	updateBottleneck()
	App.emit("refreshed", App.state)
end

-- EFFECTS -----------------------------------------------------------------------------------

local chips = {}
local function rockChips(floorIndex: number, x: number, color: Color3)
	local refs = World.floors[floorIndex]
	if not refs then
		return
	end
	for k = 1, 3 do
		local c = Kit.rect(refs.frame, x, 120 + math.random(-6, 6), 8, 8, color, { Name = "Chip", ZIndex = 9, Rotation = math.random(0, 90) })
		Kit.corner(c, 2)
		local dx, dy = math.random(-46, -10), math.random(-50, -18)
		Kit.tween(c, 0.22, { Position = UDim2.fromOffset(x + dx, 120 + dy) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.22, function()
			Kit.tween(c, 0.2, { Position = UDim2.fromOffset(x + dx * 1.4, 150), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.22)
			c:Destroy()
		end)
	end
end

local function bounce(inst: GuiObject)
	local sc = inst:FindFirstChild("Bounce") or Kit.new("UIScale", { Name = "Bounce" }, inst)
	sc.Scale = 1.15
	Kit.tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

local REASONS = {
	["Not enough money"] = "Not enough money yet!",
	["Already maxed"] = "That's already maxed out!",
	["Already hired"] = "That manager is already working.",
	["Unlock the floors above first"] = "Unlock the floors above first.",
}

local depositPops = {}

local function onFx(kind: string, a, b, c, d)
	if kind == "deposit" then
		local refs = World.floors[a]
		if refs then
			-- several miners arriving together share one rising number
			local pop = depositPops[a]
			if pop and os.clock() - pop.t < 0.45 and pop.label.Parent then
				pop.amount += b
				pop.label.Text = "+" .. F.short(pop.amount)
			else
				local label = Hud.popAt(refs.frame, W.CrateX + 66, 128, "+" .. F.short(b), Config.Shafts[a].Color:Lerp(Color3.new(1, 1, 1), 0.2), 24)
				depositPops[a] = { label = label, amount = b, t = os.clock() }
			end
			bounce(refs.tag)
		end
	elseif kind == "load" then
		if b > 0 then
			Hud.popAt(World.fxLayer, W.ShaftLeft + W.ShaftWidth / 2, floorMid(a) - 70, "+" .. F.short(b), Theme.Gold, 24)
		end
	elseif kind == "unload" then
		Hud.popAt(World.fxLayer, W.PileX, W.GroundY - 90, "+" .. F.short(a), Theme.Gold, 26)
		bounce(World.pileTag)
	elseif kind == "sell" then
		Hud.popAt(World.fxLayer, 790, 180, "+$" .. F.short(a), Theme.Gold, 34)
		Hud.noteSale(a)
		Hud.flyCoins(World.screenPoint(790, 220), math.clamp(math.floor(math.log10(a + 1) * 3), 3, 12))
	elseif kind == "empty" then
		if a == "elevator" then
			toast("No ore down there yet. Tap a miner first!", Theme.PanelLight)
		else
			toast("The pile is empty. Bring ore up with the elevator!", Theme.PanelLight)
		end
	elseif kind == "busy" then
		local p = stagePoint(a, b)
		Hud.popAt(World.fxLayer, p.X, p.Y, "Working...", Color3.fromRGB(235, 235, 245), 20)
	elseif kind == "bought" then
		local def = F.upgradeDef(a, c)
		local label = def and def.Label or "Upgrade"
		if c == "workers" then
			toast("New miner hired! (" .. tostring(d) .. " miners)", Theme.Green)
		else
			toast(label .. "  Lv " .. tostring(d) .. "!", Theme.Green)
		end
	elseif kind == "hired" then
		local name = if a == "shaft" then "Shaft " .. b else (if a == "elevator" then "Elevator" else "Warehouse")
		toast(name .. " manager hired! It works on its own now.", Theme.Green)
	elseif kind == "unlocked" then
		toast("Shaft " .. a .. " \u{00B7} " .. Config.Shafts[a].Name .. " unlocked!", Theme.Gold)
		task.delay(0.1, function()
			World.scrollTo(floorMid(a), 0.55, 0.8)
		end)
	elseif kind == "deny" then
		toast(REASONS[a] or tostring(a), Theme.Red)
	elseif kind == "offline" then
		App.pendingOffline = { a, b, c }
		App.emit("offlineReady")
	end
	App.emit("fx", kind, a, b, c, d)
end

function App.showOffline()
	local o = App.pendingOffline
	if not o then
		return
	end
	App.pendingOffline = nil
	Hud.offline(o[1], o[2], o[3])
end

-- NETWORK -----------------------------------------------------------------------------------

Remotes.Sync.OnClientEvent:Connect(function(batch)
	for _, msg in batch do
		local k = msg[1]
		if k == "full" then
			applyFull(msg[2])
		elseif k == "m" or k == "e" or k == "t" then
			applyEntity(msg)
		elseif k == "n" and App.state then
			App.state.money = msg[2]
			for i, v in msg[3] do
				if App.state.shafts[i] then
					App.state.shafts[i].ore = v
				end
			end
			App.state.pile = msg[4]
			App.state.totalEarned = msg[5]
			Hud.setMoney(msg[2])
			queueRefresh()
		elseif k == "fx" then
			local ok, err = pcall(onFx, msg[2], msg[3], msg[4], msg[5], msg[6])
			if not ok then
				warn("[Mine] fx error", err)
			end
		end
	end
end)

-- FRAME ------------------------------------------------------------------------------------

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	if refreshQueued then
		refreshNow()
	end
	Hud.update(dt)
	if App.state then
		local strikes = World.draw(clock, workspace:GetServerTimeNow(), App.ents, App.state)
		local viewTop, viewBottom = World.scroll.AbsolutePosition.Y, World.scroll.AbsolutePosition.Y + World.scroll.AbsoluteSize.Y
		for _, s in strikes do
			rockChips(s[1], s[2], Config.Shafts[s[1]].Color)
			local refs = World.floors[s[1]]
			local y = refs and refs.frame.AbsolutePosition.Y
			if App.play and y and y > viewTop - 100 and y < viewBottom then
				App.play("pick")
			end
		end
	end
end)

-- START ------------------------------------------------------------------------------------

local optional = {}
for _, name in { "Cinematic", "Tutorial", "Sfx" } do
	local m = script:FindFirstChild(name)
	if m then
		local ok, mod = pcall(require, m)
		if ok then
			optional[name] = mod
			if mod.init then
				mod.init(App)
			end
		else
			warn("[Mine] could not load", name, mod)
		end
	end
end

App.on("firstFull", function(snap)
	Kit.tween(loading, 0.4, { BackgroundTransparency = 1 })
	Kit.tween(loadingText, 0.3, { TextTransparency = 1 })
	task.delay(0.45, function()
		loading:Destroy()
	end)
	if not snap.tutorial.done and optional.Tutorial then
		if snap.tutorial.step == 0 and optional.Cinematic then
			optional.Cinematic.play(App, function()
				optional.Tutorial.start(App, snap.tutorial.step)
			end)
		else
			optional.Tutorial.start(App, snap.tutorial.step)
		end
	else
		App.showOffline()
	end
end)
App.on("offlineReady", function()
	if not firstFull and App.state and (App.state.tutorial.done or not optional.Tutorial) then
		App.showOffline()
	end
end)

local function ready()
	if player:GetAttribute("MineReady") then
		App.request("ready")
	end
end
player:GetAttributeChangedSignal("MineReady"):Connect(ready)
player:GetAttributeChangedSignal("LoadStatus"):Connect(function()
	local status = player:GetAttribute("LoadStatus")
	if status and loading.Parent and status ~= "ok" then
		loadingText.Text = tostring(status)
	end
end)
ready()
