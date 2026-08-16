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

-- THE COLOUR BEHIND THE GEAR, declared once and read by both sides.
--
-- The hub hole and the rim hollow are faked with discs painted to match
-- whatever sits behind the model, because a runtime CSG subtraction is not
-- available. That only works while the builder and the HUD agree on the
-- colour, so the HUD's plate reads this rather than choosing its own.
GearMeshBuilder.PlateColour = Color3.fromRGB(36, 30, 26)

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

	-- 1. Inner Hub -- ONE CYLINDER, NOT TWELVE BOXES.
	--
	-- WHY THIS CHANGED. The hub and rim were each approximated as a ring of
	-- boxes -- 12 and 16 of them -- which is a polygon pretending to be a circle.
	-- That is invisible at a large display size and very visible at the 48px this
	-- icon actually occupies: a ViewportFrame renders at its pixel size with NO
	-- anti-aliasing, so every one of those 28 box edges lands on a hard pixel
	-- boundary and the ring reads as a jagged, grainy blob rather than a circle.
	-- Reported as exactly that.
	--
	-- A cylinder is ONE part that the rasteriser draws as a true circle, so the
	-- curve is as smooth as the resolution permits instead of being quantised
	-- twice -- once into boxes, once into pixels. It is also cheaper: this change
	-- takes the gear from 45 parts to 19.
	--
	-- Roblox cylinders extend along their X axis, hence the rotation.
	local rHole = 0.8
	local rHub = 1.4

	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Shape = Enum.PartType.Cylinder
	hub.Size = Vector3.new(depth, rHub * 2, rHub * 2)
	hub.Color = bodyColor
	hub.Material = Enum.Material.SmoothPlastic
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanQuery = false
	hub.CanTouch = false
	hub.CastShadow = false
	hub.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	hub.Parent = model

	-- THE HOLE, punched by a disc in the backdrop colour rather than by a
	-- CSG subtraction. A real hole would need a UnionOperation, which cannot be
	-- built at runtime; and at this size the difference is not resolvable. It
	-- sits slightly proud on Z so it always wins the depth test.
	local hole = Instance.new("Part")
	hole.Name = "HubHole"
	hole.Shape = Enum.PartType.Cylinder
	hole.Size = Vector3.new(depth * 1.4, rHole * 2, rHole * 2)
	-- PAINTED IN THE PLATE'S COLOUR, NOT TRANSPARENT.
	--
	-- A transparent part does not punch a hole -- it simply is not drawn, so
	-- whatever is BEHIND it shows through, which here is the rest of the gear.
	-- Making these invisible removed the hole entirely and left a solid disc
	-- with teeth: still a shape, no longer legibly a gear.
	--
	-- A real hole needs a CSG subtraction, and UnionOperation cannot be built
	-- at runtime. So the cut-out is faked by a disc matching the plate behind
	-- it. `PlateColour` is exported alongside so the HUD and this builder read
	-- ONE declaration -- a second copy of the colour here would drift the first
	-- time the plate is restyled (L-025).
	hole.Color = GearMeshBuilder.PlateColour
	hole.Material = Enum.Material.SmoothPlastic
	hole.Anchored = true
	hole.CanCollide = false
	hole.CanQuery = false
	hole.CanTouch = false
	hole.CastShadow = false
	hole.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	hole.Parent = model

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

	-- 3. Outer Rim -- ONE CYLINDER plus an inner disc, same reasoning as the hub.
	-- Sixteen boxes around a circle is fifteen more silhouette edges than a
	-- cylinder needs, and at 48px every one of them shows.
	local rRimOut = 2.5

	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Size = Vector3.new(depth, rRimOut * 2, rRimOut * 2)
	rim.Color = bodyColor
	rim.Material = Enum.Material.SmoothPlastic
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanQuery = false
	rim.CanTouch = false
	rim.CastShadow = false
	rim.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	rim.Parent = model

	-- Hollows the rim so the spokes read as spokes rather than as ribs on a
	-- solid disc. Sits BEHIND the hub and spokes on Z so it cuts only the rim.
	local rimInner = Instance.new("Part")
	rimInner.Name = "RimInner"
	rimInner.Shape = Enum.PartType.Cylinder
	rimInner.Size = Vector3.new(depth * 1.2, rRimIn * 2, rRimIn * 2)
	-- Plate-coloured for the same reason as the hub hole.
	rimInner.Color = GearMeshBuilder.PlateColour
	rimInner.Material = Enum.Material.SmoothPlastic
	rimInner.Anchored = true
	rimInner.CanCollide = false
	rimInner.CanQuery = false
	rimInner.CanTouch = false
	rimInner.CastShadow = false
	rimInner.CFrame = CFrame.new(0, 0, -0.05) * CFrame.Angles(0, math.rad(90), 0)
	rimInner.Parent = model

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
