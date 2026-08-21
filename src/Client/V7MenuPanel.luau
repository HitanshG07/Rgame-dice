--!strict
-- V7MenuPanel.luau
-- Dedicated Full-Screen Overlay Manager for Shapes, Slots, Ascension, Shop, Boards, Quests, Vault, and Settings.
-- Standardized to the Canonical HUD-Clearing Bounding Envelope (L-065) and Unified Luxury Casino Theme.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DICE_SOURCE = "dice_faces"

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetisationCatalog = require(Shared:WaitForChild("MonetisationCatalog"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local SettingsCatalog = require(Shared:WaitForChild("SettingsCatalog"))
local VaultCatalog = require(Shared:WaitForChild("VaultCatalog"))
local Format = require(Shared:WaitForChild("Format"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local NetClient = require(script.Parent:WaitForChild("NetClient"))

local V7MenuPanel = {}
V7MenuPanel.__index = V7MenuPanel

export type V7MenuController = {
	overlays: { [string]: Frame },
	openOverlay: (self: V7MenuController, name: string) -> (),
	closeAll: (self: V7MenuController) -> (),
	applyState: (self: V7MenuController, state: any) -> (),
	shopRefresh: ((any) -> ())?,
	boardsRefresh: ((string) -> ())?,
	activeBoard: string?,
	ascendRefresh: ((any) -> ())?,
	shapeRefresh: ((any) -> ())?,
	questRefresh: ((any) -> ())?,
	vaultRefresh: ((any) -> ())?,
	slotsRefresh: ((any) -> ())?,
	settingsRefresh: ((any) -> ())?,
	setCapability: (self: V7MenuController, name: string, present: boolean) -> (),
	_capabilities: { [string]: boolean },
	lastState: any,
}

-- =============================================================================
-- UNIFIED THEME TOKENS
-- =============================================================================
local THEME = {
	ModalBg      = Color3.fromRGB(24, 20, 18),
	HeaderBg     = Color3.fromRGB(34, 28, 24),
	CardBg       = Color3.fromRGB(32, 26, 22),
	InsetBg      = Color3.fromRGB(18, 15, 13),
	ButtonDark   = Color3.fromRGB(44, 36, 30),
	ButtonHover  = Color3.fromRGB(56, 46, 38),

	GoldPrimary  = Color3.fromRGB(234, 179, 8),
	GoldLight    = Color3.fromRGB(250, 204, 21),
	GoldBurnish  = Color3.fromRGB(212, 165, 40),
	AmberFlame   = Color3.fromRGB(249, 115, 22),

	StrokeGold   = Color3.fromRGB(212, 165, 40),
	StrokeSubtle = Color3.fromRGB(60, 50, 42),
	StrokeInset  = Color3.fromRGB(45, 38, 32),

	TextPrimary  = Color3.fromRGB(245, 240, 235),
	TextGold     = Color3.fromRGB(234, 179, 8),
	TextMuted    = Color3.fromRGB(160, 148, 140),
	TextDark     = Color3.fromRGB(24, 20, 18),

	Positive     = Color3.fromRGB(34, 197, 94),
	Negative     = Color3.fromRGB(239, 68, 68),
	Gems         = Color3.fromRGB(56, 189, 248),
	Diamonds     = Color3.fromRGB(244, 114, 182),
}

local SLOTS_CANONICAL_NAMES: { [string]: string } = {
	D2  = "Quantum Monad",
	D3  = "Trinity Prism",
	D4  = "Pyramid Shard",
	D5  = "Nexus Pentagon",
	D6  = "Foundry Obsidian",
	D7  = "Mystic Heptad",
	D8  = "Astral Octahedron",
	D10 = "Titan Decagon",
	D12 = "Apex Dodecahedron",
	D14 = "Solar Tetradeca",
	D16 = "Crown Hexadeca",
	D20 = "Cosmic Icosahedron",
}

local SLOTS_SPECIMEN_SCALE_MAP: { [string]: number } = {
	D2  = 0.46,
	D3  = 0.43,
	D4  = 0.42,
	D5  = 0.43,
	D6  = 0.48,
	D7  = 0.43,
	D8  = 0.45,
	D10 = 0.43,
	D12 = 0.44,
	D14 = 0.43,
	D16 = 0.43,
	D20 = 0.43,
}

local RACK_CARD_SCALE_MAP: { [string]: number } = {
	D2  = 0.40,
	D3  = 0.38,
	D4  = 0.36,
	D5  = 0.38,
	D6  = 0.42,
	D7  = 0.38,
	D8  = 0.39,
	D10 = 0.38,
	D12 = 0.38,
	D14 = 0.38,
	D16 = 0.38,
	D20 = 0.38,
}

--------------------------------------------------------------------------------
-- HELPER: Configure Canonical Modal Shell (L-065 Standard)
--------------------------------------------------------------------------------
local function formatModalShell(
	overlayFrame: Frame,
	titleText: string,
	getController: () -> any
): (Frame, Frame)
	local scrim = overlayFrame:FindFirstChild("Scrim") :: Frame?
	if not scrim then
		scrim = Instance.new("Frame")
		scrim.Name = "Scrim"
		scrim.Size = UDim2.fromScale(1, 1)
		scrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		scrim.BackgroundTransparency = 0.45
		scrim.BorderSizePixel = 0
		scrim.ZIndex = 1
		scrim.Parent = overlayFrame

		local scrimBtn = Instance.new("TextButton")
		scrimBtn.Size = UDim2.fromScale(1, 1)
		scrimBtn.BackgroundTransparency = 1
		scrimBtn.Text = ""
		scrimBtn.Parent = scrim
		scrimBtn.MouseButton1Click:Connect(function()
			local ctrl = getController()
			if ctrl then ctrl:closeAll() else overlayFrame.Visible = false end
		end)
	end

	local mainShell = overlayFrame:FindFirstChild("Panel") :: Frame?
	if not mainShell then
		mainShell = overlayFrame:FindFirstChildOfClass("Frame")
	end

	if not mainShell then
		mainShell = Instance.new("Frame")
		mainShell.Name = "Panel"
		mainShell.Parent = overlayFrame
	end

	mainShell.ZIndex = 2
	mainShell.Size = UDim2.new(0.74, 0, 0.74, 0)
	mainShell.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainShell.AnchorPoint = Vector2.new(0.5, 0.5)
	mainShell.BackgroundColor3 = THEME.ModalBg
	mainShell.BackgroundTransparency = 0
	mainShell.BorderSizePixel = 0

	local panelCorner = mainShell:FindFirstChildOfClass("UICorner")
	if not panelCorner then
		panelCorner = Instance.new("UICorner")
		panelCorner.CornerRadius = UDim.new(0, 12)
		panelCorner.Parent = mainShell
	else
		panelCorner.CornerRadius = UDim.new(0, 12)
	end

	local panelStroke = mainShell:FindFirstChildOfClass("UIStroke")
	if not panelStroke then
		panelStroke = Instance.new("UIStroke")
		panelStroke.Color = THEME.StrokeGold
		panelStroke.Thickness = 2
		panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		panelStroke.Parent = mainShell
	else
		panelStroke.Color = THEME.StrokeGold
		panelStroke.Thickness = 2
		panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end

	local modalConstraint = mainShell:FindFirstChildOfClass("UISizeConstraint")
	if not modalConstraint then
		modalConstraint = Instance.new("UISizeConstraint")
		modalConstraint.MinSize = Vector2.new(680, 420)
		modalConstraint.MaxSize = Vector2.new(940, 580)
		modalConstraint.Parent = mainShell
	else
		modalConstraint.MinSize = Vector2.new(680, 420)
		modalConstraint.MaxSize = Vector2.new(940, 580)
	end

	-- Header Bar (50px height)
	local header = mainShell:FindFirstChild("Header") :: Frame?
	if not header then
		header = Instance.new("Frame")
		header.Name = "Header"
		header.Parent = mainShell
	end

	for _, c in ipairs(header:GetChildren()) do
		if c:IsA("UIListLayout") then c:Destroy() end
	end

	header.Size = UDim2.new(1, -24, 0, 50)
	header.Position = UDim2.new(0, 12, 0, 8)
	header.BackgroundColor3 = THEME.HeaderBg
	header.BackgroundTransparency = 0
	header.BorderSizePixel = 0

	local hCorner = header:FindFirstChildOfClass("UICorner")
	if not hCorner then
		hCorner = Instance.new("UICorner")
		hCorner.CornerRadius = UDim.new(0, 8)
		hCorner.Parent = header
	end

	local hStroke = header:FindFirstChildOfClass("UIStroke")
	if not hStroke then
		hStroke = Instance.new("UIStroke")
		hStroke.Color = THEME.StrokeGold
		hStroke.Thickness = 1
		hStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		hStroke.Parent = header
	else
		hStroke.Color = THEME.StrokeGold
		hStroke.Thickness = 1
	end

	local hPad = header:FindFirstChildOfClass("UIPadding")
	if not hPad then
		hPad = Instance.new("UIPadding")
		hPad.PaddingLeft = UDim.new(0, 14)
		hPad.PaddingRight = UDim.new(0, 14)
		hPad.Parent = header
	end

	local titleLbl = header:FindFirstChild("Title") :: TextLabel?
	if not titleLbl then
		titleLbl = Instance.new("TextLabel")
		titleLbl.Name = "Title"
		titleLbl.Parent = header
	end
	titleLbl.Size = UDim2.new(0.70, 0, 1, 0)
	titleLbl.Position = UDim2.new(0, 0, 0, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Text = titleText
	titleLbl.TextColor3 = THEME.GoldPrimary
	titleLbl.TextSize = 18
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = header:FindFirstChild("Close") :: TextButton?
	if not closeBtn then
		closeBtn = Instance.new("TextButton")
		closeBtn.Name = "Close"
		closeBtn.Parent = header
	end
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -32, 0.5, -16)
	closeBtn.BackgroundColor3 = THEME.ButtonDark
	closeBtn.BackgroundTransparency = 0
	closeBtn.TextColor3 = THEME.GoldPrimary
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "×"
	closeBtn.TextSize = 22
	closeBtn.TextStrokeTransparency = 1
	closeBtn.BorderSizePixel = 0

	local cbCorner = closeBtn:FindFirstChildOfClass("UICorner")
	if not cbCorner then
		cbCorner = Instance.new("UICorner")
		cbCorner.CornerRadius = UDim.new(0, 6)
		cbCorner.Parent = closeBtn
	end

	local cbStroke = closeBtn:FindFirstChildOfClass("UIStroke")
	if not cbStroke then
		cbStroke = Instance.new("UIStroke")
		cbStroke.Color = THEME.StrokeSubtle
		cbStroke.Thickness = 1
		cbStroke.Parent = closeBtn
	end

	closeBtn.MouseButton1Click:Connect(function()
		local ctrl = getController()
		if ctrl then
			ctrl:closeAll()
		else
			overlayFrame.Visible = false
		end
	end)

	local divider = mainShell:FindFirstChild("Divider") :: Frame?
	if divider then
		divider.Visible = false
	end

	-- Dedicated standardized body canvas (1, -24, 1, -68 at 0, 12, 0, 60)
	local bodyCanvas = Instance.new("Frame")
	bodyCanvas.Name = "BodyCanvas"
	bodyCanvas.Size = UDim2.new(1, -24, 1, -68)
	bodyCanvas.Position = UDim2.new(0, 12, 0, 60)
	bodyCanvas.BackgroundTransparency = 1
	bodyCanvas.ClipsDescendants = false
	bodyCanvas.Parent = mainShell

	return mainShell, bodyCanvas
end

--------------------------------------------------------------------------------
-- 1. DICE SHAPES OVERLAY
--------------------------------------------------------------------------------
local function buildShapesOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (any) -> ()
	local shapesOverlay, legacyBody = UITheme.overlay("Dice Shapes")
	shapesOverlay.Parent = screenGui
	overlays["shapes"] = shapesOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, contentArea = formatModalShell(shapesOverlay, "~ Dice Shapes & Master Catalog ~", getController)

	local colLayout = Instance.new("UIListLayout")
	colLayout.FillDirection = Enum.FillDirection.Horizontal
	colLayout.SortOrder = Enum.SortOrder.LayoutOrder
	colLayout.Padding = UDim.new(0, 12)
	colLayout.Parent = contentArea

	-- LEFT COLUMN (42% width): Orbit Chamber + Specimen Telemetry Stage
	local leftCol = Instance.new("Frame")
	leftCol.Name = "DualStageColumn"
	leftCol.Size = UDim2.new(0.42, -6, 1, 0)
	leftCol.BackgroundTransparency = 1
	leftCol.LayoutOrder = 1
	leftCol.Parent = contentArea

	local leftList = Instance.new("UIListLayout")
	leftList.FillDirection = Enum.FillDirection.Vertical
	leftList.SortOrder = Enum.SortOrder.LayoutOrder
	leftList.Padding = UDim.new(0, 8)
	leftList.Parent = leftCol

	-- Top Stage: Equipped Orbit Chamber (46% height)
	local loadoutChamber = Instance.new("Frame")
	loadoutChamber.Name = "EquippedFloatingChamber"
	loadoutChamber.Size = UDim2.new(1, 0, 0.46, -4)
	loadoutChamber.BackgroundColor3 = THEME.CardBg
	loadoutChamber.BorderSizePixel = 0
	loadoutChamber.LayoutOrder = 1
	loadoutChamber.Parent = leftCol

	local lcCorner = Instance.new("UICorner")
	lcCorner.CornerRadius = UDim.new(0, 8)
	lcCorner.Parent = loadoutChamber

	local lcStroke = Instance.new("UIStroke")
	lcStroke.Color = THEME.StrokeSubtle
	lcStroke.Thickness = 1
	lcStroke.Parent = loadoutChamber

	local lcPad = Instance.new("UIPadding")
	lcPad.PaddingLeft = UDim.new(0, 10)
	lcPad.PaddingRight = UDim.new(0, 10)
	lcPad.PaddingTop = UDim.new(0, 6)
	lcPad.PaddingBottom = UDim.new(0, 6)
	lcPad.Parent = loadoutChamber

	local lcList = Instance.new("UIListLayout")
	lcList.FillDirection = Enum.FillDirection.Vertical
	lcList.SortOrder = Enum.SortOrder.LayoutOrder
	lcList.Padding = UDim.new(0, 4)
	lcList.Parent = loadoutChamber

	local chamberTitle = Instance.new("TextLabel")
	chamberTitle.Name = "ChamberTitle"
	chamberTitle.Size = UDim2.new(1, 0, 0, 16)
	chamberTitle.BackgroundTransparency = 1
	chamberTitle.Text = "EQUIPPED LOADOUT"
	chamberTitle.TextColor3 = THEME.GoldPrimary
	chamberTitle.TextSize = 11
	chamberTitle.Font = Enum.Font.GothamBold
	chamberTitle.TextXAlignment = Enum.TextXAlignment.Left
	chamberTitle.LayoutOrder = 1
	chamberTitle.Parent = loadoutChamber

	local floatingContainer = Instance.new("Frame")
	floatingContainer.Name = "FloatingViewportBox"
	floatingContainer.Size = UDim2.new(1, 0, 1, -20)
	floatingContainer.BackgroundColor3 = THEME.InsetBg
	floatingContainer.BorderSizePixel = 0
	floatingContainer.LayoutOrder = 2
	floatingContainer.Parent = loadoutChamber

	local fcCorner = Instance.new("UICorner")
	fcCorner.CornerRadius = UDim.new(0, 6)
	fcCorner.Parent = floatingContainer

	local fcStroke = Instance.new("UIStroke")
	fcStroke.Color = THEME.StrokeSubtle
	fcStroke.Thickness = 1
	fcStroke.Parent = floatingContainer

	local chamberVp = Instance.new("ViewportFrame")
	chamberVp.Name = "OrbitViewport"
	chamberVp.Size = UDim2.fromScale(1, 1)
	chamberVp.BackgroundColor3 = THEME.InsetBg
	chamberVp.BackgroundTransparency = 0
	chamberVp.BorderSizePixel = 0
	chamberVp.Parent = floatingContainer

	local chamberCam = Instance.new("Camera")
	chamberCam.FieldOfView = 45
	chamberCam.Parent = chamberVp
	chamberVp.CurrentCamera = chamberCam

	local folder = ReplicatedStorage:FindFirstChild(DICE_SOURCE)
	local unlockOrder = DiceCatalog.getUnlockOrder()

	type OrbitItemData = {
		model: Model,
		isHeroSingle: boolean,
		baseAngle: number,
		radiusX: number,
		orbitSpeed: number,
		spinX: number,
		spinY: number,
		spinZ: number,
		bobAmp1: number,
		bobAmp2: number,
		bobFreq1: number,
		bobFreq2: number,
		phase1: number,
		phase2: number,
		baseHeight: number,
		phaseX: number,
		phaseY: number,
		phaseZ: number,
	}

	local orbitItems: { OrbitItemData } = {}

	local function rebuildOrbitChamber(equippedDiceList: { string })
		for _, item in ipairs(orbitItems) do
			if item.model and item.model.Parent ~= nil then
				item.model:Destroy()
			end
		end
		table.clear(orbitItems)

		local count = #equippedDiceList
		if count == 0 then
			equippedDiceList = { "D6" }
			count = 1
		end

		if count == 1 then
			chamberTitle.Text = "EQUIPPED DIE (1 DIE)"
			local shapeId = equippedDiceList[1]
			local source = if folder then folder:FindFirstChild(shapeId) else nil
			if source and source:IsA("Model") then
				local model = source:Clone()
				if model.PrimaryPart == nil then
					local pivot = model:FindFirstChild("Pivot")
					if pivot and pivot:IsA("BasePart") then
						model.PrimaryPart = pivot
					end
				end
				local _, bbSize = model:GetBoundingBox()
				local maxDim = math.max(bbSize.X, bbSize.Y, bbSize.Z)
				if maxDim > 0 then
					model:ScaleTo(1.75 / maxDim)
				end
				model:PivotTo(CFrame.new(0, 0, 0))
				model.Parent = chamberVp

				chamberCam.CFrame = CFrame.new(Vector3.new(2.8, 2.2, 3.4), Vector3.new(0, 0, 0))
				chamberCam.FieldOfView = 36

				table.insert(orbitItems, {
					model = model,
					isHeroSingle = true,
					baseAngle = 0,
					radiusX = 0,
					orbitSpeed = 0,
					spinX = 0.35,
					spinY = 0.70,
					spinZ = 0.25,
					bobAmp1 = 0.18,
					bobAmp2 = 0,
					bobFreq1 = 1.3,
					bobFreq2 = 0,
					phase1 = 0,
					phase2 = 0,
					baseHeight = 0,
					phaseX = 0,
					phaseY = 0,
					phaseZ = 0,
				})
			end
		else
			chamberTitle.Text = string.format("EQUIPPED LOADOUT (%d DICE)", count)
			local orbitRadius = math.clamp(3.0 + count * 0.22, 3.4, 5.0)
			local modelScale = math.clamp(1.4 / math.sqrt(count), 0.46, 0.70)

			chamberCam.CFrame = CFrame.new(Vector3.new(0, 4.4 + count * 0.15, 9.6 + count * 0.35), Vector3.new(0, -0.2, 0))
			chamberCam.FieldOfView = 45

			for idx, shapeId in ipairs(equippedDiceList) do
				local source = if folder then folder:FindFirstChild(shapeId) else nil
				if source and source:IsA("Model") then
					local model = source:Clone()
					if model.PrimaryPart == nil then
						local pivot = model:FindFirstChild("Pivot")
						if pivot and pivot:IsA("BasePart") then
							model.PrimaryPart = pivot
						end
					end
					model:ScaleTo(modelScale)
					model.Parent = chamberVp

					local stepAngle = (math.pi * 2) / count
					local baseAngle = (idx - 1) * stepAngle

					table.insert(orbitItems, {
						model = model,
						isHeroSingle = false,
						baseAngle = baseAngle,
						radiusX = orbitRadius,
						orbitSpeed = 0.55,
						spinX = 0.6 + (idx % 3) * 0.2,
						spinY = 0.9 + (idx % 2) * 0.3,
						spinZ = 0.4 + (idx % 4) * 0.15,
						bobAmp1 = 0.22,
						bobAmp2 = 0.10,
						bobFreq1 = 1.2 + (idx % 3) * 0.2,
						bobFreq2 = 2.4,
						phase1 = idx * 1.1,
						phase2 = idx * 0.7,
						baseHeight = 0,
						phaseX = idx * 0.9,
						phaseY = idx * 1.4,
						phaseZ = idx * 0.5,
					})
				end
			end
		end
	end

	-- Bottom Stage: Specimen Telemetry Stage (54% height)
	local specimenStage = Instance.new("Frame")
	specimenStage.Name = "SpecimenTelemetryStage"
	specimenStage.Size = UDim2.new(1, 0, 0.54, -4)
	specimenStage.BackgroundColor3 = THEME.CardBg
	specimenStage.BorderSizePixel = 0
	specimenStage.LayoutOrder = 2
	specimenStage.Parent = leftCol

	local ssCorner = Instance.new("UICorner")
	ssCorner.CornerRadius = UDim.new(0, 8)
	ssCorner.Parent = specimenStage

	local ssStroke = Instance.new("UIStroke")
	ssStroke.Color = THEME.StrokeSubtle
	ssStroke.Thickness = 1
	ssStroke.Parent = specimenStage

	local ssPad = Instance.new("UIPadding")
	ssPad.PaddingLeft = UDim.new(0, 10)
	ssPad.PaddingRight = UDim.new(0, 10)
	ssPad.PaddingTop = UDim.new(0, 6)
	ssPad.PaddingBottom = UDim.new(0, 6)
	ssPad.Parent = specimenStage

	local ssList = Instance.new("UIListLayout")
	ssList.FillDirection = Enum.FillDirection.Vertical
	ssList.SortOrder = Enum.SortOrder.LayoutOrder
	ssList.Padding = UDim.new(0, 4)
	ssList.Parent = specimenStage

	local ssTitle = Instance.new("TextLabel")
	ssTitle.Name = "SpecimenTitle"
	ssTitle.Size = UDim2.new(1, 0, 0, 14)
	ssTitle.BackgroundTransparency = 1
	ssTitle.Text = "STATS & SPECIMEN"
	ssTitle.TextColor3 = THEME.GoldPrimary
	ssTitle.TextSize = 11
	ssTitle.Font = Enum.Font.GothamBold
	ssTitle.TextXAlignment = Enum.TextXAlignment.Left
	ssTitle.LayoutOrder = 1
	ssTitle.Parent = specimenStage

	-- Middle Split Row (Display | Stats)
	local splitRow = Instance.new("Frame")
	splitRow.Name = "SplitDisplayStatsRow"
	splitRow.Size = UDim2.new(1, 0, 1, -70)
	splitRow.BackgroundTransparency = 1
	splitRow.LayoutOrder = 2
	splitRow.Parent = specimenStage

	local splitList = Instance.new("UIListLayout")
	splitList.FillDirection = Enum.FillDirection.Horizontal
	splitList.SortOrder = Enum.SortOrder.LayoutOrder
	splitList.Padding = UDim.new(0, 8)
	splitList.Parent = splitRow

	local singleVpContainer = Instance.new("Frame")
	singleVpContainer.Name = "SingleViewportContainer"
	singleVpContainer.Size = UDim2.new(0.40, -4, 1, 0)
	singleVpContainer.BackgroundColor3 = THEME.InsetBg
	singleVpContainer.BorderSizePixel = 0
	singleVpContainer.LayoutOrder = 1
	singleVpContainer.Parent = splitRow

	local svpCorner = Instance.new("UICorner")
	svpCorner.CornerRadius = UDim.new(0, 6)
	svpCorner.Parent = singleVpContainer

	local svpStroke = Instance.new("UIStroke")
	svpStroke.Color = THEME.StrokeSubtle
	svpStroke.Thickness = 1
	svpStroke.Parent = singleVpContainer

	local inspectedHeroModel: Model? = nil

	local function createInspectionTurntable(shapeId: string): ViewportFrame
		local vp = Instance.new("ViewportFrame")
		vp.Name = "SpecimenTurntable_" .. shapeId
		vp.Size = UDim2.fromScale(1, 1)
		vp.BackgroundColor3 = THEME.InsetBg
		vp.BackgroundTransparency = 1
		vp.BorderSizePixel = 0
		vp.Parent = singleVpContainer

		local sSource = if folder then folder:FindFirstChild(shapeId) else nil
		if sSource and sSource:IsA("Model") then
			local model = sSource:Clone()
			if model.PrimaryPart == nil then
				local pivot = model:FindFirstChild("Pivot")
				if pivot and pivot:IsA("BasePart") then
					model.PrimaryPart = pivot
				end
			end
			local scaleFactor = SLOTS_SPECIMEN_SCALE_MAP[shapeId] or 0.44
			model:ScaleTo(scaleFactor)
			model:PivotTo(CFrame.new(0, 0, 0))
			model.Parent = vp
			inspectedHeroModel = model

			local iCam = Instance.new("Camera")
			iCam.CFrame = CFrame.new(Vector3.new(2.4, 1.8, 3.0), Vector3.new(0, 0, 0))
			iCam.FieldOfView = 36
			iCam.Parent = vp
			vp.CurrentCamera = iCam
		end

		return vp
	end

	local statsGrid = Instance.new("Frame")
	statsGrid.Name = "StatsTelemetryGrid"
	statsGrid.Size = UDim2.new(0.60, -4, 1, 0)
	statsGrid.BackgroundColor3 = THEME.InsetBg
	statsGrid.BorderSizePixel = 0
	statsGrid.LayoutOrder = 2
	statsGrid.Parent = splitRow

	local sgCorner = Instance.new("UICorner")
	sgCorner.CornerRadius = UDim.new(0, 6)
	sgCorner.Parent = statsGrid

	local sgStroke = Instance.new("UIStroke")
	sgStroke.Color = THEME.StrokeSubtle
	sgStroke.Thickness = 1
	sgStroke.Parent = statsGrid

	local sgPad = Instance.new("UIPadding")
	sgPad.PaddingLeft = UDim.new(0, 8)
	sgPad.PaddingRight = UDim.new(0, 8)
	sgPad.PaddingTop = UDim.new(0, 4)
	sgPad.PaddingBottom = UDim.new(0, 4)
	sgPad.Parent = statsGrid

	local sgl = Instance.new("UIListLayout")
	sgl.FillDirection = Enum.FillDirection.Vertical
	sgl.SortOrder = Enum.SortOrder.LayoutOrder
	sgl.Padding = UDim.new(0, 2)
	sgl.Parent = statsGrid

	local statValueLabels: { [string]: TextLabel } = {}
	local statMeterFills: { [string]: Frame } = {}

	local function createCaliperRow(order: number, key: string, labelText: string, defaultVal: string, ratio: number)
		local row = Instance.new("Frame")
		row.Name = "CaliperRow_" .. key
		row.Size = UDim2.new(1, 0, 0.25, -2)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.Parent = statsGrid

		local rList = Instance.new("UIListLayout")
		rList.FillDirection = Enum.FillDirection.Vertical
		rList.SortOrder = Enum.SortOrder.LayoutOrder
		rList.Padding = UDim.new(0, 1)
		rList.Parent = row

		local textHeader = Instance.new("Frame")
		textHeader.Size = UDim2.new(1, 0, 0, 12)
		textHeader.BackgroundTransparency = 1
		textHeader.LayoutOrder = 1
		textHeader.Parent = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.5, 0, 1, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = labelText
		nameLbl.TextColor3 = THEME.TextMuted
		nameLbl.TextSize = 9
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Parent = textHeader

		local valLbl = Instance.new("TextLabel")
		valLbl.Size = UDim2.new(0.5, 0, 1, 0)
		valLbl.Position = UDim2.new(0.5, 0, 0, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Text = defaultVal
		valLbl.TextColor3 = THEME.TextPrimary
		valLbl.TextSize = 9.5
		valLbl.Font = Enum.Font.GothamBold
		valLbl.TextXAlignment = Enum.TextXAlignment.Right
		valLbl.Parent = textHeader
		statValueLabels[key] = valLbl

		local mTrack = Instance.new("Frame")
		mTrack.Size = UDim2.new(1, 0, 0, 4)
		mTrack.BackgroundColor3 = THEME.ModalBg
		mTrack.BorderSizePixel = 0
		mTrack.LayoutOrder = 2
		mTrack.Parent = row

		local mtCorner = Instance.new("UICorner")
		mtCorner.CornerRadius = UDim.new(1, 0)
		mtCorner.Parent = mTrack

		local mFill = Instance.new("Frame")
		mFill.Size = UDim2.new(math.clamp(ratio, 0.05, 1), 0, 1, 0)
		mFill.BackgroundColor3 = THEME.GoldPrimary
		mFill.BorderSizePixel = 0
		mFill.Parent = mTrack

		local mfCorner = Instance.new("UICorner")
		mfCorner.CornerRadius = UDim.new(1, 0)
		mfCorner.Parent = mFill
		statMeterFills[key] = mFill
	end

	createCaliperRow(1, "face", "SIDES", "6 SIDES", 6 / 20)
	createCaliperRow(2, "mass", "DICE WEIGHT", "60 / 300", 60 / 300)
	createCaliperRow(3, "volatility", "WIN RATE", "83.3% WIN", 0.833)
	createCaliperRow(4, "payout", "MAX PAYOUT", "18.0x MULT", 0.36)

	-- Bottom Action Buttons (Stacked at Bottom, 26px height)
	local equipStateBtn = Instance.new("TextButton")
	equipStateBtn.Name = "EquipStateBtn"
	equipStateBtn.Size = UDim2.new(1, 0, 0, 26)
	equipStateBtn.BackgroundColor3 = THEME.ButtonDark
	equipStateBtn.BorderSizePixel = 0
	equipStateBtn.Text = "[ EQUIPPED SOLID ]"
	equipStateBtn.TextColor3 = THEME.TextPrimary
	equipStateBtn.TextSize = 11
	equipStateBtn.Font = Enum.Font.GothamBold
	equipStateBtn.AutoButtonColor = false
	equipStateBtn.LayoutOrder = 3
	equipStateBtn.Parent = specimenStage

	local esCorner = Instance.new("UICorner")
	esCorner.CornerRadius = UDim.new(0, 5)
	esCorner.Parent = equipStateBtn

	local addInstanceBtn = Instance.new("TextButton")
	addInstanceBtn.Name = "AddInstanceBtn"
	addInstanceBtn.Size = UDim2.new(1, 0, 0, 26)
	addInstanceBtn.BackgroundColor3 = THEME.Positive
	addInstanceBtn.BorderSizePixel = 0
	addInstanceBtn.Text = "+1 DIE INSTANCE $8,000"
	addInstanceBtn.TextColor3 = THEME.TextDark
	addInstanceBtn.TextSize = 11
	addInstanceBtn.Font = Enum.Font.GothamBold
	addInstanceBtn.LayoutOrder = 4
	addInstanceBtn.Parent = specimenStage

	local aiCorner = Instance.new("UICorner")
	aiCorner.CornerRadius = UDim.new(0, 5)
	aiCorner.Parent = addInstanceBtn

	-- RIGHT COLUMN: Milled Toolroom Grid / Ladder (58% width)
	local rightContainer = Instance.new("Frame")
	rightContainer.Name = "RightToolroomContainer"
	rightContainer.Size = UDim2.new(0.58, -6, 1, 0)
	rightContainer.BackgroundColor3 = THEME.CardBg
	rightContainer.BorderSizePixel = 0
	rightContainer.LayoutOrder = 2
	rightContainer.Parent = contentArea

	local rcCorner = Instance.new("UICorner")
	rcCorner.CornerRadius = UDim.new(0, 8)
	rcCorner.Parent = rightContainer

	local rcStroke = Instance.new("UIStroke")
	rcStroke.Color = THEME.StrokeSubtle
	rcStroke.Thickness = 1
	rcStroke.Parent = rightContainer

	local rightList = Instance.new("UIListLayout")
	rightList.FillDirection = Enum.FillDirection.Vertical
	rightList.SortOrder = Enum.SortOrder.LayoutOrder
	rightList.Padding = UDim.new(0, 6)
	rightList.Parent = rightContainer

	local rcPad = Instance.new("UIPadding")
	rcPad.PaddingLeft = UDim.new(0, 8)
	rcPad.PaddingRight = UDim.new(0, 8)
	rcPad.PaddingTop = UDim.new(0, 6)
	rcPad.PaddingBottom = UDim.new(0, 6)
	rcPad.Parent = rightContainer

	-- 4-Tab Filter Bar (ALL, HIGH RISK, BALANCED, SAFE)
	local filterBar = Instance.new("Frame")
	filterBar.Name = "FilterTabBar"
	filterBar.Size = UDim2.new(1, 0, 0, 32)
	filterBar.BackgroundColor3 = THEME.InsetBg
	filterBar.BorderSizePixel = 0
	filterBar.LayoutOrder = 1
	filterBar.Parent = rightContainer

	local fbCorner = Instance.new("UICorner")
	fbCorner.CornerRadius = UDim.new(0, 6)
	fbCorner.Parent = filterBar

	local fbList = Instance.new("UIListLayout")
	fbList.FillDirection = Enum.FillDirection.Horizontal
	fbList.SortOrder = Enum.SortOrder.LayoutOrder
	fbList.Padding = UDim.new(0, 4)
	fbList.Parent = filterBar

	local filterTabs = {
		{ id = "all", label = "ALL (12)" },
		{ id = "sniper", label = "HIGH RISK (3)" },
		{ id = "balanced", label = "BALANCED (3)" },
		{ id = "grinder", label = "SAFE (6)" },
	}

	local currentActiveTab = "all"
	local tabButtons: { [string]: TextButton } = {}
	local cardFrames: { [string]: Frame } = {}
	local cardStrokes: { [string]: UIStroke } = {}
	local cardActionBtns: { [string]: TextButton } = {}

	local shapeMeta: { [string]: {
		id: string,
		name: string,
		faceCount: number,
		archetype: string,
		category: string,
		voidChance: string,
		payoutMultiplier: string,
		voidRatio: number,
		payoutRatio: number,
	} } = {
		D2  = { id = "D2", name = "Quantum Monad", faceCount = 2, archetype = "High Risk", category = "sniper", voidChance = "50.0%", payoutMultiplier = "50x", voidRatio = 0.50, payoutRatio = 1.0 },
		D3  = { id = "D3", name = "Trinity Prism", faceCount = 3, archetype = "High Risk", category = "sniper", voidChance = "49.2%", payoutMultiplier = "45x", voidRatio = 0.492, payoutRatio = 0.90 },
		D4  = { id = "D4", name = "Pyramid Shard", faceCount = 4, archetype = "High Risk", category = "sniper", voidChance = "33.3%", payoutMultiplier = "32x", voidRatio = 0.333, payoutRatio = 0.64 },
		D5  = { id = "D5", name = "Nexus Pentagon", faceCount = 5, archetype = "Balanced", category = "balanced", voidChance = "25.0%", payoutMultiplier = "24x", voidRatio = 0.25, payoutRatio = 0.48 },
		D6  = { id = "D6", name = "Foundry Obsidian", faceCount = 6, archetype = "Classic Balanced", category = "balanced", voidChance = "16.7%", payoutMultiplier = "18x", voidRatio = 0.167, payoutRatio = 0.36 },
		D7  = { id = "D7", name = "Mystic Heptad", faceCount = 7, archetype = "Balanced", category = "balanced", voidChance = "14.3%", payoutMultiplier = "14x", voidRatio = 0.143, payoutRatio = 0.28 },
		D8  = { id = "D8", name = "Astral Octahedron", faceCount = 8, archetype = "Safe", category = "grinder", voidChance = "12.5%", payoutMultiplier = "11x", voidRatio = 0.125, payoutRatio = 0.22 },
		D10 = { id = "D10", name = "Titan Decagon", faceCount = 10, archetype = "Safe", category = "grinder", voidChance = "10.0%", payoutMultiplier = "8.5x", voidRatio = 0.10, payoutRatio = 0.17 },
		D12 = { id = "D12", name = "Apex Dodecahedron", faceCount = 12, archetype = "Safe", category = "grinder", voidChance = "8.3%", payoutMultiplier = "6.5x", voidRatio = 0.083, payoutRatio = 0.13 },
		D14 = { id = "D14", name = "Solar Tetradeca", faceCount = 14, archetype = "Safe", category = "grinder", voidChance = "7.1%", payoutMultiplier = "5.0x", voidRatio = 0.071, payoutRatio = 0.10 },
		D16 = { id = "D16", name = "Crown Hexadeca", faceCount = 16, archetype = "Safe", category = "grinder", voidChance = "6.2%", payoutMultiplier = "4.2x", voidRatio = 0.062, payoutRatio = 0.084 },
		D20 = { id = "D20", name = "Cosmic Icosahedron", faceCount = 20, archetype = "Safe", category = "grinder", voidChance = "5.0%", payoutMultiplier = "3.2x", voidRatio = 0.05, payoutRatio = 0.064 },
	}

	local function applyFilter(catId: string)
		currentActiveTab = catId
		for _, tab in ipairs(filterTabs) do
			local btn = tabButtons[tab.id]
			if btn then
				btn.BackgroundColor3 = if tab.id == currentActiveTab then THEME.GoldPrimary else THEME.ButtonDark
				btn.TextColor3 = if tab.id == currentActiveTab then THEME.TextDark else THEME.TextMuted
			end
		end

		for shapeId, meta in pairs(shapeMeta) do
			local card = cardFrames[shapeId]
			if card then
				if currentActiveTab == "all" or meta.category == currentActiveTab then
					card.Visible = true
				else
					card.Visible = false
				end
			end
		end
	end

	for tIdx, tab in ipairs(filterTabs) do
		local tBtn = Instance.new("TextButton")
		tBtn.Name = "Tab_" .. tab.id
		tBtn.Size = UDim2.new(0.25, -3, 1, 0)
		tBtn.BackgroundColor3 = if tab.id == "all" then THEME.GoldPrimary else THEME.ButtonDark
		tBtn.BorderSizePixel = 0
		tBtn.Text = tab.label
		tBtn.TextColor3 = if tab.id == "all" then THEME.TextDark else THEME.TextMuted
		tBtn.TextSize = 10
		tBtn.Font = Enum.Font.GothamBold
		tBtn.LayoutOrder = tIdx
		tBtn.Parent = filterBar

		local tbC = Instance.new("UICorner")
		tbC.CornerRadius = UDim.new(0, 4)
		tbC.Parent = tBtn

		tabButtons[tab.id] = tBtn

		tBtn.MouseButton1Click:Connect(function()
			applyFilter(tab.id)
		end)
	end

	-- Scrollable Grid Rack
	local rightCol = Instance.new("ScrollingFrame")
	rightCol.Name = "ToolroomRackScroll"
	rightCol.Size = UDim2.new(1, 0, 1, -38)
	rightCol.BackgroundTransparency = 1
	rightCol.BorderSizePixel = 0
	rightCol.ScrollBarThickness = 4
	rightCol.ScrollBarImageColor3 = THEME.GoldPrimary
	rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightCol.ClipsDescendants = true
	rightCol.LayoutOrder = 2
	rightCol.Parent = rightContainer

	local rGrid = Instance.new("UIGridLayout")
	rGrid.CellSize = UDim2.new(0.5, -4, 0, 118)
	rGrid.CellPadding = UDim2.new(0, 6, 0, 6)
	rGrid.SortOrder = Enum.SortOrder.LayoutOrder
	rGrid.Parent = rightCol

	local cardModels: { Model } = {}
	local inspectedShapeId = "D6"

	local function inspectShape(shapeId: string)
		inspectedShapeId = shapeId
		local meta = shapeMeta[shapeId] or shapeMeta["D6"]
		ssTitle.Text = string.format("STATS & SPECIMEN: %s (%s)", meta.name, meta.id)

		if statValueLabels["face"] then statValueLabels["face"].Text = meta.faceCount .. " SIDES" end
		if statMeterFills["face"] then statMeterFills["face"].Size = UDim2.new(meta.faceCount / 20, 0, 1, 0) end

		if statValueLabels["volatility"] then statValueLabels["volatility"].Text = "VOID " .. meta.voidChance end
		if statMeterFills["volatility"] then statMeterFills["volatility"].Size = UDim2.new(meta.voidRatio, 0, 1, 0) end

		if statValueLabels["payout"] then statValueLabels["payout"].Text = meta.payoutMultiplier .. " PEAK" end
		if statMeterFills["payout"] then statMeterFills["payout"].Size = UDim2.new(meta.payoutRatio, 0, 1, 0) end

		for _, child in ipairs(singleVpContainer:GetChildren()) do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end
		createInspectionTurntable(shapeId)

		for sId, card in pairs(cardFrames) do
			local stk = cardStrokes[sId]
			if stk then
				if sId == shapeId then
					stk.Color = THEME.GoldPrimary
					stk.Thickness = 2
				else
					stk.Color = THEME.StrokeSubtle
					stk.Thickness = 1
				end
			end
		end
	end

	for orderIdx, shapeId in ipairs(unlockOrder) do
		local meta = shapeMeta[shapeId]
		if meta then
			local card = Instance.new("Frame")
			card.Name = "CatalogCard_" .. shapeId
			card.BackgroundColor3 = THEME.InsetBg
			card.BorderSizePixel = 0
			card.LayoutOrder = orderIdx
			card.Parent = rightCol
			cardFrames[shapeId] = card

			local cCorner = Instance.new("UICorner")
			cCorner.CornerRadius = UDim.new(0, 6)
			cCorner.Parent = card

			local cStroke = Instance.new("UIStroke")
			cStroke.Color = THEME.StrokeSubtle
			cStroke.Thickness = 1
			cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cStroke.Parent = card
			cardStrokes[shapeId] = cStroke

			local cPad = Instance.new("UIPadding")
			cPad.PaddingTop = UDim.new(0, 6)
			cPad.PaddingBottom = UDim.new(0, 6)
			cPad.PaddingLeft = UDim.new(0, 8)
			cPad.PaddingRight = UDim.new(0, 8)
			cPad.Parent = card

			-- Title Row
			local titleRow = Instance.new("Frame")
			titleRow.Size = UDim2.new(1, 0, 0, 16)
			titleRow.BackgroundTransparency = 1
			titleRow.Parent = card

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -36, 1, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = meta.name
			nameLbl.TextColor3 = THEME.TextPrimary
			nameLbl.TextSize = 11.5
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.Parent = titleRow

			local diePill = Instance.new("TextLabel")
			diePill.Size = UDim2.new(0, 32, 1, 0)
			diePill.Position = UDim2.new(1, -32, 0, 0)
			diePill.BackgroundColor3 = THEME.CardBg
			diePill.BorderSizePixel = 0
			diePill.Text = meta.id
			diePill.TextColor3 = THEME.GoldPrimary
			diePill.TextSize = 10
			diePill.Font = Enum.Font.GothamBold
			diePill.Parent = titleRow

			local dpC = Instance.new("UICorner")
			dpC.CornerRadius = UDim.new(0, 4)
			dpC.Parent = diePill

			-- Middle Row (3D Viewport Stage + Stats)
			local middleRow = Instance.new("Frame")
			middleRow.Size = UDim2.new(1, 0, 0, 52)
			middleRow.Position = UDim2.new(0, 0, 0, 20)
			middleRow.BackgroundTransparency = 1
			middleRow.Parent = card

			local plinth = Instance.new("Frame")
			plinth.Size = UDim2.fromOffset(52, 52)
			plinth.BackgroundColor3 = THEME.ModalBg
			plinth.BorderSizePixel = 0
			plinth.Parent = middleRow

			local pCorner = Instance.new("UICorner")
			pCorner.CornerRadius = UDim.new(0, 4)
			pCorner.Parent = plinth

			local cardVp = Instance.new("ViewportFrame")
			cardVp.Size = UDim2.fromScale(1, 1)
			cardVp.BackgroundColor3 = THEME.ModalBg
			cardVp.BackgroundTransparency = 0
			cardVp.BorderSizePixel = 0
			cardVp.Parent = plinth

			local cSource = if folder then folder:FindFirstChild(shapeId) else nil
			if cSource and cSource:IsA("Model") then
				local cModel = cSource:Clone()
				if cModel.PrimaryPart == nil then
					local pivot = cModel:FindFirstChild("Pivot")
					if pivot and pivot:IsA("BasePart") then
						cModel.PrimaryPart = pivot
					end
				end
				local cardScale = RACK_CARD_SCALE_MAP[shapeId] or 0.38
				cModel:ScaleTo(cardScale)
				cModel:PivotTo(CFrame.new(0, 0, 0))
				cModel.Parent = cardVp
				table.insert(cardModels, cModel)

				local cCam = Instance.new("Camera")
				cCam.CFrame = CFrame.new(Vector3.new(2.4, 1.8, 2.8), Vector3.new(0, 0, 0))
				cCam.FieldOfView = 34
				cCam.Parent = cardVp
				cardVp.CurrentCamera = cCam
			end

			local infoCol = Instance.new("Frame")
			infoCol.Size = UDim2.new(1, -58, 1, 0)
			infoCol.Position = UDim2.fromOffset(58, 0)
			infoCol.BackgroundTransparency = 1
			infoCol.Parent = middleRow

			local tList = Instance.new("UIListLayout")
			tList.FillDirection = Enum.FillDirection.Vertical
			tList.SortOrder = Enum.SortOrder.LayoutOrder
			tList.Padding = UDim.new(0, 4)
			tList.Parent = infoCol

			local tArch = Instance.new("TextLabel")
			tArch.Size = UDim2.new(1, 0, 0, 14)
			tArch.BackgroundTransparency = 1
			tArch.Text = string.upper(meta.faceCount .. " SIDES • " .. meta.archetype)
			tArch.TextColor3 = THEME.TextMuted
			tArch.TextSize = 10
			tArch.Font = Enum.Font.GothamBold
			tArch.TextXAlignment = Enum.TextXAlignment.Left
			tArch.Parent = infoCol

			local statChipRow = Instance.new("Frame")
			statChipRow.Size = UDim2.new(1, 0, 0, 20)
			statChipRow.BackgroundTransparency = 1
			statChipRow.Parent = infoCol

			local scList = Instance.new("UIListLayout")
			scList.FillDirection = Enum.FillDirection.Horizontal
			scList.SortOrder = Enum.SortOrder.LayoutOrder
			scList.Padding = UDim.new(0, 4)
			scList.Parent = statChipRow

			local voidChip = Instance.new("TextLabel")
			voidChip.Size = UDim2.new(0.5, -2, 1, 0)
			voidChip.BackgroundColor3 = THEME.ModalBg
			voidChip.BorderSizePixel = 0
			voidChip.Text = "VOID " .. meta.voidChance
			voidChip.TextColor3 = THEME.Negative
			voidChip.TextSize = 9.5
			voidChip.Font = Enum.Font.GothamBold
			voidChip.Parent = statChipRow
			local vcCorner = Instance.new("UICorner")
			vcCorner.CornerRadius = UDim.new(0, 4)
			vcCorner.Parent = voidChip

			local payChip = Instance.new("TextLabel")
			payChip.Size = UDim2.new(0.5, -2, 1, 0)
			payChip.BackgroundColor3 = THEME.ModalBg
			payChip.BorderSizePixel = 0
			payChip.Text = "PEAK " .. meta.payoutMultiplier
			payChip.TextColor3 = THEME.Positive
			payChip.TextSize = 9.5
			payChip.Font = Enum.Font.GothamBold
			payChip.Parent = statChipRow
			local pcCorner = Instance.new("UICorner")
			pcCorner.CornerRadius = UDim.new(0, 4)
			pcCorner.Parent = payChip

			-- Bottom Action Button (26px height)
			local actionBtn = Instance.new("TextButton")
			actionBtn.Name = "ActionBtn"
			actionBtn.Size = UDim2.new(1, 0, 0, 26)
			actionBtn.Position = UDim2.new(0, 0, 1, -26)
			actionBtn.BackgroundColor3 = THEME.ButtonDark
			actionBtn.BorderSizePixel = 0
			actionBtn.AutoButtonColor = false
			actionBtn.Text = "LOCKED"
			actionBtn.TextColor3 = THEME.TextMuted
			actionBtn.Font = Enum.Font.GothamBold
			actionBtn.TextSize = 11
			actionBtn.Parent = card
			cardActionBtns[shapeId] = actionBtn

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 5)
			btnCorner.Parent = actionBtn

			local clickOverlay = Instance.new("TextButton")
			clickOverlay.Size = UDim2.fromScale(1, 1)
			clickOverlay.BackgroundTransparency = 1
			clickOverlay.Text = ""
			clickOverlay.ZIndex = 5
			clickOverlay.Parent = card

			clickOverlay.MouseButton1Click:Connect(function()
				inspectShape(shapeId)
			end)
		end
	end

	inspectShape("D6")

	-- Turntable loop
	local animActive = false
	local elapsed = 0

	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function(dt: number)
		if not shapesOverlay.Visible then return end
		elapsed += dt

		for _, item in ipairs(orbitItems) do
			if item.model and item.model.PrimaryPart then
				if item.isHeroSingle then
					local rot = CFrame.Angles(elapsed * item.spinX, elapsed * item.spinY, elapsed * item.spinZ)
					local bob = math.sin(elapsed * item.bobFreq1) * item.bobAmp1
					item.model:PivotTo(CFrame.new(0, bob, 0) * rot)
				else
					local angle = item.baseAngle + elapsed * item.orbitSpeed
					local x = math.cos(angle) * item.radiusX
					local z = math.sin(angle) * (item.radiusX * 0.45)
					local y = math.sin(elapsed * item.bobFreq1 + item.phase1) * item.bobAmp1
					local rot = CFrame.Angles(elapsed * item.spinX + item.phaseX, elapsed * item.spinY + item.phaseY, elapsed * item.spinZ + item.phaseZ)
					item.model:PivotTo(CFrame.new(x, y, z) * rot)
				end
			end
		end

		if inspectedHeroModel and inspectedHeroModel.PrimaryPart then
			local rot = CFrame.Angles(elapsed * 0.35, elapsed * 0.70, elapsed * 0.25)
			local bob = math.sin(elapsed * 1.3) * 0.12
			inspectedHeroModel:PivotTo(CFrame.new(0, bob, 0) * rot)
		end

		for idx, cModel in ipairs(cardModels) do
			if cModel and cModel.PrimaryPart then
				local rot = CFrame.Angles(elapsed * 0.3 + idx * 0.1, elapsed * 0.6 + idx * 0.2, 0)
				cModel:PivotTo(CFrame.new(0, 0, 0) * rot)
			end
		end
	end)

	local function refreshShapes(state: any)
		-- `Shape`, capitalised, as `StateSyncService.buildSnapshot` writes it.
		-- This read asked for `shape` and so never matched, pinning the whole
		-- panel to the "D6" fallback -- the same defect as the slots panel, in
		-- a second place.
		local currentShape = if type(state) == "table" and type(state.dice) == "table" and #state.dice > 0
			then tostring(state.dice[1].Shape or "D6")
			else "D6"

		local equippedList = {}
		if type(state) == "table" and type(state.dice) == "table" then
			for _, d in ipairs(state.dice) do
				table.insert(equippedList, d.Shape or "D6")
			end
		end
		if #equippedList == 0 then
			table.insert(equippedList, currentShape)
		end

		rebuildOrbitChamber(equippedList)

		for shapeId, btn in pairs(cardActionBtns) do
			local isEquipped = false
			for _, eqId in ipairs(equippedList) do
				if eqId == shapeId then isEquipped = true; break end
			end

			if isEquipped then
				btn.Text = "EQUIPPED"
				btn.BackgroundColor3 = THEME.ButtonDark
				btn.TextColor3 = THEME.GoldPrimary
			else
				btn.Text = "SELECT"
				btn.BackgroundColor3 = THEME.ButtonDark
				btn.TextColor3 = THEME.TextMuted
			end
		end
	end

	return refreshShapes
end

--------------------------------------------------------------------------------
-- 2. DAILY QUESTS & REWARDS OVERLAY
--------------------------------------------------------------------------------
local function buildQuestsOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (any) -> ()
	local questsOverlay, legacyBody = UITheme.overlay("Daily Quests")
	questsOverlay.Parent = screenGui
	overlays["quests"] = questsOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, questVaultBody = formatModalShell(questsOverlay, "~ Daily Quests & Progression ~", getController)

	local mainRowLayout = Instance.new("UIListLayout")
	mainRowLayout.FillDirection = Enum.FillDirection.Horizontal
	mainRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainRowLayout.Padding = UDim.new(0, 12)
	mainRowLayout.Parent = questVaultBody

	-- Left Column (58%): 3 Heavy Quest Directives
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftQuestsCol"
	leftCol.Size = UDim2.new(0.58, -6, 1, 0)
	leftCol.BackgroundTransparency = 1
	leftCol.LayoutOrder = 1
	leftCol.Parent = questVaultBody

	local lList = Instance.new("UIListLayout")
	lList.Padding = UDim.new(0, 8)
	lList.SortOrder = Enum.SortOrder.LayoutOrder
	lList.Parent = leftCol

	local questRows: { any } = {}

	for i = 1, 3 do
		local card = Instance.new("Frame")
		card.Name = "QuestCard_" .. i
		card.Size = UDim2.new(1, 0, 0.333, -6)
		card.BackgroundColor3 = THEME.CardBg
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = leftCol

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 8)
		cCorner.Parent = card

		local cStroke = Instance.new("UIStroke")
		cStroke.Color = THEME.StrokeSubtle
		cStroke.Thickness = 1
		cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cStroke.Parent = card

		local cPad = Instance.new("UIPadding")
		cPad.PaddingTop = UDim.new(0, 6)
		cPad.PaddingBottom = UDim.new(0, 6)
		cPad.PaddingLeft = UDim.new(0, 12)
		cPad.PaddingRight = UDim.new(0, 12)
		cPad.Parent = card

		local topRow = Instance.new("Frame")
		topRow.Size = UDim2.new(1, 0, 0, 16)
		topRow.BackgroundTransparency = 1
		topRow.Parent = card

		local tagLbl = Instance.new("TextLabel")
		tagLbl.Size = UDim2.new(0.5, 0, 1, 0)
		tagLbl.BackgroundTransparency = 1
		tagLbl.Font = Enum.Font.Code
		tagLbl.Text = string.format("[ QUEST 0%d ]", i)
		tagLbl.TextColor3 = THEME.GoldPrimary
		tagLbl.TextSize = 11
		tagLbl.TextXAlignment = Enum.TextXAlignment.Left
		tagLbl.Parent = topRow

		local rewBadge = Instance.new("TextLabel")
		rewBadge.Size = UDim2.new(0.5, 0, 1, 0)
		rewBadge.Position = UDim2.new(0.5, 0, 0, 0)
		rewBadge.BackgroundTransparency = 1
		rewBadge.Font = Enum.Font.GothamBold
		rewBadge.Text = "REWARD: +$2,500 CASH"
		rewBadge.TextColor3 = THEME.Positive
		rewBadge.TextSize = 12
		rewBadge.TextXAlignment = Enum.TextXAlignment.Right
		rewBadge.Parent = topRow

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, 0, 0, 18)
		titleLbl.Position = UDim2.new(0, 0, 0, 16)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.Text = "HIGH-FREQUENCY CALIBRATION"
		titleLbl.TextColor3 = THEME.TextPrimary
		titleLbl.TextSize = 13.5
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(1, 0, 0, 16)
		descLbl.Position = UDim2.new(0, 0, 0, 34)
		descLbl.BackgroundTransparency = 1
		descLbl.Font = Enum.Font.GothamMedium
		descLbl.Text = "Perform 100 physical dice rolls in the arena."
		descLbl.TextColor3 = THEME.TextMuted
		descLbl.TextSize = 11.5
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.Parent = card

		local botRow = Instance.new("Frame")
		botRow.Size = UDim2.new(1, 0, 0, 28)
		botRow.Position = UDim2.new(0, 0, 1, -28)
		botRow.BackgroundTransparency = 1
		botRow.Parent = card

		local trackBack = Instance.new("Frame")
		trackBack.Size = UDim2.new(0.63, -8, 0, 10)
		trackBack.Position = UDim2.new(0, 0, 0.5, -5)
		trackBack.BackgroundColor3 = THEME.InsetBg
		trackBack.BorderSizePixel = 0
		trackBack.Parent = botRow

		local trCorner = Instance.new("UICorner")
		trCorner.CornerRadius = UDim.new(0, 5)
		trCorner.Parent = trackBack

		local trFill = Instance.new("Frame")
		trFill.Size = UDim2.fromScale(0, 1)
		trFill.BackgroundColor3 = THEME.GoldPrimary
		trFill.BorderSizePixel = 0
		trFill.Parent = trackBack

		local tfCorner = Instance.new("UICorner")
		tfCorner.CornerRadius = UDim.new(0, 5)
		tfCorner.Parent = trFill

		local countLbl = Instance.new("TextLabel")
		countLbl.Size = UDim2.new(0.63, -8, 0, 14)
		countLbl.Position = UDim2.new(0, 0, 0, -14)
		countLbl.BackgroundTransparency = 1
		countLbl.Font = Enum.Font.Code
		countLbl.Text = "COMPLETION: 0 / 100"
		countLbl.TextColor3 = THEME.TextMuted
		countLbl.TextSize = 10
		countLbl.TextXAlignment = Enum.TextXAlignment.Left
		countLbl.Parent = botRow

		local actionBtn = Instance.new("TextButton")
		actionBtn.Size = UDim2.new(0.37, 0, 1, 0)
		actionBtn.Position = UDim2.new(0.63, 0, 0, 0)
		actionBtn.BackgroundColor3 = THEME.ButtonDark
		actionBtn.BorderSizePixel = 0
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.Text = "IN PROGRESS"
		actionBtn.TextColor3 = THEME.TextMuted
		actionBtn.TextSize = 11
		actionBtn.Parent = botRow

		local abCorner = Instance.new("UICorner")
		abCorner.CornerRadius = UDim.new(0, 6)
		abCorner.Parent = actionBtn

		local rowState = { id = nil :: string?, isReady = false, isClaimed = false }

		actionBtn.MouseButton1Click:Connect(function()
			local id = rowState.id
			if id == nil or not rowState.isReady or rowState.isClaimed then
				return
			end
			actionBtn.Text = "CLAIMING..."
			task.spawn(function()
				local result = NetClient.claimQuest(id)
				if result.ok then
					actionBtn.Text = "CLAIMED \u{2713}"
					actionBtn.BackgroundColor3 = THEME.CardBg
					actionBtn.TextColor3 = THEME.TextMuted
					rowState.isClaimed = true
					rowState.isReady = false
				else
					actionBtn.Text = "CLAIM REWARD"
					actionBtn.BackgroundColor3 = THEME.Positive
					actionBtn.TextColor3 = THEME.TextDark
				end
			end)
		end)

		table.insert(questRows, {
			card = card,
			stroke = cStroke,
			tag = tagLbl,
			rew = rewBadge,
			title = titleLbl,
			desc = descLbl,
			count = countLbl,
			fill = trFill,
			button = actionBtn,
			state = rowState,
		})
	end

	-- Right Column (42%): Stacked Playtime Rewards & Daily Login
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightProgressionCol"
	rightCol.Size = UDim2.new(0.42, -6, 1, 0)
	rightCol.BackgroundTransparency = 1
	rightCol.LayoutOrder = 2
	rightCol.Parent = questVaultBody

	local rList = Instance.new("UIListLayout")
	rList.Padding = UDim.new(0, 8)
	rList.SortOrder = Enum.SortOrder.LayoutOrder
	rList.Parent = rightCol

	-- Top Pod: Playtime Rewards (58% height, clipping enabled)
	local chestPod = Instance.new("Frame")
	chestPod.Name = "PlaytimeRewardsPod"
	chestPod.Size = UDim2.new(1, 0, 0.58, -4)
	chestPod.BackgroundColor3 = THEME.CardBg
	chestPod.BorderSizePixel = 0
	chestPod.ClipsDescendants = true
	chestPod.LayoutOrder = 1
	chestPod.Parent = rightCol

	local cpCorner = Instance.new("UICorner")
	cpCorner.CornerRadius = UDim.new(0, 8)
	cpCorner.Parent = chestPod

	local cpStroke = Instance.new("UIStroke")
	cpStroke.Color = THEME.StrokeSubtle
	cpStroke.Thickness = 1
	cpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cpStroke.Parent = chestPod

	local cpPad = Instance.new("UIPadding")
	cpPad.PaddingTop = UDim.new(0, 6)
	cpPad.PaddingBottom = UDim.new(0, 6)
	cpPad.PaddingLeft = UDim.new(0, 12)
	cpPad.PaddingRight = UDim.new(0, 12)
	cpPad.Parent = chestPod

	local cpHeader = Instance.new("TextLabel")
	cpHeader.Size = UDim2.new(1, 0, 0, 16)
	cpHeader.Position = UDim2.new(0, 0, 0, 0)
	cpHeader.BackgroundTransparency = 1
	cpHeader.Font = Enum.Font.GothamBold
	cpHeader.Text = "\u{25B6} PLAYTIME REWARDS"
	cpHeader.TextColor3 = THEME.GoldPrimary
	cpHeader.TextSize = 12.5
	cpHeader.TextXAlignment = Enum.TextXAlignment.Left
	cpHeader.Parent = chestPod

	local chestScroll = Instance.new("ScrollingFrame")
	chestScroll.Name = "ChestScroll"
	chestScroll.Size = UDim2.new(1, 0, 1, -20)
	chestScroll.Position = UDim2.new(0, 0, 0, 18)
	chestScroll.BackgroundTransparency = 1
	chestScroll.BorderSizePixel = 0
	chestScroll.ScrollBarThickness = 3
	chestScroll.ScrollBarImageColor3 = THEME.GoldPrimary
	chestScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	chestScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	chestScroll.Parent = chestPod

	local cpList = Instance.new("UIListLayout")
	cpList.Padding = UDim.new(0, 6)
	cpList.SortOrder = Enum.SortOrder.LayoutOrder
	cpList.Parent = chestScroll

	local PLAYTIME_CONFIG = {
		{ id = "Tier1", name = "Tier 1", timeSec = 5 * 60, timeStr = "5 Mins", rewardText = "+$500 CASH", rewardColor = THEME.Positive },
		{ id = "Tier2", name = "Tier 2", timeSec = 15 * 60, timeStr = "15 Mins", rewardText = "+$1,500 CASH", rewardColor = THEME.Positive },
		{ id = "Tier3", name = "Tier 3", timeSec = 30 * 60, timeStr = "30 Mins", rewardText = "+25 GEMS", rewardColor = THEME.Gems },
		{ id = "Tier4", name = "Tier 4", timeSec = 45 * 60, timeStr = "45 Mins", rewardText = "+50 GEMS", rewardColor = THEME.Gems },
		{ id = "Tier5", name = "Tier 5", timeSec = 60 * 60, timeStr = "60 Mins", rewardText = "+$10,000 CASH", rewardColor = THEME.Positive },
		{ id = "Tier6", name = "Tier 6", timeSec = 90 * 60, timeStr = "90 Mins", rewardText = "+3 DIAMONDS", rewardColor = THEME.Diamonds },
	}

	local sessionStartTime = os.clock()
	local playtimeRows: { any } = {}

	for i, tier in ipairs(PLAYTIME_CONFIG) do
		local tRow = Instance.new("Frame")
		tRow.Size = UDim2.new(1, -4, 0, 52)
		tRow.BackgroundColor3 = THEME.InsetBg
		tRow.BorderSizePixel = 0
		tRow.LayoutOrder = i
		tRow.Parent = chestScroll

		local trCorner2 = Instance.new("UICorner")
		trCorner2.CornerRadius = UDim.new(0, 6)
		trCorner2.Parent = tRow

		local tStroke = Instance.new("UIStroke")
		tStroke.Color = THEME.StrokeSubtle
		tStroke.Thickness = 1
		tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tStroke.Parent = tRow

		local tPad = Instance.new("UIPadding")
		tPad.PaddingLeft = UDim.new(0, 10)
		tPad.PaddingRight = UDim.new(0, 10)
		tPad.Parent = tRow

		local tTitle = Instance.new("TextLabel")
		tTitle.Size = UDim2.new(0.62, 0, 0, 16)
		tTitle.Position = UDim2.new(0, 0, 0, 4)
		tTitle.BackgroundTransparency = 1
		tTitle.Font = Enum.Font.GothamBold
		tTitle.Text = string.format("%s (%s)", tier.name, tier.timeStr)
		tTitle.TextColor3 = THEME.TextPrimary
		tTitle.TextSize = 12
		tTitle.TextXAlignment = Enum.TextXAlignment.Left
		tTitle.Parent = tRow

		local tReward = Instance.new("TextLabel")
		tReward.Size = UDim2.new(0.62, 0, 0, 14)
		tReward.Position = UDim2.new(0, 0, 0, 20)
		tReward.BackgroundTransparency = 1
		tReward.Font = Enum.Font.GothamBold
		tReward.Text = "REWARD: " .. tier.rewardText
		tReward.TextColor3 = tier.rewardColor
		tReward.TextSize = 11
		tReward.TextXAlignment = Enum.TextXAlignment.Left
		tReward.Parent = tRow

		local subProgress = Instance.new("TextLabel")
		subProgress.Size = UDim2.new(0.62, 0, 0, 14)
		subProgress.Position = UDim2.new(0, 0, 0, 34)
		subProgress.BackgroundTransparency = 1
		subProgress.Font = Enum.Font.Code
		subProgress.Text = "STATUS: IN PROGRESS"
		subProgress.TextColor3 = THEME.GoldPrimary
		subProgress.TextSize = 10
		subProgress.TextXAlignment = Enum.TextXAlignment.Left
		subProgress.Parent = tRow

		local cBtn = Instance.new("TextButton")
		cBtn.Size = UDim2.new(0.35, 0, 0, 34)
		cBtn.Position = UDim2.new(0.65, 0, 0.5, -17)
		cBtn.BackgroundColor3 = THEME.ButtonDark
		cBtn.BorderSizePixel = 0
		cBtn.Font = Enum.Font.GothamBold
		cBtn.Text = "LOCKED"
		cBtn.TextColor3 = THEME.TextMuted
		cBtn.TextSize = 11
		cBtn.Parent = tRow

		local cbCorner = Instance.new("UICorner")
		cbCorner.CornerRadius = UDim.new(0, 6)
		cbCorner.Parent = cBtn

		local tState = { id = tier.id, claimed = false, ready = false }

		cBtn.MouseButton1Click:Connect(function()
			if not tState.ready or tState.claimed then
				return
			end
			cBtn.Text = "CLAIMING..."
			task.spawn(function()
				local res = NetClient.claimChest(tier.id)
				if res.ok then
					tState.claimed = true
					tState.ready = false
					cBtn.Text = "CLAIMED \u{2713}"
					cBtn.BackgroundColor3 = THEME.CardBg
					cBtn.TextColor3 = THEME.TextMuted
					subProgress.Text = "STATUS: CLAIMED"
					subProgress.TextColor3 = THEME.TextMuted
				else
					cBtn.Text = "CLAIM"
					cBtn.BackgroundColor3 = THEME.Positive
					cBtn.TextColor3 = THEME.TextDark
				end
			end)
		end)

		table.insert(playtimeRows, {
			config = tier,
			title = tTitle,
			reward = tReward,
			status = subProgress,
			button = cBtn,
			state = tState,
		})
	end

	-- Bottom Pod: Daily Login Streak (42% height with 3x2 + Day 7 layout)
	local loginPod = Instance.new("Frame")
	loginPod.Name = "DailyLoginPod"
	loginPod.Size = UDim2.new(1, 0, 0.42, -4)
	loginPod.BackgroundColor3 = THEME.CardBg
	loginPod.BorderSizePixel = 0
	loginPod.LayoutOrder = 2
	loginPod.Parent = rightCol

	local lpCorner = Instance.new("UICorner")
	lpCorner.CornerRadius = UDim.new(0, 8)
	lpCorner.Parent = loginPod

	local lpStroke = Instance.new("UIStroke")
	lpStroke.Color = THEME.StrokeSubtle
	lpStroke.Thickness = 1
	lpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lpStroke.Parent = loginPod

	local lpPad = Instance.new("UIPadding")
	lpPad.PaddingTop = UDim.new(0, 6)
	lpPad.PaddingBottom = UDim.new(0, 6)
	lpPad.PaddingLeft = UDim.new(0, 12)
	lpPad.PaddingRight = UDim.new(0, 12)
	lpPad.Parent = loginPod

	local lpHeader = Instance.new("TextLabel")
	lpHeader.Size = UDim2.new(1, 0, 0, 16)
	lpHeader.Position = UDim2.new(0, 0, 0, 0)
	lpHeader.BackgroundTransparency = 1
	lpHeader.Font = Enum.Font.GothamBold
	lpHeader.Text = "\u{25C8} DAILY LOGIN (DAY 1 / 7)"
	lpHeader.TextColor3 = THEME.GoldPrimary
	lpHeader.TextSize = 12.5
	lpHeader.TextXAlignment = Enum.TextXAlignment.Left
	lpHeader.Parent = loginPod

	local gridContainer = Instance.new("Frame")
	gridContainer.Name = "GridContainer"
	gridContainer.Size = UDim2.new(1, 0, 1, -20)
	gridContainer.Position = UDim2.new(0, 0, 0, 18)
	gridContainer.BackgroundTransparency = 1
	gridContainer.Parent = loginPod

	local gcList = Instance.new("UIListLayout")
	gcList.FillDirection = Enum.FillDirection.Horizontal
	gcList.Padding = UDim.new(0, 6)
	gcList.SortOrder = Enum.SortOrder.LayoutOrder
	gcList.Parent = gridContainer

	local leftDaysCol = Instance.new("Frame")
	leftDaysCol.Name = "LeftDaysCol"
	leftDaysCol.Size = UDim2.new(0.72, -3, 1, 0)
	leftDaysCol.BackgroundTransparency = 1
	leftDaysCol.LayoutOrder = 1
	leftDaysCol.Parent = gridContainer

	local ldcList = Instance.new("UIListLayout")
	ldcList.Padding = UDim.new(0, 4)
	ldcList.SortOrder = Enum.SortOrder.LayoutOrder
	ldcList.Parent = leftDaysCol

	local dayCardUIs: { any } = {}

	local LOGIN_LADDER = {
		{ day = 1, amount = "$300", currency = "CASH", kind = "Cash", currColor = THEME.Positive },
		{ day = 2, amount = "$700", currency = "CASH", kind = "Cash", currColor = THEME.Positive },
		{ day = 3, amount = "+20", currency = "GEMS", kind = "Gems", currColor = THEME.Gems },
		{ day = 4, amount = "$2.0K", currency = "CASH", kind = "Cash", currColor = THEME.Positive },
		{ day = 5, amount = "+45", currency = "GEMS", kind = "Gems", currColor = THEME.Gems },
		{ day = 6, amount = "$5.0K", currency = "CASH", kind = "Cash", currColor = THEME.Positive },
		{ day = 7, amount = "+5", currency = "DIAMONDS", kind = "Diamonds", jackpot = true, currColor = THEME.Diamonds },
	}

	local function createDayCard(d: any, parentRow: Frame)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0.333, -4, 1, 0)
		card.BackgroundColor3 = THEME.InsetBg
		card.BorderSizePixel = 0
		card.LayoutOrder = d.day
		card.Parent = parentRow

		local cCorn = Instance.new("UICorner")
		cCorn.CornerRadius = UDim.new(0, 6)
		cCorn.Parent = card

		local cStk = Instance.new("UIStroke")
		cStk.Color = THEME.StrokeSubtle
		cStk.Thickness = 1
		cStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cStk.Parent = card

		local dTitle = Instance.new("TextLabel")
		dTitle.Size = UDim2.new(1, 0, 0, 12)
		dTitle.Position = UDim2.new(0, 0, 0, 2)
		dTitle.BackgroundTransparency = 1
		dTitle.Font = Enum.Font.GothamBold
		dTitle.Text = "DAY " .. d.day
		dTitle.TextColor3 = THEME.TextMuted
		dTitle.TextSize = 9
		dTitle.Parent = card

		local dVal = Instance.new("TextLabel")
		dVal.Size = UDim2.new(1, 0, 0, 14)
		dVal.Position = UDim2.new(0, 0, 0, 14)
		dVal.BackgroundTransparency = 1
		dVal.Font = Enum.Font.GothamBold
		dVal.Text = d.amount
		dVal.TextColor3 = THEME.TextPrimary
		dVal.TextSize = 11
		dVal.Parent = card

		local dCurr = Instance.new("TextLabel")
		dCurr.Size = UDim2.new(1, 0, 0, 10)
		dCurr.Position = UDim2.new(0, 0, 0, 28)
		dCurr.BackgroundTransparency = 1
		dCurr.Font = Enum.Font.Code
		dCurr.Text = d.currency
		dCurr.TextColor3 = d.currColor
		dCurr.TextSize = 8
		dCurr.Parent = card

		local dBtn = Instance.new("Frame")
		dBtn.Size = UDim2.new(1, -4, 0, 14)
		dBtn.Position = UDim2.new(0, 2, 1, -16)
		dBtn.BackgroundColor3 = THEME.ButtonDark
		dBtn.BorderSizePixel = 0
		dBtn.Parent = card

		local dbCorner = Instance.new("UICorner")
		dbCorner.CornerRadius = UDim.new(0, 4)
		dbCorner.Parent = dBtn

		local dbText = Instance.new("TextLabel")
		dbText.Size = UDim2.fromScale(1, 1)
		dbText.BackgroundTransparency = 1
		dbText.Font = Enum.Font.GothamBold
		dbText.Text = "LOCKED"
		dbText.TextColor3 = THEME.TextMuted
		dbText.TextSize = 8
		dbText.Parent = dBtn

		table.insert(dayCardUIs, {
			day = d.day,
			card = card,
			stroke = cStk,
			title = dTitle,
			val = dVal,
			curr = dCurr,
			stat = dbText,
			currColor = d.currColor,
		})
	end

	local row1 = Instance.new("Frame")
	row1.Size = UDim2.new(1, 0, 0.5, -2)
	row1.BackgroundTransparency = 1
	row1.LayoutOrder = 1
	row1.Parent = leftDaysCol

	local r1List = Instance.new("UIListLayout")
	r1List.FillDirection = Enum.FillDirection.Horizontal
	r1List.Padding = UDim.new(0, 4)
	r1List.Parent = row1

	for i = 1, 3 do
		createDayCard(LOGIN_LADDER[i], row1)
	end

	local row2 = Instance.new("Frame")
	row2.Size = UDim2.new(1, 0, 0.5, -2)
	row2.BackgroundTransparency = 1
	row2.LayoutOrder = 2
	row2.Parent = leftDaysCol

	local r2List = Instance.new("UIListLayout")
	r2List.FillDirection = Enum.FillDirection.Horizontal
	r2List.Padding = UDim.new(0, 4)
	r2List.Parent = row2

	for i = 4, 6 do
		createDayCard(LOGIN_LADDER[i], row2)
	end

	-- Day 7 Grand Reward
	local day7Card = Instance.new("Frame")
	day7Card.Name = "Day7GrandReward"
	day7Card.Size = UDim2.new(0.28, -3, 1, 0)
	day7Card.BackgroundColor3 = THEME.InsetBg
	day7Card.BorderSizePixel = 0
	day7Card.LayoutOrder = 2
	day7Card.Parent = gridContainer

	local d7Corner = Instance.new("UICorner")
	d7Corner.CornerRadius = UDim.new(0, 8)
	d7Corner.Parent = day7Card

	local d7Stroke = Instance.new("UIStroke")
	d7Stroke.Color = THEME.Diamonds
	d7Stroke.Thickness = 1.5
	d7Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	d7Stroke.Parent = day7Card

	local d7Title = Instance.new("TextLabel")
	d7Title.Size = UDim2.new(1, 0, 0, 16)
	d7Title.Position = UDim2.new(0, 0, 0, 4)
	d7Title.BackgroundTransparency = 1
	d7Title.Font = Enum.Font.GothamBold
	d7Title.Text = "\u{2605} DAY 7"
	d7Title.TextColor3 = THEME.Diamonds
	d7Title.TextSize = 11
	d7Title.Parent = day7Card

	local d7Amount = Instance.new("TextLabel")
	d7Amount.Size = UDim2.new(1, 0, 0, 22)
	d7Amount.Position = UDim2.new(0, 0, 0, 22)
	d7Amount.BackgroundTransparency = 1
	d7Amount.Font = Enum.Font.GothamBlack
	d7Amount.Text = "+5"
	d7Amount.TextColor3 = THEME.Diamonds
	d7Amount.TextSize = 18
	d7Amount.Parent = day7Card

	local d7Sub = Instance.new("TextLabel")
	d7Sub.Size = UDim2.new(1, 0, 0, 12)
	d7Sub.Position = UDim2.new(0, 0, 0, 44)
	d7Sub.BackgroundTransparency = 1
	d7Sub.Font = Enum.Font.GothamBold
	d7Sub.Text = "DIAMONDS"
	d7Sub.TextColor3 = THEME.GoldPrimary
	d7Sub.TextSize = 9
	d7Sub.Parent = day7Card

	local d7Btn = Instance.new("Frame")
	d7Btn.Size = UDim2.new(1, -4, 0, 16)
	d7Btn.Position = UDim2.new(0, 2, 1, -18)
	d7Btn.BackgroundColor3 = THEME.ButtonDark
	d7Btn.BorderSizePixel = 0
	d7Btn.Parent = day7Card

	local d7bCorner = Instance.new("UICorner")
	d7bCorner.CornerRadius = UDim.new(0, 4)
	d7bCorner.Parent = d7Btn

	local d7bText = Instance.new("TextLabel")
	d7bText.Size = UDim2.fromScale(1, 1)
	d7bText.BackgroundTransparency = 1
	d7bText.Font = Enum.Font.GothamBold
	d7bText.Text = "LOCKED"
	d7bText.TextColor3 = THEME.TextMuted
	d7bText.TextSize = 8.5
	d7bText.Parent = d7Btn

	table.insert(dayCardUIs, {
		day = 7,
		card = day7Card,
		stroke = d7Stroke,
		title = d7Title,
		val = d7Amount,
		stat = d7bText,
		isGrand = true,
	})

	local function refreshQuests(state: any)
		-- Update playtime tiers
		local sessionSec = os.clock() - sessionStartTime
		for _, row in ipairs(playtimeRows) do
			if not row.state.claimed then
				if sessionSec >= row.config.timeSec then
					row.state.ready = true
					row.button.Text = "CLAIM"
					row.button.BackgroundColor3 = THEME.Positive
					row.button.TextColor3 = THEME.TextDark
					row.status.Text = "STATUS: UNLOCKED"
					row.status.TextColor3 = THEME.Positive
				else
					row.state.ready = false
					local rem = row.config.timeSec - sessionSec
					local rMin = math.ceil(rem / 60)
					row.button.Text = "LOCKED"
					row.button.BackgroundColor3 = THEME.ButtonDark
					row.button.TextColor3 = THEME.TextMuted
					row.status.Text = string.format("STATUS: %dm left", rMin)
					row.status.TextColor3 = THEME.GoldPrimary
				end
			end
		end

		-- Refresh Daily Login Matrix
		local streakData = if type(state) == "table" then state.loginStreak else nil
		local currentDay = 1
		local claimedToday = false
		if type(streakData) == "table" then
			currentDay = math.clamp(((tonumber(streakData.count) or 1) - 1) % 7 + 1, 1, 7)
			claimedToday = streakData.claimedToday == true
		end

		lpHeader.Text = string.format("\u{25C8} DAILY LOGIN (DAY %d / 7)", currentDay)

		for _, item in ipairs(dayCardUIs) do
			if item.day < currentDay or (item.day == currentDay and claimedToday) then
				if item.isGrand then
					item.stat.Text = "CLAIMED \u{2713}"
					item.stat.TextColor3 = THEME.TextMuted
					item.stroke.Color = THEME.StrokeSubtle
				else
					item.card.BackgroundColor3 = THEME.InsetBg
					item.stroke.Color = THEME.StrokeSubtle
					item.stroke.Thickness = 1
					item.title.TextColor3 = THEME.TextMuted
					item.val.TextColor3 = THEME.TextMuted
					item.stat.Text = "\u{2713} DONE"
					item.stat.TextColor3 = THEME.TextMuted
				end
			elseif item.day == currentDay and not claimedToday then
				if item.isGrand then
					item.stat.Text = "READY"
					item.stat.TextColor3 = THEME.Diamonds
					item.stroke.Color = THEME.Diamonds
					item.stroke.Thickness = 1.5
				else
					item.card.BackgroundColor3 = THEME.GoldPrimary
					item.stroke.Color = THEME.TextPrimary
					item.stroke.Thickness = 1.5
					item.title.TextColor3 = THEME.TextDark
					item.val.TextColor3 = THEME.TextDark
					item.stat.Text = "READY"
					item.stat.TextColor3 = THEME.TextDark
				end
			else
				if item.isGrand then
					item.stat.Text = "LOCKED"
					item.stat.TextColor3 = THEME.TextMuted
					item.stroke.Color = THEME.Diamonds
					item.stroke.Thickness = 1.5
				else
					item.card.BackgroundColor3 = THEME.InsetBg
					item.stroke.Color = THEME.StrokeSubtle
					item.stroke.Thickness = 1
					item.title.TextColor3 = THEME.TextMuted
					item.val.TextColor3 = THEME.TextPrimary
					item.stat.Text = "LOCKED"
					item.stat.TextColor3 = THEME.TextMuted
				end
			end
		end
	end

	return refreshQuests
