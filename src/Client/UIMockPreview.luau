--!strict
-- UIMockPreview.luau
-- DICE SHAPES & UNLOCK LADDER REDESIGN PREVIEW
-- 4 Highly Refined, Flabbergasting Variations of Variant A with Varied Floating Dice Constellations:
--   Variation 1: 1 DIE FLOATING   - [ 1/4 : MACHINIST BASELINE - HERO DIE CORE ]
--   Variation 2: 5 DICE FLOATING  - [ 2/4 : TACTICAL DOSSIER - 5-DIE PENTAGONAL ARRAY ]
--   Variation 3: 8 DICE FLOATING  - [ 3/4 : CYBER-HOLOGRAPHIC - 8-DIE DUAL-RING GYRO ]
--   Variation 4: APEX COLLABORATION - [ 4/4 : APEX COLLABORATION - SPACIOUS LOADOUT + HOLOGRAPHIC GYRO ]
--
-- Features:
--   1. Spacious, non-clustered floating chamber with crystal-clear 3D orbital separation
--   2. High-legibility typography across all labels, pills, stats, and buttons (no tiny unreadable text)
--   3. Unique, rich, legendary polyhedral names for all 12 dice
--   4. Modern tactile card representation with dual stat-chip pills, 80x80px 3D plinths, and tier badges
--   5. Master-detail live click inspection + filter tabs + segmented precision caliper bars

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIMockPreview = {}

local currentGui: ScreenGui? = nil
local activeVariationIndex: number = 4 -- Default to Variation 4 (Apex Collaboration)

type SinglePreview = { model: Model, pivot: CFrame }
type OrbitItem = {
	model: Model,
	isZeroG: boolean,
	basePos: Vector3,
	freq: Vector3,
	amp: Vector3,
	phase: Vector3,
	rotSpeed: Vector3,
	baseAngle: number,
	radiusX: number,
	radiusZ: number,
	baseHeight: number,
	orbitSpeed: number,
	spinRateX: number,
	spinRateY: number,
	isHeroCenter: boolean,
}
type GyroRing = { part: BasePart, initialCFrame: CFrame, spinRateX: number, spinRateY: number }

local previewModels: { SinglePreview } = {}
local orbitItems: { OrbitItem } = {}
local gyroRings: { GyroRing } = {}
local orbitElapsed: number = 0
local previewConn: RBXScriptConnection? = nil

--------------------------------------------------------------------------------
-- 12 POLYHEDRA CATALOG DATA WITH UNIQUE LEGENDARY NAMES & STATS
--------------------------------------------------------------------------------

type ShapeTier = "Tier 1: Sniper" | "Tier 2: Balanced" | "Tier 3: Grinder"

type ShapePreviewData = {
	id: string,
	name: string,
	tierTag: string,
	faceCount: number,
	unlockCost: number,
	prereq: string?,
	category: "sniper" | "balanced" | "grinder",
	tierName: ShapeTier,
	archetype: string,
	archetypeDesc: string,
	state: "equipped" | "owned_worn" | "owned_free" | "affordable" | "unaffordable" | "locked",
	stateLabel: string,
	voidChance: string,
	voidRatio: number,
	payoutMultiplier: string,
	payoutRatio: number,
	massFloor: number,
	accentColor: Color3,
}

local SHAPES_DATA: { ShapePreviewData } = {
	-- HIGH RISK & BIG PAYOUT (High Risk / High Multiplier)
	{
		id = "D2",
		name = "Quantum Monad",
		tierTag = "D2",
		faceCount = 2,
		unlockCost = 0,
		prereq = nil,
		category = "sniper",
		tierName = "Tier 1: Sniper",
		archetype = "All Or Nothing",
		archetypeDesc = "50% chance to lose, but gives a massive 50x payout when you win.",
		state = "owned_worn",
		stateLabel = "SLOT 4",
		voidChance = "50.0%",
		voidRatio = 0.50,
		payoutMultiplier = "50x",
		payoutRatio = 1.0,
		massFloor = 60,
		accentColor = Color3.fromRGB(244, 63, 94),
	},
	{
		id = "D3",
		name = "Trinity Prism",
		tierTag = "D3",
		faceCount = 3,
		unlockCost = 500,
		prereq = "D2",
		category = "sniper",
		tierName = "Tier 1: Sniper",
		archetype = "High Risk & Big Payout",
		archetypeDesc = "High risk rolls with huge 45x multiplier rewards.",
		state = "owned_free",
		stateLabel = "UNLOCKED",
		voidChance = "49.2%",
		voidRatio = 0.49,
		payoutMultiplier = "45x",
		payoutRatio = 0.90,
		massFloor = 60,
		accentColor = Color3.fromRGB(251, 113, 133),
	},
	{
		id = "D4",
		name = "Pyramid Shard",
		tierTag = "D4",
		faceCount = 4,
		unlockCost = 2500,
		prereq = "D3",
		category = "sniper",
		tierName = "Tier 1: Sniper",
		archetype = "Big Multiplier",
		archetypeDesc = "33% chance to lose with high 32x payout rewards.",
		state = "owned_worn",
		stateLabel = "SLOT 3",
		voidChance = "33.3%",
		voidRatio = 0.33,
		payoutMultiplier = "32x",
		payoutRatio = 0.64,
		massFloor = 60,
		accentColor = Color3.fromRGB(192, 132, 252),
	},

	-- BALANCED WORKHORSES
	{
		id = "D5",
		name = "Nexus Pentagon",
		tierTag = "D5",
		faceCount = 5,
		unlockCost = 6000,
		prereq = "D4",
		category = "balanced",
		tierName = "Tier 2: Balanced",
		archetype = "Steady Earner",
		archetypeDesc = "Good balance of fair risk and solid 24x rewards.",
		state = "owned_free",
		stateLabel = "UNLOCKED",
		voidChance = "25.0%",
		voidRatio = 0.25,
		payoutMultiplier = "24x",
		payoutRatio = 0.48,
		massFloor = 60,
		accentColor = Color3.fromRGB(45, 212, 191),
	},
	{
		id = "D6",
		name = "Foundry Obsidian",
		tierTag = "D6",
		faceCount = 6,
		unlockCost = 12000,
		prereq = "D5",
		category = "balanced",
		tierName = "Tier 2: Balanced",
		archetype = "Classic Balanced",
		archetypeDesc = "The standard classic die. Reliable and well-rounded.",
		state = "equipped",
		stateLabel = "SLOTS 1,2",
		voidChance = "16.7%",
		voidRatio = 0.167,
		payoutMultiplier = "18x",
		payoutRatio = 0.36,
		massFloor = 60,
		accentColor = Color3.fromRGB(212, 175, 55),
	},
	{
		id = "D7",
		name = "Mystic Heptad",
		tierTag = "D7",
		faceCount = 7,
		unlockCost = 25000,
		prereq = "D6",
		category = "balanced",
		tierName = "Tier 2: Balanced",
		archetype = "Low Risk Earner",
		archetypeDesc = "Smooth rolls with only a low 14% chance to lose.",
		state = "affordable",
		stateLabel = "READY",
		voidChance = "14.3%",
		voidRatio = 0.143,
		payoutMultiplier = "14x",
		payoutRatio = 0.28,
		massFloor = 60,
		accentColor = Color3.fromRGB(74, 222, 128),
	},

	-- SAFE & CONSISTENT (Low Risk / Win Streaks)
	{
		id = "D8",
		name = "Astral Octahedron",
		tierTag = "D8",
		faceCount = 8,
		unlockCost = 55000,
		prereq = "D7",
		category = "grinder",
		tierName = "Tier 3: Grinder",
		archetype = "Safe Streak Builder",
		archetypeDesc = "Safe die built for keeping long win streaks going.",
		state = "unaffordable",
		stateLabel = "$55K",
		voidChance = "12.5%",
		voidRatio = 0.125,
		payoutMultiplier = "10x",
		payoutRatio = 0.20,
		massFloor = 60,
		accentColor = Color3.fromRGB(56, 189, 248),
	},
	{
		id = "D10",
		name = "Titan Decagon",
		tierTag = "D10",
		faceCount = 10,
		unlockCost = 240000,
		prereq = "D8",
		category = "grinder",
		tierName = "Tier 3: Grinder",
		archetype = "High Win Rate",
		archetypeDesc = "90% win rate with dependable continuous income.",
		state = "locked",
		stateLabel = "REQ D8",
		voidChance = "10.0%",
		voidRatio = 0.10,
		payoutMultiplier = "8x",
		payoutRatio = 0.16,
		massFloor = 60,
		accentColor = Color3.fromRGB(251, 146, 60),
	},
	{
		id = "D12",
		name = "Celestial Dodeca",
		tierTag = "D12",
		faceCount = 12,
		unlockCost = 1000000,
		prereq = "D10",
		category = "grinder",
		tierName = "Tier 3: Grinder",
		archetype = "Ultra Safe",
		archetypeDesc = "Over 91% safe rolls for consistent steady cash.",
		state = "locked",
		stateLabel = "REQ D10",
		voidChance = "8.3%",
		voidRatio = 0.083,
		payoutMultiplier = "6x",
		payoutRatio = 0.12,
		massFloor = 60,
		accentColor = Color3.fromRGB(168, 85, 247),
	},
	{
		id = "D14",
		name = "Valkyrie Tetradeca",
		tierTag = "D14",
		faceCount = 14,
		unlockCost = 2200000,
		prereq = "D12",
		category = "grinder",
		tierName = "Tier 3: Grinder",
		archetype = "Long Win Streaks",
		archetypeDesc = "Very low risk for effortless long winning combos.",
		state = "locked",
		stateLabel = "REQ D12",
		voidChance = "7.1%",
		voidRatio = 0.071,
		payoutMultiplier = "5x",
		payoutRatio = 0.10,
		massFloor = 60,
		accentColor = Color3.fromRGB(99, 102, 241),
	},
	{
		id = "D16",
		name = "Fortress Hexadeca",
		tierTag = "D16",
		faceCount = 16,
		unlockCost = 3200000,
		prereq = "D14",
		category = "grinder",
		tierName = "Tier 3: Grinder",
		archetype = "Maximum Safety",
		archetypeDesc = "Nearly impossible to lose with 94% safe win rate.",
		state = "locked",
		stateLabel = "REQ D14",
		voidChance = "6.25%",
		voidRatio = 0.0625,
		payoutMultiplier = "4.5x",
		payoutRatio = 0.09,
		massFloor = 60,
		accentColor = Color3.fromRGB(236, 72, 153),
	},
	{
		id = "D20",
		name = "Sovereign Apex Icosa",
		tierTag = "D20",
		faceCount = 20,
		unlockCost = 4200000,
		prereq = "D16",
		category = "grinder",
		tierName = "Tier 3: Grinder",
		archetype = "Master Safe Die",
		archetypeDesc = "The ultimate safe die with 95% win rate and reliable income.",
		state = "locked",
		stateLabel = "REQ D16",
		voidChance = "5.2%",
		voidRatio = 0.052,
		payoutMultiplier = "3.8x",
		payoutRatio = 0.076,
		massFloor = 60,
		accentColor = Color3.fromRGB(234, 179, 8),
	},
}

