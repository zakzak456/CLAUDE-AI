-- The guided first session. Each step either asks for one action (the screen
-- darkens around that control, a ring and an arrow point at it, and only it can
-- be pressed), explains while the player watches (no darkening), or sets a goal
-- the player works toward freely. Skip is always on screen. Progress is saved on
-- the server, and a returning player resumes at the start of their section.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Mine.Config)
local F = require(ReplicatedStorage.Mine.Formulas)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Figures = require(script.Parent.Figures)

local W = Config.World
local Tutorial = {}
local App

local ui = {}
local stepConns = {}
local currentStep = 0
local running = false
local target -- function -> GuiObject?
local shadeOn = false
local renderConn

local function money(n)
	return "$" .. F.short(n)
end

function Tutorial.init(app)
	App = app
end

-- UI --------------------------------------------------------------------------------------

local function shadeButton(parent, name)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.Text = ""
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.new(0, 0, 0)
	b.BackgroundTransparency = 0.42
	b.ZIndex = 10
	b.Visible = false
	b.Parent = parent
	return b
end

local function build()
	local root = Kit.rect(App.gui, 0, 0, 0, 0, Color3.new(), { Name = "Tutorial", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10 })
	ui.root = root
	ui.shades = {}
	for i = 1, 4 do
		ui.shades[i] = shadeButton(root, "Shade" .. i)
	end
	local ring = Kit.rect(root, 0, 0, 10, 10, Color3.new(), { Name = "Ring", BackgroundTransparency = 1, ZIndex = 11, Visible = false })
	Kit.corner(ring, 16)
	ui.ringStroke = Kit.stroke(ring, Theme.Gold, 5)
	ui.ring = ring
	local arrow = Kit.label(root, { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(60, 60), Text = "\u{25BC}", TextSize = 54, TextColor3 = Theme.Gold, ZIndex = 12, Visible = false })
	Kit.outlined(arrow, Theme.Ink, 3)
	ui.arrow = arrow

	-- speech bubble with the foreman
	local bubble = Kit.rect(root, 0, 0, 480, 120, Theme.White, { Name = "Bubble", ZIndex = 13, Visible = false })
	Kit.corner(bubble, 20)
	Kit.stroke(bubble, Theme.Ink, 4)
	ui.bubbleScale = Kit.new("UIScale", {}, bubble)
	local face = Kit.rect(bubble, 12, 14, 76, 76, Color3.new(), { BackgroundTransparency = 1, ZIndex = 14 })
	Figures.portrait(face, 76, Color3.fromRGB(240, 140, 40))
	for _, d in face:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 2
		end
	end
	Kit.label(bubble, { Position = UDim2.fromOffset(8, 92), Size = UDim2.fromOffset(84, 20), Text = "FOREMAN", TextSize = 13, TextColor3 = Theme.Ink, ZIndex = 14 })
	ui.text = Kit.label(bubble, { Name = "Text", Position = UDim2.fromOffset(100, 12), Size = UDim2.fromOffset(366, 96), Text = "", TextSize = 21, TextWrapped = true, TextColor3 = Theme.Ink, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 14 })
	local nextB = Kit.button(bubble, { Name = "Next", Position = UDim2.fromOffset(330, 92), Size = UDim2.fromOffset(136, 50), BackgroundColor3 = Theme.Green, ZIndex = 15, Visible = false }, function()
		if ui.onNext then
			local fn = ui.onNext
			ui.onNext = nil
			fn()
		end
	end)
	Kit.corner(nextB, 14)
	Kit.stroke(nextB, Theme.Ink, 3)
	local nt = Kit.label(nextB, { Size = UDim2.fromScale(1, 1), Text = "GOT IT!", TextSize = 22, ZIndex = 16 })
	Kit.outlined(nt, Theme.Ink, 1.5)
	ui.next = nextB
	ui.bubble = bubble

	-- goal card (free-play steps)
	local goal = Kit.rect(root, 0, 0, 330, 120, Theme.Panel, { Name = "Goal", ZIndex = 13, Visible = false })
	Kit.corner(goal, 18)
	Kit.stroke(goal, Theme.Gold, 3)
	ui.goalScale = Kit.new("UIScale", {}, goal)
	Kit.label(goal, { Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(300, 24), Text = "GOAL", TextSize = 18, TextColor3 = Theme.Gold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 14 })
	ui.goalList = Kit.rect(goal, 14, 32, 302, 80, Color3.new(), { BackgroundTransparency = 1, ZIndex = 14 })
	Kit.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, ui.goalList)
	ui.goal = goal

	-- skip, always visible
	local skipHolder = Kit.rect(root, 0, 0, 170, 50, Color3.new(), { Name = "SkipHolder", BackgroundTransparency = 1, ZIndex = 16 })
	local skip = Kit.button(skipHolder, { Name = "Skip", Size = UDim2.fromOffset(170, 50), BackgroundColor3 = Theme.Panel, ZIndex = 16 }, function()
		Tutorial.finish(true)
	end)
	Kit.corner(skip, 14)
	Kit.stroke(skip, Theme.Ink, 3)
	local st = Kit.label(skip, { Size = UDim2.fromScale(1, 1), Text = "Skip tutorial \u{2192}", TextSize = 20, ZIndex = 17 })
	ui.skipScale = Kit.new("UIScale", {}, skipHolder)
	ui.skip = skipHolder
