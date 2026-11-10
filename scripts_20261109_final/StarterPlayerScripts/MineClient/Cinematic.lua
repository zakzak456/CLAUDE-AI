-- The opening: about nine seconds, skippable at any time.
--   1. A kid with a pickaxe digs one little hole on a grassy hill.
--   2. Flash: the dream - a huge cross-section mine, six glittering floors, an
--      elevator racing up and down, coins pouring out.
--   3. The title pops in: MOM, LOOK! I CAN MINE!
-- Everything is drawn on a 1000 x 560 stage, letterboxed to fit any screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Mine.Config)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Figures = require(script.Parent.Figures)

local Cinematic = {}

local STAGE_W, STAGE_H = 1000, 560
local LENGTH = 9.2

local function caption(parent, text)
	local l = Kit.label(parent, { Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(STAGE_W / 2, STAGE_H - 64), Size = UDim2.fromOffset(900, 50), Text = text, TextSize = 34, ZIndex = 30, TextTransparency = 1 })
	local st = Kit.outlined(l, Theme.Ink, 3)
	st.Transparency = 1
	return l, st
end

local function fadeIn(l, st, time)
	Kit.tween(l, time or 0.4, { TextTransparency = 0 })
	Kit.tween(st, time or 0.4, { Transparency = 0 })
end

local function fadeOut(l, st, time)
	Kit.tween(l, time or 0.3, { TextTransparency = 1 })
	Kit.tween(st, time or 0.3, { Transparency = 1 })
end

-- Scene 1: the little hole
local function sceneHill(stage)
	local scene = Kit.rect(stage, 0, 0, STAGE_W, STAGE_H, Color3.new(1, 1, 1), { Name = "Hill", ZIndex = 21, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(STAGE_W / 2, STAGE_H / 2) })
	Kit.gradient(scene, Theme.Sky[1], Theme.Sky[2], 90)
	local zoom = Kit.new("UIScale", {}, scene)
	local sun = Kit.rect(scene, 760, 60, 90, 90, Color3.fromRGB(255, 236, 120), { ZIndex = 21 })
	Kit.corner(sun)
	Kit.stroke(sun, Color3.fromRGB(255, 210, 90), 8, 0.4)
	for _, c in { { 90, 70, 1.2 }, { 520, 120, 0.9 } } do
		local cloud = Kit.rect(scene, c[1], c[2], 140 * c[3], 40 * c[3], Theme.White, { ZIndex = 21 })
		Kit.corner(cloud)
		local puff = Kit.rect(cloud, 30 * c[3], -20 * c[3], 64 * c[3], 48 * c[3], Theme.White, { ZIndex = 21 })
		Kit.corner(puff)
	end
	local hill = Kit.rect(scene, 120, 300, 760, 420, Theme.Grass, { ZIndex = 22 })
	Kit.corner(hill, 200)
	local ground = Kit.rect(scene, 0, 420, STAGE_W, 140, Theme.Dirt[1], { ZIndex = 22 })
	Kit.rect(scene, 0, 410, STAGE_W, 18, Theme.Grass, { ZIndex = 23 })
	local hole = Kit.rect(scene, 520, 396, 110, 40, Theme.Shaft, { ZIndex = 24 })
	Kit.corner(hole)
	local sign = Kit.rect(scene, 640, 330, 90, 40, Theme.Wood, { ZIndex = 23, Rotation = -6 })
	Kit.corner(sign, 6)
	Kit.stroke(sign, Theme.WoodDark, 3)
	Kit.label(sign, { Size = UDim2.fromScale(1, 1), Text = "MINE", TextSize = 22, ZIndex = 24 })
	Kit.rect(scene, 680, 368, 8, 50, Theme.WoodDark, { ZIndex = 22 })
	local kid = Figures.worker(scene, { name = "Kid", shirt = Color3.fromRGB(240, 140, 40), pants = Color3.fromRGB(60, 80, 140), tool = "pickaxe" })
	kid.root.ZIndex = 25
	for _, d in kid.root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 20
		end
	end
	local scaleKid = Kit.new("UIScale", { Scale = 1.6 }, kid.root)
	return scene, zoom, kid
end

