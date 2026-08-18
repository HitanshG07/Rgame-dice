const fs = require('fs');
const path = require('path');

const code = `--!strict
-- UIMockPreview.luau
-- Ascend Panel Redesign Preview: Sovereign Vault (Master Edition with Telemetry Breakdown).
--
-- Harmonized strictly with Shop & Settings UI revamp:
--   - Color Theme: Base Mocha (#1A1614), Panel Maroon (#241E1A), Panel Deep (#14100E), Matte Brass Gold (#D4AF37)
--   - Full Vertical Density: Left column now features a structured Lifetime Vault Metrics & Yield Breakdown pod
--   - Typography: Scaled up for high readability (22px headers, 36px diamond readout, 14-15px body, 16px action buttons)
--   - 4 Interactive Runtime State Presets (Qualified, Locked, Armed Confirm, High Prestige)
--   - Two-step interactive arming
--
-- Runnable in Roblox Studio command bar via:
-- require(game.StarterPlayer.StarterPlayerScripts.Client.UIMockPreview:Clone()).show()

local Players = game:GetService("Players")

local UIMockPreview = {}

local currentGui: ScreenGui? = nil
local activeStateIndex = 1 -- 1 = Qualified, 2 = Locked, 3 = Armed, 4 = HighPrestige

--------------------------------------------------------------------------------
-- RUNTIME PREVIEW SCENARIOS (Accurate to DiceCatalog & AscensionService)
--------------------------------------------------------------------------------

type PreviewState = {
	id: string,
	label: string,
	cash: number,
	threshold: number,
	diamonds: number,
	currentVaultDiamonds: number,
	nextDiamondThreshold: number,
	ascensions: number,
	isArmed: boolean,
	isLocked: boolean,
	statusText: string,
	statusColorType: string,
}

local PREVIEW_STATES: { PreviewState } = {
	{
		id = "QUALIFIED",
		label = "QUALIFIED ($4.5M)",
		cash = 4500000,
		threshold = 1000000,
		diamonds = 2,
		currentVaultDiamonds = 8,
		nextDiamondThreshold = 10000000,
		ascensions = 3,
		isArmed = false,
		isLocked = false,
		statusText = "Ready to ascend. Press button to begin two-step confirmation.",
		statusColorType = "Positive",
	},
	{
		id = "LOCKED",
		label = "LOCKED ($350K)",
		cash = 350000,
		threshold = 1000000,
		diamonds = 0,
		currentVaultDiamonds = 2,
		nextDiamondThreshold = 1000000,
		ascensions = 1,
		isArmed = false,
		isLocked = true,
		statusText = "Threshold not met: Earn $650,000 more cash this run to unlock.",
		statusColorType = "Negative",
	},
	{
		id = "ARMED",
		label = "ARMED CONFIRM",
		cash = 4500000,
		threshold = 1000000,
		diamonds = 2,
		currentVaultDiamonds = 8,
		nextDiamondThreshold = 10000000,
		ascensions = 3,
		isArmed = true,
		isLocked = false,
		statusText = "WARNING: Press again to confirm. Cash, dice & slots will be wiped permanently.",
		statusColorType = "Warning",
	},
	{
		id = "HIGH_PRESTIGE",
		label = "HIGH PRESTIGE ($125M)",
		cash = 125000000,
		threshold = 1000000,
		diamonds = 11,
		currentVaultDiamonds = 24,
		nextDiamondThreshold = 250000000,
		ascensions = 8,
		isArmed = false,
		isLocked = false,
		statusText = "High-yield run active. Ready to extract 11 Diamonds into permanent storage.",
		statusColorType = "Positive",
	},
}

--------------------------------------------------------------------------------
-- CORE DESIGN TOKENS (Matching Shop & Settings Revamp)
--------------------------------------------------------------------------------

local Colors = {
	BaseMocha   = Color3.fromRGB(26, 22, 20),
	PanelMaroon = Color3.fromRGB(36, 30, 26),
	PanelDeep   = Color3.fromRGB(20, 16, 14),
	ButtonMuted = Color3.fromRGB(48, 40, 36),
	
	MatteGold   = Color3.fromRGB(212, 175, 55),
	BrightGold  = Color3.fromRGB(234, 179, 8),
	TextPrimary = Color3.fromRGB(245, 239, 230),
	TextDim     = Color3.fromRGB(160, 148, 140),
	TextSubtle  = Color3.fromRGB(140, 130, 120),
	
	Positive    = Color3.fromRGB(74, 222, 128),
	Negative    = Color3.fromRGB(248, 113, 113),
	AlertRed    = Color3.fromRGB(220, 38, 38),
	Diamonds    = Color3.fromRGB(244, 114, 182),
	AscendPurple= Color3.fromRGB(168, 85, 247),
	
	BorderSubtle= Color3.fromRGB(70, 58, 48),
	BorderLost  = Color3.fromRGB(160, 65, 65),
	BorderKept  = Color3.fromRGB(65, 160, 90),
}

local function createPadding(parent: Instance, top: number, bottom: number, left: number, right: number): UIPadding
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingBottom = UDim.new(0, bottom)
	pad.PaddingLeft = UDim.new(0, left)
	pad.PaddingRight = UDim.new(0, right)
	pad.Parent = parent
	return pad
end

local function createCorner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createBorderStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function formatCash(amount: number): string
	if amount >= 1000000000 then
		return string.format("%.2fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("%.2fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("%.1fK", amount / 1000)
	else
		return tostring(amount)
	end
end

type VariantControls = {
	root: Frame,
	rewardLabel: TextLabel,
	progressLabel: TextLabel,
	meterFill: Frame,
	postVaultVal: TextLabel,
	nextTierVal: TextLabel,
	boostVal: TextLabel,
	statusLabel: TextLabel,
	ascendButton: TextButton,
	updateState: (state: PreviewState) -> (),
}

-- -----------------------------------------------------------------------------
-- [SOVEREIGN VAULT MASTER] - Fully Density-Balanced with Integrated Metrics
-- -----------------------------------------------------------------------------
local function buildSovereignVault(parent: Instance): VariantControls
	local root = Instance.new("Frame")
	root.Name = "SovereignVaultMaster"
	root.Size = UDim2.new(0, 920, 0, 610)
	root.Position = UDim2.new(0.5, 0, 0, 116)
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.BackgroundColor3 = Colors.BaseMocha
	root.BorderSizePixel = 0
	root.Parent = parent
	createCorner(root, 14)
	createBorderStroke(root, Colors.MatteGold, 2)
	createPadding(root, 14, 14, 16, 16)

	local rootLayout = Instance.new("UIListLayout")
	rootLayout.Padding = UDim.new(0, 10)
	rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rootLayout.Parent = root

	-- 1. Main Title Bar
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 48)
	header.BackgroundColor3 = Colors.PanelMaroon
	header.BorderSizePixel = 0
	header.LayoutOrder = 1
	header.Parent = root
	createCorner(header, 8)
	createBorderStroke(header, Colors.MatteGold, 1)
	createPadding(header, 0, 0, 16, 16)

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, 12)
	headerLayout.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.Size = UDim2.new(1, -190, 1, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Font = Enum.Font.GothamBold
	headerTitle.Text = "~ The Sovereign Ascension Vault ~"
	headerTitle.TextColor3 = Colors.MatteGold
	headerTitle.TextSize = 21
	headerTitle.TextStrokeTransparency = 1
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.LayoutOrder = 1
	headerTitle.Parent = header

	local folioBadge = Instance.new("Frame")
	folioBadge.Name = "FolioBadge"
	folioBadge.Size = UDim2.new(0, 170, 0, 28)
	folioBadge.BackgroundColor3 = Colors.PanelDeep
	folioBadge.BorderSizePixel = 0
	folioBadge.LayoutOrder = 2
	folioBadge.Parent = header
	createCorner(folioBadge, 4)
	createBorderStroke(folioBadge, Colors.MatteGold, 1)

	local folioLabel = Instance.new("TextLabel")
	folioLabel.Size = UDim2.fromScale(1, 1)
	folioLabel.BackgroundTransparency = 1
	folioLabel.Font = Enum.Font.Code
	folioLabel.Text = "VAULT-09 // PRESTIGE"
	folioLabel.TextColor3 = Colors.MatteGold
	folioLabel.TextSize = 11
	folioLabel.TextStrokeTransparency = 1
	folioLabel.Parent = folioBadge

	-- 2. Body Container (Left 38% Command Pod + Right 62% Stacked Cards)
	local bodyRow = Instance.new("Frame")
	bodyRow.Name = "BodyRow"
	bodyRow.Size = UDim2.new(1, 0, 0, 524)
	bodyRow.BackgroundTransparency = 1
	bodyRow.LayoutOrder = 2
	bodyRow.Parent = root

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Horizontal
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 12)
	bodyLayout.Parent = bodyRow

	-- =========================================================================
	-- LEFT COLUMN: Fully Density-Balanced Prestige Command Pod
	-- =========================================================================
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftCommandCol"
	leftCol.Size = UDim2.new(0.38, -6, 1, 0)
	leftCol.BackgroundColor3 = Colors.PanelMaroon
	leftCol.BorderSizePixel = 0
	leftCol.LayoutOrder = 1
	leftCol.Parent = bodyRow
	createCorner(leftCol, 10)
	createBorderStroke(leftCol, Colors.MatteGold, 1)
	createPadding(leftCol, 12, 12, 14, 14)

	local leftLayout = Instance.new("UIListLayout")
	leftLayout.Padding = UDim.new(0, 7)
	leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Parent = leftCol

	-- Section Badge
	local leftTagFrame = Instance.new("Frame")
	leftTagFrame.Size = UDim2.new(1, 0, 0, 24)
	leftTagFrame.BackgroundColor3 = Colors.PanelDeep
	leftTagFrame.BorderSizePixel = 0
	leftTagFrame.LayoutOrder = 1
	leftTagFrame.Parent = leftCol
	createCorner(leftTagFrame, 4)
	createBorderStroke(leftTagFrame, Colors.BorderSubtle, 1)

	local leftTag = Instance.new("TextLabel")
	leftTag.Size = UDim2.fromScale(1, 1)
	leftTag.BackgroundTransparency = 1
	leftTag.Font = Enum.Font.Code
	leftTag.Text = "[ 01 // PRESTIGE EXTRACTION ]"
	leftTag.TextColor3 = Colors.MatteGold
	leftTag.TextSize = 11
	leftTag.TextStrokeTransparency = 1
	leftTag.Parent = leftTagFrame

	-- Primary Yield Readout
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "AscendReward"
	rewardLabel.Size = UDim2.new(1, 0, 0, 44)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Font = Enum.Font.GothamBlack
	rewardLabel.Text = "+2 \u{2666} DIAMONDS"
	rewardLabel.TextColor3 = Colors.Diamonds
	rewardLabel.TextSize = 32
	rewardLabel.TextStrokeTransparency = 1
	rewardLabel.LayoutOrder = 2
	rewardLabel.Parent = leftCol

	local rewardSub = Instance.new("TextLabel")
	rewardSub.Size = UDim2.new(1, 0, 0, 16)
	rewardSub.BackgroundTransparency = 1
	rewardSub.Font = Enum.Font.GothamMedium
	rewardSub.Text = "Guaranteed Permanent Vault Asset"
	rewardSub.TextColor3 = Colors.TextDim
	rewardSub.TextSize = 12
	rewardSub.TextStrokeTransparency = 1
	rewardSub.LayoutOrder = 3
	rewardSub.Parent = leftCol

	-- Progress Bar Meter
	local meterTrack = Instance.new("Frame")
	meterTrack.Name = "MeterTrack"
	meterTrack.Size = UDim2.new(1, 0, 0, 10)
	meterTrack.BackgroundColor3 = Colors.PanelDeep
	meterTrack.BorderSizePixel = 0
	meterTrack.LayoutOrder = 4
	meterTrack.Parent = leftCol
	createCorner(meterTrack, 5)
	createBorderStroke(meterTrack, Colors.BorderSubtle, 1)

	local meterFill = Instance.new("Frame")
	meterFill.Name = "MeterFill"
	meterFill.Size = UDim2.fromScale(1, 1)
	meterFill.BackgroundColor3 = Colors.MatteGold
	meterFill.BorderSizePixel = 0
	meterFill.Parent = meterTrack
	createCorner(meterFill, 5)

	-- Basis & Progress Text
	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "AscendProgress"
	progressLabel.Size = UDim2.new(1, 0, 0, 20)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamBold
	progressLabel.Text = "Run Basis: $4.50M / $1.00M"
	progressLabel.TextColor3 = Colors.TextPrimary
	progressLabel.TextSize = 13
	progressLabel.TextStrokeTransparency = 1
	progressLabel.LayoutOrder = 5
	progressLabel.Parent = leftCol

	-- =========================================================================
	-- NEW: RECESSED LIFETIME METRICS & PERKS POD (Fills the bottom space!)
	-- =========================================================================
	local metricsCard = Instance.new("Frame")
	metricsCard.Name = "LifetimeMetricsPod"
	metricsCard.Size = UDim2.new(1, 0, 0, 140)
	metricsCard.BackgroundColor3 = Colors.PanelDeep
	metricsCard.BorderSizePixel = 0
	metricsCard.LayoutOrder = 6
	metricsCard.Parent = leftCol
	createCorner(metricsCard, 8)
	createBorderStroke(metricsCard, Colors.BorderSubtle, 1)
	createPadding(metricsCard, 8, 8, 10, 10)

	local metricsLayout = Instance.new("UIListLayout")
	metricsLayout.Padding = UDim.new(0, 5)
	metricsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	metricsLayout.Parent = metricsCard

	local mHeader = Instance.new("TextLabel")
	mHeader.Size = UDim2.new(1, 0, 0, 18)
	mHeader.BackgroundTransparency = 1
	mHeader.Font = Enum.Font.GothamBold
	mHeader.Text = "VAULT YIELD & PROJECTIONS"
	mHeader.TextColor3 = Colors.MatteGold
	mHeader.TextSize = 11
	mHeader.TextStrokeTransparency = 1
	mHeader.TextXAlignment = Enum.TextXAlignment.Left
	mHeader.LayoutOrder = 1
	mHeader.Parent = metricsCard

	-- Row 1: Post-Reset Vault Total
	local row1 = Instance.new("Frame")
	row1.Size = UDim2.new(1, 0, 0, 26)
	row1.BackgroundTransparency = 1
	row1.LayoutOrder = 2
	row1.Parent = metricsCard

	local r1Label = Instance.new("TextLabel")
	r1Label.Size = UDim2.new(0.6, 0, 1, 0)
	r1Label.BackgroundTransparency = 1
	r1Label.Font = Enum.Font.Gotham
	r1Label.Text = "Post-Reset Vault Total:"
	r1Label.TextColor3 = Colors.TextDim
	r1Label.TextSize = 12
	r1Label.TextStrokeTransparency = 1
	r1Label.TextXAlignment = Enum.TextXAlignment.Left
	r1Label.Parent = row1

	local postVaultVal = Instance.new("TextLabel")
	postVaultVal.Name = "PostVaultVal"
	postVaultVal.Size = UDim2.new(0.4, 0, 1, 0)
	postVaultVal.Position = UDim2.new(0.6, 0, 0, 0)
	postVaultVal.BackgroundTransparency = 1
	postVaultVal.Font = Enum.Font.GothamBold
	postVaultVal.Text = "10 \u{2666} (+2)"
	postVaultVal.TextColor3 = Colors.Diamonds
	postVaultVal.TextSize = 13
	postVaultVal.TextStrokeTransparency = 1
	postVaultVal.TextXAlignment = Enum.TextXAlignment.Right
	postVaultVal.Parent = row1

	-- Row 2: Next Yield Milestone
	local row2 = Instance.new("Frame")
	row2.Size = UDim2.new(1, 0, 0, 26)
	row2.BackgroundTransparency = 1
	row2.LayoutOrder = 3
	row2.Parent = metricsCard

	local r2Label = Instance.new("TextLabel")
	r2Label.Size = UDim2.new(0.55, 0, 1, 0)
	r2Label.BackgroundTransparency = 1
	r2Label.Font = Enum.Font.Gotham
	r2Label.Text = "Next Diamond Tier:"
	r2Label.TextColor3 = Colors.TextDim
	r2Label.TextSize = 12
	r2Label.TextStrokeTransparency = 1
	r2Label.TextXAlignment = Enum.TextXAlignment.Left
	r2Label.Parent = row2

	local nextTierVal = Instance.new("TextLabel")
	nextTierVal.Name = "NextTierVal"
	nextTierVal.Size = UDim2.new(0.45, 0, 1, 0)
	nextTierVal.Position = UDim2.new(0.55, 0, 0, 0)
	nextTierVal.BackgroundTransparency = 1
	nextTierVal.Font = Enum.Font.GothamBold
	nextTierVal.Text = "at $10.00M"
	nextTierVal.TextColor3 = Colors.MatteGold
	nextTierVal.TextSize = 13
	nextTierVal.TextStrokeTransparency = 1
	nextTierVal.TextXAlignment = Enum.TextXAlignment.Right
	nextTierVal.Parent = row2

	-- Row 3: Career Resets & Multiplier
	local row3 = Instance.new("Frame")
	row3.Size = UDim2.new(1, 0, 0, 26)
	row3.BackgroundTransparency = 1
	row3.LayoutOrder = 4
	row3.Parent = metricsCard

	local r3Label = Instance.new("TextLabel")
	r3Label.Size = UDim2.new(0.6, 0, 1, 0)
	r3Label.BackgroundTransparency = 1
	r3Label.Font = Enum.Font.Gotham
	r3Label.Text = "Career Ascensions:"
	r3Label.TextColor3 = Colors.TextDim
	r3Label.TextSize = 12
	r3Label.TextStrokeTransparency = 1
	r3Label.TextXAlignment = Enum.TextXAlignment.Left
	r3Label.Parent = row3

	local boostVal = Instance.new("TextLabel")
	boostVal.Name = "CareerAscendVal"
	boostVal.Size = UDim2.new(0.4, 0, 1, 0)
	boostVal.Position = UDim2.new(0.6, 0, 0, 0)
	boostVal.BackgroundTransparency = 1
	boostVal.Font = Enum.Font.GothamBold
	boostVal.Text = "3 Completed"
	boostVal.TextColor3 = Colors.Positive
	boostVal.TextSize = 13
	boostVal.TextStrokeTransparency = 1
	boostVal.TextXAlignment = Enum.TextXAlignment.Right
	boostVal.Parent = row3

	-- Large Punchy Action Button
	local ascendBtn = Instance.new("TextButton")
	ascendBtn.Name = "AscendButton"
	ascendBtn.Size = UDim2.new(1, 0, 0, 56)
	ascendBtn.BackgroundColor3 = Colors.MatteGold
	ascendBtn.BorderSizePixel = 0
	ascendBtn.Font = Enum.Font.GothamBold
	ascendBtn.Text = "SEAL THE VAULT & ASCEND"
	ascendBtn.TextColor3 = Colors.BaseMocha
	ascendBtn.TextSize = 15
	ascendBtn.TextStrokeTransparency = 1
	ascendBtn.LayoutOrder = 7
	ascendBtn.Parent = leftCol
	createCorner(ascendBtn, 8)
	createBorderStroke(ascendBtn, Colors.MatteGold, 1)

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "AscendStatus"
	statusLabel.Size = UDim2.new(1, 0, 0, 48)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Text = "Ready to ascend. Press button to begin two-step confirmation."
	statusLabel.TextColor3 = Colors.MatteGold
	statusLabel.TextSize = 12
	statusLabel.TextStrokeTransparency = 1
	statusLabel.TextWrapped = true
	statusLabel.LayoutOrder = 8
	statusLabel.Parent = leftCol

	-- =========================================================================
	-- RIGHT COLUMN: Stacked Cards (Preserved Wealth & Forfeit Assets)
	-- =========================================================================
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightLedgerCol"
	rightCol.Size = UDim2.new(0.62, -6, 1, 0)
	rightCol.BackgroundTransparency = 1
	rightCol.LayoutOrder = 2
	rightCol.Parent = bodyRow

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.Padding = UDim.new(0, 10)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Parent = rightCol

	-- TOP CARD: Preserved Wealth Card (YOU KEEP)
	local keptCard = Instance.new("Frame")
	keptCard.Name = "KeptCard"
	keptCard.Size = UDim2.new(1, 0, 0, 257)
	keptCard.BackgroundColor3 = Colors.PanelMaroon
	keptCard.BorderSizePixel = 0
	keptCard.LayoutOrder = 1
	keptCard.Parent = rightCol
	createCorner(keptCard, 10)
	createBorderStroke(keptCard, Colors.BorderKept, 1)
	createPadding(keptCard, 12, 12, 16, 16)

	local keptLayout = Instance.new("UIListLayout")
	keptLayout.Padding = UDim.new(0, 5)
	keptLayout.SortOrder = Enum.SortOrder.LayoutOrder
	keptLayout.Parent = keptCard

	local keptTitle = Instance.new("TextLabel")
	keptTitle.Name = "KeptTitle"
	keptTitle.Size = UDim2.new(1, 0, 0, 24)
	keptTitle.BackgroundTransparency = 1
	keptTitle.Font = Enum.Font.GothamBold
	keptTitle.Text = "\u{25B2} IMMUTABLE ASSETS (YOU KEEP)"
	keptTitle.TextColor3 = Colors.Positive
	keptTitle.TextSize = 15
	keptTitle.TextStrokeTransparency = 1
	keptTitle.TextXAlignment = Enum.TextXAlignment.Left
	keptTitle.LayoutOrder = 1
	keptTitle.Parent = keptCard

	local keptItems = {
		"+ Every Diamond, plus newly extracted yield",
		"+ Unlocked Dice Shapes & Elemental Masteries",
		"+ Diamond Tree Progression Perks & Multipliers",
		"+ All Purchased Gamepass Privileges",
		"+ Redeemed Promo Codes & Daily Login Streak",
	}
	for i, itemText in ipairs(keptItems) do
		local row = Instance.new("TextLabel")
		row.Name = "Credit_" .. i
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.Text = itemText
		row.TextColor3 = Colors.TextPrimary
		row.TextSize = 14
		row.TextStrokeTransparency = 1
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i + 1
		row.Parent = keptCard
	end

	-- BOTTOM CARD: Forfeit Assets Card (YOU LOSE)
	local lostCard = Instance.new("Frame")
	lostCard.Name = "LostCard"
	lostCard.Size = UDim2.new(1, 0, 0, 257)
	lostCard.BackgroundColor3 = Colors.PanelMaroon
	lostCard.BorderSizePixel = 0
	lostCard.LayoutOrder = 2
	lostCard.Parent = rightCol
	createCorner(lostCard, 10)
	createBorderStroke(lostCard, Colors.BorderLost, 1)
	createPadding(lostCard, 12, 12, 16, 16)

	local lostLayout = Instance.new("UIListLayout")
	lostLayout.Padding = UDim.new(0, 5)
	lostLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lostLayout.Parent = lostCard

	local lostTitle = Instance.new("TextLabel")
	lostTitle.Name = "LostTitle"
	lostTitle.Size = UDim2.new(1, 0, 0, 24)
	lostTitle.BackgroundTransparency = 1
	lostTitle.Font = Enum.Font.GothamBold
	lostTitle.Text = "\u{25BC} FORFEIT ON RESET (YOU LOSE)"
	lostTitle.TextColor3 = Colors.Negative
	lostTitle.TextSize = 15
	lostTitle.TextStrokeTransparency = 1
	lostTitle.TextXAlignment = Enum.TextXAlignment.Left
	lostTitle.LayoutOrder = 1
	lostTitle.Parent = lostCard

	local lostItems = {
		"\u{2014} All Current Cash Balance (Reset to $0)",
		"\u{2014} All Gem Holdings (Expended on Reset)",
		"\u{2014} All Purchased Cash Multiplier Upgrades",
		"\u{2014} Active Dice Collection (Reset to 1x D2)",
		"\u{2014} Unlocked Extra Die Slots",
	}
	for i, itemText in ipairs(lostItems) do
		local row = Instance.new("TextLabel")
		row.Name = "Debit_" .. i
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.Text = itemText
		row.TextColor3 = Colors.TextPrimary
		row.TextSize = 14
		row.TextStrokeTransparency = 1
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i + 1
		row.Parent = lostCard
	end

	local function updateState(state: PreviewState)
		if state.diamonds > 0 then
			rewardLabel.Text = string.format("+%d \u{2666} DIAMONDS", state.diamonds)
			rewardLabel.TextColor3 = Colors.Diamonds
			meterFill.Size = UDim2.fromScale(math.min(1, state.cash / state.threshold), 1)
			meterFill.BackgroundColor3 = Colors.MatteGold
		else
			rewardLabel.Text = "+0 \u{2666} DIAMONDS"
			rewardLabel.TextColor3 = Colors.TextSubtle
			meterFill.Size = UDim2.fromScale(math.min(1, state.cash / state.threshold), 1)
			meterFill.BackgroundColor3 = Colors.AlertRed
		end

		progressLabel.Text = string.format("Run Basis: $%s / $%s", formatCash(state.cash), formatCash(state.threshold))

		local newTotal = state.currentVaultDiamonds + state.diamonds
		postVaultVal.Text = string.format("%d \u{2666} (+%d)", newTotal, state.diamonds)
		nextTierVal.Text = string.format("at $%s", formatCash(state.nextDiamondThreshold))
		boostVal.Text = string.format("%d Completed", state.ascensions)

		if state.isArmed then
			ascendBtn.BackgroundColor3 = Colors.AlertRed
			ascendBtn.Text = "CONFIRM SETTLEMENT? (NO UNDO)"
			ascendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			createBorderStroke(ascendBtn, Color3.fromRGB(255, 215, 0), 2)
		elseif state.isLocked then
			ascendBtn.BackgroundColor3 = Colors.ButtonMuted
			ascendBtn.Text = "UNAVAILABLE // INSUFFICIENT CASH"
			ascendBtn.TextColor3 = Colors.TextSubtle
			createBorderStroke(ascendBtn, Colors.BorderSubtle, 1)
		else
			ascendBtn.BackgroundColor3 = Colors.MatteGold
			ascendBtn.Text = "SEAL THE VAULT & ASCEND"
			ascendBtn.TextColor3 = Colors.BaseMocha
			createBorderStroke(ascendBtn, Colors.MatteGold, 1)
		end

		statusLabel.Text = state.statusText
		if state.statusColorType == "Warning" or state.statusColorType == "Negative" then
			statusLabel.TextColor3 = Colors.Negative
		elseif state.statusColorType == "Positive" then
			statusLabel.TextColor3 = Colors.Positive
		else
			statusLabel.TextColor3 = Colors.MatteGold
		end
	end

	return {
		root = root,
		rewardLabel = rewardLabel,
		progressLabel = progressLabel,
		meterFill = meterFill,
		postVaultVal = postVaultVal,
		nextTierVal = nextTierVal,
		boostVal = boostVal,
		statusLabel = statusLabel,
		ascendButton = ascendBtn,
		updateState = updateState,
	}
end

--------------------------------------------------------------------------------
-- MAIN SHELL (SHOW & HIDE)
--------------------------------------------------------------------------------

function UIMockPreview.show(): ScreenGui
	for _, parent in ipairs({game:GetService("StarterGui"), game:GetService("CoreGui")}) do
		local old = parent:FindFirstChild("UIMockPreview")
		if old then old:Destroy() end
	end

	local localPlayer = Players.LocalPlayer
	local targetParent: Instance = game:GetService("StarterGui")
	if localPlayer then
		local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
		if pg then
			targetParent = pg
			local old = pg:FindFirstChild("UIMockPreview")
			if old then old:Destroy() end
		end
	end

	local oldV7 = targetParent:FindFirstChild("V7MenuGui")
	if oldV7 and oldV7:IsA("ScreenGui") then
		oldV7.Enabled = false
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UIMockPreview"
	screenGui.DisplayOrder = 10000
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Parent = targetParent
	currentGui = screenGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Colors.PanelDeep
	backdrop.BackgroundTransparency = 0.08
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui

	-- =========================================================================
	-- TOP FLOATING CONTROLLER BAR
	-- =========================================================================
	local controlBar = Instance.new("Frame")
	controlBar.Name = "CarouselControlBar"
	controlBar.Size = UDim2.new(0, 920, 0, 48)
	controlBar.Position = UDim2.new(0.5, 0, 0, 16)
	controlBar.AnchorPoint = Vector2.new(0.5, 0)
	controlBar.BackgroundColor3 = Colors.BaseMocha
	controlBar.BorderSizePixel = 0
	controlBar.Parent = backdrop
	createCorner(controlBar, 8)
	createBorderStroke(controlBar, Colors.MatteGold, 1)
	createPadding(controlBar, 5, 5, 8, 8)

	local controlLayout = Instance.new("UIListLayout")
	controlLayout.FillDirection = Enum.FillDirection.Horizontal
	controlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlLayout.Padding = UDim.new(0, 10)
	controlLayout.Parent = controlBar

	local indicatorPill = Instance.new("Frame")
	indicatorPill.Name = "IndicatorPill"
	indicatorPill.Size = UDim2.new(0, 680, 0, 36)
	indicatorPill.BackgroundColor3 = Colors.PanelDeep
	indicatorPill.BorderSizePixel = 0
	indicatorPill.LayoutOrder = 1
	indicatorPill.Parent = controlBar
	createCorner(indicatorPill, 6)
	createBorderStroke(indicatorPill, Colors.MatteGold, 1)

	local indicatorLabel = Instance.new("TextLabel")
	indicatorLabel.Name = "IndicatorLabel"
	indicatorLabel.Size = UDim2.fromScale(1, 1)
	indicatorLabel.BackgroundTransparency = 1
	indicatorLabel.Font = Enum.Font.GothamBold
	indicatorLabel.Text = "SOVEREIGN VAULT (DENSITY BALANCED & TELEMETRY POD)"
	indicatorLabel.TextColor3 = Colors.TextPrimary
	indicatorLabel.TextSize = 14
	indicatorLabel.TextStrokeTransparency = 1
	indicatorLabel.Parent = indicatorPill

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 120, 0, 36)
	closeBtn.BackgroundColor3 = Color3.fromRGB(60, 24, 24)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "\u{00D7} CLOSE"
	closeBtn.TextColor3 = Colors.Negative
	closeBtn.TextSize = 13
	closeBtn.TextStrokeTransparency = 1
	closeBtn.LayoutOrder = 2
	closeBtn.Parent = controlBar
	createCorner(closeBtn, 6)
	createBorderStroke(closeBtn, Colors.BorderLost, 1)

	closeBtn.MouseButton1Click:Connect(function()
		UIMockPreview.hide()
	end)

	-- =========================================================================
	-- SECONDARY STATE SWITCHER TOOLBAR (Allows real-time state testing)
	-- =========================================================================
	local stateBar = Instance.new("Frame")
	stateBar.Name = "StateSwitcherBar"
	stateBar.Size = UDim2.new(0, 920, 0, 36)
	stateBar.Position = UDim2.new(0.5, 0, 0, 70)
	stateBar.AnchorPoint = Vector2.new(0.5, 0)
	stateBar.BackgroundTransparency = 1
	stateBar.Parent = backdrop

	local stateLayout = Instance.new("UIListLayout")
	stateLayout.FillDirection = Enum.FillDirection.Horizontal
	stateLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stateLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stateLayout.Padding = UDim.new(0, 10)
	stateLayout.Parent = stateBar

	local stateButtons: { TextButton } = {}

	local design = buildSovereignVault(backdrop)

	local function refreshAll()
		local activeState = PREVIEW_STATES[activeStateIndex]

		for i, btn in ipairs(stateButtons) do
			if i == activeStateIndex then
				btn.BackgroundColor3 = Colors.MatteGold
				btn.TextColor3 = Colors.BaseMocha
			else
				btn.BackgroundColor3 = Colors.PanelMaroon
				btn.TextColor3 = Colors.TextDim
			end
		end

		design.updateState(activeState)
		design.root.Visible = true
	end

	for i, state in ipairs(PREVIEW_STATES) do
		local btn = Instance.new("TextButton")
		btn.Name = "StateBtn_" .. state.id
		btn.Size = UDim2.new(0, 218, 1, 0)
		btn.BackgroundColor3 = Colors.PanelMaroon
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.Text = state.label
		btn.TextColor3 = Colors.TextDim
		btn.TextSize = 12
		btn.TextStrokeTransparency = 1
		btn.LayoutOrder = i
		btn.Parent = stateBar
		createCorner(btn, 4)
		createBorderStroke(btn, Colors.BorderSubtle, 1)

		btn.MouseButton1Click:Connect(function()
			activeStateIndex = i
			refreshAll()
		end)

		table.insert(stateButtons, btn)
	end

	design.ascendButton.MouseButton1Click:Connect(function()
		if activeStateIndex == 1 then
			activeStateIndex = 3
			refreshAll()
		elseif activeStateIndex == 3 then
			activeStateIndex = 1
			refreshAll()
		end
	end)

	refreshAll()

	print("[UIMockPreview] Sovereign Vault Master Edition with Telemetry Pod displayed.")
	return screenGui
end

function UIMockPreview.hide(): ()
	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end
	for _, parent in ipairs({game:GetService("StarterGui"), game:GetService("CoreGui")}) do
		local old = parent:FindFirstChild("UIMockPreview")
		if old then old:Destroy() end
	end
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
		if pg then
			local old = pg:FindFirstChild("UIMockPreview")
			if old then old:Destroy() end
		end
	end
	print("[UIMockPreview] Cleanly destroyed preview.")
end

return UIMockPreview
`;

fs.writeFileSync('C:\\RGame\\src\\Client\\UIMockPreview.luau', code, 'utf8');
console.log('Successfully generated Sovereign Vault Master with Telemetry Pod!');
