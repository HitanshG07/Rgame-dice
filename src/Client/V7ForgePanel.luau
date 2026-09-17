--!strict
--[=[
    V7ForgePanel.luau
    THE FORGE: Specimen Calibration Lab & Precision Inverse-Mass Engine (FR-2.3 / FR-3).
    
    Production Architecture:
      - 2-Column Machinist Layout (35% Left Specimen/Telemetry / 65% Right Face Bank).
      - Fullscreen edge-to-edge seamless scrim (IgnoreGuiInset = true, DisplayOrder = 50).
      - Signature V7 modal framing (~ Forge Specimen Calibration ~) with warm gold close button (\u{00D7}).
      - Two-digit slot tab navigation (SLOT 01, SLOT 02... with scroll arrow affordances for >4 slots).
      - Live zero-sum mass allocation caliper controls ([ - ] [ Gauge ] [ + ]).
      - Optimization Presets ([EVEN], [JACKPOT], [SAFE], [RESET]).
      - Real-time EV ($) and Streak Hazard Risk (%) telemetry.
      - Ascending numerical face rows (F1, F2, F3... Fn) with explicit [PRIMARY HAZARD ($0)] distinction.
      - Clean per-die draft lifecycle (switching tabs / unequipping cleanly resets draft without state pollution).
      - Integrated Buy Mass Upgrade progress with live pricing quotes.
      - Strict UITheme casino palette tokens, crisp button borders (ApplyStrokeMode = Border), and zero pixel overflow.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))
