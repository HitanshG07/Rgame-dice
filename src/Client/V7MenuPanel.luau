--!strict

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

-- ==============================
-- ==============================
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
	TextSubtle   = Color3.fromRGB(120, 110, 102),
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

-- ------------------------------
-- ------------------------------
local MODAL_DESIGN_SIZE = Vector2.new(940, 580)
local MODAL_MIN_SIZE = Vector2.new(680, 420)

local MODAL_VIEWPORT_FRACTION = 0.85
local MODAL_SCALE_MIN = 0.65
local MODAL_SCALE_MAX = 1.25

local function computeModalScale(viewport: Vector2): number
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 1.0
	end
	local kx = (viewport.X * MODAL_VIEWPORT_FRACTION) / MODAL_DESIGN_SIZE.X
	local ky = (viewport.Y * MODAL_VIEWPORT_FRACTION) / MODAL_DESIGN_SIZE.Y
	return math.clamp(math.min(kx, ky), MODAL_SCALE_MIN, MODAL_SCALE_MAX)
end

local function bindModalScale(shell: Frame)
	local uiScale = shell:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = shell
	end

	local function apply()
		local cam = workspace.CurrentCamera
		if cam then
			uiScale.Scale = computeModalScale(cam.ViewportSize)
		end
	end

	apply()

	local viewportConn: RBXScriptConnection? = nil
	local function watchCamera()
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		local cam = workspace.CurrentCamera
		if cam then
			viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
		end
		apply()
	end

	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
end

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
	mainShell.Size = UDim2.new(0, 940, 0, 580)
	mainShell.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainShell.AnchorPoint = Vector2.new(0.5, 0.5)
	mainShell.BackgroundColor3 = THEME.ModalBg
	mainShell.BackgroundTransparency = 0
	mainShell.BorderSizePixel = 0
	mainShell.ClipsDescendants = false

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

	bindModalScale(mainShell)

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

	local bodyCanvas = Instance.new("Frame")
	bodyCanvas.Name = "BodyCanvas"
	bodyCanvas.Size = UDim2.new(1, -24, 1, -68)
	bodyCanvas.Position = UDim2.new(0, 12, 0, 60)
	bodyCanvas.BackgroundTransparency = 1
	bodyCanvas.ClipsDescendants = false
	bodyCanvas.Parent = mainShell

	return mainShell, bodyCanvas
end

-- ------------------------------
-- 1. DICE SHAPES OVERLAY
-- ------------------------------
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

	local rPad = Instance.new("UIPadding")
	rPad.PaddingLeft = UDim.new(0, 4)
	rPad.PaddingRight = UDim.new(0, 8)
	rPad.PaddingTop = UDim.new(0, 4)
	rPad.PaddingBottom = UDim.new(0, 8)
	rPad.Parent = rightCol

	local rGrid = Instance.new("UIGridLayout")
	rGrid.CellSize = UDim2.new(0.5, -9, 0, 118)
	rGrid.CellPadding = UDim2.new(0, 6, 0, 6)
	rGrid.SortOrder = Enum.SortOrder.LayoutOrder
	rGrid.Parent = rightCol

	local cardModels: { Model } = {}
	local inspectedShapeId = "D6"
	local currentEquippedShapeList: { string } = { "D6" }
	local currentDieSlotsCount = 1
	local currentAscensionsCount = 0
	local currentCashBalance = 0
	local ownedShapesMap: { [string]: boolean } = { D2 = true }

	local updateActionButtons: () -> ()

	local function inspectShape(shapeId: string)
		inspectedShapeId = shapeId
		local meta = shapeMeta[shapeId] or shapeMeta["D6"]
		local isOwned = (ownedShapesMap[shapeId] == true)
		local canUnlock, _ = DiceCatalog.canUnlock(shapeId, ownedShapesMap)

		if isOwned then
			ssTitle.Text = string.format("STATS & SPECIMEN: %s (%s)", meta.name, meta.id)
			if statValueLabels["face"] then statValueLabels["face"].Text = meta.faceCount .. " SIDES" end
			if statMeterFills["face"] then statMeterFills["face"].Size = UDim2.new(meta.faceCount / 20, 0, 1, 0) end

			if statValueLabels["volatility"] then statValueLabels["volatility"].Text = "VOID " .. meta.voidChance end
			if statMeterFills["volatility"] then statMeterFills["volatility"].Size = UDim2.new(meta.voidRatio, 0, 1, 0) end

			if statValueLabels["payout"] then statValueLabels["payout"].Text = meta.payoutMultiplier .. " PEAK" end
			if statMeterFills["payout"] then statMeterFills["payout"].Size = UDim2.new(meta.payoutRatio, 0, 1, 0) end
		elseif canUnlock then
			local cost = DiceCatalog.getUnlockCost(shapeId) or 0
			ssTitle.Text = string.format("AVAILABLE: %s [UNLOCK: $%s]", meta.name, Format.formatNumber(cost))
			if statValueLabels["face"] then statValueLabels["face"].Text = meta.faceCount .. " SIDES" end
			if statMeterFills["face"] then statMeterFills["face"].Size = UDim2.new(meta.faceCount / 20, 0, 1, 0) end

			if statValueLabels["volatility"] then statValueLabels["volatility"].Text = "VOID " .. meta.voidChance end
			if statMeterFills["volatility"] then statMeterFills["volatility"].Size = UDim2.new(meta.voidRatio, 0, 1, 0) end

			if statValueLabels["payout"] then statValueLabels["payout"].Text = meta.payoutMultiplier .. " PEAK" end
			if statMeterFills["payout"] then statMeterFills["payout"].Size = UDim2.new(meta.payoutRatio, 0, 1, 0) end
		else
			local prereq = DiceCatalog.getPrerequisite(shapeId)
			ssTitle.Text = string.format("LOCKED: %s [REQUIRES %s]", meta.name, prereq or "PREVIOUS")
			if statValueLabels["face"] then statValueLabels["face"].Text = "? SIDES" end
			if statMeterFills["face"] then statMeterFills["face"].Size = UDim2.new(0, 0, 1, 0) end

			if statValueLabels["volatility"] then statValueLabels["volatility"].Text = "LOCKED" end
			if statMeterFills["volatility"] then statMeterFills["volatility"].Size = UDim2.new(0, 0, 1, 0) end

			if statValueLabels["payout"] then statValueLabels["payout"].Text = "LOCKED" end
			if statMeterFills["payout"] then statMeterFills["payout"].Size = UDim2.new(0, 0, 1, 0) end
		end

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

		if updateActionButtons then
			updateActionButtons()
		end
	end

	updateActionButtons = function()
		local isUnlocked = (ownedShapesMap[inspectedShapeId] == true)
		local ownedTotal = if type(playerInventory) == "table" then (tonumber(playerInventory[inspectedShapeId]) or 0) else 0
		local inUseCount = 0
		for _, s in ipairs(currentEquippedShapeList) do
			if s == inspectedShapeId then
				inUseCount += 1
			end
		end
		local isEquippedOnSlot1 = (#currentEquippedShapeList > 0 and currentEquippedShapeList[1] == inspectedShapeId)
		local availableCount = math.max(0, ownedTotal - inUseCount)
		local cost = DiceCatalog.getUnlockCost(inspectedShapeId) or 0

		if isUnlocked then
			addInstanceBtn.Visible = true
			if ownedTotal == 0 then
				equipStateBtn.Text = "[ NO DICE OWNED ]"
				equipStateBtn.BackgroundColor3 = THEME.ButtonDark
				equipStateBtn.TextColor3 = THEME.TextMuted
				equipStateBtn.AutoButtonColor = false

				if currentCashBalance < cost then
					addInstanceBtn.Text = string.format("BUY %s ($%s)", inspectedShapeId, Format.formatNumber(cost))
					addInstanceBtn.BackgroundColor3 = THEME.ButtonDark
					addInstanceBtn.TextColor3 = THEME.Negative
					addInstanceBtn.AutoButtonColor = false
				else
					addInstanceBtn.Text = string.format("BUY %s ($%s)", inspectedShapeId, Format.formatNumber(cost))
					addInstanceBtn.BackgroundColor3 = THEME.Positive
					addInstanceBtn.TextColor3 = THEME.TextDark
					addInstanceBtn.AutoButtonColor = true
				end
			else
				if isEquippedOnSlot1 then
					equipStateBtn.Text = "[ EQUIPPED ON DIE 1 ]"
					equipStateBtn.BackgroundColor3 = THEME.ButtonDark
					equipStateBtn.TextColor3 = THEME.Positive
					equipStateBtn.AutoButtonColor = false
				elseif availableCount > 0 then
					equipStateBtn.Text = "EQUIP " .. inspectedShapeId .. " TO ACTIVE DIE"
					equipStateBtn.BackgroundColor3 = THEME.GoldPrimary
					equipStateBtn.TextColor3 = THEME.TextDark
					equipStateBtn.AutoButtonColor = true
				else
					equipStateBtn.Text = string.format("[ ALL %d IN USE ]", ownedTotal)
					equipStateBtn.BackgroundColor3 = THEME.ButtonDark
					equipStateBtn.TextColor3 = THEME.TextMuted
					equipStateBtn.AutoButtonColor = false
				end

				if currentCashBalance < cost then
					addInstanceBtn.Text = string.format("+1 %s INSTANCE ($%s)", inspectedShapeId, Format.formatNumber(cost))
					addInstanceBtn.BackgroundColor3 = THEME.ButtonDark
					addInstanceBtn.TextColor3 = THEME.Negative
					addInstanceBtn.AutoButtonColor = false
				else
					addInstanceBtn.Text = string.format("+1 %s INSTANCE ($%s)", inspectedShapeId, Format.formatNumber(cost))
					addInstanceBtn.BackgroundColor3 = THEME.Positive
					addInstanceBtn.TextColor3 = THEME.TextDark
					addInstanceBtn.AutoButtonColor = true
				end
			end
		else
			addInstanceBtn.Visible = false
			local canUnlock, _ = DiceCatalog.canUnlock(inspectedShapeId, ownedShapesMap)
			if canUnlock then
				local unlockCost = DiceCatalog.getUnlockCost(inspectedShapeId) or 0
				local canAfford = currentCashBalance >= unlockCost
				equipStateBtn.Text = string.format("UNLOCK %s ($%s)", inspectedShapeId, Format.formatNumber(unlockCost))
				equipStateBtn.BackgroundColor3 = if canAfford then THEME.GoldPrimary else THEME.ButtonDark
				equipStateBtn.TextColor3 = if canAfford then THEME.TextDark else THEME.Negative
				equipStateBtn.AutoButtonColor = canAfford
			else
				local prereq = DiceCatalog.getPrerequisite(inspectedShapeId)
				equipStateBtn.Text = string.format("LOCKED (REQUIRES %s)", prereq or "PREVIOUS")
				equipStateBtn.BackgroundColor3 = THEME.ButtonDark
				equipStateBtn.TextColor3 = THEME.TextMuted
				equipStateBtn.AutoButtonColor = false
			end
		end
	end

	local actionInFlight = false
	equipStateBtn.MouseButton1Click:Connect(function()
		if actionInFlight then return end
		local isUnlocked = (ownedShapesMap[inspectedShapeId] == true)
		local ownedTotal = if type(playerInventory) == "table" then (tonumber(playerInventory[inspectedShapeId]) or 0) else 0
		local inUseCount = 0
		for _, s in ipairs(currentEquippedShapeList) do
			if s == inspectedShapeId then
				inUseCount += 1
			end
		end
		local isEquippedOnSlot1 = (#currentEquippedShapeList > 0 and currentEquippedShapeList[1] == inspectedShapeId)
		local availableCount = math.max(0, ownedTotal - inUseCount)

		if isUnlocked then
			if ownedTotal > 0 and availableCount > 0 and not isEquippedOnSlot1 then
				actionInFlight = true
				task.spawn(function()
					NetClient.setShape(1, inspectedShapeId)
					actionInFlight = false
					updateActionButtons()
				end)
			end
		else
			local canUnlock, _ = DiceCatalog.canUnlock(inspectedShapeId, ownedShapesMap)
			if canUnlock then
				local unlockCost = DiceCatalog.getUnlockCost(inspectedShapeId) or 0
				if currentCashBalance < unlockCost then return end
				actionInFlight = true
				equipStateBtn.Text = "UNLOCKING..."
				task.spawn(function()
					local res = NetClient.buyDiamondNode(inspectedShapeId)
					actionInFlight = false
					updateActionButtons()
				end)
			end
		end
	end)

	local purchaseInFlight = false
	addInstanceBtn.MouseButton1Click:Connect(function()
		if purchaseInFlight then return end
		local isOwned = (ownedShapesMap[inspectedShapeId] == true)
		if not isOwned then return end

		local cost = DiceCatalog.getUnlockCost(inspectedShapeId) or 0
		if currentCashBalance < cost then
			return
		end

		purchaseInFlight = true
		addInstanceBtn.Text = "PURCHASING..."
		task.spawn(function()
			local res = NetClient.buyDieInstance(inspectedShapeId)
			purchaseInFlight = false
			updateActionButtons()
		end)
	end)

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

			local actionBtn = Instance.new("TextButton")
			actionBtn.Name = "ActionBtn"
			actionBtn.Size = UDim2.new(1, 0, 0, 26)
			actionBtn.Position = UDim2.new(0, 0, 1, -26)
			actionBtn.BackgroundColor3 = THEME.ButtonDark
			actionBtn.BorderSizePixel = 0
			actionBtn.AutoButtonColor = false
			actionBtn.Text = "SELECT"
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

	inspectShape("D2")

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
		if type(state) == "table" then
			currentCashBalance = tonumber(state.cash) or 0
			currentDieSlotsCount = tonumber(state.dieSlots) or 1
			currentAscensionsCount = tonumber(state.ascensions) or 0

			if type(state.diamondTree) == "table" and type(state.diamondTree.Shapes) == "table" then
				ownedShapesMap = state.diamondTree.Shapes
			end

			local currentShape = if type(state.dice) == "table" and #state.dice > 0
				then tostring(state.dice[1].Shape or "D2")
				else "D2"

			currentEquippedShapeList = {}
			if type(state.dice) == "table" then
				for _, d in ipairs(state.dice) do
					table.insert(currentEquippedShapeList, d.Shape or "D2")
				end
			end
			if #currentEquippedShapeList == 0 then
				table.insert(currentEquippedShapeList, currentShape)
			end

			rebuildOrbitChamber(currentEquippedShapeList)

			for shapeId, btn in pairs(cardActionBtns) do
				local isOwned = (ownedShapesMap[shapeId] == true)
				local isEquipped = false
				for _, eqId in ipairs(currentEquippedShapeList) do
					if eqId == shapeId then isEquipped = true; break end
				end

				local card = cardFrames[shapeId]
				local cStroke = cardStrokes[shapeId]

				if isOwned then
					if card then card.BackgroundColor3 = THEME.InsetBg end
					if isEquipped then
						btn.Text = "EQUIPPED"
						btn.BackgroundColor3 = THEME.ButtonDark
						btn.TextColor3 = THEME.GoldPrimary
					else
						btn.Text = "SELECT"
						btn.BackgroundColor3 = THEME.ButtonDark
						btn.TextColor3 = THEME.TextMuted
					end
				else
					local canUnlock, _ = DiceCatalog.canUnlock(shapeId, ownedShapesMap)
					if canUnlock then
						local unlockCost = DiceCatalog.getUnlockCost(shapeId) or 0
						if card then card.BackgroundColor3 = THEME.InsetBg end
						btn.Text = string.format("UNLOCK ($%s)", Format.formatNumber(unlockCost))
						btn.BackgroundColor3 = if currentCashBalance >= unlockCost then THEME.GoldPrimary else THEME.ButtonDark
						btn.TextColor3 = if currentCashBalance >= unlockCost then THEME.TextDark else THEME.Negative
					else
						if card then card.BackgroundColor3 = Color3.fromRGB(14, 12, 10) end
						btn.Text = "[ LOCKED ]"
						btn.BackgroundColor3 = THEME.ButtonDark
						btn.TextColor3 = THEME.TextMuted
					end
				end
			end

			updateActionButtons()
		end
	end

	return refreshShapes
end

-- ------------------------------
-- 2. DAILY QUESTS & REWARDS OVERLAY
-- ------------------------------
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

	local csPad = Instance.new("UIPadding")
	csPad.PaddingLeft = UDim.new(0, 4)
	csPad.PaddingRight = UDim.new(0, 8)
	csPad.PaddingTop = UDim.new(0, 4)
	csPad.PaddingBottom = UDim.new(0, 6)
	csPad.Parent = chestScroll

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
		tRow.Size = UDim2.new(1, 0, 0, 52)
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

-- ------------------------------
-- 3. SHOP & EXCHANGE OVERLAY
-- ------------------------------
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

	local sPad = Instance.new("UIPadding")
	sPad.PaddingLeft = UDim.new(0, 6)
	sPad.PaddingRight = UDim.new(0, 12)
	sPad.PaddingTop = UDim.new(0, 6)
	sPad.PaddingBottom = UDim.new(0, 10)
	sPad.Parent = shopScroll

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -14, 0, 176)
	gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
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
		textStack.Size = UDim2.new(1, 0, 1, 0)
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
		actionRow.BackgroundTransparency = 1
		actionRow.LayoutOrder = 99
		actionRow.Parent = textStack

		local buyBtn = Instance.new("TextButton")
		buyBtn.Name = "BuyButton"
		buyBtn.Size = UDim2.fromScale(1, 1)
		buyBtn.BackgroundColor3 = THEME.GoldPrimary
		buyBtn.BorderSizePixel = 0
		buyBtn.Font = Enum.Font.GothamBold
		buyBtn.Text = "BUY"
		buyBtn.TextColor3 = THEME.TextDark
		buyBtn.TextSize = 12
		buyBtn.Parent = actionRow

		local bbC = Instance.new("UICorner")
		bbC.CornerRadius = UDim.new(0, 6)
		bbC.Parent = buyBtn

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

-- ------------------------------
-- 4. THE SOVEREIGN ASCENSION VAULT OVERLAY
-- ------------------------------
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
	mHeader.Size = UDim2.new(1, 0, 0, 18)
	mHeader.BackgroundTransparency = 1
	mHeader.Font = Enum.Font.GothamBold
	mHeader.Text = "VAULT YIELD & PROJECTIONS"
	mHeader.TextColor3 = THEME.GoldPrimary
	mHeader.TextSize = 12.5
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
		rLabel.TextSize = 12
		rLabel.TextXAlignment = Enum.TextXAlignment.Left
		rLabel.Parent = row

		local rVal = Instance.new("TextLabel")
		rVal.Size = UDim2.new(0.4, 0, 1, 0)
		rVal.Position = UDim2.new(0.6, 0, 0, 0)
		rVal.BackgroundTransparency = 1
		rVal.Font = Enum.Font.GothamBold
		rVal.Text = defaultVal
		rVal.TextColor3 = valColor
		rVal.TextSize = 13
		rVal.TextXAlignment = Enum.TextXAlignment.Right
		rVal.Parent = row
		return rVal
	end

	local postVaultVal = makeMetricRow(2, "Post-Reset Vault Total:", "0 \u{2666} (+0)", THEME.Diamonds)
	local nextTierVal = makeMetricRow(3, "Next Diamond Tier:", "at $1.00M", THEME.GoldPrimary)
	local careerAscendVal = makeMetricRow(4, "Career Ascensions:", "0 Completed", THEME.Positive)

	local ascendBtn = Instance.new("TextButton")
	ascendBtn.Name = "AscendButton"
	ascendBtn.Size = UDim2.new(1, 0, 0, 44)
	ascendBtn.BackgroundColor3 = THEME.GoldPrimary
	ascendBtn.BorderSizePixel = 0
	ascendBtn.Font = Enum.Font.GothamBold
	ascendBtn.Text = "SEAL THE VAULT & ASCEND"
	ascendBtn.TextColor3 = THEME.TextDark
	ascendBtn.TextSize = 14
	ascendBtn.LayoutOrder = 7
	ascendBtn.Parent = leftCol

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 6)
	bCorner.Parent = ascendBtn

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = THEME.StrokeGold
	bStroke.Thickness = 1
	bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bStroke.Parent = ascendBtn

	local ascendStatus = Instance.new("TextLabel")
	ascendStatus.Name = "AscendStatus"
	ascendStatus.Size = UDim2.new(1, 0, 0, 26)
	ascendStatus.BackgroundTransparency = 1
	ascendStatus.Font = Enum.Font.GothamMedium
	ascendStatus.Text = "Ready to ascend. Press button to begin two-step confirmation."
	ascendStatus.TextColor3 = THEME.GoldPrimary
	ascendStatus.TextSize = 11.5
	ascendStatus.TextWrapped = true
	ascendStatus.LayoutOrder = 8
	ascendStatus.Parent = leftCol

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
		local cash = if type(state) == "table" then tonumber(state.cash) or 0 else 0
		local ascensions = if type(state) == "table" then tonumber(state.ascensions) or 0 else 0
		local diamonds = if type(state) == "table" then tonumber(state.diamonds) else nil
		local projected = DiceCatalog.ascensionDiamonds(cash)
		local threshold = DiceCatalog.ASCEND_MIN_LIFETIME_CASH

		careerAscendVal.Text = string.format("%d Completed", ascensions)
		nextTierVal.Text = "at $" .. Format.formatNumber(threshold)

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

