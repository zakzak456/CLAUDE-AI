-- Colours and fonts in one place.

local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.Body = Enum.Font.GothamBold

Theme.Sky = { Color3.fromRGB(96, 178, 255), Color3.fromRGB(196, 232, 255) }
Theme.Grass = Color3.fromRGB(108, 200, 78)
Theme.GrassDark = Color3.fromRGB(72, 160, 58)
Theme.Hill = { Color3.fromRGB(128, 206, 108), Color3.fromRGB(98, 182, 92) }
Theme.Dirt = { -- by depth, top to bottom
	Color3.fromRGB(176, 116, 70), Color3.fromRGB(156, 100, 62), Color3.fromRGB(136, 86, 56),
	Color3.fromRGB(116, 74, 52), Color3.fromRGB(98, 64, 50), Color3.fromRGB(82, 56, 50), Color3.fromRGB(66, 48, 48),
}
Theme.Tunnel = Color3.fromRGB(222, 176, 122)
Theme.TunnelShade = Color3.fromRGB(196, 146, 96)
Theme.Plank = Color3.fromRGB(150, 98, 56)
Theme.Beam = Color3.fromRGB(128, 82, 46)
Theme.Rock = Color3.fromRGB(92, 74, 64)
Theme.RockDark = Color3.fromRGB(58, 46, 42)
Theme.Shaft = Color3.fromRGB(46, 36, 34)
Theme.Rail = Color3.fromRGB(120, 110, 100)
Theme.Cage = Color3.fromRGB(255, 196, 46)
Theme.Wood = Color3.fromRGB(170, 112, 62)
Theme.WoodDark = Color3.fromRGB(122, 78, 42)
Theme.Brick = Color3.fromRGB(214, 106, 76)
Theme.Roof = Color3.fromRGB(70, 92, 150)

Theme.Ink = Color3.fromRGB(44, 30, 22)
Theme.Panel = Color3.fromRGB(34, 38, 54)
Theme.PanelLight = Color3.fromRGB(52, 58, 80)
Theme.Gold = Color3.fromRGB(255, 202, 58)
Theme.Green = Color3.fromRGB(74, 196, 98)
Theme.GreenDark = Color3.fromRGB(46, 150, 70)
Theme.Red = Color3.fromRGB(232, 84, 72)
Theme.Grey = Color3.fromRGB(118, 124, 140)
Theme.Blue = Color3.fromRGB(70, 150, 245)
Theme.White = Color3.new(1, 1, 1)
Theme.Skin = { Color3.fromRGB(255, 210, 170), Color3.fromRGB(222, 166, 120), Color3.fromRGB(170, 116, 80) }

return Theme
