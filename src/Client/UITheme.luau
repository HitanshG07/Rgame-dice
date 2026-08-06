--!strict
-- UITheme.luau
-- The single source of visual truth for every 2D surface (SRS FR-13.1).
--
-- WHY THIS EXISTS BEFORE THE PANELS DO. FR-13.1 specifies "dark maroon and
-- charcoal panels, 1-pixel gold borders, monospace pixel type". Three separate
-- modules building panels from that sentence would produce three different
-- maroons, and the interface would read as three interfaces. Worse, nothing
-- would flag it: every panel would individually satisfy the requirement.
--
-- So the palette is data, declared once, and the panel builders below are the
-- only sanctioned way to make a framed surface. A module that constructs its own
-- Frame with its own Color3 is not breaking a test -- it is quietly forking the
-- design, which is exactly the failure a shared constant prevents.
--
-- READ-ONLY TO EVERY VIEW MODULE. This file is written by the orchestrator and
-- never by a view module, which is what keeps the view modules disjoint from
-- one another.
--
-- LAYOUT LAW (FR-13.7, NFR-3): Scale-based sizing ONLY, never fixed Offset,
-- except for 1-pixel borders and UIStroke thickness where a pixel IS the intent.
-- Everything here must render from 320px through 4K without clipping.

local UITheme = {}

--------------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------------

UITheme.Colors = {
	PanelDark      = Color3.fromRGB(24, 20, 24),   -- charcoal, the base surface
	PanelMaroon    = Color3.fromRGB(46, 18, 26),   -- dark maroon, raised surfaces
	PanelDeep      = Color3.fromRGB(14, 12, 15),   -- recessed wells and insets
	BorderGold     = Color3.fromRGB(196, 158, 72), -- the 1px border, FR-13.1
	BorderDim      = Color3.fromRGB(92, 74, 40),   -- inactive/disabled border
	TextPrimary    = Color3.fromRGB(236, 226, 208),
	TextDim        = Color3.fromRGB(150, 140, 126),
	TextGold       = Color3.fromRGB(226, 190, 104),
	Cash           = Color3.fromRGB(226, 190, 104),
	Gems           = Color3.fromRGB(120, 196, 220),
	Diamonds       = Color3.fromRGB(198, 150, 232),
	Positive       = Color3.fromRGB(126, 196, 122),
	Negative       = Color3.fromRGB(206, 96, 92),
	VoidFace       = Color3.fromRGB(88, 84, 92),   -- a face that pays nothing
}

-- Element tints. Keys match ElementCatalog ids exactly; a mismatch here means a
-- face renders untinted rather than erroring, so UT-13's catalog-alignment check
-- is what actually guards it.
UITheme.ElementColors = {
	None       = Color3.fromRGB(150, 140, 126),
	Fire       = Color3.fromRGB(224, 118, 62),
	Freeze     = Color3.fromRGB(120, 196, 220),
	Gold       = Color3.fromRGB(226, 190, 104),
	Multiplier = Color3.fromRGB(198, 150, 232),
}

UITheme.Font = Enum.Font.Code          -- monospace pixel type, FR-13.1
UITheme.BorderThickness = 1            -- literally 1 pixel, FR-13.1

-- Z-ordering, declared centrally so two panels cannot both decide they are on top.
UITheme.Layer = {
	Arena   = 0,
	HUD     = 10,
	Sidebar = 20,
	Panel   = 30,
	Toast   = 40,
	Fatal   = 1000,
}

--------------------------------------------------------------------------------
-- Builders — the sanctioned way to make a surface
--------------------------------------------------------------------------------

-- A framed panel: charcoal or maroon fill, 1px gold border, no rounded corners.
-- `size` and `position` are UDim2 and MUST be Scale-based (FR-13.7).
function UITheme.panel(size: UDim2, position: UDim2, maroon: boolean?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = if maroon then UITheme.Colors.PanelMaroon else UITheme.Colors.PanelDark
	frame.BorderSizePixel = 0

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.BorderGold
	stroke.Thickness = UITheme.BorderThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	return frame
end

-- Text that scales with its box rather than with a fixed point size, so it stays
-- readable from a phone to a 4K monitor (NFR-3).
function UITheme.label(text: string, size: UDim2, position: UDim2, colour: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font
	label.TextScaled = true
	label.TextColor3 = colour or UITheme.Colors.TextPrimary
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

-- A button in the house style. Returns the TextButton; the caller connects it.
function UITheme.button(text: string, size: UDim2, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Text = text
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = UITheme.Colors.PanelMaroon
	button.BorderSizePixel = 0
	button.Font = UITheme.Font
	button.TextScaled = true
	button.TextColor3 = UITheme.Colors.TextGold
	button.AutoButtonColor = true

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.BorderGold
	stroke.Thickness = UITheme.BorderThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	return button
end

-- Greys a button out without disabling input handling, so a caller can still
-- explain WHY it is unavailable rather than the press silently doing nothing.
function UITheme.setEnabled(button: TextButton, enabled: boolean): ()
	button.TextColor3 = if enabled then UITheme.Colors.TextGold else UITheme.Colors.TextDim
	button.AutoButtonColor = enabled
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if enabled then UITheme.Colors.BorderGold else UITheme.Colors.BorderDim
	end
end

function UITheme.elementColor(elementId: string): Color3
	return UITheme.ElementColors[elementId] or UITheme.Colors.TextDim
end

return UITheme