-- ------------------------------
-- 5. SETTINGS OVERLAY
-- ------------------------------
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
	sList.Padding = UDim.new(0, 12)
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.Parent = settingsBody

	local settingRows: { [string]: any } = {}

	for i, def in ipairs(SettingsCatalog.ordered()) do
		local row = Instance.new("Frame")
		row.Name = "SettingRow_" .. def.key
		row.Size = UDim2.new(1, 0, 0, 80)
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
		rowPadding.PaddingTop = UDim.new(0, 12)
		rowPadding.PaddingBottom = UDim.new(0, 12)
		rowPadding.PaddingLeft = UDim.new(0, 18)
		rowPadding.PaddingRight = UDim.new(0, 18)
		rowPadding.Parent = row

		local infoFrame = Instance.new("Frame")
		infoFrame.Name = "InfoFrame"
		infoFrame.Size = UDim2.new(1, -160, 1, 0)
		infoFrame.BackgroundTransparency = 1
		infoFrame.Parent = row

		local infoList = Instance.new("UIListLayout")
		infoList.Padding = UDim.new(0, 4)
		infoList.SortOrder = Enum.SortOrder.LayoutOrder
		infoList.Parent = infoFrame

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, 0, 0, 24)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = def.label
		label.TextColor3 = THEME.GoldPrimary
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = 1
		label.Parent = infoFrame

		local blurb = Instance.new("TextLabel")
		blurb.Name = "Blurb"
		blurb.Size = UDim2.new(1, 0, 0, 22)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.Gotham
		blurb.Text = def.blurb
		blurb.TextColor3 = THEME.TextMuted
		blurb.TextSize = 13
		blurb.TextWrapped = true
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.LayoutOrder = 2
		blurb.Parent = infoFrame

		local toggleBtn = Instance.new("TextButton")
		toggleBtn.Name = "ToggleButton"
		toggleBtn.Size = UDim2.new(0, 140, 0, 46)
		toggleBtn.Position = UDim2.new(1, -140, 0.5, -23)
		toggleBtn.BackgroundColor3 = THEME.GoldPrimary
		toggleBtn.BorderSizePixel = 0
		toggleBtn.Font = Enum.Font.GothamBold
		toggleBtn.Text = "ACTIVE"
		toggleBtn.TextColor3 = THEME.TextDark
		toggleBtn.TextSize = 14
		toggleBtn.Parent = row

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = toggleBtn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = THEME.StrokeGold
		btnStroke.Thickness = 1
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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

	local codeCard = Instance.new("Frame")
	codeCard.Name = "PromoCard"
	-- 144. Two separate budgets had to balance here and the first fix only
	-- balanced one of them, so both are written down:
	--
	--   INSIDE the card: 14+14 padding + 22 title + 10 gap + 48 input row
	--   + 10 gap + 16 status = 134. A UIListLayout charges its Padding BETWEEN
	--   siblings, so a third child costs 10+16, not 16 -- which is why the
	--   original 126 (sized for two children) could not absorb a status line.
	--
	--   INSIDE THE PANEL: `settingsBody` is a fixed 512px with no ScrollingFrame
	--   and ClipsDescendants = false, and `sList` pads 12 between children. Four
	--   setting rows at 80 = 320, plus 3 gaps at 12 = 36, plus 12 to this card,
	--   leaves 144 at the absolute limit. At 152 the card hung 9px past the
	--   panel body -- measured
	--   live, not derived -- and because nothing clips, it drew over the scrim
	--   rather than being cut off.
	--
	-- 140, not 144: 144 lands EXACTLY flush, and a zero margin is not a fit --
	-- it survives only until any row grows by a pixel. 140 leaves 4px outside
	-- and 6px inside. THE
	-- LESSON: sizing a child to fit its own contents is half the check; the
	-- other half is whether the parent still holds the child.
	codeCard.Size = UDim2.new(1, 0, 0, 140)
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
	promoPad.PaddingTop = UDim.new(0, 14)
	promoPad.PaddingBottom = UDim.new(0, 14)
	promoPad.PaddingLeft = UDim.new(0, 18)
	promoPad.PaddingRight = UDim.new(0, 18)
	promoPad.Parent = codeCard

	local promoList = Instance.new("UIListLayout")
	promoList.Padding = UDim.new(0, 10)
	promoList.SortOrder = Enum.SortOrder.LayoutOrder
	promoList.Parent = codeCard

	local codeTitle = Instance.new("TextLabel")
	codeTitle.Size = UDim2.new(1, 0, 0, 22)
	codeTitle.BackgroundTransparency = 1
	codeTitle.Font = Enum.Font.GothamBold
	codeTitle.Text = "PROMO CODE REDEMPTION"
	codeTitle.TextColor3 = THEME.GoldPrimary
	codeTitle.TextSize = 14
	codeTitle.TextXAlignment = Enum.TextXAlignment.Left
	codeTitle.LayoutOrder = 1
	codeTitle.Parent = codeCard

	local inputRow = Instance.new("Frame")
	inputRow.Size = UDim2.new(1, 0, 0, 48)
	inputRow.BackgroundTransparency = 1
	inputRow.LayoutOrder = 2
	inputRow.Parent = codeCard

	local codeBox = Instance.new("TextBox")
	codeBox.Size = UDim2.new(1, -152, 1, 0)
	codeBox.BackgroundColor3 = THEME.InsetBg
	codeBox.BorderSizePixel = 0
	codeBox.Font = Enum.Font.Code
	codeBox.PlaceholderText = "ENTER CODE"
	codeBox.PlaceholderColor3 = Color3.fromRGB(140, 130, 120)
	codeBox.Text = ""
	codeBox.TextColor3 = THEME.TextPrimary
	codeBox.TextSize = 14
	codeBox.TextXAlignment = Enum.TextXAlignment.Left
	codeBox.ClearTextOnFocus = false
	codeBox.Parent = inputRow

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 6)
	boxCorner.Parent = codeBox

	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingLeft = UDim.new(0, 14)
	boxPad.PaddingRight = UDim.new(0, 14)
	boxPad.Parent = codeBox

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = THEME.StrokeSubtle
	boxStroke.Thickness = 1
	boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	boxStroke.Parent = codeBox

	local redeemBtn = Instance.new("TextButton")
	redeemBtn.Size = UDim2.new(0, 140, 1, 0)
	redeemBtn.Position = UDim2.new(1, -140, 0, 0)
	redeemBtn.BackgroundColor3 = THEME.GoldPrimary
	redeemBtn.BorderSizePixel = 0
	redeemBtn.Font = Enum.Font.GothamBold
	redeemBtn.Text = "REDEEM"
	redeemBtn.TextColor3 = THEME.TextDark
	redeemBtn.TextSize = 14
	redeemBtn.Parent = inputRow

	local rbc = Instance.new("UICorner")
	rbc.CornerRadius = UDim.new(0, 6)
	rbc.Parent = redeemBtn

	-- The button was built, styled and parented with NO click handler at all, on
	-- top of a redemption path that works end to end -- gateway, catalog,
	-- duplicate tracking and persistence were all already in place. Typing a
	-- valid code and clicking did nothing, with no error and no feedback.
	--
	-- The card was resized to hold this line -- see the arithmetic where
	-- `codeCard.Size` is set. Nothing else was moved or restyled.
	local codeStatus = Instance.new("TextLabel")
	codeStatus.Name = "CodeStatus"
	codeStatus.Size = UDim2.new(1, 0, 0, 16)
	codeStatus.BackgroundTransparency = 1
	codeStatus.Font = Enum.Font.Gotham
	codeStatus.Text = ""
	codeStatus.TextColor3 = THEME.TextMuted
	codeStatus.TextSize = 12
	codeStatus.TextXAlignment = Enum.TextXAlignment.Left
	codeStatus.TextTruncate = Enum.TextTruncate.AtEnd
	codeStatus.LayoutOrder = 3
	codeStatus.Parent = codeCard

	local function setCodeStatus(message: string, colour: Color3)
		codeStatus.Text = message
		codeStatus.TextColor3 = colour
	end

	-- NFR-5: the reward is never named here. The server credits it and the next
	-- snapshot carries the new balance -- quoting a figure client-side would be
	-- asserting an outcome the client has no authority over.
	--
	-- Every value that can ARRIVE HERE, enumerated by walking the wire INWARD
	-- from this consumer -- not by listing what the functions I happened to know
	-- about return. Two rounds of audit rejection came from the outward method:
	-- both times the table looked complete and both times a producer nobody was
	-- thinking about (first `PlayerProfile.mutate`, then the gateway's own
	-- dispatch wrapper) sat outside the walk. The inbound surface is finite and
	-- greppable; the set of functions that might feed it is not.
	--
	-- The surface, in the order a call meets it:
	--
	--   1. NetClient.call, BEFORE the wire  (NetClient.luau:105,112,119)
	--        throttled, unavailable, malformed_response
	--   2. Gateway dispatch wrapper          (RemoteGateway.luau:241,245,261)
	--        invalid_request, rate_limited, server_error
	--        -- and reject() at :204 rewrites any detailed refusal to
	--        invalid_request on the way out, so the detail never arrives.
	--   3. The RedeemCode handler            (ServerBootstrap.server.luau:695)
	--        not_string, empty_string, too_long -- returned DIRECTLY, not
	--        through reject(), so unlike most refusals these do reach us.
	--   4. ProgressionService.redeemCode     (:89,99,104,108)
	--        invalid_code, no_profile, already_redeemed
	--   5. PlayerProfile.mutate, via `reason or "mutate_failed"` (:116)
	--        profile_released, mutate_failed
	--
	-- NFR-5: no message below names a figure. The server credits the reward and
	-- the next snapshot carries the balance; quoting an amount here would assert
	-- an outcome the client has no authority over.
	--
	-- `invalid_code` stays deliberately generic -- the server returns it both for
	-- a malformed code and for one that does not exist, so a fishing client
	-- cannot enumerate which codes are real. Do not split it.
	local REDEEM_MESSAGES: { [string]: string } = {
		-- 1. never left the client
		throttled = "Slow down a moment, then try again.",
		unavailable = "Could not reach the server. Try again in a moment.",
		malformed_response = "Could not reach the server. Try again in a moment.",
		-- 2. refused by the gateway
		invalid_request = "That code is not valid.",
		rate_limited = "Too many tries. Wait a few seconds, then try again.",
		server_error = "Something went wrong on our side. Try again in a moment.",
		-- 3. refused by the handler's own validator
		not_string = "That code is not valid.",
		empty_string = "Enter a code first.",
		too_long = "That code is too long.",
		-- 4. refused by the redemption rules
		invalid_code = "That code is not valid.",
		no_profile = "Your profile is still loading. Try again in a moment.",
		already_redeemed = "You have already redeemed that code.",
		-- 5. the write itself failed -- the redemption did NOT persist
		profile_released = "Your session ended, so that code was not saved. Rejoin and try again.",
		mutate_failed = "Could not save that redemption. Try again in a moment.",
	}

	-- Bumped on every submit so a reply that arrives after the watchdog has
	-- already given up cannot overwrite the newer attempt's status.
	local REDEEM_TIMEOUT_SEC = 10
	local redeemBusy = false
	local redeemGeneration = 0

	local function submitCode()
		if redeemBusy then
			return
		end

		local typed = (string.gsub(codeBox.Text, "%s+", ""))
		if typed == "" then
			setCodeStatus("Enter a code first.", THEME.TextMuted)
			return
		end

		redeemBusy = true
		redeemGeneration += 1
		local generation = redeemGeneration
		redeemBtn.AutoButtonColor = false
		redeemBtn.Text = "..."
		setCodeStatus("Checking...", THEME.TextMuted)

		-- Claims the right to report this attempt's outcome. Exactly one caller
		-- can win: the reply or the watchdog, whichever arrives first.
		--
		-- IT MUST BUMP THE GENERATION ITSELF. An earlier version only compared
		-- against it, which separated one attempt from the NEXT but not the two
		-- racers within a single attempt -- so on a stall the watchdog reported
		-- the timeout at T+10 and a reply landing at T+12 passed the same check
		-- again, overwrote the message and re-ran the restore. Bumping here is
		-- what makes the claim exclusive rather than merely ordered.
		--
		-- The Parent check keeps a spawned thread from writing to a destroyed
		-- Instance, which throws inside `task.spawn` where nothing catches it.
		local function finish(): boolean
			if generation ~= redeemGeneration or codeStatus.Parent == nil then
				return false
			end
			redeemGeneration += 1
			redeemBusy = false
			redeemBtn.AutoButtonColor = true
			redeemBtn.Text = "REDEEM"
			return true
		end

		-- `NetClient.call` pcalls InvokeServer, which catches a handler that
		-- ERRORS -- but not one that never returns. A RemoteFunction whose server
		-- handler yields forever (a DataStore stall is the realistic case) yields
		-- this thread indefinitely, and pcall never resolves. Without a watchdog
		-- the button would sit at "..." with redeemBusy stuck true, and every
		-- later click would hit the early return: exactly the do-nothing button
		-- this change exists to remove, only now claiming to be busy.
		task.delay(REDEEM_TIMEOUT_SEC, function()
			if finish() then
				setCodeStatus("That took too long. Try again in a moment.", THEME.Negative)
			end
		end)

		task.spawn(function()
			local result = NetClient.redeemCode(typed)

			if not finish() then
				return
			end

			if result.ok then
				codeBox.Text = ""
				setCodeStatus("Code redeemed. Your balance has been updated.", THEME.Positive)
			else
				local reason = if type(result.reason) == "string" then result.reason else ""
				setCodeStatus(REDEEM_MESSAGES[reason] or "Could not redeem that code right now.", THEME.Negative)
			end
		end)
	end

	redeemBtn.MouseButton1Click:Connect(submitCode)

	-- Enter submits, because a code box that ignores Enter reads as broken. The
	-- guard matters: FocusLost fires on click-away too, and submitting then would
	-- fire a request the player never asked for.
	codeBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submitCode()
		end
	end)

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

