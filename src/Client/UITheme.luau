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
	ShadowLight    = Color3.fromRGB(48, 40, 36),
	ShadowDark     = Color3.fromRGB(14, 12, 10),
	TextPrimary    = Color3.fromRGB(245, 239, 230),
	TextDim        = Color3.fromRGB(160, 148, 140),
	TextGold       = Color3.fromRGB(234, 179, 8),
	
	-- Accents
	Cash           = Color3.fromRGB(249, 115, 22),
	Gems           = Color3.fromRGB(56, 189, 248),
	Diamonds       = Color3.fromRGB(244, 114, 182),
	Positive       = Color3.fromRGB(249, 115, 22),
	Negative       = Color3.fromRGB(248, 113, 113),
	VoidFace       = Color3.fromRGB(90, 78, 70),
	Multiplier     = Color3.fromRGB(249, 115, 22),
	PurpleAscend   = Color3.fromRGB(168, 85, 247),
	
	-- The board's felt, in the shared 3D scene the dice are thrown into.
	--
	-- DELIBERATELY LIGHTER AND WARMER THAN `BaseCream`, which is the full-screen
	-- backdrop the tray sits on. The felt was drawn in `PanelDeep` at first --
	-- RGB(20,16,14) against a backdrop of RGB(26,22,20) -- a six-point difference
	-- no eye resolves, so the table vanished and the dice read as floating in
	-- space rather than lying on a surface. A board the dice are thrown ONTO has
	-- to be visibly a thing they are on.
	--
	-- Kept dark regardless, so a die's own colour is what draws the eye, and
	-- pitched to sit just inside the bronze tray border RGB(56,44,36) so the felt
	-- reads as the surface inside the frame rather than as a second frame.
	Felt           = Color3.fromRGB(42, 33, 27),

	-- Legacy
	PanelDark      = Color3.fromRGB(26, 22, 20),
	PanelMaroon    = Color3.fromRGB(36, 30, 26),
	PanelDeep      = Color3.fromRGB(20, 16, 14),
	BorderGold     = Color3.fromRGB(234, 179, 8),
	BorderDim      = Color3.fromRGB(28, 22, 18),
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

UITheme.Icons = {
	SettingsGear = "rbxassetid://99435608372494", -- Custom Ethereal Gold Tech Gear Icon (Uploaded Asset)
}

--------------------------------------------------------------------------------
-- THE SCALE
--
-- One 4px-based ladder for every gap, inset, radius and type size in the game.
--
-- WHY THIS EXISTS. Before it, every panel invented its own numbers -- 0.03 here,
-- 10px there, 0.545 somewhere else -- and the result was not merely inconsistent
-- but overlapping: the SHAPES card placed a status label spanning x 0.44-0.66
-- and an action button starting at x 0.585, so "OWNED" was drawn straight
-- through "USE 5<>". The SHOP card had the same collision vertically, its small
-- print struck through its blurb. Neither was a styling mistake; both were two
-- hand-picked numbers that happened to intersect, with nothing in the code able
-- to notice.
--
-- A scale alone does not prevent that -- LAYOUTS do, and the builders below use
-- UIListLayout so sibling content occupies disjoint tracks by construction. The
-- scale is what keeps those tracks looking like one designer chose them.
--
-- Values are PIXELS. Scale-relative sizing stretches a gap on a monitor and
-- crushes it on a phone; a 12px gutter is 12px everywhere, which is what makes
-- spacing read as deliberate across resolutions (NFR-3).
--------------------------------------------------------------------------------

