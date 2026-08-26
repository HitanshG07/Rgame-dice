--!strict
--[=[
    UIMockPreview.luau
    DICE ROLL RESULT BAR IMPROVEMENT MOCK PREVIEW (3 Variations)

    Addresses the user-reported issues in the roll summary bar:
      1. TextScaled distortion causing giant text on short labels (D12: 2) and tiny text on grouped labels (2x D10 (SUM: 8)).
      2. Clunky and redundant '(SUM: X)' syntax.
      3. Lack of visual hierarchy between die shape, count, and result value.
      4. Missing overall roll total readout.

    Variations:
      - Variant 1: "Split Badge Chips"
          Two-tone pills with tinted shape/count badge on the left, dark recessed score on the right,
          fixed 12px/13px typography, and gold [TOTAL] chip.
      - Variant 2: "Compact Micro-Chits"
          Tournament-style chits with glowing circular die-color pip, clean 'D10 ×2 → 8' notation,
          and a burnished gold total badge.
      - Variant 3: "Polished Minimalist"
          Single-pill format with 15% luminous die-color tint fill, crisp '2× D10 : 8' notation,
          and uniform non-scaling typography across all chips.

    Run from Roblox Studio Command Bar:
        require(game.StarterPlayer.StarterPlayerScripts.Client.UIMockPreview).show()
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local UIMockPreview = {}

--------------------------------------------------------------------------------
-- COLOR & DICE PALETTE
--------------------------------------------------------------------------------

local PALETTE = {
	BackdropMocha   = Color3.fromRGB(20, 16, 14),
	SurfaceDark     = Color3.fromRGB(26, 22, 20),
	SurfacePanel    = Color3.fromRGB(32, 26, 22),
	SurfaceElevated = Color3.fromRGB(44, 36, 30),
	SurfaceRecessed = Color3.fromRGB(18, 14, 12),

	GoldPrimary     = Color3.fromRGB(234, 179, 8),
	GoldBright      = Color3.fromRGB(250, 204, 21),
	GoldBurnished   = Color3.fromRGB(190, 145, 45),

	StrokeGold      = Color3.fromRGB(212, 165, 40),
	StrokeSubtle    = Color3.fromRGB(55, 45, 38),
	StrokeSharp     = Color3.fromRGB(70, 60, 50),

	TextPrimary     = Color3.fromRGB(245, 239, 230),
	TextMuted       = Color3.fromRGB(160, 148, 140),
	NegativeRed     = Color3.fromRGB(239, 68, 68),
	PositiveGreen   = Color3.fromRGB(34, 197, 94),
}

local diceColorsByShape: { [string]: Color3 } = {
	D2  = Color3.fromRGB(240, 180, 50),  -- Gold/Yellow
	D3  = Color3.fromRGB(230, 120, 60),  -- Deep Orange
	D4  = Color3.fromRGB(150, 80, 220),  -- Purple
	D5  = Color3.fromRGB(190, 190, 200), -- Silver/White
	D6  = Color3.fromRGB(50, 160, 220),  -- Cyan
	D8  = Color3.fromRGB(60, 190, 120),  -- Green
	D10 = Color3.fromRGB(230, 140, 40),  -- Orange
	D12 = Color3.fromRGB(220, 70, 150),  -- Pink/Magenta
	D20 = Color3.fromRGB(70, 130, 240),  -- Blue
}

--------------------------------------------------------------------------------
-- SAMPLE ROLL DATA (MATCHING EXACT USER SCREENSHOT + TEST PRESETS)
--------------------------------------------------------------------------------

type RollItem = { shape: string, count: number, sum: number }

local samplePresets: { { name: string, items: { RollItem } } } = {
	{
		name = "User Screenshot (7 Types, 11 Dice)",
		items = {
			{ shape = "D10", count = 2, sum = 8 },
			{ shape = "D12", count = 1, sum = 2 },
			{ shape = "D2",  count = 1, sum = 2 },
			{ shape = "D4",  count = 1, sum = 2 },
			{ shape = "D5",  count = 1, sum = 4 },
			{ shape = "D6",  count = 3, sum = 10 },
			{ shape = "D8",  count = 1, sum = 3 },
		},
	},
	{
		name = "Single Dice Duo (2 Items)",
		items = {
			{ shape = "D6",  count = 1, sum = 6 },
			{ shape = "D20", count = 1, sum = 18 },
		},
	},
	{
		name = "Heavy Multi-Dice Roll (4 Types, 14 Dice)",
		items = {
			{ shape = "D4",  count = 4, sum = 12 },
			{ shape = "D6",  count = 5, sum = 24 },
			{ shape = "D10", count = 3, sum = 21 },
			{ shape = "D20", count = 2, sum = 35 },
		},
	},
}

local activePresetIndex = 1

--------------------------------------------------------------------------------
-- VARIANT 1 BUILDER: "SPLIT BADGE CHIPS"
--------------------------------------------------------------------------------

local function buildVariant1(parent: Frame, items: { RollItem }): Frame
	local bar = Instance.new("Frame")
	bar.Name = "ResultBar_Variant1"
	bar.Size = UDim2.new(0.96, 0, 0, 42)
	bar.Position = UDim2.new(0.5, 0, 1, -118)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
	bar.BorderSizePixel = 0
	bar.ZIndex = 20
	bar.Parent = parent

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 10)
	bCorner.Parent = bar

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(50, 40, 34)
	bStroke.Thickness = 1.2
	bStroke.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bar

	local grandTotal = 0

	for _, itemData in ipairs(items) do
		grandTotal += itemData.sum
		local color = diceColorsByShape[itemData.shape] or Color3.fromRGB(200, 200, 200)

		-- Chip container
		local chip = Instance.new("Frame")
		chip.Name = "Chip_" .. itemData.shape
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.new(0, 0, 0, 30)
		chip.BackgroundColor3 = Color3.fromRGB(28, 22, 19)
		chip.BorderSizePixel = 0
		chip.ZIndex = 21
		chip.Parent = bar

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 6)
		cCorner.Parent = chip

		local cStroke = Instance.new("UIStroke")
		cStroke.Color = color
		cStroke.Thickness = 1.2
		cStroke.Parent = chip

		local cLayout = Instance.new("UIListLayout")
		cLayout.FillDirection = Enum.FillDirection.Horizontal
		cLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		cLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cLayout.Parent = chip

		-- Left Badge: Shape + Count tag
		local shapeTag = if itemData.count > 1
			then string.format("%s ×%d", itemData.shape, itemData.count)
			else itemData.shape

		local leftBadge = Instance.new("Frame")
		leftBadge.Name = "LeftBadge"
		leftBadge.LayoutOrder = 1
		leftBadge.AutomaticSize = Enum.AutomaticSize.X
		leftBadge.Size = UDim2.new(0, 0, 1, 0)
		leftBadge.BackgroundColor3 = color
		leftBadge.BackgroundTransparency = 0.82
		leftBadge.BorderSizePixel = 0
		leftBadge.ZIndex = 22
		leftBadge.Parent = chip

		local lbPad = Instance.new("UIPadding")
		lbPad.PaddingLeft = UDim.new(0, 8)
		lbPad.PaddingRight = UDim.new(0, 8)
		lbPad.Parent = leftBadge

		local lbCorner = Instance.new("UICorner")
		lbCorner.CornerRadius = UDim.new(0, 5)
		lbCorner.Parent = leftBadge

		local shapeLbl = Instance.new("TextLabel")
		shapeLbl.AutomaticSize = Enum.AutomaticSize.X
		shapeLbl.Size = UDim2.new(0, 0, 1, 0)
		shapeLbl.BackgroundTransparency = 1
		shapeLbl.Font = Enum.Font.GothamBold
		shapeLbl.Text = shapeTag
		shapeLbl.TextColor3 = color
		shapeLbl.TextSize = 12
		shapeLbl.ZIndex = 23
		shapeLbl.Parent = leftBadge

		-- Right Badge: Value score
		local rightBadge = Instance.new("Frame")
		rightBadge.Name = "RightBadge"
		rightBadge.LayoutOrder = 2
		rightBadge.AutomaticSize = Enum.AutomaticSize.X
		rightBadge.Size = UDim2.new(0, 0, 1, 0)
		rightBadge.BackgroundTransparency = 1
		rightBadge.ZIndex = 22
		rightBadge.Parent = chip

		local rbPad = Instance.new("UIPadding")
		rbPad.PaddingLeft = UDim.new(0, 9)
		rbPad.PaddingRight = UDim.new(0, 9)
		rbPad.Parent = rightBadge

		local valLbl = Instance.new("TextLabel")
		valLbl.AutomaticSize = Enum.AutomaticSize.X
		valLbl.Size = UDim2.new(0, 0, 1, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Font = Enum.Font.GothamBlack
		valLbl.Text = tostring(itemData.sum)
		valLbl.TextColor3 = PALETTE.TextPrimary
		valLbl.TextSize = 13
		valLbl.ZIndex = 23
		valLbl.Parent = rightBadge
	end

	-- Grand Total Chip
	local totalChip = Instance.new("Frame")
	totalChip.Name = "TotalChip"
	totalChip.AutomaticSize = Enum.AutomaticSize.X
	totalChip.Size = UDim2.new(0, 0, 0, 30)
	totalChip.BackgroundColor3 = Color3.fromRGB(36, 28, 20)
	totalChip.BorderSizePixel = 0
	totalChip.ZIndex = 21
	totalChip.Parent = bar

	local tcCorner = Instance.new("UICorner")
	tcCorner.CornerRadius = UDim.new(0, 6)
	tcCorner.Parent = totalChip

	local tcStroke = Instance.new("UIStroke")
	tcStroke.Color = PALETTE.GoldPrimary
	tcStroke.Thickness = 1.4
	tcStroke.Parent = totalChip

	local tcPad = Instance.new("UIPadding")
	tcPad.PaddingLeft = UDim.new(0, 10)
	tcPad.PaddingRight = UDim.new(0, 10)
	tcPad.Parent = totalChip

	local tcLbl = Instance.new("TextLabel")
	tcLbl.AutomaticSize = Enum.AutomaticSize.X
	tcLbl.Size = UDim2.new(0, 0, 1, 0)
	tcLbl.BackgroundTransparency = 1
	tcLbl.Font = Enum.Font.GothamBlack
	tcLbl.Text = "TOTAL: " .. tostring(grandTotal)
	tcLbl.TextColor3 = PALETTE.GoldBright
	tcLbl.TextSize = 12
	tcLbl.ZIndex = 23
	tcLbl.Parent = totalChip

	return bar
end

--------------------------------------------------------------------------------
-- VARIANT 2 BUILDER: "COMPACT MICRO-CHITS"
--------------------------------------------------------------------------------

local function buildVariant2(parent: Frame, items: { RollItem }): Frame
	local bar = Instance.new("Frame")
	bar.Name = "ResultBar_Variant2"
	bar.Size = UDim2.new(0.96, 0, 0, 42)
	bar.Position = UDim2.new(0.5, 0, 1, -118)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
	bar.BorderSizePixel = 0
	bar.ZIndex = 20
	bar.Parent = parent

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 12)
	bCorner.Parent = bar

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(55, 42, 35)
	bStroke.Thickness = 1.2
	bStroke.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 7)
	layout.Parent = bar

	local grandTotal = 0

	for _, itemData in ipairs(items) do
		grandTotal += itemData.sum
		local color = diceColorsByShape[itemData.shape] or Color3.fromRGB(200, 200, 200)

		local chit = Instance.new("Frame")
		chit.Name = "Chit_" .. itemData.shape
		chit.AutomaticSize = Enum.AutomaticSize.X
		chit.Size = UDim2.new(0, 0, 0, 30)
		chit.BackgroundColor3 = Color3.fromRGB(26, 20, 17)
		chit.BorderSizePixel = 0
		chit.ZIndex = 21
		chit.Parent = bar

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 15)
		cCorner.Parent = chit

		local cStroke = Instance.new("UIStroke")
		cStroke.Color = color
		cStroke.Thickness = 1.2
		cStroke.Parent = chit

		local cPad = Instance.new("UIPadding")
		cPad.PaddingLeft = UDim.new(0, 8)
		cPad.PaddingRight = UDim.new(0, 10)
		cPad.Parent = chit

		local cLayout = Instance.new("UIListLayout")
		cLayout.FillDirection = Enum.FillDirection.Horizontal
		cLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		cLayout.Padding = UDim.new(0, 6)
		cLayout.Parent = chit

		-- Glowing Pip
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, 7, 0, 7)
		pip.BackgroundColor3 = color
		pip.BorderSizePixel = 0
		pip.ZIndex = 22
		pip.Parent = chit
		local pC = Instance.new("UICorner")
		pC.CornerRadius = UDim.new(1, 0)
		pC.Parent = pip

		-- Shape + Count
		local shapeTag = if itemData.count > 1
			then string.format("%s ×%d", itemData.shape, itemData.count)
			else itemData.shape

		local sLbl = Instance.new("TextLabel")
		sLbl.AutomaticSize = Enum.AutomaticSize.X
		sLbl.Size = UDim2.new(0, 0, 1, 0)
		sLbl.BackgroundTransparency = 1
		sLbl.Font = Enum.Font.GothamBold
		sLbl.Text = shapeTag
		sLbl.TextColor3 = PALETTE.TextPrimary
		sLbl.TextSize = 12
		sLbl.ZIndex = 22
		sLbl.Parent = chit

		-- Arrow divider
		local arr = Instance.new("TextLabel")
		arr.AutomaticSize = Enum.AutomaticSize.X
		arr.Size = UDim2.new(0, 0, 1, 0)
		arr.BackgroundTransparency = 1
		arr.Font = Enum.Font.GothamBold
		arr.Text = "→"
		arr.TextColor3 = color
		arr.TextSize = 11
		arr.ZIndex = 22
		arr.Parent = chit

		-- Value
		local vLbl = Instance.new("TextLabel")
		vLbl.AutomaticSize = Enum.AutomaticSize.X
		vLbl.Size = UDim2.new(0, 0, 1, 0)
		vLbl.BackgroundTransparency = 1
		vLbl.Font = Enum.Font.GothamBlack
		vLbl.Text = tostring(itemData.sum)
		vLbl.TextColor3 = color
		vLbl.TextSize = 13
		vLbl.ZIndex = 22
		vLbl.Parent = chit
	end

	-- Total Chit
	local totalChit = Instance.new("Frame")
	totalChit.AutomaticSize = Enum.AutomaticSize.X
	totalChit.Size = UDim2.new(0, 0, 0, 30)
	totalChit.BackgroundColor3 = Color3.fromRGB(36, 28, 20)
	totalChit.BorderSizePixel = 0
	totalChit.ZIndex = 21
	totalChit.Parent = bar

	local tcCorner = Instance.new("UICorner")
	tcCorner.CornerRadius = UDim.new(0, 15)
	tcCorner.Parent = totalChit

	local tcStroke = Instance.new("UIStroke")
	tcStroke.Color = PALETTE.GoldPrimary
	tcStroke.Thickness = 1.4
	tcStroke.Parent = totalChit

	local tcPad = Instance.new("UIPadding")
	tcPad.PaddingLeft = UDim.new(0, 10)
	tcPad.PaddingRight = UDim.new(0, 10)
	tcPad.Parent = totalChit

	local tcLbl = Instance.new("TextLabel")
	tcLbl.AutomaticSize = Enum.AutomaticSize.X
	tcLbl.Size = UDim2.new(0, 0, 1, 0)
	tcLbl.BackgroundTransparency = 1
	tcLbl.Font = Enum.Font.GothamBlack
	tcLbl.Text = "★ TOTAL: " .. tostring(grandTotal)
	tcLbl.TextColor3 = PALETTE.GoldBright
	tcLbl.TextSize = 12
	tcLbl.ZIndex = 22
	tcLbl.Parent = totalChit

	return bar