local UpgradeCatalog = require(Shared:WaitForChild("UpgradeCatalog"))
local Format = require(Shared:WaitForChild("Format"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local NetClient = require(script.Parent:WaitForChild("NetClient"))

local V7ForgePanel = {}
V7ForgePanel.__index = V7ForgePanel

local STEP = 5
local TAB_WIDTH = 78
local TAB_GAP = 6

export type V7ForgeController = {
	overlay: Frame,
	show: (self: V7ForgeController) -> (),
	hide: (self: V7ForgeController) -> (),
	applyState: (self: V7ForgeController, state: any) -> (),
}

--------------------------------------------------------------------------------
-- THEME DESIGN TOKENS
--------------------------------------------------------------------------------

local FORGE_THEME = {
	Backdrop     = Color3.fromRGB(0, 0, 0),
	ModalBg      = Color3.fromRGB(24, 20, 18),
	HeaderBg     = Color3.fromRGB(34, 28, 24),
	CardBg       = Color3.fromRGB(32, 26, 22),
	CardBgAlt    = Color3.fromRGB(28, 23, 19),
	InsetBg      = Color3.fromRGB(18, 15, 13),
	InsetDark    = Color3.fromRGB(14, 11, 10),
	ButtonDark   = Color3.fromRGB(42, 34, 28),
	ButtonHover  = Color3.fromRGB(56, 46, 38),

	GoldPrimary  = Color3.fromRGB(234, 179, 8),
	GoldBurnished= Color3.fromRGB(185, 148, 65),
	GoldLight    = Color3.fromRGB(250, 204, 21),
	GoldMuted    = Color3.fromRGB(140, 112, 50),

	Cash         = Color3.fromRGB(249, 115, 22),
	Gems         = Color3.fromRGB(56, 189, 248),
	Diamonds     = Color3.fromRGB(244, 114, 182),
	Positive     = Color3.fromRGB(34, 197, 94),
	Negative     = Color3.fromRGB(239, 68, 68),
	VoidHazard   = Color3.fromRGB(220, 38, 38),
	VoidFace     = Color3.fromRGB(90, 78, 70),
	AmberCaution = Color3.fromRGB(245, 158, 11),
	Multiplier   = Color3.fromRGB(249, 115, 22),

	StrokeGold   = Color3.fromRGB(212, 165, 40),
	StrokeSubtle = Color3.fromRGB(55, 45, 38),
	StrokeInset  = Color3.fromRGB(40, 32, 26),

	TextPrimary  = Color3.fromRGB(245, 239, 230),
	TextMuted    = Color3.fromRGB(165, 152, 142),
	TextSubtle   = Color3.fromRGB(125, 118, 110),
	TextDark     = Color3.fromRGB(24, 20, 18),
}

local ELEMENT_COLORS: { [string]: Color3 } = {
	None       = Color3.fromRGB(180, 190, 205),
	Fire       = Color3.fromRGB(240, 130, 130),
	Freeze     = Color3.fromRGB(130, 190, 250),
	Gold       = Color3.fromRGB(240, 190, 100),
	Multiplier = Color3.fromRGB(130, 220, 170),
}

local ELEMENT_ORDER = { "None", "Fire", "Freeze", "Gold", "Multiplier" }
local MAX_FACES = 20

function V7ForgePanel.new(): V7ForgeController
	local player = Players.LocalPlayer
	assert(player ~= nil, "[V7ForgePanel] LocalPlayer must exist")
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "V7ForgeGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 50

	-- Fullscreen Dimmer Backdrop
	local fullOverlay = Instance.new("Frame")
	fullOverlay.Name = "ForgeOverlay"
	fullOverlay.Size = UDim2.fromScale(1, 1)
	fullOverlay.BackgroundColor3 = FORGE_THEME.Backdrop
	fullOverlay.BackgroundTransparency = 0.55
	fullOverlay.BorderSizePixel = 0
	fullOverlay.Visible = false
	fullOverlay.Parent = screenGui
	screenGui.Parent = playerGui

	-- Click backdrop outside modal to close (Standard across all V7 modals)
	local scrimBtn = Instance.new("TextButton")
	scrimBtn.Name = "ScrimDismiss"
	scrimBtn.Size = UDim2.fromScale(1, 1)
	scrimBtn.BackgroundTransparency = 1
	scrimBtn.Text = ""
	scrimBtn.ZIndex = 0
	scrimBtn.Parent = fullOverlay
	scrimBtn.MouseButton1Click:Connect(function()
		fullOverlay.Visible = false
	end)

	-- Modal Frame
	local modal = Instance.new("Frame")
	modal.Name = "ForgeCalibrationModal"
	modal.Size = UDim2.new(0.88, 0, 0.88, -20)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = FORGE_THEME.ModalBg
	modal.BorderSizePixel = 0
	modal.ZIndex = 1
	modal.ClipsDescendants = false
	modal.Parent = fullOverlay

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(780, 540)
	constraint.MaxSize = Vector2.new(1040, 720)
	constraint.Parent = modal

	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 10)
	mCorner.Parent = modal

	local mStroke = Instance.new("UIStroke")
	mStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mStroke.Color = FORGE_THEME.StrokeGold
	mStroke.Thickness = 2
	mStroke.Parent = modal

	----------------------------------------------------------------------------
	-- MODAL HEADER (Harmonized with V7 Modals: ~ Forge Specimen Calibration ~)
	----------------------------------------------------------------------------
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = FORGE_THEME.HeaderBg
	header.BorderSizePixel = 0
	header.Parent = modal

	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 10)
	hCorner.Parent = header

	local hSep = Instance.new("Frame")
	hSep.Name = "HeaderSeparator"
	hSep.Size = UDim2.new(1, 0, 0, 1)
	hSep.Position = UDim2.new(0, 0, 1, -1)
	hSep.BackgroundColor3 = FORGE_THEME.StrokeGold
	hSep.BorderSizePixel = 0
	hSep.Parent = header

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.60, 0, 1, 0)
	title.Position = UDim2.new(0, 18, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 17
	title.TextColor3 = FORGE_THEME.GoldPrimary
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "~ Forge Specimen Calibration ~"
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(0.35, -48, 1, 0)
	subtitle.Position = UDim2.new(0.62, 0, 0, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Code
	subtitle.TextSize = 10.5
	subtitle.TextColor3 = FORGE_THEME.TextMuted
	subtitle.TextXAlignment = Enum.TextXAlignment.Right
	subtitle.Text = "INVERSE MASS ENGINE (FR-2.3)"
	subtitle.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -40, 0.5, -16)
	closeBtn.BackgroundColor3 = FORGE_THEME.ButtonDark
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 22
	closeBtn.TextColor3 = FORGE_THEME.GoldPrimary
	closeBtn.Text = "\u{00D7}"
	closeBtn.TextStrokeTransparency = 1
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = header
	local cbc = Instance.new("UICorner") cbc.CornerRadius = UDim.new(0, 6) cbc.Parent = closeBtn
	local cbs = Instance.new("UIStroke")
	cbs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cbs.Color = FORGE_THEME.StrokeSubtle
	cbs.Thickness = 1
	cbs.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		fullOverlay.Visible = false
	end)

	----------------------------------------------------------------------------
	-- MODAL BODY (35% LEFT / 65% RIGHT)
	----------------------------------------------------------------------------
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -24, 1, -58)
	body.Position = UDim2.new(0, 12, 0, 50)
	body.BackgroundTransparency = 1
	body.ClipsDescendants = false
	body.Parent = modal

	-- LEFT COLUMN (35% WIDTH)
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftCol"
	leftCol.Size = UDim2.new(0.35, -6, 1, 0)
	leftCol.BackgroundTransparency = 1
	leftCol.Parent = body

	-- CARD 1: SPECIMEN CORE (142px - Clean & Proportioned)
	local card1 = Instance.new("Frame")
	card1.Name = "SpecimenCoreCard"
	card1.Size = UDim2.new(1, 0, 0, 142)
	card1.BackgroundColor3 = FORGE_THEME.CardBg
	card1.BorderSizePixel = 0
	card1.Parent = leftCol

	local c1Corner = Instance.new("UICorner") c1Corner.CornerRadius = UDim.new(0, 6) c1Corner.Parent = card1
	local c1Stroke = Instance.new("UIStroke") c1Stroke.Color = FORGE_THEME.StrokeSubtle c1Stroke.Parent = card1
	local c1Pad = Instance.new("UIPadding")
	c1Pad.PaddingLeft = UDim.new(0, 12) c1Pad.PaddingRight = UDim.new(0, 12)
	c1Pad.PaddingTop = UDim.new(0, 10) c1Pad.PaddingBottom = UDim.new(0, 10)
	c1Pad.Parent = card1

	-- Slot Selector Tabs with Scroll Navigation Affordance
	local tabNavRow = Instance.new("Frame")
	tabNavRow.Name = "TabNavRow"
	tabNavRow.Size = UDim2.new(1, 0, 0, 30)
	tabNavRow.BackgroundTransparency = 1
	tabNavRow.Parent = card1

	local tabScrollLeft = Instance.new("TextButton")
	tabScrollLeft.Name = "ScrollLeft"
	tabScrollLeft.Size = UDim2.new(0, 16, 1, 0)
	tabScrollLeft.Position = UDim2.new(0, 0, 0, 0)
	tabScrollLeft.BackgroundColor3 = FORGE_THEME.ButtonDark
	tabScrollLeft.Font = Enum.Font.GothamBold
	tabScrollLeft.TextSize = 11
	tabScrollLeft.TextColor3 = FORGE_THEME.GoldPrimary
	tabScrollLeft.Text = "<"
	tabScrollLeft.AutoButtonColor = false
	tabScrollLeft.Visible = false
	tabScrollLeft.Parent = tabNavRow
	local tslc = Instance.new("UICorner") tslc.CornerRadius = UDim.new(0, 4) tslc.Parent = tabScrollLeft
	local tsls = Instance.new("UIStroke") tsls.Color = FORGE_THEME.StrokeSubtle tsls.Thickness = 1 tsls.Parent = tabScrollLeft

	local tabScrollRight = Instance.new("TextButton")
	tabScrollRight.Name = "ScrollRight"
	tabScrollRight.Size = UDim2.new(0, 16, 1, 0)
	tabScrollRight.Position = UDim2.new(1, -16, 0, 0)
	tabScrollRight.BackgroundColor3 = FORGE_THEME.ButtonDark
	tabScrollRight.Font = Enum.Font.GothamBold
	tabScrollRight.TextSize = 11
	tabScrollRight.TextColor3 = FORGE_THEME.GoldPrimary
	tabScrollRight.Text = ">"
	tabScrollRight.AutoButtonColor = false
	tabScrollRight.Visible = false
	tabScrollRight.Parent = tabNavRow
	local tsrc = Instance.new("UICorner") tsrc.CornerRadius = UDim.new(0, 4) tsrc.Parent = tabScrollRight
	local tsrs = Instance.new("UIStroke") tsrs.Color = FORGE_THEME.StrokeSubtle tsrs.Thickness = 1 tsrs.Parent = tabScrollRight

	local tabRow = Instance.new("ScrollingFrame")
	tabRow.Name = "TabStrip"
	tabRow.Size = UDim2.new(1, 0, 1, 0)
	tabRow.Position = UDim2.new(0, 0, 0, 0)
	tabRow.BackgroundTransparency = 1
	tabRow.BorderSizePixel = 0
	tabRow.ScrollingDirection = Enum.ScrollingDirection.X
	tabRow.ScrollBarThickness = 3
	tabRow.ScrollBarImageColor3 = FORGE_THEME.GoldBurnished
	tabRow.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabRow.ClipsDescendants = true
	tabRow.Parent = tabNavRow

	tabScrollLeft.MouseButton1Click:Connect(function()
		tabRow.CanvasPosition = Vector2.new(math.max(0, tabRow.CanvasPosition.X - (TAB_WIDTH + TAB_GAP)), 0)
	end)

	tabScrollRight.MouseButton1Click:Connect(function()
		tabRow.CanvasPosition = Vector2.new(tabRow.CanvasPosition.X + (TAB_WIDTH + TAB_GAP), 0)
	end)

	local trLayout = Instance.new("UIListLayout")
	trLayout.FillDirection = Enum.FillDirection.Horizontal
	trLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trLayout.Padding = UDim.new(0, TAB_GAP)
	trLayout.Parent = tabRow

	trLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		tabRow.CanvasSize = UDim2.new(0, trLayout.AbsoluteContentSize.X, 0, 0)
	end)

	-- Specimen Header
	local specRow = Instance.new("Frame")
	specRow.Name = "SpecimenHeaderRow"
	specRow.Size = UDim2.new(1, 0, 0, 42)
	specRow.Position = UDim2.new(0, 0, 0, 38)
	specRow.BackgroundTransparency = 1
	specRow.Parent = card1

	local dBadge = Instance.new("Frame")
	dBadge.Name = "DieBadge"
	dBadge.Size = UDim2.new(0, 40, 0, 40)
	dBadge.BackgroundColor3 = FORGE_THEME.InsetDark
	dBadge.Parent = specRow
	local dbC = Instance.new("UICorner") dbC.CornerRadius = UDim.new(0, 5) dbC.Parent = dBadge
	local dbS = Instance.new("UIStroke") dbS.Color = FORGE_THEME.GoldPrimary dbS.Thickness = 1.5 dbS.Parent = dBadge
	local dbLbl = Instance.new("TextLabel")
	dbLbl.Name = "BadgeLabel"
	dbLbl.Size = UDim2.fromScale(1, 1) dbLbl.BackgroundTransparency = 1
	dbLbl.Font = Enum.Font.GothamBlack dbLbl.TextSize = 14 dbLbl.TextColor3 = FORGE_THEME.GoldLight
	dbLbl.Text = "D6" dbLbl.Parent = dBadge

	local dName = Instance.new("TextLabel")
	dName.Name = "SpecimenName"
	dName.Size = UDim2.new(1, -50, 0, 20)
	dName.Position = UDim2.new(0, 48, 0, 0)
	dName.BackgroundTransparency = 1
	dName.Font = Enum.Font.GothamBlack
	dName.TextSize = 13.5
	dName.TextColor3 = FORGE_THEME.TextPrimary
	dName.TextXAlignment = Enum.TextXAlignment.Left
	dName.Text = "DIE 1 [D6 SPECIMEN]"
	dName.Parent = specRow

	local dSub = Instance.new("TextLabel")
	dSub.Name = "SpecimenSub"
	dSub.Size = UDim2.new(1, -50, 0, 18)
	dSub.Position = UDim2.new(0, 48, 0, 20)
	dSub.BackgroundTransparency = 1
	dSub.Font = Enum.Font.Code
	dSub.TextSize = 10.5
	dSub.TextColor3 = FORGE_THEME.TextMuted
	dSub.TextXAlignment = Enum.TextXAlignment.Left
	dSub.Text = "6 Faces | Slot 01 of 04"
	dSub.Parent = specRow

	-- Mass Allocation Progress Meter
	local poolRow = Instance.new("Frame")
	poolRow.Name = "PoolRow"
	poolRow.Size = UDim2.new(1, 0, 0, 40)
	poolRow.Position = UDim2.new(0, 0, 0, 88)
	poolRow.BackgroundTransparency = 1
	poolRow.Parent = card1

	local plTitle = Instance.new("TextLabel")
	plTitle.Size = UDim2.new(0.5, 0, 0, 16)
	plTitle.BackgroundTransparency = 1
	plTitle.Font = Enum.Font.Code
	plTitle.TextSize = 10
	plTitle.TextColor3 = FORGE_THEME.TextMuted
	plTitle.TextXAlignment = Enum.TextXAlignment.Left
	plTitle.Text = "MASS ALLOCATION"
	plTitle.Parent = poolRow

	local plVal = Instance.new("TextLabel")
	plVal.Size = UDim2.new(0.5, 0, 0, 16)
	plVal.Position = UDim2.new(0.5, 0, 0, 0)
	plVal.BackgroundTransparency = 1
	plVal.Font = Enum.Font.GothamBold
	plVal.TextSize = 11
	plVal.TextColor3 = FORGE_THEME.GoldLight
	plVal.TextXAlignment = Enum.TextXAlignment.Right
	plVal.Text = "60 / 60 MASS"
	plVal.Parent = poolRow

	local plBar = Instance.new("Frame")
	plBar.Size = UDim2.new(1, 0, 0, 16)
	plBar.Position = UDim2.new(0, 0, 0, 20)
	plBar.BackgroundColor3 = FORGE_THEME.InsetDark
	plBar.BorderSizePixel = 0
	plBar.ClipsDescendants = true
	plBar.Parent = poolRow
	local plc = Instance.new("UICorner") plc.CornerRadius = UDim.new(0, 4) plc.Parent = plBar

	local plFill = Instance.new("Frame")
	plFill.Size = UDim2.new(1, 0, 1, 0)
	plFill.BackgroundColor3 = FORGE_THEME.GoldPrimary
	plFill.BorderSizePixel = 0
	plFill.Parent = plBar
	local plfc = Instance.new("UICorner") plfc.CornerRadius = UDim.new(0, 4) plfc.Parent = plFill

	-- CARD 2: TELEMETRY & PRESETS
	local card2 = Instance.new("Frame")
	card2.Name = "TelemetryPresetsCard"
	card2.Size = UDim2.new(1, 0, 1, -272)
	card2.Position = UDim2.new(0, 0, 0, 152)
	card2.BackgroundColor3 = FORGE_THEME.CardBg
	card2.BorderSizePixel = 0
	card2.Parent = leftCol

	local c2Corner = Instance.new("UICorner") c2Corner.CornerRadius = UDim.new(0, 6) c2Corner.Parent = card2
	local c2Stroke = Instance.new("UIStroke") c2Stroke.Color = FORGE_THEME.StrokeSubtle c2Stroke.Parent = card2
	local c2Pad = Instance.new("UIPadding")
	c2Pad.PaddingLeft = UDim.new(0, 14) c2Pad.PaddingRight = UDim.new(0, 14)
	c2Pad.PaddingTop = UDim.new(0, 14) c2Pad.PaddingBottom = UDim.new(0, 14)
	c2Pad.Parent = card2

	-- EV Row
	local evRow = Instance.new("Frame")
	evRow.Name = "EVRow"
	evRow.Size = UDim2.new(1, 0, 0, 32)
	evRow.Position = UDim2.new(0, 0, 0, 0)
	evRow.BackgroundTransparency = 1
	evRow.Parent = card2

	local evL = Instance.new("TextLabel")
	evL.Size = UDim2.new(0.50, 0, 1, 0)
	evL.BackgroundTransparency = 1
	evL.Font = Enum.Font.GothamMedium
	evL.TextSize = 14
	evL.TextColor3 = FORGE_THEME.TextMuted
	evL.TextXAlignment = Enum.TextXAlignment.Left
	evL.Text = "Projected EV / Roll"
	evL.Parent = evRow

	local evV = Instance.new("TextLabel")
	evV.Size = UDim2.new(0.50, 0, 1, 0)
	evV.Position = UDim2.new(0.50, 0, 0, 0)
	evV.BackgroundTransparency = 1
	evV.Font = Enum.Font.GothamBlack
	evV.TextSize = 24
	evV.TextColor3 = FORGE_THEME.Cash
	evV.TextXAlignment = Enum.TextXAlignment.Right
	evV.Text = "$0.00"
	evV.Parent = evRow

	-- Hazard Row
	local vdRow = Instance.new("Frame")
	vdRow.Name = "HazardRow"
	vdRow.Size = UDim2.new(1, 0, 0, 30)
	vdRow.Position = UDim2.new(0, 0, 0, 36)
	vdRow.BackgroundTransparency = 1
	vdRow.Parent = card2

	local vdL = Instance.new("TextLabel")
	vdL.Size = UDim2.new(0.50, 0, 1, 0)
	vdL.BackgroundTransparency = 1
	vdL.Font = Enum.Font.GothamMedium
	vdL.TextSize = 14
	vdL.TextColor3 = FORGE_THEME.AmberCaution
	vdL.TextXAlignment = Enum.TextXAlignment.Left
	vdL.Text = "Streak Hazard Risk"
	vdL.Parent = vdRow

	local vdV = Instance.new("TextLabel")
	vdV.Size = UDim2.new(0.50, 0, 1, 0)
	vdV.Position = UDim2.new(0.50, 0, 0, 0)
	vdV.BackgroundTransparency = 1
	vdV.Font = Enum.Font.GothamBlack
	vdV.TextSize = 20
	vdV.TextColor3 = FORGE_THEME.Negative
	vdV.TextXAlignment = Enum.TextXAlignment.Right
	vdV.Text = "0.0%"
	vdV.Parent = vdRow

	-- Optimization Presets Toolbar
	local psSection = Instance.new("Frame")
	psSection.Name = "PresetsSection"
	psSection.Size = UDim2.new(1, 0, 0, 68)
	psSection.Position = UDim2.new(0, 0, 0, 76)
	psSection.BackgroundTransparency = 1
	psSection.Parent = card2

	local psTitle = Instance.new("TextLabel")
	psTitle.Size = UDim2.new(1, 0, 0, 18)
	psTitle.Position = UDim2.new(0, 0, 0, 0)
	psTitle.BackgroundTransparency = 1
	psTitle.Font = Enum.Font.Code
	psTitle.TextSize = 11
	psTitle.TextColor3 = FORGE_THEME.TextMuted
	psTitle.TextXAlignment = Enum.TextXAlignment.Left
	psTitle.Text = "OPTIMIZATION PRESETS"
	psTitle.Parent = psSection

	local psDeck = Instance.new("Frame")
	psDeck.Name = "PresetsDeck"
	psDeck.Size = UDim2.new(1, 0, 0, 42)
	psDeck.Position = UDim2.new(0, 0, 0, 22)
	psDeck.BackgroundTransparency = 1
	psDeck.Parent = psSection

	local psL = Instance.new("UIListLayout")
	psL.FillDirection = Enum.FillDirection.Horizontal
	psL.Padding = UDim.new(0, 6)
	psL.Parent = psDeck

	local function makePresetBtn(name: string, txt: string, col: Color3): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.new(0.23, 0, 1, 0)
		b.BackgroundColor3 = FORGE_THEME.ButtonDark
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12.5
		b.TextColor3 = col
		b.Text = txt
		b.AutoButtonColor = false
		b.Parent = psDeck
		local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 6) bc.Parent = b
		local bs = Instance.new("UIStroke")
		bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bs.Color = FORGE_THEME.StrokeSubtle
		bs.Thickness = 1.5
		bs.Parent = b
		return b
	end

	local btnEven = makePresetBtn("Even", "EVEN", FORGE_THEME.Gems)
	local btnJackpot = makePresetBtn("Jackpot", "JACKPOT", FORGE_THEME.Cash)
	local btnReset = makePresetBtn("Reset", "RESET", FORGE_THEME.TextMuted)
	local btnSafe = makePresetBtn("Safe", "SAFE", FORGE_THEME.Positive)

	-- Inset Rule Callout Card
	local ruleBox = Instance.new("Frame")
	ruleBox.Name = "RuleBox"
	ruleBox.Size = UDim2.new(1, 0, 0, 52)
	ruleBox.Position = UDim2.new(0, 0, 0, 154)
	ruleBox.BackgroundColor3 = FORGE_THEME.InsetDark
	ruleBox.BorderSizePixel = 0
	ruleBox.Parent = card2

	local rbc = Instance.new("UICorner") rbc.CornerRadius = UDim.new(0, 5) rbc.Parent = ruleBox
	local rbs = Instance.new("UIStroke") rbs.Color = FORGE_THEME.StrokeInset rbs.Thickness = 1 rbs.Parent = ruleBox
	local rbp = Instance.new("UIPadding")
	rbp.PaddingLeft = UDim.new(0, 8) rbp.PaddingRight = UDim.new(0, 8)
	rbp.PaddingTop = UDim.new(0, 6) rbp.PaddingBottom = UDim.new(0, 6)
	rbp.Parent = ruleBox

	local rNote = Instance.new("TextLabel")
	rNote.Size = UDim2.fromScale(1, 1)
	rNote.BackgroundTransparency = 1
	rNote.Font = Enum.Font.Code
	rNote.TextSize = 10
	rNote.TextColor3 = FORGE_THEME.TextMuted
	rNote.TextWrapped = true
	rNote.TextXAlignment = Enum.TextXAlignment.Left
	rNote.Text = "Rule: Heavier faces land LESS often (FR-2.3). The lightest starved face becomes the Primary Hazard (breaks streaks)."
	rNote.Parent = ruleBox

	-- BOTTOM ACTION DECK
	local actDeck = Instance.new("Frame")
	actDeck.Name = "ActionDeck"
	actDeck.Size = UDim2.new(1, 0, 0, 114)
	actDeck.Position = UDim2.new(0, 0, 1, -114)
	actDeck.BackgroundTransparency = 1
	actDeck.Parent = leftCol

	local bBuy = Instance.new("TextButton")
	bBuy.Name = "BuyMass"
	bBuy.Size = UDim2.new(1, 0, 0, 32)
	bBuy.BackgroundColor3 = FORGE_THEME.ButtonDark
	bBuy.Font = Enum.Font.GothamBold
	bBuy.TextSize = 11.5
	bBuy.TextColor3 = FORGE_THEME.Positive
	bBuy.Text = "+ Buy Mass Upgrade"
	bBuy.AutoButtonColor = false
	bBuy.Parent = actDeck
	local bbc = Instance.new("UICorner") bbc.CornerRadius = UDim.new(0, 4) bbc.Parent = bBuy
	local bbs = Instance.new("UIStroke")
	bbs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bbs.Color = FORGE_THEME.StrokeSubtle
	bbs.Thickness = 1
	bbs.Parent = bBuy

	local cQuote = Instance.new("TextLabel")
	cQuote.Name = "CostQuote"
	cQuote.Size = UDim2.new(1, 0, 0, 20)
	cQuote.Position = UDim2.new(0, 0, 0, 38)
	cQuote.BackgroundTransparency = 1
	cQuote.Font = Enum.Font.Code
	cQuote.TextSize = 12
	cQuote.TextColor3 = FORGE_THEME.GoldPrimary
	cQuote.Text = "No changes pending"
	cQuote.Parent = actDeck

	local bForge = Instance.new("TextButton")
	bForge.Name = "Forge"
	bForge.Size = UDim2.new(1, 0, 0, 50)
	bForge.Position = UDim2.new(0, 0, 1, -50)
	bForge.BackgroundColor3 = FORGE_THEME.Cash
	bForge.Font = Enum.Font.GothamBlack
	bForge.TextSize = 15
	bForge.TextColor3 = FORGE_THEME.TextDark
	bForge.TextStrokeTransparency = 1
	bForge.Text = "FORGE CALIBRATION"
	bForge.AutoButtonColor = false
	bForge.Parent = actDeck
	local bfc = Instance.new("UICorner") bfc.CornerRadius = UDim.new(0, 6) bfc.Parent = bForge
	local bfs = Instance.new("UIStroke")
	bfs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bfs.Color = FORGE_THEME.GoldLight
	bfs.Thickness = 1.5
	bfs.Parent = bForge

	----------------------------------------------------------------------------
	-- RIGHT COLUMN (65% WIDTH) — 4-ROW LOCK & ZERO OVERFLOW
	----------------------------------------------------------------------------
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightFaceBankCol"
	rightCol.Size = UDim2.new(0.65, -6, 1, 0)
	rightCol.Position = UDim2.new(0.35, 6, 0, 0)
	rightCol.BackgroundColor3 = FORGE_THEME.CardBg
	rightCol.BorderSizePixel = 0
	rightCol.ClipsDescendants = true
	rightCol.Parent = body

	local rcCorner = Instance.new("UICorner") rcCorner.CornerRadius = UDim.new(0, 6) rcCorner.Parent = rightCol
	local rcStroke = Instance.new("UIStroke") rcStroke.Color = FORGE_THEME.StrokeSubtle rcStroke.Parent = rightCol
	local rcPad = Instance.new("UIPadding")
	rcPad.PaddingTop = UDim.new(0, 10) rcPad.PaddingBottom = UDim.new(0, 10)
	rcPad.PaddingLeft = UDim.new(0, 10) rcPad.PaddingRight = UDim.new(0, 10)
	rcPad.Parent = rightCol

	-- Caliper Column Header Legend
	local legend = Instance.new("Frame")
	legend.Size = UDim2.new(1, -12, 0, 22)
	legend.Position = UDim2.new(0, 0, 0, 0)
	legend.BackgroundTransparency = 1
	legend.Parent = rightCol

	local function makeLeg(txt: string, xPos: number, width: number, col: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(0, width, 1, 0)
		l.Position = UDim2.new(0, xPos, 0, 0)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Code
		l.TextSize = 10
		l.TextColor3 = col
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = txt
		l.Parent = legend
		return l
	end

	makeLeg("FACE", 10, 44, FORGE_THEME.GoldPrimary)
	makeLeg("MASS CALIPER", 60, 174, FORGE_THEME.TextMuted)
	makeLeg("ELEMENT", 242, 74, FORGE_THEME.Multiplier)
	makeLeg("CHANCE %", 324, 56, FORGE_THEME.Gems)

	local legPay = Instance.new("TextLabel")
	legPay.Size = UDim2.new(1, -394, 1, 0)
	legPay.Position = UDim2.new(0, 388, 0, 0)
	legPay.BackgroundTransparency = 1
	legPay.Font = Enum.Font.Code
	legPay.TextSize = 10
	legPay.TextColor3 = FORGE_THEME.Cash
	legPay.TextXAlignment = Enum.TextXAlignment.Right
	legPay.Text = "PAYOUT"
	legPay.Parent = legend

	-- Exactly 4 Rows Visible with 12px scrollbar gutter
	local faceList = Instance.new("ScrollingFrame")
	faceList.Name = "FaceList"
	faceList.Size = UDim2.new(1, 0, 1, -26)
	faceList.Position = UDim2.new(0, 0, 0, 26)
	faceList.BackgroundTransparency = 1
	faceList.BorderSizePixel = 0
	faceList.ClipsDescendants = true
	faceList.ScrollBarThickness = 5
	faceList.ScrollBarImageColor3 = FORGE_THEME.GoldBurnished
	faceList.CanvasSize = UDim2.fromScale(0, 0)
	faceList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	faceList.Parent = rightCol

	local flL = Instance.new("UIListLayout")
	flL.FillDirection = Enum.FillDirection.Vertical
	flL.SortOrder = Enum.SortOrder.LayoutOrder
	flL.Padding = UDim.new(0, 8)
	flL.Parent = faceList

	----------------------------------------------------------------------------
	-- WORKING STATE & DATA MODEL
	----------------------------------------------------------------------------

	local shapeId: string = DiceCatalog.STARTING_SHAPE
	local budget = 0
	local cash = 0
	local committed: { number } = {}
	local draft: { number } = {}
	local activeDie = 1
	local dieCount = 1
	local dieShapes: { string } = {}
	local faceElements: { string } = {}
	local unlockedElements: { [string]: boolean } = { None = true }
	local dieTabs: { any } = {}
	local emptySlots = 0
	local dirty = false
	local massUpgradeCost = 0
	local canAffordMass = false
	local isMassMaxed = false
	local lastActiveDie = 1

	local faceRowPool: { any } = {}
	local refresh: () -> ()
	local lastSnapshot: any = nil
	local applySnapshot: (any) -> ()
	local selectDie: (number) -> ()

	-- Ensure dynamic tab buttons exist in TabStrip (Strict LayoutOrder Sorting)
	local function ensureTabs(count: number)
		for i = #dieTabs + 1, count do
			local tab = Instance.new("TextButton")
			tab.Name = "DieTab" .. tostring(i)
			tab.LayoutOrder = i
			tab.Size = UDim2.new(0, TAB_WIDTH, 1, 0)
			tab.BackgroundColor3 = FORGE_THEME.InsetBg
			tab.Font = Enum.Font.GothamBlack
			tab.TextSize = 11
			tab.TextColor3 = FORGE_THEME.TextMuted
			tab.Text = string.format("SLOT %02d", i)
			tab.AutoButtonColor = false
			tab.Parent = tabRow

			local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 4) tc.Parent = tab
			local tcs = Instance.new("UIStroke")
			tcs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			tcs.Color = FORGE_THEME.StrokeSubtle
			tcs.Thickness = 1
			tcs.Parent = tab

			local index = i
			tab.MouseButton1Click:Connect(function()
				selectDie(index)
			end)
			table.insert(dieTabs, tab)
		end
	end

	local function revealTab(index: number)
		local tab = dieTabs[index]
		if tab == nil or not tab.Visible then
			return
		end
		local left = (index - 1) * (TAB_WIDTH + TAB_GAP)
		local right = left + TAB_WIDTH
		local window = tabRow.AbsoluteWindowSize.X
		if window <= 0 then
			return
		end
		local at = tabRow.CanvasPosition.X
		if left < at then
			tabRow.CanvasPosition = Vector2.new(left, 0)
		elseif right > at + window then
			tabRow.CanvasPosition = Vector2.new(right - window, 0)
		end
	end

	-- Zero-sum round-robin mass adjustment
	local function adjust(index: number, amount: number)
		local floor = DiceCatalog.getMassFloor(shapeId)
		local count = #draft
		if count == 0 or draft[index] == nil then
			return
		end

		if amount > 0 then
			local need = amount
			local taken = 0
			for _ = 1, count do
				if need <= 0 then break end
				for i = 1, count do
					if i ~= index and need > 0 then
						local spare = draft[i] - floor
						if spare > 0 then
							local grab = math.min(spare, need, 1)
							draft[i] -= grab
							taken += grab
							need -= grab
						end
					end
				end
			end
			draft[index] += taken
		else
			local give = math.min(-amount, draft[index] - floor)
			if give <= 0 then return end
			draft[index] -= give
			local per = give / math.max(1, count - 1)
			for i = 1, count do
				if i ~= index then
					draft[i] += per
				end
			end
		end
		dirty = true
		refresh()
	end

	-- Build 20 reusable FaceRows (Strict LayoutOrder)
	for i = 1, MAX_FACES do
		local row = Instance.new("Frame")
		row.Name = "FaceRow_" .. tostring(i)
		row.Size = UDim2.new(1, -12, 0.25, -6)
		row.BackgroundColor3 = FORGE_THEME.CardBgAlt
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Visible = false
		row.Parent = faceList

		local rCorner = Instance.new("UICorner") rCorner.CornerRadius = UDim.new(0, 8) rCorner.Parent = row
		local rStroke = Instance.new("UIStroke")
		rStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rStroke.Color = FORGE_THEME.StrokeInset
		rStroke.Thickness = 1
		rStroke.Parent = row

		-- Face Badge
		local fBadge = Instance.new("Frame")
		fBadge.Name = "FaceBadge"
		fBadge.Size = UDim2.new(0, 44, 0, 44)
		fBadge.Position = UDim2.new(0, 10, 0.5, -22)
		fBadge.BackgroundColor3 = FORGE_THEME.HeaderBg
		fBadge.BorderSizePixel = 0
		fBadge.Parent = row
		local fbC = Instance.new("UICorner") fbC.CornerRadius = UDim.new(0, 6) fbC.Parent = fBadge

		local fbLbl = Instance.new("TextLabel")
		fbLbl.Name = "BadgeLabel"
		fbLbl.Size = UDim2.fromScale(1, 1)
		fbLbl.BackgroundTransparency = 1
		fbLbl.Font = Enum.Font.GothamBlack
		fbLbl.TextSize = 17
		fbLbl.TextColor3 = FORGE_THEME.GoldPrimary
		fbLbl.Text = "F" .. tostring(i)
		fbLbl.Parent = fBadge

		-- Stepper Deck
		local stepperDeck = Instance.new("Frame")
		stepperDeck.Name = "StepperDeck"
		stepperDeck.Size = UDim2.new(0, 174, 1, 0)
		stepperDeck.Position = UDim2.new(0, 60, 0, 0)
		stepperDeck.BackgroundTransparency = 1
		stepperDeck.Parent = row

		local minusBtn = Instance.new("TextButton")
		minusBtn.Name = "Minus"
		minusBtn.Size = UDim2.new(0, 36, 0, 36)
		minusBtn.Position = UDim2.new(0, 0, 0.5, -18)
		minusBtn.BackgroundColor3 = FORGE_THEME.ButtonDark
		minusBtn.Font = Enum.Font.GothamBlack
		minusBtn.TextSize = 18
		minusBtn.TextColor3 = FORGE_THEME.Negative
		minusBtn.Text = "\u{2212}"
		minusBtn.AutoButtonColor = false
		minusBtn.Parent = stepperDeck
		local mbc = Instance.new("UICorner") mbc.CornerRadius = UDim.new(0, 5) mbc.Parent = minusBtn
		local mbs = Instance.new("UIStroke") mbs.Color = FORGE_THEME.StrokeSubtle mbs.Thickness = 1 mbs.Parent = minusBtn

		local massBarBg = Instance.new("Frame")
		massBarBg.Name = "MassBarBg"
		massBarBg.Size = UDim2.new(0, 92, 0, 26)
		massBarBg.Position = UDim2.new(0, 42, 0.5, -13)
		massBarBg.BackgroundColor3 = FORGE_THEME.InsetDark
		massBarBg.BorderSizePixel = 0
		massBarBg.ClipsDescendants = true
		massBarBg.Parent = stepperDeck
		local mbbc = Instance.new("UICorner") mbbc.CornerRadius = UDim.new(0, 4) mbbc.Parent = massBarBg

		local massFill = Instance.new("Frame")
		massFill.Name = "MassFill"
		massFill.Size = UDim2.new(0.5, 0, 1, 0)
		massFill.BackgroundColor3 = FORGE_THEME.GoldBurnished
		massFill.BorderSizePixel = 0
		massFill.Parent = massBarBg
		local mfc = Instance.new("UICorner") mfc.CornerRadius = UDim.new(0, 4) mfc.Parent = massFill

		local massVal = Instance.new("TextLabel")
		massVal.Name = "MassVal"
		massVal.Size = UDim2.fromScale(1, 1)
		massVal.BackgroundTransparency = 1
		massVal.Font = Enum.Font.Code
		massVal.TextSize = 13.5
		massVal.TextColor3 = FORGE_THEME.TextPrimary
		massVal.Text = "10"
		massVal.Parent = massBarBg

		local plusBtn = Instance.new("TextButton")
		plusBtn.Name = "Plus"
		plusBtn.Size = UDim2.new(0, 36, 0, 36)
		plusBtn.Position = UDim2.new(0, 138, 0.5, -18)
		plusBtn.BackgroundColor3 = FORGE_THEME.ButtonDark
		plusBtn.Font = Enum.Font.GothamBlack
		plusBtn.TextSize = 18
		plusBtn.TextColor3 = FORGE_THEME.Positive
		plusBtn.Text = "+"
		plusBtn.AutoButtonColor = false
		plusBtn.Parent = stepperDeck
		local pbc = Instance.new("UICorner") pbc.CornerRadius = UDim.new(0, 5) pbc.Parent = plusBtn
		local pbs = Instance.new("UIStroke") pbs.Color = FORGE_THEME.StrokeSubtle pbs.Thickness = 1 pbs.Parent = plusBtn

		-- Element Chip
		local elemChip = Instance.new("TextButton")
		elemChip.Name = "ElementChip"
		elemChip.Size = UDim2.new(0, 74, 0, 30)
		elemChip.Position = UDim2.new(0, 242, 0.5, -15)
		elemChip.BackgroundColor3 = FORGE_THEME.InsetDark
		elemChip.Font = Enum.Font.GothamBold
		elemChip.TextSize = 11.5
		elemChip.TextColor3 = FORGE_THEME.TextMuted
		elemChip.Text = "None"
		elemChip.AutoButtonColor = false
		elemChip.Parent = row
		local ecc = Instance.new("UICorner") ecc.CornerRadius = UDim.new(0, 5) ecc.Parent = elemChip
		local ecs = Instance.new("UIStroke")
		ecs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ecs.Color = FORGE_THEME.StrokeInset
		ecs.Thickness = 1.5
		ecs.Parent = elemChip

		-- Probability
		local probVal = Instance.new("TextLabel")
		probVal.Name = "ProbVal"
		probVal.Size = UDim2.new(0, 56, 1, 0)
		probVal.Position = UDim2.new(0, 324, 0, 0)
		probVal.BackgroundTransparency = 1
		probVal.Font = Enum.Font.Code
		probVal.TextSize = 14
		probVal.TextColor3 = FORGE_THEME.Gems
		probVal.Text = "16.7%"
		probVal.Parent = row

		-- Payout
		local payVal = Instance.new("TextLabel")
		payVal.Name = "PayoutLabel"
		payVal.Size = UDim2.new(1, -400, 1, 0)
		payVal.Position = UDim2.new(0, 388, 0, 0)
		payVal.BackgroundTransparency = 1
		payVal.Font = Enum.Font.GothamBold
		payVal.TextSize = 16
		payVal.TextColor3 = FORGE_THEME.Cash
		payVal.TextXAlignment = Enum.TextXAlignment.Right
		payVal.Text = "$0"
		payVal.Parent = row

		-- Starved Box (Hidden by default)
		local starvedBox = Instance.new("Frame")
		starvedBox.Name = "StarvedBox"
		starvedBox.Size = UDim2.new(1, -394, 0, 48)
		starvedBox.Position = UDim2.new(0, 388, 0.5, -24)
		starvedBox.BackgroundTransparency = 1
		starvedBox.Visible = false
		starvedBox.Parent = row

		local stLbl = Instance.new("TextLabel")
		stLbl.Name = "StarvedLabel"
		stLbl.Size = UDim2.new(1, -6, 0, 22)
		stLbl.BackgroundTransparency = 1
		stLbl.Font = Enum.Font.GothamBlack
		stLbl.TextSize = 13.5
		stLbl.TextColor3 = FORGE_THEME.Negative
		stLbl.TextXAlignment = Enum.TextXAlignment.Right
		stLbl.Text = "PRIMARY HAZARD ($0)"
		stLbl.Parent = starvedBox

		local pill = Instance.new("Frame")
		pill.Name = "StreakBreakerPill"
		pill.Size = UDim2.new(0, 144, 0, 20)
		pill.Position = UDim2.new(1, -150, 0, 24)
		pill.BackgroundColor3 = FORGE_THEME.InsetBg
		pill.BorderSizePixel = 0
		pill.Parent = starvedBox
		local pc = Instance.new("UICorner") pc.CornerRadius = UDim.new(0, 4) pc.Parent = pill
		local ps = Instance.new("UIStroke") ps.Color = FORGE_THEME.AmberCaution ps.Thickness = 1.5 ps.Parent = pill

		local pLbl = Instance.new("TextLabel")
		pLbl.Name = "PillLabel"
		pLbl.Size = UDim2.fromScale(1, 1)
		pLbl.BackgroundTransparency = 1
		pLbl.Font = Enum.Font.Code
		pLbl.TextSize = 9.5
		pLbl.TextColor3 = FORGE_THEME.AmberCaution
		pLbl.Text = "STREAK BREAKER [0x]"
		pLbl.Parent = pill

		-- Stepper Click Handlers
		local rowIdx = i
		minusBtn.MouseButton1Click:Connect(function()
			adjust(rowIdx, -STEP)
		end)
		plusBtn.MouseButton1Click:Connect(function()
			adjust(rowIdx, STEP)
		end)

		-- Element Cycle Handler
		elemChip.MouseButton1Click:Connect(function()
			local current = faceElements[rowIdx] or "None"
			local startIdx = 1
			for k, id in ipairs(ELEMENT_ORDER) do
				if id == current then startIdx = k break end
			end
			for step = 1, #ELEMENT_ORDER do
				local nextId = ELEMENT_ORDER[((startIdx - 1 + step) % #ELEMENT_ORDER) + 1]
				if unlockedElements[nextId] then
					NetClient.setElement(activeDie, rowIdx, nextId)
					return
				end
			end
		end)

		table.insert(faceRowPool, {
			row = row,
			badge = fBadge,
			badgeLbl = fbLbl,
			massBar = massFill,
			massVal = massVal,
			elemChip = elemChip,
			elemStroke = ecs,
			probVal = probVal,
			payVal = payVal,
			starvedBox = starvedBox,
			stLbl = stLbl,
			pLbl = pLbl,
			rowStroke = rStroke,
		})
	end

	----------------------------------------------------------------------------
	-- RENDERING / REFRESH
	----------------------------------------------------------------------------

	refresh = function()
		local count = #draft
		local floor = DiceCatalog.getMassFloor(shapeId)

		local total = 0
		for _, m in ipairs(draft) do
			total += m
		end

		local denom = total * count - total
		local ev = 0
		local voidP = 0

		for i = 1, MAX_FACES do
			local ui = faceRowPool[i]
			if i > count then
				ui.row.Visible = false
			else
				ui.row.Visible = true
				local m = draft[i]
				local p = if denom > 0 then (total - m) / denom else 0
				local value = ForgeMath.faceValue(m)
				ev += p * value

				local isVoid = ForgeMath.isVoidFace(draft, i, floor)
				if isVoid then
					voidP += p
				end

				ui.badgeLbl.Text = "F" .. tostring(i)
				ui.badgeLbl.TextColor3 = if isVoid then FORGE_THEME.AmberCaution else FORGE_THEME.GoldPrimary
				ui.badge.BackgroundColor3 = if isVoid then FORGE_THEME.InsetBg else FORGE_THEME.HeaderBg

				ui.row.BackgroundColor3 = if isVoid then FORGE_THEME.InsetDark else FORGE_THEME.CardBgAlt
				ui.rowStroke.Color = if isVoid then FORGE_THEME.AmberCaution else FORGE_THEME.StrokeInset
				ui.rowStroke.Thickness = if isVoid then 2 else 1

				-- Stepper Gauge
				local maxCap = math.max(budget, 30)
				ui.massBar.Size = UDim2.new(math.clamp(m / maxCap, 0.05, 1), 0, 1, 0)
				ui.massBar.BackgroundColor3 = if isVoid then FORGE_THEME.VoidHazard else FORGE_THEME.GoldBurnished
				ui.massVal.Text = tostring(math.floor(m + 0.5))
				ui.massVal.TextColor3 = if isVoid then FORGE_THEME.AmberCaution else FORGE_THEME.TextPrimary

				-- Element Chip
				local elemId = faceElements[i] or "None"
				local choices = 0
				for _, id in ipairs(ELEMENT_ORDER) do
					if unlockedElements[id] and id ~= "None" then
						choices += 1
					end
				end

				if elemId ~= "None" then
					ui.elemChip.Text = elemId
					local eCol = ELEMENT_COLORS[elemId] or FORGE_THEME.TextMuted
					ui.elemChip.TextColor3 = eCol
					ui.elemStroke.Color = eCol
				elseif choices > 0 then
					ui.elemChip.Text = "Element"
					ui.elemChip.TextColor3 = FORGE_THEME.TextMuted
					ui.elemStroke.Color = FORGE_THEME.StrokeInset
				else
					ui.elemChip.Text = "Locked"
					ui.elemChip.TextColor3 = FORGE_THEME.TextSubtle
					ui.elemStroke.Color = FORGE_THEME.StrokeInset
				end

				ui.probVal.Text = string.format("%.1f%%", p * 100)
				ui.probVal.TextColor3 = if isVoid then FORGE_THEME.AmberCaution else FORGE_THEME.Gems

				if isVoid then
					ui.starvedBox.Visible = true
					ui.payVal.Visible = false
				else
					ui.starvedBox.Visible = false
					ui.payVal.Visible = true
					ui.payVal.Text = "$" .. Format.formatNumber(value)
				end
			end
		end

		-- Specimen Card UI
		dbLbl.Text = shapeId
		dName.Text = string.format("DIE %d [%s SPECIMEN]", activeDie, shapeId)
		dSub.Text = string.format("%d Faces | Slot %02d of %02d", count, activeDie, dieCount)

		plVal.Text = string.format("%d / %d MASS", math.floor(total + 0.5), budget)
		plFill.Size = UDim2.new(math.clamp(if budget > 0 then total / budget else 1, 0.05, 1), 0, 1, 0)

		-- Telemetry Values
		evV.Text = "$" .. string.format("%.2f", ev)
		vdV.Text = string.format("%.1f%%", voidP * 100)

		-- Die Tabs: STRICTLY show only owned dice (dieCount)
		local showScrollArrows = dieCount > 4
		tabScrollLeft.Visible = showScrollArrows
		tabScrollRight.Visible = showScrollArrows
		if showScrollArrows then
			tabRow.Size = UDim2.new(1, -40, 1, 0)
			tabRow.Position = UDim2.new(0, 20, 0, 0)
		else
			tabRow.Size = UDim2.new(1, 0, 1, 0)
			tabRow.Position = UDim2.new(0, 0, 0, 0)
		end

		for i, tab in ipairs(dieTabs) do
			tab.Visible = i <= dieCount
			if i <= dieCount then
				tab.Text = string.format("SLOT %02d", i)
				if i == activeDie then
					tab.BackgroundColor3 = FORGE_THEME.GoldPrimary
					tab.TextColor3 = FORGE_THEME.TextDark
				else
					tab.BackgroundColor3 = FORGE_THEME.InsetBg
					tab.TextColor3 = FORGE_THEME.TextMuted
				end
			end
		end
		revealTab(activeDie)

		-- Buy Mass Upgrade Button Display
		if isMassMaxed then
			bBuy.Text = "MAX MASS LEVEL"
			bBuy.TextColor3 = FORGE_THEME.TextSubtle
			bBuy.AutoButtonColor = false
		else
			bBuy.Text = string.format("+ Buy Mass (+%d) - $%s", UpgradeCatalog.MASS_PER_LEVEL, Format.formatNumber(massUpgradeCost))
			bBuy.TextColor3 = if canAffordMass then FORGE_THEME.Positive else FORGE_THEME.TextSubtle
			bBuy.AutoButtonColor = canAffordMass
		end

		-- Quoted Cost & Commit Button
		if dirty then
			local quoted = ForgeMath.forgeCost(committed, draft, budget)
			if ForgeMath.isFinite(quoted) then
				local afford = cash >= quoted
				cQuote.Text = "Quoted Cost: $" .. Format.formatNumber(quoted)
				cQuote.TextColor3 = if afford then FORGE_THEME.GoldPrimary else FORGE_THEME.Negative
				bForge.BackgroundColor3 = if afford then FORGE_THEME.Cash else FORGE_THEME.ButtonDark
				bForge.AutoButtonColor = afford
			else
				cQuote.Text = "Invalid distribution"
				cQuote.TextColor3 = FORGE_THEME.Negative
				bForge.BackgroundColor3 = FORGE_THEME.ButtonDark
				bForge.AutoButtonColor = false
			end
		else
			cQuote.Text = "No changes pending"
			cQuote.TextColor3 = FORGE_THEME.TextMuted
			bForge.BackgroundColor3 = FORGE_THEME.ButtonDark
			bForge.AutoButtonColor = false
		end
	end

	----------------------------------------------------------------------------
	-- BUTTON HANDLERS
	----------------------------------------------------------------------------

	-- Slot Switcher: switching tabs cleanly loads the new die's committed state
	selectDie = function(index: number)
		if index < 1 or index > dieCount then
			return
		end
		activeDie = index
		dirty = false
		draft = {}
		faceList.CanvasPosition = Vector2.new(0, 0)
		local st = lastSnapshot
		if st ~= nil then
			applySnapshot(st)
		end
	end

	-- Buy Mass Upgrade
	bBuy.MouseButton1Click:Connect(function()
		if isMassMaxed or not canAffordMass then
			return
		end
		bBuy.Text = "Purchasing..."
		task.spawn(function()
			-- NetClient returns a single Result table { ok: boolean, reason: string? },
			-- not a tuple. Destructuring as (ok, reason) made `ok` always truthy (FORGE-1).
			local result = NetClient.buyUpgrade("MassBudget")
			if not result.ok then
				bBuy.Text = tostring(result.reason or "Refused")
				task.wait(1.2)
			end
			refresh()
		end)
	end)

	-- Presets
	btnEven.MouseButton1Click:Connect(function()
		local count = #draft
		if count == 0 then return end
		local share = math.floor(budget / count)
		local rem = budget % count
		for i = 1, count do
			draft[i] = share + (if i <= rem then 1 else 0)
		end
		dirty = true
		refresh()
	end)

	btnJackpot.MouseButton1Click:Connect(function()
		local count = #draft
		local floor = DiceCatalog.getMassFloor(shapeId)
		if count <= 1 then return end
		local leftover = budget - (count - 1) * floor
		draft[1] = leftover
		for i = 2, count do
			draft[i] = floor
		end
		dirty = true
		refresh()
	end)

	btnSafe.MouseButton1Click:Connect(function()
		local count = #draft
		if count == 0 then return end
		local share = math.floor(budget / count)
		local rem = budget % count
		for i = 1, count do
			draft[i] = share + (if i <= rem then 1 else 0)
		end
		dirty = true
		refresh()
	end)

	btnReset.MouseButton1Click:Connect(function()
		draft = table.clone(committed)
		dirty = false
		refresh()
	end)

	-- Primary Forge Calibration Action
	bForge.MouseButton1Click:Connect(function()
		if #draft == 0 or not dirty then
			return
		end

		local quoted = ForgeMath.forgeCost(committed, draft, budget)
		if not ForgeMath.isFinite(quoted) or cash < quoted then
			cQuote.Text = "Insufficient Cash to Forge!"
			cQuote.TextColor3 = FORGE_THEME.Negative
			return
		end

		local out: { number } = {}
		local sum = 0
		for i, m in ipairs(draft) do
			out[i] = math.floor(m + 0.5)
			sum += out[i]
		end
		-- Target the die's REAL budget, not a rounded one. `newDie` snaps the per-face
		-- share down to 3dp, so D7 is 59.997 and D14 is 59.990 -- rounding the target to
		-- 60 put both past the server's 0.001 epsilon and made those two shapes
		-- permanently unforgeable (FORGE-2). The server never required integers.
		local drift = budget - sum
		if drift > 0 then
			local heaviest, heaviestIdx = -1, 1
			for i, m in ipairs(out) do
				if m > heaviest then
					heaviest, heaviestIdx = m, i
				end
			end
			out[heaviestIdx] += drift
		elseif drift < 0 then
			local floor = DiceCatalog.getMassFloor(shapeId)
			local remaining = -drift
			while remaining > 1e-6 do
				local heaviest, heaviestIdx = -1, 1
				for i, m in ipairs(out) do
					if m > heaviest then
						heaviest, heaviestIdx = m, i
					end
				end
				local spare = out[heaviestIdx] - floor
				if spare <= 0 then
					out[heaviestIdx] -= remaining
					break
				end
				local sub = math.min(spare, remaining)
				if remaining > 1 and spare > 1 then
					sub = math.min(sub, 1)
				end
				out[heaviestIdx] -= sub
				remaining -= sub
			end
		end

		bForge.Text = "CALIBRATING..."
		bForge.BackgroundColor3 = FORGE_THEME.ButtonDark
		task.spawn(function()
			-- NetClient returns a single Result table { ok: boolean, reason: string? },
			-- not a tuple. Destructuring as (ok, reason) made `ok` a truthy table reference,
			-- unconditionally reporting success and clearing dirty even on refusal (FORGE-1).
			local result = NetClient.forge(activeDie, out)
			if result.ok then
				dirty = false
				bForge.Text = "CALIBRATED"
				bForge.BackgroundColor3 = FORGE_THEME.Positive
			else
				bForge.Text = tostring(result.reason or "Refused")
				bForge.BackgroundColor3 = FORGE_THEME.Negative
				draft = table.clone(committed)
				dirty = false
			end
			task.wait(1.2)
			bForge.Text = "FORGE CALIBRATION"
			refresh()
		end)
	end)

	----------------------------------------------------------------------------
	-- DATA SNAPSHOT INGESTION
	----------------------------------------------------------------------------

	applySnapshot = function(state: any)
		lastSnapshot = state
		-- Owned dice count strictly matches state.dice
		local owned = if type(state.dice) == "table" then #state.dice else 0
		if owned <= 0 then
			return
		end

		local slots = math.max(1, math.floor(tonumber(state.dieSlots) or owned))
		dieCount = owned
		emptySlots = math.max(0, slots - owned)
		
		-- If active die was removed or out of range, clamp to 1
		if activeDie > dieCount or activeDie < 1 then
			activeDie = 1
			dirty = false
			draft = {}
		end

		-- If active die changed since last snapshot, reset dirty
		if activeDie ~= lastActiveDie then
			dirty = false
			draft = {}
			lastActiveDie = activeDie
		end

		ensureTabs(dieCount)
		dieShapes = {}
		for i, d in ipairs(state.dice) do
			dieShapes[i] = tostring(d.Shape)
		end

		unlockedElements = {}
		local el = state.diamondTree and state.diamondTree.Elements
		if type(el) == "table" then
			for id, on in pairs(el) do
				unlockedElements[id] = on == true
			end
		end
		unlockedElements.None = true

		local die = state.dice[activeDie]
		if type(die) ~= "table" or type(die.Faces) ~= "table" then
			return
		end
		shapeId = tostring(die.Shape)
		budget = tonumber(die.MassBudget) or 0
		cash = tonumber(state.cash) or 0

		-- Compute Mass Upgrade Cost
		local massLvl = (state.upgrades and tonumber(state.upgrades.MassBudget)) or 0
		local massDef = UpgradeCatalog.getCashUpgrade("MassBudget")
		if massDef and massLvl < massDef.maxLevel then
			massUpgradeCost = UpgradeCatalog.getCashUpgradeCost("MassBudget", massLvl)
			canAffordMass = cash >= massUpgradeCost
			isMassMaxed = false
		else
			massUpgradeCost = 0
			canAffordMass = false
			isMassMaxed = true
		end

		committed = {}
		faceElements = {}
		for i, face in ipairs(die.Faces) do
			if type(face) == "table" then
				committed[i] = tonumber(face.Mass) or 0
				faceElements[i] = tostring(face.Element or "None")
			else
				committed[i] = tonumber(face) or 0
				faceElements[i] = "None"
			end
		end

		-- Draft resets cleanly if not dirty or if face count or shape changed
		if not dirty or #draft ~= #committed then
			draft = table.clone(committed)
			dirty = false
		end
		refresh()
	end

	local self: V7ForgeController = setmetatable({
		overlay = fullOverlay,
		_apply = applySnapshot,
	}, V7ForgePanel) :: any

	return self
end

function V7ForgePanel:show()
	self.overlay.Visible = true
end

function V7ForgePanel:hide()
	self.overlay.Visible = false
end

function V7ForgePanel:applyState(state: any)
	if type(state) ~= "table" then
		return
	end
	local ok, err = pcall(self._apply, state)
	if not ok then
		warn("[V7ForgePanel] applyState failed: " .. tostring(err))
	end
end

return V7ForgePanel
