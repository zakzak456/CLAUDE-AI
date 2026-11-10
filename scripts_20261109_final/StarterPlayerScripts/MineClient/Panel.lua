-- The upgrade panel. Opens from a stage's level badge and slides in from the right.
-- Each row shows what the next level changes (before -> after) and its price; a
-- row you can't afford shakes and says how much more you need. The manager card
-- explains what automation does, and the footer compares the three stages so the
-- slowest one is obvious.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Mine.Config)
local F = require(ReplicatedStorage.Mine.Formulas)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Figures = require(script.Parent.Figures)
local App = require(script.Parent.App)

local W = Config.World
local Panel = {}
Panel.isOpen = false
Panel.buyMode = 1 -- 1, 10 or "max"

local WIDTH = 420

local function money(n: number): string
	return "$" .. F.short(n)
end

local function secs(n: number): string
	return string.format("%.1fs", n)
end

-- Throughput of each stage in coins per second (when kept busy).
function Panel.rates(state)
	return F.rates(state)
end

-- What each upgrade row shows.
local ROWS = {
	shaft = {
		pick = function(i, s)
			return F.short(F.shaft(i, s).ore) .. " ore/trip"
		end,
		speed = function(i, s)
			return secs(F.shaft(i, s).trip) .. " trip"
		end,
		workers = function(i, s)
			return s.workers .. (if s.workers == 1 then " miner" else " miners")
		end,
	},
	elevator = {
		cap = function(_, e)
			return "holds " .. F.short(F.elevator(e).capacity)
		end,
		speed = function(_, e, state)
			local copy = table.clone(state)
			copy.elevator = e
			return secs(Panel.rates(copy).eTrip) .. " round trip"
		end,
	},
	warehouse = {
		cap = function(_, w)
			return "holds " .. F.short(F.warehouse(w).capacity)
		end,
		speed = function(_, w)
			return secs(F.warehouse(w).trip) .. " trip"
		end,
	},
}

local ICONS = { pick = "\u{26CF}", speed = "\u{26A1}", workers = "+", cap = "\u{25A3}" }

function Panel.build(gui: ScreenGui, hudRoot: GuiObject)
	local root = Kit.rect(hudRoot, 0, 0, WIDTH, 400, Theme.Panel, { Name = "Panel", AnchorPoint = Vector2.new(0, 0), ZIndex = 12, Visible = false })
	Kit.corner(root, 22)
	Kit.stroke(root, Theme.Ink, 4)
	Panel.root = root
	local header = Kit.rect(root, 0, 0, WIDTH, 70, Theme.Blue, { Name = "Header", ZIndex = 13 })
	Kit.corner(header, 22)
	Kit.rect(header, 0, 40, WIDTH, 30, Theme.Blue, { Name = "Square", ZIndex = 13 })
	Panel.header = header
	Panel.title = Kit.label(header, { Position = UDim2.fromOffset(20, 6), Size = UDim2.fromOffset(WIDTH - 110, 36), Text = "", TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 14 })
	Kit.outlined(Panel.title, Theme.Ink, 2)
	Panel.subtitle = Kit.label(header, { Position = UDim2.fromOffset(20, 38), Size = UDim2.fromOffset(WIDTH - 110, 24), Text = "", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(235, 240, 255), ZIndex = 14 })
	local close = Kit.button(header, { Name = "Close", Position = UDim2.fromOffset(WIDTH - 72, 8), Size = UDim2.fromOffset(58, 54), BackgroundColor3 = Theme.Red, ZIndex = 15 }, function()
		Panel.close()
	end)
	Kit.corner(close, 16)
	Kit.stroke(close, Theme.Ink, 3)
	local x = Kit.label(close, { Size = UDim2.fromScale(1, 1), Text = "X", TextSize = 28, ZIndex = 16 })
	Kit.outlined(x, Theme.Ink, 2)

	local body = Kit.new("ScrollingFrame", {
		Name = "Body", Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -82), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 13,
	}, root)
	Kit.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, body)
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10) }, body)
	Panel.body = body
	return Panel
end

-- Places the panel on the right, under the money counter.
function Panel.fit(hudSize: Vector2)
	Panel.top = 76
	local h = math.max(260, hudSize.Y - Panel.top - 12)
	Panel.root.Size = UDim2.fromOffset(WIDTH, h)
	Panel.shownX = hudSize.X - WIDTH - 12
	Panel.hiddenX = hudSize.X + 20
	Panel.root.Position = UDim2.fromOffset(if Panel.isOpen then Panel.shownX else Panel.hiddenX, Panel.top)