end

--------------------------------------------------------------------------------
-- 3. SHOP & EXCHANGE OVERLAY
--------------------------------------------------------------------------------
local function buildShopOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (any) -> ()
	local shopOverlay, legacyBody = UITheme.overlay("Shop & Exchange")
	shopOverlay.Parent = screenGui
	overlays["shop"] = shopOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, shopBodyCanvas = formatModalShell(shopOverlay, "~ Shop & Exchange ~", getController)

	-- Category Selector Tabs Bar (36px height)
	local categoryBar = Instance.new("Frame")
	categoryBar.Name = "CategoryBar"
	categoryBar.Size = UDim2.new(1, 0, 0, 36)
	categoryBar.Position = UDim2.new(0, 0, 0, 0)
	categoryBar.BackgroundColor3 = THEME.InsetBg
	categoryBar.BorderSizePixel = 0
	categoryBar.Parent = shopBodyCanvas

	local cbCorner = Instance.new("UICorner")
	cbCorner.CornerRadius = UDim.new(0, 6)
	cbCorner.Parent = categoryBar

	local cbStroke = Instance.new("UIStroke")
	cbStroke.Color = THEME.StrokeSubtle
	cbStroke.Thickness = 1
	cbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cbStroke.Parent = categoryBar

	local cbList = Instance.new("UIListLayout")
	cbList.FillDirection = Enum.FillDirection.Horizontal
	cbList.SortOrder = Enum.SortOrder.LayoutOrder
	cbList.Padding = UDim.new(0, 6)
	cbList.Parent = categoryBar

	local cbPad = Instance.new("UIPadding")
	cbPad.PaddingLeft = UDim.new(0, 6)
	cbPad.PaddingRight = UDim.new(0, 6)
	cbPad.PaddingTop = UDim.new(0, 4)
	cbPad.PaddingBottom = UDim.new(0, 4)
	cbPad.Parent = categoryBar

	local CATEGORIES = {
		{ id = "ALL", label = "ALL PRODUCTS" },
		{ id = "GAMEPASS", label = "GAMEPASSES" },
		{ id = "CURRENCY", label = "CURRENCY" },
		{ id = "BOOST", label = "BOOSTS & BUNDLES" },
	}

	local currentCategory = "ALL"
	local categoryButtons: { [string]: TextButton } = {}
	local itemFrames: { [string]: Frame } = {}

	local function updateCategoryFilter(catId: string)
		currentCategory = catId
		for id, btn in pairs(categoryButtons) do
			if id == catId then
				btn.BackgroundColor3 = THEME.GoldPrimary
				btn.TextColor3 = THEME.TextDark
			else
				btn.BackgroundColor3 = THEME.ButtonDark
				btn.TextColor3 = THEME.TextMuted
			end
		end
		for key, card in pairs(itemFrames) do
			local cType = card:GetAttribute("Category")
			if currentCategory == "ALL" or cType == currentCategory then
				card.Visible = true
			else
				card.Visible = false
			end
		end
	end

	for order, cat in ipairs(CATEGORIES) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "CategoryTab_" .. cat.id
		tabBtn.Size = UDim2.new(0.25, -5, 1, 0)
		tabBtn.BackgroundColor3 = if cat.id == "ALL" then THEME.GoldPrimary else THEME.ButtonDark
		tabBtn.BorderSizePixel = 0
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.Text = cat.label
		tabBtn.TextColor3 = if cat.id == "ALL" then THEME.TextDark else THEME.TextMuted
		tabBtn.TextSize = 11
		tabBtn.TextStrokeTransparency = 1
		tabBtn.LayoutOrder = order
		tabBtn.Parent = categoryBar

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 6)
		tabCorner.Parent = tabBtn

		categoryButtons[cat.id] = tabBtn

		tabBtn.MouseButton1Click:Connect(function()
			updateCategoryFilter(cat.id)
		end)
	end

	-- Scrolling Shop Body
	local shopScroll = Instance.new("ScrollingFrame")
	shopScroll.Name = "ShopGridScroll"
	shopScroll.Position = UDim2.new(0, 0, 0, 42)
	shopScroll.Size = UDim2.new(1, 0, 1, -42)
	shopScroll.BackgroundTransparency = 1
	shopScroll.BorderSizePixel = 0
	shopScroll.ScrollBarThickness = 4
	shopScroll.ScrollBarImageColor3 = THEME.GoldPrimary
	shopScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	shopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	shopScroll.ClipsDescendants = true
	shopScroll.Parent = shopBodyCanvas

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -6, 0, 176)
	gridLayout.CellPadding = UDim2.new(0, 12, 0, 12)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = shopScroll

	local sellableItems: { MonetisationCatalog.Entry } = {}
	for _, entry in pairs(MonetisationCatalog.Passes) do
		if MonetisationCatalog.isSellable(entry) then table.insert(sellableItems, entry) end
	end
	for _, entry in pairs(MonetisationCatalog.Products) do
		if MonetisationCatalog.isSellable(entry) then table.insert(sellableItems, entry) end
	end
	table.sort(sellableItems, function(a, b) return a.key < b.key end)

	local SHOP_TIER_DETAIL: { [string]: string } = {
		VipVault = string.format(
			"Vault: +%d%% earning rate, capacity raised to %dh.\nStandard is %d%% and %dh.",
			math.floor(VaultCatalog.VIP_EFFICIENCY_BONUS * 100 + 0.5),
			math.floor(VaultCatalog.VIP_CAPACITY_SEC / 3600),
			math.floor(VaultCatalog.BASE_EFFICIENCY * 100 + 0.5),
			math.floor(VaultCatalog.BASE_CAPACITY_SEC / 3600)),
		AutoRoll = "Rolls automatically. Manual rolling is capped lower.",
		UltraAutoRoll = "Raises auto-roll speed ceiling above standard pass.",
		CashX2 = string.format("Multiplies Cash from rolls by %sx.", tostring(MonetisationCatalog.Passes.CashX2.amount or 2)),
		DieSlots2 = string.format("Adds %d slots on top of ascension count (cap %d).", MonetisationCatalog.Passes.DieSlots2.amount or 2, DiceCatalog.MAX_DIE_SLOTS),
		VipForge = string.format("Re-forging costs %d%% of standard price.", math.floor((MonetisationCatalog.Passes.VipForge.amount or 0.6) * 100 + 0.5)),
		StreakShield = "Void face pays nothing but won't reset streak.",
		StarterBundle = "Grants Cash, Gems, Diamonds and 1 die slot. One purchase only.",
		DiamondCache = string.format("Diamonds re-roll die shape (%d per change) and unlock tree nodes.", DiceCatalog.SHAPE_CHANGE_DIAMOND_COST),
		GemsLarge = string.format("Gems buy vault capacity at %d per hour (cap %dh).", VaultCatalog.GEMS_PER_CAPACITY_HOUR, math.floor(VaultCatalog.MAX_PURCHASED_CAPACITY_SEC / 3600)),
		GemsSmall = string.format("Gems buy vault capacity at %d per hour (cap %dh).", VaultCatalog.GEMS_PER_CAPACITY_HOUR, math.floor(VaultCatalog.MAX_PURCHASED_CAPACITY_SEC / 3600)),
		LuckBoost = "For 15 minutes, heavy faces land closer to even odds.",
		OfflineX2 = "Multiplies NEXT vault claim by 2x.",
		TimeSkip24 = "Pays 24 hours at your own earning rate.",
	}

	-- THE OWNED-STATE REGISTRY. Only gamepasses appear here: a pass is owned
	-- forever and must stop being offered, whereas a developer product (gems,
	-- boosts, time skips) is repeatable and always has a live BUY button.
	type ShopPassCard = {
		button: TextButton,
		blurb: TextLabel,
		baseBlurb: string,
		pill: TextLabel,
		stroke: UIStroke,
	}
	local passCards: { [string]: ShopPassCard } = {}
	local player = Players.LocalPlayer

	for order, entry in ipairs(sellableItems) do
		local detail = SHOP_TIER_DETAIL[entry.key]
		local isPass = MonetisationCatalog.Passes[entry.key] ~= nil
		local categoryType = if isPass then "GAMEPASS" elseif entry.kind == "Currency" then "CURRENCY" else "BOOST"

		local card = Instance.new("Frame")
		card.Name = "Item_" .. entry.key
		card.BackgroundColor3 = THEME.CardBg
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = shopScroll
		card:SetAttribute("Category", categoryType)
		itemFrames[entry.key] = card

		local cCorn = Instance.new("UICorner")
		cCorn.CornerRadius = UDim.new(0, 8)
		cCorn.Parent = card

		local cardStroke = Instance.new("UIStroke")
		-- `entry.owned` is not a field on `MonetisationCatalog.Entry`; the
		-- catalog describes the PRODUCT, and ownership is per-player state that
		-- arrives on the snapshot. Reading it here was always nil, so this
		-- branch never fired. `refreshShop` repaints this stroke instead.
		cardStroke.Color = THEME.StrokeSubtle
		cardStroke.Thickness = 1
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Parent = card

		local cardPadding = Instance.new("UIPadding")
		cardPadding.PaddingTop = UDim.new(0, 10)
		cardPadding.PaddingBottom = UDim.new(0, 10)
		cardPadding.PaddingLeft = UDim.new(0, 12)
		cardPadding.PaddingRight = UDim.new(0, 12)
		cardPadding.Parent = card

		local textStack = Instance.new("Frame")
		textStack.Name = "TextStack"
		textStack.Size = UDim2.new(1, 0, 1, -40)
		textStack.BackgroundTransparency = 1
		textStack.Parent = card

		local cardList = Instance.new("UIListLayout")
		cardList.Padding = UDim.new(0, 4)
		cardList.SortOrder = Enum.SortOrder.LayoutOrder
		cardList.FillDirection = Enum.FillDirection.Vertical
		cardList.Parent = textStack

		local tagRow = Instance.new("Frame")
		tagRow.Size = UDim2.new(1, 0, 0, 22)
		tagRow.BackgroundTransparency = 1
		tagRow.LayoutOrder = 1
		tagRow.Parent = textStack

		local categoryBadgeFrame = Instance.new("Frame")
		categoryBadgeFrame.Size = UDim2.new(0, 80, 1, 0)
		categoryBadgeFrame.BackgroundColor3 = THEME.InsetBg
		categoryBadgeFrame.BorderSizePixel = 0
		categoryBadgeFrame.Parent = tagRow
		local cbC = Instance.new("UICorner")
		cbC.CornerRadius = UDim.new(0, 4)
		cbC.Parent = categoryBadgeFrame

		local catStroke = Instance.new("UIStroke")
		catStroke.Color = THEME.GoldPrimary
		catStroke.Thickness = 1
		catStroke.Parent = categoryBadgeFrame

		local categoryLabel = Instance.new("TextLabel")
		categoryLabel.Size = UDim2.fromScale(1, 1)
		categoryLabel.BackgroundTransparency = 1
		categoryLabel.Font = Enum.Font.Code
		categoryLabel.Text = categoryType
		categoryLabel.TextColor3 = THEME.GoldPrimary
		categoryLabel.TextSize = 10
		categoryLabel.Parent = categoryBadgeFrame

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, -88, 1, 0)
		titleLbl.Position = UDim2.new(0, 88, 0, 0)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.Text = entry.name
		titleLbl.TextColor3 = THEME.TextPrimary
		titleLbl.TextSize = 13.5
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
		titleLbl.Parent = tagRow

		local blurbLbl = Instance.new("TextLabel")
		blurbLbl.Size = UDim2.new(1, 0, 0, 28)
		blurbLbl.BackgroundTransparency = 1
		blurbLbl.Font = Enum.Font.Gotham
		blurbLbl.Text = entry.blurb
		blurbLbl.TextColor3 = THEME.TextPrimary
		blurbLbl.TextSize = 12
		blurbLbl.TextWrapped = true
		blurbLbl.TextXAlignment = Enum.TextXAlignment.Left
		blurbLbl.TextYAlignment = Enum.TextYAlignment.Top
		blurbLbl.LayoutOrder = 2
		blurbLbl.Parent = textStack

		local blurbFlex = Instance.new("UIFlexItem")
		blurbFlex.FlexMode = Enum.UIFlexMode.Fill
		blurbFlex.Parent = blurbLbl

		if detail ~= nil then
			local fine = Instance.new("TextLabel")
			fine.Size = UDim2.new(1, 0, 0, 0)
			fine.AutomaticSize = Enum.AutomaticSize.Y
			fine.BackgroundTransparency = 1
			fine.Font = Enum.Font.Code
			fine.Text = detail
			fine.TextColor3 = THEME.TextMuted
			fine.TextSize = 10
			fine.TextWrapped = true
			fine.TextXAlignment = Enum.TextXAlignment.Left
			fine.LayoutOrder = 3
			fine.Parent = textStack
		end

		local actionRow = Instance.new("Frame")
		actionRow.Name = "ActionRow"
		actionRow.Size = UDim2.new(1, 0, 0, 32)
		actionRow.AnchorPoint = Vector2.new(0.5, 1)
		actionRow.Position = UDim2.new(0.5, 0, 1, 0)
		actionRow.BackgroundTransparency = 1
		actionRow.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyButton"
		buyBtn.Size = UDim2.fromScale(1, 1)
		buyBtn.BackgroundColor3 = THEME.GoldPrimary
		buyBtn.BorderSizePixel = 0
		buyBtn.Font = Enum.Font.GothamBold
		-- "BUY", NOT A PRICE. This read `entry.priceRobux`, which does not exist
		-- on `Entry` -- so `or 0` fired for every item and every button in the
		-- shop advertised "BUY FOR R$ 0". The catalog holds no price on purpose:
		-- Roblox owns the price, it varies by region and sale, and a figure
		-- asserted here is one the platform's own prompt will contradict.
		buyBtn.Text = "BUY"
		buyBtn.TextColor3 = THEME.TextDark
		buyBtn.TextSize = 12
		buyBtn.Parent = actionRow

		local bbC = Instance.new("UICorner")
		bbC.CornerRadius = UDim.new(0, 6)
		bbC.Parent = buyBtn

		-- OWNED, shown in the button's place rather than beside it, so an owned
		-- pass cannot be bought twice.
		local ownedPill = Instance.new("TextLabel")
		ownedPill.Name = "OwnedPill"
		ownedPill.Size = UDim2.fromScale(1, 1)
		ownedPill.BackgroundColor3 = THEME.ButtonDark
		ownedPill.BorderSizePixel = 0
		ownedPill.Font = Enum.Font.GothamBold
		ownedPill.Text = "OWNED"
		ownedPill.TextColor3 = THEME.GoldPrimary
		ownedPill.TextSize = 12
		ownedPill.Visible = false
		ownedPill.Parent = actionRow

		local opC = Instance.new("UICorner")
		opC.CornerRadius = UDim.new(0, 6)
		opC.Parent = ownedPill

		-- THE PURCHASE ITSELF. The revamp left every BUY button inert -- no
		-- handler at all, on the only screen in the game that earns money.
		--
		-- The client never grants anything: it opens the platform prompt, and
		-- the grant happens server-side in `ProcessReceipt` against the receipt
		-- Roblox issues. A failure to OPEN the window is all this can report.
		local assetId = entry.assetId
		buyBtn.MouseButton1Click:Connect(function()
			if assetId == nil then
				blurbLbl.Text = "Not available yet."
				blurbLbl.TextColor3 = THEME.TextMuted
				return
			end
			local ok, err
			if isPass then
				ok, err = pcall(MarketplaceService.PromptGamePassPurchase,
					MarketplaceService, player, assetId)
			else
				ok, err = pcall(MarketplaceService.PromptProductPurchase,
					MarketplaceService, player, assetId)
			end
			if not ok then
				warn(string.format("[V7MenuPanel] purchase prompt failed for %s: %s",
					entry.key, tostring(err)))
				blurbLbl.Text = "Could not open the purchase window."
				blurbLbl.TextColor3 = THEME.Negative
			end
		end)

		if isPass then
			passCards[entry.key] = {
				button = buyBtn,
				blurb = blurbLbl,
				baseBlurb = entry.blurb,
				pill = ownedPill,
				stroke = cardStroke,
			}
		end
	end

	-- Paints owned state across the gamepass cards. Was an empty stub after the
	-- revamp, so no card ever showed OWNED and every pass stayed on sale to the
	-- player who already had it.
	local function refreshShop(state: any)
		local owned = if type(state) == "table" and type(state.ownedPasses) == "table"
			then state.ownedPasses
			else {}
		for key, ui in pairs(passCards) do
			local isOwned = owned[key] == true
			ui.pill.Visible = isOwned
			ui.button.Visible = not isOwned
			ui.blurb.Text = ui.baseBlurb
			ui.blurb.TextColor3 = if isOwned then THEME.TextMuted else THEME.TextPrimary
			ui.stroke.Color = if isOwned then THEME.StrokeGold else THEME.StrokeSubtle
		end
	end

	return refreshShop