UITheme.Scale = {
	-- Spacing ladder.
	XS = 4,
	SM = 8,
	MD = 12,
	LG = 16,
	XL = 24,
	XXL = 32,

	-- Corner radii. Cards are gently rounded; controls are pill-round.
	RadiusCard = 10,
	RadiusControl = 8,

	-- Type ladder. At most four sizes on any one screen (ui_ux_design skill S1).
	TextTitle = 22,
	TextHeading = 17,
	TextBody = 14,
	TextSmall = 12,

	-- The accessibility floor. 44px is the platform minimum for a touch target
	-- and is NOT negotiable per build tier (ui_ux_design skill S3). Every
	-- interactive element built here is at least this tall.
	TouchTarget = 44,

	-- Standard row height for a list item carrying a title, a subtitle and an
	-- action. Comfortably above the touch floor with room for two text lines.
	RowHeight = 76,
}

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

	-- THE TOUCH FLOOR, APPLIED IN THE BUILDER RATHER THAN AT EACH CALL SITE.
	--
	-- Almost every caller sizes these in SCALE, which is a statement about
	-- proportion and says nothing about whether a thumb can hit the result. The
	-- HUD's menu buttons measure 40px on a 420px-wide phone and the AUTO toggle
	-- 29px -- both under the 44px platform minimum, on the controls a player uses
	-- most. Patching them one at a time leaves the next scale-sized button to
	-- rediscover it; the constraint belongs where the button is made.
	--
	-- A MINIMUM only. Buttons larger than the floor are untouched, so this
	-- changes nothing on a desktop and rescues the small screens.
	local floor = Instance.new("UISizeConstraint")
	floor.Name = "TouchFloor"
	floor.MinSize = Vector2.new(UITheme.Scale.TouchTarget, UITheme.Scale.TouchTarget)
	floor.Parent = container

	-- Shadow Offsets use a subtle, compact 3px pixel offset
	local offset = 3

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
	shadowLight.BackgroundTransparency = 0
	shadowLight.Visible = true
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
	-- NAMED so callers can restyle it. The button's visible text is THIS LABEL,
	-- not the TextButton's own `.Text`, which is deliberately empty. Setting
	-- `button.Text = "..."` therefore renders unstyled text UNDERNEATH the label
	-- instead of updating it -- correct-looking in a screenshot, wrong font and
	-- wrong size next to any button built with its text up front. Callers that
	-- change a label at runtime must use `UITheme.setButtonText`.
	lbl.Name = "Label"
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

	-- Subtle, compact 3px shadow offset
	local offset = 3

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
	shadowLight.BackgroundTransparency = 0
	shadowLight.Visible = true
	shadowLight.BorderSizePixel = 0
	shadowLight.ZIndex = 1
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.5, 0)
	c2.Parent = shadowLight
	shadowLight.Parent = container

	local body = Instance.new("Frame")
	-- NAMED so a child's instance path does not pass through an anonymous rung.
	-- A path is only addressable if EVERY level of it is, and one unnamed frame
	-- in the middle makes the whole chain ambiguous.
	body.Name = "Body"
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
	-- A LIGHT SCRIM. It exists to say "the panel is in front and the board is
	-- not currently yours to touch", and that reads at a much lower strength
	-- than it first appears.
	--
	-- Tuned DOWN from 0.45, which the operator described as everything having a
	-- black shade behind it. At that strength the felt and the dice all but
	-- disappeared, so opening any panel felt like leaving the game rather than
	-- layering something over it. At 0.72 the board stays legible underneath --
	-- which is the point, since the numbers on it are what most panels are
	-- about -- while the panel still clearly sits in front.
	-- IT MUST COVER THE WHOLE SCREEN, INCLUDING ABOVE THE INSET.
	--
	-- The overlay ScreenGui respects the topbar inset -- that is what centres
	-- the panel correctly -- so its canvas begins BELOW the topbar. A scrim at
	-- `fromScale(1, 1)` therefore stopped short of the top and left an
	-- undimmed strip across it: measured, the scrim spanned y 0..723 of a 780px
	-- screen while the HUD's currency bar sits at y -42, outside it entirely.
	-- That bright band above a dimmed page is the "black outline surrounding
	-- but not covering the top" the operator reported -- the HUD stayed at full
	-- brightness while everything below it dimmed.
	--
	-- Growing the frame upward by the inset and sizing it to match covers the
	-- real screen. The panel is unaffected: it centres on the CANVAS, which is
	-- still the visible region, so this dims more without moving anything.
	-- Grown at BOTH ends. Covering only the top left the scrim 57px short of the
	-- bottom, because the canvas is already shorter than the screen by the
	-- inset -- so the frame needs the inset back at the top AND the same amount
	-- again at the bottom to reach y = screenHeight. Generous on both sides
	-- rather than exact: over-covering is invisible, under-covering is the
	-- bright band being fixed here.
	local INSET_COVER = 80

	local fullOverlay = Instance.new("Frame")
	fullOverlay.Size = UDim2.new(1, 0, 1, INSET_COVER * 2)
	fullOverlay.Position = UDim2.new(0, 0, 0, -INSET_COVER)
	fullOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	fullOverlay.BackgroundTransparency = 0.72
	fullOverlay.Visible = false
	fullOverlay.ZIndex = UITheme.Layer.Overlay

	-- CAPPED IN PIXELS AS WELL AS SCALED. At a flat 0.85 the panel stretched to
	-- fill an ultrawide monitor, giving cards a metre of empty width and text
	-- lines too long to track. Content has a comfortable maximum measure.
	local container = Instance.new("Frame")
	container.Name = "Panel"
	-- Header, divider and body are anchored to one another in pixels rather than
	-- arranged by a layout -- disjoint bands by construction. Declared so the
	-- overlap rule can tell a deliberate exception from an oversight.
	container:SetAttribute("LayoutExempt", true)
	-- Height discounts the extra the scrim gained at both ends, so the panel
	-- stays the size it was before the scrim was grown.
	container.Size = UDim2.new(0.86, 0, 0.86, -INSET_COVER * 2 * 0.86)
	container.AnchorPoint = Vector2.new(0.5, 0.5)

	container.Position = UDim2.fromScale(0.5, 0.5)
	container.BackgroundColor3 = UITheme.Colors.BaseCream
	container.BorderSizePixel = 0
	container.ZIndex = UITheme.Layer.Overlay + 1
	container.Parent = fullOverlay


	-- A FLOOR AS WELL AS A CEILING, and the floor is the one that matters for
	-- content-dense panels.
	--
	-- At a flat 0.86 the panel is only as tall as the window allows, and the
	-- FORGE needs a fixed amount of chrome regardless: a tab strip, a die
	-- header, a readout, a cost line and an action bar come to roughly 160px
	-- before a single face row is drawn. Measured on a 276px-tall window the
	-- body was 174px, leaving the face list THIRTY-TWO pixels -- less than one
	-- row of a panel whose entire purpose is editing rows.
	--
	-- BOUNDED BY THE VIEWPORT, not a bare constant. A hard 420px minimum would
	-- simply push the panel off a genuinely small screen, trading a cramped
	-- panel for an unreachable one. This asks for 420px and accepts less when
	-- less is all there is, so the panel grows to usable on any window that can
	-- afford it and never exceeds the window that cannot.
	-- ONE CONSTRAINT CARRYING BOTH BOUNDS. Two `UISizeConstraint`s on the same
	-- instance do not compose -- only one takes effect -- so the floor and the
	-- ceiling have to share an object.
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.Name = "PanelBounds"
	sizeCap.MaxSize = Vector2.new(900, 1100)
	sizeCap.Parent = container

	local function fitBounds()
		local vp = fullOverlay.AbsoluteSize
		if vp.Y <= 0 then
			return
		end
		sizeCap.MinSize = Vector2.new(
			math.min(320, vp.X),
			math.min(420, vp.Y))
	end
	fitBounds()
	fullOverlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBounds)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UITheme.Scale.LG)
	corner.Parent = container

	-- A 1px EDGE, not a 4px band. The heavy stroke read as a border drawn around
	-- the panel; a hairline reads as the panel's own edge.
	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.ShadowLight
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = container

	-- THE HEADER IS A FIXED PIXEL BAND, not a fraction of the panel.
	--
	-- At `0.08` scale the title was 40px tall on a monitor and 22px on a phone,
	-- and because it was `TextScaled` the words changed size with the panel --
	-- so the same screen read as two different designs depending on the display.
	-- A fixed band with a fixed type size is what makes the chrome consistent.
	local HEADER_H = 56

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.BackgroundTransparency = 1
	header.ZIndex = UITheme.Layer.Overlay + 2
	header.Parent = container

	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, UITheme.Scale.XL)
	headerPad.PaddingRight = UDim.new(0, UITheme.Scale.MD)
	headerPad.Parent = header

	-- Title and close button in a layout, so a long title shortens instead of
	-- running underneath the close button.
	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.Padding = UDim.new(0, UITheme.Scale.MD)
	headerLayout.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(0, 0, 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = UITheme.FontHeading
	titleLabel.Text = title
	titleLabel.TextColor3 = UITheme.Colors.TextPrimary
	titleLabel.TextSize = UITheme.Scale.TextTitle
	titleLabel.TextScaled = false
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.LayoutOrder = 1
	titleLabel.ZIndex = UITheme.Layer.Overlay + 3
	titleLabel.Parent = header

	local titleFlex = Instance.new("UIFlexItem")
	titleFlex.FlexMode = Enum.UIFlexMode.Fill
	titleFlex.Parent = titleLabel

	-- A REAL 44px TARGET. It was `0.08` of the panel wide and `0.8` tall, which
	-- on a phone is roughly 26px -- under the touch floor, and the close control
	-- is the one every player needs to hit.
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.fromOffset(UITheme.Scale.TouchTarget, UITheme.Scale.TouchTarget)
	closeBtn.BackgroundColor3 = UITheme.Colors.PanelMaroon
	closeBtn.BackgroundTransparency = 0.35
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = UITheme.FontHeading
	-- A MULTIPLICATION SIGN, not a capital X. The letter is a letter -- it sits
	-- on the text baseline and reads as a word, which is why the old header
	-- looked like it had a stray character in the corner.
	closeBtn.Text = "\u{00D7}"
	closeBtn.TextColor3 = UITheme.Colors.TextDim
	closeBtn.TextSize = 24
	closeBtn.TextScaled = false
	closeBtn.AutoButtonColor = false
	closeBtn.LayoutOrder = 2
	closeBtn.ZIndex = UITheme.Layer.Overlay + 3
	closeBtn.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, UITheme.Scale.RadiusControl)
	closeCorner.Parent = closeBtn

	-- Hover and press states. Closing is the one control on every panel, and a
	-- control that never acknowledges the cursor reads as decoration.
	closeBtn.MouseEnter:Connect(function()
		closeBtn.TextColor3 = UITheme.Colors.Negative
		closeBtn.BackgroundTransparency = 0.15
	end)
	closeBtn.MouseLeave:Connect(function()
		closeBtn.TextColor3 = UITheme.Colors.TextDim
		closeBtn.BackgroundTransparency = 0.35
	end)

	-- A HAIRLINE UNDER THE HEADER. Without it the title floated over the content
	-- with nothing separating chrome from body, which is most of why these
	-- panels read as unfinished.
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, -UITheme.Scale.XL * 2, 0, 1)
	divider.Position = UDim2.new(0, UITheme.Scale.XL, 0, HEADER_H)
	divider.BackgroundColor3 = UITheme.Colors.ShadowLight
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.ZIndex = UITheme.Layer.Overlay + 2
	divider.Parent = container

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
	-- ANCHORED TO THE HEADER IN PIXELS, so the gap between chrome and content is
	-- the same on every display. The scale-based `0.1` offset it used to carry
	-- left a growing dead band on tall screens and clipped into the title on
	-- short ones.
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, -(HEADER_H + UITheme.Scale.SM))
	body.Position = UDim2.new(0, 0, 0, HEADER_H + UITheme.Scale.SM)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ZIndex = UITheme.Layer.Overlay + 2
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.fromScale(0, 0)
	body.ScrollBarThickness = 6
	body.ScrollBarImageColor3 = UITheme.Colors.ShadowLight
	body.ScrollBarImageTransparency = 0.4
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