-- Scene 2: the dream mine
local function sceneEmpire(stage)
	local scene = Kit.rect(stage, 0, 0, STAGE_W, STAGE_H, Color3.new(1, 1, 1), { Name = "Empire", ZIndex = 21, Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(STAGE_W / 2, STAGE_H / 2) })
	Kit.gradient(scene, Color3.fromRGB(255, 196, 120), Color3.fromRGB(120, 70, 160), 90)
	local zoom = Kit.new("UIScale", {}, scene)
	local skyline = Kit.rect(scene, 0, 0, STAGE_W, 110, Color3.fromRGB(255, 220, 150), { ZIndex = 21, BackgroundTransparency = 0.3 })
	local wh = Kit.rect(scene, 640, 30, 300, 80, Theme.Brick, { ZIndex = 22 })
	Kit.stroke(wh, Theme.Ink, 3)
	local roof = Kit.rect(scene, 620, 14, 340, 26, Theme.Roof, { ZIndex = 23 })
	Kit.corner(roof, 8)
	Kit.label(wh, { Size = UDim2.fromScale(1, 1), Text = "$$$", TextSize = 40, TextColor3 = Theme.Gold, ZIndex = 23 })
	local rows = {}
	for i, def in Config.Shafts do
		local y = 110 + (i - 1) * 75
		local row = Kit.rect(scene, 0, y, STAGE_W, 75, Theme.Dirt[math.min(i + 1, #Theme.Dirt)], { ZIndex = 22 })
		local tunnel = Kit.rect(row, 150, 10, 830, 56, Theme.Tunnel, { ZIndex = 23 })
		Kit.corner(tunnel, 10)
		for k = 1, 7 do
			local gem = Kit.rect(row, 210 + k * 105, 18 + (k % 2) * 16, 22, 18, def.Color, { ZIndex = 24, Rotation = (k * 31) % 50 - 25 })
			Kit.corner(gem, 5)
			Kit.stroke(gem, def.Color:Lerp(Color3.new(1, 1, 1), 0.6), 2)
		end
		local miners = {}
		for k = 1, 3 do
			local dot = Kit.rect(row, 200 + k * 200, 26, 20, 34, Color3.fromRGB(240, 140, 40), { ZIndex = 25 })
			Kit.corner(dot, 8)
			local helmet = Kit.rect(dot, -2, -8, 24, 12, Theme.Gold, { ZIndex = 26 })
			Kit.corner(helmet, 6)
			miners[k] = dot
		end
		rows[i] = { frame = row, miners = miners }
	end
	local shaft = Kit.rect(scene, 40, 60, 90, STAGE_H, Theme.Shaft, { ZIndex = 26 })
	local cage = Kit.rect(scene, 50, 120, 70, 60, Theme.Cage, { ZIndex = 27 })
	Kit.corner(cage, 6)
	Kit.stroke(cage, Theme.Ink, 3)
	local coins = {}
	for k = 1, 28 do
		local c = Kit.rect(scene, math.random(0, STAGE_W), -40, 26, 26, Theme.Gold, { ZIndex = 28 })
		Kit.corner(c)
		Kit.stroke(c, Color3.fromRGB(200, 140, 20), 2)
		coins[k] = { inst = c, x = math.random(20, STAGE_W - 20), delay = math.random() * 2.2, speed = 260 + math.random() * 200, spin = math.random(-200, 200) }
	end
	return scene, zoom, rows, cage, coins
end

local function title(stage)
	local holder = Kit.rect(stage, 0, 0, STAGE_W, STAGE_H, Color3.new(), { Name = "Title", BackgroundTransparency = 1, ZIndex = 35 })
	local top = Kit.label(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(STAGE_W / 2, 200), Size = UDim2.fromOffset(900, 90), Text = "MOM, LOOK!", TextSize = 78, TextColor3 = Theme.White, ZIndex = 36, Visible = false })
	Kit.outlined(top, Theme.Ink, 6)
	local bottom = Kit.label(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(STAGE_W / 2, 300), Size = UDim2.fromOffset(900, 120), Text = "I CAN MINE!", TextSize = 112, TextColor3 = Theme.Gold, ZIndex = 36, Visible = false })
	Kit.outlined(bottom, Theme.Ink, 7)
	Kit.gradient(bottom, Color3.fromRGB(255, 236, 120), Color3.fromRGB(255, 170, 40), 90)
	local pick = Kit.label(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(STAGE_W / 2, 400), Size = UDim2.fromOffset(200, 80), Text = "\u{26CF}", TextSize = 70, TextColor3 = Theme.White, ZIndex = 36, Visible = false })
	Kit.outlined(pick, Theme.Ink, 4)
	return top, bottom, pick
end