end

local function clear()
	for _, c in Panel.body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	Panel.rows = {}
end

local function card(order: number, height: number, color: Color3?)
	local c = Kit.rect(Panel.body, 0, 0, WIDTH - 28, height, color or Theme.PanelLight, { LayoutOrder = order, ZIndex = 14 })
	Kit.corner(c, 16)
	Kit.stroke(c, Theme.Ink, 2)
	return c
end

local function buyButton(parent, x, y, w, h, onClick)
	local b = Kit.button(parent, { Name = "Buy", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Theme.Green, ZIndex = 16 }, onClick)
	Kit.corner(b, 14)
	Kit.stroke(b, Theme.Ink, 2.5)
	local t = Kit.label(b, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = 21, RichText = true, ZIndex = 17 })
	Kit.outlined(t, Theme.Ink, 1.8)
	return b, t
end

local function stageData(state, stage, index)
	if stage == "shaft" then
		return state.shafts[index], Config.Shafts[index].Value
	end
	return state[stage], 1
end

local function needMore(button: GuiObject, price: number)
	Kit.shake(button)
	local have = App.state and App.state.money or 0
	App.emit("toast", "Need " .. money(price - have) .. " more!", Theme.Red)
end

-- (Re)builds the rows for a stage.
local function populate()
	local state = App.state
	local stage, index = Panel.stage, Panel.index
	clear()
	local data, value = stageData(state, stage, index)
	if not data then
		return
	end
	local defs = Config.Upgrades[stage]
	-- headline stats
	local rates = Panel.rates(state)
	local info = card(1, 70, Theme.Panel)
	local infoLabel = Kit.label(info, { Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(WIDTH - 56, 58), TextWrapped = true, Text = "", TextSize = 17, Font = Theme.Body, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15 })
	Panel.infoLabel = infoLabel
	-- how many levels a Buy press gets
	local modeBar = card(2, 50, Theme.Panel)
	modeBar.Name = "BuyMode"
	Kit.label(modeBar, { Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(90, 50), Text = "BUY", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15 })
	Panel.modeButtons = {}
	for k, mode in { 1, 10, "max" } do
		local b = Kit.button(modeBar, { Name = "Mode_" .. tostring(mode), Position = UDim2.fromOffset(100 + (k - 1) * 92, 7), Size = UDim2.fromOffset(84, 36), BackgroundColor3 = Theme.PanelLight, ZIndex = 16 }, function()
			Panel.buyMode = mode
			Panel.refresh()
		end)
		Kit.corner(b, 12)
		Kit.stroke(b, Theme.Ink, 2)
		local l = Kit.label(b, { Size = UDim2.fromScale(1, 1), Text = if mode == "max" then "MAX" else "x" .. mode, TextSize = 19, ZIndex = 17 })
		Kit.outlined(l, Theme.Ink, 1.5)
		Panel.modeButtons[mode] = b
	end
	for order, def in defs do
		local row = card(order + 2, 92)
		local icon = Kit.rect(row, 10, 14, 64, 64, Theme.Panel, { ZIndex = 15 })
		Kit.corner(icon, 14)
		Kit.label(icon, { Size = UDim2.fromScale(1, 1), Text = ICONS[def.Id] or "\u{25B2}", TextSize = 32, TextColor3 = Theme.Gold, ZIndex = 16 })
		local name = Kit.label(row, { Position = UDim2.fromOffset(84, 8), Size = UDim2.fromOffset(196, 26), Text = def.Label, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15 })
		local level = Kit.label(row, { Position = UDim2.fromOffset(84, 32), Size = UDim2.fromOffset(196, 20), Text = "", TextSize = 15, Font = Theme.Body, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 200, 225), ZIndex = 15 })
		local change = Kit.label(row, { Position = UDim2.fromOffset(84, 54), Size = UDim2.fromOffset(180, 30), Text = "", TextSize = 15, Font = Theme.Body, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextColor3 = Color3.fromRGB(170, 255, 170), ZIndex = 15 })
		local refs = { def = def, level = level, change = change, name = name }
		row.Name = "Row_" .. def.Id
		refs.button, refs.text = buyButton(row, WIDTH - 28 - 128, 18, 116, 56, function()
			local price = refs.price
			if not price then
				return
			end
			if (App.state.money or 0) < price then
				needMore(refs.button, price)
				return
			end
			if App.gate and not App.gate("buy", stage, index, def.Id) then
				return
			end
			App.request("buy", stage, index, def.Id, refs.count or 1)
			App.emit("buyClicked", stage, index, def.Id)
		end)
		refs.button.Name = "Buy_" .. def.Id
		Panel.rows[def.Id] = refs
	end
	-- manager card
	local mgr = card(10, 112, Color3.fromRGB(70, 58, 98))
	mgr.Name = "ManagerCard"
	local holder = Kit.rect(mgr, 12, 14, 70, 70, Color3.new(), { BackgroundTransparency = 1, ZIndex = 15 })
	Figures.portrait(holder, 70, if stage == "shaft" then Color3.fromRGB(150, 90, 200) elseif stage == "elevator" then Theme.Blue else Theme.Green)
	for _, d in holder:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 4
		end
	end
	Kit.label(mgr, { Position = UDim2.fromOffset(92, 8), Size = UDim2.fromOffset(170, 26), Text = "Manager", TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15 })
	local what = if stage == "shaft" then "Keeps your miners digging, no taps needed." elseif stage == "elevator" then "Runs the elevator on its own." else "Keeps the cart delivering on its own."
	Kit.label(mgr, { Position = UDim2.fromOffset(92, 34), Size = UDim2.fromOffset(170, 70), Text = what, TextSize = 14, Font = Theme.Body, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(225, 215, 245), ZIndex = 15 })
	local mrefs = {}
	mrefs.button, mrefs.text = buyButton(mgr, WIDTH - 28 - 128, 26, 116, 60, function()
		local price = mrefs.price
		if not price then
			return
		end
		if (App.state.money or 0) < price then
			needMore(mrefs.button, price)
			return
		end
		if App.gate and not App.gate("hire", stage, index) then
			return
		end
		App.request("hire", stage, index)
	end)
	mrefs.button.Name = "Hire"
	Panel.manager = mrefs
	-- footer: the three stages side by side
	local foot = card(20, 112, Theme.Panel)
	Kit.label(foot, { Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(WIDTH - 56, 22), Text = "WHOLE MINE (coins per second)", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 200, 225), ZIndex = 15 })
	Panel.bars = {}
	for k, key in { "shafts", "elevator", "warehouse" } do
		local y = 30 + (k - 1) * 26
		Kit.label(foot, { Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(100, 22), Text = ({ "Mining", "Elevator", "Warehouse" })[k], TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 15 })
		local track = Kit.rect(foot, 110, y + 4, 180, 16, Color3.fromRGB(20, 22, 32), { ZIndex = 15 })
		Kit.corner(track, 8)
		local fill = Kit.rect(track, 0, 0, 180, 16, Theme.Green, { ZIndex = 16 })
		Kit.corner(fill, 8)
		local val = Kit.label(foot, { Position = UDim2.fromOffset(296, y), Size = UDim2.fromOffset(90, 22), Text = "", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 15 })
		Panel.bars[key] = { fill = fill, val = val }
	end
	Panel.refresh()