-- THE SANCTIONED WAY TO BIND A BUTTON PRESS.
--
-- Binds BOTH `Activated` and `MouseButton1Click`, debounced so the two firing
-- for one press runs the handler once.
--
-- WHY BOTH. `Activated` does not fire in every input path -- notably it can be
-- missed for a synthetic/driven click and behaves differently across input
-- devices -- while `MouseButton1Click` covers the ordinary mouse case. The HUD
-- has always bound both and its buttons work; V7MenuPanel bound `Activated`
-- alone in nine places and those buttons were unreachable to a driven click,
-- which is also how a real player on some input devices would find them.
--
-- Found 2026-08-12 while trying to verify the ASCEND confirm: the panel
-- rendered correctly, the button was topmost and interactable, the coordinates
-- were right, and pressing it did nothing at all.
function UITheme.onPressed(button: TextButton, handler: () -> ()): ()
	local last = 0
	local function trigger()
		local now = os.clock()
		if now - last < 0.12 then
			return
		end
		last = now
		local ok, err = pcall(handler)
		if not ok then
			warn("[UITheme] button handler errored: " .. tostring(err))
		end
	end
	button.Activated:Connect(trigger)
	button.MouseButton1Click:Connect(trigger)
end

-- SMALL PRINT. A fine, dim, non-scaling line for tier and entitlement notes
-- (operator-directed 2026-08-13: "every detail which differentiates standard vip
-- and premium users is mentioned in a small font wherever its needed").
--
-- DELIBERATELY NOT `TextScaled`. Every other label in this UI scales to fill its
-- box, which is right for figures the player is meant to read at a glance and
-- wrong for a footnote -- scaled small print grows to shout on a large screen
-- and shrinks to nothing on a phone. A fixed size keeps it subordinate to the
-- number it is annotating at every resolution.
--
-- One helper rather than each panel inventing its own, so "small print" stays
-- one visual weight across the game instead of five near-misses.
function UITheme.smallPrint(text: string, size: UDim2, position: UDim2, colour: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font
	label.TextSize = 12
	label.TextScaled = false
	label.TextWrapped = true
	label.TextColor3 = colour or UITheme.Colors.TextDim
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 5
	return label
end

-- The sanctioned way to change a neumorphic button's caption at runtime.
--
-- Falls back to the button's own Text for any button not built by
-- `neumorphicButton`, so callers do not have to know which builder made it.
function UITheme.setButtonText(button: TextButton, text: string): ()
	local lbl = button:FindFirstChild("Label")
	if lbl ~= nil and lbl:IsA("TextLabel") then
		lbl.Text = text
	else
		button.Text = text
	end
end

-- Greys a button out AND STOPS IT FIRING.
--
-- TWO DEFECTS FIXED HERE, both of which made "disabled" purely decorative:
--
--   IT RECOLOURED THE WRONG THING. `button.TextColor3` tints the TextButton's
--   own text, which for a neumorphic button is empty -- the visible caption is a
--   child label. A disabled button looked identical to an enabled one.
--
--   IT NEVER DISABLED INPUT. `AutoButtonColor` is a HOVER TINT, not an
--   interaction switch. Every `Activated` handler still fired, so a button
--   reading LOCKED or MAX still sent its request -- the server refused it, which
--   is why nothing visibly broke, but the client was asking for things it had
--   just told the player it could not do.
--
-- `Active` and `Interactable` are what actually gate input.
function UITheme.setEnabled(button: TextButton, enabled: boolean): ()
	button.AutoButtonColor = enabled
	button.Active = enabled
	button.Interactable = enabled

	-- A TOGGLE HAS NO CAPTION, so the label branch below could not dim it and the
	-- fallback recoloured `TextColor3` on a button whose Text is empty -- meaning
	-- `setEnabled(false)` on a switch changed NOTHING visible. A disabled toggle
	-- was pixel-identical to an enabled one sitting in the off position, so
	-- "you cannot change this" and "this is currently off" looked the same.
	local knob = button:FindFirstChild("Knob")
	if knob ~= nil and knob:IsA("Frame") then
		knob.BackgroundTransparency = if enabled then 0 else 0.6
		button.BackgroundTransparency = if enabled then 0 else 0.5
		return
	end

	local lbl = button:FindFirstChild("Label")
	if lbl ~= nil and lbl:IsA("TextLabel") then
		lbl.TextTransparency = if enabled then 0 else 0.55
	else
		button.TextColor3 = if enabled then UITheme.Colors.TextPrimary else UITheme.Colors.TextDim
	end

	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if enabled then UITheme.Colors.ShadowDark else UITheme.Colors.BaseCream
	end
end

-- A PILL SWITCH. Returns the container, the clickable button, and a setter.
--
-- WHY A SWITCH AND NOT A BUTTON READING "ON"/"OFF". A caption is ambiguous in
-- exactly the place it matters: a button labelled "OFF" reads either as the
-- current state or as what pressing it will do, and players guess wrong roughly
-- half the time. A knob that physically sits on one side has no such reading --
-- left is off, right is on, and the colour reinforces it.
--
-- THE SETTER IS RETURNED RATHER THAN THE STATE BEING OWNED HERE, deliberately.
-- A settings toggle must never flip on its own click: the server owns the value,
-- and the switch shows what the last snapshot said. Optimistically flipping and
-- then correcting on the next snapshot is what makes a refused write look like a
-- toggle that "sometimes doesn't stick".
function UITheme.toggle(size: UDim2, position: UDim2): (Frame, TextButton, (boolean) -> ())
	local container = Instance.new("Frame")
	container.Name = "Toggle"
	container.Size = size
	container.Position = position
	container.BackgroundTransparency = 1

	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = UITheme.Colors.ShadowDark
	track.BorderSizePixel = 0
	track.Text = ""
	track.AutoButtonColor = false
	track.ZIndex = 4
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromScale(0.46, 0.84)
	knob.Position = UDim2.fromScale(0.04, 0.08)
	-- A LIGHT knob, fixed in both states. It was `BaseCream` (26,22,20), which in
	-- this dark palette is very nearly the same colour as `ShadowDark` (14,12,10)
	-- -- so an OFF switch was a near-black knob on a near-black track inside a
	-- near-black row, and the control simply disappeared. Only the ON state was
	-- legible, which is the worst way round: a player cannot see the setting they
	-- just turned off.
	knob.BackgroundColor3 = UITheme.Colors.TextPrimary
	knob.BorderSizePixel = 0
	knob.ZIndex = 5
	knob.Parent = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local function setState(on: boolean): ()
		-- OFF is `ShadowLight`, not `ShadowDark`: the track has to stay visible
		-- against the row behind it, so that "off" reads as a switch in the off
		-- position rather than as an empty patch of panel.
		track.BackgroundColor3 = if on then UITheme.Colors.Positive else UITheme.Colors.ShadowLight
		local target = UDim2.fromScale(if on then 0.50 else 0.04, 0.08)

		-- SNAP WHEN NOT YET RENDERED, tween when it is.
		--
		-- `TweenPosition` RAISES -- "Can only tween objects in the workspace" --
		-- for a GuiObject that is not under a rendered tree, and the very first
		-- call is always in that state: the builder sets the initial position
		-- before the caller has parented anything. That error propagated out of
		-- `V7MenuPanel.new()` and destroyed the ENTIRE menu layer: shop, shapes,
		-- boards, ascend, quests, vault, settings and slots, all eight overlays,
		-- gone because a switch tried to animate a frame too early.
		--
		-- The suite did not catch it and could not have: it requires the module,
		-- which resolves every symbol, but `new()` needs a LocalPlayer and the
		-- suite runs server-side. Module scope was safe; construction was not.
		if knob:IsDescendantOf(game) then
			-- The movement is what tells the player the press registered, which
			-- matters because the value is confirmed a round trip later and a
			-- motionless switch reads as a dead control in between.
			knob:TweenPosition(target, Enum.EasingDirection.Out,
				Enum.EasingStyle.Quad, 0.12, true)
		else
			knob.Position = target
		end
	end

	setState(false)
	return container, track, setState
end

function UITheme.elementColor(elementId: string): Color3
	return (UITheme.ElementColors and UITheme.ElementColors[elementId]) or UITheme.Colors.TextDim
end

--------------------------------------------------------------------------------
-- LAYOUT PRIMITIVES
--
-- These exist to make overlapping content IMPOSSIBLE rather than merely
-- unlikely. Every builder below arranges its children with a UIListLayout, so
-- two siblings cannot occupy the same pixels no matter what text arrives at
-- runtime -- which is the failure mode hand-placed scale coordinates have, and
-- the reason the shop and shapes panels had text drawn through their buttons.
--
-- The rule they encode: a container either POSITIONS its children with a layout,
-- or it holds exactly one child. Never a mix of hand-placed siblings.
--------------------------------------------------------------------------------

-- A vertical stack. Children are laid out top to bottom with a uniform gap and
-- a uniform inset, and the canvas grows to fit them.
--
-- `parent` may be a ScrollingFrame, in which case AutomaticCanvasSize is already
-- doing the work and this just supplies the rhythm.
function UITheme.verticalStack(parent: Instance, gap: number?, inset: number?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Name = "Stack"
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap or UITheme.Scale.MD)
	layout.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.Name = "StackPadding"
	local i = inset or UITheme.Scale.LG
	pad.PaddingTop = UDim.new(0, i)
	pad.PaddingBottom = UDim.new(0, i)
	pad.PaddingLeft = UDim.new(0, i)
	pad.PaddingRight = UDim.new(0, i)
	pad.Parent = parent

	return layout
end

-- A CARD: one surface holding one idea.
--
-- Returns the card and its CONTENT frame. Callers parent into the content
-- frame, never into the card itself, so the card's padding and its border are
-- not something every call site has to re-derive.
--
-- Fixed pixel height by default because a card's height is set by what it
-- holds, not by the screen it is on -- a 44%-of-panel card is a different thing
-- on a phone and a monitor, and that is exactly how the shop grid ended up with
-- text spilling past its own edges.
-- Passing `height` fixes the card; passing nil lets it GROW TO ITS CONTENT,
-- with `Scale.RowHeight` as the floor.
--
-- The growing form is the right default for anything holding wrapped prose. A
-- fixed height is a resolution assumption: the same blurb occupies one line on a
-- monitor and three on a phone, so a card sized for the first clips on the
-- second -- content escaping its box, which is the exact defect class these
-- primitives exist to make impossible.
function UITheme.card(height: number?): (Frame, Frame)
	local card = Instance.new("Frame")
	card.Name = "Card"
	if height ~= nil then
		card.Size = UDim2.new(1, 0, 0, height)
	else
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		local floor = Instance.new("UISizeConstraint")
		floor.MinSize = Vector2.new(0, UITheme.Scale.RowHeight)
		floor.Parent = card
	end
	card.BackgroundColor3 = UITheme.Colors.PanelMaroon
	card.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UITheme.Scale.RadiusCard)
	corner.Parent = card

	-- A HAIRLINE, not a heavy frame. The old 2px stroke at 50% transparency read
	-- as a box drawn around content rather than as a raised surface; at 1px in a
	-- colour close to the card it reads as an edge catching light.
	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.ShadowLight
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	local content = Instance.new("Frame")
	content.Name = "Content"
	if height ~= nil then
		content.Size = UDim2.fromScale(1, 1)
	else
		-- A `fromScale(1, 1)` child inside an auto-sizing parent is circular --
		-- the parent measures its children while this child measures the parent
		-- -- and resolves to zero. Full width, self-measured height.
		content.Size = UDim2.new(1, 0, 0, 0)
		content.AutomaticSize = Enum.AutomaticSize.Y
	end
	content.BackgroundTransparency = 1
	content.Parent = card

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, UITheme.Scale.MD)
	pad.PaddingRight = UDim.new(0, UITheme.Scale.MD)
	pad.PaddingTop = UDim.new(0, UITheme.Scale.SM)
	pad.PaddingBottom = UDim.new(0, UITheme.Scale.SM)
	pad.Parent = content

	return card, content