local function formatCash(amount: number): string
	if amount >= 1000000 then
		return string.format("$%.1fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("$%.0fK", amount / 1000)
	else
		return "$" .. tostring(amount)
	end
end

local function getShapeById(id: string): ShapePreviewData
	for _, shape in ipairs(SHAPES_DATA) do
		if shape.id == id then
			return shape
		end
	end
	return SHAPES_DATA[5]
end

--------------------------------------------------------------------------------
-- 3D TURNTABLES & VIEWPORT GENERATORS
--------------------------------------------------------------------------------

local function createDieViewport(shapeId: string, parent: Instance, size: UDim2, bgColor: Color3): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Preview_" .. shapeId
	vp.Size = size
	vp.BackgroundColor3 = bgColor
	vp.BackgroundTransparency = 0
	vp.BorderSizePixel = 0
	vp.LayoutOrder = 0
	vp.Parent = parent

	local folder = ReplicatedStorage:FindFirstChild("dice_faces")
	local source = if folder then folder:FindFirstChild(shapeId) else nil

	if source and source:IsA("Model") then
		local model = source:Clone()
		if model.PrimaryPart == nil then
			local pivot = model:FindFirstChild("Pivot")
			if pivot and pivot:IsA("BasePart") then
				model.PrimaryPart = pivot
			end
		end

		-- Normalize scale so all dice across all 12 cards have identical visual volume
		local _, bbSize = model:GetBoundingBox()
		local maxDim = math.max(bbSize.X, bbSize.Y, bbSize.Z)
		if maxDim > 0 then
			local targetDim = 1.8
			model:ScaleTo(targetDim / maxDim)
		end

		model:PivotTo(CFrame.new(0, 0, 0))
		model.Parent = vp

		-- Standardized, crystal-clear uniform isometric camera angle across all cards
		local cam = Instance.new("Camera")
		cam.CFrame = CFrame.new(Vector3.new(2.8, 2.2, 3.4), Vector3.new(0, 0, 0))
		cam.FieldOfView = 36
		cam.Parent = vp
		vp.CurrentCamera = cam

		table.insert(previewModels, { model = model, pivot = CFrame.new(0, 0, 0) })
	else
		local fallbackLabel = Instance.new("TextLabel")
		fallbackLabel.Size = UDim2.fromScale(1, 1)
		fallbackLabel.BackgroundTransparency = 1
		fallbackLabel.Text = shapeId
		fallbackLabel.TextColor3 = Color3.fromRGB(212, 175, 55)
		fallbackLabel.TextSize = 20
		fallbackLabel.Font = Enum.Font.GothamBold
		fallbackLabel.Parent = vp
	end

	return vp
end

-- Builds the Spacious 3D Floating Chamber with non-clustered, crystal-clear orbital kinematics
local function createFloatingChamberWithDice(
	parent: Instance,
	size: UDim2,
	bgColor: Color3,
	diceList: { string },
	includeDualGyro: boolean
): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "EquippedOrbitChamber_" .. #diceList
	vp.Size = size
	vp.BackgroundColor3 = bgColor
	vp.BackgroundTransparency = 0
	vp.BorderSizePixel = 0
	vp.Parent = parent

	-- Chamber Background & Viewport (Obstruction-free 3D Space)
	local folder = ReplicatedStorage:FindFirstChild("dice_faces")
	local count = #diceList

	if count == 1 then
		-- VARIATION 1: 1 Hero Solitary Die (Perfect Centered Framing)
		local shapeId = diceList[1]
		local source = if folder then folder:FindFirstChild(shapeId) else nil
		if source and source:IsA("Model") then
			local model = source:Clone()
			if model.PrimaryPart == nil then
				local pivot = model:FindFirstChild("Pivot")
				if pivot and pivot:IsA("BasePart") then
					model.PrimaryPart = pivot
				end
			end
			model:ScaleTo(0.68)
			model:PivotTo(CFrame.new(0, 0, 0))
			model.Parent = vp

			table.insert(orbitItems, {
				model = model,
				baseAngle = 0,
				radiusX = 0,
				radiusZ = 0,
				baseHeight = 0,
				orbitSpeed = 0,
				spinRateX = 0.70,
				spinRateY = 0.90,
				isHeroCenter = true,
			})
		end
	elseif count == 5 then
		-- VARIATION 2: 5-Die Pentagonal Array with Spacious Radial Breathing Room
		local orbitRadius = 3.3
		for idx, shapeId in ipairs(diceList) do
			local source = if folder then folder:FindFirstChild(shapeId) else nil
			if source and source:IsA("Model") then
				local model = source:Clone()
				if model.PrimaryPart == nil then
					local pivot = model:FindFirstChild("Pivot")
					if pivot and pivot:IsA("BasePart") then
						model.PrimaryPart = pivot
					end
				end
				model:ScaleTo(0.72)
				local baseAngle = (idx - 1) * ((2 * math.pi) / count)
				local initialX = orbitRadius * math.cos(baseAngle)
				local initialZ = orbitRadius * math.sin(baseAngle)
				model:PivotTo(CFrame.new(initialX, 0, initialZ))
				model.Parent = vp

				table.insert(orbitItems, {
					model = model,
					baseAngle = baseAngle,
					radiusX = orbitRadius,
					radiusZ = orbitRadius,
					baseHeight = 0,
					orbitSpeed = 0.65,
					spinRateX = 0.80,
					spinRateY = 1.0 + (idx * 0.12),
					isHeroCenter = false,
				})
			end
		end
	elseif count == 8 then
		-- VARIATION 3: 8 Dice (Dual-Ring: 4 Inner at radius 2.6 + 4 Outer at radius 4.2)
		for idx, shapeId in ipairs(diceList) do
			local source = if folder then folder:FindFirstChild(shapeId) else nil
			if source and source:IsA("Model") then
				local model = source:Clone()
				if model.PrimaryPart == nil then
					local pivot = model:FindFirstChild("Pivot")
					if pivot and pivot:IsA("BasePart") then
						model.PrimaryPart = pivot
					end
				end

				local isInner = (idx <= 4)
				local orbitRadius = if isInner then 2.6 else 4.2
				local baseHeight = if isInner then 0.35 else -0.35
				local scale = if isInner then 0.60 else 0.68
				model:ScaleTo(scale)

				local ringIndex = if isInner then idx else (idx - 4)
				local baseAngle = (ringIndex - 1) * ((2 * math.pi) / 4) + (if isInner then 0 else (math.pi / 4))
				local initialX = orbitRadius * math.cos(baseAngle)
				local initialZ = orbitRadius * math.sin(baseAngle)
				model:PivotTo(CFrame.new(initialX, baseHeight, initialZ))
				model.Parent = vp

				table.insert(orbitItems, {
					model = model,
					baseAngle = baseAngle,
					radiusX = orbitRadius,
					radiusZ = orbitRadius,
					baseHeight = baseHeight,
					orbitSpeed = if isInner then 0.75 else 0.50,
					spinRateX = if isInner then 0.85 else -0.75,
					spinRateY = 0.95 + (idx * 0.10),
					isHeroCenter = false,
				})
			end
		end
	else
		-- 12-DIE BALANCED CIRCULAR ORBIT CAROUSEL (Spacious 12-Die Ring + Slow Steady Self-Spin)
		local orbitRadius = 5.2
		for idx, shapeId in ipairs(diceList) do
			local source = if folder then folder:FindFirstChild(shapeId) else nil
			if source and source:IsA("Model") then
				local model = source:Clone()
				if model.PrimaryPart == nil then
					local pivot = model:FindFirstChild("Pivot")
					if pivot and pivot:IsA("BasePart") then
						model.PrimaryPart = pivot
					end
				end

				model:ScaleTo(0.50)

				-- Base circular distribution with per-die unique radial and vertical offsets
				local baseAngle = (idx - 1) * ((2 * math.pi) / 12)
				local p1 = math.sin(idx * 2.718)
				local p2 = math.cos(idx * 3.141)
				local p3 = math.sin(idx * 1.618)

				local baseRadius = 5.0 + 0.5 * p1 -- Radial band between 4.5 and 5.5 studs
				local initialX = baseRadius * math.cos(baseAngle)
				local initialZ = baseRadius * math.sin(baseAngle)
				local initialY = 0.5 * p2
				model:PivotTo(CFrame.new(initialX, initialY, initialZ))
				model.Parent = vp

				-- Multi-frequency rotational speeds and harmonic bobbing rates
				local spinRateX = 0.45 + 0.35 * p1
				local spinRateY = 0.85 + 0.55 * p2
				local spinRateZ = 0.35 + 0.30 * p3

				local bobFreq1 = 0.95 + 0.30 * p2
				local bobFreq2 = 1.65 + 0.40 * p3
				local bobAmp1 = 0.45 + 0.15 * math.abs(p1)
				local bobAmp2 = 0.25 + 0.10 * math.abs(p2)

				table.insert(orbitItems, {
					model = model,
					isZeroG = false,
					basePos = Vector3.zero,
					freq = Vector3.new(bobFreq1, bobFreq2, 0),
					amp = Vector3.new(bobAmp1, bobAmp2, 0),
					phase = Vector3.new(idx * 0.85, idx * 1.45, idx * 2.15),
					rotSpeed = Vector3.new(spinRateX, spinRateY, spinRateZ),
					baseAngle = baseAngle,
					radiusX = baseRadius,
					radiusZ = baseRadius,
					baseHeight = 0.15 * p2,
					orbitSpeed = 0.40, -- Clean overall orbit progression
					spinRateX = spinRateX,
					spinRateY = spinRateY,
					spinRateZ = spinRateZ,
					bobAmp1 = bobAmp1,
					bobAmp2 = bobAmp2,
					bobFreq1 = bobFreq1,
					bobFreq2 = bobFreq2,
					phase1 = idx * 1.35,
					phase2 = idx * 2.75,
					isHeroCenter = false,
				})
			end
		end
	end

	-- Camera framing calibrated for elevated panoramic circular viewing (Zero Overlap)
	local cam = Instance.new("Camera")
	if count == 1 then
		cam.CFrame = CFrame.new(Vector3.new(2.6, 2.0, 3.8), Vector3.new(0, 0, 0))
		cam.FieldOfView = 45
	elseif count == 5 then
		cam.CFrame = CFrame.new(Vector3.new(0, 3.4, 7.6), Vector3.new(0, 0, 0))
		cam.FieldOfView = 46
	elseif count == 8 then
		cam.CFrame = CFrame.new(Vector3.new(0, 3.8, 8.4), Vector3.new(0, 0, 0))
		cam.FieldOfView = 48
	else
		-- 12-die circular carousel camera (Elevated downward pitch with deep vertical coverage)
		cam.CFrame = CFrame.new(Vector3.new(0, 4.6, 11.2), Vector3.new(0, -0.2, 0))
		cam.FieldOfView = 45
	end
	cam.Parent = vp
	vp.CurrentCamera = cam

	return vp
end

local animationActive = false

local function startTurntables(): ()
	if animationActive then
		return
	end
	animationActive = true
	orbitElapsed = 0

	task.spawn(function()
		while animationActive and (currentGui ~= nil and currentGui.Parent ~= nil) do
			local rawDt = task.wait()
			local dt = math.clamp(rawDt, 0, 0.05)
			orbitElapsed += dt

			-- Rotate standard preview cards steadily at constant speed
			local cardSpinAngle = orbitElapsed * 0.70
			for _, entry in ipairs(previewModels) do
				if entry.model and entry.model.Parent ~= nil then
					entry.model:PivotTo(CFrame.Angles(0, cardSpinAngle, 0))
				end
			end

			-- Animate floating equipped dice in rich zero-g randomized orbit
			for _, item in ipairs(orbitItems) do
				if item.model and item.model.Parent ~= nil then
					if item.isZeroG then
						local xOff = math.sin(orbitElapsed * item.freq.X + item.phase.X) * item.amp.X
						local yOff = math.cos(orbitElapsed * item.freq.Y + item.phase.Y) * item.amp.Y
						local zOff = math.sin(orbitElapsed * item.freq.Z + item.phase.Z) * item.amp.Z
						local currentPos = item.basePos + Vector3.new(xOff, yOff, zOff)
						local rot = CFrame.Angles(
							orbitElapsed * item.rotSpeed.X + item.phase.X,
							orbitElapsed * item.rotSpeed.Y + item.phase.Y,
							orbitElapsed * item.rotSpeed.Z + item.phase.Z
						)
						item.model:PivotTo(CFrame.new(currentPos) * rot)
					elseif item.isHeroCenter then
						local yBob = math.sin(orbitElapsed * 1.5) * 0.18
						local localSpin = CFrame.Angles(orbitElapsed * 0.30, orbitElapsed * 0.75, 0)
						item.model:PivotTo(CFrame.new(0, yBob, 0) * localSpin)
					else
						-- Multi-harmonic zero-gravity orbital revolution
						local phaseX = item.phaseX or 0
						local phaseY = item.phaseY or 0
						local phaseZ = item.phaseZ or 0
						local driftAngle = math.sin(orbitElapsed * 0.8 + phaseX) * 0.18
						local currentAngle = item.baseAngle + (orbitElapsed * item.orbitSpeed) + driftAngle
						local radBreath = item.radiusX + math.cos(orbitElapsed * 0.65 + phaseY) * 0.35
						local x = radBreath * math.cos(currentAngle)
						local z = radBreath * math.sin(currentAngle)

						-- Dual-harmonic deep vertical wave [-0.85, +0.85 studs]
						local y1 = math.sin(orbitElapsed * (item.bobFreq1 or 1.0) + (item.phase1 or 0)) * (item.bobAmp1 or 0.45)
						local y2 = math.cos(orbitElapsed * (item.bobFreq2 or 1.7) + (item.phase2 or 0)) * (item.bobAmp2 or 0.25)
						local yBob = y1 + y2 + (item.baseHeight or 0)

						-- Multi-axis chaotic 3D tumbling (pitch, yaw, roll)
						local rotX = orbitElapsed * item.spinRateX + math.sin(orbitElapsed * 0.75 + phaseX) * 0.5 + phaseX
						local rotY = orbitElapsed * item.spinRateY + math.cos(orbitElapsed * 0.55 + phaseY) * 0.4 + phaseY
						local rotZ = orbitElapsed * (item.spinRateZ or 0.35) + math.sin(orbitElapsed * 1.1 + phaseZ) * 0.4 + phaseZ

						item.model:PivotTo(CFrame.new(x, yBob, z) * CFrame.Angles(rotX, rotY, rotZ))
					end
				end
			end

			-- Animate Gyro Rings (if any)
			for _, ring in ipairs(gyroRings) do
				if ring.part and ring.part.Parent ~= nil then
					ring.part.CFrame = ring.initialCFrame * CFrame.Angles(orbitElapsed * ring.spinRateX, orbitElapsed * ring.spinRateY, 0)
				end
			end
		end
		animationActive = false
	end)
end

local function stopTurntables(): ()
	animationActive = false
	if previewConn ~= nil then
		previewConn:Disconnect()
		previewConn = nil
	end
	table.clear(previewModels)
	table.clear(orbitItems)
	table.clear(gyroRings)
end

local function getTargetGuiParent(): Instance?
	local player = Players.LocalPlayer
	if player then
		local pGui = player:FindFirstChild("PlayerGui")
		if pGui then
			return pGui
		end
	end
	local players = Players:GetPlayers()
	if #players > 0 then
		local pGui = players[1]:FindFirstChild("PlayerGui")
		if pGui then
			return pGui
		end
	end
	local starterGui = game:GetService("StarterGui")
	if starterGui then
		return starterGui
	end
	return game:GetService("CoreGui")
end

--------------------------------------------------------------------------------
-- REUSABLE BUILDER CONFIGURATION & COMPONENT FACTORY
--------------------------------------------------------------------------------

type VariationConfig = {
	variationName: string,
	floatingDice: { string },
	chamberTitle: string,
	showFilterTabs: boolean,
	showTierBanners: boolean,
	interactiveInspection: boolean,
	holographicHUD: boolean,
	segmentedStatBars: boolean,
}

local function buildVariation(parent: Frame, config: VariationConfig): Frame
	local container = Instance.new("Frame")
	container.Name = config.variationName
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundColor3 = Color3.fromRGB(20, 17, 15)
	container.BorderSizePixel = 0
	container.Parent = parent

	local cPad = Instance.new("UIPadding")
	cPad.PaddingLeft = UDim.new(0, 14)
	cPad.PaddingRight = UDim.new(0, 14)
	cPad.PaddingTop = UDim.new(0, 12)
	cPad.PaddingBottom = UDim.new(0, 12)
	cPad.Parent = container

	local rootLayout = Instance.new("UIListLayout")
	rootLayout.FillDirection = Enum.FillDirection.Horizontal
	rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rootLayout.Padding = UDim.new(0, 14)
	rootLayout.Parent = container

	-- =========================================================================
	-- LEFT COLUMN: Dual-Stage (42% width, fills 100% height with ZERO vacant space)
	-- =========================================================================
	local leftCol = Instance.new("Frame")
	leftCol.Name = "DualStageColumn"
	leftCol.Size = UDim2.new(0.42, -7, 1, 0)
	leftCol.BackgroundColor3 = Color3.fromRGB(18, 15, 13)
	leftCol.BorderSizePixel = 0
	leftCol.LayoutOrder = 1
	leftCol.Parent = container

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 8)
	leftCorner.Parent = leftCol

	local leftStroke = Instance.new("UIStroke")
	leftStroke.Color = if config.holographicHUD then Color3.fromRGB(56, 189, 248) else Color3.fromRGB(64, 54, 44)
	leftStroke.Thickness = 1.5
	leftStroke.Parent = leftCol

	local leftPad = Instance.new("UIPadding")
	leftPad.PaddingLeft = UDim.new(0, 10)
	leftPad.PaddingRight = UDim.new(0, 10)
	leftPad.PaddingTop = UDim.new(0, 10)
	leftPad.PaddingBottom = UDim.new(0, 10)
	leftPad.Parent = leftCol

	local leftList = Instance.new("UIListLayout")
	leftList.FillDirection = Enum.FillDirection.Vertical
	leftList.SortOrder = Enum.SortOrder.LayoutOrder
	leftList.Padding = UDim.new(0, 10)
	leftList.Parent = leftCol

	-- =========================================================================
	-- SECTION 1 (TOP): ACTIVE EQUIPPED FLOATING LOADOUT CHAMBER (40% height)
	-- =========================================================================
	local loadoutChamber = Instance.new("Frame")
	loadoutChamber.Name = "EquippedFloatingChamber"
	loadoutChamber.Size = UDim2.new(1, 0, 0.40, -5)
	loadoutChamber.BackgroundColor3 = Color3.fromRGB(26, 22, 19)
	loadoutChamber.BorderSizePixel = 0
	loadoutChamber.LayoutOrder = 1
	loadoutChamber.Parent = leftCol

	local lcCorner = Instance.new("UICorner")
	lcCorner.CornerRadius = UDim.new(0, 8)
	lcCorner.Parent = loadoutChamber

	local lcStroke = Instance.new("UIStroke")
	lcStroke.Color = if config.holographicHUD then Color3.fromRGB(56, 189, 248) else Color3.fromRGB(80, 68, 56)
	lcStroke.Thickness = 1.5
	lcStroke.Parent = loadoutChamber

	local lcPad = Instance.new("UIPadding")
	lcPad.PaddingLeft = UDim.new(0, 12)
	lcPad.PaddingRight = UDim.new(0, 12)
	lcPad.PaddingTop = UDim.new(0, 10)
	lcPad.PaddingBottom = UDim.new(0, 10)
	lcPad.Parent = loadoutChamber

	local lcList = Instance.new("UIListLayout")
	lcList.FillDirection = Enum.FillDirection.Vertical
	lcList.SortOrder = Enum.SortOrder.LayoutOrder
	lcList.Padding = UDim.new(0, 6)
	lcList.Parent = loadoutChamber

	-- Chamber Header Badge
	local chamberHeader = Instance.new("TextLabel")
	chamberHeader.Name = "ChamberHeader"
	chamberHeader.Size = UDim2.new(1, 0, 0, 18)
	chamberHeader.BackgroundTransparency = 1
	chamberHeader.Text = config.chamberTitle
	chamberHeader.TextColor3 = if config.holographicHUD then Color3.fromRGB(56, 189, 248) else Color3.fromRGB(212, 175, 55)
	chamberHeader.TextSize = 12
	chamberHeader.Font = Enum.Font.RobotoMono
	chamberHeader.TextXAlignment = Enum.TextXAlignment.Left
	chamberHeader.LayoutOrder = 1
	chamberHeader.Parent = loadoutChamber

	-- 3D Floating Dice Viewport Container
	local floatingContainer = Instance.new("Frame")
	floatingContainer.Name = "FloatingViewportBox"
	floatingContainer.Size = UDim2.new(1, 0, 1, -24)
	floatingContainer.BackgroundColor3 = Color3.fromRGB(13, 11, 9)
	floatingContainer.BorderSizePixel = 0
	floatingContainer.LayoutOrder = 2
	floatingContainer.Parent = loadoutChamber

	local fcCorner = Instance.new("UICorner")
	fcCorner.CornerRadius = UDim.new(0, 6)
	fcCorner.Parent = floatingContainer

	local fcStroke = Instance.new("UIStroke")
	fcStroke.Color = if config.holographicHUD then Color3.fromRGB(56, 189, 248) else Color3.fromRGB(80, 68, 56)
	fcStroke.Thickness = 1.5
	fcStroke.Parent = floatingContainer

	-- Holographic Reticles & Live Sync Badges
	if config.holographicHUD then
		local reticles = {
			{ pos = UDim2.new(0, 6, 0, 6), text = "\u{250C}" },
			{ pos = UDim2.new(1, -16, 0, 6), text = "\u{2510}" },
			{ pos = UDim2.new(0, 6, 1, -18), text = "\u{2514}" },
			{ pos = UDim2.new(1, -16, 1, -18), text = "\u{2518}" },
		}
		for rIdx, ret in ipairs(reticles) do
			local rLbl = Instance.new("TextLabel")
			rLbl.Name = "Reticle_" .. rIdx
			rLbl.Size = UDim2.fromOffset(12, 12)
			rLbl.Position = ret.pos
			rLbl.BackgroundTransparency = 1
			rLbl.Text = ret.text
			rLbl.TextColor3 = Color3.fromRGB(56, 189, 248)
			rLbl.TextSize = 14
			rLbl.Font = Enum.Font.RobotoMono
			rLbl.ZIndex = 5
			rLbl.Parent = floatingContainer
		end

		local livePill = Instance.new("TextLabel")
		livePill.Name = "LiveSyncPill"
		livePill.Size = UDim2.new(0, 136, 0, 20)
		livePill.Position = UDim2.new(1, -144, 1, -26)
		livePill.BackgroundColor3 = Color3.fromRGB(20, 36, 44)
		livePill.BorderSizePixel = 0
		livePill.Text = "\u{25CF} LIVE RESONANCE"
		livePill.TextColor3 = Color3.fromRGB(56, 189, 248)
		livePill.TextSize = 10
		livePill.Font = Enum.Font.RobotoMono
		livePill.ZIndex = 5
		livePill.Parent = floatingContainer

		local lpC = Instance.new("UICorner")
		lpC.CornerRadius = UDim.new(0, 4)
		lpC.Parent = livePill

		local lpS = Instance.new("UIStroke")
		lpS.Color = Color3.fromRGB(56, 189, 248)
		lpS.Thickness = 1
		lpS.Parent = livePill
	end

	createFloatingChamberWithDice(floatingContainer, UDim2.fromScale(1, 1), Color3.fromRGB(13, 11, 9), config.floatingDice, config.holographicHUD)

	-- =========================================================================
	-- SECTION 2 (BOTTOM): SPECIMEN TELEMETRY STAGE (60% height)
	-- =========================================================================
	local specimenStage = Instance.new("Frame")
	specimenStage.Name = "SpecimenTelemetryStage"
	specimenStage.Size = UDim2.new(1, 0, 0.60, -5)
	specimenStage.BackgroundColor3 = Color3.fromRGB(26, 22, 19)
	specimenStage.BorderSizePixel = 0
	specimenStage.LayoutOrder = 2
	specimenStage.Parent = leftCol

	local specCorner = Instance.new("UICorner")
	specCorner.CornerRadius = UDim.new(0, 8)
	specCorner.Parent = specimenStage

	local specStroke = Instance.new("UIStroke")
	specStroke.Color = Color3.fromRGB(80, 68, 56)
	specStroke.Thickness = 1.5
	specStroke.Parent = specimenStage

	local specPad = Instance.new("UIPadding")
	specPad.PaddingLeft = UDim.new(0, 12)
	specPad.PaddingRight = UDim.new(0, 12)
	specPad.PaddingTop = UDim.new(0, 10)
	specPad.PaddingBottom = UDim.new(0, 10)
	specPad.Parent = specimenStage

	local sList = Instance.new("UIListLayout")
	sList.FillDirection = Enum.FillDirection.Vertical
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.Padding = UDim.new(0, 5)
	sList.Parent = specimenStage

	-- Stage Header
	local inspectHeader = Instance.new("TextLabel")
	inspectHeader.Name = "InspectHeader"
	inspectHeader.Size = UDim2.new(1, 0, 0, 18)
	inspectHeader.BackgroundTransparency = 1
	inspectHeader.Text = "STATS"
	inspectHeader.TextColor3 = Color3.fromRGB(245, 205, 100)
	inspectHeader.TextSize = 12
	inspectHeader.Font = Enum.Font.RobotoMono
	inspectHeader.TextXAlignment = Enum.TextXAlignment.Left
	inspectHeader.LayoutOrder = 1
	inspectHeader.Parent = specimenStage

	-- 3D Inspected Die Viewport Container
	local singleViewportContainer = Instance.new("Frame")
	singleViewportContainer.Name = "SingleViewportContainer"
	singleViewportContainer.Size = UDim2.new(1, 0, 1, -204)
	singleViewportContainer.BackgroundColor3 = Color3.fromRGB(13, 11, 9)
	singleViewportContainer.BorderSizePixel = 0
	singleViewportContainer.LayoutOrder = 2
	singleViewportContainer.Parent = specimenStage

	local svCorner = Instance.new("UICorner")
	svCorner.CornerRadius = UDim.new(0, 6)
	svCorner.Parent = singleViewportContainer

	local svStroke = Instance.new("UIStroke")
	svStroke.Color = Color3.fromRGB(160, 130, 45)
	svStroke.Thickness = 1.5
	svStroke.Parent = singleViewportContainer

	local currentInspectedVp = createDieViewport("D6", singleViewportContainer, UDim2.fromScale(1, 1), Color3.fromRGB(13, 11, 9))

	-- Inspected Die Title Banner
	local dieTitle = Instance.new("TextLabel")
	dieTitle.Name = "DieTitle"
	dieTitle.Size = UDim2.new(1, 0, 0, 24)
	dieTitle.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	dieTitle.BorderSizePixel = 0
	dieTitle.Text = "D6 FOUNDRY OBSIDIAN  •  CLASSIC BALANCED"
	dieTitle.TextColor3 = Color3.fromRGB(245, 240, 235)
	dieTitle.TextSize = 13
	dieTitle.Font = Enum.Font.GothamBold
	dieTitle.LayoutOrder = 3
	dieTitle.Parent = specimenStage

	local dtCorner = Instance.new("UICorner")
	dtCorner.CornerRadius = UDim.new(0, 4)
	dtCorner.Parent = dieTitle

	-- 4 Telemetry Rows with Segmented Caliper Bars
	local specRows: { [string]: { valLabel: TextLabel, barFill: Frame? } } = {}

	local function createCaliperRow(order: number, key: string, label: string, initialVal: string, ratio: number): Frame
		local row = Instance.new("Frame")
		row.Name = "Row_" .. key
		row.Size = UDim2.new(1, 0, 0, 17)
		row.BackgroundTransparency = 1
		row.LayoutOrder = 3 + order
		row.Parent = specimenStage

		local lLabel = Instance.new("TextLabel")
		lLabel.Size = UDim2.new(0.36, 0, 1, 0)
		lLabel.BackgroundTransparency = 1
		lLabel.Text = label
		lLabel.TextColor3 = Color3.fromRGB(160, 150, 140)
		lLabel.TextSize = 10
		lLabel.Font = Enum.Font.RobotoMono
		lLabel.TextXAlignment = Enum.TextXAlignment.Left
		lLabel.Parent = row

		if config.segmentedStatBars then
			local barBack = Instance.new("Frame")
			barBack.Name = "BarBack"
			barBack.Size = UDim2.new(0.24, -6, 0, 8)
			barBack.Position = UDim2.new(0.36, 0, 0.5, -4)
			barBack.BackgroundColor3 = Color3.fromRGB(16, 14, 12)
			barBack.BorderSizePixel = 0
			barBack.Parent = row

			local bbCorner = Instance.new("UICorner")
			bbCorner.CornerRadius = UDim.new(0, 2)
			bbCorner.Parent = barBack

			local barFill = Instance.new("Frame")
			barFill.Name = "BarFill"
			barFill.Size = UDim2.fromScale(math.clamp(ratio, 0.05, 1), 1)
			barFill.BackgroundColor3 = Color3.fromRGB(245, 205, 100)
			barFill.BorderSizePixel = 0
			barFill.Parent = barBack

			local bfCorner = Instance.new("UICorner")
			bfCorner.CornerRadius = UDim.new(0, 2)
			bfCorner.Parent = barFill

			local rVal = Instance.new("TextLabel")
			rVal.Name = "ValText"
			rVal.Size = UDim2.new(0.40, 0, 1, 0)
			rVal.Position = UDim2.new(0.60, 0, 0, 0)
			rVal.BackgroundTransparency = 1
			rVal.Text = initialVal
			rVal.TextColor3 = Color3.fromRGB(245, 240, 235)
			rVal.TextSize = 10
			rVal.Font = Enum.Font.GothamBold
			rVal.TextXAlignment = Enum.TextXAlignment.Right
			rVal.Parent = row

			specRows[key] = { valLabel = rVal, barFill = barFill }
		else
			local rVal = Instance.new("TextLabel")
			rVal.Name = "ValText"
			rVal.Size = UDim2.new(0.64, 0, 1, 0)
			rVal.Position = UDim2.new(0.36, 0, 0, 0)
			rVal.BackgroundTransparency = 1
			rVal.Text = initialVal
			rVal.TextColor3 = Color3.fromRGB(245, 240, 235)
			rVal.TextSize = 10
			rVal.Font = Enum.Font.GothamBold
			rVal.TextXAlignment = Enum.TextXAlignment.Right
			rVal.Parent = row

			specRows[key] = { valLabel = rVal, barFill = nil }
		end

		return row
	end

	createCaliperRow(1, "face", "SIDES", "6 SIDES", 6 / 20)
	createCaliperRow(2, "mass", "DICE WEIGHT", "60 WEIGHT (MAX 300)", 60 / 300)
	createCaliperRow(3, "volatility", "WIN CHANCE", "83.3% WIN  •  16.7% LOSE", 0.833)
	createCaliperRow(4, "payout", "MAX PAYOUT", "18.0x MULTIPLIER", 0.36)

	-- Specimen Action Buttons
	local equipStateBtn = Instance.new("TextButton")
	equipStateBtn.Name = "EquipStateBtn"
	equipStateBtn.Size = UDim2.new(1, 0, 0, 30)
	equipStateBtn.BackgroundColor3 = Color3.fromRGB(48, 38, 28)
	equipStateBtn.BorderSizePixel = 0
	equipStateBtn.Text = "[ EQUIPPED SOLID ]"
	equipStateBtn.TextColor3 = Color3.fromRGB(212, 175, 55)
	equipStateBtn.TextSize = 12
	equipStateBtn.Font = Enum.Font.GothamBold
	equipStateBtn.AutoButtonColor = false
	equipStateBtn.LayoutOrder = 8
	equipStateBtn.Parent = specimenStage

	local esCorner = Instance.new("UICorner")
	esCorner.CornerRadius = UDim.new(0, 4)
	esCorner.Parent = equipStateBtn

	local addInstanceBtn = Instance.new("TextButton")
	addInstanceBtn.Name = "AddInstanceBtn"
	addInstanceBtn.Size = UDim2.new(1, 0, 0, 30)
	addInstanceBtn.BackgroundColor3 = Color3.fromRGB(36, 76, 48)
	addInstanceBtn.BorderSizePixel = 0
	addInstanceBtn.Text = "+1 DIE INSTANCE   $8,000"
	addInstanceBtn.TextColor3 = Color3.fromRGB(74, 222, 128)
	addInstanceBtn.TextSize = 12
	addInstanceBtn.Font = Enum.Font.GothamBold
	addInstanceBtn.LayoutOrder = 9
	addInstanceBtn.Parent = specimenStage

	local aiCorner = Instance.new("UICorner")
	aiCorner.CornerRadius = UDim.new(0, 4)
	aiCorner.Parent = addInstanceBtn

	-- =========================================================================
	-- RIGHT COLUMN: Milled Toolroom Grid / Ladder (58% width)
	-- =========================================================================
	local rightContainer = Instance.new("Frame")
	rightContainer.Name = "RightToolroomContainer"
	rightContainer.Size = UDim2.new(0.58, -7, 1, 0)
	rightContainer.BackgroundColor3 = Color3.fromRGB(18, 15, 13)
	rightContainer.BorderSizePixel = 0
	rightContainer.LayoutOrder = 2
	rightContainer.Parent = container

	local rcCorner = Instance.new("UICorner")
	rcCorner.CornerRadius = UDim.new(0, 8)
	rcCorner.Parent = rightContainer

	local rcStroke = Instance.new("UIStroke")
	rcStroke.Color = Color3.fromRGB(64, 54, 44)
	rcStroke.Thickness = 1.5
	rcStroke.Parent = rightContainer

	local rcList = Instance.new("UIListLayout")
	rcList.FillDirection = Enum.FillDirection.Vertical
	rcList.SortOrder = Enum.SortOrder.LayoutOrder
	rcList.Padding = UDim.new(0, 8)
	rcList.Parent = rightContainer

	local rcPad = Instance.new("UIPadding")
	rcPad.PaddingLeft = UDim.new(0, 10)
	rcPad.PaddingRight = UDim.new(0, 10)
	rcPad.PaddingTop = UDim.new(0, 10)
	rcPad.PaddingBottom = UDim.new(0, 10)
	rcPad.Parent = rightContainer

	local cardFrames: { [string]: Frame } = {}
	local cardStrokes: { [string]: UIStroke } = {}

	-- Filter Bar
	if config.showFilterTabs then
		local filterBar = Instance.new("Frame")
		filterBar.Name = "FilterTabBar"
		filterBar.Size = UDim2.new(1, 0, 0, 34)
		filterBar.BackgroundColor3 = Color3.fromRGB(26, 22, 19)
		filterBar.BorderSizePixel = 0
		filterBar.LayoutOrder = 1
		filterBar.Parent = rightContainer

		local fbCorner = Instance.new("UICorner")
		fbCorner.CornerRadius = UDim.new(0, 6)
		fbCorner.Parent = filterBar

		local fbList = Instance.new("UIListLayout")
		fbList.FillDirection = Enum.FillDirection.Horizontal
		fbList.SortOrder = Enum.SortOrder.LayoutOrder
		fbList.Padding = UDim.new(0, 6)
		fbList.Parent = filterBar

		local filterTabs = {
			{ id = "all", label = "ALL (12)" },
			{ id = "sniper", label = "HIGH RISK (3)" },
			{ id = "balanced", label = "BALANCED (3)" },
			{ id = "grinder", label = "SAFE (6)" },
		}

		local currentActiveTab = "all"
		local tabButtons: { [string]: TextButton } = {}

		local function applyFilter(catId: string)
			currentActiveTab = catId
			for _, tab in ipairs(filterTabs) do
				local btn = tabButtons[tab.id]
				if btn then
					btn.BackgroundColor3 = if tab.id == currentActiveTab then Color3.fromRGB(50, 42, 34) else Color3.fromRGB(22, 19, 17)
					btn.TextColor3 = if tab.id == currentActiveTab then Color3.fromRGB(245, 240, 235) else Color3.fromRGB(150, 145, 140)
				end
			end

			for _, sData in ipairs(SHAPES_DATA) do
				local card = cardFrames[sData.id]
				if card then
					if currentActiveTab == "all" or sData.category == currentActiveTab then
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
			tBtn.Size = UDim2.new(0.25, -5, 1, 0)
			tBtn.BackgroundColor3 = if tab.id == "all" then Color3.fromRGB(50, 42, 34) else Color3.fromRGB(22, 19, 17)
			tBtn.BorderSizePixel = 0
			tBtn.Text = tab.label
			tBtn.TextColor3 = if tab.id == "all" then Color3.fromRGB(245, 240, 235) else Color3.fromRGB(150, 145, 140)
			tBtn.TextSize = 11
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
	end

	-- Scrollable Grid Rack (Roomy Exact 6-Card Viewport)
	local rightCol = Instance.new("ScrollingFrame")
	rightCol.Name = "ToolroomRackScroll"
	rightCol.Size = if config.showFilterTabs then UDim2.new(1, 0, 1, -42) else UDim2.fromScale(1, 1)
	rightCol.BackgroundTransparency = 1
	rightCol.BorderSizePixel = 0
	rightCol.ScrollBarThickness = 6
	rightCol.ScrollBarImageColor3 = Color3.fromRGB(245, 205, 100)
	rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightCol.ClipsDescendants = true
	rightCol.LayoutOrder = 2
	rightCol.Parent = rightContainer

	local rGrid = Instance.new("UIGridLayout")
	rGrid.CellSize = UDim2.new(0.5, -4, 0, 172)
	rGrid.CellPadding = UDim2.new(0, 8, 0, 8)
	rGrid.SortOrder = Enum.SortOrder.LayoutOrder
	rGrid.Parent = rightCol

	local function updateGridCellSize()
		local availableH = rightCol.AbsoluteSize.Y
		if availableH > 60 then
			local rowH = math.floor((availableH - 16) / 3)
			rGrid.CellSize = UDim2.new(0.5, -4, 0, rowH)
		end
	end
	rightCol:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridCellSize)
	task.defer(updateGridCellSize)

	local function inspectShape(shapeData: ShapePreviewData)
		if currentInspectedVp then
			currentInspectedVp:Destroy()
		end
		currentInspectedVp = createDieViewport(shapeData.id, singleViewportContainer, UDim2.fromScale(1, 1), Color3.fromRGB(13, 11, 9))

		dieTitle.Text = shapeData.id .. " " .. string.upper(shapeData.name) .. "  •  " .. string.upper(shapeData.archetype)

		if specRows["face"] then
			specRows["face"].valLabel.Text = shapeData.faceCount .. " SIDES"
			if specRows["face"].barFill then
				specRows["face"].barFill.Size = UDim2.fromScale(math.clamp(shapeData.faceCount / 20, 0.1, 1), 1)
			end
		end
		if specRows["volatility"] then
			local safePct = string.format("%.1f%% WIN", (1 - shapeData.voidRatio) * 100)
			specRows["volatility"].valLabel.Text = safePct .. "  •  " .. shapeData.voidChance .. " LOSE"
			if specRows["volatility"].barFill then
				specRows["volatility"].barFill.Size = UDim2.fromScale(math.clamp(1 - shapeData.voidRatio, 0.1, 1), 1)
			end
		end
		if specRows["payout"] then
			specRows["payout"].valLabel.Text = shapeData.payoutMultiplier .. " MULTIPLIER"
			if specRows["payout"].barFill then
				specRows["payout"].barFill.Size = UDim2.fromScale(math.clamp(shapeData.payoutRatio, 0.1, 1), 1)
			end
		end

		if shapeData.state == "equipped" then
			equipStateBtn.Text = "[ EQUIPPED SOLID ]"
			equipStateBtn.TextColor3 = Color3.fromRGB(245, 240, 235)
			equipStateBtn.BackgroundColor3 = Color3.fromRGB(48, 38, 28)
		elseif shapeData.state == "owned_worn" then
			equipStateBtn.Text = "EQUIP (5 DIAMONDS)"
			equipStateBtn.TextColor3 = Color3.fromRGB(245, 240, 235)
			equipStateBtn.BackgroundColor3 = Color3.fromRGB(36, 48, 56)
		elseif shapeData.state == "owned_free" then
			equipStateBtn.Text = "EQUIP (FREE)"
			equipStateBtn.TextColor3 = Color3.fromRGB(245, 240, 235)
			equipStateBtn.BackgroundColor3 = Color3.fromRGB(36, 52, 42)
		elseif shapeData.state == "affordable" then
			equipStateBtn.Text = "UNLOCK " .. formatCash(shapeData.unlockCost)
			equipStateBtn.TextColor3 = Color3.fromRGB(245, 240, 235)
			equipStateBtn.BackgroundColor3 = Color3.fromRGB(42, 76, 50)
		elseif shapeData.state == "unaffordable" then
			equipStateBtn.Text = "UNLOCK " .. formatCash(shapeData.unlockCost)
			equipStateBtn.TextColor3 = Color3.fromRGB(180, 175, 170)
			equipStateBtn.BackgroundColor3 = Color3.fromRGB(36, 32, 30)
		else
			equipStateBtn.Text = "LOCKED (" .. (shapeData.prereq or "REQ") .. ")"
			equipStateBtn.TextColor3 = Color3.fromRGB(140, 135, 130)
			equipStateBtn.BackgroundColor3 = Color3.fromRGB(28, 26, 24)
		end

		for sId, strk in pairs(cardStrokes) do
			if sId == shapeData.id then
				strk.Color = Color3.fromRGB(212, 175, 55)
				strk.Thickness = 2.5
			else
				local otherShape = getShapeById(sId)
				strk.Color = if otherShape.state == "equipped"
					then Color3.fromRGB(212, 175, 55)
					elseif otherShape.state == "affordable" then Color3.fromRGB(74, 222, 128)
					else Color3.fromRGB(56, 48, 40)
				strk.Thickness = if otherShape.state == "equipped" then 1.5 else 1
			end
		end
	end

	-- =========================================================================
	-- CARD FACTORY: Roomy, High-Contrast, Luxurious Polyhedra Cards
	-- =========================================================================
	for idx, sData in ipairs(SHAPES_DATA) do
		local card = Instance.new("Frame")
		card.Name = "RackCard_" .. sData.id
		card.BackgroundColor3 = if sData.state == "equipped"
			then Color3.fromRGB(38, 32, 26)
			elseif sData.state == "locked" then Color3.fromRGB(24, 21, 19)
			else Color3.fromRGB(30, 26, 22)
		card.BorderSizePixel = 0
		card.LayoutOrder = idx
		card.Parent = rightCol

		cardFrames[sData.id] = card

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 8)
		cCorner.Parent = card

		local cStroke = Instance.new("UIStroke")
		cStroke.Color = if sData.state == "equipped"
			then Color3.fromRGB(212, 175, 55)
			elseif sData.state == "affordable" then Color3.fromRGB(74, 222, 128)
			else Color3.fromRGB(58, 50, 42)
		cStroke.Thickness = if sData.state == "equipped" then 1.8 else 1
		cStroke.Parent = card

		cardStrokes[sData.id] = cStroke

		local cardPad = Instance.new("UIPadding")
		cardPad.PaddingLeft = UDim.new(0, 10)
		cardPad.PaddingRight = UDim.new(0, 10)
		cardPad.PaddingTop = UDim.new(0, 10)
		cardPad.PaddingBottom = UDim.new(0, 10)
		cardPad.Parent = card

		-- Top Row: 3D Viewport Plinth + Info Column
		local topRow = Instance.new("Frame")
		topRow.Size = UDim2.new(1, 0, 1, -44)
		topRow.BackgroundTransparency = 1
		topRow.Parent = card

		-- Left 84x84px 3D Plinth Recess
		local plinth = Instance.new("Frame")
		plinth.Name = "PlinthRecess"
		plinth.Size = UDim2.fromOffset(84, 84)
		plinth.BackgroundColor3 = Color3.fromRGB(13, 11, 9)
		plinth.BorderSizePixel = 0
		plinth.Parent = topRow

		local pCorner = Instance.new("UICorner")
		pCorner.CornerRadius = UDim.new(0, 6)
		pCorner.Parent = plinth

		local pStroke = Instance.new("UIStroke")
		pStroke.Color = Color3.fromRGB(52, 44, 36)
		pStroke.Thickness = 1
		pStroke.Parent = plinth

		createDieViewport(sData.id, plinth, UDim2.fromScale(1, 1), Color3.fromRGB(13, 11, 9))

		-- Right Info Column
		local infoCol = Instance.new("Frame")
		infoCol.Size = UDim2.new(1, -94, 1, 0)
		infoCol.Position = UDim2.fromOffset(94, 0)
		infoCol.BackgroundTransparency = 1
		infoCol.Parent = topRow

		local tList = Instance.new("UIListLayout")
		tList.FillDirection = Enum.FillDirection.Vertical
		tList.SortOrder = Enum.SortOrder.LayoutOrder
		tList.Padding = UDim.new(0, 3)
		tList.Parent = infoCol

		-- Title Line with Die ID Pill (D2, D3, D4, etc.)
		local titleRow = Instance.new("Frame")
		titleRow.Size = UDim2.new(1, 0, 0, 22)
		titleRow.BackgroundTransparency = 1
		titleRow.LayoutOrder = 1
		titleRow.Parent = infoCol

		local tTitle = Instance.new("TextLabel")
		tTitle.Size = UDim2.new(1, -44, 1, 0)
		tTitle.BackgroundTransparency = 1
		tTitle.Text = string.upper(sData.name)
		tTitle.TextColor3 = Color3.fromRGB(245, 240, 235)
		tTitle.TextSize = 13
		tTitle.Font = Enum.Font.GothamBold
		tTitle.TextXAlignment = Enum.TextXAlignment.Left
		tTitle.Parent = titleRow

		local diePill = Instance.new("TextLabel")
		diePill.Name = "DieIdTag"
		diePill.Size = UDim2.new(0, 36, 0, 18)
		diePill.Position = UDim2.new(1, -36, 0.5, -9)
		diePill.BackgroundColor3 = Color3.fromRGB(36, 32, 28)
		diePill.BorderSizePixel = 0
		diePill.Text = sData.id
		diePill.TextColor3 = Color3.fromRGB(215, 210, 205)
		diePill.TextSize = 11
		diePill.Font = Enum.Font.GothamBold
		diePill.Parent = titleRow

		local dpC = Instance.new("UICorner")
		dpC.CornerRadius = UDim.new(0, 4)
		dpC.Parent = diePill

		local dpS = Instance.new("UIStroke")
		dpS.Color = Color3.fromRGB(72, 64, 56)
		dpS.Thickness = 1
		dpS.Parent = diePill

		-- Clean, Crisp Archetype Subtitle (No glowing colored fonts)
		local tArch = Instance.new("TextLabel")
		tArch.Size = UDim2.new(1, 0, 0, 16)
		tArch.BackgroundTransparency = 1
		tArch.Text = string.upper(sData.faceCount .. " SIDES  •  " .. sData.archetype)
		tArch.TextColor3 = Color3.fromRGB(160, 155, 150)
		tArch.TextSize = 11
		tArch.Font = Enum.Font.GothamMedium
		tArch.TextXAlignment = Enum.TextXAlignment.Left
		tArch.LayoutOrder = 2
		tArch.Parent = infoCol

		-- Dual Stat-Chip Pills (Solid High-Contrast, No Glow)
		local statChipRow = Instance.new("Frame")
		statChipRow.Name = "StatChipRow"
		statChipRow.Size = UDim2.new(1, 0, 0, 22)
		statChipRow.BackgroundTransparency = 1
		statChipRow.LayoutOrder = 3
		statChipRow.Parent = infoCol

		local scList = Instance.new("UIListLayout")
		scList.FillDirection = Enum.FillDirection.Horizontal
		scList.SortOrder = Enum.SortOrder.LayoutOrder
		scList.Padding = UDim.new(0, 6)
		scList.Parent = statChipRow

		-- Void Chip
		local voidChip = Instance.new("TextLabel")
		voidChip.Name = "VoidChip"
		voidChip.Size = UDim2.new(0.5, -3, 1, 0)
		voidChip.BackgroundColor3 = Color3.fromRGB(36, 32, 30)
		voidChip.BorderSizePixel = 0
		voidChip.Text = "VOID: " .. sData.voidChance
		voidChip.TextColor3 = Color3.fromRGB(225, 220, 215)
		voidChip.TextSize = 11
		voidChip.Font = Enum.Font.GothamBold
		voidChip.LayoutOrder = 1
		voidChip.Parent = statChipRow

		local vcCorner = Instance.new("UICorner")
		vcCorner.CornerRadius = UDim.new(0, 4)
		vcCorner.Parent = voidChip

		-- Payout Chip
		local payChip = Instance.new("TextLabel")
		payChip.Name = "PayChip"
		payChip.Size = UDim2.new(0.5, -3, 1, 0)
		payChip.BackgroundColor3 = Color3.fromRGB(36, 32, 30)
		payChip.BorderSizePixel = 0
		payChip.Text = "PEAK: " .. sData.payoutMultiplier
		payChip.TextColor3 = Color3.fromRGB(225, 220, 215)
		payChip.TextSize = 11
		payChip.Font = Enum.Font.GothamBold
		payChip.LayoutOrder = 2
		payChip.Parent = statChipRow

		local pcCorner = Instance.new("UICorner")
		pcCorner.CornerRadius = UDim.new(0, 4)
		pcCorner.Parent = payChip

		-- Bottom Prominent Action Button (36px height)
		local actionBtn = Instance.new("TextButton")
		actionBtn.Name = "ActionBtn"
		actionBtn.Size = UDim2.new(1, 0, 0, 36)
		actionBtn.Position = UDim2.new(0, 0, 1, -36)
		actionBtn.BorderSizePixel = 0
		actionBtn.AutoButtonColor = false
		actionBtn.Parent = card

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = actionBtn

		if sData.state == "equipped" then
			actionBtn.BackgroundColor3 = Color3.fromRGB(56, 44, 28)
			actionBtn.Text = "[ EQUIPPED SOLID ]"
			actionBtn.TextColor3 = Color3.fromRGB(245, 240, 235)
			actionBtn.Font = Enum.Font.GothamBold
			actionBtn.TextSize = 12
		elseif sData.state == "owned_worn" then
			actionBtn.BackgroundColor3 = Color3.fromRGB(30, 58, 76)
			actionBtn.Text = "EQUIP (5 DIAMONDS)"
			actionBtn.TextColor3 = Color3.fromRGB(245, 240, 235)
			actionBtn.Font = Enum.Font.GothamBold
			actionBtn.TextSize = 12
		elseif sData.state == "owned_free" then
			actionBtn.BackgroundColor3 = Color3.fromRGB(30, 62, 40)
			actionBtn.Text = "EQUIP (FREE)"
			actionBtn.TextColor3 = Color3.fromRGB(245, 240, 235)
			actionBtn.Font = Enum.Font.GothamBold
			actionBtn.TextSize = 12
		elseif sData.state == "affordable" then
			actionBtn.BackgroundColor3 = Color3.fromRGB(36, 90, 54)
			actionBtn.Text = "UNLOCK " .. formatCash(sData.unlockCost)
			actionBtn.TextColor3 = Color3.fromRGB(245, 240, 235)
			actionBtn.Font = Enum.Font.GothamBold
			actionBtn.TextSize = 12
		elseif sData.state == "unaffordable" then
			actionBtn.BackgroundColor3 = Color3.fromRGB(44, 38, 34)
			actionBtn.Text = "UNLOCK " .. formatCash(sData.unlockCost)
			actionBtn.TextColor3 = Color3.fromRGB(180, 175, 170)
			actionBtn.Font = Enum.Font.GothamBold
			actionBtn.TextSize = 12
		else
			actionBtn.BackgroundColor3 = Color3.fromRGB(32, 30, 28)
			actionBtn.Text = "LOCKED (" .. (sData.prereq or "REQ") .. ")"
			actionBtn.TextColor3 = Color3.fromRGB(140, 135, 130)
			actionBtn.Font = Enum.Font.RobotoMono
			actionBtn.TextSize = 11
		end

		if config.interactiveInspection then
			local clickDetector = Instance.new("TextButton")
			clickDetector.Name = "ClickOverlay"
			clickDetector.Size = UDim2.fromScale(1, 1)
			clickDetector.BackgroundTransparency = 1
			clickDetector.Text = ""
			clickDetector.ZIndex = 10
			clickDetector.Parent = card

			clickDetector.MouseButton1Click:Connect(function()
				inspectShape(sData)
			end)
		end
	end

	return container