end

-- Updates prices, levels and colours without rebuilding (safe while a finger is down).
function Panel.refresh()
	if not Panel.isOpen or not App.state then
		return
	end
	local state = App.state
	local stage, index = Panel.stage, Panel.index
	local data, value = stageData(state, stage, index)
	if not data then
		Panel.close()
		return
	end
	local rates = Panel.rates(state)
	for mode, b in Panel.modeButtons or {} do
		b.BackgroundColor3 = if Panel.buyMode == mode then Theme.Gold else Theme.PanelLight
	end
	for id, refs in Panel.rows do
		local def = refs.def
		local lv = data[def.Id]
		-- plan the purchase: x1, x10, or as many as the player can afford (at least one)
		local limit = if Panel.buyMode == "max" then 200 else Panel.buyMode
		local count, total = 0, 0
		while count < limit do
			local p = F.price(def, lv + count, value)
			if not p then
				break
			end
			if Panel.buyMode == "max" and count > 0 and total + p > state.money then
				break
			end
			total += p
			count += 1
		end
		local price = if count > 0 then total else nil
		refs.price, refs.count = price, count
		local show = ROWS[stage][def.Id]
		local now = show(index, data, state)
		refs.name.Text = if def.Id == "workers" then def.Label .. "  " .. lv .. "/" .. def.Max else def.Label .. "  Lv " .. lv
		refs.level.Text = def.Info
		if price then
			local nextData = table.clone(data)
			nextData[def.Id] = lv + count
			refs.change.Text = now .. "  \u{2192}  " .. show(index, nextData, state)
			local can = state.money >= price
			refs.button.BackgroundColor3 = if can then Theme.Green else Theme.Grey
			refs.text.Text = if count > 1 then string.format('%s<br/><font size="14">+%d levels</font>', money(price), count) else money(price)
		else
			refs.change.Text = now .. "  (max)"
			refs.button.BackgroundColor3 = Theme.Gold
			refs.text.Text = "MAX"
		end
	end
	local mprice = if stage == "shaft" then Config.Shafts[index].ManagerCost elseif stage == "elevator" then Config.Managers.Elevator else Config.Managers.Warehouse
	if data.manager then
		Panel.manager.price = nil
		Panel.manager.button.BackgroundColor3 = Theme.Gold
		Panel.manager.text.Text = "AUTO \u{2713}"
	else
		Panel.manager.price = mprice
		Panel.manager.button.BackgroundColor3 = if state.money >= mprice then Theme.Green else Theme.Grey
		Panel.manager.text.Text = "Hire " .. money(mprice)
	end
	-- headline
	if stage == "shaft" then
		local st = F.shaft(index, data)
		Panel.infoLabel.Text = string.format("%d %s \u{00B7} %s ore per trip \u{00B7} %s per trip\nThis shaft digs %s/s of ore when kept busy.", st.miners, if st.miners == 1 then "miner" else "miners", F.short(st.ore), secs(st.trip), money(st.valuePerSecond))
	elseif stage == "elevator" then
		local e = F.elevator(data)
		Panel.infoLabel.Text = string.format("Cage holds %s ore \u{00B7} %s round trip\nIt can lift about %s/s of ore.", F.short(e.capacity), secs(rates.eTrip), money(rates.elevator))
	else
		local w = F.warehouse(data)
		Panel.infoLabel.Text = string.format("Cart holds %s ore \u{00B7} %s per trip\nIt can sell about %s/s of ore.", F.short(w.capacity), secs(w.trip), money(rates.warehouse))
	end
	local top = math.max(rates.shafts, rates.elevator, rates.warehouse, 0.001)
	local low = math.min(rates.shafts, rates.elevator, rates.warehouse)
	for key, bar in Panel.bars do
		local r = rates[key]
		bar.fill.Size = UDim2.fromOffset(math.max(10, 180 * r / top), 16)
		bar.fill.BackgroundColor3 = if r <= low + 1e-6 then Theme.Red else Theme.Green
		bar.val.Text = money(r) .. "/s"
	end