end

-- A ROW: a text column on the left, an actions column on the right, which
-- CANNOT overlap because a horizontal UIListLayout assigns them disjoint tracks.
--
-- THIS IS THE FIX FOR THE COLLISION CLASS. The shapes card previously placed a
-- status label at x 0.44 width 0.22 and a button at x 0.585 -- a 7.5% overlap
-- that no test could see and that only appeared once the status text was long
-- enough to fill its box. Here the text column is sized by what remains after
-- the actions are measured, so a longer label shortens the text rather than
-- running underneath a button.
--
-- Returns the row, the text column, and the actions column. The actions column
-- is right-aligned and sized to its content.
-- As with `card`, a nil height means "measure yourself from the text column",
-- which is what a row inside a growing card must do.
function UITheme.listRow(height: number?): (Frame, Frame, Frame)
	local row = Instance.new("Frame")
	row.Name = "Row"
	if height ~= nil then
		row.Size = UDim2.new(1, 0, 0, height)
	else
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
	end
	row.BackgroundTransparency = 1

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, UITheme.Scale.MD)
	layout.Parent = row

	-- WHICHEVER AXIS THE ROW DOES NOT FIX, THE COLUMNS MEASURE.
	--
	-- A `1, 0` scale height inside an auto-sizing row is the same circular
	-- measurement as a `fromScale(1, 1)` child inside an auto-sizing card, and
	-- collapses the same way. When the row is self-measuring, the text column is
	-- what determines its height, so the column measures its own stack and the
	-- actions match whatever results.
	local autoHeight = height == nil

	local textCol = Instance.new("Frame")
	textCol.Name = "TextColumn"
	-- Takes the remaining width. `UIFlexItem` is what makes this a real column
	-- rather than a guess: the actions measure themselves first and the text
	-- column absorbs whatever is left, at any resolution.
	textCol.Size = if autoHeight then UDim2.new(0, 0, 0, 0) else UDim2.new(0, 0, 1, 0)
	if autoHeight then
		textCol.AutomaticSize = Enum.AutomaticSize.Y
	end
	textCol.BackgroundTransparency = 1
	textCol.LayoutOrder = 1
	textCol.Parent = row

	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = textCol

	local textStack = Instance.new("UIListLayout")
	textStack.FillDirection = Enum.FillDirection.Vertical
	textStack.SortOrder = Enum.SortOrder.LayoutOrder
	textStack.VerticalAlignment = Enum.VerticalAlignment.Center
	textStack.Padding = UDim.new(0, UITheme.Scale.XS)
	textStack.Parent = textCol

	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	-- Width always measures to the buttons. Height follows the row when the row
	-- is fixed, and measures the buttons when it is not -- an `AutomaticSize.XY`
	-- frame whose only children are 44px buttons is 44px tall, which is the
	-- correct minimum for a self-measuring row.
	actions.AutomaticSize = if autoHeight
		then Enum.AutomaticSize.XY
		else Enum.AutomaticSize.X
	actions.Size = if autoHeight then UDim2.new(0, 0, 0, 0) else UDim2.new(0, 0, 1, 0)
	actions.BackgroundTransparency = 1
	actions.LayoutOrder = 2
	actions.Parent = row

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	actionLayout.Padding = UDim.new(0, UITheme.Scale.SM)
	actionLayout.Parent = actions

	return row, textCol, actions
