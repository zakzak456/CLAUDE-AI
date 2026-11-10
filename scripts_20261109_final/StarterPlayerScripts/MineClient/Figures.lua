-- Little 2D workers built from rounded frames: miners (pickaxe, ore sack), the
-- elevator operator, the transporter (wheelbarrow) and manager portraits. Each
-- worker is drawn facing right; facing left mirrors every part. update() poses
-- the limbs: walking legs and bob, pickaxe swings (reports each strike), and the
-- carried ore.

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Figures = {}

local Worker = {}
Worker.__index = Worker

local R = 34 -- pivot frames are 2R x 2R, rotating around their centre

local function pivot(parent: Instance)
	local p = Instance.new("Frame")
	p.BackgroundTransparency = 1
	p.Size = UDim2.fromOffset(2 * R, 2 * R)
	p.Parent = parent
	return p
end

-- style = { shirt, pants, helmet, skin, tool = "pickaxe" | nil, cart = bool, scale }
function Figures.worker(parent: Instance, style)
	local width = if style.cart then 112 else 64
	local root = Instance.new("Frame")
	root.Name = style.name or "Worker"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Size = UDim2.fromOffset(width, 88)
	root.ZIndex = 5
	local self = setmetatable({ root = root, parts = {}, width = width, facing = 1, style = style, hitPhase = 0 }, Worker)
	local skin = style.skin or Theme.Skin[1]
	local z = 5

	local function part(name, x, y, w, h, color, opts)
		local f = Kit.rect(root, x, y, w, h, color, { Name = name, ZIndex = (opts and opts.z) or z })
		if opts and opts.round then
			Kit.corner(f, opts.round ~= true and opts.round or nil)
		end
		table.insert(self.parts, { inst = f, x = x, y = y, w = w, h = h })
		return f
	end
	local function pivotAt(name, cx, cy, zz)
		local p = pivot(root)
		p.Name = name
		p.ZIndex = zz
		table.insert(self.parts, { inst = p, x = cx - R, y = cy - R, w = 2 * R, h = 2 * R, pivot = true })
		return p
	end

	local shadow = part("Shadow", 14, 82, 36, 8, Color3.new(0, 0, 0), { round = true, z = 4 })
	shadow.BackgroundTransparency = 0.75

	-- legs (rotate at the hips)
	self.legs = {}
	for i, hx in { 26, 37 } do
		local p = pivotAt("Leg" .. i, hx, 58, 5)
		local leg = Kit.rect(p, R - 5, R, 10, 22, style.pants or Color3.fromRGB(60, 80, 140), { ZIndex = 5 })
		Kit.corner(leg, 3)
		local boot = Kit.rect(leg, -1, 16, 13, 8, Color3.fromRGB(70, 48, 34), { ZIndex = 5 })
		Kit.corner(boot, 3)
		self.legs[i] = p
	end

	-- carried ore sack on the back
	self.sack = part("Sack", 4, 28, 22, 26, Color3.fromRGB(190, 150, 100), { round = 9, z = 5 })
	self.sackOre = Kit.rect(self.sack, 4, 3, 14, 10, Color3.new(1, 1, 1), { ZIndex = 6 })
	Kit.corner(self.sackOre, 5)
	self.sack.Visible = false

	local body = part("Body", 18, 32, 28, 30, style.shirt or Color3.fromRGB(240, 140, 40), { round = 9, z = 6 })
	local strap = Kit.rect(body, 6, 0, 5, 30, style.pants or Color3.fromRGB(60, 80, 140), { ZIndex = 6 })
	local strap2 = Kit.rect(body, 17, 0, 5, 30, style.pants or Color3.fromRGB(60, 80, 140), { ZIndex = 6 })
	strap.BackgroundTransparency, strap2.BackgroundTransparency = 0.25, 0.25
	self.body = body

	local head = part("Head", 19, 8, 26, 26, skin, { round = true, z = 7 })
	local eye = part("Eye", 36, 18, 4, 6, Theme.Ink, { round = 2, z = 8 })
	local nose = part("Nose", 42, 21, 5, 5, skin:Lerp(Color3.new(0.6, 0.3, 0.2), 0.3), { round = true, z = 8 })
	self.head, self.eye, self.nose = head, eye, nose
	if style.hat == "manager" then
		local hat = part("Hat", 16, 0, 32, 10, Color3.fromRGB(40, 40, 50), { round = 4, z = 8 })
		part("HatBrim", 12, 8, 40, 4, Color3.fromRGB(40, 40, 50), { round = 2, z = 8 })
		self.helmet = hat
	else
		local dome = part("Helmet", 17, 3, 30, 16, style.helmet or Theme.Gold, { round = 9, z = 8 })
		part("Brim", 15, 15, 36, 5, (style.helmet or Theme.Gold):Lerp(Color3.new(0, 0, 0), 0.15), { round = 2, z = 8 })
		local lamp = part("Lamp", 41, 6, 8, 8, Color3.fromRGB(255, 250, 190), { round = true, z = 9 })
		Kit.stroke(lamp, Color3.fromRGB(120, 90, 30), 1.5)
		self.helmet = dome
	end

	-- the working arm (rotates at the shoulder) with its tool
	local arm = pivotAt("Arm", 33, 40, 9)
	local sleeve = Kit.rect(arm, R - 4, R - 2, 9, 18, style.shirt or Color3.fromRGB(240, 140, 40), { ZIndex = 9 })
	Kit.corner(sleeve, 4)
	local hand = Kit.rect(arm, R - 4, R + 14, 9, 8, skin, { ZIndex = 9 })
	Kit.corner(hand, 4)
	if style.tool == "pickaxe" then
		local handle = Kit.rect(arm, R, R + 15, 34, 5, Color3.fromRGB(150, 96, 52), { ZIndex = 10 })
		Kit.corner(handle, 2)
		local headP = Kit.rect(arm, R + 29, R + 1, 7, 32, Color3.fromRGB(170, 178, 192), { ZIndex = 10 })
		Kit.corner(headP, 3)
		Kit.stroke(headP, Color3.fromRGB(90, 96, 110), 1.5)
	end
	self.arm = arm

	if style.cart then
		local tray = part("CartTray", 62, 50, 44, 18, Theme.Wood, { round = 4, z = 6 })
		Kit.stroke(tray, Theme.WoodDark, 2)
		part("CartHandle", 40, 54, 26, 5, Theme.WoodDark, { round = 2, z = 6 })
		local wheel = part("CartWheel", 82, 64, 18, 18, Color3.fromRGB(60, 56, 60), { round = true, z = 7 })
		Kit.stroke(wheel, Color3.fromRGB(30, 28, 30), 2)
		self.cartOre = part("CartOre", 66, 38, 36, 16, Color3.new(1, 1, 1), { round = 8, z = 5 })
		self.cartOre.Visible = false
		self.wheel = wheel
	end

	root.Parent = parent
	self:setFacing(1)
	return self