end

--------------------------------------------------------------------------------
-- 4. THE SOVEREIGN ASCENSION VAULT OVERLAY
--------------------------------------------------------------------------------
local function buildAscendOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (any) -> ()
	local ascendOverlay, legacyBody = UITheme.overlay("The Sovereign Ascension Vault")
	ascendOverlay.Parent = screenGui
	overlays["ascend"] = ascendOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, vaultBody = formatModalShell(ascendOverlay, "~ The Sovereign Ascension Vault ~", getController)

	local bodyRow = Instance.new("Frame")
	bodyRow.Name = "BodyRow"
	bodyRow.Size = UDim2.fromScale(1, 1)
	bodyRow.BackgroundTransparency = 1
	bodyRow.Parent = vaultBody

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Horizontal
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 12)
	bodyLayout.Parent = bodyRow

	-- LEFT COLUMN (48%): Prestige Command Pod
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftCommandCol"
	leftCol.Size = UDim2.new(0.48, -6, 1, 0)
	leftCol.BackgroundColor3 = THEME.CardBg
	leftCol.BorderSizePixel = 0
	leftCol.LayoutOrder = 1
	leftCol.Parent = bodyRow

	local lCorner = Instance.new("UICorner")
	lCorner.CornerRadius = UDim.new(0, 8)
	lCorner.Parent = leftCol

	local lStroke = Instance.new("UIStroke")
	lStroke.Color = THEME.StrokeSubtle
	lStroke.Thickness = 1
	lStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lStroke.Parent = leftCol

	local lPad = Instance.new("UIPadding")
	lPad.PaddingTop = UDim.new(0, 10)
	lPad.PaddingBottom = UDim.new(0, 10)
	lPad.PaddingLeft = UDim.new(0, 12)
	lPad.PaddingRight = UDim.new(0, 12)
	lPad.Parent = leftCol

	local leftList = Instance.new("UIListLayout")
	leftList.Padding = UDim.new(0, 6)
	leftList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	leftList.SortOrder = Enum.SortOrder.LayoutOrder
	leftList.Parent = leftCol

	local leftTagFrame = Instance.new("Frame")
	leftTagFrame.Name = "TagFrame"
	leftTagFrame.Size = UDim2.new(1, 0, 0, 22)
	leftTagFrame.BackgroundColor3 = THEME.InsetBg
	leftTagFrame.BorderSizePixel = 0
	leftTagFrame.LayoutOrder = 1
	leftTagFrame.Parent = leftCol

	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 4)
	tCorner.Parent = leftTagFrame

	local tStroke = Instance.new("UIStroke")
	tStroke.Color = THEME.StrokeSubtle
	tStroke.Thickness = 1
	tStroke.Parent = leftTagFrame

	local leftTag = Instance.new("TextLabel")
	leftTag.Size = UDim2.fromScale(1, 1)
	leftTag.BackgroundTransparency = 1
	leftTag.Font = Enum.Font.Code
	leftTag.Text = "[ 01 // PRESTIGE EXTRACTION ]"
	leftTag.TextColor3 = THEME.GoldPrimary
	leftTag.TextSize = 10
	leftTag.Parent = leftTagFrame

	local ascendReward = Instance.new("TextLabel")
	ascendReward.Name = "AscendReward"
	ascendReward.Size = UDim2.new(1, 0, 0, 36)
	ascendReward.BackgroundTransparency = 1
	ascendReward.Font = Enum.Font.GothamBlack
	ascendReward.Text = "+0 \u{2666} DIAMONDS"
	ascendReward.TextColor3 = THEME.Diamonds
	ascendReward.TextSize = 28
	ascendReward.LayoutOrder = 2
	ascendReward.Parent = leftCol

	local rewardSub = Instance.new("TextLabel")
	rewardSub.Name = "RewardSub"
	rewardSub.Size = UDim2.new(1, 0, 0, 14)
	rewardSub.BackgroundTransparency = 1
	rewardSub.Font = Enum.Font.GothamMedium
	rewardSub.Text = "Guaranteed Permanent Vault Asset"
	rewardSub.TextColor3 = THEME.TextMuted
	rewardSub.TextSize = 11
	rewardSub.LayoutOrder = 3
	rewardSub.Parent = leftCol

	local meterTrack = Instance.new("Frame")
	meterTrack.Name = "MeterTrack"
	meterTrack.Size = UDim2.new(1, 0, 0, 10)
	meterTrack.BackgroundColor3 = THEME.InsetBg
	meterTrack.BorderSizePixel = 0
	meterTrack.LayoutOrder = 4
	meterTrack.Parent = leftCol

	local mtCorner = Instance.new("UICorner")
	mtCorner.CornerRadius = UDim.new(0, 5)
	mtCorner.Parent = meterTrack

	local meterFill = Instance.new("Frame")
	meterFill.Name = "MeterFill"
	meterFill.Size = UDim2.fromScale(0, 1)
	meterFill.BackgroundColor3 = THEME.GoldPrimary
	meterFill.BorderSizePixel = 0
	meterFill.Parent = meterTrack

	local mfCorner = Instance.new("UICorner")
	mfCorner.CornerRadius = UDim.new(0, 5)
	mfCorner.Parent = meterFill

	local ascendProgress = Instance.new("TextLabel")
	ascendProgress.Name = "AscendProgress"
	ascendProgress.Size = UDim2.new(1, 0, 0, 18)
	ascendProgress.BackgroundTransparency = 1
	ascendProgress.Font = Enum.Font.GothamBold
	ascendProgress.Text = "Run Basis: $0 / $1.00M"
	ascendProgress.TextColor3 = THEME.TextPrimary
	ascendProgress.TextSize = 12
	ascendProgress.LayoutOrder = 5
	ascendProgress.Parent = leftCol

	local metricsCard = Instance.new("Frame")
	metricsCard.Name = "LifetimeMetricsPod"
	metricsCard.Size = UDim2.new(1, 0, 0, 136)
	metricsCard.BackgroundColor3 = THEME.InsetBg
	metricsCard.BorderSizePixel = 0
	metricsCard.LayoutOrder = 6
	metricsCard.Parent = leftCol

	local mcCorner = Instance.new("UICorner")
	mcCorner.CornerRadius = UDim.new(0, 6)
	mcCorner.Parent = metricsCard

	local mcStroke = Instance.new("UIStroke")
	mcStroke.Color = THEME.StrokeSubtle
	mcStroke.Thickness = 1
	mcStroke.Parent = metricsCard

	local mcPad = Instance.new("UIPadding")
	mcPad.PaddingTop = UDim.new(0, 8)
	mcPad.PaddingBottom = UDim.new(0, 8)
	mcPad.PaddingLeft = UDim.new(0, 12)
	mcPad.PaddingRight = UDim.new(0, 12)
	mcPad.Parent = metricsCard

	local mcList = Instance.new("UIListLayout")
	mcList.Padding = UDim.new(0, 4)
	mcList.SortOrder = Enum.SortOrder.LayoutOrder
	mcList.Parent = metricsCard

	local mHeader = Instance.new("TextLabel")
	mHeader.Size = UDim2.new(1, 0, 0, 16)
	mHeader.BackgroundTransparency = 1
	mHeader.Font = Enum.Font.GothamBold
	mHeader.Text = "VAULT YIELD & PROJECTIONS"
	mHeader.TextColor3 = THEME.GoldPrimary
	mHeader.TextSize = 11
	mHeader.TextXAlignment = Enum.TextXAlignment.Left
	mHeader.LayoutOrder = 1
	mHeader.Parent = metricsCard

	local function makeMetricRow(order: number, lblText: string, defaultVal: string, valColor: Color3): TextLabel
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.Parent = metricsCard

		local rLabel = Instance.new("TextLabel")
		rLabel.Size = UDim2.new(0.6, 0, 1, 0)
		rLabel.BackgroundTransparency = 1
		rLabel.Font = Enum.Font.GothamMedium
		rLabel.Text = lblText
		rLabel.TextColor3 = THEME.TextMuted
		rLabel.TextSize = 11
		rLabel.TextXAlignment = Enum.TextXAlignment.Left
		rLabel.Parent = row

		local rVal = Instance.new("TextLabel")
		rVal.Size = UDim2.new(0.4, 0, 1, 0)
		rVal.Position = UDim2.new(0.6, 0, 0, 0)
		rVal.BackgroundTransparency = 1
		rVal.Font = Enum.Font.GothamBold
		rVal.Text = defaultVal
		rVal.TextColor3 = valColor
		rVal.TextSize = 12
		rVal.TextXAlignment = Enum.TextXAlignment.Right
		rVal.Parent = row
		return rVal
	end

	local postVaultVal = makeMetricRow(2, "Post-Reset Vault Total:", "0 \u{2666} (+0)", THEME.Diamonds)
	local nextTierVal = makeMetricRow(3, "Next Diamond Tier:", "at $1.00M", THEME.GoldPrimary)
	local careerAscendVal = makeMetricRow(4, "Career Ascensions:", "0 Completed", THEME.Positive)

	local ascendBtn = Instance.new("TextButton")
	ascendBtn.Name = "AscendButton"
	ascendBtn.Size = UDim2.new(1, 0, 0, 42)
	ascendBtn.BackgroundColor3 = THEME.GoldPrimary
	ascendBtn.BorderSizePixel = 0
	ascendBtn.Font = Enum.Font.GothamBold
	ascendBtn.Text = "SEAL THE VAULT & ASCEND"
	ascendBtn.TextColor3 = THEME.TextDark
	ascendBtn.TextSize = 13
	ascendBtn.LayoutOrder = 7
	ascendBtn.Parent = leftCol

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 6)
	bCorner.Parent = ascendBtn

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = THEME.StrokeGold
	bStroke.Thickness = 1
	bStroke.Parent = ascendBtn

	local ascendStatus = Instance.new("TextLabel")
	ascendStatus.Name = "AscendStatus"
	ascendStatus.Size = UDim2.new(1, 0, 0, 26)
	ascendStatus.BackgroundTransparency = 1
	ascendStatus.Font = Enum.Font.GothamMedium
	ascendStatus.Text = "Ready to ascend. Press button to begin two-step confirmation."
	ascendStatus.TextColor3 = THEME.GoldPrimary
	ascendStatus.TextSize = 10
	ascendStatus.TextWrapped = true
	ascendStatus.LayoutOrder = 8
	ascendStatus.Parent = leftCol

	-- RIGHT COLUMN (52%): Retention Ledger
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightLedgerCol"
	rightCol.Size = UDim2.new(0.52, -6, 1, 0)
	rightCol.BackgroundTransparency = 1
	rightCol.LayoutOrder = 2
	rightCol.Parent = bodyRow

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.Padding = UDim.new(0, 8)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Parent = rightCol

	-- Top Card: Preserved Wealth
	local keptCard = Instance.new("Frame")
	keptCard.Name = "KeptCard"
	keptCard.Size = UDim2.new(1, 0, 0.5, -4)
	keptCard.BackgroundColor3 = THEME.CardBg
	keptCard.BorderSizePixel = 0
	keptCard.LayoutOrder = 1
	keptCard.Parent = rightCol

	local kCorner = Instance.new("UICorner")
	kCorner.CornerRadius = UDim.new(0, 8)
	kCorner.Parent = keptCard

	local kStroke = Instance.new("UIStroke")
	kStroke.Color = THEME.Positive
	kStroke.Thickness = 1
	kStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	kStroke.Parent = keptCard

	local kPad = Instance.new("UIPadding")
	kPad.PaddingTop = UDim.new(0, 8)
	kPad.PaddingBottom = UDim.new(0, 8)
	kPad.PaddingLeft = UDim.new(0, 12)
	kPad.PaddingRight = UDim.new(0, 12)
	kPad.Parent = keptCard

	local kList = Instance.new("UIListLayout")
	kList.Padding = UDim.new(0, 3)
	kList.SortOrder = Enum.SortOrder.LayoutOrder
	kList.Parent = keptCard

	local keptTitle = Instance.new("TextLabel")
	keptTitle.Name = "KeptTitle"
	keptTitle.Size = UDim2.new(1, 0, 0, 20)
	keptTitle.BackgroundTransparency = 1
	keptTitle.Font = Enum.Font.GothamBold
	keptTitle.Text = "\u{25B2} IMMUTABLE ASSETS (YOU KEEP)"
	keptTitle.TextColor3 = THEME.Positive
	keptTitle.TextSize = 12
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
		row.Size = UDim2.new(1, 0, 0, 18)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.Text = itemText
		row.TextColor3 = THEME.TextPrimary
		row.TextSize = 10.5
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i + 1
		row.Parent = keptCard
	end

	-- Bottom Card: Reset Losses
	local lostCard = Instance.new("Frame")
	lostCard.Name = "LostCard"
	lostCard.Size = UDim2.new(1, 0, 0.5, -4)
	lostCard.BackgroundColor3 = THEME.CardBg
	lostCard.BorderSizePixel = 0
	lostCard.LayoutOrder = 2
	lostCard.Parent = rightCol

	local lLostCorner = Instance.new("UICorner")
	lLostCorner.CornerRadius = UDim.new(0, 8)
	lLostCorner.Parent = lostCard

	local lostStroke = Instance.new("UIStroke")
	lostStroke.Color = THEME.Negative
	lostStroke.Thickness = 1
	lostStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lostStroke.Parent = lostCard

	local lostPad = Instance.new("UIPadding")
	lostPad.PaddingTop = UDim.new(0, 8)
	lostPad.PaddingBottom = UDim.new(0, 8)
	lostPad.PaddingLeft = UDim.new(0, 12)
	lostPad.PaddingRight = UDim.new(0, 12)
	lostPad.Parent = lostCard

	local lostL = Instance.new("UIListLayout")
	lostL.Padding = UDim.new(0, 3)
	lostL.SortOrder = Enum.SortOrder.LayoutOrder
	lostL.Parent = lostCard

	local lostTitle = Instance.new("TextLabel")
	lostTitle.Name = "LostTitle"
	lostTitle.Size = UDim2.new(1, 0, 0, 20)
	lostTitle.BackgroundTransparency = 1
	lostTitle.Font = Enum.Font.GothamBold
	lostTitle.Text = "\u{25BC} FORFEIT ON RESET (YOU LOSE)"
	lostTitle.TextColor3 = THEME.Negative
	lostTitle.TextSize = 12
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
		row.Size = UDim2.new(1, 0, 0, 18)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.Text = itemText
		row.TextColor3 = THEME.TextPrimary
		row.TextSize = 10.5
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i + 1
		row.Parent = lostCard
	end

	-- THE TWO-STEP CONFIRM.
	--
	-- The status label already promised one; the revamp shipped no handler at
	-- all, so the button was decorative. Ascension is IRREVERSIBLE -- it wipes
	-- cash, dice and upgrades -- so a single press must never reach the server.
	--
	-- Arming is deliberately fragile: it expires on a timer, it is cleared when
	-- the panel closes, and `refreshAscend` disarms it the moment the reward
	-- stops being available. Every one of those is a path where the player's
	-- intent has gone stale, and the safe reading of stale intent is "no".
	local ascendArmed = false
	local ascendInFlight = false
	local armToken = 0
	local ARM_WINDOW_SEC = 4

	local function disarmAscend()
		ascendArmed = false
		armToken += 1
		ascendBtn.Text = "SEAL THE VAULT & ASCEND"
		ascendBtn.BackgroundColor3 = THEME.GoldPrimary
	end

	local function setAscendEnabled(enabled: boolean)
		ascendBtn.Active = enabled
		ascendBtn.AutoButtonColor = enabled
		ascendBtn.BackgroundColor3 = if enabled then THEME.GoldPrimary else THEME.ButtonDark
		ascendBtn.TextColor3 = if enabled then THEME.TextDark else THEME.TextMuted
	end

	-- CLOSING THE PANEL CANCELS THE CONFIRMATION. Bound to the overlay's own
	-- visibility rather than routed through the controller's `closeAll`, so it
	-- holds for every path that hides this panel -- the close button, the scrim,
	-- and opening a different overlay -- without any of them having to know that
	-- ascend keeps arming state.
	ascendOverlay:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ascendOverlay.Visible and ascendArmed then
			disarmAscend()
		end
	end)

	ascendBtn.MouseButton1Click:Connect(function()
		if ascendInFlight or not ascendBtn.Active then
			return
		end

		if not ascendArmed then
			ascendArmed = true
			armToken += 1
			local myToken = armToken
			ascendBtn.Text = "PRESS AGAIN TO CONFIRM"
			ascendBtn.BackgroundColor3 = THEME.Negative
			ascendStatus.Text = "This wipes cash, dice and upgrades. Press again "
				.. "within a few seconds to confirm, or wait to cancel."
			ascendStatus.TextColor3 = THEME.Negative
			task.delay(ARM_WINDOW_SEC, function()
				-- Only the arming that is still current may disarm. A second
				-- arm inside the window bumps the token, so an older timer
				-- firing late cannot cancel a fresh confirmation.
				if ascendArmed and armToken == myToken then
					disarmAscend()
					ascendStatus.Text = "Confirmation expired. Press again to ascend."
					ascendStatus.TextColor3 = THEME.TextMuted
				end
			end)
			return
		end

		disarmAscend()
		ascendInFlight = true
		setAscendEnabled(false)
		ascendStatus.Text = "Ascending..."
		ascendStatus.TextColor3 = THEME.TextMuted
		task.spawn(function()
			local result = NetClient.ascend()
			ascendInFlight = false
			if result.ok then
				-- Deliberately no success figure here. The reward is the
				-- server's to state, and the snapshot that follows repaints
				-- every number on this panel from the profile.
				ascendStatus.Text = "Ascension complete."
				ascendStatus.TextColor3 = THEME.Positive
			else
				ascendStatus.Text = "Could not ascend. Nothing was changed."
				ascendStatus.TextColor3 = THEME.Negative
				setAscendEnabled(true)
			end
		end)
	end)

	local function refreshAscend(state: any)
		-- CASH ON HAND -- the same figure the HUD's cash readout shows.
		--
		-- Reading `lifetimeCash` here once told a player "$1.09M this run" when
		-- they had earned nothing of the sort, because lifetime never resets.
		-- Reading `cash` means this panel and the HUD are the same number by
		-- construction and cannot contradict each other.
		local cash = if type(state) == "table" then tonumber(state.cash) or 0 else 0
		local ascensions = if type(state) == "table" then tonumber(state.ascensions) or 0 else 0
		local diamonds = if type(state) == "table" then tonumber(state.diamonds) else nil
		local projected = DiceCatalog.ascensionDiamonds(cash)
		local threshold = DiceCatalog.ASCEND_MIN_LIFETIME_CASH

		careerAscendVal.Text = string.format("%d Completed", ascensions)
		nextTierVal.Text = "at $" .. Format.formatNumber(threshold)

		-- A figure with no field on the wire reads "--". It does NOT read zero:
		-- "0 diamonds" is a claim about the player's balance, and a balance the
		-- panel does not actually know is not one it may assert.
		if diamonds ~= nil then
			postVaultVal.Text = string.format("%s \u{2666} (+%s)",
				Format.formatNumber(diamonds), Format.formatNumber(projected))
		else
			postVaultVal.Text = "--"
		end

		meterFill.Size = UDim2.fromScale(
			math.clamp(if threshold > 0 then cash / threshold else 0, 0, 1), 1)

		if projected > 0 then
			ascendReward.Text = string.format("+%s \u{2666} DIAMONDS", Format.formatNumber(projected))
			ascendReward.TextColor3 = THEME.Diamonds
			-- Earned / target stays visible past the threshold so the two
			-- numbers remain comparable for the whole run.
			ascendProgress.Text = string.format("Run Basis: $%s / $%s",
				Format.formatNumber(cash), Format.formatNumber(threshold))
			setAscendEnabled(true)
			if not ascendArmed and not ascendInFlight then
				ascendStatus.Text = "Ready to ascend. Press button to begin "
					.. "two-step confirmation."
				ascendStatus.TextColor3 = THEME.GoldPrimary
			end
		else
			ascendReward.Text = "+0 \u{2666} DIAMONDS"
			ascendReward.TextColor3 = THEME.TextMuted
			ascendProgress.Text = string.format("Run Basis: $%s / $%s",
				Format.formatNumber(cash), Format.formatNumber(threshold))
			setAscendEnabled(false)
			-- THE REWARD WENT AWAY, SO THE ARMING MUST TOO. Otherwise a player
			-- who armed at the threshold and then spent below it still has a
			-- live confirmation pointed at a server call that would refuse.
			if ascendArmed then
				disarmAscend()
			end
			if not ascendInFlight then
				ascendStatus.Text = "Keep rolling to reach the ascension threshold."
				ascendStatus.TextColor3 = THEME.TextMuted
			end
		end
	end

	return refreshAscend
