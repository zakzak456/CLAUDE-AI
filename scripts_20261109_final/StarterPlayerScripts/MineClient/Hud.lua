-- The interface over the mine: money (counts up smoothly), income per second, the
-- slowest-stage hint, toasts, floating numbers, coins flying to the counter, the
-- jump buttons and the welcome-back card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Mine.Config)
local F = require(ReplicatedStorage.Mine.Formulas)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Hud = {}
local sales = {}
local toasts = {}

local function coinIcon(parent, x, y, size, z)
	local c = Kit.rect(parent, x, y, size, size, Theme.Gold, { Name = "Coin", ZIndex = z })
	Kit.corner(c)
	Kit.stroke(c, Color3.fromRGB(200, 140, 20), math.max(2, size / 12))
	local inner = Kit.label(c, { Size = UDim2.fromScale(1, 1), Text = "$", TextSize = size * 0.62, TextColor3 = Color3.fromRGB(170, 110, 10), ZIndex = z + 1 })
	return c
end
Hud.coinIcon = coinIcon

function Hud.build(gui: ScreenGui)
	local root = Kit.rect(gui, 0, 0, 100, 100, Color3.new(), { Name = "Hud", BackgroundTransparency = 1, ZIndex = 5 })
	Hud.root = root
	Hud.uiScale = Kit.new("UIScale", {}, root)

	local pill = Kit.rect(root, 0, 8, 260, 56, Theme.Panel, { Name = "Money", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), ZIndex = 5 })
	Kit.corner(pill)
	Kit.stroke(pill, Theme.Ink, 3)
	Kit.gradient(pill, Theme.PanelLight, Theme.Panel, 90)
	Hud.coin = coinIcon(pill, 8, 6, 44, 6)
	Hud.moneyLabel = Kit.label(pill, { Name = "Amount", Position = UDim2.fromOffset(58, 0), Size = UDim2.fromOffset(190, 56), Text = "$0", TextSize = 32, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Gold, ZIndex = 6 })
	Kit.outlined(Hud.moneyLabel, Theme.Ink, 2)
	Hud.moneyScale = Kit.new("UIScale", {}, pill)
	Hud.pill = pill

	local rate = Kit.rect(root, 0, 66, 150, 26, Theme.Panel, { Name = "Rate", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), ZIndex = 5, BackgroundTransparency = 0.15 })
	Kit.corner(rate)
	Kit.stroke(rate, Theme.Ink, 2)
	Hud.rateLabel = Kit.label(rate, { Size = UDim2.fromScale(1, 1), Text = "$0 /s", TextSize = 16, TextColor3 = Color3.fromRGB(180, 255, 170), ZIndex = 6 })
	Hud.rate = rate

	-- the slowest stage, tappable
	local chip = Kit.button(root, { Name = "Bottleneck", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 98), Size = UDim2.fromOffset(300, 34), BackgroundColor3 = Color3.fromRGB(255, 140, 40), ZIndex = 5, Visible = false }, function()
		if Hud.onBottleneck and Hud.bottleneckStage then
			Hud.onBottleneck(Hud.bottleneckStage, Hud.bottleneckIndex)
		end
	end)
	Kit.corner(chip)
	Kit.stroke(chip, Theme.Ink, 2.5)
	Hud.chipLabel = Kit.label(chip, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = 16, ZIndex = 6 })
	Kit.outlined(Hud.chipLabel, Theme.Ink, 1.5)
	Hud.chip = chip

	-- jump buttons
	local function jump(name, y, text, cb)
		local b = Kit.button(root, { Name = name, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, y), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.1, ZIndex = 5 }, cb)
		Kit.corner(b, 18)
		Kit.stroke(b, Theme.Ink, 3)
		Kit.label(b, { Size = UDim2.fromScale(1, 1), Text = text, TextSize = 26, ZIndex = 6 })
		return b
	end
	Hud.upButton = jump("JumpUp", -86, "\u{25B2}", function()
		if Hud.onJump then
			Hud.onJump("top")
		end
	end)
	Hud.downButton = jump("JumpDown", -14, "\u{25BC}", function()
		if Hud.onJump then
			Hud.onJump("bottom")
		end
	end)

	Hud.toastHolder = Kit.rect(root, 0, 140, 10, 10, Color3.new(), { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), ZIndex = 9 })
	Hud.flyLayer = Kit.rect(root, 0, 0, 10, 10, Color3.new(), { Name = "Fly", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20 })
	Hud.shown, Hud.target = 0, 0
	return Hud