local function pop(label: GuiObject)
	label.Visible = true
	local sc = label:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", {}, label)
	sc.Scale = 0.2
	Kit.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Cinematic.play(App, onDone)
	local gui = App.gui
	local root = Kit.rect(gui, 0, 0, 0, 0, Color3.new(0, 0, 0), { Name = "Cinematic", Size = UDim2.fromScale(1, 1), ZIndex = 20 })
	local blocker = Instance.new("TextButton")
	blocker.Name = "Blocker"
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.BackgroundTransparency = 1
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.ZIndex = 20
	blocker.Parent = root
	local stage = Kit.rect(root, 0, 0, STAGE_W, STAGE_H, Color3.new(), { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 21, ClipsDescendants = true })
	local stageScale = Kit.new("UIScale", {}, stage)
	local function fit()
		local vp = gui.AbsoluteSize
		stageScale.Scale = math.min(vp.X / STAGE_W, vp.Y / STAGE_H)
	end
	fit()
	local fitConn = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local hill, hillZoom, kid = sceneHill(stage)
	local empire, empireZoom, rows, cage, coins = sceneEmpire(stage)
	local top, bottom, pick = title(stage)
	local cap1, st1 = caption(stage, "Every mining empire starts small...")
	local cap2, st2 = caption(stage, "...but dig hard enough, and it gets HUGE!")
	local flash = Kit.rect(stage, 0, 0, STAGE_W, STAGE_H, Theme.White, { Name = "Flash", ZIndex = 40, BackgroundTransparency = 1 })
	-- letterbox bars over the whole screen
	local barTop = Kit.rect(root, 0, 0, 0, 0, Color3.new(0, 0, 0), { Size = UDim2.new(1, 0, 0.06, 0), ZIndex = 45 })
	local barBottom = Kit.rect(root, 0, 0, 0, 0, Color3.new(0, 0, 0), { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.06, 0), ZIndex = 45 })
	local fade = Kit.rect(root, 0, 0, 0, 0, Color3.new(0, 0, 0), { Name = "Fade", Size = UDim2.fromScale(1, 1), ZIndex = 48, BackgroundTransparency = 0 })
	Kit.tween(fade, 0.5, { BackgroundTransparency = 1 })

	local finished = false
	local conn
	local function finish()
		if finished then
			return
		end
		finished = true
		if conn then
			conn:Disconnect()
		end
		fitConn:Disconnect()
		local t = Kit.tween(fade, 0.35, { BackgroundTransparency = 0 })
		t.Completed:Wait()
		Kit.tween(fade, 0.4, { BackgroundTransparency = 1 })
		for _, c in root:GetChildren() do
			if c ~= fade then
				c:Destroy()
			end
		end
		task.delay(0.45, function()
			root:Destroy()
		end)
		if onDone then
			onDone()
		end
	end

	local skipHolder = Kit.rect(root, 0, 0, 160, 56, Color3.new(), { Name = "SkipHolder", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), BackgroundTransparency = 1, ZIndex = 50 })
	Kit.new("UIScale", { Scale = App.Hud.scale or 1 }, skipHolder)
	local skip = Kit.button(skipHolder, { Name = "Skip", Size = UDim2.fromOffset(160, 56), BackgroundColor3 = Theme.Panel, ZIndex = 50 }, function()
		task.spawn(finish)
	end)
	Kit.corner(skip, 16)
	Kit.stroke(skip, Theme.White, 2.5)
	local skipText = Kit.label(skip, { Size = UDim2.fromScale(1, 1), Text = "SKIP \u{2192}", TextSize = 24, ZIndex = 51 })

	local fired = {}
	local function once(key, fn)
		if not fired[key] then
			fired[key] = true
			fn()
		end
	end
	local t0 = os.clock()
	local speed = workspace:GetAttribute("CineSpeed") or 1 -- Studio tests can slow it down to capture frames
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - t0) * speed
		if t < 3.4 then
			-- scene 1: the kid digs
			once("cap1", function()
				fadeIn(cap1, st1, 0.5)
			end)
			hillZoom.Scale = 1 + t * 0.03
			kid:update({ x = 470, y = 420, facing = 1, mining = true, t = t })
		elseif t < 6.6 then
			once("flash", function()
				fadeOut(cap1, st1, 0.2)
				flash.BackgroundTransparency = 0
				Kit.tween(flash, 0.6, { BackgroundTransparency = 1 })
				hill.Visible = false
				empire.Visible = true
				empireZoom.Scale = 1.25
				Kit.tween(empireZoom, 3.0, { Scale = 1 }, Enum.EasingStyle.Quad)
				fadeIn(cap2, st2, 0.4)
			end)
			local k = t - 3.4
			-- elevator races, miners shuffle, coins rain
			cage.Position = UDim2.fromOffset(50, 120 + (math.sin(k * 3) * 0.5 + 0.5) * 380)
			for i, row in rows do
				for j, dot in row.miners do
					local phase = k * (1.2 + i * 0.1) + j
					dot.Position = UDim2.fromOffset(200 + j * 200 + math.sin(phase) * 80, 26 - math.abs(math.sin(phase * 4)) * 4)
				end
			end
			for _, c in coins do
				local ct = k - c.delay
				if ct > 0 then
					local y = -40 + ct * c.speed
					c.inst.Position = UDim2.fromOffset(c.x, y % (STAGE_H + 60) - 40)
					c.inst.Rotation = ct * c.spin
				end
			end
		elseif t < LENGTH then
			once("title", function()
				fadeOut(cap2, st2, 0.2)
				local dim = Kit.rect(stage, 0, 0, STAGE_W, STAGE_H, Color3.new(0, 0, 0), { ZIndex = 34, BackgroundTransparency = 1 })
				Kit.tween(dim, 0.3, { BackgroundTransparency = 0.45 })
				pop(top)
				task.delay(0.45, function()
					pop(bottom)
				end)
				task.delay(0.9, function()
					pop(pick)
				end)
			end)
			local k = t - 6.6
			for _, c in coins do
				local y = -40 + (k + 3.2 - c.delay) * c.speed
				c.inst.Position = UDim2.fromOffset(c.x, y % (STAGE_H + 60) - 40)
			end
			pick.Rotation = math.sin(k * 8) * 20
		else
			task.spawn(finish)
		end
	end)
end

return Cinematic