end

--------------------------------------------------------------------------------
-- 5. SETTINGS OVERLAY
--------------------------------------------------------------------------------
local function buildSettingsOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (any) -> ()
	local settingsOverlay, legacyBody = UITheme.overlay("Settings")
	settingsOverlay.Parent = screenGui
	overlays["settings"] = settingsOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, settingsBody = formatModalShell(settingsOverlay, "~ Settings & Options ~", getController)

	local sList = Instance.new("UIListLayout")
	sList.Padding = UDim.new(0, 8)
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.Parent = settingsBody

	local settingRows: { [string]: any } = {}

	for i, def in ipairs(SettingsCatalog.ordered()) do
		local row = Instance.new("Frame")
		row.Name = "SettingRow_" .. def.key
		row.Size = UDim2.new(1, 0, 0, 58)
		row.BackgroundColor3 = THEME.CardBg
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = settingsBody

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 8)
		rowCorner.Parent = row

		local rowStroke = Instance.new("UIStroke")
		rowStroke.Color = THEME.StrokeSubtle
		rowStroke.Thickness = 1
		rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rowStroke.Parent = row

		local rowPadding = Instance.new("UIPadding")
		rowPadding.PaddingTop = UDim.new(0, 8)
		rowPadding.PaddingBottom = UDim.new(0, 8)
		rowPadding.PaddingLeft = UDim.new(0, 14)
		rowPadding.PaddingRight = UDim.new(0, 14)
		rowPadding.Parent = row

		local infoFrame = Instance.new("Frame")
		infoFrame.Name = "InfoFrame"
		infoFrame.Size = UDim2.new(1, -135, 1, 0)
		infoFrame.BackgroundTransparency = 1
		infoFrame.Parent = row

		local infoList = Instance.new("UIListLayout")
		infoList.Padding = UDim.new(0, 2)
		infoList.SortOrder = Enum.SortOrder.LayoutOrder
		infoList.Parent = infoFrame

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, 0, 0, 20)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = def.label
		label.TextColor3 = THEME.GoldPrimary
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = 1
		label.Parent = infoFrame

		local blurb = Instance.new("TextLabel")
		blurb.Name = "Blurb"
		blurb.Size = UDim2.new(1, 0, 0, 18)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.Gotham
		blurb.Text = def.blurb
		blurb.TextColor3 = THEME.TextMuted
		blurb.TextSize = 12
		blurb.TextWrapped = true
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.LayoutOrder = 2
		blurb.Parent = infoFrame

		local toggleBtn = Instance.new("TextButton")
		toggleBtn.Name = "ToggleButton"
		toggleBtn.Size = UDim2.new(0, 120, 0, 36)
		toggleBtn.Position = UDim2.new(1, -120, 0.5, -18)
		toggleBtn.BackgroundColor3 = THEME.GoldPrimary
		toggleBtn.BorderSizePixel = 0
		toggleBtn.Font = Enum.Font.GothamBold
		toggleBtn.Text = "ACTIVE"
		toggleBtn.TextColor3 = THEME.TextDark
		toggleBtn.TextSize = 13
		toggleBtn.Parent = row

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = toggleBtn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = THEME.StrokeGold
		btnStroke.Thickness = 1
		btnStroke.Parent = toggleBtn

		local key = def.key
		toggleBtn.MouseButton1Click:Connect(function()
			local entry = settingRows[key]
			local current = entry ~= nil and entry.value == true
			NetClient.setSetting(key, not current)
		end)

		local function setDisplayState(active: boolean, available: boolean?)
			local usable = available ~= false
			if not usable then
				toggleBtn.BackgroundColor3 = THEME.InsetBg
				toggleBtn.TextColor3 = THEME.TextMuted
				toggleBtn.Text = "LOCKED"
				btnStroke.Color = THEME.StrokeSubtle
				toggleBtn.Active = false
			elseif active then
				toggleBtn.BackgroundColor3 = THEME.GoldPrimary
				toggleBtn.TextColor3 = THEME.TextDark
				toggleBtn.Text = "ACTIVE"
				btnStroke.Color = THEME.StrokeGold
			else
				toggleBtn.BackgroundColor3 = THEME.ButtonDark
				toggleBtn.TextColor3 = THEME.TextMuted
				toggleBtn.Text = "INACTIVE"
				btnStroke.Color = THEME.StrokeSubtle
			end
		end

		settingRows[key] = {
			set = setDisplayState,
			value = def.default,
			button = toggleBtn,
		}
	end

	-- PROMO CODES (Casino Ledger Style, 90px height)
	local codeCard = Instance.new("Frame")
	codeCard.Name = "PromoCard"
	codeCard.Size = UDim2.new(1, 0, 0, 90)
	codeCard.BackgroundColor3 = THEME.CardBg
	codeCard.BorderSizePixel = 0
	codeCard.LayoutOrder = 90
	codeCard.Parent = settingsBody

	local promoCorner = Instance.new("UICorner")
	promoCorner.CornerRadius = UDim.new(0, 8)
	promoCorner.Parent = codeCard

	local promoStroke = Instance.new("UIStroke")
	promoStroke.Color = THEME.StrokeSubtle
	promoStroke.Thickness = 1
	promoStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	promoStroke.Parent = codeCard

	local promoPad = Instance.new("UIPadding")
	promoPad.PaddingTop = UDim.new(0, 10)
	promoPad.PaddingBottom = UDim.new(0, 10)
	promoPad.PaddingLeft = UDim.new(0, 14)
	promoPad.PaddingRight = UDim.new(0, 14)
	promoPad.Parent = codeCard

	local promoList = Instance.new("UIListLayout")
	promoList.Padding = UDim.new(0, 6)
	promoList.SortOrder = Enum.SortOrder.LayoutOrder
	promoList.Parent = codeCard

	local codeTitle = Instance.new("TextLabel")
	codeTitle.Size = UDim2.new(1, 0, 0, 18)
	codeTitle.BackgroundTransparency = 1
	codeTitle.Font = Enum.Font.GothamBold
	codeTitle.Text = "PROMO CODE REDEMPTION"
	codeTitle.TextColor3 = THEME.GoldPrimary
	codeTitle.TextSize = 13
	codeTitle.TextXAlignment = Enum.TextXAlignment.Left
	codeTitle.LayoutOrder = 1
	codeTitle.Parent = codeCard

	local inputRow = Instance.new("Frame")
	inputRow.Size = UDim2.new(1, 0, 0, 36)
	inputRow.BackgroundTransparency = 1
	inputRow.LayoutOrder = 2
	inputRow.Parent = codeCard

	local codeBox = Instance.new("TextBox")
	codeBox.Size = UDim2.new(1, -130, 1, 0)
	codeBox.BackgroundColor3 = THEME.InsetBg
	codeBox.BorderSizePixel = 0
	codeBox.Font = Enum.Font.Code
	codeBox.PlaceholderText = "ENTER CODE"
	codeBox.PlaceholderColor3 = Color3.fromRGB(140, 130, 120)
	codeBox.Text = ""
	codeBox.TextColor3 = THEME.TextPrimary
	codeBox.TextSize = 13
	codeBox.TextXAlignment = Enum.TextXAlignment.Left
	codeBox.ClearTextOnFocus = false
	codeBox.Parent = inputRow

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 6)
	boxCorner.Parent = codeBox

	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingLeft = UDim.new(0, 10)
	boxPad.PaddingRight = UDim.new(0, 10)
	boxPad.Parent = codeBox

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = THEME.StrokeSubtle
	boxStroke.Thickness = 1
	boxStroke.Parent = codeBox

	local redeemBtn = Instance.new("TextButton")
	redeemBtn.Size = UDim2.new(0, 120, 1, 0)
	redeemBtn.Position = UDim2.new(1, -120, 0, 0)
	redeemBtn.BackgroundColor3 = THEME.GoldPrimary
	redeemBtn.BorderSizePixel = 0
	redeemBtn.Font = Enum.Font.GothamBold
	redeemBtn.Text = "REDEEM"
	redeemBtn.TextColor3 = THEME.TextDark
	redeemBtn.TextSize = 13
	redeemBtn.Parent = inputRow

	local rbc = Instance.new("UICorner")
	rbc.CornerRadius = UDim.new(0, 6)
	rbc.Parent = redeemBtn

	local function refreshSettings(state: any)
		if type(state) == "table" and type(state.settings) == "table" then
			for key, entry in pairs(settingRows) do
				local val = state.settings[key]
				if val ~= nil then
					entry.value = val
					entry.set(val, true)
				end
			end
		end
	end

	return refreshSettings
