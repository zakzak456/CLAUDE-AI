-- Small helpers for building the 2D world and the interface out of Frames.
-- Everything is laid out in design units; a UIScale on the parent does the rest.

local TweenService = game:GetService("TweenService")

local Kit = {}

function Kit.new(class: string, props, parent: Instance?)
	local o = Instance.new(class)
	for k, v in props or {} do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

-- A plain rectangle at (x, y) with size (w, h).
function Kit.rect(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	for k, v in props or {} do
		f[k] = v
	end
	f.Parent = parent
	return f
end

function Kit.corner(o: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0)
	c.Parent = o
	return c
end

function Kit.stroke(o: Instance, color: Color3, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

function Kit.gradient(o: Instance, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = o
	return g
end

function Kit.label(parent: Instance, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextSize = 20
	for k, v in props or {} do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- Outlined text that stays readable on any background.
function Kit.outlined(l: TextLabel, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(40, 28, 20)
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = l
	return s
end

-- A button that squashes a little when pressed.
function Kit.button(parent: Instance, props, onClick)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 20
	b.Text = ""
	for k, v in props or {} do
		b[k] = v
	end
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
	b.Activated:Connect(function()
		if Kit.onAnyClick then
			Kit.onAnyClick()
		end
	end)
	if onClick then
		b.Activated:Connect(onClick)
	end
	b.Parent = parent
	return b
end

-- A quick sideways shake (for "can't afford").
function Kit.shake(o: GuiObject)
	local base = o.Position
	task.spawn(function()
		for i = 1, 6 do
			o.Position = base + UDim2.fromOffset(if i % 2 == 0 then -6 else 6, 0)
			task.wait(0.035)
		end
		o.Position = base
	end)
end

function Kit.tween(o: Instance, time: number, props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(o, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

return Kit