end

function UIMockPreview.show(): ScreenGui
	if currentGui ~= nil then
		currentGui:Destroy()
		currentGui = nil
	end
	stopTurntables()

	local targetParent = getTargetGuiParent()
	if not targetParent then
		error("UIMockPreview: No valid GUI parent found (PlayerGui or StarterGui)")
	end

	local existing = targetParent:FindFirstChild("UIMockPreview")
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UIMockPreview"
	screenGui.DisplayOrder = 100
	screenGui.IgnoreGuiInset = false
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local modalDimmer = Instance.new("Frame")
	modalDimmer.Name = "ModalDimmer"
	modalDimmer.Size = UDim2.fromScale(1, 1)
	modalDimmer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	modalDimmer.BackgroundTransparency = 0.4
	modalDimmer.BorderSizePixel = 0
	modalDimmer.Parent = screenGui

	local mainShell = Instance.new("Frame")
	mainShell.Name = "MainShell"
	mainShell.Size = UDim2.new(0.92, 0, 0.88, 0)
	mainShell.Position = UDim2.new(0.04, 0, 0.06, 0)
	mainShell.BackgroundColor3 = Color3.fromRGB(18, 15, 13)
	mainShell.BorderSizePixel = 0
	mainShell.Parent = screenGui

	local shellCorner = Instance.new("UICorner")
	shellCorner.CornerRadius = UDim.new(0, 10)
	shellCorner.Parent = mainShell

	local shellStroke = Instance.new("UIStroke")
	shellStroke.Color = Color3.fromRGB(212, 175, 55)
	shellStroke.Thickness = 2
	shellStroke.Parent = mainShell

	local shellConstraint = Instance.new("UISizeConstraint")
	shellConstraint.MinSize = Vector2.new(720, 520)
	shellConstraint.MaxSize = Vector2.new(1180, 780)
	shellConstraint.Parent = mainShell

	local headerBar = Instance.new("Frame")
	headerBar.Name = "CarouselHeader"
	headerBar.Size = UDim2.new(1, 0, 0, 52)
	headerBar.BackgroundColor3 = Color3.fromRGB(28, 24, 20)
	headerBar.BorderSizePixel = 0
	headerBar.Parent = mainShell

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = headerBar

	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 16)
	headerPad.PaddingRight = UDim.new(0, 16)
	headerPad.PaddingTop = UDim.new(0, 8)
	headerPad.PaddingBottom = UDim.new(0, 8)
	headerPad.Parent = headerBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleBadge"
	titleLabel.Size = UDim2.new(0.28, 0, 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "DICE SHAPES"
	titleLabel.TextColor3 = Color3.fromRGB(212, 175, 55)
	titleLabel.TextSize = 14
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = headerBar

	local switcher = Instance.new("Frame")
	switcher.Name = "VariantSwitcher"
	switcher.Size = UDim2.new(0.56, 0, 1, 0)
	switcher.Position = UDim2.new(0.28, 0, 0, 0)
	switcher.BackgroundTransparency = 1
	switcher.Parent = headerBar

	local sList = Instance.new("UIListLayout")
	sList.FillDirection = Enum.FillDirection.Horizontal
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.VerticalAlignment = Enum.VerticalAlignment.Center
	sList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sList.Padding = UDim.new(0, 8)
	sList.Parent = switcher

	local prevBtn = Instance.new("TextButton")
	prevBtn.Name = "PrevBtn"
	prevBtn.Size = UDim2.fromOffset(36, 32)
	prevBtn.BackgroundColor3 = Color3.fromRGB(44, 38, 32)
	prevBtn.BorderSizePixel = 0
	prevBtn.Text = "<"
	prevBtn.TextColor3 = Color3.fromRGB(245, 239, 230)
	prevBtn.TextSize = 16
	prevBtn.Font = Enum.Font.GothamBold
	prevBtn.LayoutOrder = 1
	prevBtn.Parent = switcher

	local prevCorner = Instance.new("UICorner")
	prevCorner.CornerRadius = UDim.new(0, 4)
	prevCorner.Parent = prevBtn

	local indicatorLabel = Instance.new("TextLabel")
	indicatorLabel.Name = "IndicatorLabel"
	indicatorLabel.Size = UDim2.new(0, 310, 1, 0)
	indicatorLabel.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	indicatorLabel.BorderSizePixel = 0
	indicatorLabel.Text = "[ 4/4 : APEX COLLABORATION ]"
	indicatorLabel.TextColor3 = Color3.fromRGB(245, 239, 230)
	indicatorLabel.TextSize = 11
	indicatorLabel.Font = Enum.Font.RobotoMono
	indicatorLabel.LayoutOrder = 2
	indicatorLabel.Parent = switcher

	local indCorner = Instance.new("UICorner")
	indCorner.CornerRadius = UDim.new(0, 4)
	indCorner.Parent = indicatorLabel

	local indStroke = Instance.new("UIStroke")
	indStroke.Color = Color3.fromRGB(212, 175, 55)
	indStroke.Thickness = 1
	indStroke.Parent = indicatorLabel

	local nextBtn = Instance.new("TextButton")
	nextBtn.Name = "NextBtn"
	nextBtn.Size = UDim2.fromOffset(36, 32)
	nextBtn.BackgroundColor3 = Color3.fromRGB(44, 38, 32)
	nextBtn.BorderSizePixel = 0
	nextBtn.Text = ">"
	nextBtn.TextColor3 = Color3.fromRGB(245, 239, 230)
	nextBtn.TextSize = 16
	nextBtn.Font = Enum.Font.GothamBold
	nextBtn.LayoutOrder = 3
	nextBtn.Parent = switcher

	local nextCorner = Instance.new("UICorner")
	nextCorner.CornerRadius = UDim.new(0, 4)
	nextCorner.Parent = nextBtn

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0.16, 0, 0, 32)
	closeBtn.Position = UDim2.new(0.84, 0, 0, 2)
	closeBtn.BackgroundColor3 = Color3.fromRGB(48, 34, 30)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "CLOSE X"
	closeBtn.TextColor3 = Color3.fromRGB(239, 68, 68)
	closeBtn.TextSize = 12
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = headerBar

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 4)
	closeCorner.Parent = closeBtn

	local contentArea = Instance.new("Frame")
	contentArea.Name = "VariantContentArea"
	contentArea.Size = UDim2.new(1, 0, 1, -52)
	contentArea.Position = UDim2.new(0, 0, 0, 52)
	contentArea.BackgroundTransparency = 1
	contentArea.Parent = mainShell

	-- 1. Variation 1: 1 Hero Solitary Die Floating
	local var1 = buildVariation(contentArea, {
		variationName = "Variation1_1Die",
		floatingDice = { "D6" },
		chamberTitle = "// LOADOUT CORE [ 1 ACTIVE HERO DIE ]",
		showFilterTabs = false,
		showTierBanners = true,
		interactiveInspection = false,
		holographicHUD = false,
		segmentedStatBars = true,
	})

	-- 2. Variation 2: 5 Dice Pentagonal Formation Floating
	local var2 = buildVariation(contentArea, {
		variationName = "Variation2_5Dice",
		floatingDice = { "D2", "D4", "D6", "D8", "D10" },
		chamberTitle = "// LOADOUT ARRAY [ 5 ACTIVE DICE // PENTAGONAL ]",
		showFilterTabs = true,
		showTierBanners = false,
		interactiveInspection = true,
		holographicHUD = false,
		segmentedStatBars = true,
	})

	-- 3. Variation 3: 8 Dice Dual-Ring Holographic Gyro Floating
	local var3 = buildVariation(contentArea, {
		variationName = "Variation3_8Dice",
		floatingDice = { "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D10" },
		chamberTitle = "// HOLOGRAPHIC GYRO [ 8 ACTIVE DICE // DUAL-TIER ]",
		showFilterTabs = false,
		showTierBanners = false,
		interactiveInspection = false,
		holographicHUD = true,
		segmentedStatBars = false,
	})

	-- 4. Variation 4: All 12 Unique Polyhedra in Dynamic Revolving Orbit + Master-Detail Inspection
	local var4 = buildVariation(contentArea, {
		variationName = "Variation4_ApexCollaboration",
		floatingDice = { "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D10", "D12", "D14", "D16", "D20" },
		chamberTitle = "ORBIT CHAMBER",
		showFilterTabs = true,
		showTierBanners = false,
		interactiveInspection = true,
		holographicHUD = false,
		segmentedStatBars = true,
	})

	local variations = { var1, var2, var3, var4 }
	local variationLabels = {
		"[ 1/4 : 1-DIE HERO CORE ]",
		"[ 2/4 : 5-DIE PENTAGONAL ARRAY ]",
		"[ 3/4 : 8-DIE DUAL-RING GYRO ]",
		"[ 4/4 : APEX COLLABORATION ]",
	}

	local function updateCarousel(newIndex: number): ()
		if newIndex < 1 then
			newIndex = #variations
		elseif newIndex > #variations then
			newIndex = 1
		end
		activeVariationIndex = newIndex

		for i, vFrame in ipairs(variations) do
			vFrame.Visible = (i == activeVariationIndex)
		end
		indicatorLabel.Text = variationLabels[activeVariationIndex]
	end

	prevBtn.MouseButton1Click:Connect(function()
		updateCarousel(activeVariationIndex - 1)
	end)

	nextBtn.MouseButton1Click:Connect(function()
		updateCarousel(activeVariationIndex + 1)
	end)

	closeBtn.MouseButton1Click:Connect(function()
		UIMockPreview.hide()
	end)

	updateCarousel(4) -- Start on Variation 4 (Apex Collaboration)

	screenGui.Parent = targetParent
	currentGui = screenGui

	startTurntables()

	-- Embedded Autonomous Client Animator LocalScript (guarantees animation runs on all clients in Play mode)
	local animScript = Instance.new("LocalScript")
	animScript.Name = "PreviewAnimator"
	animScript.Source = [==[
local RunService = game:GetService("RunService")
local screenGui = script.Parent
if not screenGui or not screenGui:IsA("ScreenGui") then return end

local mainShell = screenGui:WaitForChild("MainShell", 5)
if not mainShell then return end
local varArea = mainShell:WaitForChild("VariantContentArea", 5)
if not varArea then return end
local var4 = varArea:WaitForChild("Variation4_ApexCollaboration", 5)
if not var4 then return end

local dualCol = var4:WaitForChild("DualStageColumn", 5)
local chamberBox = dualCol and dualCol:WaitForChild("EquippedFloatingChamber", 5):WaitForChild("FloatingViewportBox", 5)
local chamberVp = chamberBox and chamberBox:FindFirstChildWhichIsA("ViewportFrame")

local orbitList = {}
if chamberVp then
	local models = {}
	for _, child in ipairs(chamberVp:GetChildren()) do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end
	for idx, m in ipairs(models) do
		local baseAngle = (idx - 1) * (2 * math.pi / #models)
		local p1 = math.sin(idx * 2.718)
		local p2 = math.cos(idx * 3.141)
		local p3 = math.sin(idx * 1.618)

		local baseRadius = 5.0 + 0.5 * p1
		local spinRateX = 0.45 + 0.35 * p1
		local spinRateY = 0.85 + 0.55 * p2
		local spinRateZ = 0.35 + 0.30 * p3

		local bobFreq1 = 0.95 + 0.30 * p2
		local bobFreq2 = 1.65 + 0.40 * p3
		local bobAmp1 = 0.45 + 0.15 * math.abs(p1)
		local bobAmp2 = 0.25 + 0.10 * math.abs(p2)

		table.insert(orbitList, {
			model = m,
			baseAngle = baseAngle,
			radiusX = baseRadius,
			orbitSpeed = 0.40,
			spinX = spinRateX,
			spinY = spinRateY,
			spinZ = spinRateZ,
			bobAmp1 = bobAmp1,
			bobAmp2 = bobAmp2,
			bobFreq1 = bobFreq1,
			bobFreq2 = bobFreq2,
			phase1 = idx * 1.35,
			phase2 = idx * 2.75,
			baseHeight = 0.15 * p2,
			phaseX = idx * 0.85,
			phaseY = idx * 1.45,
			phaseZ = idx * 2.15,
		})
	end
end

local cardModels = {}
local rightCont = var4:WaitForChild("RightToolroomContainer", 5)
local rackScroll = rightCont and rightCont:WaitForChild("ToolroomRackScroll", 5)
if rackScroll then
	for _, card in ipairs(rackScroll:GetChildren()) do
		if card:IsA("Frame") and string.find(card.Name, "RackCard_") then
			local plinth = card:FindFirstChild("TopRow") or card:FindFirstChildWhichIsA("Frame")
			if plinth then
				local recess = plinth:FindFirstChild("PlinthRecess")
				if recess then
					local vp = recess:FindFirstChildWhichIsA("ViewportFrame")
					if vp then
						local m = vp:FindFirstChildWhichIsA("Model")
						if m then
							table.insert(cardModels, m)
						end
					end
				end
			end
		end
	end
end

local specStage = dualCol and dualCol:WaitForChild("SpecimenTelemetryStage", 5)
local singleVpCont = specStage and specStage:WaitForChild("SingleViewportContainer", 5)
local singleVp = singleVpCont and singleVpCont:FindFirstChildWhichIsA("ViewportFrame")
if singleVp then
	local sm = singleVp:FindFirstChildWhichIsA("Model")
	if sm then
		table.insert(cardModels, sm)
	end
end

local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	elapsed += math.clamp(dt, 0, 0.05)

	for _, item in ipairs(orbitList) do
		if item.model and item.model.Parent ~= nil then
			local driftAngle = math.sin(elapsed * 0.8 + item.phaseX) * 0.18
			local curAngle = item.baseAngle + (elapsed * item.orbitSpeed) + driftAngle
			local radBreath = item.radiusX + math.cos(elapsed * 0.65 + item.phaseY) * 0.35
			local x = radBreath * math.cos(curAngle)
			local z = radBreath * math.sin(curAngle)

			local y1 = math.sin(elapsed * item.bobFreq1 + item.phase1) * item.bobAmp1
			local y2 = math.cos(elapsed * item.bobFreq2 + item.phase2) * item.bobAmp2
			local yBob = y1 + y2 + item.baseHeight

			local rotX = elapsed * item.spinX + math.sin(elapsed * 0.75 + item.phaseX) * 0.5 + item.phaseX
			local rotY = elapsed * item.spinY + math.cos(elapsed * 0.55 + item.phaseY) * 0.4 + item.phaseY
			local rotZ = elapsed * item.spinZ + math.sin(elapsed * 1.1 + item.phaseZ) * 0.4 + item.phaseZ

			item.model:PivotTo(CFrame.new(x, yBob, z) * CFrame.Angles(rotX, rotY, rotZ))
		end
	end

	local cardAngle = elapsed * 0.70
	for _, cm in ipairs(cardModels) do
		if cm and cm.Parent ~= nil then
			cm:PivotTo(CFrame.Angles(0, cardAngle, 0))
		end
	end
end)
]==]
	animScript.Parent = screenGui

	return screenGui
end

function UIMockPreview.hide(): ()
	stopTurntables()
	if currentGui ~= nil then
		currentGui:Destroy()
		currentGui = nil
	end
	local targetParent = getTargetGuiParent()
	if targetParent then
		local existing = targetParent:FindFirstChild("UIMockPreview")
		if existing then
			existing:Destroy()
		end
	end
end

return UIMockPreview