end

--------------------------------------------------------------------------------
-- 6. DIE SLOTS & TRAIT FORGE OVERLAY (APPROVED 4-QUADRANT ARCHITECTURE)
--------------------------------------------------------------------------------
local function buildSlotsOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (any) -> ()
	local slotsOverlay, legacyBody = UITheme.overlay("Die Slots")
	slotsOverlay.Parent = screenGui
	overlays["slots"] = slotsOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, bodyContainer = formatModalShell(slotsOverlay, "~ Slots & Trait Forge ~", getController)

	type SlotsViewportItem = {
		model: Model,
		pivot: CFrame,
		rotSpeed: Vector3,
		baseHeight: number,
		bobFreq: number,
		bobAmp: number,
		orbitRadius: number,
		orbitAngle: number,
		orbitSpeed: number,
		phase: number,
	}

	local slotsVpItems: { SlotsViewportItem } = {}
	local animActive = false
	local animElapsed = 0

	-- DROPS EVERY ITEM WHOSE MODEL IS NO LONGER IN THE DATA MODEL.
	--
	-- Both rebuild paths used to prune this list by testing `orbitRadius`, one
	-- keeping `== 0` and the other keeping `~= 0`, using the radius as a stand-in
	-- for "is this an orrery item or a mini". That stand-in is wrong for the most
	-- common profile in the game: `createOrreryChamber` sets `orbitRadius = 0`
	-- when there is a single die, so a one-die orrery satisfied BOTH tests -- it
	-- was kept by the sweep that had just destroyed its ViewportFrame (leaking a
	-- model pivoted every frame forever) and discarded by the other. Every new
	-- player hit this on their first look at the panel.
	--
	-- Parentage answers the question directly instead of inferring it. A
	-- destroyed ViewportFrame is out of the tree, so its children are too, and
	-- `IsDescendantOf(game)` is false for exactly the items that should go --
	-- regardless of which grid rebuilt, how many did, or what geometry they use.
	local function pruneDeadViewportItems()
		local live: { SlotsViewportItem } = {}
		for _, item in ipairs(slotsVpItems) do
			if item.model:IsDescendantOf(game) then
				table.insert(live, item)
			end
		end
		slotsVpItems = live
	end

	local function createOrreryChamber(parent: Instance, size: UDim2, shapeList: { string }, bg: Color3): ViewportFrame
		local vp = Instance.new("ViewportFrame")
		vp.Name = "ChamberOrreryViewport"
		vp.Size = size
		vp.BackgroundColor3 = bg
		vp.BackgroundTransparency = 0
		vp.BorderSizePixel = 0
		vp.Parent = parent

		local count = #shapeList
		if count == 0 then
			shapeList = { "D6" }
			count = 1
		end

		local folder = ReplicatedStorage:FindFirstChild(DICE_SOURCE)
		local orbitRadius = if count == 1 then 0 else math.clamp(2.8 + count * 0.22, 3.2, 4.8)
		local modelScale = if count == 1 then 0.72 else math.clamp(1.35 / math.sqrt(count), 0.44, 0.68)

		for idx, shapeId in ipairs(shapeList) do
			local source = if folder then folder:FindFirstChild(shapeId) else nil
			if source and source:IsA("Model") then
				local model = source:Clone()
				if model.PrimaryPart == nil then
					local pivot = model:FindFirstChild("Pivot")
					if pivot and pivot:IsA("BasePart") then
						model.PrimaryPart = pivot
					end
				end
				model:ScaleTo(modelScale)
				model.Parent = vp

				local stepAngle = (math.pi * 2) / count
				local baseAngle = (idx - 1) * stepAngle

				table.insert(slotsVpItems, {
					model = model,
					pivot = CFrame.new(0, 0, 0),
					rotSpeed = Vector3.new(0.6 + (idx % 3) * 0.25, 0.9 + (idx % 2) * 0.35, 0.4),
					baseHeight = 0,
					bobFreq = 1.2 + (idx % 3) * 0.2,
					bobAmp = if count == 1 then 0.16 else 0.20,
					orbitRadius = orbitRadius,
					orbitAngle = baseAngle,
					orbitSpeed = if count == 1 then 0 else 0.55,
					phase = idx * 1.1,
				})
			end
		end

		local cam = Instance.new("Camera")
		if count == 1 then
			cam.CFrame = CFrame.new(Vector3.new(2.8, 2.2, 3.4), Vector3.new(0, 0, 0))
			cam.FieldOfView = 36
		else
			cam.CFrame = CFrame.new(Vector3.new(0, 4.2 + count * 0.15, 9.4 + count * 0.35), Vector3.new(0, -0.2, 0))
			cam.FieldOfView = 45
		end
		cam.Parent = vp
		vp.CurrentCamera = cam

		return vp
	end

	local function createMiniDieViewport(parent: Instance, size: UDim2, shapeId: string, bg: Color3): ViewportFrame
		local vp = Instance.new("ViewportFrame")
		vp.Name = "MiniDieViewport_" .. shapeId
		vp.Size = size
		vp.BackgroundColor3 = bg
		vp.BackgroundTransparency = 1
		vp.BorderSizePixel = 0
		vp.Parent = parent

		local folder = ReplicatedStorage:FindFirstChild(DICE_SOURCE)
		local source = if folder then folder:FindFirstChild(shapeId) else nil
		if source and source:IsA("Model") then
			local model = source:Clone()
			if model.PrimaryPart == nil then
				local pivot = model:FindFirstChild("Pivot")
				if pivot and pivot:IsA("BasePart") then
					model.PrimaryPart = pivot
				end
			end

			local scaleFactor = (SLOTS_SPECIMEN_SCALE_MAP[shapeId] or 0.44) * 0.90
			model:ScaleTo(scaleFactor)
			model:PivotTo(CFrame.new(0, 0, 0))
			model.Parent = vp

			table.insert(slotsVpItems, {
				model = model,
				pivot = CFrame.new(0, 0, 0),
				rotSpeed = Vector3.new(0.5, 0.8, 0.3),
				baseHeight = 0,
				bobFreq = 1.0,
				bobAmp = 0.08,
				orbitRadius = 0,
				orbitAngle = 0,
				orbitSpeed = 0,
				phase = 0,
			})
		end

		local cam = Instance.new("Camera")
		cam.CFrame = CFrame.new(Vector3.new(2.2, 1.6, 2.8), Vector3.new(0, 0, 0))
		cam.FieldOfView = 36
		cam.Parent = vp
		vp.CurrentCamera = cam

		return vp
	end

	local function buildQuadrantShell(parent: Instance, name: string, size: UDim2, order: number, strokeColor: Color3, bgColor: Color3): Frame
		local shell = Instance.new("Frame")
		shell.Name = name
		shell.Size = size
		shell.BackgroundColor3 = bgColor
		shell.BorderSizePixel = 0
		shell.LayoutOrder = order
		shell.Parent = parent

		local sCorner = Instance.new("UICorner")
		sCorner.CornerRadius = UDim.new(0, 8)
		sCorner.Parent = shell

		local sStroke = Instance.new("UIStroke")
		sStroke.Color = strokeColor
		sStroke.Thickness = 1
		sStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		sStroke.Parent = shell

		local sPad = Instance.new("UIPadding")
		sPad.PaddingLeft = UDim.new(0, 10)
		sPad.PaddingRight = UDim.new(0, 10)
		sPad.PaddingTop = UDim.new(0, 8)
		sPad.PaddingBottom = UDim.new(0, 8)
		sPad.Parent = shell

		local sList = Instance.new("UIListLayout")
		sList.FillDirection = Enum.FillDirection.Vertical
		sList.SortOrder = Enum.SortOrder.LayoutOrder
		sList.Padding = UDim.new(0, 6)
		sList.Parent = shell

		return shell
	end

	local function buildSectionHeader(parent: Instance, title: string, rightTag: string?, accentColor: Color3): (Frame, TextLabel?)
		local hFrame = Instance.new("Frame")
		hFrame.Name = "SectionHeader"
		hFrame.Size = UDim2.new(1, 0, 0, 20)
		hFrame.BackgroundTransparency = 1
		hFrame.LayoutOrder = 1
		hFrame.Parent = parent

		local tLbl = Instance.new("TextLabel")
		tLbl.Size = UDim2.new(if rightTag then 0.50 else 1, 0, 1, 0)
		tLbl.BackgroundTransparency = 1
		tLbl.Text = title
		tLbl.TextColor3 = accentColor
		tLbl.Font = Enum.Font.GothamBold
		tLbl.TextSize = 12
		tLbl.TextXAlignment = Enum.TextXAlignment.Left
		tLbl.Parent = hFrame

		local rLbl: TextLabel? = nil
		if rightTag then
			rLbl = Instance.new("TextLabel")
			rLbl.Size = UDim2.new(0.50, 0, 1, 0)
			rLbl.Position = UDim2.new(0.50, 0, 0, 0)
			rLbl.BackgroundTransparency = 1
			rLbl.Text = rightTag
			rLbl.TextColor3 = THEME.TextMuted
			rLbl.Font = Enum.Font.Code
			rLbl.TextSize = 10
			rLbl.TextXAlignment = Enum.TextXAlignment.Right
			rLbl.Parent = hFrame
		end

		return hFrame, rLbl
	end

	local function createTraitEmblem(parent: Instance, emblemType: number, color: Color3): Frame
		local box = Instance.new("Frame")
		box.Name = "TraitEmblem"
		box.Size = UDim2.new(0, 28, 0, 28)
		box.BackgroundColor3 = THEME.InsetBg
		box.BorderSizePixel = 0
		box.Parent = parent

		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 6)
		bCorner.Parent = box

		local bStroke = Instance.new("UIStroke")
		bStroke.Color = color
		bStroke.Thickness = 1.2
		bStroke.Parent = box

		if emblemType == 1 then
			local f1 = Instance.new("Frame")
			f1.Size = UDim2.new(0, 12, 0, 12)
			f1.Position = UDim2.new(0.5, -6, 0.5, -6)
			f1.BackgroundColor3 = color
			f1.Rotation = 45
			f1.BorderSizePixel = 0
			f1.Parent = box
			local f1c = Instance.new("UICorner")
			f1c.CornerRadius = UDim.new(0, 2)
			f1c.Parent = f1
		else
			local r1 = Instance.new("Frame")
			r1.Size = UDim2.new(0, 14, 0, 14)
			r1.Position = UDim2.new(0.5, -7, 0.5, -7)
			r1.BackgroundTransparency = 1
			r1.Parent = box
			local r1s = Instance.new("UIStroke")
			r1s.Color = color
			r1s.Thickness = 2
			r1s.Parent = r1
			local r1c = Instance.new("UICorner")
			r1c.CornerRadius = UDim.new(1, 0)
			r1c.Parent = r1
		end

		return box
	end

	-- Master Quad Container
	local quadList = Instance.new("UIListLayout")
	quadList.FillDirection = Enum.FillDirection.Vertical
	quadList.SortOrder = Enum.SortOrder.LayoutOrder
	quadList.Padding = UDim.new(0, 8)
	quadList.Parent = bodyContainer

	-- State tracking for active slots & focus
	local currentSlotPage = 1
	local selectedSlotIndex = 1
	local selectedFocusedShape = "D6"
	-- NO `id` FIELD. There is none on the wire, and an array index living in a
	-- field called `id` is an invitation to send it somewhere that wants a real
	-- identifier. The die's identity IS its position: `liveEquippedDice[n]` is
	-- the die in slot n, exactly as `Profile.Dice[n]` is on the server.
	local liveEquippedDice: { { shape: string, mass: number } } = {
		{ shape = "D6", mass = 60 },
	}
	local unlockedSlotsCount = 1
	local ascensionsCount = 0

	-- TOP ROW (44% height)
	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.new(1, 0, 0.44, -4)
	topRow.BackgroundTransparency = 1
	topRow.LayoutOrder = 1
	topRow.Parent = bodyContainer

	local topList = Instance.new("UIListLayout")
	topList.FillDirection = Enum.FillDirection.Horizontal
	topList.SortOrder = Enum.SortOrder.LayoutOrder
	topList.Padding = UDim.new(0, 10)
	topList.Parent = topRow

	-- Top-Left: Preview (30%)
	local prevBox = buildQuadrantShell(topRow, "OrreryChamber", UDim2.new(0.30, -5, 1, 0), 1, THEME.StrokeSubtle, THEME.CardBg)
	buildSectionHeader(prevBox, "PREVIEW", nil, THEME.GoldPrimary)

	local pvFrame = Instance.new("Frame")
	pvFrame.Size = UDim2.new(1, 0, 1, -26)
	pvFrame.BackgroundColor3 = THEME.InsetBg
	pvFrame.BorderSizePixel = 0
	pvFrame.LayoutOrder = 2
	pvFrame.Parent = prevBox

	local pvCorner = Instance.new("UICorner")
	pvCorner.CornerRadius = UDim.new(0, 6)
	pvCorner.Parent = pvFrame

	local pvStroke = Instance.new("UIStroke")
	pvStroke.Color = THEME.StrokeSubtle
	pvStroke.Thickness = 1
	pvStroke.Parent = pvFrame

	local function rebuildOrreryChamber()
		for _, child in ipairs(pvFrame:GetChildren()) do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end

		pruneDeadViewportItems()

		local shapeList = {}
		for _, d in ipairs(liveEquippedDice) do
			table.insert(shapeList, d.shape)
		end
		if #shapeList == 0 then table.insert(shapeList, "D6") end

		createOrreryChamber(pvFrame, UDim2.fromScale(1, 1), shapeList, THEME.InsetBg)
	end

	rebuildOrreryChamber()

	-- Top-Right: 1x3 Showcase Slots (70%)
	local slotsBox = buildQuadrantShell(topRow, "ShowcaseSlots", UDim2.new(0.70, -5, 1, 0), 2, THEME.StrokeSubtle, THEME.CardBg)
	local _, pageTagLbl = buildSectionHeader(slotsBox, "ACTIVE SLOTS", "SLOTS 01 - 03  [PAGE 1/4]", THEME.GoldPrimary)

	local slotStrip = Instance.new("Frame")
	slotStrip.Size = UDim2.new(1, 0, 1, -26)
	slotStrip.BackgroundTransparency = 1
	slotStrip.LayoutOrder = 2
	slotStrip.Parent = slotsBox

	local ssList = Instance.new("UIListLayout")
	ssList.FillDirection = Enum.FillDirection.Horizontal
	ssList.SortOrder = Enum.SortOrder.LayoutOrder
	ssList.VerticalAlignment = Enum.VerticalAlignment.Center
	ssList.Padding = UDim.new(0, 8)
	ssList.Parent = slotStrip

	local lArrow = Instance.new("TextButton")
	lArrow.Size = UDim2.new(0, 28, 0.90, 0)
	lArrow.BackgroundColor3 = THEME.ButtonDark
	lArrow.BorderSizePixel = 0
	lArrow.Text = "<"
	lArrow.TextColor3 = THEME.GoldPrimary
	lArrow.Font = Enum.Font.GothamBlack
	lArrow.TextSize = 16
	lArrow.LayoutOrder = 1
	lArrow.Parent = slotStrip
	local laCorn = Instance.new("UICorner")
	laCorn.CornerRadius = UDim.new(0, 4)
	laCorn.Parent = lArrow
	local laStroke = Instance.new("UIStroke")
	laStroke.Color = THEME.StrokeSubtle
	laStroke.Thickness = 1
	laStroke.Parent = lArrow

	local sGrid = Instance.new("Frame")
	sGrid.Size = UDim2.new(1, -72, 1, 0)
	sGrid.BackgroundTransparency = 1
	sGrid.LayoutOrder = 2
	sGrid.Parent = slotStrip

	local sgl = Instance.new("UIGridLayout")
	sgl.CellSize = UDim2.new(0.3333, -6, 1, 0)
	sgl.CellPadding = UDim2.new(0, 8, 0, 0)
	sgl.SortOrder = Enum.SortOrder.LayoutOrder
	sgl.Parent = sGrid

	local rArrow = Instance.new("TextButton")
	rArrow.Size = UDim2.new(0, 28, 0.90, 0)
	rArrow.BackgroundColor3 = THEME.ButtonDark
	rArrow.BorderSizePixel = 0
	rArrow.Text = ">"
	rArrow.TextColor3 = THEME.GoldPrimary
	rArrow.Font = Enum.Font.GothamBlack
	rArrow.TextSize = 16
	rArrow.LayoutOrder = 3
	rArrow.Parent = slotStrip
	local raCorn = Instance.new("UICorner")
	raCorn.CornerRadius = UDim.new(0, 4)
	raCorn.Parent = rArrow
	local raStroke = Instance.new("UIStroke")
	raStroke.Color = THEME.StrokeSubtle
	raStroke.Thickness = 1
	raStroke.Parent = rArrow

	-- BOTTOM ROW (56% height)
	local botRow = Instance.new("Frame")
	botRow.Name = "BottomRow"
	botRow.Size = UDim2.new(1, 0, 0.56, -4)
	botRow.BackgroundTransparency = 1
	botRow.LayoutOrder = 2
	botRow.Parent = bodyContainer

	local botList = Instance.new("UIListLayout")
	botList.FillDirection = Enum.FillDirection.Horizontal
	botList.SortOrder = Enum.SortOrder.LayoutOrder
	botList.Padding = UDim.new(0, 10)
	botList.Parent = botRow

	-- Bottom-Left: 3x2 Inventory (40%)
	local invBox = buildQuadrantShell(botRow, "Inventory", UDim2.new(0.40, -5, 1, 0), 1, THEME.StrokeSubtle, THEME.CardBg)
	buildSectionHeader(invBox, "INVENTORY", "SELECT DIE TO EQUIP", THEME.GoldPrimary)

	local igFrame = Instance.new("Frame")
	igFrame.Size = UDim2.new(1, 0, 1, -26)
	igFrame.BackgroundTransparency = 1
	igFrame.LayoutOrder = 2
	igFrame.Parent = invBox

	local igl = Instance.new("UIGridLayout")
	igl.CellSize = UDim2.new(0.3333, -6, 0.50, -4)
	igl.CellPadding = UDim2.new(0, 8, 0, 8)
	igl.SortOrder = Enum.SortOrder.LayoutOrder
	igl.Parent = igFrame

	-- Bottom-Right: Trait Forge & Shards (60%)
	local traitsBox = buildQuadrantShell(botRow, "TraitsSection", UDim2.new(0.60, -5, 1, 0), 2, THEME.StrokeSubtle, THEME.CardBg)
	-- NOT IMPLEMENTED. Traits and shards exist nowhere in this project -- not
	-- in the profile, not in any catalog, not on the server. The visual design
	-- is kept because it is worth building against later, but every figure it
	-- once displayed was invented, so the header says so and the controls below
	-- are inert rather than pretending to spend a currency that does not exist.
	buildSectionHeader(traitsBox, "TRAIT FORGE & SHARDS", "COMING SOON", THEME.TextMuted)

	local tBody = Instance.new("Frame")
	tBody.Size = UDim2.new(1, 0, 1, -26)
	tBody.BackgroundTransparency = 1
	tBody.LayoutOrder = 2
	tBody.Parent = traitsBox

	local tbl = Instance.new("UIListLayout")
	tbl.FillDirection = Enum.FillDirection.Horizontal
	tbl.SortOrder = Enum.SortOrder.LayoutOrder
	tbl.Padding = UDim.new(0, 8)
	tbl.Parent = tBody

	-- Left Sub-Panel (38%): Focused Die Preview + Boost 1 & 2 + Shards & Reroll Button
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftCol"
	leftCol.Size = UDim2.new(0.38, -4, 1, 0)
	leftCol.BackgroundTransparency = 1
	leftCol.LayoutOrder = 1
	leftCol.Parent = tBody

	local lcl = Instance.new("UIListLayout")
	lcl.FillDirection = Enum.FillDirection.Vertical
	lcl.SortOrder = Enum.SortOrder.LayoutOrder
	lcl.Padding = UDim.new(0, 4)
	lcl.Parent = leftCol

	-- Top Focused Die Box (40% height)
	local dieBox = Instance.new("Frame")
	dieBox.Name = "DieReceptacle"
	dieBox.Size = UDim2.new(1, 0, 0.40, -3)
	dieBox.BackgroundColor3 = THEME.InsetBg
	dieBox.BorderSizePixel = 0
	dieBox.LayoutOrder = 1
	dieBox.Parent = leftCol

	local dbc = Instance.new("UICorner")
	dbc.CornerRadius = UDim.new(0, 6)
	dbc.Parent = dieBox

	local dbs = Instance.new("UIStroke")
	dbs.Color = THEME.StrokeSubtle
	dbs.Thickness = 1
	dbs.Parent = dieBox

	local focusedDieVpContainer = Instance.new("Frame")
	focusedDieVpContainer.Size = UDim2.fromScale(1, 1)
	focusedDieVpContainer.BackgroundTransparency = 1
	focusedDieVpContainer.Parent = dieBox

	local focusedDieTag = Instance.new("TextLabel")
	focusedDieTag.Size = UDim2.new(0.72, 0, 0, 16)
	focusedDieTag.Position = UDim2.new(0, 8, 0, 4)
	focusedDieTag.BackgroundTransparency = 1
	focusedDieTag.Text = SLOTS_CANONICAL_NAMES[selectedFocusedShape] or "FOUNDRY OBSIDIAN"
	focusedDieTag.TextColor3 = THEME.GoldPrimary
	focusedDieTag.Font = Enum.Font.GothamBlack
	focusedDieTag.TextSize = 10
	focusedDieTag.TextXAlignment = Enum.TextXAlignment.Left
	focusedDieTag.Parent = dieBox

	local infoBtn = Instance.new("TextButton")
	infoBtn.Name = "InfoBtn"
	infoBtn.Size = UDim2.new(0, 18, 0, 18)
	infoBtn.Position = UDim2.new(1, -24, 0, 4)
	infoBtn.BackgroundColor3 = THEME.ButtonDark
	infoBtn.BorderSizePixel = 0
	infoBtn.Text = ""
	infoBtn.AutoButtonColor = true
	infoBtn.Parent = dieBox

	local ibc = Instance.new("UICorner")
	ibc.CornerRadius = UDim.new(1, 0)
	ibc.Parent = infoBtn

	local ibs = Instance.new("UIStroke")
	ibs.Color = THEME.StrokeGold
	ibs.Thickness = 1
	ibs.Parent = infoBtn

	local iDot = Instance.new("Frame")
	iDot.Size = UDim2.new(0, 2, 0, 2)
	iDot.Position = UDim2.new(0.5, -1, 0, 3)
	iDot.BackgroundColor3 = THEME.GoldPrimary
	iDot.BorderSizePixel = 0
	iDot.Parent = infoBtn

	local iStem = Instance.new("Frame")
	iStem.Size = UDim2.new(0, 2, 0, 7)
	iStem.Position = UDim2.new(0.5, -1, 0, 7)
	iStem.BackgroundColor3 = THEME.GoldPrimary
	iStem.BorderSizePixel = 0
	iStem.Parent = infoBtn

	-- Middle: Boost 1 & Boost 2 Row (22% height)
	local boostRow = Instance.new("Frame")
	boostRow.Name = "BoostRow"
	boostRow.Size = UDim2.new(1, 0, 0.22, -2)
	boostRow.BackgroundTransparency = 1
	boostRow.LayoutOrder = 2
	boostRow.Parent = leftCol

	local brList = Instance.new("UIListLayout")
	brList.FillDirection = Enum.FillDirection.Horizontal
	brList.SortOrder = Enum.SortOrder.LayoutOrder
	brList.Padding = UDim.new(0, 4)
	brList.Parent = boostRow

	-- Mutes a control that has no implementation behind it, so it cannot be
	-- mistaken for a working one: no hover response, no click target, and the
	-- dead palette every other disabled control in this file uses.
	local function setTraitControlInert(btn: TextButton)
		btn.Active = false
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = THEME.ButtonDark
		btn.TextColor3 = THEME.TextMuted
	end

	local function makeBoostCard(order: number, nameText: string, valText: string, tagColor: Color3)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0.50, -2, 1, 0)
		card.BackgroundColor3 = THEME.InsetBg
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.Parent = boostRow

		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 6)
		bCorner.Parent = card

		local bStroke = Instance.new("UIStroke")
		bStroke.Color = THEME.StrokeSubtle
		bStroke.Thickness = 1
		bStroke.Parent = card

		local bPad = Instance.new("UIPadding")
		bPad.PaddingLeft = UDim.new(0, 4)
		bPad.PaddingRight = UDim.new(0, 4)
		bPad.Parent = card

		local bList = Instance.new("UIListLayout")
		bList.FillDirection = Enum.FillDirection.Vertical
		bList.SortOrder = Enum.SortOrder.LayoutOrder
		bList.VerticalAlignment = Enum.VerticalAlignment.Center
		bList.Parent = card

		local tag = Instance.new("TextLabel")
		tag.Size = UDim2.new(1, 0, 0, 12)
		tag.BackgroundTransparency = 1
		tag.Text = nameText
		tag.TextColor3 = tagColor
		tag.Font = Enum.Font.GothamBlack
		tag.TextSize = 8.5
		tag.Parent = card

		local val = Instance.new("TextLabel")
		val.Size = UDim2.new(1, 0, 0, 14)
		val.BackgroundTransparency = 1
		val.Text = valText
		val.TextColor3 = THEME.TextPrimary
		val.Font = Enum.Font.GothamBold
		val.TextSize = 9.5
		val.Parent = card
	end

	makeBoostCard(1, "BOOST 1", "+65% VELOCITY", THEME.GoldPrimary)
	makeBoostCard(2, "BOOST 2", "-40% VOID", THEME.AmberFlame)

	-- Bottom: Number of Shards + Reroll Trait Button (38% height)
	local shardDeck = Instance.new("Frame")
	shardDeck.Name = "ShardDeck"
	shardDeck.Size = UDim2.new(1, 0, 0.38, -2)
	shardDeck.BackgroundColor3 = THEME.InsetBg
	shardDeck.BorderSizePixel = 0
	shardDeck.LayoutOrder = 3
	shardDeck.Parent = leftCol

	local sdc = Instance.new("UICorner")
	sdc.CornerRadius = UDim.new(0, 6)
	sdc.Parent = shardDeck

	local sds = Instance.new("UIStroke")
	sds.Color = THEME.StrokeSubtle
	sds.Thickness = 1
	sds.Parent = shardDeck

	local sPad = Instance.new("UIPadding")
	sPad.PaddingLeft = UDim.new(0, 6)
	sPad.PaddingRight = UDim.new(0, 6)
	sPad.PaddingTop = UDim.new(0, 4)
	sPad.PaddingBottom = UDim.new(0, 4)
	sPad.Parent = shardDeck

	local sList = Instance.new("UIListLayout")
	sList.FillDirection = Enum.FillDirection.Vertical
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.VerticalAlignment = Enum.VerticalAlignment.Center
	sList.Padding = UDim.new(0, 4)
	sList.Parent = shardDeck

	local countPill = Instance.new("Frame")
	countPill.Size = UDim2.new(1, 0, 0, 20)
	countPill.BackgroundTransparency = 1
	countPill.LayoutOrder = 1
	countPill.Parent = shardDeck

	local shardValLbl = Instance.new("TextLabel")
	shardValLbl.Size = UDim2.new(0.60, 0, 1, 0)
	shardValLbl.BackgroundTransparency = 1
	shardValLbl.Text = "◆ -- SHARDS"
	shardValLbl.TextColor3 = THEME.GoldPrimary
	shardValLbl.Font = Enum.Font.GothamBlack
	shardValLbl.TextSize = 10
	shardValLbl.TextXAlignment = Enum.TextXAlignment.Left
	shardValLbl.Parent = countPill

	local costTagLbl = Instance.new("TextLabel")
	costTagLbl.Size = UDim2.new(0.40, 0, 1, 0)
	costTagLbl.Position = UDim2.new(0.60, 0, 0, 0)
	costTagLbl.BackgroundTransparency = 1
	costTagLbl.Text = "COST: --"
	costTagLbl.TextColor3 = THEME.TextMuted
	costTagLbl.Font = Enum.Font.Code
	costTagLbl.TextSize = 9
	costTagLbl.TextXAlignment = Enum.TextXAlignment.Right
	costTagLbl.Parent = countPill

	local rollBtn = Instance.new("TextButton")
	rollBtn.Name = "RollButton"
	rollBtn.Size = UDim2.new(1, 0, 0, 28)
	rollBtn.BackgroundColor3 = THEME.GoldPrimary
	rollBtn.BorderSizePixel = 0
	rollBtn.Text = "REROLL TRAITS"
	rollBtn.TextColor3 = THEME.TextDark
	rollBtn.Font = Enum.Font.GothamBlack
	rollBtn.TextSize = 11
	rollBtn.LayoutOrder = 2
	rollBtn.Parent = shardDeck

	local rbc = Instance.new("UICorner")
	rbc.CornerRadius = UDim.new(0, 5)
	rbc.Parent = rollBtn

	-- The handler here decremented the shard label from 145 to 135 and did
	-- nothing else -- no server call, no persistence, and it would keep
	-- "charging" forever. Deleted rather than replaced: a control that
	-- fabricates a transaction is worse than an inert one.
	setTraitControlInert(rollBtn)

	-- Right Sub-Panel (62%): Dual-Trait Results
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightResultCol"
	rightCol.Size = UDim2.new(0.62, -4, 1, 0)
	rightCol.BackgroundColor3 = THEME.InsetBg
	rightCol.BorderSizePixel = 0
	rightCol.LayoutOrder = 2
	rightCol.Parent = tBody

	local rcCorner = Instance.new("UICorner")
	rcCorner.CornerRadius = UDim.new(0, 8)
	rcCorner.Parent = rightCol

	local rcStroke = Instance.new("UIStroke")
	rcStroke.Color = THEME.StrokeSubtle
	rcStroke.Thickness = 1
	rcStroke.Parent = rightCol

	local rPad = Instance.new("UIPadding")
	rPad.PaddingLeft = UDim.new(0, 8)
	rPad.PaddingRight = UDim.new(0, 8)
	rPad.PaddingTop = UDim.new(0, 6)
	rPad.PaddingBottom = UDim.new(0, 6)
	rPad.Parent = rightCol

	local rList = Instance.new("UIListLayout")
	rList.FillDirection = Enum.FillDirection.Vertical
	rList.SortOrder = Enum.SortOrder.LayoutOrder
	rList.Padding = UDim.new(0, 6)
	rList.Parent = rightCol

	-- Trait Slot 1 Container (42% height)
	local t1Container = Instance.new("Frame")
	t1Container.Name = "Trait1_Container"
	t1Container.Size = UDim2.new(1, 0, 0.42, -4)
	t1Container.BackgroundColor3 = THEME.CardBg
	t1Container.BorderSizePixel = 0
	t1Container.LayoutOrder = 1
	t1Container.Parent = rightCol

	local t1c = Instance.new("UICorner")
	t1c.CornerRadius = UDim.new(0, 6)
	t1c.Parent = t1Container

	local t1s = Instance.new("UIStroke")
	t1s.Color = THEME.StrokeSubtle
	t1s.Thickness = 1
	t1s.Parent = t1Container

	local t1Pad = Instance.new("UIPadding")
	t1Pad.PaddingLeft = UDim.new(0, 8)
	t1Pad.PaddingRight = UDim.new(0, 8)
	t1Pad.PaddingTop = UDim.new(0, 6)
	t1Pad.PaddingBottom = UDim.new(0, 6)
	t1Pad.Parent = t1Container

	local t1List = Instance.new("UIListLayout")
	t1List.FillDirection = Enum.FillDirection.Vertical
	t1List.SortOrder = Enum.SortOrder.LayoutOrder
	t1List.Padding = UDim.new(0, 3)
	t1List.Parent = t1Container

	local t1Head = Instance.new("Frame")
	t1Head.Size = UDim2.new(1, 0, 0, 20)
	t1Head.BackgroundTransparency = 1
	t1Head.LayoutOrder = 1
	t1Head.Parent = t1Container

	local t1hList = Instance.new("UIListLayout")
	t1hList.FillDirection = Enum.FillDirection.Horizontal
	t1hList.SortOrder = Enum.SortOrder.LayoutOrder
	t1hList.VerticalAlignment = Enum.VerticalAlignment.Center
	t1hList.Padding = UDim.new(0, 6)
	t1hList.Parent = t1Head

	createTraitEmblem(t1Head, 1, THEME.GoldPrimary)

	local t1Title = Instance.new("TextLabel")
	t1Title.Size = UDim2.new(1, -110, 1, 0)
	t1Title.BackgroundTransparency = 1
	t1Title.Text = "TRAIT 1: PYRO RESONANCE"
	t1Title.TextColor3 = THEME.TextPrimary
	t1Title.Font = Enum.Font.GothamBlack
	t1Title.TextSize = 10.5
	t1Title.TextTruncate = Enum.TextTruncate.AtEnd
	t1Title.TextXAlignment = Enum.TextXAlignment.Left
	t1Title.LayoutOrder = 2
	t1Title.Parent = t1Head

	local t1Flex = Instance.new("UIFlexItem")
	t1Flex.FlexMode = Enum.UIFlexMode.Fill
	t1Flex.Parent = t1Title

	local t1Rarity = Instance.new("TextLabel")
	t1Rarity.Size = UDim2.new(0, 80, 1, 0)
	t1Rarity.BackgroundTransparency = 1
	t1Rarity.Text = "LEGENDARY"
	t1Rarity.TextColor3 = THEME.GoldPrimary
	t1Rarity.Font = Enum.Font.GothamBlack
	t1Rarity.TextSize = 9.5
	t1Rarity.TextXAlignment = Enum.TextXAlignment.Right
	t1Rarity.LayoutOrder = 3
	t1Rarity.Parent = t1Head

	local t1Desc = Instance.new("TextLabel")
	t1Desc.Size = UDim2.new(1, 0, 1, -24)
	t1Desc.BackgroundTransparency = 1
	t1Desc.Text = "Supercharges adjacent dice in orrery throw for +1.5x face value with +65% kinetic velocity."
	t1Desc.TextColor3 = THEME.TextPrimary
	t1Desc.Font = Enum.Font.GothamMedium
	t1Desc.TextSize = 10
	t1Desc.TextWrapped = true
	t1Desc.TextYAlignment = Enum.TextYAlignment.Top
	t1Desc.TextXAlignment = Enum.TextXAlignment.Left
	t1Desc.LayoutOrder = 2
	t1Desc.Parent = t1Container

	-- Trait Slot 2 Container (42% height)
	local t2Container = Instance.new("Frame")
	t2Container.Name = "Trait2_Container"
	t2Container.Size = UDim2.new(1, 0, 0.42, -4)
	t2Container.BackgroundColor3 = THEME.CardBg
	t2Container.BorderSizePixel = 0
	t2Container.LayoutOrder = 2
	t2Container.Parent = rightCol

	local t2c = Instance.new("UICorner")
	t2c.CornerRadius = UDim.new(0, 6)
	t2c.Parent = t2Container

	local t2s = Instance.new("UIStroke")
	t2s.Color = THEME.StrokeSubtle
	t2s.Thickness = 1
	t2s.Parent = t2Container

	local t2Pad = Instance.new("UIPadding")
	t2Pad.PaddingLeft = UDim.new(0, 8)
	t2Pad.PaddingRight = UDim.new(0, 8)
	t2Pad.PaddingTop = UDim.new(0, 6)
	t2Pad.PaddingBottom = UDim.new(0, 6)
	t2Pad.Parent = t2Container

	local t2List = Instance.new("UIListLayout")
	t2List.FillDirection = Enum.FillDirection.Vertical
	t2List.SortOrder = Enum.SortOrder.LayoutOrder
	t2List.Padding = UDim.new(0, 3)
	t2List.Parent = t2Container

	local t2Head = Instance.new("Frame")
	t2Head.Size = UDim2.new(1, 0, 0, 20)
	t2Head.BackgroundTransparency = 1
	t2Head.LayoutOrder = 1
	t2Head.Parent = t2Container

	local t2hList = Instance.new("UIListLayout")
	t2hList.FillDirection = Enum.FillDirection.Horizontal
	t2hList.SortOrder = Enum.SortOrder.LayoutOrder
	t2hList.VerticalAlignment = Enum.VerticalAlignment.Center
	t2hList.Padding = UDim.new(0, 6)
	t2hList.Parent = t2Head

	createTraitEmblem(t2Head, 2, THEME.AmberFlame)

	local t2Title = Instance.new("TextLabel")
	t2Title.Size = UDim2.new(1, -110, 1, 0)
	t2Title.BackgroundTransparency = 1
	t2Title.Text = "TRAIT 2: VOID SHIELD"
	t2Title.TextColor3 = THEME.TextPrimary
	t2Title.Font = Enum.Font.GothamBlack
	t2Title.TextSize = 10.5
	t2Title.TextTruncate = Enum.TextTruncate.AtEnd
	t2Title.TextXAlignment = Enum.TextXAlignment.Left
	t2Title.LayoutOrder = 2
	t2Title.Parent = t2Head

	local t2Flex = Instance.new("UIFlexItem")
	t2Flex.FlexMode = Enum.UIFlexMode.Fill
	t2Flex.Parent = t2Title

	local t2Rarity = Instance.new("TextLabel")
	t2Rarity.Size = UDim2.new(0, 80, 1, 0)
	t2Rarity.BackgroundTransparency = 1
	t2Rarity.Text = "EPIC (PROC)"
	t2Rarity.TextColor3 = THEME.AmberFlame
	t2Rarity.Font = Enum.Font.GothamBlack
	t2Rarity.TextSize = 9.5
	t2Rarity.TextXAlignment = Enum.TextXAlignment.Right
	t2Rarity.LayoutOrder = 3
	t2Rarity.Parent = t2Head

	local t2Desc = Instance.new("TextLabel")
	t2Desc.Size = UDim2.new(1, 0, 1, -24)
	t2Desc.BackgroundTransparency = 1
	t2Desc.Text = "Dampens void hazard penalties by 40% and converts absorbed kinetic impact into bonus multipliers."
	t2Desc.TextColor3 = THEME.TextPrimary
	t2Desc.Font = Enum.Font.GothamMedium
	t2Desc.TextSize = 10
	t2Desc.TextWrapped = true
	t2Desc.TextYAlignment = Enum.TextYAlignment.Top
	t2Desc.TextXAlignment = Enum.TextXAlignment.Left
	t2Desc.LayoutOrder = 2
	t2Desc.Parent = t2Container

	-- Action Controls (32px height)
	local actFooter = Instance.new("Frame")
	actFooter.Size = UDim2.new(1, 0, 0, 32)
	actFooter.BackgroundTransparency = 1
	actFooter.LayoutOrder = 3
	actFooter.Parent = rightCol

	local afl = Instance.new("UIListLayout")
	afl.FillDirection = Enum.FillDirection.Horizontal
	afl.SortOrder = Enum.SortOrder.LayoutOrder
	afl.Padding = UDim.new(0, 6)
	afl.Parent = actFooter

	local keepBtn = Instance.new("TextButton")
	keepBtn.Name = "KeepButton"
	keepBtn.Size = UDim2.new(0.50, -3, 1, 0)
	keepBtn.BackgroundColor3 = THEME.ButtonDark
	keepBtn.BorderSizePixel = 0
	keepBtn.Text = "KEEP TRAITS"
	keepBtn.TextColor3 = THEME.GoldPrimary
	keepBtn.Font = Enum.Font.GothamBold
	keepBtn.TextSize = 11
	keepBtn.LayoutOrder = 1
	keepBtn.Parent = actFooter
	local kbc = Instance.new("UICorner")
	kbc.CornerRadius = UDim.new(0, 6)
	kbc.Parent = keepBtn
	local kbStroke = Instance.new("UIStroke")
	kbStroke.Color = THEME.StrokeSubtle
	kbStroke.Thickness = 1
	kbStroke.Parent = keepBtn

	local rerollAllBtn = Instance.new("TextButton")
	rerollAllBtn.Name = "RerollAllButton"
	rerollAllBtn.Size = UDim2.new(0.50, -3, 1, 0)
	rerollAllBtn.BackgroundColor3 = THEME.GoldPrimary
	rerollAllBtn.BorderSizePixel = 0
	rerollAllBtn.Text = "REROLL ALL"
	rerollAllBtn.TextColor3 = THEME.TextDark
	rerollAllBtn.Font = Enum.Font.GothamBlack
	rerollAllBtn.TextSize = 11
	rerollAllBtn.LayoutOrder = 2
	rerollAllBtn.Parent = actFooter
	-- Both footer controls belong to the same unimplemented section as the
	-- reroll button above, so neither may look actionable.
	setTraitControlInert(keepBtn)
	setTraitControlInert(rerollAllBtn)

	local rrc = Instance.new("UICorner")
	rrc.CornerRadius = UDim.new(0, 6)
	rrc.Parent = rerollAllBtn

	local function updateFocusedDie(shapeId: string)
		selectedFocusedShape = shapeId
		focusedDieTag.Text = SLOTS_CANONICAL_NAMES[shapeId] or shapeId

		for _, child in ipairs(focusedDieVpContainer:GetChildren()) do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end

		pruneDeadViewportItems()

		createMiniDieViewport(focusedDieVpContainer, UDim2.fromScale(1, 1), shapeId, THEME.InsetBg)
	end

	updateFocusedDie("D6")

	local rebuildShowcaseSlots: () -> ()
	local rebuildInventory: (any) -> ()

	rebuildShowcaseSlots = function()
		for _, child in ipairs(sGrid:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local startIdx = (currentSlotPage - 1) * 3 + 1
		for i = 1, 3 do
			local slotNum = startIdx + i - 1
			local dieInfo = liveEquippedDice[slotNum]
			local isUnlocked = slotNum <= unlockedSlotsCount
			local isSelected = (slotNum == selectedSlotIndex)

			local bay = Instance.new("Frame")
			bay.Name = "SlotBay_" .. slotNum
			bay.BackgroundColor3 = if isSelected then THEME.InsetBg else THEME.CardBg
			bay.BorderSizePixel = 0
			bay.LayoutOrder = i
			bay.Parent = sGrid

			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 6)
			bc.Parent = bay

			local bs = Instance.new("UIStroke")
			bs.Thickness = if isSelected then 2 else 1
			bs.Color = if isSelected then THEME.GoldPrimary elseif isUnlocked then THEME.StrokeGold else THEME.StrokeSubtle
			bs.Parent = bay

			if isUnlocked and dieInfo then
				local vpBox = Instance.new("Frame")
				vpBox.Size = UDim2.new(1, 0, 0.52, 0)
				vpBox.BackgroundTransparency = 1
				vpBox.Parent = bay
				createMiniDieViewport(vpBox, UDim2.fromScale(1, 1), dieInfo.shape, THEME.InsetBg)

				local bTitle = Instance.new("TextLabel")
				bTitle.Size = UDim2.new(1, 0, 0, 16)
				bTitle.Position = UDim2.new(0, 0, 0.54, 0)
				bTitle.BackgroundTransparency = 1
				bTitle.Text = string.format("SLOT %02d: %s", slotNum, dieInfo.shape)
				bTitle.TextColor3 = THEME.GoldPrimary
				bTitle.Font = Enum.Font.GothamBold
				bTitle.TextSize = 9.5
				bTitle.Parent = bay

				local bSub = Instance.new("TextLabel")
				bSub.Size = UDim2.new(1, 0, 0, 14)
				bSub.Position = UDim2.new(0, 0, 0.74, 0)
				bSub.BackgroundTransparency = 1
				bSub.Text = "EQUIPPED"
				bSub.TextColor3 = THEME.Positive
				bSub.Font = Enum.Font.Code
				bSub.TextSize = 8.5
				bSub.Parent = bay
			elseif isUnlocked then
				local bTitle = Instance.new("TextLabel")
				bTitle.Size = UDim2.new(1, 0, 0, 16)
				bTitle.Position = UDim2.new(0, 0, 0.42, 0)
				bTitle.BackgroundTransparency = 1
				bTitle.Text = string.format("SLOT %02d (EMPTY)", slotNum)
				bTitle.TextColor3 = THEME.TextMuted
				bTitle.Font = Enum.Font.GothamBold
				bTitle.TextSize = 9
				bTitle.Parent = bay
			else
				-- `dieSlotCost` RETURNS `number?`. It answers nil at the
				-- ascension cap, meaning "there is no next slot to price" --
				-- and this compared that nil with `>`, which throws. Reachable
				-- simply by paging right: at zero ascensions the cap is 3, so
				-- slot 4 onward returns nil the first time the player looks.
				--
				-- Nil is not "locked". Locked implies a price the player has
				-- not met; at the cap no amount of cash opens this bay, so it
				-- names the thing that actually would.
				local nextCost = DiceCatalog.dieSlotCost(slotNum - 1, ascensionsCount)
				local costStr = if nextCost ~= nil and nextCost > 0
					then "$" .. Format.formatNumber(nextCost)
					else "ASCEND TO UNLOCK"

				local lockedLbl = Instance.new("TextLabel")
				lockedLbl.Size = UDim2.new(1, 0, 0, 16)
				lockedLbl.Position = UDim2.new(0, 0, 0.38, 0)
				lockedLbl.BackgroundTransparency = 1
				lockedLbl.Text = "[ LOCKED ]"
				lockedLbl.TextColor3 = THEME.TextMuted
				lockedLbl.Font = Enum.Font.Code
				lockedLbl.TextSize = 9.5
				lockedLbl.Parent = bay

				local bTitle = Instance.new("TextLabel")
				bTitle.Size = UDim2.new(1, 0, 0, 14)
				bTitle.Position = UDim2.new(0, 0, 0.58, 0)
				bTitle.BackgroundTransparency = 1
				bTitle.Text = string.format("SLOT %02d", slotNum)
				bTitle.TextColor3 = THEME.TextMuted
				bTitle.Font = Enum.Font.GothamBold
				bTitle.TextSize = 9
				bTitle.Parent = bay

				local costLbl = Instance.new("TextLabel")
				costLbl.Size = UDim2.new(1, 0, 0, 14)
				costLbl.Position = UDim2.new(0, 0, 0.76, 0)
				costLbl.BackgroundTransparency = 1
				costLbl.Text = costStr
				costLbl.TextColor3 = THEME.GoldBurnish
				costLbl.Font = Enum.Font.Code
				costLbl.TextSize = 9
				costLbl.Parent = bay
			end

			local clickBtn = Instance.new("TextButton")
			clickBtn.Size = UDim2.fromScale(1, 1)
			clickBtn.BackgroundTransparency = 1
			clickBtn.Text = ""
			clickBtn.Parent = bay

			clickBtn.MouseButton1Click:Connect(function()
				selectedSlotIndex = slotNum
				if dieInfo then
					updateFocusedDie(dieInfo.shape)
				end
				rebuildShowcaseSlots()
			end)
		end

		if pageTagLbl then
			local endIdx = math.min(startIdx + 2, 12)
			pageTagLbl.Text = string.format("SLOTS %02d - %02d  [PAGE %d/4]", startIdx, endIdx, currentSlotPage)
		end
	end

	lArrow.MouseButton1Click:Connect(function()
		if currentSlotPage > 1 then
			currentSlotPage -= 1
			rebuildShowcaseSlots()
		end
	end)

	rArrow.MouseButton1Click:Connect(function()
		if currentSlotPage < 4 then
			currentSlotPage += 1
			rebuildShowcaseSlots()
		end
	end)

	rebuildInventory = function(state: any)
		for _, child in ipairs(igFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local ownedShapeCounts: { [string]: number } = {}
		for _, d in ipairs(liveEquippedDice) do
			ownedShapeCounts[d.shape] = (ownedShapeCounts[d.shape] or 0) + 1
		end
		if type(state) == "table" and type(state.diamondTree) == "table" and type(state.diamondTree.Shapes) == "table" then
			for shapeId, unlocked in pairs(state.diamondTree.Shapes) do
				if unlocked == true and not ownedShapeCounts[shapeId] then
					ownedShapeCounts[shapeId] = 1
				end
			end
		end
		if not next(ownedShapeCounts) then
			ownedShapeCounts["D6"] = 1
		end

		local invList: { { shape: string, count: number } } = {}
		for sId, count in pairs(ownedShapeCounts) do
			table.insert(invList, { shape = sId, count = count })
		end
		table.sort(invList, function(a, b)
			local order = { D2=1, D3=2, D4=3, D5=4, D6=5, D7=6, D8=7, D10=8, D12=9, D14=10, D16=11, D20=12 }
			return (order[a.shape] or 99) < (order[b.shape] or 99)
		end)

		for idx = 1, 6 do
			local item = invList[idx]
			if not item then break end

			local isSelected = (item.shape == selectedFocusedShape)

			local c = Instance.new("Frame")
			c.Name = "InvCard_" .. idx
			c.LayoutOrder = idx
			c.BackgroundColor3 = THEME.InsetBg
			c.BorderSizePixel = 0
			c.ClipsDescendants = true
			c.Parent = igFrame

			local cc = Instance.new("UICorner")
			cc.CornerRadius = UDim.new(0, 6)
			cc.Parent = c

			local cs = Instance.new("UIStroke")
			cs.Thickness = if isSelected then 2 else 1
			cs.Color = if isSelected then THEME.GoldPrimary else THEME.StrokeSubtle
			cs.Parent = c

			createMiniDieViewport(c, UDim2.fromScale(1, 1), item.shape, THEME.InsetBg)

			if item.count > 1 then
				local badge = Instance.new("TextLabel")
				badge.Size = UDim2.new(0, 24, 0, 15)
				badge.Position = UDim2.new(1, -26, 0, 2)
				badge.BackgroundColor3 = THEME.ModalBg
				badge.BorderSizePixel = 0
				badge.Text = "x" .. item.count
				badge.TextColor3 = THEME.GoldPrimary
				badge.Font = Enum.Font.Code
				badge.TextSize = 9.5
				badge.Parent = c

				local bc = Instance.new("UICorner")
				bc.CornerRadius = UDim.new(0, 4)
				bc.Parent = badge

				local bs = Instance.new("UIStroke")
				bs.Color = THEME.StrokeGold
				bs.Thickness = 1
				bs.Parent = badge
			end

			if isSelected then
				local selPill = Instance.new("TextLabel")
				selPill.Size = UDim2.new(1, 0, 0, 14)
				selPill.Position = UDim2.new(0, 0, 1, -14)
				selPill.BackgroundColor3 = THEME.GoldPrimary
				selPill.BorderSizePixel = 0
				selPill.Text = "Selected"
				selPill.TextColor3 = THEME.TextDark
				selPill.Font = Enum.Font.GothamBlack
				selPill.TextSize = 8.5
				selPill.Parent = c
			end

			local invBtn = Instance.new("TextButton")
			invBtn.Size = UDim2.fromScale(1, 1)
			invBtn.BackgroundTransparency = 1
			invBtn.Text = ""
			invBtn.Parent = c

			invBtn.MouseButton1Click:Connect(function()
				updateFocusedDie(item.shape)
				rebuildInventory(state)
			end)
		end
	end

	-- Master turntable render loop
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function(dt: number)
		if not slotsOverlay.Visible then return end
		animElapsed += dt

		for _, item in ipairs(slotsVpItems) do
			if item.model and item.model.PrimaryPart then
				if item.orbitRadius == 0 then
					local rot = CFrame.Angles(animElapsed * item.rotSpeed.X, animElapsed * item.rotSpeed.Y, animElapsed * item.rotSpeed.Z)
					local bob = math.sin(animElapsed * item.bobFreq) * item.bobAmp
					item.model:PivotTo(item.pivot * CFrame.new(0, bob, 0) * rot)
				else
					local angle = item.orbitAngle + animElapsed * item.orbitSpeed
					local x = math.cos(angle) * item.orbitRadius
					local z = math.sin(angle) * (item.orbitRadius * 0.45)
					local y = math.sin(animElapsed * item.bobFreq + item.phase) * item.bobAmp
					local rot = CFrame.Angles(animElapsed * item.rotSpeed.X, animElapsed * item.rotSpeed.Y, animElapsed * item.rotSpeed.Z)
					item.model:PivotTo(CFrame.new(x, y, z) * rot)
				end
			end
		end
	end)

	local function refreshSlots(state: any)
		if type(state) == "table" then
			ascensionsCount = tonumber(state.ascensions) or 0
			unlockedSlotsCount = tonumber(state.dieSlots) or 1

			if type(state.dice) == "table" and #state.dice > 0 then
				liveEquippedDice = {}
				-- THE SNAPSHOT'S KEYS ARE CAPITALISED. `StateSyncService`
				-- sends `Shape` and `MassBudget`; this read asked for `shape`
				-- and `mass`, missed on every die, and fell through to the
				-- defaults -- which is why every slot in the panel reported
				-- "D6" at mass 60 regardless of what the player owned. The
				-- fallbacks stay, but they are defence now rather than the
				-- path every die takes.
				for _, d in ipairs(state.dice) do
					table.insert(liveEquippedDice, {
						shape = tostring(d.Shape or "D6"),
						mass = tonumber(d.MassBudget) or 60,
					})
				end
			end
		end

		rebuildOrreryChamber()
		rebuildShowcaseSlots()
		rebuildInventory(state)
	end

	return refreshSlots