end

local function hideBubble()
	ui.bubble.Visible = false
	ui.next.Visible = false
	ui.onNext = nil
end

local function say(text: string, withNext: (() -> ())?)
	ui.text.Text = text
	ui.bubble.Visible = true
	ui.next.Visible = withNext ~= nil
	ui.onNext = withNext
	local bounds = TextService:GetTextSize(text, 21, ui.text.Font, Vector2.new(366, 1000))
	local textH = math.max(76, bounds.Y + 8)
	ui.text.Size = UDim2.fromOffset(366, textH)
	local h = math.max(120, textH + 24) + (if withNext then 58 else 0)
	ui.bubble.Size = UDim2.fromOffset(480, h)
	ui.next.Position = UDim2.fromOffset(330, h - 62)
	ui.bubbleScale.Scale = 0.6 * (App.Hud.scale or 1)
	Kit.tween(ui.bubbleScale, 0.22, { Scale = App.Hud.scale or 1 }, Enum.EasingStyle.Back)
end

local function setGoals(lines)
	for _, c in ui.goalList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if not lines then
		ui.goal.Visible = false
		return
	end
	ui.goal.Visible = true
	for i, line in lines do
		local l = Kit.label(ui.goalList, { LayoutOrder = i, Size = UDim2.fromOffset(302, 24), Text = (if line.done then "\u{2713} " else "\u{2022} ") .. line.text, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if line.done then Theme.Green else Theme.White, ZIndex = 14 })
		if line.progress and not line.done then
			local track = Kit.rect(ui.goalList, 0, 0, 290, 12, Color3.fromRGB(20, 22, 32), { LayoutOrder = i, ZIndex = 14 })
			Kit.corner(track, 6)
			local fill = Kit.rect(track, 0, 0, math.max(8, 290 * math.clamp(line.progress, 0, 1)), 12, Theme.Gold, { ZIndex = 15 })
			Kit.corner(fill, 6)
		end
	end
	ui.goal.Size = UDim2.fromOffset(330, 40 + #lines * 28 + (if lines[1] and lines[1].progress and not lines[1].done then 16 else 0))
end

-- Layout every frame: the hole follows its target even while the mine scrolls.
local function layout()
	local root = ui.root
	local origin = root.AbsolutePosition
	local size = root.AbsoluteSize
	local s = App.Hud.scale or 1
	ui.skipScale.Scale = s
	ui.skip.Position = UDim2.fromOffset(12, 64 * math.max(1, s * 0.9))
	ui.goalScale.Scale = s
	ui.goal.Position = UDim2.fromOffset(12, 64 * math.max(1, s * 0.9) + 56 * s)
	local inst = target and target()
	local hole
	if inst and inst.Parent and inst.AbsoluteSize.X > 0 then
		local pad = 10
		local p = inst.AbsolutePosition - origin
		local sz = inst.AbsoluteSize
		hole = { x = math.floor(p.X - pad), y = math.floor(p.Y - pad), w = math.ceil(sz.X + pad * 2), h = math.ceil(sz.Y + pad * 2) }
	end
	local sh = ui.shades
	if shadeOn then
		if hole then
			local x, y, w, h = hole.x, hole.y, hole.w, hole.h
			local rects = {
				{ 0, 0, size.X, math.max(0, y) },
				{ 0, y + h, size.X, math.max(0, size.Y - (y + h)) },
				{ 0, y, math.max(0, x), h },
				{ x + w, y, math.max(0, size.X - (x + w)), h },
			}
			for i, r in rects do
				sh[i].Visible = true
				sh[i].Position = UDim2.fromOffset(r[1], r[2])
				sh[i].Size = UDim2.fromOffset(r[3], r[4])
			end
		else
			sh[1].Visible = true
			sh[1].Position = UDim2.fromOffset(0, 0)
			sh[1].Size = UDim2.fromOffset(size.X, size.Y)
			for i = 2, 4 do
				sh[i].Visible = false
			end
		end
	else
		for i = 1, 4 do
			sh[i].Visible = false
		end
	end
	local t = os.clock()
	if hole then
		ui.ring.Visible = true
		ui.ring.Position = UDim2.fromOffset(hole.x, hole.y)
		ui.ring.Size = UDim2.fromOffset(hole.w, hole.h)
		ui.ringStroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(t * 6))
		ui.arrow.Visible = true
		local bob = math.sin(t * 6) * 8
		local above = hole.y > 90
		ui.arrow.Text = if above then "\u{25BC}" else "\u{25B2}"
		ui.arrow.AnchorPoint = if above then Vector2.new(0.5, 1) else Vector2.new(0.5, 0)
		ui.arrow.Position = UDim2.fromOffset(hole.x + hole.w / 2, if above then hole.y - 4 + bob else hole.y + hole.h + 4 + bob)
	else
		ui.ring.Visible = false
		ui.arrow.Visible = false
	end
	-- bubble: below the hole when there is room, else above; centred otherwise
	if ui.bubble.Visible then
		local bw, bh = ui.bubble.AbsoluteSize.X, ui.bubble.AbsoluteSize.Y
		local x, y
		if hole and hole.x + hole.w / 2 > size.X * 0.62 and hole.x - bw - 30 > 0 then
			-- target on the right (e.g. the upgrade panel): sit to its left
			x = hole.x - bw - 30
			y = hole.y + hole.h / 2 - bh / 2
		elseif hole then
			x = hole.x + hole.w / 2 - bw / 2
			if hole.y + hole.h + 70 + bh < size.Y then
				y = hole.y + hole.h + 64
			elseif hole.y - 70 - bh > 0 then
				y = hole.y - 64 - bh
			else
				y = size.Y - bh - 16
				x = 16
			end
		else
			x = size.X / 2 - bw / 2
			y = size.Y - bh - 24
		end
		x = math.clamp(x, 12, math.max(12, size.X - bw - 12))
		y = math.clamp(y, 12, math.max(12, size.Y - bh - 12))
		ui.bubble.Position = UDim2.fromOffset(x, y)
	end
