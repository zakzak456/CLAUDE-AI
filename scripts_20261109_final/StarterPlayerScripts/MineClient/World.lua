-- The 2D mine: a side-view cross-section in a vertical ScrollingFrame. The
-- surface (sky, elevator tower, ore pile, warehouse) sits on top of stacked
-- floors; the next locked floor shows its unlock price. Every stage has a big tap
-- area, a level badge (opens upgrades) and a manager slot. World coordinates are
-- design units (1000 wide); a UIScale fits them to the screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Mine")
local Config = require(Shared:WaitForChild("Config"))
local F = require(Shared:WaitForChild("Formulas"))
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Figures = require(script.Parent.Figures)

local W = Config.World
local World = {}
World.floors = {} -- [shaft] = refs
World.callbacks = {} -- onTap(stage, i), onOpen(stage, i), onHire(stage, i), onUnlock(i)

local FEET = 160 -- miners stand on the tunnel floor (floor-local y)
local CAGE_H, CAGE_W = 96, 112

local function fire(name, ...)
	local cb = World.callbacks[name]
	if cb then
		cb(...)
	end
end

local function dirtFor(i: number): Color3
	return Theme.Dirt[math.clamp(i, 1, #Theme.Dirt)]
end

-- A level badge button: "SHAFT 1 / Lv 3" with an upgrade arrow.
local function badge(parent, x, y, title, color, onClick)
	local b = Kit.button(parent, { Name = "Badge", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(170, 40), BackgroundColor3 = Theme.Panel, ZIndex = 15 }, onClick)
	Kit.corner(b, 12)
	Kit.stroke(b, Theme.Ink, 2.5)
	local t = Kit.label(b, { Name = "Title", Position = UDim2.fromOffset(10, 2), Size = UDim2.fromOffset(110, 20), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Text = title, TextColor3 = color, ZIndex = 16 })
	local lv = Kit.label(b, { Name = "Level", Position = UDim2.fromOffset(10, 18), Size = UDim2.fromOffset(110, 20), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = "Lv 1", ZIndex = 16 })
	local up = Kit.rect(b, 126, 6, 36, 28, Theme.Green, { Name = "Up", ZIndex = 16 })
	Kit.corner(up, 9)
	Kit.label(up, { Size = UDim2.fromScale(1, 1), Text = "\u{25B2}", TextSize = 18, ZIndex = 17 })
	return { button = b, title = t, level = lv, up = up }
end

-- A manager slot: "+ hire" or the manager's portrait with an AUTO tag.
local function managerSlot(parent, x, y, onClick)
	local b = Kit.button(parent, { Name = "Manager", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = Color3.fromRGB(90, 96, 116), ZIndex = 15 }, onClick)
	Kit.corner(b)
	Kit.stroke(b, Theme.Ink, 2.5)
	local plus = Kit.label(b, { Name = "Plus", Size = UDim2.fromOffset(56, 40), Text = "+", TextSize = 34, ZIndex = 16 })
	local cost = Kit.label(b, { Name = "Cost", Position = UDim2.fromOffset(-22, 50), Size = UDim2.fromOffset(100, 20), Text = "", TextSize = 14, ZIndex = 16 })
	Kit.outlined(cost)
	local portraitHolder = Kit.rect(b, 0, 0, 56, 56, Color3.new(), { Name = "PortraitHolder", BackgroundTransparency = 1, ZIndex = 15, Visible = false })
	local auto = Kit.rect(b, 2, 46, 52, 18, Theme.Green, { Name = "Auto", ZIndex = 18, Visible = false })
	Kit.corner(auto, 6)
	Kit.stroke(auto, Theme.Ink, 2)
	Kit.label(auto, { Size = UDim2.fromScale(1, 1), Text = "AUTO", TextSize = 13, ZIndex = 19 })
	return { button = b, plus = plus, cost = cost, holder = portraitHolder, auto = auto, hired = nil }
end

local function setManager(slot, hired: boolean, price: number?, money: number, shirt: Color3)
	if slot.hired ~= hired then
		slot.hired = hired
		slot.plus.Visible = not hired
		slot.holder.Visible = hired
		slot.auto.Visible = hired
		if hired and not slot.portrait then
			slot.portrait = Figures.portrait(slot.holder, 56, shirt)
		end
		slot.button.BackgroundColor3 = if hired then Theme.Gold else Color3.fromRGB(90, 96, 116)
	end
	if not hired then
		local can = price ~= nil and money >= price
		slot.cost.Text = if price then "$" .. F.short(price) else ""
		slot.cost.TextColor3 = if can then Theme.Gold else Color3.fromRGB(220, 220, 230)
		slot.button.BackgroundColor3 = if can then Theme.Green else Color3.fromRGB(90, 96, 116)
	else
		slot.cost.Text = ""
	end
end

-- An ore heap that grows with the amount it holds.
local function heap(parent, x, baseY, color)
	local h = Kit.rect(parent, x, baseY, 10, 10, color, { Name = "Heap", AnchorPoint = Vector2.new(0.5, 1), ZIndex = 6 })
	Kit.corner(h, 20)
	Kit.stroke(h, color:Lerp(Color3.new(0, 0, 0), 0.35), 2)
	local shine = Kit.rect(h, 0, 0, 10, 4, Color3.new(1, 1, 1), { ZIndex = 7, BackgroundTransparency = 0.55, Position = UDim2.fromScale(0.25, 0.18), Size = UDim2.fromScale(0.3, 0.16) })
	Kit.corner(shine)
	return h
end

local function sizeHeap(h: Frame, amount: number, maxW: number)
	if amount <= 0 then
		h.Visible = false
		return
	end
	h.Visible = true
	local k = math.clamp(math.log10(amount + 1) / 5, 0.15, 1)
	h.Size = UDim2.fromOffset(maxW * (0.35 + 0.65 * k), 10 + 34 * k)
end

local function amountTag(parent, x, y)
	local t = Kit.rect(parent, x, y, 96, 26, Theme.Panel, { Name = "Amount", AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 14 })
	Kit.corner(t, 9)
	Kit.stroke(t, Theme.Ink, 2)
	local l = Kit.label(t, { Size = UDim2.fromScale(1, 1), Text = "0", TextSize = 17, ZIndex = 15 })
	return t, l
end

local function warnTag(parent, x, y, text)
	local t = Kit.rect(parent, x, y, 150, 24, Color3.fromRGB(255, 140, 40), { Name = "Warn", AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 14, Visible = false })
	Kit.corner(t, 8)
	Kit.stroke(t, Theme.Ink, 2)
	Kit.label(t, { Size = UDim2.fromScale(1, 1), Text = text, TextSize = 13, ZIndex = 15 })
	return t
end

local function tapHint(parent)
	local h = Kit.rect(parent, 0, 0, 74, 30, Theme.White, { Name = "TapHint", AnchorPoint = Vector2.new(0.5, 1), ZIndex = 20, Visible = false })
	Kit.corner(h, 10)
	Kit.stroke(h, Theme.Ink, 2.5)
	Kit.label(h, { Size = UDim2.fromScale(1, 1), Text = "TAP!", TextSize = 18, TextColor3 = Theme.Ink, ZIndex = 21 })
	local tail = Kit.rect(h, 30, 24, 12, 12, Theme.White, { Rotation = 45, ZIndex = 20 })
	return h
end

-- BUILD -------------------------------------------------------------------------------------

function World.build(gui: ScreenGui)
	local bg = Kit.rect(gui, 0, 0, 0, 0, Theme.Dirt[4], { Name = "Backdrop", Size = UDim2.fromScale(1, 1), ZIndex = 0 })
	local scroll = Kit.new("ScrollingFrame", {
		Name = "MineView", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 8, ScrollBarImageColor3 = Color3.fromRGB(255, 220, 150),
		CanvasSize = UDim2.new(1, 0, 0, 2000), ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, ZIndex = 1,
		ScrollingEnabled = true, Active = true,
	}, gui)
	local world = Kit.rect(scroll, 0, 0, W.Width, 2000, Theme.Dirt[1], { Name = "World", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), ZIndex = 1 })
	world.ClipsDescendants = false -- wide screens see the sky, ground and rock carry on past the edges
	local scale = Kit.new("UIScale", { Scale = 1 }, world)
	World.scroll, World.world, World.uiScale, World.backdrop = scroll, world, scale, bg

	-- sky and surface
	local skyExt = Kit.rect(world, -1200, 0, W.Width + 2400, W.GroundY, Color3.new(1, 1, 1), { Name = "SkyExt", ZIndex = 1 })
	Kit.gradient(skyExt, Theme.Sky[1], Theme.Sky[2], 90)
	local sky = Kit.rect(world, 0, 0, W.Width, W.GroundY, Color3.new(1, 1, 1), { Name = "Sky", ZIndex = 1, BackgroundTransparency = 1 })
	local sun = Kit.rect(sky, 560, 70, 70, 70, Color3.fromRGB(255, 236, 120), { Name = "Sun", ZIndex = 1 })
	Kit.corner(sun)
	Kit.stroke(sun, Color3.fromRGB(255, 210, 90), 6, 0.4)
	World.clouds = {}
	for i, c in { { 120, 40, 1 }, { 430, 110, 0.8 }, { 820, 54, 1.1 } } do
		local cloud = Kit.rect(sky, c[1], c[2], 120 * c[3], 34 * c[3], Theme.White, { Name = "Cloud", ZIndex = 1, BackgroundTransparency = 0.05 })
		Kit.corner(cloud)
		local puff = Kit.rect(cloud, 24 * c[3], -16 * c[3], 54 * c[3], 40 * c[3], Theme.White, { ZIndex = 1 })
		Kit.corner(puff)
		table.insert(World.clouds, { inst = cloud, x = c[1], speed = 6 + i * 3 })
	end
	for i, h in { { -460, 200, 420, 150 }, { -60, 190, 360, 160 }, { 250, 210, 420, 150 }, { 640, 200, 460, 170 }, { 1060, 196, 440, 160 } } do
		local hill = Kit.rect(world, h[1], h[2], h[3], h[4], Theme.Hill[(i % 2) + 1], { Name = "Hill", ZIndex = 1 })
		Kit.corner(hill)
	end
	local ground = Kit.rect(world, -1200, W.GroundY, W.Width + 2400, W.SurfaceHeight - W.GroundY, Theme.Dirt[1], { Name = "Ground", ZIndex = 2 })
	local grass = Kit.rect(world, -1200, W.GroundY - 6, W.Width + 2400, 16, Theme.Grass, { Name = "Grass", ZIndex = 3 })
	Kit.rect(grass, 0, 12, W.Width + 2400, 4, Theme.GrassDark, { ZIndex = 3 })
	for i = 0, 18 do
		local tuft = Kit.rect(world, 20 + i * 54, W.GroundY - 12, 10, 10, Theme.Grass, { ZIndex = 3, Rotation = 45 })
		tuft.BorderSizePixel = 0
	end

	-- warehouse
	local wh = Kit.rect(world, 740, 128, 245, W.GroundY - 128, Theme.Brick, { Name = "Warehouse", ZIndex = 2 })
	Kit.stroke(wh, Theme.Ink, 3)
	for row = 0, 5 do
		Kit.rect(wh, 0, 18 + row * 24, 245, 2, Theme.Brick:Lerp(Color3.new(0, 0, 0), 0.2), { ZIndex = 2 })
	end
	local roof = Kit.rect(world, 724, 100, 277, 40, Theme.Roof, { Name = "Roof", ZIndex = 3 })
	Kit.corner(roof, 10)
	Kit.stroke(roof, Theme.Ink, 3)
	local sign = Kit.rect(world, 790, 108, 160, 26, Theme.Wood, { Name = "Sign", ZIndex = 4 })
	Kit.corner(sign, 6)
	Kit.stroke(sign, Theme.Ink, 2)
	Kit.label(sign, { Size = UDim2.fromScale(1, 1), Text = "WAREHOUSE", TextSize = 17, ZIndex = 5 })
	local door = Kit.rect(world, 752, 196, 62, W.GroundY - 196, Color3.fromRGB(82, 52, 34), { Name = "Door", ZIndex = 3 })
	Kit.corner(door, 8)
	Kit.stroke(door, Theme.Ink, 3)
	local window = Kit.rect(world, 870, 176, 70, 50, Color3.fromRGB(180, 230, 255), { Name = "Window", ZIndex = 3 })
	Kit.corner(window, 6)
	Kit.stroke(window, Theme.Ink, 3)
	local coin = Kit.rect(world, 905, 236, 34, 34, Theme.Gold, { Name = "CoinSign", ZIndex = 3 })
	Kit.corner(coin)
	Kit.stroke(coin, Theme.Ink, 2)
	Kit.label(coin, { Size = UDim2.fromScale(1, 1), Text = "$", TextSize = 22, TextColor3 = Theme.Ink, ZIndex = 4 })
	World.warehouse = wh

	-- elevator tower
	local tower = Kit.rect(world, W.ShaftLeft, 150, W.ShaftWidth, W.GroundY - 150, Color3.new(), { Name = "Tower", BackgroundTransparency = 1, ZIndex = 3 })
	for _, x in { 0, W.ShaftWidth - 12 } do
		Kit.rect(tower, x, 0, 12, W.GroundY - 150, Theme.WoodDark, { ZIndex = 3 })
	end
	for i = 0, 2 do
		Kit.rect(tower, 6, 20 + i * 40, W.ShaftWidth - 12, 6, Theme.Wood, { ZIndex = 3, Rotation = if i % 2 == 0 then 18 else -18 })
	end
	local wheel = Kit.rect(world, W.ShaftLeft + W.ShaftWidth / 2 - 32, 112, 64, 64, Color3.fromRGB(80, 80, 92), { Name = "Wheel", ZIndex = 4 })
	Kit.corner(wheel)
	Kit.stroke(wheel, Theme.Ink, 4)
	for r = 0, 2 do
		Kit.rect(wheel, 30, 4, 4, 56, Color3.fromRGB(150, 150, 165), { Rotation = r * 60, ZIndex = 4 })
	end
	World.wheel = wheel

	-- the shaft column (height set in layout)
	local shaft = Kit.rect(world, W.ShaftLeft, W.GroundY, W.ShaftWidth, 100, Theme.Shaft, { Name = "Shaft", ZIndex = 3 })
	Kit.stroke(shaft, Theme.Ink, 3)
	World.shaftColumn = shaft
	World.rails = {}

	-- the elevator cage
	local cage = Kit.rect(world, W.ShaftLeft + (W.ShaftWidth - CAGE_W) / 2, 0, CAGE_W, CAGE_H, Color3.fromRGB(40, 34, 32), { Name = "Cage", ZIndex = 6, BackgroundTransparency = 0.25 })
	Kit.corner(cage, 6)
	Kit.stroke(cage, Theme.Cage, 5)
	Kit.rect(cage, 0, 0, CAGE_W, 10, Theme.Cage, { ZIndex = 9 })
	Kit.rect(cage, 0, CAGE_H - 10, CAGE_W, 10, Theme.Cage, { ZIndex = 9 })
	for _, x in { 34, 74 } do
		Kit.rect(cage, x, 0, 4, CAGE_H, Theme.Cage, { ZIndex = 9, BackgroundTransparency = 0.2 })
	end
	local cable = Kit.rect(world, W.ShaftLeft + W.ShaftWidth / 2 - 2, 144, 4, 10, Color3.fromRGB(30, 30, 34), { Name = "Cable", ZIndex = 5 })
	World.cage, World.cable = cage, cable
	World.operator = Figures.worker(cage, { name = "Operator", shirt = Color3.fromRGB(70, 150, 245), pants = Color3.fromRGB(50, 60, 90), helmet = Color3.fromRGB(255, 120, 60) })
	World.operator.root.ZIndex = 7
	World.cageHeap = heap(cage, 86, CAGE_H - 10, Theme.Gold)
	World.cageHeap.ZIndex = 8
	World.cageTag, World.cageLabel = amountTag(world, 0, 0)

	-- elevator controls and the surface pile
	World.elevBadge = badge(world, 190, 112, "ELEVATOR", Color3.fromRGB(150, 210, 255), function()
		fire("onOpen", "elevator", 0)
	end)
	World.elevManager = managerSlot(world, 366, 104, function()
		fire("onHire", "elevator", 0)
	end)
	World.elevManager.button.Name = "ElevatorManager"
	World.elevBadge.button.Name = "ElevatorBadge"
	World.elevTap = Kit.button(world, { Name = "ElevatorTap", Position = UDim2.fromOffset(W.ShaftLeft - 10, 120), Size = UDim2.fromOffset(W.ShaftWidth + 20, 180), BackgroundTransparency = 1, ZIndex = 12 }, function()
		fire("onTap", "elevator", 0)
	end)
	World.elevHint = tapHint(world)
	World.pileHeap = heap(world, W.PileX, W.GroundY + 4, Theme.Gold)
	World.pileHeap.ZIndex = 4
	World.pileTag, World.pileLabel = amountTag(world, W.PileX, W.GroundY - 62)
	World.pileWarn = warnTag(world, W.PileX + 20, W.GroundY - 94, "Piling up!")

	-- transporter and warehouse controls
	World.transporter = Figures.worker(world, { name = "Transporter", shirt = Color3.fromRGB(80, 190, 100), pants = Color3.fromRGB(60, 70, 110), helmet = Color3.fromRGB(240, 240, 250), cart = true })
	World.transporter.root.ZIndex = 6
	World.whBadge = badge(world, 466, 122, "WAREHOUSE", Color3.fromRGB(255, 210, 120), function()
		fire("onOpen", "warehouse", 0)
	end)
	World.whManager = managerSlot(world, 642, 114, function()
		fire("onHire", "warehouse", 0)
	end)
	World.whManager.button.Name = "WarehouseManager"
	World.whBadge.button.Name = "WarehouseBadge"
	World.whTap = Kit.button(world, { Name = "WarehouseTap", Position = UDim2.fromOffset(300, 214), Size = UDim2.fromOffset(690, 90), BackgroundTransparency = 1, ZIndex = 11 }, function()
		fire("onTap", "warehouse", 0)
	end)
	World.whHint = tapHint(world)

	-- floors are added by layout()
	World.floorsFolder = Kit.rect(world, 0, W.SurfaceHeight, W.Width, 10, Color3.new(), { Name = "Floors", BackgroundTransparency = 1, ZIndex = 2 })
	World.fxLayer = Kit.rect(world, 0, 0, W.Width, 10, Color3.new(), { Name = "Fx", BackgroundTransparency = 1, ZIndex = 30, Size = UDim2.fromScale(1, 1) })
	return World
end

-- FLOORS ------------------------------------------------------------------------------------

local function buildFloor(i: number)
	local def = Config.Shafts[i]
	local y = (i - 1) * W.FloorHeight
	local f = Kit.rect(World.floorsFolder, 0, y, W.Width, W.FloorHeight, dirtFor(i), { Name = "Floor" .. i, ZIndex = 2 })
	Kit.rect(f, -1200, 0, W.Width + 2400, W.FloorHeight, dirtFor(i), { Name = "Ext", ZIndex = 1 })
	-- speckles in the rock
	for k = 1, 10 do
		local sx = ((i * 97 + k * 131) % 980)
		local sy = ((i * 53 + k * 71) % 170)
		local speck = Kit.rect(f, sx, sy, 10 + k % 3 * 4, 6 + k % 2 * 4, dirtFor(i):Lerp(Color3.new(0, 0, 0), 0.18), { ZIndex = 2 })
		Kit.corner(speck, 4)
	end
	local tunnel = Kit.rect(f, 176, 30, 790, 136, Theme.Tunnel, { Name = "Tunnel", ZIndex = 3 })
	Kit.corner(tunnel, 14)
	Kit.gradient(tunnel, Theme.Tunnel, Theme.TunnelShade, 90)
	Kit.rect(f, 176, 158, 790, 12, Theme.Plank, { Name = "Plank", ZIndex = 4 })
	Kit.rect(f, 176, 30, 790, 10, Theme.Beam, { Name = "TopBeam", ZIndex = 4 })
	for _, bx in { 480, 700 } do
		Kit.rect(f, bx, 30, 12, 136, Theme.Beam, { ZIndex = 3 })
		local lamp = Kit.rect(f, bx + 36, 40, 14, 14, Color3.fromRGB(255, 236, 150), { ZIndex = 4 })
		Kit.corner(lamp)
		Kit.stroke(lamp, Color3.fromRGB(255, 200, 80), 4, 0.5)
	end
	-- rock face with this shaft's ore
	local face = Kit.rect(f, 880, 30, 86, 136, Theme.Rock, { Name = "Face", ZIndex = 4 })
	Kit.corner(face, 14)
	local chunks = {}
	for k, p in { { 10, 14 }, { 44, 30 }, { 18, 58 }, { 52, 76 }, { 14, 98 }, { 46, 108 } } do
		local c = Kit.rect(face, p[1], p[2], 22, 18, def.Color, { ZIndex = 5, Rotation = (k * 23) % 40 - 20 })
		Kit.corner(c, 5)
		Kit.stroke(c, def.Color:Lerp(Color3.new(0, 0, 0), 0.4), 2)
		chunks[k] = c
	end
	-- the crate the miners fill
	local crate = Kit.rect(f, W.CrateX - 44, 116, 88, 44, Theme.Wood, { Name = "Crate", ZIndex = 5 })
	Kit.corner(crate, 6)
	Kit.stroke(crate, Theme.WoodDark, 3)
	Kit.rect(crate, 0, 20, 88, 4, Theme.WoodDark, { ZIndex = 5 })
	local crateHeap = heap(f, W.CrateX, 120, def.Color)
	crateHeap.ZIndex = 4
	local tag, label = amountTag(f, W.CrateX, 92)
	local warn = warnTag(f, W.CrateX + 168, 128, "Piling up!")
	-- dock where the elevator stops
	Kit.rect(f, W.ShaftLeft + W.ShaftWidth - 6, 158, 24, 12, Theme.Rail, { Name = "Dock", ZIndex = 4 })
	local refs = { frame = f, chunks = chunks, crateHeap = crateHeap, tag = tag, label = label, warn = warn, miners = {}, def = def }
	refs.tap = Kit.button(f, { Name = "Tap", Position = UDim2.fromOffset(176, 30), Size = UDim2.fromOffset(790, 140), BackgroundTransparency = 1, ZIndex = 12 }, function()
		fire("onTap", "shaft", i)
	end)
	refs.badge = badge(f, 184, 36, "SHAFT " .. i .. " \u{00B7} " .. string.upper(def.Name), def.Color:Lerp(Color3.new(1, 1, 1), 0.3), function()
		fire("onOpen", "shaft", i)
	end)
	refs.badge.button.Size = UDim2.fromOffset(200, 40)
	refs.badge.title.Size = UDim2.fromOffset(150, 20)
	refs.badge.up.Position = UDim2.fromOffset(156, 6)
	refs.manager = managerSlot(f, 392, 32, function()
		fire("onHire", "shaft", i)
	end)
	refs.hint = tapHint(f)
	return refs
end

local function buildLocked(i: number)
	local def = Config.Shafts[i]
	local y = (i - 1) * W.FloorHeight
	local f = Kit.rect(World.floorsFolder, 0, y, W.Width, W.FloorHeight, Theme.RockDark, { Name = "Locked" .. i, ZIndex = 2 })
	Kit.rect(f, -1200, 0, W.Width + 2400, W.FloorHeight, Theme.RockDark, { Name = "Ext", ZIndex = 1 })
	for k = 1, 14 do
		local rock = Kit.rect(f, (k * 173 + i * 41) % 960, (k * 61 + i * 29) % 150, 40 + k % 3 * 16, 24 + k % 2 * 10, Theme.Rock, { ZIndex = 2, Rotation = (k * 17) % 30 - 15 })
		Kit.corner(rock, 8)
	end
	for k = 1, 5 do
		local glint = Kit.rect(f, 300 + k * 110, 40 + (k % 3) * 38, 14, 12, def.Color, { ZIndex = 3, Rotation = 45 })
		Kit.corner(glint, 3)
	end
	local card = Kit.rect(f, 330, 26, 400, 128, Theme.Panel, { Name = "Card", ZIndex = 4, BackgroundTransparency = 0.08 })
	Kit.corner(card, 16)
	Kit.stroke(card, Theme.Ink, 3)
	local lock = Kit.rect(card, 18, 34, 48, 40, Theme.Gold, { ZIndex = 5 })
	Kit.corner(lock, 8)
	Kit.stroke(lock, Theme.Ink, 2)
	local shackle = Kit.rect(card, 28, 16, 28, 26, Color3.new(), { ZIndex = 4, BackgroundTransparency = 1 })
	Kit.corner(shackle, 12)
	Kit.stroke(shackle, Theme.Gold, 6)
	Kit.label(card, { Position = UDim2.fromOffset(80, 10), Size = UDim2.fromOffset(310, 30), Text = "SHAFT " .. i .. " \u{00B7} " .. string.upper(def.Name), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = def.Color:Lerp(Color3.new(1, 1, 1), 0.25), ZIndex = 5 })
	Kit.label(card, { Position = UDim2.fromOffset(80, 36), Size = UDim2.fromOffset(310, 20), Text = string.format("Each ore is worth $%s!", F.short(def.Value)), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 205, 220), ZIndex = 5 })
	local button = Kit.button(card, { Name = "Unlock", Position = UDim2.fromOffset(80, 62), Size = UDim2.fromOffset(300, 52), BackgroundColor3 = Theme.Green, ZIndex = 6 }, function()
		fire("onUnlock", i)
	end)
	Kit.corner(button, 14)
	Kit.stroke(button, Theme.Ink, 3)
	local text = Kit.label(button, { Size = UDim2.fromScale(1, 1), Text = "UNLOCK  $" .. F.short(def.UnlockCost), TextSize = 22, ZIndex = 7 })
	Kit.outlined(text)
	return { frame = f, button = button, text = text, def = def, card = card }