end

function Hud.fit(vp: Vector2)
	local s = math.clamp(math.min(vp.X / 900, vp.Y / 520), 0.62, 1.3)
	Hud.scale = s
	Hud.uiScale.Scale = s
	Hud.root.Size = UDim2.fromOffset(vp.X / s, vp.Y / s)
	return s
end

function Hud.setMoney(v: number, instant: boolean?)
	if v > Hud.target and not instant then
		Hud.moneyScale.Scale = 1.12
		Kit.tween(Hud.moneyScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	Hud.target = v
	if instant then
		Hud.shown = v
	end
end

function Hud.noteSale(amount: number)
	table.insert(sales, { os.clock(), amount })
end

function Hud.update(dt: number)
	local diff = Hud.target - Hud.shown
	if math.abs(diff) < 0.5 then
		Hud.shown = Hud.target
	else
		Hud.shown += diff * math.min(1, dt * 9)
	end
	Hud.moneyLabel.Text = "$" .. F.short(Hud.shown)
	-- income over the last 20 s
	local now = os.clock()
	while sales[1] and now - sales[1][1] > 20 do
		table.remove(sales, 1)
	end
	local sum = 0
	for _, s in sales do
		sum += s[2]
	end
	local window = if sales[1] then math.clamp(now - sales[1][1], 8, 20) else 20
	Hud.rateLabel.Text = "$" .. F.short(sum / window) .. " /s"
end

function Hud.setBottleneck(text: string?, stage: string?, index: number?)
	Hud.chip.Visible = text ~= nil
	Hud.chipLabel.Text = text or ""
	Hud.bottleneckStage, Hud.bottleneckIndex = stage, index
end

function Hud.toast(text: string, color: Color3?)
	local t = Kit.rect(Hud.toastHolder, 0, 0, 10, 40, color or Theme.Panel, { Name = "Toast", AnchorPoint = Vector2.new(0.5, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 9 })
	Kit.corner(t, 14)
	Kit.stroke(t, Theme.Ink, 2.5)
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, t)
	local l = Kit.label(t, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = text, TextSize = 20, ZIndex = 10 })
	Kit.outlined(l, Theme.Ink, 1.5)
	table.insert(toasts, 1, t)
	while #toasts > 3 do
		table.remove(toasts):Destroy()
	end
	for i, inst in toasts do
		Kit.tween(inst, 0.18, { Position = UDim2.fromOffset(0, (i - 1) * 46) })
	end
	local sc = Kit.new("UIScale", { Scale = 0.6 }, t)
	Kit.tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.6, function()
		local i = table.find(toasts, t)
		if i then
			table.remove(toasts, i)
		end
		if t.Parent then
			Kit.tween(sc, 0.2, { Scale = 0 })
			task.wait(0.2)
			t:Destroy()
		end
	end)
end