end

-- A text line for use INSIDE a laid-out column.
--
-- DELIBERATELY NOT `TextScaled`. TextScaled sizes text to its box, which makes
-- every label a different size and is why the old panels read as ransom notes --
-- a card title at 40px next to a row title at 19px, with no intent behind
-- either. A fixed size from the type ladder is what makes a hierarchy legible.
--
-- Height is fixed to the line height so the vertical layout can measure it.
function UITheme.textLine(text: string, size: number, colour: Color3?, weight: Enum.Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.Size = UDim2.new(1, 0, 0, math.floor(size * 1.35 + 0.5))
	label.BackgroundTransparency = 1
	label.Font = weight or UITheme.Font
	label.Text = text
	label.TextSize = size
	label.TextScaled = false
	label.TextColor3 = colour or UITheme.Colors.TextPrimary
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 5
	return label
end

-- A wrapping paragraph that reports its own height, for prose whose length is
-- not known up front. Sized by the layout, not by a guessed fraction.
function UITheme.paragraph(text: string, size: number?, colour: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Paragraph"
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font
	label.Text = text
	label.TextSize = size or UITheme.Scale.TextBody
	label.TextScaled = false
	label.TextWrapped = true
	label.TextColor3 = colour or UITheme.Colors.TextDim
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 5
	return label
end

-- A SOLID ACTION BUTTON, sized to its caption and never below the touch floor.
--
-- WHY NOT `neumorphicButton`. That builder takes a UDim2 size from the caller,
-- which is how a "USE 5<>" caption ended up in a box narrower than its own text
-- while a "BUY" caption got one four times too wide. This one measures the
-- caption and adds padding, so a button is exactly as wide as it needs to be
-- and every button in a row shares one height.
--
-- `emphasis` chooses the visual weight: "primary" is the one dominant action on
-- a screen, "secondary" is subordinate, "quiet" is a text-weight action. Exactly
-- one primary per screen (ui_ux_design skill S1).
function UITheme.actionButton(text: string, emphasis: string, accent: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.new(0, 0, 0, UITheme.Scale.TouchTarget)
	button.Font = UITheme.FontHeading
	button.Text = text
	button.TextSize = UITheme.Scale.TextBody
	button.TextScaled = false
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.ZIndex = 6

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, UITheme.Scale.LG)
	pad.PaddingRight = UDim.new(0, UITheme.Scale.LG)
	pad.Parent = button

	-- A MINIMUM WIDTH as well as a minimum height. A two-character caption like
	-- "OK" would otherwise produce a button narrower than the touch floor even
	-- with padding, which passes a height check and still cannot be hit.
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(UITheme.Scale.TouchTarget, UITheme.Scale.TouchTarget)
	sizeConstraint.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UITheme.Scale.RadiusControl)
	corner.Parent = button

	local tone = accent or UITheme.Colors.Cash
	if emphasis == "primary" then
		button.BackgroundColor3 = tone
		button.BackgroundTransparency = 0
		-- Dark ink on a saturated fill. White on orange fails the 4.5:1 contrast
		-- floor at this type size; the panel's own near-black clears it easily.
		button.TextColor3 = UITheme.Colors.PanelDeep
	elseif emphasis == "secondary" then
		button.BackgroundColor3 = UITheme.Colors.BaseCream
		button.BackgroundTransparency = 0
		button.TextColor3 = tone
		local stroke = Instance.new("UIStroke")
		stroke.Color = tone
		stroke.Thickness = 1
		stroke.Transparency = 0.4
		stroke.Parent = button
	else
		button.BackgroundTransparency = 1
		button.TextColor3 = UITheme.Colors.TextDim
	end

	-- PRESSED STATE IS MANDATORY (ui_ux_design skill S3: every interactive
	-- element has a visible pressed state).
	--
	-- THE PRESS AND THE DISABLED DIM MUST NOT SHARE A CHANNEL. Both wanted
	-- `TextTransparency`, and because the press handlers restored a value
	-- captured at CONSTRUCTION, moving the cursor across a disabled button fired
	-- `MouseLeave` and reset it to fully opaque -- so a greyed-out FORGE button
	-- repainted itself as enabled while staying unclickable. `Interactable =
	-- false` does not suppress hover signals, so the handler still ran.
	--
	-- The press therefore paints a CHILD overlay instead, leaving
	-- `TextTransparency` to mean one thing only: whether the control is
	-- available. Two states, two properties, no interference.
	local press = Instance.new("Frame")
	press.Name = "PressVeil"
	press.Size = UDim2.fromScale(1, 1)
	press.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	press.BackgroundTransparency = 1
	press.BorderSizePixel = 0
	press.Visible = false
	press.ZIndex = button.ZIndex + 1
	press.Parent = button

	local pressCorner = Instance.new("UICorner")
	pressCorner.CornerRadius = UDim.new(0, UITheme.Scale.RadiusControl)
	pressCorner.Parent = press

	button.MouseButton1Down:Connect(function()
		press.BackgroundTransparency = 0.72
		press.Visible = true
	end)
	button.MouseButton1Up:Connect(function()
		press.Visible = false
	end)
	button.MouseLeave:Connect(function()
		press.Visible = false
	end)

	return button
end

-- A STATUS PILL: a short state word in its own tinted chip.
--
-- Replaces the bare coloured text that used to sit loose next to buttons. A
-- word like "OWNED" in orange next to a button in orange reads as part of the
-- button; in a chip it reads as a state, which is what it is. Colour is never
-- the only signal (skill S3) -- the chip's presence and its text both carry it.
function UITheme.statusPill(text: string, colour: Color3): Frame
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AutomaticSize = Enum.AutomaticSize.X
	-- Height from the ladder, not a magic 22: small text plus a step of padding
	-- above and below, so a chip stays proportional if the type scale moves.
	pill.Size = UDim2.new(0, 0, 0, UITheme.Scale.TextSmall + UITheme.Scale.SM)
	pill.BackgroundColor3 = colour
	pill.BackgroundTransparency = 0.82
	pill.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, UITheme.Scale.SM)
	pad.PaddingRight = UDim.new(0, UITheme.Scale.SM)
	pad.Parent = pill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = UITheme.FontHeading
	label.Text = text
	label.TextSize = UITheme.Scale.TextSmall
	label.TextScaled = false
	label.TextColor3 = colour
	label.ZIndex = 6
	label.Parent = pill

	return pill
