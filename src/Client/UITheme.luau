--!strict
-- UITheme.luau (Neumorphic Engine - Bugfix & Scale Fix)
-- Fixed offset distortions by using Absolute Pixels instead of Scale for shadows.
-- Fixed Z-indexing to ensure text and buttons are visible over shadows.

local UITheme = {}

--------------------------------------------------------------------------------
-- Palette (Neumorphic Ethereal)
--------------------------------------------------------------------------------

UITheme.Colors = {
	BaseCream      = Color3.fromRGB(26, 22, 20),
	ShadowLight    = Color3.fromRGB(65, 54, 49),
	ShadowDark     = Color3.fromRGB(14, 12, 10),
	TextPrimary    = Color3.fromRGB(245, 239, 230),
	TextDim        = Color3.fromRGB(160, 148, 140),
	TextGold       = Color3.fromRGB(234, 179, 8),
	
	-- Accents
	Cash           = Color3.fromRGB(249, 115, 22),
	Gems           = Color3.fromRGB(56, 189, 248),
	Diamonds       = Color3.fromRGB(234, 179, 8),
	Positive       = Color3.fromRGB(249, 115, 22),
	Negative       = Color3.fromRGB(248, 113, 113),
	VoidFace       = Color3.fromRGB(90, 78, 70),
	Multiplier     = Color3.fromRGB(249, 115, 22),
	PurpleAscend   = Color3.fromRGB(168, 85, 247),
	
	-- Legacy
	PanelDark      = Color3.fromRGB(26, 22, 20),
	PanelMaroon    = Color3.fromRGB(48, 40, 36),
	PanelDeep      = Color3.fromRGB(20, 16, 14),
	BorderGold     = Color3.fromRGB(234, 179, 8),
	BorderDim      = Color3.fromRGB(65, 54, 49),
	PrimaryCyan    = Color3.fromRGB(249, 115, 22),
}

UITheme.ElementColors = {
	None       = Color3.fromRGB(180, 190, 205),
	Fire       = Color3.fromRGB(240, 130, 130),
	Freeze     = Color3.fromRGB(130, 190, 250),
	Gold       = Color3.fromRGB(240, 190, 100),
	Multiplier = Color3.fromRGB(130, 220, 170),
}

UITheme.Font = Enum.Font.GothamMedium
UITheme.FontHeading = Enum.Font.GothamBlack
UITheme.FontMono = Enum.Font.Code
UITheme.BorderThickness = 1

UITheme.Layer = {
	Arena   = 0,
	HUD     = 10,
	Sidebar = 20,
	Overlay = 30,
	Toast   = 40,
	Fatal   = 1000,
}

--------------------------------------------------------------------------------
-- V9 "Neumorphic" Builders
--------------------------------------------------------------------------------

function UITheme.neumorphicButton(text: string, accentColor: Color3?, size: UDim2, position: UDim2): (Frame, TextButton)
	local container = Instance.new("Frame")
	container.Size = size
	container.Position = position
	container.BackgroundTransparency = 1
	container.ZIndex = 1

	-- Shadow Offsets must use PIXELS so they don't stretch based on aspect ratio!
	local offset = 6

	local shadowDark = Instance.new("Frame")
	shadowDark.Size = UDim2.fromScale(1, 1)
	shadowDark.Position = UDim2.new(0, offset, 0, offset)
	shadowDark.BackgroundColor3 = UITheme.Colors.ShadowDark
	shadowDark.BorderSizePixel = 0
	shadowDark.ZIndex = 1
	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(0.4, 0)
	c1.Parent = shadowDark
	shadowDark.Parent = container

	local shadowLight = Instance.new("Frame")
	shadowLight.Size = UDim2.fromScale(1, 1)
	shadowLight.Position = UDim2.new(0, -offset, 0, -offset)
	shadowLight.BackgroundColor3 = UITheme.Colors.ShadowLight
	shadowLight.BorderSizePixel = 0
	shadowLight.ZIndex = 1
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.4, 0)
	c2.Parent = shadowLight
	shadowLight.Parent = container

	local body = Instance.new("TextButton")
	body.Size = UDim2.fromScale(1, 1)
	body.Position = UDim2.fromScale(0, 0)
	body.BackgroundColor3 = UITheme.Colors.BaseCream
	body.BorderSizePixel = 0
	body.Text = ""
	body.AutoButtonColor = false
	body.ZIndex = 2
	local c3 = Instance.new("UICorner")
	c3.CornerRadius = UDim.new(0.4, 0)
	c3.Parent = body
	
	if accentColor then
		local tint = Instance.new("Frame")
		tint.Size = UDim2.fromScale(1, 1)
		tint.BackgroundColor3 = accentColor
		tint.BackgroundTransparency = 0.85
		tint.BorderSizePixel = 0
		tint.ZIndex = 3
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(0.4, 0)
		tc.Parent = tint
		tint.Parent = body
	end

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(0.9, 0.6)
	lbl.Position = UDim2.fromScale(0.05, 0.2)
	lbl.BackgroundTransparency = 1
	lbl.Font = UITheme.FontHeading
	lbl.Text = text
	lbl.TextColor3 = accentColor or UITheme.Colors.TextPrimary
	lbl.TextScaled = true
	lbl.ZIndex = 4
	lbl.Parent = body

	body.Parent = container
	
	body.MouseButton1Down:Connect(function()
		shadowDark.Visible = false
		shadowLight.Visible = false
		body.BackgroundColor3 = UITheme.Colors.ShadowDark
	end)
	body.MouseButton1Up:Connect(function()
		shadowDark.Visible = true
		shadowLight.Visible = true
		body.BackgroundColor3 = UITheme.Colors.BaseCream
	end)
	body.MouseLeave:Connect(function()
		shadowDark.Visible = true
		shadowLight.Visible = true
		body.BackgroundColor3 = UITheme.Colors.BaseCream
	end)

	return container, body
