-- Sound effects. Licensed library sounds (Pro Sound Effects and APM Music, free in
-- the Creator Store) plus Roblox's built-in client sounds. Each sound has a small
-- random pitch range and a minimum gap so busy mines don't turn into noise.

local SoundService = game:GetService("SoundService")
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Sfx = {}
Sfx.enabled = true

local DEFS = {
	pick = { id = "rbxassetid://9118608412", volume = 0.18, pitch = { 1.05, 1.3 }, gap = 0.09 }, -- Rock Hits (Pro Sound Effects)
	drop = { id = "rbxassetid://9117271802", volume = 0.3, pitch = { 1.0, 1.2 }, gap = 0.18 }, -- Pebbles On Wood (Pro Sound Effects)
	chain = { id = "rbxassetid://9113760542", volume = 0.35, pitch = { 0.9, 1.05 }, gap = 0.3 }, -- Chain Movement (Pro Sound Effects)
	coin = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, pitch = { 1.25, 1.45 }, gap = 0.08 },
	buy = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45, pitch = { 1.6, 1.7 }, gap = 0.05 },
	click = { id = "rbxasset://sounds/clickfast.wav", volume = 0.5, pitch = { 0.95, 1.05 }, gap = 0.04 },
	deny = { id = "rbxasset://sounds/button.wav", volume = 0.45, pitch = { 0.55, 0.6 }, gap = 0.15 },
	fanfare = { id = "rbxassetid://9040476898", volume = 0.5, pitch = { 1, 1 }, gap = 1 }, -- Early Bird - Hit1 (APM Music)
	pop = { id = "rbxasset://sounds/snap.mp3", volume = 0.4, pitch = { 1.1, 1.3 }, gap = 0.05 },
}

local sounds = {}
local last = {}

function Sfx.play(name: string)
	if not Sfx.enabled then
		return
	end
	local def, s = DEFS[name], sounds[name]
	if not def or not s then
		return
	end
	local now = os.clock()
	if last[name] and now - last[name] < def.gap then
		return
	end
	last[name] = now
	s.PlaybackSpeed = def.pitch[1] + math.random() * (def.pitch[2] - def.pitch[1])
	SoundService:PlayLocalSound(s)
end

function Sfx.init(App)
	local folder = Instance.new("Folder")
	folder.Name = "MineSfx"
	folder.Parent = SoundService
	for name, def in DEFS do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.id
		s.Volume = def.volume
		s.Parent = folder
		sounds[name] = s
	end
	App.play = Sfx.play
	Kit.onAnyClick = function()
		Sfx.play("click")
	end
	App.on("fx", function(kind, a, b)
		if kind == "deposit" or kind == "unload" then
			Sfx.play("drop")
		elseif kind == "load" then
			if (b or 0) > 0 then
				Sfx.play("drop")
			end
		elseif kind == "sell" then
			Sfx.play("coin")
		elseif kind == "bought" then
			Sfx.play("buy")
		elseif kind == "hired" or kind == "unlocked" then
			Sfx.play("fanfare")
		elseif kind == "deny" or kind == "empty" then
			Sfx.play("deny")
		end
	end)
	-- a small on/off switch in the bottom-left corner
	local hudRoot = App.Hud.root
	local b = Kit.button(hudRoot, { Name = "SoundToggle", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -14), Size = UDim2.fromOffset(84, 52), BackgroundColor3 = Theme.Green, ZIndex = 5 })
	Kit.corner(b, 16)
	Kit.stroke(b, Theme.Ink, 3)
	local l = Kit.label(b, { Size = UDim2.fromScale(1, 1), Text = "SFX", TextSize = 22, ZIndex = 6 })
	Kit.outlined(l, Theme.Ink, 1.5)
	b.Activated:Connect(function()
		Sfx.enabled = not Sfx.enabled
		b.BackgroundColor3 = if Sfx.enabled then Theme.Green else Theme.Grey
		l.Text = if Sfx.enabled then "SFX" else "SFX OFF"
		b.Size = UDim2.fromOffset(if Sfx.enabled then 84 else 120, 52)
	end)
end

return Sfx