end

function Panel.open(stage: string, index: number)
	if not App.state then
		return
	end
	Panel.stage, Panel.index = stage, index
	Panel.isOpen = true
	local name, color
	if stage == "shaft" then
		local def = Config.Shafts[index]
		name, color = "Shaft " .. index .. " \u{00B7} " .. def.Name, def.Color:Lerp(Color3.new(0, 0, 0), 0.25)
		Panel.subtitle.Text = "Each piece of ore here is worth $" .. F.short(def.Value)
	elseif stage == "elevator" then
		name, color = "Elevator", Theme.Blue
		Panel.subtitle.Text = "Collects the richest ore first, from the bottom up"
	else
		name, color = "Warehouse", Color3.fromRGB(220, 130, 40)
		Panel.subtitle.Text = "Carries the pile inside and sells it"
	end
	Panel.title.Text = string.upper(name)
	Panel.header.BackgroundColor3 = color
	Panel.header.Square.BackgroundColor3 = color
	Panel.root.Visible = true
	populate()
	Kit.tween(Panel.root, 0.25, { Position = UDim2.fromOffset(Panel.shownX or 0, Panel.top or 76) }, Enum.EasingStyle.Back)
	App.emit("panelOpened", stage, index)
end

function Panel.close()
	if not Panel.isOpen then
		return
	end
	Panel.isOpen = false
	local t = Kit.tween(Panel.root, 0.18, { Position = UDim2.fromOffset(Panel.hiddenX or 2000, Panel.top or 76) })
	t.Completed:Connect(function()
		if not Panel.isOpen then
			Panel.root.Visible = false
		end
	end)
	App.emit("panelClosed")
end

return Panel