end

--------------------------------------------------------------------------------
-- 7. LEADERBOARDS OVERLAY
--------------------------------------------------------------------------------
local function buildBoardsOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (string) -> ()
	local boardsOverlay, legacyBody = UITheme.overlay("Leaderboards")
	boardsOverlay.Parent = screenGui
	overlays["boards"] = boardsOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, boardsBody = formatModalShell(boardsOverlay, "~ Global Leaderboards ~", getController)

	local BOARD_TABS: { { id: string, label: string, prefix: string } } = {
		{ id = "NetWorth", label = "NET WORTH", prefix = "$" },
		{ id = "HighestRoll", label = "BEST ROLL", prefix = "$" },
		{ id = "Ascensions", label = "ASCENSIONS", prefix = "" },
	}
	local activeBoard = "NetWorth"

	local boardStack = Instance.new("Frame")
	boardStack.Name = "BoardStack"
	boardStack.Size = UDim2.fromScale(1, 1)
	boardStack.BackgroundTransparency = 1
	boardStack.Parent = boardsBody

	local bsList = Instance.new("UIListLayout")
	bsList.SortOrder = Enum.SortOrder.LayoutOrder
	bsList.Padding = UDim.new(0, 8)
	bsList.Parent = boardStack

	-- TAB WIDTH FROM THE COUNT, never a literal fraction. A hardcoded 0.32 fits
	-- exactly three tabs and silently pushes the fourth off the panel.
	local tabCount = #BOARD_TABS
	local tabGutter = 6

	local boardTabRow = Instance.new("Frame")
	boardTabRow.Name = "BoardTabRow"
	boardTabRow.Size = UDim2.new(1, 0, 0, 30)
	boardTabRow.BackgroundTransparency = 1
	boardTabRow.LayoutOrder = 1
	boardTabRow.Parent = boardStack

	local btrList = Instance.new("UIListLayout")
	btrList.FillDirection = Enum.FillDirection.Horizontal
	btrList.SortOrder = Enum.SortOrder.LayoutOrder
	btrList.Padding = UDim.new(0, tabGutter)
	btrList.Parent = boardTabRow

	local boardStatus = Instance.new("TextLabel")
	boardStatus.Name = "BoardStatus"
	boardStatus.Size = UDim2.new(1, 0, 0, 18)
	boardStatus.BackgroundTransparency = 1
	boardStatus.Font = Enum.Font.GothamMedium
	boardStatus.Text = "Leaderboards sync every 30 seconds."
	boardStatus.TextColor3 = THEME.TextMuted
	boardStatus.TextSize = 11
	boardStatus.TextXAlignment = Enum.TextXAlignment.Left
	boardStatus.LayoutOrder = 2
	boardStatus.Parent = boardStack

	local boardRowsHolder = Instance.new("Frame")
	boardRowsHolder.Name = "BoardRows"
	boardRowsHolder.Size = UDim2.new(1, 0, 1, -62)
	boardRowsHolder.BackgroundTransparency = 1
	boardRowsHolder.LayoutOrder = 3
	boardRowsHolder.Parent = boardStack

	local brhList = Instance.new("UIListLayout")
	brhList.SortOrder = Enum.SortOrder.LayoutOrder
	brhList.Padding = UDim.new(0, 4)
	brhList.Parent = boardRowsHolder

	-- A FIXED POOL, refilled rather than rebuilt. The board holds at most a page
	-- of entries, and rebuilding Instances on every tab press would churn the
	-- whole list each time.
	local BOARD_ROW_COUNT = 10
	type BoardRowUI = { row: Frame, rank: TextLabel, name: TextLabel, score: TextLabel }
	local boardRows: { BoardRowUI } = {}

	for i = 1, BOARD_ROW_COUNT do
		local row = Instance.new("Frame")
		row.Name = "BoardRow" .. tostring(i)
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = THEME.CardBg
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Visible = false
		row.Parent = boardRowsHolder

		local rowC = Instance.new("UICorner")
		rowC.CornerRadius = UDim.new(0, 6)
		rowC.Parent = row

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 10)
		rowPad.PaddingRight = UDim.new(0, 10)
		rowPad.Parent = row

		local rankLbl = Instance.new("TextLabel")
		rankLbl.Name = "Rank"
		rankLbl.Size = UDim2.new(0.14, 0, 1, 0)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Font = Enum.Font.Code
		rankLbl.Text = ""
		rankLbl.TextColor3 = THEME.GoldPrimary
		rankLbl.TextSize = 12
		rankLbl.TextXAlignment = Enum.TextXAlignment.Left
		rankLbl.Parent = row

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "PlayerName"
		nameLbl.Size = UDim2.new(0.52, 0, 1, 0)
		nameLbl.Position = UDim2.new(0.14, 0, 0, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.Gotham
		nameLbl.Text = ""
		nameLbl.TextColor3 = THEME.TextPrimary
		nameLbl.TextSize = 12
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Parent = row

		local scoreLbl = Instance.new("TextLabel")
		scoreLbl.Name = "Score"
		scoreLbl.Size = UDim2.new(0.34, 0, 1, 0)
		scoreLbl.Position = UDim2.new(0.66, 0, 0, 0)
		scoreLbl.BackgroundTransparency = 1
		scoreLbl.Font = Enum.Font.Code
		scoreLbl.Text = ""
		scoreLbl.TextColor3 = THEME.Positive
		scoreLbl.TextSize = 12
		scoreLbl.TextXAlignment = Enum.TextXAlignment.Right
		scoreLbl.Parent = row

		table.insert(boardRows, { row = row, rank = rankLbl, name = nameLbl, score = scoreLbl })
	end

	local refreshBoards: (string) -> ()
	local boardTabButtons: { [string]: TextButton } = {}

	local function paintTabs(activeId: string)
		for id, btn in pairs(boardTabButtons) do
			local isActive = id == activeId
			btn.BackgroundColor3 = if isActive then THEME.GoldPrimary else THEME.ButtonDark
			btn.TextColor3 = if isActive then THEME.TextDark else THEME.TextMuted
		end
	end

	for i, tab in ipairs(BOARD_TABS) do
		local tBtn = Instance.new("TextButton")
		tBtn.Name = "Tab_" .. tab.id
		tBtn.Size = UDim2.new(1 / tabCount, -(tabGutter * (tabCount - 1)) / tabCount, 1, 0)
		tBtn.BackgroundColor3 = THEME.ButtonDark
		tBtn.BorderSizePixel = 0
		tBtn.Font = Enum.Font.GothamBold
		tBtn.Text = tab.label
		tBtn.TextColor3 = THEME.TextMuted
		tBtn.TextSize = 11
		tBtn.LayoutOrder = i
		tBtn.Parent = boardTabRow

		local tC = Instance.new("UICorner")
		tC.CornerRadius = UDim.new(0, 6)
		tC.Parent = tBtn

		boardTabButtons[tab.id] = tBtn

		tBtn.MouseButton1Click:Connect(function()
			activeBoard = tab.id
			-- Mirrored onto the controller so `openOverlay` reopens on the tab
			-- the player last chose rather than resetting to the first.
			local ctrl = getController()
			if ctrl ~= nil then
				ctrl.activeBoard = tab.id
			end
			refreshBoards(tab.id)
		end)
	end

	-- THE FETCH. `GetLeaderboard` reads the server CACHE and never triggers a
	-- DataStore call of its own (T-22), so pressing a tab repeatedly is cheap --
	-- but NetClient still throttles it, and a throttled call returns nil.
	refreshBoards = function(boardId: string)
		activeBoard = boardId
		paintTabs(boardId)

		local def
		for _, t in ipairs(BOARD_TABS) do
			if t.id == boardId then
				def = t
			end
		end
		if def == nil then
			return
		end

		boardStatus.Text = "Loading..."
		boardStatus.TextColor3 = THEME.TextMuted

		task.spawn(function()
			local entries, myRank = NetClient.getLeaderboard(boardId)
			-- STILL THE ACTIVE TAB? A player switching quickly must not have an
			-- older response paint over a newer one.
			if activeBoard ~= boardId then
				return
			end

			if type(entries) ~= "table" then
				for _, ui in ipairs(boardRows) do
					ui.row.Visible = false
				end
				boardStatus.Text = "Could not load the board. Try again shortly."
				boardStatus.TextColor3 = THEME.Negative
				return
			end

			local shown = 0
			for i, ui in ipairs(boardRows) do
				local e = entries[i]
				if type(e) ~= "table" then
					ui.row.Visible = false
				else
					shown += 1
					ui.row.Visible = true
					ui.rank.Text = "#" .. tostring(e.rank or i)
					ui.name.Text = tostring(e.name or "?")
					ui.score.Text = def.prefix .. Format.formatNumber(tonumber(e.rawVal) or 0)
					-- The player own row, highlighted so they can find
					-- themselves without reading every line.
					local isMe = myRank ~= nil and e.rank == myRank
					ui.name.TextColor3 = if isMe then THEME.GoldPrimary else THEME.TextPrimary
				end
			end

			if shown == 0 then
				-- AN EMPTY BOARD IS A REAL STATE, not an error. A fresh universe
				-- has nobody on it, and saying so beats a spinner or a
				-- fabricated top three.
				boardStatus.Text = "No one is on this board yet -- be the first."
				boardStatus.TextColor3 = THEME.TextMuted
			elseif myRank ~= nil then
				boardStatus.Text = string.format("You are ranked #%d.", myRank)
				boardStatus.TextColor3 = THEME.Positive
			else
				-- Honest about the limit rather than inventing a number: the
				-- server sends the top page only, so outside it the rank is
				-- genuinely unknown here.
				boardStatus.Text = "You are not in the top " .. tostring(shown) .. " yet."
				boardStatus.TextColor3 = THEME.TextMuted
			end
		end)
	end

	paintTabs(activeBoard)

	return refreshBoards
end

--------------------------------------------------------------------------------
-- 8. OFFLINE VAULT OVERLAY
--------------------------------------------------------------------------------
local function buildVaultOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (any) -> ()
	local vaultOverlay, legacyBody = UITheme.overlay("Offline Vault")
	vaultOverlay.Parent = screenGui
	overlays["vault"] = vaultOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, vaultBody = formatModalShell(vaultOverlay, "~ Offline Treasury Vault ~", getController)

	local function formatDuration(seconds: number): string
		local s = math.max(0, math.floor(seconds))
		local h = math.floor(s / 3600)
		local m = math.floor((s % 3600) / 60)
		if h > 0 then
			return string.format("%dh %dm", h, m)
		end
		if m > 0 then
			return string.format("%dm", m)
		end
		return string.format("%ds", s)
	end

	local vaultStack = Instance.new("Frame")
	vaultStack.Name = "VaultStack"
	vaultStack.Size = UDim2.fromScale(1, 1)
	vaultStack.BackgroundTransparency = 1
	vaultStack.Parent = vaultBody

	local vsList = Instance.new("UIListLayout")
	vsList.SortOrder = Enum.SortOrder.LayoutOrder
	vsList.Padding = UDim.new(0, 10)
	vsList.Parent = vaultStack

	-- THE ACCRUED AMOUNT, in the size it deserves. This is the number the player
	-- opened the panel to see.
	local vaultAmount = Instance.new("TextLabel")
	vaultAmount.Name = "VaultAmount"
	vaultAmount.Size = UDim2.new(1, 0, 0, 42)
	vaultAmount.BackgroundTransparency = 1
	vaultAmount.Font = Enum.Font.GothamBold
	vaultAmount.Text = "--"
	vaultAmount.TextColor3 = THEME.TextMuted
	vaultAmount.TextSize = 32
	vaultAmount.TextXAlignment = Enum.TextXAlignment.Left
	vaultAmount.LayoutOrder = 1
	vaultAmount.Parent = vaultStack

	local vaultTier = Instance.new("TextLabel")
	vaultTier.Name = "VaultTier"
	vaultTier.Size = UDim2.new(1, 0, 0, 16)
	vaultTier.BackgroundTransparency = 1
	vaultTier.Font = Enum.Font.Code
	vaultTier.Text = ""
	vaultTier.TextColor3 = THEME.GoldPrimary
	vaultTier.TextSize = 11
	vaultTier.TextXAlignment = Enum.TextXAlignment.Left
	vaultTier.LayoutOrder = 2
	vaultTier.Parent = vaultStack

	-- Capacity as a bar. Time is easier to read as a proportion than as two
	-- numbers the player has to divide.
	local vaultBarTrack = Instance.new("Frame")
	vaultBarTrack.Name = "VaultBarTrack"
	vaultBarTrack.Size = UDim2.new(1, 0, 0, 10)
	vaultBarTrack.BackgroundColor3 = THEME.InsetBg
	vaultBarTrack.BorderSizePixel = 0
	vaultBarTrack.LayoutOrder = 3
	vaultBarTrack.Parent = vaultStack

	local vbtC = Instance.new("UICorner")
	vbtC.CornerRadius = UDim.new(0, 5)
	vbtC.Parent = vaultBarTrack

	local vaultBarFill = Instance.new("Frame")
	vaultBarFill.Name = "VaultBarFill"
	vaultBarFill.Size = UDim2.fromScale(0, 1)
	vaultBarFill.BackgroundColor3 = THEME.Positive
	vaultBarFill.BorderSizePixel = 0
	vaultBarFill.Parent = vaultBarTrack

	local vbfC = Instance.new("UICorner")
	vbfC.CornerRadius = UDim.new(0, 5)
	vbfC.Parent = vaultBarFill

	local vaultInfo = Instance.new("TextLabel")
	vaultInfo.Name = "VaultInfo"
	vaultInfo.Size = UDim2.new(1, 0, 0, 0)
	vaultInfo.AutomaticSize = Enum.AutomaticSize.Y
	vaultInfo.BackgroundTransparency = 1
	vaultInfo.Font = Enum.Font.Gotham
	vaultInfo.Text = "Waiting for your vault figures..."
	vaultInfo.TextColor3 = THEME.TextMuted
	vaultInfo.TextSize = 12
	vaultInfo.TextWrapped = true
	vaultInfo.TextXAlignment = Enum.TextXAlignment.Left
	vaultInfo.TextYAlignment = Enum.TextYAlignment.Top
	vaultInfo.LayoutOrder = 4
	vaultInfo.Parent = vaultStack

	local vaultActions = Instance.new("Frame")
	vaultActions.Name = "VaultActions"
	vaultActions.Size = UDim2.new(1, 0, 0, 40)
	vaultActions.BackgroundTransparency = 1
	vaultActions.LayoutOrder = 5
	vaultActions.Parent = vaultStack

	local vaList = Instance.new("UIListLayout")
	vaList.FillDirection = Enum.FillDirection.Horizontal
	vaList.SortOrder = Enum.SortOrder.LayoutOrder
	vaList.Padding = UDim.new(0, 10)
	vaList.Parent = vaultActions

	local function makeVaultButton(order: number, text: string, bg: Color3): TextButton
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.5, -5, 1, 0)
		b.BackgroundColor3 = bg
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.Text = text
		b.TextColor3 = THEME.TextDark
		b.TextSize = 12
		b.LayoutOrder = order
		b.Parent = vaultActions
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = b
		return b
	end

	local claimVaultBtn = makeVaultButton(1, "CLAIM", THEME.GoldPrimary)
	claimVaultBtn.Name = "ClaimVaultButton"
	local buyHoursBtn = makeVaultButton(2, "+1 HOUR", THEME.ButtonDark)
	buyHoursBtn.Name = "BuyHoursButton"

	local vaultBusy = false

	local function setVaultButton(btn: TextButton, label: string, enabled: boolean)
		btn.Text = label
		btn.Active = enabled
		btn.AutoButtonColor = enabled
		btn.BackgroundColor3 = if enabled then THEME.GoldPrimary else THEME.ButtonDark
		btn.TextColor3 = if enabled then THEME.TextDark else THEME.TextMuted
	end

	claimVaultBtn.MouseButton1Click:Connect(function()
		if vaultBusy or not claimVaultBtn.Active then
			return
		end
		vaultBusy = true
		task.spawn(function()
			local result = NetClient.claimVault(false)
			vaultBusy = false
			if not result.ok then
				vaultInfo.Text = "Could not collect the vault just now."
			end
		end)
	end)

	buyHoursBtn.MouseButton1Click:Connect(function()
		if vaultBusy or not buyHoursBtn.Active then
			return
		end
		vaultBusy = true
		task.spawn(function()
			local result = NetClient.buyVaultHours(1)
			vaultBusy = false
			if not result.ok then
				vaultInfo.Text = "Could not buy capacity just now."
			end
		end)
	end)

	local function refreshVault(state: any)
		-- THE REAL FIGURES, from the snapshot's `vault` block. Was an empty stub
		-- after the revamp, so this panel showed one static sentence forever.
		--
		-- `vault` is ABSENT rather than zeroed when the server has not reported,
		-- which is deliberate: it keeps "unknown" and "empty" distinguishable.
		-- Painting "$0" for an absent block would state a balance the client
		-- does not actually know.
		local v = if type(state) == "table" then state.vault else nil
		if type(v) ~= "table" then
			vaultAmount.Text = "--"
			vaultAmount.TextColor3 = THEME.TextMuted
			vaultBarFill.Size = UDim2.fromScale(0, 1)
			vaultInfo.Text = "Waiting for your vault figures..."
			vaultTier.Text = ""
			setVaultButton(claimVaultBtn, "CLAIM", false)
			setVaultButton(buyHoursBtn, "+1 HOUR", false)
			return
		end

		local ownedHours = tonumber(v.purchasedHours) or 0
		local maxHours = tonumber(v.maxPurchasedHours) or 0
		local gems = if type(state) == "table" then tonumber(state.gems) or 0 else 0
		local hourCost = VaultCatalog.gemCostForHours(1) or 0
		-- How many more hours would ACTUALLY raise capacity -- not how many are
		-- left under the cap. The two differ for a VIP player whose floor
		-- already exceeds every other source combined.
		local buyable = tonumber(v.buyableHours) or 0
		local atPurchaseCap = maxHours > 0 and ownedHours >= maxHours

		if atPurchaseCap then
			setVaultButton(buyHoursBtn, string.format("MAX (+%dh)", math.floor(maxHours)), false)
		elseif buyable <= 0 then
			-- Nothing to sell. "INCLUDED" rather than an unexplained grey button
			-- is the difference between a player thinking the game is broken and
			-- understanding they already have the benefit.
			setVaultButton(buyHoursBtn, "INCLUDED", false)
		else
			setVaultButton(buyHoursBtn,
				string.format("+1 HOUR  %d\u{25C6}", hourCost), gems >= hourCost)
		end

		vaultTier.Text = VaultCatalog.describeTier(
			tonumber(v.efficiency) or VaultCatalog.BASE_EFFICIENCY,
			v.hasVip == true, v.hasPremium == true)

		local unclaimed = tonumber(v.unclaimed) or 0
		local claimable = tonumber(v.claimableSeconds) or 0
		local capacity = tonumber(v.capacitySeconds) or 0
		local rate = tonumber(v.ratePerSec) or 0

		vaultAmount.Text = "$" .. Format.formatNumber(unclaimed)
		vaultAmount.TextColor3 = if unclaimed > 0 then THEME.Positive else THEME.TextMuted

		local frac = if capacity > 0 then math.clamp(claimable / capacity, 0, 1) else 0
		vaultBarFill.Size = UDim2.fromScale(frac, 1)
		vaultBarFill.BackgroundColor3 = if v.atCapacity == true
			then THEME.Negative else THEME.Positive

		if rate <= 0 then
			-- An honest empty state. The vault pays at the recent average rate,
			-- so someone who has not rolled yet has no rate and would otherwise
			-- stare at $0 with no explanation.
			vaultInfo.Text = string.format(
				"Roll a few times to set an earning rate -- your vault fills at your"
				.. " recent average.\n\nHolds up to %s.", formatDuration(capacity))
		elseif v.atCapacity == true then
			vaultInfo.Text = string.format(
				"FULL -- %s of %s stored, and it has stopped earning.\n\n"
				.. "Collect it to start filling again.",
				formatDuration(claimable), formatDuration(capacity))
		else
			vaultInfo.Text = string.format("%s of %s stored, still filling.",
				formatDuration(claimable), formatDuration(capacity))
		end

		-- WHAT THE GEMS ACTUALLY BOUGHT -- which is not always what was paid for.
		--
		-- `buyable <= 0` has TWO causes meaning opposite things: the player is at
		-- the purchase cap (their Gems worked, there is simply no more to buy),
		-- or a floor is absorbing the purchase (their Gems did nothing). The cap
		-- case is tested FIRST because it is the one that means success --
		-- reading it as only the second told a player with a working +8h that it
		-- was "not adding to it", which was false.
		if ownedHours > 0 then
			if not atPurchaseCap and buyable <= 0 and v.hasVip == true then
				vaultInfo.Text ..= string.format(
					"\n\nYour VIP floor of %s already covers more than every other"
					.. " source combined, so your %dh of Gem-bought capacity is not"
					.. " adding to it.",
					formatDuration(VaultCatalog.VIP_CAPACITY_SEC), math.floor(ownedHours))
			else
				vaultInfo.Text ..= string.format(
					"\n\n+%dh of that is Gem-bought, out of a possible +%dh.",
					math.floor(ownedHours), math.floor(maxHours))
			end
		elseif buyable <= 0 and v.hasVip == true then
			vaultInfo.Text ..= string.format(
				"\n\nYour VIP floor of %s already covers more than every other"
				.. " source combined, so extra capacity is not worth buying.",
				formatDuration(VaultCatalog.VIP_CAPACITY_SEC))
		end

		setVaultButton(claimVaultBtn, if unclaimed > 0 then "CLAIM" else "EMPTY", unclaimed > 0)
	end

	return refreshVault