end

-- (Re)builds floors to match the state: every unlocked shaft, then the next locked one.
function World.layout(state)
	local unlocked = 0
	for i, sh in state.shafts do
		if sh.unlocked then
			unlocked = i
		end
	end
	for i = 1, unlocked do
		if not World.floors[i] then
			World.floors[i] = buildFloor(i)
		end
	end
	if World.locked and World.locked.index ~= unlocked + 1 then
		World.locked.refs.frame:Destroy()
		World.locked = nil
	end
	local nextIndex = unlocked + 1
	if Config.Shafts[nextIndex] and not World.locked then
		World.locked = { index = nextIndex, refs = buildLocked(nextIndex) }
	end
	if World.deep then
		World.deep:Destroy()
	end
	local rows = unlocked + (if Config.Shafts[nextIndex] then 1 else 0)
	World.deep = Kit.rect(World.floorsFolder, 0, rows * W.FloorHeight, W.Width, 160, Theme.RockDark, { Name = "Deep", ZIndex = 2 })
	Kit.rect(World.deep, -1200, 0, W.Width + 2400, 160, Theme.RockDark, { Name = "Ext", ZIndex = 1 })
	Kit.label(World.deep, { Position = UDim2.fromOffset(0, 40), Size = UDim2.fromOffset(W.Width, 30), Text = if Config.Shafts[nextIndex] then "Deeper shafts are hidden below..." else "You reached the bottom of the mine!", TextSize = 18, TextColor3 = Color3.fromRGB(150, 130, 120), ZIndex = 3 })
	World.height = W.SurfaceHeight + rows * W.FloorHeight + 160
	World.unlocked = unlocked
	World.world.Size = UDim2.fromOffset(W.Width, World.height)
	World.shaftColumn.Size = UDim2.fromOffset(W.ShaftWidth, W.SurfaceHeight - W.GroundY + unlocked * W.FloorHeight)
	for _, r in World.rails do
		r:Destroy()
	end
	World.rails = {}
	local columnH = W.SurfaceHeight - W.GroundY + unlocked * W.FloorHeight
	for _, x in { 14, W.ShaftWidth - 20 } do
		table.insert(World.rails, Kit.rect(World.shaftColumn, x, 0, 6, columnH, Theme.Rail, { ZIndex = 2 }))
	end
	for k = 0, math.floor(columnH / 44) do
		table.insert(World.rails, Kit.rect(World.shaftColumn, 14, k * 44 + 20, W.ShaftWidth - 28, 4, Theme.Rail:Lerp(Color3.new(0, 0, 0), 0.3), { ZIndex = 2 }))
	end
	-- the right number of miners on each floor
	for i = 1, unlocked do
		local refs = World.floors[i]
		local want = state.shafts[i].workers
		while #refs.miners < want do
			local n = #refs.miners + 1
			local shirts = { Color3.fromRGB(240, 140, 40), Color3.fromRGB(230, 90, 80), Color3.fromRGB(90, 170, 240), Color3.fromRGB(150, 100, 220), Color3.fromRGB(90, 200, 150) }
			local fig = Figures.worker(refs.frame, { name = "Miner" .. n, shirt = shirts[n], pants = Color3.fromRGB(60, 80, 140), tool = "pickaxe", skin = Theme.Skin[(n % 3) + 1] })
			table.insert(refs.miners, fig)
		end
	end
	World.fit()