end

-- STEPS -----------------------------------------------------------------------------------

local function on(name, fn)
	table.insert(stepConns, App.on(name, fn))
end

local function clearStep()
	for _, c in stepConns do
		c()
	end
	stepConns = {}
	target = nil
	shadeOn = false
	hideBubble()
	setGoals(nil)
end

local function floorMid(i)
	return W.SurfaceHeight + (i - 1) * W.FloorHeight + W.FloorHeight / 2
end

local function S()
	return App.state
end

local goStep

local function hiredAll()
	local s = S()
	return s.elevator.manager and s.warehouse.manager
end

local STEPS = {}

STEPS[1] = function()
	App.Panel.close()
	App.World.scrollTo(floorMid(1), 0.62)
	target = function()
		return App.World.floors[1] and App.World.floors[1].tap
	end
	shadeOn = true
	say("Welcome to your mine! Tap the tunnel to send your miner digging.")
	on("tapped", function(stage, i)
		if stage == "shaft" and i == 1 then
			goStep(2)
		end
	end)
end

STEPS[2] = function()
	target = function()
		return App.World.floors[1] and App.World.floors[1].tag
	end
	say("He digs copper ore and brings it back to the crate...")
	on("fx", function(kind, s)
		if kind == "deposit" and s == 1 then
			goStep(3)
		end
	end)