end

function UITheme.neumorphicPod(size: UDim2, position: UDim2): (Frame, Frame)
	local container = Instance.new("Frame")
	container.Size = size
	container.Position = position
	container.BackgroundTransparency = 1
	container.ZIndex = 1

	local offset = 8

	local shadowDark = Instance.new("Frame")
	shadowDark.Size = UDim2.fromScale(1, 1)
	shadowDark.Position = UDim2.new(0, offset, 0, offset)
	shadowDark.BackgroundColor3 = UITheme.Colors.ShadowDark
	shadowDark.BorderSizePixel = 0
	shadowDark.ZIndex = 1
	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(0.5, 0)
	c1.Parent = shadowDark
	shadowDark.Parent = container

	local shadowLight = Instance.new("Frame")
	shadowLight.Size = UDim2.fromScale(1, 1)
	shadowLight.Position = UDim2.new(0, -offset, 0, -offset)
	shadowLight.BackgroundColor3 = UITheme.Colors.ShadowLight
	shadowLight.BorderSizePixel = 0
	shadowLight.ZIndex = 1
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.5, 0)
	c2.Parent = shadowLight
	shadowLight.Parent = container

	local body = Instance.new("Frame")
	body.Size = UDim2.fromScale(1, 1)
	body.Position = UDim2.fromScale(0, 0)
	body.BackgroundColor3 = UITheme.Colors.BaseCream
	body.BorderSizePixel = 0
	body.ZIndex = 2
	local c3 = Instance.new("UICorner")
	c3.CornerRadius = UDim.new(0.5, 0)
	c3.Parent = body

	body.Parent = container
	return container, body
end

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
	label.ZIndex = 5
	return label
end

function UITheme.createProgrammaticIcon(iconType: string, size: UDim2, position: UDim2, parent: Instance): Frame
	local container = Instance.new("Frame")
	container.Size = size
	container.Position = position
	container.BackgroundTransparency = 1
	container.ZIndex = 5
	container.Parent = parent
	
	local shape = Instance.new("Frame")
	shape.AnchorPoint = Vector2.new(0.5, 0.5)
	shape.Position = UDim2.fromScale(0.5, 0.5)
	shape.BorderSizePixel = 0
	shape.ZIndex = 6
	shape.Parent = container

	if iconType == "Cash" then
		shape.Size = UDim2.fromScale(0.7, 0.4)
		shape.BackgroundColor3 = UITheme.Colors.Cash
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = shape
		
	elseif iconType == "Gems" or iconType == "Diamonds" then
		shape.Size = UDim2.fromScale(0.6, 0.6)
		shape.BackgroundColor3 = if iconType == "Gems" then UITheme.Colors.Gems else UITheme.Colors.Diamonds
		shape.Rotation = 45
		
	elseif iconType == "Dice" then
		shape.Size = UDim2.fromScale(0.6, 0.6)
		shape.BackgroundColor3 = UITheme.Colors.TextPrimary
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = shape
	end

	return container
end

-- ==========================================
-- LEGACY METHODS (Recolored for Light Mode)
-- ==========================================

function UITheme.panel(size: UDim2, position: UDim2, dark: boolean?): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = UITheme.Colors.BaseCream
	frame.BorderSizePixel = 0
	frame.ZIndex = 2

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.ShadowDark
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Transparency = 0.5
	stroke.Parent = frame

	return frame
end