end

function Worker:setFacing(f: number)
	if f == self.facing and self.placed then
		return
	end
	self.facing = f
	self.placed = true
	for _, p in self.parts do
		local x = if f > 0 then p.x else self.width - p.x - p.w
		p.inst.Position = UDim2.fromOffset(x, p.y)
	end
end

-- opts: { walking, mining, carrying, carryColor, facing, t, idle }
-- Returns true on the frame a pickaxe strike lands.
function Worker:update(opts)
	local t = opts.t
	local f = opts.facing or self.facing
	self:setFacing(f)
	local hit = false
	local bob = 0
	if opts.walking then
		local s = math.sin(t * 13)
		self.legs[1].Rotation = s * 26
		self.legs[2].Rotation = -s * 26
		bob = math.abs(s) * 2.5
	else
		self.legs[1].Rotation, self.legs[2].Rotation = 0, 0
		bob = if opts.idle then math.sin(t * 2.4) * 1.2 else 0
	end
	local armRot
	if opts.mining then
		local cycle = (t * 2.4) % 1
		if cycle < 0.62 then
			armRot = -20 - 110 * (cycle / 0.62) -- raise
		elseif cycle < 0.74 then
			armRot = -130 + 160 * ((cycle - 0.62) / 0.12) -- strike
		else
			armRot = 30
		end
		local struck = cycle >= 0.74
		if struck and not self.struck then
			hit = true
		end
		self.struck = struck
	elseif opts.lever then
		armRot = -60 + math.sin(t * 3) * 8
	elseif self.style.tool == "pickaxe" then
		armRot = -150 + (if opts.walking then math.sin(t * 13) * 6 else 0) -- over the shoulder
	else
		armRot = (if opts.walking then math.sin(t * 13) * 20 else 0) - 10
	end
	self.arm.Rotation = armRot * f
	self.root.Position = UDim2.fromOffset(opts.x, opts.y - bob)
	local carrying = opts.carrying == true
	if self.style.cart then
		self.cartOre.Visible = carrying
		if carrying then
			self.cartOre.BackgroundColor3 = opts.carryColor or Theme.Gold
		end
		if self.wheel and opts.walking then
			self.wheel.Rotation = (t * 360 * 1.5 * f) % 360
		end
	else
		self.sack.Visible = carrying and self.style.tool == "pickaxe"
		if carrying then
			self.sack.BackgroundColor3 = Color3.fromRGB(196, 152, 98)
			self.sackOre.BackgroundColor3 = opts.carryColor or Theme.Gold
		end
	end
	return hit
end

function Worker:destroy()
	self.root:Destroy()
end

-- A round portrait for manager slots.
function Figures.portrait(parent: Instance, size: number, shirt: Color3)
	local p = Kit.rect(parent, 0, 0, size, size, Color3.fromRGB(255, 236, 190), { Name = "Portrait", ZIndex = 12 })
	Kit.corner(p)
	Kit.stroke(p, Theme.Ink, 3)
	local s = size / 64
	local body = Kit.rect(p, 12 * s, 40 * s, 40 * s, 30 * s, shirt, { ZIndex = 12 })
	Kit.corner(body, 10 * s)
	local tie = Kit.rect(p, 29 * s, 42 * s, 6 * s, 16 * s, Theme.Red, { ZIndex = 13 })
	Kit.corner(tie, 2)
	local head = Kit.rect(p, 18 * s, 12 * s, 28 * s, 28 * s, Theme.Skin[1], { ZIndex = 13 })
	Kit.corner(head)
	Kit.rect(head, 7 * s, 12 * s, 4 * s, 5 * s, Theme.Ink, { ZIndex = 14 })
	Kit.rect(head, 17 * s, 12 * s, 4 * s, 5 * s, Theme.Ink, { ZIndex = 14 })
	local smile = Kit.rect(head, 9 * s, 20 * s, 10 * s, 3 * s, Theme.Ink, { ZIndex = 14 })
	Kit.corner(smile, 2)
	local hat = Kit.rect(p, 16 * s, 6 * s, 32 * s, 9 * s, Color3.fromRGB(40, 40, 50), { ZIndex = 14 })
	Kit.corner(hat, 3)
	Kit.rect(p, 12 * s, 13 * s, 40 * s, 4 * s, Color3.fromRGB(40, 40, 50), { ZIndex = 14 })
	p.ClipsDescendants = true
	return p
end

return Figures