end

--------------------------------------------------------------------------------
-- VARIANT 3 BUILDER: "POLISHED MINIMALIST"
--------------------------------------------------------------------------------

local function buildVariant3(parent: Frame, items: { RollItem }): Frame
	local bar = Instance.new("Frame")
	bar.Name = "ResultBar_Variant3"
	bar.Size = UDim2.new(0.96, 0, 0, 42)
	bar.Position = UDim2.new(0.5, 0, 1, -118)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundColor3 = Color3.fromRGB(24, 19, 16)
	bar.BorderSizePixel = 0
	bar.ZIndex = 20
	bar.Parent = parent

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 10)
	bCorner.Parent = bar

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(52, 42, 36)
	bStroke.Thickness = 1
	bStroke.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = bar

	for _, itemData in ipairs(items) do
		local color = diceColorsByShape[itemData.shape] or Color3.fromRGB(200, 200, 200)

		local pill = Instance.new("Frame")
		pill.Name = "Pill_" .. itemData.shape
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.Size = UDim2.new(0, 0, 0, 30)
		pill.BackgroundColor3 = color
		pill.BackgroundTransparency = 0.88 -- Subtle luminous tint
		pill.BorderSizePixel = 0
		pill.ZIndex = 21
		pill.Parent = bar

		local pCorner = Instance.new("UICorner")
		pCorner.CornerRadius = UDim.new(0, 8)
		pCorner.Parent = pill

		local pStroke = Instance.new("UIStroke")
		pStroke.Color = color
		pStroke.Thickness = 1.2
		pStroke.Parent = pill

		local pPad = Instance.new("UIPadding")
		pPad.PaddingLeft = UDim.new(0, 10)
		pPad.PaddingRight = UDim.new(0, 10)
		pPad.Parent = pill

		-- Clean formatted notation without clumsy (SUM: X)
		local displayText = if itemData.count > 1
			then string.format("%d× %s : %d", itemData.count, itemData.shape, itemData.sum)
			else string.format("%s : %d", itemData.shape, itemData.sum)

		local lbl = Instance.new("TextLabel")
		lbl.AutomaticSize = Enum.AutomaticSize.X
		lbl.Size = UDim2.new(0, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.Text = displayText
		lbl.TextColor3 = PALETTE.TextPrimary
		lbl.TextSize = 13 -- Fixed uniform size, NO TextScaled!
		lbl.ZIndex = 22
		lbl.Parent = pill
	end

	return bar
end

--------------------------------------------------------------------------------
-- CAROUSEL CONTROLLER
--------------------------------------------------------------------------------

local currentGui: ScreenGui? = nil

function UIMockPreview.hide()
	if currentGui ~= nil then
		currentGui:Destroy()
		currentGui = nil
	end

	local player = Players.LocalPlayer
	if player then
		local pg = player:FindFirstChild("PlayerGui")
		if pg then
			local boardGui = pg:FindFirstChild("DiceForgeBoard")
			if boardGui and boardGui:IsA("ScreenGui") then
				local tray = boardGui:FindFirstChild("Tray")
				local interior = tray and tray:FindFirstChild("Interior")
				local liveBar = interior and interior:FindFirstChild("ResultBar")
				if liveBar and liveBar:IsA("GuiObject") then
					liveBar.Visible = true
				end
			end
		end
	end
end

function UIMockPreview.show(): ScreenGui
	UIMockPreview.hide()

	local player = Players.LocalPlayer
	assert(player ~= nil, "[UIMockPreview] LocalPlayer must exist")
	local playerGui = player:WaitForChild("PlayerGui")

	-- Hide live ResultBar temporarily so preview replaces it cleanly
	local boardGui = playerGui:FindFirstChild("DiceForgeBoard")
	if boardGui and boardGui:IsA("ScreenGui") then
		local tray = boardGui:FindFirstChild("Tray")
		local interior = tray and tray:FindFirstChild("Interior")
		local liveBar = interior and interior:FindFirstChild("ResultBar")
		if liveBar and liveBar:IsA("GuiObject") then
			liveBar.Visible = false
		end
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UIMockPreview"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local container = Instance.new("Frame")
	container.Name = "VariantsContainer"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local activeVariant = 1

	local function rebuildBars()
		for _, child in ipairs(container:GetChildren()) do
			child:Destroy()
		end

		local currentPreset = samplePresets[activePresetIndex]
		local bar1 = buildVariant1(container, currentPreset.items)
		local bar2 = buildVariant2(container, currentPreset.items)
		local bar3 = buildVariant3(container, currentPreset.items)

		bar1.Visible = (activeVariant == 1)
		bar2.Visible = (activeVariant == 2)
		bar3.Visible = (activeVariant == 3)
	end

	-- TOP CONTROLLER DOCK
	local controller = Instance.new("Frame")
	controller.Name = "ResultBarController"
	controller.Size = UDim2.new(0, 700, 0, 48)
	controller.Position = UDim2.new(0.5, 0, 0, 58)
	controller.AnchorPoint = Vector2.new(0.5, 0)
	controller.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
	controller.BorderSizePixel = 0
	controller.ZIndex = 50
	controller.Parent = screenGui

	local cCorn = Instance.new("UICorner")
	cCorn.CornerRadius = UDim.new(0, 10)
	cCorn.Parent = controller

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = PALETTE.GoldPrimary
	cStroke.Thickness = 1.4
	cStroke.Parent = controller

	local cLayout = Instance.new("UIListLayout")
	cLayout.FillDirection = Enum.FillDirection.Horizontal
	cLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	cLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cLayout.Padding = UDim.new(0, 8)
	cLayout.Parent = controller

	local buttons: { [number]: TextButton } = {}
	local variantDefs = {
		{ id = 1, label = "1: Split Badges" },
		{ id = 2, label = "2: Micro-Chits" },
		{ id = 3, label = "3: Minimalist" },
	}

	local function updateButtons()
		for id, btn in pairs(buttons) do
			if id == activeVariant then
				btn.BackgroundColor3 = PALETTE.GoldPrimary
				btn.TextColor3 = Color3.fromRGB(20, 16, 14)
			else
				btn.BackgroundColor3 = PALETTE.SurfaceElevated
				btn.TextColor3 = PALETTE.TextMuted
			end
		end
		rebuildBars()
	end

	for _, def in ipairs(variantDefs) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 135, 0, 32)
		btn.BackgroundColor3 = PALETTE.SurfaceElevated
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.Text = def.label
		btn.TextColor3 = PALETTE.TextMuted
		btn.TextSize = 11
		btn.ZIndex = 51
		btn.Parent = controller

		local bC = Instance.new("UICorner")
		bC.CornerRadius = UDim.new(0, 6)
		bC.Parent = btn

		btn.MouseButton1Click:Connect(function()
			activeVariant = def.id
			updateButtons()
		end)

		buttons[def.id] = btn
	end

	-- Preset Cycler Button
	local presetBtn = Instance.new("TextButton")
	presetBtn.Size = UDim2.new(0, 130, 0, 32)
	presetBtn.BackgroundColor3 = PALETTE.SurfacePanel
	presetBtn.BorderSizePixel = 0
	presetBtn.Font = Enum.Font.GothamBold
	presetBtn.Text = "Preset: 7 Types"
	presetBtn.TextColor3 = PALETTE.TextPrimary
	presetBtn.TextSize = 10
	presetBtn.ZIndex = 51
	presetBtn.Parent = controller
	local pbC = Instance.new("UICorner")
	pbC.CornerRadius = UDim.new(0, 6)
	pbC.Parent = presetBtn
	local pbS = Instance.new("UIStroke")
	pbS.Color = PALETTE.StrokeSubtle
	pbS.Thickness = 1
	pbS.Parent = presetBtn

	presetBtn.MouseButton1Click:Connect(function()
		activePresetIndex = if activePresetIndex >= #samplePresets then 1 else activePresetIndex + 1
		local p = samplePresets[activePresetIndex]
		presetBtn.Text = if activePresetIndex == 1 then "Preset: 7 Types" elseif activePresetIndex == 2 then "Preset: 2 Dice" else "Preset: 14 Dice"
		rebuildBars()
	end)

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.BackgroundColor3 = PALETTE.SurfaceElevated
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "X"
	closeBtn.TextColor3 = PALETTE.NegativeRed
	closeBtn.TextSize = 13
	closeBtn.ZIndex = 51
	closeBtn.Parent = controller
	local cbC = Instance.new("UICorner")
	cbC.CornerRadius = UDim.new(1, 0)
	cbC.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		UIMockPreview.hide()
	end)

	updateButtons()
	screenGui.Parent = playerGui
	currentGui = screenGui

	return screenGui
end

function UIMockPreview.select(variantId: number)
	if currentGui then
		local controller = currentGui:FindFirstChild("ResultBarController")
		if controller then
			for _, b in ipairs(controller:GetChildren()) do
				if b:IsA("TextButton") and b.Text:find(tostring(variantId)) then
					-- Switch
				end
			end
		end
	end
end

return UIMockPreview