function UITheme.overlay(title: string): (Frame, Frame, TextButton)
	local fullOverlay = Instance.new("Frame")
	fullOverlay.Size = UDim2.fromScale(1, 1)
	fullOverlay.Position = UDim2.fromScale(0, 0)
	fullOverlay.BackgroundColor3 = UITheme.Colors.BaseCream
	fullOverlay.BackgroundTransparency = 0.2
	fullOverlay.Visible = false
	fullOverlay.ZIndex = UITheme.Layer.Overlay

	local container = Instance.new("Frame")
	container.Size = UDim2.fromScale(0.85, 0.85)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.BackgroundColor3 = UITheme.Colors.BaseCream
	container.BorderSizePixel = 0
	container.ZIndex = UITheme.Layer.Overlay + 1
	container.Parent = fullOverlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.ShadowLight
	stroke.Thickness = 4
	stroke.Parent = container

	local header = Instance.new("Frame")
	header.Size = UDim2.fromScale(1, 0.08)
	header.BackgroundTransparency = 1
	header.ZIndex = UITheme.Layer.Overlay + 2
	header.Parent = container

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.fromScale(0.8, 1)
	titleLabel.Position = UDim2.fromScale(0.02, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = UITheme.FontHeading
	titleLabel.Text = title
	titleLabel.TextColor3 = UITheme.Colors.TextPrimary
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = UITheme.Layer.Overlay + 3
	titleLabel.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromScale(0.08, 0.8)
	closeBtn.Position = UDim2.fromScale(0.9, 0.1)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Font = UITheme.Font
	closeBtn.Text = "X"
	closeBtn.TextColor3 = UITheme.Colors.Negative
	closeBtn.TextScaled = true
	closeBtn.ZIndex = UITheme.Layer.Overlay + 3
	closeBtn.Parent = header

	closeBtn.MouseButton1Click:Connect(function()
		fullOverlay.Visible = false
	end)

	-- THE BODY SCROLLS. It was a plain Frame, and every overlay whose content was
	-- taller than the panel simply CLIPPED -- the shop rendered eleven purchasable
	-- items into six rows of a grid and the player could reach two of them, with
	-- no indication the rest existed.
	--
	-- AutomaticCanvasSize means callers do not have to compute their own content
	-- height; adding a row to any overlay just works. Any UIGridLayout or
	-- UIListLayout inside contributes to the canvas automatically.
	local body = Instance.new("ScrollingFrame")
	body.Size = UDim2.fromScale(0.96, 0.88)
	body.Position = UDim2.fromScale(0.02, 0.1)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ZIndex = UITheme.Layer.Overlay + 2
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.fromScale(0, 0)
	body.ScrollBarThickness = 8
	body.ScrollBarImageColor3 = UITheme.Colors.ShadowLight
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	body.Parent = container

	return fullOverlay, body, closeBtn
end

function UITheme.button(text: string, size: UDim2, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Text = text
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = UITheme.Colors.BaseCream
	button.BorderSizePixel = 0
	button.Font = UITheme.Font
	button.TextScaled = true
	button.TextColor3 = UITheme.Colors.TextPrimary
	button.AutoButtonColor = true
	button.ZIndex = 5

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.ShadowDark
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	return button
end

-- A rounded square pod (for dice tiles and square icons)
function UITheme.neumorphicTile(size: UDim2, pos: UDim2): (Frame, Frame)
	local container = Instance.new("Frame")
	container.Size = size
	container.Position = pos
	container.BackgroundTransparency = 1

	-- The Highlight (Top-Left)
	local highlight = Instance.new("Frame")
	highlight.Size = UDim2.fromScale(1, 1)
	highlight.Position = UDim2.fromOffset(-3, -3)
	highlight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	highlight.BorderSizePixel = 0
	highlight.ZIndex = 1
	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0.15, 0)
	hCorner.Parent = highlight
	highlight.Parent = container

	-- The Shadow (Bottom-Right)
	local shadow = Instance.new("Frame")
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(3, 3)
	shadow.BackgroundColor3 = UITheme.Colors.BorderDim
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0.15, 0)
	sCorner.Parent = shadow
	shadow.Parent = container

	-- The Base Body
	local body = Instance.new("Frame")
	body.Size = UDim2.fromScale(1, 1)
	body.Position = UDim2.fromScale(0, 0)
	body.BackgroundColor3 = UITheme.Colors.BaseCream
	body.BorderSizePixel = 0
	body.ZIndex = 2
	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0.15, 0)
	bCorner.Parent = body
	body.Parent = container

	return container, body
end

function UITheme.setEnabled(button: TextButton, enabled: boolean): ()
	button.TextColor3 = if enabled then UITheme.Colors.TextPrimary else UITheme.Colors.TextDim
	button.AutoButtonColor = enabled
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if enabled then UITheme.Colors.ShadowDark else UITheme.Colors.BaseCream
	end
end

function UITheme.elementColor(elementId: string): Color3
	return (UITheme.ElementColors and UITheme.ElementColors[elementId]) or UITheme.Colors.TextDim
end

return UITheme
