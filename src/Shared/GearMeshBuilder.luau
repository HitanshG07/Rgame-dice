--!strict
-- GearMeshBuilder.luau
-- Procedural 3D settings gear geometry for ViewportFrame display.
--
-- Builds a 3D mechanical gear model from primitive Parts:
--   - Central hole (visible ring cutout)
--   - Inner hub ring
--   - 8 internal spokes
--   - Outer rim ring
--   - 8 perimeter teeth
--
-- NO ASSET IDS / NO EXTERNAL MESHES: Built entirely from primitive Parts.
--
-- CONTRACTS & CONVENTIONS:
--   - model.PrimaryPart = invisible "Pivot" Part at exact centroid (0,0,0)
--   - Every part: Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false
--   - Bounding extent normalised to TARGET_EXTENT (6.0 studs)
--   - Colour: UITheme.Colors.TextGold
--   - Sub-pixel constraint: math.min(Size.X, Size.Y, Size.Z) >= 0.08 studs across ALL parts

local StarterPlayer = game:GetService("StarterPlayer")

local TARGET_EXTENT = 6.0
local MIN_AXIS_SIZE = 0.08

local UITheme: any = nil

local function getUITheme(): any
	if UITheme ~= nil then
		return UITheme
	end
	local clientScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local clientFolder = if clientScripts then clientScripts:FindFirstChild("Client") else nil
	local themeModule = if clientFolder then clientFolder:FindFirstChild("UITheme") else nil
	if themeModule and themeModule:IsA("ModuleScript") then
		local ok, mod = pcall(require, themeModule)
		if ok and mod then
			UITheme = mod
			return UITheme
		end
	end
	return nil
end

local GearMeshBuilder = {}

function GearMeshBuilder.build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Gear"

	local theme = getUITheme()
	local bodyColor = if theme ~= nil and theme.Colors ~= nil and theme.Colors.TextGold ~= nil
		then theme.Colors.TextGold
		else Color3.fromRGB(234, 179, 8)

	-- Create PrimaryPart Pivot at exact centroid (0,0,0)
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.new(0.2, 0.2, 0.2)
	pivot.CFrame = CFrame.identity
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.CastShadow = false
	pivot.Parent = model
	model.PrimaryPart = pivot

	local depth = 0.6

	-- 1. Inner Hub Ring (around the central hole)
	local rHole = 0.8
	local rHub = 1.4
	local hubSectors = 12
	local rMidHub = (rHole + rHub) / 2
	local radialHubWidth = rHub - rHole
	local tanHubWidth = 2 * rMidHub * math.tan(math.pi / hubSectors) * 1.05

	for i = 1, hubSectors do
		local angle = (i - 1) * (2 * math.pi / hubSectors)
		local part = Instance.new("Part")
		part.Name = "HubSegment"
		part.Size = Vector3.new(radialHubWidth, depth, tanHubWidth)
		part.Color = bodyColor
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false

		local pos = Vector3.new(math.cos(angle) * rMidHub, math.sin(angle) * rMidHub, 0)
		part.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, angle)
		part.Parent = model
	end

	-- 2. 8 Internal Spokes (connecting Hub to Outer Rim)
	local rRimIn = 2.1
	local spokeCount = 8
	local spokeLength = rRimIn - rHub
	local spokeWidth = 0.4
	local rMidSpoke = (rHub + rRimIn) / 2

	for i = 1, spokeCount do
		local angle = (i - 1) * (2 * math.pi / spokeCount)
		local part = Instance.new("Part")
		part.Name = "Spoke"
		part.Size = Vector3.new(spokeLength, depth, spokeWidth)
		part.Color = bodyColor
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false

		local pos = Vector3.new(math.cos(angle) * rMidSpoke, math.sin(angle) * rMidSpoke, 0)
		part.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, angle)
		part.Parent = model
	end

	-- 3. Outer Rim Ring
	local rRimOut = 2.5
	local rimSectors = 16
	local rMidRim = (rRimIn + rRimOut) / 2
	local radialRimWidth = rRimOut - rRimIn
	local tanRimWidth = 2 * rMidRim * math.tan(math.pi / rimSectors) * 1.05

	for i = 1, rimSectors do
		local angle = (i - 1) * (2 * math.pi / rimSectors)
		local part = Instance.new("Part")
		part.Name = "RimSegment"
		part.Size = Vector3.new(radialRimWidth, depth, tanRimWidth)
		part.Color = bodyColor
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false

		local pos = Vector3.new(math.cos(angle) * rMidRim, math.sin(angle) * rMidRim, 0)
		part.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, angle)
		part.Parent = model
	end

	-- 4. 8 Outer Gear Teeth
	local rToothOut = 3.0
	local toothCount = 8
	local toothLength = rToothOut - rRimOut
	local toothWidth = 0.5
	local rMidTooth = (rRimOut + rToothOut) / 2

	for i = 1, toothCount do
		local angle = (i - 1) * (2 * math.pi / toothCount)
		local part = Instance.new("Part")
		part.Name = "Tooth"
		part.Size = Vector3.new(toothLength, depth, toothWidth)
		part.Color = bodyColor
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false

		local pos = Vector3.new(math.cos(angle) * rMidTooth, math.sin(angle) * rMidTooth, 0)
		part.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, angle)
		part.Parent = model
	end

	-- Radial Extent Normalisation
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local maxExtent = math.max(bboxSize.X, bboxSize.Y, bboxSize.Z)
	local scaleFactor = if maxExtent > 0 then TARGET_EXTENT / maxExtent else 1.0

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			child.Size = child.Size * scaleFactor
			local relPos = child.CFrame.Position - bboxCFrame.Position
			local newPos = bboxCFrame.Position + relPos * scaleFactor
			local rotOnly = child.CFrame - child.CFrame.Position
			child.CFrame = CFrame.new(newPos) * rotOnly
		end
	end

	-- Final Centroid Alignment & Safety Verification
	pivot.CFrame = CFrame.identity

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			local minAxis = math.min(child.Size.X, child.Size.Y, child.Size.Z)
			assert(
				minAxis >= MIN_AXIS_SIZE,
				string.format("Part %s has sub-pixel axis size %.4f studs (< 0.08 studs)", child.Name, minAxis)
			)
		end
	end

	if parent ~= nil then
		model.Parent = parent
	end

	return model
end

return GearMeshBuilder