end

STEPS[3] = function()
	App.World.scrollTo(0, 0)
	target = function()
		return App.World.elevTap
	end
	shadeOn = true
	say("Ore in the crate! Tap the elevator to bring it up.")
	on("tapped", function(stage)
		if stage == "elevator" then
			goStep(4)
		end
	end)
	on("fx", function(kind)
		if kind == "empty" then
			goStep(1)
		end
	end)
end

STEPS[4] = function()
	target = function()
		return App.World.pileTag
	end
	say("Up it goes! The elevator drops the ore on the pile.")
	on("fx", function(kind)
		if kind == "unload" then
			goStep(5)
		end
	end)
end

STEPS[5] = function()
	App.World.scrollTo(0, 0)
	target = function()
		return App.World.whTap
	end
	shadeOn = true
	say("Now tap the warehouse worker. He carries the pile inside.")
	on("tapped", function(stage)
		if stage == "warehouse" then
			goStep(6)
		end
	end)
end

STEPS[6] = function()
	target = function()
		return App.World.warehouse
	end
	say("Ore only turns into money when it reaches the warehouse...")
	on("fx", function(kind)
		if kind == "sell" then
			task.wait(0.8)
			goStep(7)
		end
	end)
end

STEPS[7] = function()
	target = function()
		return App.Hud.pill
	end
	shadeOn = true
	say("Cha-ching! Your first money! Every trip through the whole mine pays out here.", function()
		goStep(8)
	end)
end

STEPS[8] = function()
	App.World.scrollTo(floorMid(1), 0.62)
	target = function()
		return App.World.floors[1] and App.World.floors[1].badge.button
	end
	shadeOn = true
	say("Let's make it faster. Tap the shaft's level button to see its upgrades.")
	on("panelOpened", function(stage, i)
		if stage == "shaft" and i == 1 then
			goStep(9)
		end
	end)
end

STEPS[9] = function()
	local def = F.upgradeDef("shaft", "pick")
	local price = F.price(def, S().shafts[1].pick, 1)
	if not App.Panel.isOpen or App.Panel.stage ~= "shaft" or App.Panel.index ~= 1 then
		App.Panel.open("shaft", 1)
	end
	if not price or S().money < price then
		goStep(10)
		return
	end
	target = function()
		return App.Panel.isOpen and App.Panel.rows and App.Panel.rows.pick and App.Panel.rows.pick.button
	end
	shadeOn = true
	say("Buy Pickaxes: your miner carries more ore on every trip.")
	on("fx", function(kind, stage, _, id)
		if kind == "bought" and stage == "shaft" then
			task.wait(0.5)
			goStep(10)
		end
	end)
end

STEPS[10] = function()
	local price = Config.Shafts[1].ManagerCost
	if S().shafts[1].manager then
		goStep(12)
		return
	end
	if S().money >= price then
		goStep(11)
		return
	end
	App.Panel.close()
	say("Tapping gets tiring! Managers work for you. Run the mine a few more times to earn " .. money(price) .. ".", function()
		hideBubble()
	end)
	local function update()
		local m = S().money
		setGoals({ { text = "Earn " .. money(price) .. " for a manager  (" .. money(math.min(m, price)) .. ")", progress = m / price } })
		if m >= price then
			goStep(11)
		end
	end
	update()
	on("refreshed", update)
end