end

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------
function V7MenuPanel.new(): V7MenuController
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "V7MenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 50
	screenGui.Parent = playerGui

	local overlays: { [string]: Frame } = {}
	local controller: V7MenuController

	local function getController(): V7MenuController
		return controller
	end

	-- Instantiate each overlay
	local shapeRefresh = buildShapesOverlay(screenGui, overlays, getController)
	local questRefresh = buildQuestsOverlay(screenGui, overlays, getController)
	local shopRefresh = buildShopOverlay(screenGui, overlays, getController)
	local boardsRefresh = buildBoardsOverlay(screenGui, overlays, getController)
	local ascendRefresh = buildAscendOverlay(screenGui, overlays, getController)
	local vaultRefresh = buildVaultOverlay(screenGui, overlays, getController)
	local settingsRefresh = buildSettingsOverlay(screenGui, overlays, getController)
	local slotsRefresh = buildSlotsOverlay(screenGui, overlays, getController)

	for key, frame in pairs(overlays) do
		frame.Name = "Overlay_" .. key
		frame.Visible = false
	end

	local capabilities: { [string]: boolean } = {}

	controller = {
		overlays = overlays,
		shopRefresh = shopRefresh,
		boardsRefresh = boardsRefresh,
		-- The board the tabs open on. Regressed to nil during the revamp, which
		-- left the first open with no tab highlighted and nothing fetched.
		activeBoard = "NetWorth",
		ascendRefresh = ascendRefresh,
		shapeRefresh = shapeRefresh,
		questRefresh = questRefresh,
		vaultRefresh = vaultRefresh,
		slotsRefresh = slotsRefresh,
		settingsRefresh = settingsRefresh,
		_capabilities = capabilities,
		lastState = nil,

		openOverlay = function(self: V7MenuController, name: string)
			for k, f in pairs(self.overlays) do
				f.Visible = (k == name)
			end
			if self.lastState ~= nil then
				self:applyState(self.lastState)
			end

			-- BOARDS IS PULL, NOT PUSH. Every other panel rides the StateSync
			-- snapshot, but leaderboards are global rather than per-player, so
			-- they are fetched on demand -- and only when the panel is actually
			-- opened, so a player who never looks at them never costs the server
			-- a request. This is also why `boardsRefresh` is absent from the
			-- fan-out below: its parameter is a board id, not a snapshot.
			if name == "boards" and type(self.boardsRefresh) == "function" then
				local ok, err = pcall(self.boardsRefresh, self.activeBoard or "NetWorth")
				if not ok then
					warn("[V7MenuPanel] board refresh failed: " .. tostring(err))
				end
			end
		end,

		closeAll = function(self: V7MenuController)
			for _, f in pairs(self.overlays) do
				f.Visible = false
			end
		end,

		applyState = function(self: V7MenuController, state: any)
			if type(state) ~= "table" then
				return
			end
			self.lastState = state

			-- ITERATED BY NAME, WITH EVERY CALL ISOLATED. Restored after the UI
			-- revamp replaced it with a bare `if` chain that had neither.
			--
			-- Two separate protections live here, and the project has paid for
			-- both. FIRST, a nil entry is skipped and REPORTED rather than
			-- ending the sweep: the original defect (L-057) was `ipairs` over a
			-- list literal whose FIRST element was nil, which terminated the
			-- loop and left six unrelated panels dead with nothing logged.
			-- SECOND, each call is pcall-wrapped, because `applyState` is
			-- invoked from inside the StateSync handler -- an unguarded throw
			-- here does not merely lose one panel, it escapes the handler and
			-- takes the forge's snapshot down with it.
			--
			-- A stub is a PRESENT function, so the missing-refresher warning
			-- below would not have caught the four empty refreshers the revamp
			-- left behind. It catches a lost assignment, which is a different
			-- failure; do not read a silent console as proof a panel is live.
			local refreshers: { { name: string, fn: any } } = {
				{ name = "shop", fn = self.shopRefresh },
				{ name = "shapes", fn = self.shapeRefresh },
				{ name = "quests", fn = self.questRefresh },
				{ name = "vault", fn = self.vaultRefresh },
				{ name = "slots", fn = self.slotsRefresh },
				{ name = "settings", fn = self.settingsRefresh },
				{ name = "ascend", fn = self.ascendRefresh },
			}
			for _, entry in ipairs(refreshers) do
				if type(entry.fn) == "function" then
					local ok, err = pcall(entry.fn, state)
					if not ok then
						warn(string.format("[V7MenuPanel] %s refresh failed: %s",
							entry.name, tostring(err)))
					end
				else
					warn(string.format("[V7MenuPanel] %s refresh is missing -- that "
						.. "panel will never receive a snapshot", entry.name))
				end
			end
		end,

		-- Declares whether a client capability is present, from the composition
		-- root. Repaints immediately from the last snapshot so the answer takes
		-- effect without waiting for the next StateSync -- otherwise the audio
		-- rows in Settings sit stale from boot until a roll happens to arrive.
		setCapability = function(self: V7MenuController, name: string, present: boolean)
			self._capabilities[name] = present
			local last = self.lastState
			if last ~= nil and type(self.settingsRefresh) == "function" then
				local ok, err = pcall(self.settingsRefresh, last)
				if not ok then
					warn("[V7MenuPanel] settings refresh failed: " .. tostring(err))
				end
			end
		end,
	}

	return controller
end

return V7MenuPanel