end

-- Scale the world to the screen width.
-- Phones fit the width (big, readable); desktops also cap by height so the
-- surface and about two floors stay in view.
function World.fit(vp: Vector2?, touch: boolean?)
	if vp then
		World.lastVp, World.lastTouch = vp, touch
	else
		vp, touch = World.lastVp, World.lastTouch
	end
	vp = vp or workspace.CurrentCamera.ViewportSize
	local scale = vp.X / W.Width
	if not touch then
		scale = math.min(scale, vp.Y / 640)
	end
	scale = math.clamp(scale, 0.35, 1.7)
	World.uiScale.Scale = scale
	World.scale = scale
	World.scroll.CanvasSize = UDim2.new(0, 0, 0, (World.height or 2000) * scale)
end

-- COUNTS AND LABELS -----------------------------------------------------------------------------

function World.refresh(state)
	local money = state.money
	local elev = F.elevator(state.elevator)
	local trans = F.warehouse(state.warehouse)
	for i, refs in World.floors do
		local sh = state.shafts[i]
		refs.label.Text = F.short(sh.ore)
		sizeHeap(refs.crateHeap, sh.ore, 80)
		local backed = sh.ore > elev.capacity * Config.BackupLoads
		refs.warn.Visible = backed
		refs.tag.BackgroundColor3 = if backed then Color3.fromRGB(220, 110, 30) else Theme.Panel
		refs.badge.level.Text = "Lv " .. sh.pick
		local cheapest = math.huge
		for _, def in Config.Upgrades.shaft do
			local p = F.price(def, sh[def.Id], Config.Shafts[i].Value)
			if p then
				cheapest = math.min(cheapest, p)
			end
		end
		refs.badge.up.BackgroundColor3 = if money >= cheapest then Theme.Green else Theme.Grey
		setManager(refs.manager, sh.manager, Config.Shafts[i].ManagerCost, money, Color3.fromRGB(150, 90, 200))
	end
	World.pileLabel.Text = F.short(state.pile)
	sizeHeap(World.pileHeap, state.pile, 110)
	local pileBacked = state.pile > trans.capacity * Config.BackupLoads
	World.pileWarn.Visible = pileBacked
	World.pileTag.BackgroundColor3 = if pileBacked then Color3.fromRGB(220, 110, 30) else Theme.Panel
	World.elevBadge.level.Text = "Lv " .. state.elevator.cap
	World.whBadge.level.Text = "Lv " .. state.warehouse.cap
	for _, pair in { { World.elevBadge, "elevator" }, { World.whBadge, "warehouse" } } do
		local data = state[pair[2]]
		local cheapest = math.huge
		for _, def in Config.Upgrades[pair[2]] do
			local p = F.price(def, data[def.Id], 1)
			if p then
				cheapest = math.min(cheapest, p)
			end
		end
		pair[1].up.BackgroundColor3 = if money >= cheapest then Theme.Green else Theme.Grey
	end
	setManager(World.elevManager, state.elevator.manager, Config.Managers.Elevator, money, Color3.fromRGB(70, 150, 245))
	setManager(World.whManager, state.warehouse.manager, Config.Managers.Warehouse, money, Color3.fromRGB(80, 190, 100))
	if World.locked then
		local refs, def = World.locked.refs, World.locked.refs.def
		local can = money >= def.UnlockCost
		refs.button.BackgroundColor3 = if can then Theme.Green else Theme.Grey
		refs.text.Text = if can then "UNLOCK  $" .. F.short(def.UnlockCost) else "NEED  $" .. F.short(def.UnlockCost)
	end