-- Coins that fly from a screen point (pixels) to the money counter.
function Hud.flyCoins(from: Vector2, count: number)
	local s = Hud.scale or 1
	local target = Hud.coin.AbsolutePosition + Hud.coin.AbsoluteSize / 2
	local rootPos = Hud.root.AbsolutePosition
	for i = 1, count do
		task.delay((i - 1) * 0.05, function()
			local start = (from - rootPos) / s + Vector2.new(math.random(-20, 20), math.random(-20, 20))
			local goal = (target - rootPos) / s
			local c = coinIcon(Hud.flyLayer, start.X - 14, start.Y - 14, 28, 21)
			c.AnchorPoint = Vector2.new(0, 0)
			local mid = start:Lerp(goal, 0.5) + Vector2.new(math.random(-60, 60), -80)
			local t0 = os.clock()
			local dur = 0.55 + math.random() * 0.15
			local conn
			conn = game:GetService("RunService").RenderStepped:Connect(function()
				local k = math.min(1, (os.clock() - t0) / dur)
				local a = start:Lerp(mid, k)
				local b = mid:Lerp(goal, k)
				local p = a:Lerp(b, k * k)
				c.Position = UDim2.fromOffset(p.X - 14, p.Y - 14)
				if k >= 1 then
					conn:Disconnect()
					c:Destroy()
					Hud.coin.Rotation = 0
					Hud.moneyScale.Scale = 1.08
					Kit.tween(Hud.moneyScale, 0.18, { Scale = 1 })
				end
			end)
		end)
	end
end

-- A number that floats up from a point in the world layer and fades.
function Hud.popAt(layer: GuiObject, x: number, y: number, text: string, color: Color3?, size: number?)
	local l = Kit.label(layer, { Name = "Pop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(200, 40), Text = text, TextSize = size or 26, TextColor3 = color or Theme.Gold, ZIndex = 40 })
	local stroke = Kit.outlined(l, Theme.Ink, 2.5)
	local sc = Kit.new("UIScale", { Scale = 0.4 }, l)
	Kit.tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	Kit.tween(l, 0.9, { Position = UDim2.fromOffset(x, y - 60) })
	task.delay(0.55, function()
		Kit.tween(l, 0.35, { TextTransparency = 1 })
		Kit.tween(stroke, 0.35, { Transparency = 1 })
		task.wait(0.4)
		l:Destroy()
	end)
	return l
end

-- Welcome back card
function Hud.offline(earned: number, seconds: number, capped: boolean, onClose)
	local shade = Kit.button(Hud.root, { Name = "Offline", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 30 })
	local card = Kit.rect(shade, 0, 0, 440, 300, Theme.Panel, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 31 })
	Kit.corner(card, 22)
	Kit.stroke(card, Theme.Ink, 4)
	Kit.label(card, { Position = UDim2.fromOffset(0, 18), Size = UDim2.fromOffset(440, 40), Text = "WELCOME BACK!", TextSize = 34, TextColor3 = Theme.Gold, ZIndex = 32 })
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local away = if h > 0 then string.format("%dh %dm", h, m) else string.format("%dm", m)
	Kit.label(card, { Position = UDim2.fromOffset(30, 64), Size = UDim2.fromOffset(380, 50), TextWrapped = true, Text = "Your managers kept the mine running for " .. away .. (if capped then " (the most they can do)" else "") .. ".", TextSize = 19, ZIndex = 32 })
	coinIcon(card, 110, 130, 56, 32)
	local amt = Kit.label(card, { Position = UDim2.fromOffset(176, 128), Size = UDim2.fromOffset(240, 60), Text = "$" .. F.short(earned), TextSize = 44, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Gold, ZIndex = 32 })
	Kit.outlined(amt, Theme.Ink, 2.5)
	local ok = Kit.button(card, { Name = "Collect", Position = UDim2.fromOffset(120, 212), Size = UDim2.fromOffset(200, 64), BackgroundColor3 = Theme.Green, ZIndex = 32 }, function()
		local p = card.AbsolutePosition + card.AbsoluteSize / 2
		shade:Destroy()
		Hud.flyCoins(p, 14)
		if onClose then
			onClose()
		end
	end)
	Kit.corner(ok, 18)
	Kit.stroke(ok, Theme.Ink, 3)
	local t = Kit.label(ok, { Size = UDim2.fromScale(1, 1), Text = "COLLECT", TextSize = 28, ZIndex = 33 })
	Kit.outlined(t, Theme.Ink, 2)
	local sc = Kit.new("UIScale", { Scale = 0.5 }, card)
	Kit.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	return shade
end

return Hud