end

-- Repoints a pill built by `statusPill` at a new state.
function UITheme.setPill(pill: Frame, text: string, colour: Color3): ()
	pill.BackgroundColor3 = colour
	local label = pill:FindFirstChild("Label")
	if label ~= nil and label:IsA("TextLabel") then
		label.Text = text
		label.TextColor3 = colour
	end
end

-- THE LAYOUT CONTRACT, as a function rather than as a claim.
--
-- WHY THIS IS HERE. The panels' defining defect was overlapping siblings, and
-- the natural acceptance criterion -- "no two elements in a card intersect" --
-- cannot be checked by this project's suite: `new()` needs a LocalPlayer and the
-- suite runs server-side, so no panel can be constructed and no AbsoluteSize
-- measured (L-036). An acceptance criterion that cannot be evaluated is not a
-- criterion, and asserting it anyway is how a green suite comes to certify a
-- property nobody tested (L-051).
--
-- So the property is restated as something checkable. Overlap is impossible when
-- a container positions its children with a layout; it is possible exactly when
-- siblings are hand-placed. This function answers the question the suite CAN
-- ask: does this container arbitrate its own children?
--
-- It takes an instance and is called on live panels by the in-Studio checks, and
-- its RULE is asserted by the suite against synthetic containers -- which is the
-- part that runs everywhere.
function UITheme.arbitratesChildren(container: Instance): boolean
	-- A layout of any direction assigns disjoint tracks.
	if container:FindFirstChildOfClass("UIListLayout") ~= nil
		or container:FindFirstChildOfClass("UIGridLayout") ~= nil
		or container:FindFirstChildOfClass("UIPageLayout") ~= nil
		or container:FindFirstChildOfClass("UITableLayout") ~= nil then
		return true
	end

	-- PIXEL-ANCHORED CHROME IS THE ONE EXEMPTION, and it is declared rather than
	-- assumed. The overlay's own container holds a header, a divider and a body
	-- at fixed pixel offsets computed from one header height -- bands that cannot
	-- overlap because each begins where the last ends, but which no layout
	-- arbitrates. Requiring a layout there would mean nesting the scrolling body
	-- inside another list for no benefit.
	--
	-- Opting in EXPLICITLY, by name, is what keeps this from becoming a hole:
	-- a container claiming the exemption has to say so, and "someone marked this
	-- deliberately" is auditable in a way that a silent pass is not.
	if container:GetAttribute("LayoutExempt") == true then
		return true
	end

	-- Otherwise it is safe only while it holds at most one positioned child.
	-- Non-GuiObjects (UICorner, UIStroke, UIPadding, constraints) do not occupy
	-- layout space and are not counted.
	local positioned = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			positioned += 1
			if positioned > 1 then
				return false
			end
		end
	end
	return true
end

-- Enables or disables a button built by `actionButton`.
--
-- Separate from `setEnabled`, which knows about neumorphic buttons and toggles.
-- This one dims the whole control uniformly, which is correct here because the
-- caption IS the button rather than a child label.
function UITheme.setActionEnabled(button: TextButton, enabled: boolean): ()
	button.Active = enabled
	button.Interactable = enabled
	button.TextTransparency = if enabled then 0 else 0.55
	button.BackgroundTransparency = if button.BackgroundTransparency >= 1
		then 1
		else (if enabled then 0 else 0.6)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke ~= nil then
		stroke.Transparency = if enabled then 0.4 else 0.8
	end
end

return UITheme