end

-- PER FRAME ------------------------------------------------------------------------------------

local function progress(e, sNow: number): number
	if e.t1 <= e.t0 then
		return 1
	end
	return math.clamp((sNow - e.t0) / (e.t1 - e.t0), 0, 1)
end

local function smooth(k: number): number
	return k * k * (3 - 2 * k)
end

-- Returns the list of pickaxe strikes this frame: { { shaft, x } }
function World.draw(t: number, sNow: number, ents, state)
	local strikes = {}
	for i, refs in World.floors do
		local sh = state.shafts[i]
		local list = ents.miners[i] or {}
		local allIdle = true
		for w, fig in refs.miners do
			local m = list[w] or { p = "idle", t0 = 0, t1 = 0, carry = 0 }
			local home = W.MinerHome + (w - 1) * 30
			local face = W.RockX - 18 - (w - 1) * 20
			local k = progress(m, sNow)
			local x, facing, walking, mining, carrying = home, 1, false, false, false
			if m.p == "out" then
				x, facing, walking = home + (face - home) * k, 1, true
			elseif m.p == "mine" then
				x, mining = face, true
			elseif m.p == "back" then
				x, facing, walking, carrying = face + (home - face) * k, -1, true, true
			else
				facing = 1
			end
			if m.p ~= "idle" then
				allIdle = false
			end
			local hit = fig:update({ x = x, y = FEET, facing = facing, walking = walking, mining = mining, carrying = carrying, carryColor = refs.def.Color, t = t + w * 0.37, idle = m.p == "idle" })
			if hit then
				table.insert(strikes, { i, x + 40 })
			end
		end
		local showHint = allIdle and not sh.manager
		refs.hint.Visible = showHint
		if showHint then
			refs.hint.Position = UDim2.fromOffset(W.MinerHome + 150, FEET - 30 + math.sin(t * 5) * 5)
		end
	end
	-- elevator
	local e = ents.elev
	local cageY
	if e.p == "move" then
		cageY = e.fromY + (e.toY - e.fromY) * smooth(progress(e, sNow))
		World.wheel.Rotation = (World.wheel.Rotation + (if e.toY > e.fromY then 6 else -6)) % 360
	else
		cageY = e.toY
	end
	local cageTop = cageY + 70 - CAGE_H
	World.cage.Position = UDim2.fromOffset(W.ShaftLeft + (W.ShaftWidth - CAGE_W) / 2, cageTop)
	World.cable.Size = UDim2.fromOffset(4, math.max(0, cageTop - 144))
	World.operator:update({ x = 34, y = CAGE_H - 8, facing = 1, walking = false, lever = e.p == "load" or e.p == "unload", t = t, idle = e.p == "idle" })
	sizeHeap(World.cageHeap, e.load, 40)
	World.cageTag.Position = UDim2.fromOffset(W.ShaftLeft + W.ShaftWidth / 2, cageTop - 16)
	World.cageTag.Visible = e.load > 0
	World.cageLabel.Text = F.short(e.load)
	local anyOre = false
	for _, sh in state.shafts do
		if sh.unlocked and sh.ore > 0 then
			anyOre = true
		end
	end
	local elevHint = e.p == "idle" and not state.elevator.manager and anyOre
	World.elevHint.Visible = elevHint
	if elevHint then
		World.elevHint.Position = UDim2.fromOffset(W.ShaftLeft + W.ShaftWidth / 2, 108 + math.sin(t * 5) * 5)
	end
	-- transporter
	local tr = ents.tr
	local k = progress(tr, sNow)
	local stand = W.PileX + 96
	local x, facing, walking = W.TransporterHome, 1, false
	if tr.p == "out" then
		x, facing, walking = W.TransporterHome + (stand - W.TransporterHome) * k, -1, true
	elseif tr.p == "load" then
		x, facing = stand, -1
	elseif tr.p == "back" then
		x, facing, walking = stand + (W.TransporterHome - stand) * k, 1, true
	end
	World.transporter:update({ x = x, y = W.GroundY + 4, facing = facing, walking = walking, carrying = tr.carry > 0, carryColor = Theme.Gold, t = t, idle = tr.p == "idle" })
	local whHint = tr.p == "idle" and not state.warehouse.manager and state.pile > 0
	World.whHint.Visible = whHint
	if whHint then
		World.whHint.Position = UDim2.fromOffset(W.TransporterHome - 78, W.GroundY - 46 + math.sin(t * 5) * 5)
	end
	-- clouds drift
	for _, c in World.clouds do
		c.x += c.speed * (1 / 60)
		if c.x > W.Width + 60 then
			c.x = -180
		end
		c.inst.Position = UDim2.fromOffset(c.x, c.inst.Position.Y.Offset)
	end
	return strikes
end

-- Where something sits on screen (for effects that fly to the HUD).
function World.screenPoint(xDU: number, yDU: number): Vector2
	local wpos = World.world.AbsolutePosition
	return wpos + Vector2.new(xDU, yDU) * World.scale
end

-- The screen-space Y of a world Y (for scrolling to things).
function World.canvasYFor(yDU: number): number
	return yDU * World.scale
end

-- Smoothly scrolls so world height yDU sits at fraction `at` of the screen (0.5 = middle).
function World.scrollTo(yDU: number, at: number?, time: number?)
	local view = World.scroll.AbsoluteSize.Y
	local maxY = math.max(0, World.scroll.AbsoluteCanvasSize.Y - view)
	local target = math.clamp(yDU * World.scale - view * (at or 0.5), 0, maxY)
	World.scrollTween = game:GetService("TweenService"):Create(World.scroll, TweenInfo.new(time or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = Vector2.new(0, target) })
	World.scrollTween:Play()
	return World.scrollTween
end

function World.floorTop(i: number): number
	return W.SurfaceHeight + (i - 1) * W.FloorHeight
end

return World