-- ------------------------------
-- 6. DIE SLOTS & TRAIT FORGE OVERLAY (APPROVED 4-QUADRANT ARCHITECTURE)
-- ------------------------------
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

		for idx, rawItem in ipairs(shapeList) do
			local shapeId = if type(rawItem) == "table" then tostring((rawItem :: any).shape or "D2") else tostring(rawItem)
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
		tLbl.TextSize = 13.5
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
			rLbl.TextSize = 11.5
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

	local quadList = Instance.new("UIListLayout")
	quadList.FillDirection = Enum.FillDirection.Vertical
	quadList.SortOrder = Enum.SortOrder.LayoutOrder
	quadList.Padding = UDim.new(0, 8)
	quadList.Parent = bodyContainer

	local currentSlotPage = 1
	local selectedSlotIndex = 1
	local selectedInventoryShape = "D2"
	local currentCash = 0
	local ownedShapesMap: { [string]: boolean } = { D2 = true }
	local playerInventory: { [string]: number } = { D2 = 1 }

	local liveEquippedDice: { { shape: string, mass: number } } = {
		{ shape = "D2", mass = 60 },
	}
	local unlockedSlotsCount = 1
	local ascensionsCount = 0
	-- The SlotNodes tree level. Tracked here because the slot cap is
	-- `ascensions + SlotNodes`, and reading only half of it would make this
	-- panel disagree with the server about how many slots exist.
	local slotNodesCount = 0

	local SLOTS_PER_PAGE = 3
	local function slotPageCount(): number
		local total = math.max(DiceCatalog.dieSlotCapFor(ascensionsCount, slotNodesCount), unlockedSlotsCount, #liveEquippedDice, 1)
		return math.max(1, math.ceil(total / SLOTS_PER_PAGE))
	end

	local topRow = Instance.new("Frame")
	topRow.Name = "TopRow"
	topRow.Size = UDim2.new(1, 0, 0.44, -4)
	topRow.BackgroundTransparency = 1
	topRow.LayoutOrder = 1
	topRow.Parent = bodyContainer

	local topList = Instance.new("UIListLayout")
	topList.FillDirection = Enum.FillDirection.Horizontal
	topList.SortOrder = Enum.SortOrder.LayoutOrder
	topList.Padding = UDim.new(0, 8)
	topList.Parent = topRow

	local prevBox = buildQuadrantShell(topRow, "Visualizer", UDim2.new(0.30, -3, 1, 0), 1, THEME.StrokeSubtle, THEME.CardBg)
	buildSectionHeader(prevBox, "PREVIEW", nil, THEME.GoldPrimary)

	local pvFrame = Instance.new("Frame")
	pvFrame.Name = "OrreryViewportContainer"
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
	pvStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pvStroke.Parent = pvFrame

	local function rebuildOrreryChamber()
		for _, child in ipairs(pvFrame:GetChildren()) do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end

		pruneDeadViewportItems()

		if #liveEquippedDice <= 1 then
			local shape = if liveEquippedDice[1] then liveEquippedDice[1].shape else "D2"
			createMiniDieViewport(pvFrame, UDim2.fromScale(1, 1), shape, THEME.InsetBg)
		else
			local shapes: { string } = {}
			for _, d in ipairs(liveEquippedDice) do
				table.insert(shapes, d.shape or "D2")
			end
			createOrreryChamber(pvFrame, UDim2.fromScale(1, 1), shapes, THEME.InsetBg)
		end
	end

	rebuildOrreryChamber()

	local slotsBox = buildQuadrantShell(topRow, "ActiveSlots", UDim2.new(0.70, -5, 1, 0), 2, THEME.StrokeGold, THEME.CardBg)

	local sHeadFrame = Instance.new("Frame")
	sHeadFrame.Size = UDim2.new(1, 0, 0, 20)
	sHeadFrame.BackgroundTransparency = 1
	sHeadFrame.LayoutOrder = 1
	sHeadFrame.Parent = slotsBox

	local sHeadLeft = Instance.new("TextLabel")
	sHeadLeft.Size = UDim2.new(0.5, 0, 1, 0)
	sHeadLeft.BackgroundTransparency = 1
	sHeadLeft.Text = "ACTIVE SLOTS"
	sHeadLeft.TextColor3 = THEME.GoldPrimary
	sHeadLeft.Font = Enum.Font.GothamBold
	sHeadLeft.TextSize = 13.5
	sHeadLeft.TextXAlignment = Enum.TextXAlignment.Left
	sHeadLeft.Parent = sHeadFrame

	local pageTagLbl = Instance.new("TextLabel")
	pageTagLbl.Size = UDim2.new(0.5, 0, 1, 0)
	pageTagLbl.Position = UDim2.new(0.5, 0, 0, 0)
	pageTagLbl.BackgroundTransparency = 1
	pageTagLbl.Text = "SLOTS 01 - 03  [PAGE 1/1]"
	pageTagLbl.TextColor3 = THEME.TextMuted
	pageTagLbl.Font = Enum.Font.Code
	pageTagLbl.TextSize = 10.5
	pageTagLbl.TextXAlignment = Enum.TextXAlignment.Right
	pageTagLbl.Parent = sHeadFrame

	local sBody = Instance.new("Frame")
	sBody.Size = UDim2.new(1, 0, 1, -26)
	sBody.BackgroundTransparency = 1
	sBody.LayoutOrder = 2
	sBody.Parent = slotsBox

	local sList = Instance.new("UIListLayout")
	sList.FillDirection = Enum.FillDirection.Horizontal
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.VerticalAlignment = Enum.VerticalAlignment.Center
	sList.Padding = UDim.new(0, 4)
	sList.Parent = sBody

	local lArrow = Instance.new("TextButton")
	lArrow.Size = UDim2.new(0, 24, 1, 0)
	lArrow.BackgroundColor3 = THEME.InsetBg
	lArrow.BorderSizePixel = 0
	lArrow.Text = "<"
	lArrow.TextColor3 = THEME.GoldPrimary
	lArrow.Font = Enum.Font.GothamBold
	lArrow.TextSize = 16
	lArrow.LayoutOrder = 1
	lArrow.Parent = sBody

	local lac = Instance.new("UICorner")
	lac.CornerRadius = UDim.new(0, 6)
	lac.Parent = lArrow

	local sGrid = Instance.new("Frame")
	sGrid.Name = "ShowcaseSlots"
	sGrid.Size = UDim2.new(1, -56, 1, 0)
	sGrid.BackgroundTransparency = 1
	sGrid.LayoutOrder = 2
	sGrid.Parent = sBody

	local sgl = Instance.new("UIGridLayout")
	sgl.CellSize = UDim2.new(0.3333, -4, 1, 0)
	sgl.CellPadding = UDim2.new(0, 6, 0, 0)
	sgl.SortOrder = Enum.SortOrder.LayoutOrder
	sgl.Parent = sGrid

	local rArrow = Instance.new("TextButton")
	rArrow.Size = UDim2.new(0, 24, 1, 0)
	rArrow.BackgroundColor3 = THEME.InsetBg
	rArrow.BorderSizePixel = 0
	rArrow.Text = ">"
	rArrow.TextColor3 = THEME.GoldPrimary
	rArrow.Font = Enum.Font.GothamBold
	rArrow.TextSize = 16
	rArrow.LayoutOrder = 3
	rArrow.Parent = sBody

	local rac = Instance.new("UICorner")
	rac.CornerRadius = UDim.new(0, 6)
	rac.Parent = rArrow

	local btmRow = Instance.new("Frame")
	btmRow.Name = "BottomRow"
	btmRow.Size = UDim2.new(1, 0, 0.56, -4)
	btmRow.BackgroundTransparency = 1
	btmRow.LayoutOrder = 2
	btmRow.Parent = bodyContainer

	local btmList = Instance.new("UIListLayout")
	btmList.FillDirection = Enum.FillDirection.Horizontal
	btmList.SortOrder = Enum.SortOrder.LayoutOrder
	btmList.Padding = UDim.new(0, 8)
	btmList.Parent = btmRow

	local invBox = buildQuadrantShell(btmRow, "Inventory", UDim2.new(0.30, -3, 1, 0), 1, THEME.StrokeSubtle, THEME.CardBg)
	buildSectionHeader(invBox, "INVENTORY", "CLICK DIE TO SELECT", THEME.GoldPrimary)

	local igFrame = Instance.new("ScrollingFrame")
	igFrame.Name = "InventoryGrid"
	igFrame.Size = UDim2.new(1, 0, 1, -26)
	igFrame.BackgroundTransparency = 1
	igFrame.BorderSizePixel = 0
	igFrame.ScrollBarThickness = 3
	igFrame.ScrollBarImageColor3 = THEME.GoldPrimary
	igFrame.LayoutOrder = 2
	igFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	igFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	igFrame.Parent = invBox

	local igPad = Instance.new("UIPadding")
	igPad.PaddingTop = UDim.new(0, 4)
	igPad.PaddingBottom = UDim.new(0, 4)
	igPad.PaddingLeft = UDim.new(0, 4)
	igPad.PaddingRight = UDim.new(0, 4)
	igPad.Parent = igFrame

	local igl = Instance.new("UIGridLayout")
	igl.CellSize = UDim2.new(0.3333, -6, 0, 80)
	igl.CellPadding = UDim2.new(0, 6, 0, 6)
	igl.SortOrder = Enum.SortOrder.LayoutOrder
	igl.Parent = igFrame

	local traitsBox = buildQuadrantShell(btmRow, "TraitsSection", UDim2.new(0.70, -5, 1, 0), 2, THEME.StrokeSubtle, THEME.CardBg)
	buildSectionHeader(traitsBox, "TRAIT FORGE & INSPECTION", "ACTIVE", THEME.GoldPrimary)

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

	local dieBox = Instance.new("Frame")
	dieBox.Name = "DieReceptacle"
	dieBox.Size = UDim2.new(1, 0, 0.40, 0)
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
	dbs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	dbs.Parent = dieBox

	local focusedDieVpContainer = Instance.new("Frame")
	focusedDieVpContainer.Size = UDim2.fromScale(1, 1)
	focusedDieVpContainer.BackgroundTransparency = 1
	focusedDieVpContainer.Parent = dieBox

	local focusedDieTag = Instance.new("TextLabel")
	focusedDieTag.Size = UDim2.new(0.90, 0, 0, 18)
	focusedDieTag.Position = UDim2.new(0, 8, 0, 4)
	focusedDieTag.BackgroundTransparency = 1
	focusedDieTag.Text = SLOTS_CANONICAL_NAMES[selectedInventoryShape] or "Foundry Obsidian"
	focusedDieTag.TextColor3 = THEME.GoldPrimary
	focusedDieTag.Font = Enum.Font.GothamBold
	focusedDieTag.TextSize = 12
	focusedDieTag.TextXAlignment = Enum.TextXAlignment.Left
	focusedDieTag.Parent = dieBox

	local equipToSlotBtn = Instance.new("TextButton")
	equipToSlotBtn.Name = "EquipToSlotBtn"
	equipToSlotBtn.Size = UDim2.new(1, 0, 0, 28)
	equipToSlotBtn.BackgroundColor3 = THEME.GoldPrimary
	equipToSlotBtn.BorderSizePixel = 0
	equipToSlotBtn.Text = "EQUIP TO SLOT 01"
	equipToSlotBtn.TextColor3 = THEME.TextDark
	equipToSlotBtn.Font = Enum.Font.GothamBold
	equipToSlotBtn.TextSize = 11
	equipToSlotBtn.LayoutOrder = 2
	equipToSlotBtn.Parent = leftCol

	local etc = Instance.new("UICorner")
	etc.CornerRadius = UDim.new(0, 5)
	etc.Parent = equipToSlotBtn

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

		local bCorner = Instance.new("UICorner")
		bCorner.CornerRadius = UDim.new(0, 6)
		bCorner.Parent = card

		local bStroke = Instance.new("UIStroke")
		bStroke.Color = THEME.StrokeSubtle
		bStroke.Thickness = 1
		bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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

		return card
	end

	local boostRow = Instance.new("Frame")
	boostRow.Name = "BoostRow"
	boostRow.Size = UDim2.new(1, 0, 0.24, -2)
	boostRow.BackgroundTransparency = 1
	boostRow.LayoutOrder = 3
	boostRow.Parent = leftCol

	local brList = Instance.new("UIListLayout")
	brList.FillDirection = Enum.FillDirection.Horizontal
	brList.SortOrder = Enum.SortOrder.LayoutOrder
	brList.Padding = UDim.new(0, 4)
	brList.Parent = boostRow

	local b1 = makeBoostCard(1, "BOOST 1", "--", THEME.TextMuted)
	b1.Parent = boostRow
	local b2 = makeBoostCard(2, "BOOST 2", "--", THEME.TextMuted)
	b2.Parent = boostRow

	local shardDeck = Instance.new("Frame")
	shardDeck.Name = "ShardDeck"
	shardDeck.Size = UDim2.new(1, 0, 0.24, -4)
	shardDeck.BackgroundColor3 = THEME.InsetBg
	shardDeck.BorderSizePixel = 0
	shardDeck.LayoutOrder = 4
	shardDeck.Parent = leftCol

	local sdc = Instance.new("UICorner")
	sdc.CornerRadius = UDim.new(0, 6)
	sdc.Parent = shardDeck

	local sds = Instance.new("UIStroke")
	sds.Color = THEME.StrokeSubtle
	sds.Thickness = 1
	sds.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sds.Parent = shardDeck

	local sPad = Instance.new("UIPadding")
	sPad.PaddingLeft = UDim.new(0, 6)
	sPad.PaddingRight = UDim.new(0, 6)
	sPad.PaddingTop = UDim.new(0, 2)
	sPad.PaddingBottom = UDim.new(0, 2)
	sPad.Parent = shardDeck

	local sList = Instance.new("UIListLayout")
	sList.FillDirection = Enum.FillDirection.Horizontal
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.VerticalAlignment = Enum.VerticalAlignment.Center
	sList.Parent = shardDeck

	local shardValLbl = Instance.new("TextLabel")
	shardValLbl.Size = UDim2.new(0.50, 0, 1, 0)
	shardValLbl.BackgroundTransparency = 1
	shardValLbl.Text = "◆ -- SHARDS"
	shardValLbl.TextColor3 = THEME.GoldPrimary
	shardValLbl.Font = Enum.Font.GothamBold
	shardValLbl.TextSize = 10
	shardValLbl.TextXAlignment = Enum.TextXAlignment.Left
	shardValLbl.Parent = shardDeck

	local rollBtn = Instance.new("TextButton")
	rollBtn.Name = "RollButton"
	rollBtn.Size = UDim2.new(0.48, 0, 0.85, 0)
	rollBtn.BackgroundColor3 = THEME.ButtonDark
	rollBtn.BorderSizePixel = 0
	rollBtn.Text = "REROLL"
	rollBtn.TextColor3 = THEME.TextMuted
	rollBtn.Font = Enum.Font.GothamBold
	rollBtn.TextSize = 10.5
	rollBtn.Parent = shardDeck

	local rbc = Instance.new("UICorner")
	rbc.CornerRadius = UDim.new(0, 4)
	rbc.Parent = rollBtn

	local rbs = Instance.new("UIStroke")
	rbs.Color = THEME.StrokeSubtle
	rbs.Thickness = 1
	rbs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rbs.Parent = rollBtn

	setTraitControlInert(rollBtn)

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
	rcStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
	rList.Padding = UDim.new(0, 4)
	rList.Parent = rightCol

	local t1Container = Instance.new("Frame")
	t1Container.Name = "Trait1_Container"
	t1Container.Size = UDim2.new(1, 0, 0.44, -4)
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
	t1s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	t1s.Parent = t1Container

	local t1Pad = Instance.new("UIPadding")
	t1Pad.PaddingLeft = UDim.new(0, 8)
	t1Pad.PaddingRight = UDim.new(0, 8)
	t1Pad.PaddingTop = UDim.new(0, 4)
	t1Pad.PaddingBottom = UDim.new(0, 4)
	t1Pad.Parent = t1Container

	local t1List = Instance.new("UIListLayout")
	t1List.FillDirection = Enum.FillDirection.Vertical
	t1List.SortOrder = Enum.SortOrder.LayoutOrder
	t1List.Padding = UDim.new(0, 2)
	t1List.Parent = t1Container

	local t1Head = Instance.new("Frame")
	t1Head.Size = UDim2.new(1, 0, 0, 18)
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
	t1Title.Size = UDim2.new(1, -26, 1, 0)
	t1Title.BackgroundTransparency = 1
	t1Title.Text = "TRAIT 1: NOT YET AVAILABLE"
	t1Title.TextColor3 = THEME.TextMuted
	t1Title.Font = Enum.Font.GothamBold
	t1Title.TextSize = 10.5
	t1Title.TextTruncate = Enum.TextTruncate.AtEnd
	t1Title.TextXAlignment = Enum.TextXAlignment.Left
	t1Title.LayoutOrder = 2
	t1Title.Parent = t1Head

	local t1Desc = Instance.new("TextLabel")
	t1Desc.Size = UDim2.new(1, 0, 0, 24)
	t1Desc.BackgroundTransparency = 1
	t1Desc.Text = "Trait enhancements unlock in upcoming updates."
	t1Desc.TextColor3 = THEME.TextMuted
	t1Desc.Font = Enum.Font.GothamMedium
	t1Desc.TextSize = 9.5
	t1Desc.TextWrapped = true
	t1Desc.TextYAlignment = Enum.TextYAlignment.Top
	t1Desc.TextXAlignment = Enum.TextXAlignment.Left
	t1Desc.LayoutOrder = 2
	t1Desc.Parent = t1Container

	local t2Container = Instance.new("Frame")
	t2Container.Name = "Trait2_Container"
	t2Container.Size = UDim2.new(1, 0, 0.44, -4)
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
	t2s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	t2s.Parent = t2Container

	local t2Pad = Instance.new("UIPadding")
	t2Pad.PaddingLeft = UDim.new(0, 8)
	t2Pad.PaddingRight = UDim.new(0, 8)
	t2Pad.PaddingTop = UDim.new(0, 4)
	t2Pad.PaddingBottom = UDim.new(0, 4)
	t2Pad.Parent = t2Container

	local t2List = Instance.new("UIListLayout")
	t2List.FillDirection = Enum.FillDirection.Vertical
	t2List.SortOrder = Enum.SortOrder.LayoutOrder
	t2List.Padding = UDim.new(0, 2)
	t2List.Parent = t2Container

	local t2Head = Instance.new("Frame")
	t2Head.Size = UDim2.new(1, 0, 0, 18)
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
	t2Title.Size = UDim2.new(1, -26, 1, 0)
	t2Title.BackgroundTransparency = 1
	t2Title.Text = "TRAIT 2: NOT YET AVAILABLE"
	t2Title.TextColor3 = THEME.TextMuted
	t2Title.Font = Enum.Font.GothamBold
	t2Title.TextSize = 10.5
	t2Title.TextTruncate = Enum.TextTruncate.AtEnd
	t2Title.TextXAlignment = Enum.TextXAlignment.Left
	t2Title.LayoutOrder = 2
	t2Title.Parent = t2Head

	local t2Desc = Instance.new("TextLabel")
	t2Desc.Size = UDim2.new(1, 0, 0, 24)
	t2Desc.BackgroundTransparency = 1
	t2Desc.Text = "Trait enhancements unlock in upcoming updates."
	t2Desc.TextColor3 = THEME.TextMuted
	t2Desc.Font = Enum.Font.GothamMedium
	t2Desc.TextSize = 9.5
	t2Desc.TextWrapped = true
	t2Desc.TextYAlignment = Enum.TextYAlignment.Top
	t2Desc.TextXAlignment = Enum.TextXAlignment.Left
	t2Desc.LayoutOrder = 2
	t2Desc.Parent = t2Container

	local actFooter = Instance.new("Frame")
	actFooter.Size = UDim2.new(1, 0, 0, 28)
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
	keepBtn.TextColor3 = THEME.TextMuted
	keepBtn.Font = Enum.Font.GothamBold
	keepBtn.TextSize = 11
	keepBtn.LayoutOrder = 1
	keepBtn.Parent = actFooter

	local kbc = Instance.new("UICorner")
	kbc.CornerRadius = UDim.new(0, 6)
	kbc.Parent = keepBtn

	local kbs = Instance.new("UIStroke")
	kbs.Color = THEME.StrokeSubtle
	kbs.Thickness = 1
	kbs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	kbs.Parent = keepBtn

	setTraitControlInert(keepBtn)

	local rerollAllBtn = Instance.new("TextButton")
	rerollAllBtn.Name = "RerollAllButton"
	rerollAllBtn.Size = UDim2.new(0.50, -3, 1, 0)
	rerollAllBtn.BackgroundColor3 = THEME.ButtonDark
	rerollAllBtn.BorderSizePixel = 0
	rerollAllBtn.Text = "REROLL ALL"
	rerollAllBtn.TextColor3 = THEME.TextMuted
	rerollAllBtn.Font = Enum.Font.GothamBold
	rerollAllBtn.TextSize = 11
	rerollAllBtn.LayoutOrder = 2
	rerollAllBtn.Parent = actFooter

	local rabc = Instance.new("UICorner")
	rabc.CornerRadius = UDim.new(0, 6)
	rabc.Parent = rerollAllBtn

	local rabs = Instance.new("UIStroke")
	rabs.Color = THEME.StrokeSubtle
	rabs.Thickness = 1
	rabs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rabs.Parent = rerollAllBtn

	setTraitControlInert(rerollAllBtn)

	local updateEquipButton: () -> ()

	local function updateFocusedDie(shapeId: string)
		selectedInventoryShape = shapeId
		focusedDieTag.Text = SLOTS_CANONICAL_NAMES[shapeId] or shapeId

		for _, child in ipairs(focusedDieVpContainer:GetChildren()) do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end

		pruneDeadViewportItems()

		createMiniDieViewport(focusedDieVpContainer, UDim2.fromScale(1, 1), shapeId, THEME.InsetBg)
		if updateEquipButton then
			updateEquipButton()
		end
	end

	updateEquipButton = function()
		local currentDie = liveEquippedDice[selectedSlotIndex]
		local isCurrent = (currentDie ~= nil and currentDie.shape == selectedInventoryShape)

		local ownedTotal = if type(playerInventory) == "table" then (tonumber(playerInventory[selectedInventoryShape]) or 0) else 0
		local inUseCount = 0
		for i, d in ipairs(liveEquippedDice) do
			if i ~= selectedSlotIndex and d and d.shape == selectedInventoryShape then
				inUseCount += 1
			end
		end
		local canEquipThisShape = (inUseCount + 1 <= ownedTotal)

		if currentDie == nil then
			if canEquipThisShape then
				equipToSlotBtn.Text = string.format("EQUIP %s TO SLOT %02d", selectedInventoryShape, selectedSlotIndex)
				equipToSlotBtn.BackgroundColor3 = THEME.GoldPrimary
				equipToSlotBtn.TextColor3 = THEME.TextDark
				equipToSlotBtn.AutoButtonColor = true
			else
				equipToSlotBtn.Text = string.format("[ 0 %s AVAILABLE ]", selectedInventoryShape)
				equipToSlotBtn.BackgroundColor3 = THEME.ButtonDark
				equipToSlotBtn.TextColor3 = THEME.TextMuted
				equipToSlotBtn.AutoButtonColor = false
			end
		elseif isCurrent then
			equipToSlotBtn.Text = string.format("[ %s IN SLOT %02d ]", selectedInventoryShape, selectedSlotIndex)
			equipToSlotBtn.BackgroundColor3 = THEME.ButtonDark
			equipToSlotBtn.TextColor3 = THEME.Positive
			equipToSlotBtn.AutoButtonColor = false
		else
			if canEquipThisShape then
				equipToSlotBtn.Text = string.format("CHANGE TO %s (SLOT %02d)", selectedInventoryShape, selectedSlotIndex)
				equipToSlotBtn.BackgroundColor3 = THEME.GoldPrimary
				equipToSlotBtn.TextColor3 = THEME.TextDark
				equipToSlotBtn.AutoButtonColor = true
			else
				equipToSlotBtn.Text = string.format("[ 0 %s AVAILABLE ]", selectedInventoryShape)
				equipToSlotBtn.BackgroundColor3 = THEME.ButtonDark
				equipToSlotBtn.TextColor3 = THEME.TextMuted
				equipToSlotBtn.AutoButtonColor = false
			end
		end
	end

	local equipInFlight = false
	equipToSlotBtn.MouseButton1Click:Connect(function()
		if equipInFlight then return end
		local currentDie = liveEquippedDice[selectedSlotIndex]
		if currentDie and currentDie.shape == selectedInventoryShape then
			return
		end

		local ownedTotal = if type(playerInventory) == "table" then (tonumber(playerInventory[selectedInventoryShape]) or 0) else 0
		local inUseCount = 0
		for i, d in ipairs(liveEquippedDice) do
			if i ~= selectedSlotIndex and d and d.shape == selectedInventoryShape then
				inUseCount += 1
			end
		end
		if inUseCount + 1 > ownedTotal then
			return
		end

		equipInFlight = true
		equipToSlotBtn.Text = "EQUIPPING..."
		local targetSlot = if selectedSlotIndex <= #liveEquippedDice
			then selectedSlotIndex
			else math.min(selectedSlotIndex, #liveEquippedDice + 1)

		task.spawn(function()
			local result = NetClient.setShape(targetSlot, selectedInventoryShape)
			equipInFlight = false
			updateEquipButton()
		end)
	end)

	updateFocusedDie("D2")

	local rebuildShowcaseSlots: () -> ()
	local rebuildInventory: () -> ()

	rebuildShowcaseSlots = function()
		for _, child in ipairs(sGrid:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local pageCount = slotPageCount()
		if currentSlotPage > pageCount then
			currentSlotPage = pageCount
		end
		if currentSlotPage < 1 then
			currentSlotPage = 1
		end

		local startIdx = (currentSlotPage - 1) * SLOTS_PER_PAGE + 1
		for i = 1, SLOTS_PER_PAGE do
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
			bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			bs.Parent = bay

			if isUnlocked and dieInfo then
				local vpBox = Instance.new("Frame")
				vpBox.Size = UDim2.new(1, 0, 0.52, 0)
				vpBox.BackgroundTransparency = 1
				vpBox.Parent = bay
				createMiniDieViewport(vpBox, UDim2.fromScale(1, 1), dieInfo.shape, THEME.InsetBg)

				local removeBtn = Instance.new("TextButton")
				removeBtn.Name = "RemoveBtn"
				removeBtn.Size = UDim2.fromOffset(26, 26)
				removeBtn.Position = UDim2.new(1, -30, 0, 4)
				removeBtn.BackgroundColor3 = THEME.ButtonDark
				removeBtn.BorderSizePixel = 0
				removeBtn.Text = "X"
				removeBtn.TextColor3 = if #liveEquippedDice > 1 then THEME.Negative else THEME.TextMuted
				removeBtn.Font = Enum.Font.GothamBold
				removeBtn.TextSize = 14
				removeBtn.Active = (#liveEquippedDice > 1)
				removeBtn.AutoButtonColor = (#liveEquippedDice > 1)
				removeBtn.ZIndex = 8
				removeBtn.Parent = bay

				local rbc = Instance.new("UICorner")
				rbc.CornerRadius = UDim.new(0, 6)
				rbc.Parent = removeBtn

				local rbs = Instance.new("UIStroke")
				rbs.Color = if #liveEquippedDice > 1 then THEME.Negative else THEME.StrokeSubtle
				rbs.Thickness = 1
				rbs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				rbs.Parent = removeBtn

				if #liveEquippedDice > 1 then
					removeBtn.MouseButton1Click:Connect(function()
						task.spawn(function()
							NetClient.unequipDie(slotNum)
						end)
					end)
				end

				local bTitle = Instance.new("TextLabel")
				bTitle.Size = UDim2.new(1, 0, 0, 18)
				bTitle.Position = UDim2.new(0, 0, 0.56, 0)
				bTitle.BackgroundTransparency = 1
				bTitle.Text = string.format("SLOT %02d: %s", slotNum, dieInfo.shape)
				bTitle.TextColor3 = THEME.GoldPrimary
				bTitle.Font = Enum.Font.GothamBold
				bTitle.TextSize = 12
				bTitle.Parent = bay

				local bSub = Instance.new("TextLabel")
				bSub.Size = UDim2.new(1, 0, 0, 16)
				bSub.Position = UDim2.new(0, 0, 0.76, 0)
				bSub.BackgroundTransparency = 1
				bSub.Text = if isSelected then "[ SELECTED ]" else "EQUIPPED"
				bSub.TextColor3 = if isSelected then THEME.GoldPrimary else THEME.Positive
				bSub.Font = Enum.Font.GothamBold
				bSub.TextSize = 11
				bSub.Parent = bay

				local clickBtn = Instance.new("TextButton")
				clickBtn.Size = UDim2.fromScale(1, 1)
				clickBtn.BackgroundTransparency = 1
				clickBtn.Text = ""
				clickBtn.Parent = bay

				clickBtn.MouseButton1Click:Connect(function()
					selectedSlotIndex = slotNum
					selectedInventoryShape = dieInfo.shape
					updateFocusedDie(dieInfo.shape)
					rebuildShowcaseSlots()
					rebuildInventory()
					updateEquipButton()
				end)
			elseif isUnlocked then
				local bTitle = Instance.new("TextLabel")
				bTitle.Size = UDim2.new(1, 0, 0, 18)
				bTitle.Position = UDim2.new(0, 0, 0.42, 0)
				bTitle.BackgroundTransparency = 1
				bTitle.Text = string.format("SLOT %02d (EMPTY)", slotNum)
				bTitle.TextColor3 = THEME.TextMuted
				bTitle.Font = Enum.Font.GothamBold
				bTitle.TextSize = 11
				bTitle.Parent = bay

				local clickBtn = Instance.new("TextButton")
				clickBtn.Size = UDim2.fromScale(1, 1)
				clickBtn.BackgroundTransparency = 1
				clickBtn.Text = ""
				clickBtn.Parent = bay

				clickBtn.MouseButton1Click:Connect(function()
					selectedSlotIndex = slotNum
					rebuildShowcaseSlots()
					rebuildInventory()
					updateEquipButton()
				end)
			else
				local nextCost = DiceCatalog.dieSlotCost(slotNum - 1, ascensionsCount, slotNodesCount)
				local isNextBuyable = (slotNum == unlockedSlotsCount + 1 and nextCost ~= nil)

				local lockedLbl = Instance.new("TextLabel")
				lockedLbl.Size = UDim2.new(1, 0, 0, 16)
				lockedLbl.Position = UDim2.new(0, 0, 0, 6)
				lockedLbl.BackgroundTransparency = 1
				lockedLbl.Text = string.format("[ LOCKED SLOT %02d ]", slotNum)
				lockedLbl.TextColor3 = THEME.TextMuted
				lockedLbl.Font = Enum.Font.GothamBold
				lockedLbl.TextSize = 11
				lockedLbl.Parent = bay

				if isNextBuyable and nextCost then
					local unlockBtn = Instance.new("TextButton")
					unlockBtn.Size = UDim2.new(0.85, 0, 0, 28)
					unlockBtn.Position = UDim2.new(0.075, 0, 0.52, -14)
					unlockBtn.BackgroundColor3 = if currentCash >= nextCost then THEME.GoldPrimary else THEME.ButtonDark
					unlockBtn.BorderSizePixel = 0
					unlockBtn.Text = string.format("UNLOCK ($%s)", Format.formatNumber(nextCost))
					unlockBtn.TextColor3 = if currentCash >= nextCost then THEME.TextDark else THEME.Negative
					unlockBtn.Font = Enum.Font.GothamBold
					unlockBtn.TextSize = 10.5
					unlockBtn.Parent = bay

					local uc = Instance.new("UICorner")
					uc.CornerRadius = UDim.new(0, 4)
					uc.Parent = unlockBtn

					local unlocking = false
					unlockBtn.MouseButton1Click:Connect(function()
						if unlocking or currentCash < nextCost then return end
						unlocking = true
						unlockBtn.Text = "UNLOCKING..."
						task.spawn(function()
							NetClient.addDieSlot("")
							unlocking = false
						end)
					end)
				else
					local subLbl = Instance.new("TextLabel")
					subLbl.Size = UDim2.new(1, 0, 0, 16)
					subLbl.Position = UDim2.new(0, 0, 0.55, 0)
					subLbl.BackgroundTransparency = 1
					subLbl.Text = if nextCost == nil then "REACH ASCENSION" else "UNLOCK PREVIOUS"
					subLbl.TextColor3 = THEME.TextMuted
					subLbl.Font = Enum.Font.Code
					subLbl.TextSize = 9.5
					subLbl.Parent = bay
				end
			end
		end

		if pageTagLbl then
			local totalSlots = math.max(DiceCatalog.dieSlotCapFor(ascensionsCount, slotNodesCount), unlockedSlotsCount, #liveEquippedDice, 1)
			local endIdx = math.min(startIdx + SLOTS_PER_PAGE - 1, totalSlots)
			pageTagLbl.Text = string.format("SLOTS %02d - %02d  [PAGE %d/%d]",
				startIdx, endIdx, currentSlotPage, pageCount)
		end

		lArrow.TextColor3 = if currentSlotPage > 1 then THEME.GoldPrimary else THEME.StrokeSubtle
		rArrow.TextColor3 = if currentSlotPage < pageCount then THEME.GoldPrimary else THEME.StrokeSubtle
	end

	lArrow.MouseButton1Click:Connect(function()
		if currentSlotPage > 1 then
			currentSlotPage -= 1
			rebuildShowcaseSlots()
		end
	end)

	rArrow.MouseButton1Click:Connect(function()
		if currentSlotPage < slotPageCount() then
			currentSlotPage += 1
			rebuildShowcaseSlots()
		end
	end)

	rebuildInventory = function()
		for _, child in ipairs(igFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		pruneDeadViewportItems()

		local equippedCounts: { [string]: number } = {}
		for _, d in ipairs(liveEquippedDice) do
			if d and d.shape then
				equippedCounts[d.shape] = (equippedCounts[d.shape] or 0) + 1
			end
		end

		local invList: { { shape: string, count: number } } = {}
		for shapeId, totalCount in pairs(playerInventory) do
			if type(totalCount) == "number" and totalCount > 0 then
				local inUse = equippedCounts[shapeId] or 0
				local available = math.max(0, totalCount - inUse)
				if available > 0 then
					table.insert(invList, {
						shape = shapeId,
						count = available,
					})
				end
			end
		end

		table.sort(invList, function(a, b)
			local order = { D2=1, D3=2, D4=3, D5=4, D6=5, D7=6, D8=7, D10=8, D12=9, D14=10, D16=11, D20=12 }
			return (order[a.shape] or 99) < (order[b.shape] or 99)
		end)

		local selectedExists = false
		for _, item in ipairs(invList) do
			if item.shape == selectedInventoryShape then
				selectedExists = true
				break
			end
		end
		if not selectedExists and #invList > 0 then
			selectedInventoryShape = invList[1].shape
			updateFocusedDie(selectedInventoryShape)
		end

		for idx, item in ipairs(invList) do
			local isSelected = (item.shape == selectedInventoryShape)

			local c = Instance.new("Frame")
			c.Name = "InvCard_" .. item.shape
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
			cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cs.Parent = c

			createMiniDieViewport(c, UDim2.fromScale(1, 1), item.shape, THEME.InsetBg)

			local nameTag = Instance.new("TextLabel")
			nameTag.Name = "ShapeTag"
			nameTag.Size = UDim2.new(0, 36, 0, 18)
			nameTag.Position = UDim2.new(0, 4, 0, 4)
			nameTag.BackgroundColor3 = THEME.ModalBg
			nameTag.BorderSizePixel = 0
			nameTag.Text = item.shape
			nameTag.TextColor3 = THEME.GoldPrimary
			nameTag.Font = Enum.Font.GothamBold
			nameTag.TextSize = 11
			nameTag.Parent = c

			local ntC = Instance.new("UICorner")
			ntC.CornerRadius = UDim.new(0, 4)
			ntC.Parent = nameTag

			if item.count > 1 then
				local badge = Instance.new("TextLabel")
				badge.Name = "CountBadge"
				badge.Size = UDim2.new(0, 32, 0, 18)
				badge.Position = UDim2.new(1, -36, 1, -22)
				badge.BackgroundColor3 = THEME.ModalBg
				badge.BorderSizePixel = 0
				badge.Text = "x" .. item.count
				badge.TextColor3 = THEME.GoldPrimary
				badge.Font = Enum.Font.GothamBold
				badge.TextSize = 11
				badge.Parent = c

				local bc2 = Instance.new("UICorner")
				bc2.CornerRadius = UDim.new(0, 4)
				bc2.Parent = badge

				local bs2 = Instance.new("UIStroke")
				bs2.Color = THEME.StrokeGold
				bs2.Thickness = 1
				bs2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				bs2.Parent = badge
			end

			if isSelected then
				local selPill = Instance.new("TextLabel")
				selPill.Size = UDim2.new(1, 0, 0, 16)
				selPill.Position = UDim2.new(0, 0, 1, -16)
				selPill.BackgroundColor3 = THEME.GoldPrimary
				selPill.BorderSizePixel = 0
				selPill.Text = "SELECTED"
				selPill.TextColor3 = THEME.TextDark
				selPill.Font = Enum.Font.GothamBlack
				selPill.TextSize = 9.5
				selPill.Parent = c
			end

			local invBtn = Instance.new("TextButton")
			invBtn.Size = UDim2.fromScale(1, 1)
			invBtn.BackgroundTransparency = 1
			invBtn.Text = ""
			invBtn.Parent = c

			invBtn.MouseButton1Click:Connect(function()
				selectedInventoryShape = item.shape
				updateFocusedDie(item.shape)
				rebuildInventory()
				updateEquipButton()
			end)
		end
	end

	rebuildOrreryChamber()
	rebuildShowcaseSlots()
	rebuildInventory()
	if updateEquipButton then
		updateEquipButton()
	end

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
			currentCash = tonumber(state.cash) or 0
			ascensionsCount = tonumber(state.ascensions) or 0
			slotNodesCount = if type(state.diamondTree) == "table"
				then tonumber(state.diamondTree.SlotNodes) or 0
				else 0
			unlockedSlotsCount = tonumber(state.dieSlots) or 1

			if type(state.diamondTree) == "table" and type(state.diamondTree.Shapes) == "table" then
				ownedShapesMap = state.diamondTree.Shapes
			end

			if type(state.inventory) == "table" then
				playerInventory = state.inventory
			elseif type(state.diamondTree) == "table" and type(state.diamondTree.Shapes) == "table" then
				playerInventory = {}
				for s, owned in pairs(state.diamondTree.Shapes) do
					if owned == true then
						playerInventory[s] = 1
					end
				end
			end

			liveEquippedDice = {}
			if type(state.dice) == "table" and #state.dice > 0 then
				for _, d in ipairs(state.dice) do
					table.insert(liveEquippedDice, {
						shape = tostring(d.Shape or "D2"),
						mass = tonumber(d.MassBudget) or 60,
					})
				end
			end
			if #liveEquippedDice == 0 then
				table.insert(liveEquippedDice, { shape = "D2", mass = 60 })
			end

			if selectedSlotIndex > unlockedSlotsCount then
				selectedSlotIndex = math.max(1, unlockedSlotsCount)
			end
			if liveEquippedDice[selectedSlotIndex] then
				selectedInventoryShape = liveEquippedDice[selectedSlotIndex].shape
				updateFocusedDie(selectedInventoryShape)
			end
		end

		rebuildOrreryChamber()
		rebuildShowcaseSlots()
		rebuildInventory()
		if updateEquipButton then
			updateEquipButton()
		end
	end

	return refreshSlots
end

-- ------------------------------
-- 7. LEADERBOARDS OVERLAY (BRUTALIST KINETIC MONOLITH - L-065/L-066)
-- ------------------------------

local function createBoardsAvatar(parent: Instance, size: UDim2, initial: string, accentColor: Color3, isPlayer: boolean): (Frame, TextLabel)
	local avatar = Instance.new("Frame")
	avatar.Name = "AvatarMonogram"
	avatar.Size = size
	avatar.BackgroundColor3 = if isPlayer then Color3.fromRGB(38, 30, 20) else THEME.InsetBg
	avatar.BorderSizePixel = 0
	avatar.Parent = parent

	local avCorner = Instance.new("UICorner")
	avCorner.CornerRadius = UDim.new(0, 6)
	avCorner.Parent = avatar

	local avStroke = Instance.new("UIStroke")
	avStroke.Color = if isPlayer then THEME.GoldPrimary else THEME.StrokeSubtle
	avStroke.Thickness = if isPlayer then 1.5 else 1
	avStroke.Parent = avatar

	local initLbl = Instance.new("TextLabel")
	initLbl.Name = "InitLabel"
	initLbl.Size = UDim2.fromScale(1, 1)
	initLbl.BackgroundTransparency = 1
	initLbl.Text = string.sub(initial, 1, 1):upper()
	initLbl.TextColor3 = accentColor
	initLbl.Font = Enum.Font.GothamBold
	initLbl.TextSize = 12
	initLbl.Parent = avatar

	return avatar, initLbl
end

local function getRankClass(rank: number, boardId: string): string
	if rank == 1 then
		return if boardId == "Ascensions" then "SOVEREIGN" elseif boardId == "HighestRoll" then "RECORD" else "CHAMPION"
	elseif rank == 2 then
		return if boardId == "Ascensions" then "IMMORTAL" elseif boardId == "HighestRoll" then "ELITE" else "GRANDMASTER"
	elseif rank == 3 then
		return if boardId == "Ascensions" then "ASCENDED" elseif boardId == "HighestRoll" then "ELITE" else "HIGH ROLLER"
	elseif rank <= 5 then
		return if boardId == "Ascensions" then "EXALTED" elseif boardId == "HighestRoll" then "EXPERT" else "MASTER"
	elseif rank <= 8 then
		return if boardId == "Ascensions" then "RISEN" elseif boardId == "HighestRoll" then "SHARP" else "FORGER"
	elseif rank <= 12 then
		return if boardId == "Ascensions" then "AWAKENED" elseif boardId == "HighestRoll" then "ROLLER" else "ADEPT"
	elseif rank <= 20 then
		return if boardId == "Ascensions" then "AWAKENED" elseif boardId == "HighestRoll" then "ROLLER" else "APPRENTICE"
	else
		return "INITIATE"
	end
end

local function formatBoardScore(boardId: string, rawVal: number): string
	if boardId == "NetWorth" then
		return "$" .. Format.formatNumber(rawVal)
	elseif boardId == "HighestRoll" then
		return Format.formatNumber(rawVal) .. " pts"
	elseif boardId == "Ascensions" then
		return Format.formatNumber(rawVal) .. " Ascensions"
	else
		return Format.formatNumber(rawVal)
	end
end

local function buildBoardsOverlay(
	screenGui: ScreenGui,
	overlays: { [string]: Frame },
	getController: () -> any
): (string) -> ()
	local boardsOverlay, legacyBody = UITheme.overlay("Leaderboards")
	boardsOverlay.Parent = screenGui
	overlays["boards"] = boardsOverlay
	if legacyBody then legacyBody.Visible = false end

	local mainShell, boardsBody = formatModalShell(boardsOverlay, "GLOBAL LEADERBOARDS", getController)

	local BOARD_TABS: { { id: string, label: string, title: string } } = {
		{ id = "NetWorth", label = "NET WORTH", title = "LIFETIME NET WORTH" },
		{ id = "HighestRoll", label = "PEAK ROLL", title = "BEST SINGLE ROLL" },
		{ id = "Ascensions", label = "ASCENSIONS", title = "TOTAL ASCENSIONS" },
	}
	local activeBoard = "NetWorth"

	local SilverColor = Color3.fromRGB(203, 213, 225)
	local StrokeSilver = Color3.fromRGB(148, 163, 184)
	local BronzeColor = Color3.fromRGB(217, 119, 6)
	local StrokeBronze = Color3.fromRGB(180, 83, 9)
	local TextDark = Color3.fromRGB(24, 20, 18)

	local boardStack = Instance.new("Frame")
	boardStack.Name = "BoardStack"
	boardStack.Size = UDim2.fromScale(1, 1)
	boardStack.BackgroundTransparency = 1
	boardStack.Parent = boardsBody

	local bsList = Instance.new("UIListLayout")
	bsList.FillDirection = Enum.FillDirection.Vertical
	bsList.SortOrder = Enum.SortOrder.LayoutOrder
	bsList.Padding = UDim.new(0, 8)
	bsList.Parent = boardStack

	-- 1. BRUTALIST TAB STRIP
	local tabStrip = Instance.new("Frame")
	tabStrip.Name = "TabStrip"
	tabStrip.Size = UDim2.new(1, 0, 0, 30)
	tabStrip.BackgroundColor3 = THEME.InsetBg
	tabStrip.BorderSizePixel = 0
	tabStrip.LayoutOrder = 1
	tabStrip.Parent = boardStack

	local tsCorner = Instance.new("UICorner")
	tsCorner.CornerRadius = UDim.new(0, 4)
	tsCorner.Parent = tabStrip

	local tabCount = #BOARD_TABS
	local tabGutter = 6

	local tsList = Instance.new("UIListLayout")
	tsList.FillDirection = Enum.FillDirection.Horizontal
	tsList.SortOrder = Enum.SortOrder.LayoutOrder
	tsList.Padding = UDim.new(0, tabGutter)
	tsList.Parent = tabStrip

	local tsPad = Instance.new("UIPadding")
	tsPad.PaddingTop = UDim.new(0, 3)
	tsPad.PaddingBottom = UDim.new(0, 3)
	tsPad.PaddingLeft = UDim.new(0, 4)
	tsPad.PaddingRight = UDim.new(0, 4)
	tsPad.Parent = tabStrip

	local boardTabButtons: { [string]: TextButton } = {}
	local refreshBoards: (string) -> ()

	for i, tab in ipairs(BOARD_TABS) do
		local tBtn = Instance.new("TextButton")
		tBtn.Name = "Tab_" .. tab.id
		tBtn.Size = UDim2.new(1 / tabCount, -(tabGutter * (tabCount - 1)) / tabCount, 1, 0)
		tBtn.BackgroundColor3 = if tab.id == activeBoard then THEME.GoldPrimary else THEME.CardBg
		tBtn.Text = tab.label
		tBtn.TextColor3 = if tab.id == activeBoard then TextDark else THEME.TextMuted
		tBtn.Font = Enum.Font.GothamBlack
		tBtn.TextSize = 11
		tBtn.LayoutOrder = i
		tBtn.Parent = tabStrip

		local tbCorner = Instance.new("UICorner")
		tbCorner.CornerRadius = UDim.new(0, 4)
		tbCorner.Parent = tBtn

		boardTabButtons[tab.id] = tBtn

		tBtn.MouseButton1Click:Connect(function()
			activeBoard = tab.id
			local ctrl = getController()
			if ctrl ~= nil then
				ctrl.activeBoard = tab.id
			end
			refreshBoards(tab.id)
		end)
	end

	-- 2. MONOLITH TOP 3 PODIUMS
	local monolithRow = Instance.new("Frame")
	monolithRow.Name = "MonolithRow"
	monolithRow.Size = UDim2.new(1, 0, 0, 112)
	monolithRow.BackgroundTransparency = 1
	monolithRow.LayoutOrder = 2
	monolithRow.Parent = boardStack

	local mList = Instance.new("UIListLayout")
	mList.FillDirection = Enum.FillDirection.Horizontal
	mList.SortOrder = Enum.SortOrder.LayoutOrder
	mList.Padding = UDim.new(0, 8)
	mList.Parent = monolithRow

	type MonolithUI = {
		card: Frame,
		rankChip: TextLabel,
		classTag: TextLabel,
		avatarFrame: Frame,
		avatarInit: TextLabel,
		nameLabel: TextLabel,
		scoreLabel: TextLabel,
	}

	local monolithCards: { [number]: MonolithUI } = {}
	local cardConfigs = {
		{ rank = 2, rankStr = "02", color = SilverColor, stroke = StrokeSilver, order = 1, width = 0.31, height = 102 },
		{ rank = 1, rankStr = "01", color = THEME.GoldPrimary, stroke = THEME.StrokeGold, order = 2, width = 0.38, height = 112 },
		{ rank = 3, rankStr = "03", color = BronzeColor, stroke = StrokeBronze, order = 3, width = 0.31, height = 94 },
	}

	for _, cfg in ipairs(cardConfigs) do
		local mCard = Instance.new("Frame")
		mCard.Name = "Monolith_" .. cfg.rank
		mCard.Size = UDim2.new(cfg.width, -6, 0, cfg.height)
		mCard.BackgroundColor3 = if cfg.rank == 1 then Color3.fromRGB(36, 28, 22) else THEME.CardBg
		mCard.BorderSizePixel = 0
		mCard.LayoutOrder = cfg.order
		mCard.Parent = monolithRow

		local mcCorner = Instance.new("UICorner")
		mcCorner.CornerRadius = UDim.new(0, 6)
		mcCorner.Parent = mCard

		local mcStroke = Instance.new("UIStroke")
		mcStroke.Color = cfg.stroke
		mcStroke.Thickness = if cfg.rank == 1 then 2 else 1
		mcStroke.Parent = mCard

		local mcPad = Instance.new("UIPadding")
		mcPad.PaddingTop = UDim.new(0, 6)
		mcPad.PaddingBottom = UDim.new(0, 6)
		mcPad.PaddingLeft = UDim.new(0, 8)
		mcPad.PaddingRight = UDim.new(0, 8)
		mcPad.Parent = mCard

		local mcList = Instance.new("UIListLayout")
		mcList.FillDirection = Enum.FillDirection.Vertical
		mcList.SortOrder = Enum.SortOrder.LayoutOrder
		mcList.Padding = UDim.new(0, 2)
		mcList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		mcList.Parent = mCard

		local topBar = Instance.new("Frame")
		topBar.Size = UDim2.new(1, 0, 0, 18)
		topBar.BackgroundTransparency = 1
		topBar.LayoutOrder = 1
		topBar.Parent = mCard

		local rChip = Instance.new("TextLabel")
		rChip.Size = UDim2.new(0, 32, 0, 16)
		rChip.BackgroundColor3 = if cfg.rank == 1 then THEME.GoldPrimary else THEME.InsetBg
		rChip.Text = cfg.rankStr
		rChip.TextColor3 = if cfg.rank == 1 then TextDark else cfg.color
		rChip.Font = Enum.Font.GothamBlack
		rChip.TextSize = 10
		rChip.Parent = topBar

		local rcCorner = Instance.new("UICorner")
		rcCorner.CornerRadius = UDim.new(0, 3)
		rcCorner.Parent = rChip

		local tTag = Instance.new("TextLabel")
		tTag.Size = UDim2.new(1, -38, 1, 0)
		tTag.Position = UDim2.new(0, 38, 0, 0)
		tTag.BackgroundTransparency = 1
		tTag.Text = if cfg.rank == 1 then "SOVEREIGN" elseif cfg.rank == 2 then "IMMORTAL" else "ASCENDED"
		tTag.TextColor3 = cfg.color
		tTag.Font = Enum.Font.GothamBlack
		tTag.TextSize = 9
		tTag.TextXAlignment = Enum.TextXAlignment.Right
		tTag.Parent = topBar

		local nRow = Instance.new("Frame")
		nRow.Size = UDim2.new(1, 0, 0, 22)
		nRow.BackgroundTransparency = 1
		nRow.LayoutOrder = 2
		nRow.Parent = mCard

		local nrL = Instance.new("UIListLayout")
		nrL.FillDirection = Enum.FillDirection.Horizontal
		nrL.SortOrder = Enum.SortOrder.LayoutOrder
		nrL.Padding = UDim.new(0, 6)
		nrL.VerticalAlignment = Enum.VerticalAlignment.Center
		nrL.Parent = nRow

		local avFrame, avInit = createBoardsAvatar(nRow, UDim2.new(0, 20, 0, 20), "-", cfg.color, false)

		local nLbl = Instance.new("TextLabel")
		nLbl.Size = UDim2.new(1, -28, 1, 0)
		nLbl.BackgroundTransparency = 1
		nLbl.Text = "-"
		nLbl.TextColor3 = THEME.TextPrimary
		nLbl.Font = Enum.Font.GothamBlack
		nLbl.TextSize = if cfg.rank == 1 then 12 else 10.5
		nLbl.TextXAlignment = Enum.TextXAlignment.Left
		nLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nLbl.Parent = nRow

		local scBox = Instance.new("Frame")
		scBox.Size = UDim2.new(1, 0, 0, 28)
		scBox.BackgroundColor3 = THEME.InsetBg
		scBox.BorderSizePixel = 0
		scBox.LayoutOrder = 3
		scBox.Parent = mCard

		local scCorner = Instance.new("UICorner")
		scCorner.CornerRadius = UDim.new(0, 4)
		scCorner.Parent = scBox

		local scLbl = Instance.new("TextLabel")
		scLbl.Size = UDim2.fromScale(1, 1)
		scLbl.BackgroundTransparency = 1
		scLbl.Text = "-"
		scLbl.TextColor3 = cfg.color
		scLbl.Font = Enum.Font.GothamBlack
		scLbl.TextSize = if cfg.rank == 1 then 13.5 else 12
		scLbl.Parent = scBox

		monolithCards[cfg.rank] = {
			card = mCard,
			rankChip = rChip,
			classTag = tTag,
			avatarFrame = avFrame,
			avatarInit = avInit,
			nameLabel = nLbl,
			scoreLabel = scLbl,
		}
	end

	-- 3. BRUTALIST DATA STREAM (SCROLLING ROWS)
	local stream = Instance.new("Frame")
	stream.Name = "BrutalistStream"
	stream.Size = UDim2.new(1, 0, 1, -208)
	stream.BackgroundColor3 = Color3.fromRGB(28, 23, 19)
	stream.BorderSizePixel = 0
	stream.LayoutOrder = 3
	stream.Parent = boardStack

	local stCorner = Instance.new("UICorner")
	stCorner.CornerRadius = UDim.new(0, 6)
	stCorner.Parent = stream

	local stStroke = Instance.new("UIStroke")
	stStroke.Color = THEME.StrokeSubtle
	stStroke.Thickness = 1
	stStroke.Parent = stream

	local stHeader = Instance.new("Frame")
	stHeader.Name = "StreamHeader"
	stHeader.Size = UDim2.new(1, 0, 0, 22)
	stHeader.BackgroundColor3 = THEME.HeaderBg
	stHeader.BorderSizePixel = 0
	stHeader.Parent = stream

	local sthCorner = Instance.new("UICorner")
	sthCorner.CornerRadius = UDim.new(0, 6)
	sthCorner.Parent = stHeader

	local sthPad = Instance.new("UIPadding")
	sthPad.PaddingLeft = UDim.new(0, 10)
	sthPad.PaddingRight = UDim.new(0, 10)
	sthPad.Parent = stHeader

	local sthRank = Instance.new("TextLabel")
	sthRank.Size = UDim2.new(0, 44, 1, 0)
	sthRank.BackgroundTransparency = 1
	sthRank.Text = "TIER"
	sthRank.TextColor3 = THEME.TextSubtle
	sthRank.Font = Enum.Font.GothamBlack
	sthRank.TextSize = 9.5
	sthRank.TextXAlignment = Enum.TextXAlignment.Left
	sthRank.Parent = stHeader

	local sthUser = Instance.new("TextLabel")
	sthUser.Size = UDim2.new(0.40, 0, 1, 0)
	sthUser.Position = UDim2.new(0, 48, 0, 0)
	sthUser.BackgroundTransparency = 1
	sthUser.Text = "OPERATOR IDENT"
	sthUser.TextColor3 = THEME.TextSubtle
	sthUser.Font = Enum.Font.GothamBlack
	sthUser.TextSize = 9.5
	sthUser.TextXAlignment = Enum.TextXAlignment.Left
	sthUser.Parent = stHeader

	local sthScore = Instance.new("TextLabel")
	sthScore.Size = UDim2.new(0.32, 0, 1, 0)
	sthScore.Position = UDim2.new(0.48, 0, 0, 0)
	sthScore.BackgroundTransparency = 1
	sthScore.Text = "SCORE / VALUE"
	sthScore.TextColor3 = THEME.TextSubtle
	sthScore.Font = Enum.Font.GothamBlack
	sthScore.TextSize = 9.5
	sthScore.TextXAlignment = Enum.TextXAlignment.Right
	sthScore.Parent = stHeader

	local sthTag = Instance.new("TextLabel")
	sthTag.Size = UDim2.new(0.18, 0, 1, 0)
	sthTag.Position = UDim2.new(0.82, 0, 0, 0)
	sthTag.BackgroundTransparency = 1
	sthTag.Text = "CLASS"
	sthTag.TextColor3 = THEME.TextSubtle
	sthTag.Font = Enum.Font.GothamBlack
	sthTag.TextSize = 9.5
	sthTag.TextXAlignment = Enum.TextXAlignment.Right
	sthTag.Parent = stHeader

	local stScroll = Instance.new("ScrollingFrame")
	stScroll.Name = "StreamScroll"
	stScroll.Size = UDim2.new(1, 0, 1, -26)
	stScroll.Position = UDim2.new(0, 0, 0, 24)
	stScroll.BackgroundTransparency = 1
	stScroll.BorderSizePixel = 0
	stScroll.ScrollBarThickness = 4
	stScroll.ScrollBarImageColor3 = THEME.StrokeGold
	stScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	stScroll.Parent = stream

	local stsList = Instance.new("UIListLayout")
	stsList.FillDirection = Enum.FillDirection.Vertical
	stsList.SortOrder = Enum.SortOrder.LayoutOrder
	stsList.Padding = UDim.new(0, 3)
	stsList.Parent = stScroll

	local stsPad = Instance.new("UIPadding")
	stsPad.PaddingTop = UDim.new(0, 4)
	stsPad.PaddingBottom = UDim.new(0, 4)
	stsPad.PaddingLeft = UDim.new(0, 6)
	stsPad.PaddingRight = UDim.new(0, 8)
	stsPad.Parent = stScroll

	local emptyNotice = Instance.new("TextLabel")
	emptyNotice.Name = "EmptyNotice"
	emptyNotice.Size = UDim2.new(1, 0, 0, 40)
	emptyNotice.Position = UDim2.new(0, 0, 0.4, 0)
	emptyNotice.BackgroundTransparency = 1
	emptyNotice.Text = "Loading stream data..."
	emptyNotice.TextColor3 = THEME.TextMuted
	emptyNotice.Font = Enum.Font.GothamMedium
	emptyNotice.TextSize = 12
	emptyNotice.Visible = true
	emptyNotice.Parent = stream

	type StreamRowUI = {
		row: Frame,
		stroke: UIStroke,
		rankBlock: TextLabel,
		avatarFrame: Frame,
		avatarInit: TextLabel,
		nameLabel: TextLabel,
		scoreLabel: TextLabel,
		classPill: TextLabel,
	}

	local streamRowPool: { StreamRowUI } = {}
	local MAX_STREAM_ROWS = 47 -- Ranks 4 to 50

	for idx = 1, MAX_STREAM_ROWS do
		local rowRank = idx + 3
		local row = Instance.new("Frame")
		row.Name = "StreamRow_" .. rowRank
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = THEME.InsetBg
		row.BorderSizePixel = 0
		row.LayoutOrder = rowRank
		row.Visible = false
		row.Parent = stScroll

		local rCorner = Instance.new("UICorner")
		rCorner.CornerRadius = UDim.new(0, 4)
		rCorner.Parent = row

		local rStroke = Instance.new("UIStroke")
		rStroke.Color = THEME.StrokeGold
		rStroke.Thickness = 1.5
		rStroke.Enabled = false
		rStroke.Parent = row

		local rPad = Instance.new("UIPadding")
		rPad.PaddingLeft = UDim.new(0, 6)
		rPad.PaddingRight = UDim.new(0, 6)
		rPad.Parent = row

		local rBlock = Instance.new("TextLabel")
		rBlock.Name = "RankBlock"
		rBlock.Size = UDim2.new(0, 36, 1, 0)
		rBlock.BackgroundTransparency = 1
		rBlock.Text = string.format("[%02d]", rowRank)
		rBlock.TextColor3 = THEME.TextMuted
		rBlock.Font = Enum.Font.Code
		rBlock.TextSize = 11
		rBlock.TextXAlignment = Enum.TextXAlignment.Left
		rBlock.Parent = row

		local nBox = Instance.new("Frame")
		nBox.Name = "NameBox"
		nBox.Size = UDim2.new(0.40, 0, 1, 0)
		nBox.Position = UDim2.new(0, 40, 0, 0)
		nBox.BackgroundTransparency = 1
		nBox.Parent = row

		local nbList = Instance.new("UIListLayout")
		nbList.FillDirection = Enum.FillDirection.Horizontal
		nbList.SortOrder = Enum.SortOrder.LayoutOrder
		nbList.Padding = UDim.new(0, 6)
		nbList.VerticalAlignment = Enum.VerticalAlignment.Center
		nbList.Parent = nBox

		local rAvFrame, rAvInit = createBoardsAvatar(nBox, UDim2.new(0, 20, 0, 20), "-", THEME.TextMuted, false)

		local uName = Instance.new("TextLabel")
		uName.Name = "UserName"
		uName.Size = UDim2.new(1, -28, 1, 0)
		uName.BackgroundTransparency = 1
		uName.Text = "-"
		uName.TextColor3 = THEME.TextPrimary
		uName.Font = Enum.Font.GothamBlack
		uName.TextSize = 11
		uName.TextXAlignment = Enum.TextXAlignment.Left
		uName.TextTruncate = Enum.TextTruncate.AtEnd
		uName.Parent = nBox

		local uScore = Instance.new("TextLabel")
		uScore.Name = "UserScore"
		uScore.Size = UDim2.new(0.32, 0, 1, 0)
		uScore.Position = UDim2.new(0.48, 0, 0, 0)
		uScore.BackgroundTransparency = 1
		uScore.Text = "-"
		uScore.TextColor3 = THEME.TextPrimary
		uScore.Font = Enum.Font.GothamBlack
		uScore.TextSize = 11.5
		uScore.TextXAlignment = Enum.TextXAlignment.Right
		uScore.Parent = row

		local uTag = Instance.new("TextLabel")
		uTag.Name = "ClassTag"
		uTag.Size = UDim2.new(0.18, 0, 0, 18)
		uTag.Position = UDim2.new(0.82, 0, 0.5, -9)
		uTag.BackgroundColor3 = THEME.HeaderBg
		uTag.Text = "INITIATE"
		uTag.TextColor3 = THEME.TextMuted
		uTag.Font = Enum.Font.GothamBlack
		uTag.TextSize = 8.5
		uTag.Parent = row

		local utCorner = Instance.new("UICorner")
		utCorner.CornerRadius = UDim.new(0, 3)
		utCorner.Parent = uTag

		table.insert(streamRowPool, {
			row = row,
			stroke = rStroke,
			rankBlock = rBlock,
			avatarFrame = rAvFrame,
			avatarInit = rAvInit,
			nameLabel = uName,
			scoreLabel = uScore,
			classPill = uTag,
		})
	end

	-- 4. PINNED ILLUMINATED OPERATOR CONSOLE
	local console = Instance.new("Frame")
	console.Name = "IlluminatedConsole"
	console.Size = UDim2.new(1, 0, 0, 44)
	console.BackgroundColor3 = Color3.fromRGB(36, 28, 22)
	console.BorderSizePixel = 0
	console.LayoutOrder = 4
	console.Parent = boardStack

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 6)
	cCorner.Parent = console

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = THEME.GoldPrimary
	cStroke.Thickness = 1.5
	cStroke.Parent = console

	local cPad = Instance.new("UIPadding")
	cPad.PaddingLeft = UDim.new(0, 10)
	cPad.PaddingRight = UDim.new(0, 10)
	cPad.Parent = console

	local cLeft = Instance.new("Frame")
	cLeft.Name = "ConsoleLeft"
	cLeft.Size = UDim2.new(0.38, 0, 1, 0)
	cLeft.BackgroundTransparency = 1
	cLeft.Parent = console

	local clList = Instance.new("UIListLayout")
	clList.FillDirection = Enum.FillDirection.Horizontal
	clList.SortOrder = Enum.SortOrder.LayoutOrder
	clList.Padding = UDim.new(0, 8)
	clList.VerticalAlignment = Enum.VerticalAlignment.Center
	clList.Parent = cLeft

	local localPlayer = Players.LocalPlayer
	local localName = if localPlayer then localPlayer.Name else "Player"
	local myAvFrame, myAvInit = createBoardsAvatar(cLeft, UDim2.new(0, 28, 0, 28), localName, THEME.GoldPrimary, true)

	local clText = Instance.new("Frame")
	clText.Size = UDim2.new(1, -38, 0, 30)
	clText.BackgroundTransparency = 1
	clText.Parent = cLeft

	local cltList = Instance.new("UIListLayout")
	cltList.FillDirection = Enum.FillDirection.Vertical
	cltList.SortOrder = Enum.SortOrder.LayoutOrder
	cltList.Padding = UDim.new(0, 1)
	cltList.Parent = clText

	local cName = Instance.new("TextLabel")
	cName.Size = UDim2.new(1, 0, 0, 15)
	cName.BackgroundTransparency = 1
	cName.Text = localName .. " (Operator)"
	cName.TextColor3 = THEME.GoldPrimary
	cName.Font = Enum.Font.GothamBlack
	cName.TextSize = 11.5
	cName.TextXAlignment = Enum.TextXAlignment.Left
	cName.Parent = clText

	local cRank = Instance.new("TextLabel")
	cRank.Size = UDim2.new(1, 0, 0, 13)
	cRank.BackgroundTransparency = 1
	cRank.Text = "STANDBY: FETCHING STANDING..."
	cRank.TextColor3 = THEME.TextMuted
	cRank.Font = Enum.Font.GothamBold
	cRank.TextSize = 9
	cRank.TextXAlignment = Enum.TextXAlignment.Left
	cRank.Parent = clText

	local cMid = Instance.new("Frame")
	cMid.Name = "ConsoleMid"
	cMid.Size = UDim2.new(0.30, 0, 1, 0)
	cMid.Position = UDim2.new(0.38, 0, 0, 0)
	cMid.BackgroundTransparency = 1
	cMid.Parent = console

	local cmLbl = Instance.new("TextLabel")
	cmLbl.Name = "MetricLabel"
	cmLbl.Size = UDim2.new(1, 0, 0, 14)
	cmLbl.Position = UDim2.new(0, 0, 0, 6)
	cmLbl.BackgroundTransparency = 1
	cmLbl.Text = "LIFETIME NET WORTH"
	cmLbl.TextColor3 = THEME.TextSubtle
	cmLbl.Font = Enum.Font.GothamBlack
	cmLbl.TextSize = 8.5
	cmLbl.TextXAlignment = Enum.TextXAlignment.Center
	cmLbl.Parent = cMid

	local cmVal = Instance.new("TextLabel")
	cmVal.Name = "MetricValue"
	cmVal.Size = UDim2.new(1, 0, 0, 18)
	cmVal.Position = UDim2.new(0, 0, 0, 20)
	cmVal.BackgroundTransparency = 1
	cmVal.Text = "-"
	cmVal.TextColor3 = THEME.GoldPrimary
	cmVal.Font = Enum.Font.GothamBlack
	cmVal.TextSize = 13.5
	cmVal.TextXAlignment = Enum.TextXAlignment.Center
	cmVal.Parent = cMid

	local cRight = Instance.new("Frame")
	cRight.Name = "ConsoleRight"
	cRight.Size = UDim2.new(0.30, 0, 1, 0)
	cRight.Position = UDim2.new(0.70, 0, 0, 0)
	cRight.BackgroundTransparency = 1
	cRight.Parent = console

	local crLbl = Instance.new("TextLabel")
	crLbl.Name = "TargetLabel"
	crLbl.Size = UDim2.new(1, 0, 1, 0)
	crLbl.BackgroundTransparency = 1
	crLbl.Text = "Synchronizing metrics..."
	crLbl.TextColor3 = THEME.AmberFlame
	crLbl.Font = Enum.Font.GothamBold
	crLbl.TextSize = 9.5
	crLbl.TextXAlignment = Enum.TextXAlignment.Right
	crLbl.Parent = cRight

	local function paintTabs(activeId: string)
		for id, btn in pairs(boardTabButtons) do
			local isActive = id == activeId
			btn.BackgroundColor3 = if isActive then THEME.GoldPrimary else THEME.CardBg
			btn.TextColor3 = if isActive then TextDark else THEME.TextMuted
		end

		for _, t in ipairs(BOARD_TABS) do
			if t.id == activeId then
				cmLbl.Text = t.title
				break
			end
		end
	end

	-- 5. LIVE REFRESH DISPATCHER
	refreshBoards = function(boardId: string)
		activeBoard = boardId
		paintTabs(boardId)

		emptyNotice.Text = "Loading stream data..."
		emptyNotice.TextColor3 = THEME.TextMuted
		emptyNotice.Visible = true

		task.spawn(function()
			local entries, myRank = NetClient.getLeaderboard(boardId)

			if activeBoard ~= boardId then
				return
			end

			if type(entries) ~= "table" then
				for _, m in pairs(monolithCards) do
					m.nameLabel.Text = "-"
					m.scoreLabel.Text = "-"
					m.avatarInit.Text = "-"
				end
				for _, ui in ipairs(streamRowPool) do
					ui.row.Visible = false
				end
				stScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
				emptyNotice.Text = "Could not load stream. Try again shortly."
				emptyNotice.TextColor3 = THEME.Negative
				emptyNotice.Visible = true
				cRank.Text = "ERROR: STREAM OFFLINE"
				cRank.TextColor3 = THEME.Negative
				return
			end

			local count = #entries

			for rankNum = 1, 3 do
				local mUI = monolithCards[rankNum]
				if mUI then
					local e = entries[rankNum]
					if type(e) == "table" then
						local entryName = tostring(e.name or "?")
						local entryRaw = tonumber(e.rawVal) or tonumber(e.score) or 0
						mUI.nameLabel.Text = entryName
						mUI.scoreLabel.Text = formatBoardScore(boardId, entryRaw)
						mUI.avatarInit.Text = string.sub(entryName, 1, 1):upper()
						mUI.classTag.Text = getRankClass(rankNum, boardId)
					else
						mUI.nameLabel.Text = "VACANT"
						mUI.scoreLabel.Text = "---"
						mUI.avatarInit.Text = "-"
						mUI.classTag.Text = "OPEN"
					end
				end
			end

			local streamRowsActive = 0
			for idx, ui in ipairs(streamRowPool) do
				local entryIndex = idx + 3
				local e = entries[entryIndex]
				if type(e) == "table" then
					streamRowsActive += 1
					ui.row.Visible = true
					local rankVal = tonumber(e.rank) or entryIndex
					local eName = tostring(e.name or "?")
					local eRaw = tonumber(e.rawVal) or tonumber(e.score) or 0
					local isMe = myRank ~= nil and rankVal == myRank

					ui.rankBlock.Text = string.format("[%02d]", rankVal)
					ui.rankBlock.TextColor3 = if isMe then THEME.GoldPrimary else THEME.TextMuted
					ui.avatarInit.Text = string.sub(eName, 1, 1):upper()
					ui.nameLabel.Text = eName .. (if isMe then " (YOU)" else "")
					ui.nameLabel.TextColor3 = if isMe then THEME.GoldPrimary else THEME.TextPrimary
					ui.scoreLabel.Text = formatBoardScore(boardId, eRaw)
					ui.scoreLabel.TextColor3 = if isMe then THEME.GoldPrimary else THEME.TextPrimary
					ui.classPill.Text = getRankClass(rankVal, boardId)
					ui.classPill.BackgroundColor3 = if isMe then THEME.GoldPrimary else THEME.HeaderBg
					ui.classPill.TextColor3 = if isMe then TextDark else THEME.TextMuted
					ui.stroke.Enabled = isMe
					ui.row.BackgroundColor3 = if isMe then Color3.fromRGB(38, 30, 22) else THEME.InsetBg
				else
					ui.row.Visible = false
				end
			end

			stScroll.CanvasSize = UDim2.new(0, 0, 0, streamRowsActive * 31 + 8)

			if count == 0 then
				emptyNotice.Text = "No records recorded yet -- be the first."
				emptyNotice.TextColor3 = THEME.TextMuted
				emptyNotice.Visible = true
			else
				emptyNotice.Visible = false
			end

			local myEntry = nil
			if myRank ~= nil and myRank >= 1 and myRank <= count then
				myEntry = entries[myRank]
			end

			if myRank ~= nil then
				cRank.Text = string.format("RANK #%d / 50 • TOP %.0f%%", myRank, math.clamp((myRank / math.max(count, 50)) * 100, 1, 100))
				cRank.TextColor3 = THEME.GoldPrimary

				if myEntry then
					local myScore = tonumber(myEntry.rawVal) or tonumber(myEntry.score) or 0
					cmVal.Text = formatBoardScore(boardId, myScore)

					if myRank > 1 then
						local prevEntry = entries[myRank - 1]
						if prevEntry then
							local prevScore = tonumber(prevEntry.rawVal) or tonumber(prevEntry.score) or 0
							local delta = math.max(0, prevScore - myScore)
							crLbl.Text = string.format("Next Rank (#%d):\n+%s Needed", myRank - 1, formatBoardScore(boardId, delta))
							crLbl.TextColor3 = THEME.AmberFlame
						else
							crLbl.Text = "Maintaining Rank position"
							crLbl.TextColor3 = THEME.Positive
						end
					else
						crLbl.Text = "WORLD CHAMPION\nDefending Throne"
						crLbl.TextColor3 = THEME.GoldPrimary
					end
				else
					cmVal.Text = "Active"
					crLbl.Text = "Ranked In Stream"
					crLbl.TextColor3 = THEME.Positive
				end
			else
				cRank.Text = string.format("STATUS: UNRANKED (Outside Top %d)", count)
				cRank.TextColor3 = THEME.AmberFlame

				if count > 0 then
					local cutoffEntry = entries[count]
					local cutoffScore = if cutoffEntry then (tonumber(cutoffEntry.rawVal) or tonumber(cutoffEntry.score) or 0) else 0
					crLbl.Text = string.format("Qualify Top 50:\nReach %s+", formatBoardScore(boardId, cutoffScore))
					crLbl.TextColor3 = THEME.TextMuted
				else
					crLbl.Text = "Qualify Top 50:\nSubmit First Score"
					crLbl.TextColor3 = THEME.TextMuted
				end
				cmVal.Text = "Unranked"
			end
		end)
	end

	paintTabs(activeBoard)

	return refreshBoards
end

-- ------------------------------
-- 8. OFFLINE VAULT OVERLAY
-- ------------------------------
local buildVaultOverlay = require(script.Parent:WaitForChild("V7VaultOverlay"))

-- ------------------------------
-- CONSTRUCTOR
-- ------------------------------
function V7MenuPanel.new(customParent: Instance?): V7MenuController
	local player = Players.LocalPlayer
	local parentGui: Instance? = customParent
	if not parentGui and player then
		parentGui = player:WaitForChild("PlayerGui", 5)
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "V7MenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 50
	if parentGui then
		screenGui.Parent = parentGui
	end

	local overlays: { [string]: Frame } = {}
	local controller: V7MenuController

	local function getController(): V7MenuController
		return controller
	end

	local shapeRefresh = buildShapesOverlay(screenGui, overlays, getController)
	local questRefresh = buildQuestsOverlay(screenGui, overlays, getController)
	local shopRefresh = buildShopOverlay(screenGui, overlays, getController)
	local boardsRefresh = buildBoardsOverlay(screenGui, overlays, getController)
	local ascendRefresh = buildAscendOverlay(screenGui, overlays, getController)
	local vaultRefresh = buildVaultOverlay(screenGui, overlays, getController, formatModalShell)
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