STEPS[11] = function()
	if S().shafts[1].manager then
		goStep(12)
		return
	end
	App.Panel.close()
	App.World.scrollTo(floorMid(1), 0.62)
	target = function()
		return App.World.floors[1] and App.World.floors[1].manager.button
	end
	shadeOn = true
	say("You can afford a manager! Tap here to hire one for this shaft.")
	on("fx", function(kind, stage, i)
		if kind == "hired" and stage == "shaft" and i == 1 then
			task.wait(1.2)
			goStep(12)
		end
	end)
	on("refreshed", function()
		if S().money < Config.Shafts[1].ManagerCost and not S().shafts[1].manager then
			goStep(10)
		end
	end)
end

STEPS[12] = function()
	App.World.scrollTo(floorMid(1), 0.62)
	target = function()
		return App.World.floors[1] and App.World.floors[1].tag
	end
	say("Look! Your miner keeps digging by himself now. But nobody runs the elevator, so ore piles up in the crate. Each stage needs its own manager.", function()
		goStep(13)
	end)
end

STEPS[13] = function()
	local cost = Config.Shafts[2].UnlockCost
	local shown = false
	local function update()
		local s = S()
		if s.shafts[2].unlocked then
			goStep(14)
			return
		end
		local m = s.money
		local lines = {
			{ text = "Hire the Elevator manager (" .. money(Config.Managers.Elevator) .. ")", done = s.elevator.manager },
			{ text = "Hire the Warehouse manager (" .. money(Config.Managers.Warehouse) .. ")", done = s.warehouse.manager },
			{ text = "Unlock Shaft 2 (" .. money(cost) .. ")", done = false, progress = if hiredAll() then m / cost else nil },
		}
		setGoals(lines)
		-- point at whichever goal is affordable right now (no darkening: free play)
		if not s.elevator.manager and m >= Config.Managers.Elevator then
			target = function()
				return App.World.elevManager.button
			end
		elseif s.elevator.manager and not s.warehouse.manager and m >= Config.Managers.Warehouse then
			target = function()
				return App.World.whManager.button
			end
		elseif m >= cost and App.World.locked and App.World.locked.index == 2 then
			target = function()
				return App.World.locked and App.World.locked.refs.button
			end
		else
			target = nil
		end
	end
	if not shown then
		shown = true
		say("Hire managers for the elevator and warehouse, then open Shaft 2. Deeper ore is worth way more!", function()
			hideBubble()
		end)
	end
	update()
	on("refreshed", update)
end

STEPS[14] = function()
	App.World.scrollTo(floorMid(2), 0.55, 0.8)
	target = function()
		return App.World.floors[2] and App.World.floors[2].tap
	end
	say("Shaft 2 is open, and every piece of iron is worth 10x more than copper! Upgrade, hire and dig deeper. Build your mining empire!", function()
		Tutorial.finish(false)
	end)
end

-- Where a saved step resumes (the start of its section).
local RESUME = { 1, 1, 1, 1, 1, 1, 1, 8, 8, 10, 10, 12, 13, 14 }

goStep = function(n: number)
	if not running then
		return
	end
	clearStep()
	currentStep = n
	App.request("tut", n)
	App.emit("tutorialStep", n)
	local fn = STEPS[n]
	if fn then
		task.spawn(fn)
	end
end

function Tutorial.start(app, saved: number?)
	App = App or app
	if running then
		return
	end
	if not ui.root then
		build()
	end
	running = true
	ui.root.Visible = true
	renderConn = RunService.RenderStepped:Connect(layout)
	local step = RESUME[math.clamp(saved or 1, 1, #RESUME)] or 1
	if (saved or 0) <= 0 then
		step = 1
	end
	goStep(step)
end

function Tutorial.finish(skipped: boolean)
	if not running then
		return
	end
	clearStep()
	running = false
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	ui.root.Visible = false
	App.request("tutdone")
	if App.state then
		App.state.tutorial.done = true
	end
	App.emit("tutorialDone", skipped)
	App.emit("toast", if skipped then "Tutorial skipped. Have fun!" else "Tutorial complete! The mine is yours.", Theme.Green)
	App.showOffline()
end

function Tutorial.isRunning()
	return running
end

function Tutorial.step()
	return currentStep
end

return Tutorial
