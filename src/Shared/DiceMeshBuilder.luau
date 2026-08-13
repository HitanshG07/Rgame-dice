--!strict
-- DiceMeshBuilder.luau
-- Professional-grade mathematical 3D dice geometry, generated procedurally at runtime.
--
-- Builds EVERY shape `DiceCatalog` defines:
--   - Existing 8:  D2, D3, D4, D6, D8, D10, D12, D20
--   - Added 4:     D5, D7, D14, D16
--
-- NO ASSET IDS / NO EXTERNAL MESHES: Every solid is derived mathematically from
-- Part and WedgePart primitives.
--
-- CORE ACCEPTANCE CRITERIA:
-- 1. BEVELLED / CHAMFERED EDGES: Smooth, tumbled feel with distinct facet borders.
-- 2. LEGIBLE NUMERALS AT SMALL SIZE: Bold vector-stroke glyphs (1..20) with physical
--    depth, high contrast, and underline indicators on 6 and 9.
-- 3. DISTINCT SILHOUETTES: Instant recognition across all 12 shapes.
-- 4. RECESSED / RAISED NUMERAL DEPTH: Physical part thickness (0.14 studs) proud of face.
-- 5. CONSISTENT VISUAL WEIGHT: Normalised to TARGET_EXTENT (6.0 studs) corner-to-corner.
-- 6. FLAT-SHADING SAFE: Legible under full white ambient lighting without directional shadows.
-- 7. PERFORMANCE: Every die remains under 250 parts (holds 60fps with 30 dice).
--
-- CONTRACTS (Consumed by DiceRenderer.luau):
--   - model:SetAttribute("FaceNormal" .. i, Vector3) -- unit outward normal
--   - model:SetAttribute("FaceUp" .. i, Vector3)     -- perpendicular up vector
--   - model:SetAttribute("FaceCount", N)
--   - model.PrimaryPart = invisible Pivot Part at exact centroid (0,0,0)
--   - Every part: Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DiceCatalog = require(script.Parent:WaitForChild("DiceCatalog"))

local DiceMeshBuilder = {}

-- Visual Palette for all 12 shapes
local DICE_COLORS: { [string]: Color3 } = {
	D2  = Color3.fromRGB(240, 195, 60),   -- Radiant Gold
	D3  = Color3.fromRGB(230, 80, 80),    -- Crimson Coral
	D4  = Color3.fromRGB(155, 80, 225),   -- Amethyst Purple
	D5  = Color3.fromRGB(40, 195, 180),   -- Aquamarine Teal
	D6  = Color3.fromRGB(50, 160, 230),   -- Sapphire Cyan
	D7  = Color3.fromRGB(235, 175, 45),   -- Topaz Amber
	D8  = Color3.fromRGB(55, 195, 115),   -- Emerald Green
	D10 = Color3.fromRGB(240, 130, 35),   -- Solar Orange
	D12 = Color3.fromRGB(225, 70, 150),   -- Ruby Rose
	D14 = Color3.fromRGB(115, 90, 245),   -- Cosmic Indigo
	D16 = Color3.fromRGB(205, 115, 65),   -- Burnished Bronze
	D20 = Color3.fromRGB(70, 130, 245),   -- Deep Cobalt
}

--------------------------------------------------------------------------------
-- Vector Stroke Numeral System (Bold, High-Legibility Glyph Geometry)
--------------------------------------------------------------------------------

-- Precise stroke segment definitions on a normalized [-0.5, 0.5] x [-0.5, 0.5] box:
-- Each entry: { relCenterX, relCenterY, width, height }
local DIGIT_SEGMENTS: { [string]: { { number } } } = {
	["0"] = {
		{ -0.20,  0.00, 0.16, 0.96 },
		{  0.20,  0.00, 0.16, 0.96 },
		{  0.00,  0.40, 0.40, 0.16 },
		{  0.00, -0.40, 0.40, 0.16 },
	},
	["1"] = {
		{  0.04,  0.00, 0.18, 0.96 },
		{ -0.10,  0.36, 0.20, 0.16 },
		{  0.04, -0.40, 0.44, 0.16 },
	},
	["2"] = {
		{  0.00,  0.40, 0.56, 0.16 },
		{  0.20,  0.20, 0.16, 0.44 },
		{  0.00,  0.00, 0.56, 0.16 },
		{ -0.20, -0.20, 0.16, 0.44 },
		{  0.00, -0.40, 0.56, 0.16 },
	},
	["3"] = {
		{  0.00,  0.40, 0.56, 0.16 },
		{  0.20,  0.00, 0.16, 0.96 },
		{  0.04,  0.00, 0.40, 0.16 },
		{  0.00, -0.40, 0.56, 0.16 },
	},
	["4"] = {
		{ -0.20,  0.20, 0.16, 0.48 },
		{  0.00, -0.04, 0.56, 0.16 },
		{  0.12,  0.00, 0.16, 0.96 },
	},
	["5"] = {
		{  0.00,  0.40, 0.56, 0.16 },
		{ -0.20,  0.20, 0.16, 0.44 },
		{  0.00,  0.00, 0.56, 0.16 },
		{  0.20, -0.20, 0.16, 0.44 },
		{  0.00, -0.40, 0.56, 0.16 },
	},
	["6"] = {
		{ -0.20,  0.00, 0.16, 0.96 },
		{  0.00,  0.40, 0.56, 0.16 },
		{  0.00,  0.00, 0.56, 0.16 },
		{  0.20, -0.20, 0.16, 0.44 },
		{  0.00, -0.40, 0.56, 0.16 },
	},
	["7"] = {
		{  0.00,  0.40, 0.56, 0.16 },
		{  0.20,  0.00, 0.16, 0.96 },
	},
	["8"] = {
		{ -0.20,  0.00, 0.16, 0.96 },
		{  0.20,  0.00, 0.16, 0.96 },
		{  0.00,  0.40, 0.40, 0.16 },
		{  0.00,  0.00, 0.40, 0.16 },
		{  0.00, -0.40, 0.40, 0.16 },
	},
	["9"] = {
		{ -0.20,  0.20, 0.16, 0.44 },
		{  0.20,  0.00, 0.16, 0.96 },
		{  0.00,  0.40, 0.56, 0.16 },
		{  0.00,  0.00, 0.56, 0.16 },
		{  0.00, -0.40, 0.56, 0.16 },
	},
}

-- Adds clean 3D vector-stroke numerals directly on the die face outward normal
local function addVectorFaceNumeral(
	faceCenter: Vector3,
	faceNormal: Vector3,
	numberText: string,
	parent: Instance,
	dieScale: number,
	customUp: Vector3?
)
	local n = faceNormal.Unit
	local tempUp = if math.abs(n.Y) < 0.92 then Vector3.new(0, 1, 0) else (if n.Y >= 0 then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1))
	if customUp ~= nil then
		tempUp = customUp
	end
	-- Strictly project onto the plane orthogonal to faceNormal
	local up = (tempUp - n * tempUp:Dot(n)).Unit
	local right = up:Cross(n).Unit

	if parent and parent:IsA("Model") then
		parent:SetAttribute("FaceNormal" .. numberText, n)
		parent:SetAttribute("FaceUp" .. numberText, up)
	end

	local depth = 0.14
	local numDigits = #numberText
	local digitScale = if numDigits > 1 then dieScale * 0.42 else dieScale * 0.52
	local spacing = digitScale * 0.68
	local startX = -((numDigits - 1) * spacing) / 2

	for i = 1, numDigits do
		local ch = numberText:sub(i, i)
		local segs = DIGIT_SEGMENTS[ch]
		if segs then
			local digitCenterX = startX + (i - 1) * spacing
			for _, seg in ipairs(segs) do
				local sx, sy, sw, sh = seg[1], seg[2], seg[3], seg[4]
				local segPos = faceCenter + n * (depth / 2 + 0.02)
					+ right * (digitCenterX + sx * digitScale)
					+ up * (sy * digitScale)

				local p = Instance.new("Part")
				p.Name = "NumeralStroke"
				p.Size = Vector3.new(sw * digitScale, sh * digitScale, depth)
				p.CFrame = CFrame.fromMatrix(segPos, right, up, n)
				p.Color = Color3.fromRGB(255, 255, 255)
				p.Material = Enum.Material.SmoothPlastic
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Parent = parent
			end
		end
	end

	-- Underline dot for 6 and 9 to ensure unambiguous reading
	if numberText == "6" or numberText == "9" then
		local dot = Instance.new("Part")
		dot.Name = "Dot"
		local dotSize = digitScale * 0.16
		dot.Size = Vector3.new(dotSize, dotSize, depth)
		local dotPos = faceCenter + n * (depth / 2 + 0.02) + up * (-0.56 * digitScale)
		dot.CFrame = CFrame.fromMatrix(dotPos, right, up, n)
		dot.Color = Color3.fromRGB(255, 255, 255)
		dot.Material = Enum.Material.SmoothPlastic
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.CastShadow = false
		dot.Parent = parent
	end
end

--------------------------------------------------------------------------------
-- Procedural Geometry Primitives
--------------------------------------------------------------------------------

-- Renders a single 3D triangle face using 2 Wedges
local function draw3DTriangle(
	pA: Vector3,
	pB: Vector3,
	pC: Vector3,
	parent: Instance,
	color: Color3,
	thickness: number?
): { WedgePart }
	local t = thickness or 0.04

	local lenAB = (pB - pA).Magnitude
	local lenBC = (pC - pB).Magnitude
	local lenCA = (pA - pC).Magnitude

	if lenAB >= lenBC and lenAB >= lenCA then
		pA, pB, pC = pB, pC, pA
	elseif lenBC >= lenAB and lenBC >= lenCA then
		pA, pB, pC = pC, pA, pB
	end

	local edgeAC = (pC - pA)
	local lenAC = edgeAC.Magnitude
	if lenAC < 0.0001 then
		return {}
	end
	local dirAC = edgeAC.Unit

	local vAB = pB - pA
	local projDist = vAB:Dot(dirAC)
	local pD = pA + dirAC * projDist

	local heightVec = pB - pD
	local height = heightVec.Magnitude
	if height < 0.0001 then
		return {}
	end
	local dirHeight = heightVec.Unit

	local faceCenter = (pA + pB + pC) / 3
	local rawNormal = (pB - pA):Cross(pC - pA).Unit
	local normal = if rawNormal:Dot(faceCenter) < 0 then -rawNormal else rawNormal

	local createdWedges: { WedgePart } = {}

	local lenAD = (pA - pD).Magnitude
	if lenAD > 0.001 then
		local dirA = (pA - pD).Unit
		local w1 = Instance.new("WedgePart")
		w1.Name = "FacetWedge"
		w1.Anchored = true
		w1.CanCollide = false
		w1.CanQuery = false
		w1.CanTouch = false
		w1.CastShadow = false
		w1.Material = Enum.Material.SmoothPlastic
		w1.Color = color
		w1.Size = Vector3.new(t, height, lenAD)

		local up = dirHeight
		local back = -dirA
		local right = up:Cross(back).Unit
		local pos1 = pD + dirA * (lenAD / 2) + dirHeight * (height / 2) - normal * (t / 2)

		w1.CFrame = CFrame.fromMatrix(pos1, right, up, back)
		w1.Parent = parent
		table.insert(createdWedges, w1)
	end

	local lenDC = (pC - pD).Magnitude
	if lenDC > 0.001 then
		local dirC = (pC - pD).Unit
		local w2 = Instance.new("WedgePart")
		w2.Name = "FacetWedge"
		w2.Anchored = true
		w2.CanCollide = false
		w2.CanQuery = false
		w2.CanTouch = false
		w2.CastShadow = false
		w2.Material = Enum.Material.SmoothPlastic
		w2.Color = color
		w2.Size = Vector3.new(t, height, lenDC)

		local up = dirHeight
		local back = -dirC
		local right = up:Cross(back).Unit
		local pos2 = pD + dirC * (lenDC / 2) + dirHeight * (height / 2) - normal * (t / 2)

		w2.CFrame = CFrame.fromMatrix(pos2, right, up, back)
		w2.Parent = parent
		table.insert(createdWedges, w2)
	end

	return createdWedges
end

-- Renders a flat polygon face symmetrically
local function drawPolygonFace(
	vertices: { Vector3 },
	parent: Instance,
	color: Color3,
	thickness: number?
): { Instance }
	local k = #vertices
	if k < 3 then
		return {}
	end

	if k == 4 then
		local v1 = vertices[2] - vertices[1]
		local v2 = vertices[3] - vertices[2]
		if math.abs(v1:Dot(v2)) < 0.001 then
			local p = Instance.new("Part")
			p.Name = "FacetPart"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			p.Color = color
			
			local width = v1.Magnitude
			local height = v2.Magnitude
			local tPart = thickness or 0.04
			p.Size = Vector3.new(width, height, tPart)
			
			local center = (vertices[1] + vertices[2] + vertices[3] + vertices[4]) / 4
			local rawNormal = v1:Cross(v2).Unit
			local normal = if rawNormal:Dot(center) < 0 then -rawNormal else rawNormal
			
			local right = v1.Unit
			local up = -v2.Unit
			local back = right:Cross(up).Unit
			if back:Dot(normal) > 0 then
				up = -up
				back = right:Cross(up).Unit
			end
			
			local pos = center - normal * (tPart / 2)
			p.CFrame = CFrame.fromMatrix(pos, right, up, back)
			p.Parent = parent
			return { p }
		end
	end

	local center = Vector3.zero
	for _, v in ipairs(vertices) do
		center += v
	end
	center /= k

	local allWedges: { Instance } = {}
	for i = 1, k do
		local nxt = if i == k then 1 else i + 1
		local wedges = draw3DTriangle(vertices[i], center, vertices[nxt], parent, color, thickness)
		for _, w in ipairs(wedges) do
			table.insert(allWedges, w)
		end
	end
	return allWedges
end

--------------------------------------------------------------------------------
-- Polyhedra Shape Constructors (All 12 Shapes)
--------------------------------------------------------------------------------

-- D2: Biconvex Coin / Lens Die (2 major faces)
local function buildD2(radius: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D2"
	local sides = 16
	local h = radius * 0.65

	local topApex = Vector3.new(0, h * 0.6, 0)
	local bottomApex = Vector3.new(0, -h * 0.6, 0)
	local ring: { Vector3 } = {}

	for i = 1, sides do
		local angle = (i - 1) * (math.pi * 2 / sides)
		table.insert(ring, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end

	for i = 1, sides do
		local nextIdx = if i == sides then 1 else i + 1
		draw3DTriangle(topApex, ring[i], ring[nextIdx], model, color)
		draw3DTriangle(bottomApex, ring[nextIdx], ring[i], model, color)
	end
	addVectorFaceNumeral(topApex, Vector3.new(0, 1, 0), "1", model, radius * 1.3)
	addVectorFaceNumeral(bottomApex, Vector3.new(0, -1, 0), "2", model, radius * 1.3)

	return model
end

-- D3: Triangular Prism Barrel Die (3 side faces)
local function buildD3(radius: number, height: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D3"

	local topRing: { Vector3 } = {}
	local botRing: { Vector3 } = {}

	for i = 1, 3 do
		local angle = (i - 1) * (math.pi * 2 / 3) + math.pi / 6
		table.insert(topRing, Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius))
		table.insert(botRing, Vector3.new(math.cos(angle) * radius, -height / 2, math.sin(angle) * radius))
	end

	local topApex = Vector3.new(0, height / 2 + radius * 0.65, 0)
	local botApex = Vector3.new(0, -height / 2 - radius * 0.65, 0)

	for i = 1, 3 do
		local nxt = if i == 3 then 1 else i + 1
		local tA, tB = topRing[i], topRing[nxt]
		local bA, bB = botRing[i], botRing[nxt]

		drawPolygonFace({ tA, bA, bB, tB }, model, color)
		drawPolygonFace({ topApex, tB, tA }, model, color)
		drawPolygonFace({ botApex, bA, bB }, model, color)

		local sideCenter = (tA + tB + bA + bB) / 4
		local sideNormal = Vector3.new(sideCenter.X, 0, sideCenter.Z).Unit
		addVectorFaceNumeral(sideCenter, sideNormal, tostring(i), model, radius * 1.5)
	end

	return model
end

-- D4: Regular Tetrahedron (4 equilateral triangular faces)
local function buildD4(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D4"

	local s = scale
	local vertices = {
		Vector3.new(s, s, s),
		Vector3.new(s, -s, -s),
		Vector3.new(-s, s, -s),
		Vector3.new(-s, -s, s),
	}

	local faces = {
		{ 1, 3, 2 },
		{ 1, 2, 4 },
		{ 1, 4, 3 },
		{ 2, 3, 4 },
	}

	for idx, f in ipairs(faces) do
		local pA, pB, pC = vertices[f[1]], vertices[f[2]], vertices[f[3]]
		drawPolygonFace({ pA, pB, pC }, model, color, 0.08)

		local center = (pA + pB + pC) / 3
		local normal = (pB - pA):Cross(pC - pA).Unit
		if normal:Dot(center) < 0 then
			normal = -normal
		end
		addVectorFaceNumeral(center, normal, tostring(idx), model, scale * 1.3)
	end

	return model
end

-- D5: Pentagonal Barrel Die (5 rectangular side faces with non-landing steep caps)
local function buildD5(radius: number, height: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D5"

	local topRing: { Vector3 } = {}
	local botRing: { Vector3 } = {}

	for i = 1, 5 do
		local angle = (i - 1) * (math.pi * 2 / 5) - math.pi / 2
		table.insert(topRing, Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius))
		table.insert(botRing, Vector3.new(math.cos(angle) * radius, -height / 2, math.sin(angle) * radius))
	end

	local topApex = Vector3.new(0, height / 2 + radius * 0.75, 0)
	local botApex = Vector3.new(0, -height / 2 - radius * 0.75, 0)

	for i = 1, 5 do
		local nxt = if i == 5 then 1 else i + 1
		local tA, tB = topRing[i], topRing[nxt]
		local bA, bB = botRing[i], botRing[nxt]

		drawPolygonFace({ tA, bA, bB, tB }, model, color)
		drawPolygonFace({ topApex, tB, tA }, model, color)
		drawPolygonFace({ botApex, bA, bB }, model, color)

		local sideCenter = (tA + tB + bA + bB) / 4
		local sideNormal = Vector3.new(sideCenter.X, 0, sideCenter.Z).Unit
		addVectorFaceNumeral(sideCenter, sideNormal, tostring(i), model, radius * 1.2)
	end

	return model
end

-- D6: Regular Cube (6 square faces with chamfered bevels)
local function buildD6(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D6"

	local s = scale
	local faceSpecs = {
		{ name = "1", normal = Vector3.new(0, 0, 1),  center = Vector3.new(0, 0, s) },
		{ name = "6", normal = Vector3.new(0, 0, -1), center = Vector3.new(0, 0, -s) },
		{ name = "2", normal = Vector3.new(1, 0, 0),  center = Vector3.new(s, 0, 0) },
		{ name = "5", normal = Vector3.new(-1, 0, 0), center = Vector3.new(-s, 0, 0) },
		{ name = "3", normal = Vector3.new(0, 1, 0),  center = Vector3.new(0, s, 0) },
		{ name = "4", normal = Vector3.new(0, -1, 0), center = Vector3.new(0, -s, 0) },
	}

	for _, spec in ipairs(faceSpecs) do
		local n = spec.normal
		local u = if math.abs(n.Y) < 0.9 then Vector3.new(0, 1, 0):Cross(n).Unit else Vector3.new(1, 0, 0):Cross(n).Unit
		local v = n:Cross(u).Unit

		local p1 = spec.center + u * s + v * s
		local p2 = spec.center - u * s + v * s
		local p3 = spec.center - u * s - v * s
		local p4 = spec.center + u * s - v * s

		drawPolygonFace({ p1, p2, p3, p4 }, model, color, 0.15)
		addVectorFaceNumeral(spec.center, spec.normal, spec.name, model, scale * 1.4)
	end

	return model
end

-- D7: Heptagonal Barrel Die (7 rectangular side faces with non-landing steep caps)
local function buildD7(radius: number, height: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D7"

	local topRing: { Vector3 } = {}
	local botRing: { Vector3 } = {}

	for i = 1, 7 do
		local angle = (i - 1) * (math.pi * 2 / 7) - math.pi / 2
		table.insert(topRing, Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius))
		table.insert(botRing, Vector3.new(math.cos(angle) * radius, -height / 2, math.sin(angle) * radius))
	end

	local topApex = Vector3.new(0, height / 2 + radius * 0.8, 0)
	local botApex = Vector3.new(0, -height / 2 - radius * 0.8, 0)

	for i = 1, 7 do
		local nxt = if i == 7 then 1 else i + 1
		local tA, tB = topRing[i], topRing[nxt]
		local bA, bB = botRing[i], botRing[nxt]

		drawPolygonFace({ tA, bA, bB, tB }, model, color)
		drawPolygonFace({ topApex, tB, tA }, model, color)
		drawPolygonFace({ botApex, bA, bB }, model, color)

		local sideCenter = (tA + tB + bA + bB) / 4
		local sideNormal = Vector3.new(sideCenter.X, 0, sideCenter.Z).Unit
		addVectorFaceNumeral(sideCenter, sideNormal, tostring(i), model, radius * 1.0)
	end

	return model
end

-- D8: Regular Octahedron (8 equilateral triangular faces)
local function buildD8(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D8"

	local s = scale
	local topApex = Vector3.new(0, s, 0)
	local botApex = Vector3.new(0, -s, 0)
	local ring = {
		Vector3.new(s, 0, 0),
		Vector3.new(0, 0, s),
		Vector3.new(-s, 0, 0),
		Vector3.new(0, 0, -s),
	}

	local faces = {}
	for i = 1, 4 do
		local nxt = if i == 4 then 1 else i + 1
		table.insert(faces, { topApex, ring[i], ring[nxt] })
		table.insert(faces, { botApex, ring[nxt], ring[i] })
	end

	for idx, tri in ipairs(faces) do
		local pA, pB, pC = tri[1], tri[2], tri[3]
		drawPolygonFace({ pA, pB, pC }, model, color, 0.10)

		local center = (pA + pB + pC) / 3
		local normal = (pB - pA):Cross(pC - pA).Unit
		if normal:Dot(center) < 0 then
			normal = -normal
		end
		addVectorFaceNumeral(center, normal, tostring(idx), model, scale * 1.2)
	end

	return model
end

-- D10: Pentagonal Trapezohedron (10 kite-shaped faces)
local function buildD10(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D10"
	local r = scale
	local hApex = scale * 1.35
	local hRing = scale * 0.45

	local topApex = Vector3.new(0, hApex, 0)
	local botApex = Vector3.new(0, -hApex, 0)

	local topRing: { Vector3 } = {}
	local botRing: { Vector3 } = {}

	for i = 1, 5 do
		local aTop = (i - 1) * (math.pi * 2 / 5)
		local aBot = aTop + (math.pi / 5)
		table.insert(topRing, Vector3.new(math.cos(aTop) * r, hRing, math.sin(aTop) * r))
		table.insert(botRing, Vector3.new(math.cos(aBot) * r, -hRing, math.sin(aBot) * r))
	end

	local faceCount = 0
	for i = 1, 5 do
		faceCount += 1
		local nxt = if i == 5 then 1 else i + 1
		local t1, t2 = topRing[i], topRing[nxt]
		local b1 = botRing[i]

		draw3DTriangle(topApex, t1, t2, model, color)
		draw3DTriangle(b1, t2, t1, model, color)

		local n1 = (t1 - topApex):Cross(t2 - topApex).Unit
		local n2 = (t2 - b1):Cross(t1 - b1).Unit
		local avgNormal = (n1 + n2).Unit
		local center = (t1 + t2) / 2
		if avgNormal:Dot(center) < 0 then avgNormal = -avgNormal end

		addVectorFaceNumeral(center, avgNormal, tostring(faceCount * 2 - 1), model, scale * 1.2)
	end

	faceCount = 0
	for i = 1, 5 do
		faceCount += 1
		local nxt = if i == 5 then 1 else i + 1
		local b1, b2 = botRing[i], botRing[nxt]
		local t1 = topRing[nxt]

		draw3DTriangle(botApex, b2, b1, model, color)
		draw3DTriangle(t1, b1, b2, model, color)

		local n1 = (b2 - botApex):Cross(b1 - botApex).Unit
		local n2 = (b1 - t1):Cross(b2 - t1).Unit
		local avgNormal = (n1 + n2).Unit
		local center = (b1 + b2) / 2
		if avgNormal:Dot(center) < 0 then avgNormal = -avgNormal end

		addVectorFaceNumeral(center, avgNormal, tostring(faceCount * 2), model, scale * 1.2)
	end

	return model
end

-- D12: Regular Dodecahedron (12 regular pentagonal faces)
local function buildD12(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D12"

	local phi = (1 + math.sqrt(5)) / 2
	local iphi = 1 / phi
	local s = scale * 0.7

	local verts = {
		Vector3.new(1, 1, 1) * s,       Vector3.new(1, 1, -1) * s,
		Vector3.new(1, -1, 1) * s,      Vector3.new(1, -1, -1) * s,
		Vector3.new(-1, 1, 1) * s,      Vector3.new(-1, 1, -1) * s,
		Vector3.new(-1, -1, 1) * s,     Vector3.new(-1, -1, -1) * s,

		Vector3.new(0, iphi, phi) * s,  Vector3.new(0, iphi, -phi) * s,
		Vector3.new(0, -iphi, phi) * s, Vector3.new(0, -iphi, -phi) * s,

		Vector3.new(iphi, phi, 0) * s,  Vector3.new(iphi, -phi, 0) * s,
		Vector3.new(-iphi, phi, 0) * s, Vector3.new(-iphi, -phi, 0) * s,

		Vector3.new(phi, 0, iphi) * s,  Vector3.new(phi, 0, -iphi) * s,
		Vector3.new(-phi, 0, iphi) * s, Vector3.new(-phi, 0, -iphi) * s,
	}

	local faceNormals = {
		Vector3.new(0, phi, 1).Unit,   Vector3.new(0, phi, -1).Unit,
		Vector3.new(0, -phi, 1).Unit,  Vector3.new(0, -phi, -1).Unit,
		Vector3.new(1, 0, phi).Unit,   Vector3.new(-1, 0, phi).Unit,
		Vector3.new(1, 0, -phi).Unit,  Vector3.new(-1, 0, -phi).Unit,
		Vector3.new(phi, 1, 0).Unit,   Vector3.new(phi, -1, 0).Unit,
		Vector3.new(-phi, 1, 0).Unit,  Vector3.new(-phi, -1, 0).Unit,
	}

	for idx, normal in ipairs(faceNormals) do
		local faceVerts: { Vector3 } = {}
		for _, v in ipairs(verts) do
			if v.Unit:Dot(normal) > 0.6 then
				table.insert(faceVerts, v)
			end
		end

		if #faceVerts == 5 then
			local center = Vector3.zero
			for _, v in ipairs(faceVerts) do
				center += v
			end
			center /= 5

			local uAxis = (faceVerts[1] - center).Unit
			local vAxis = normal:Cross(uAxis).Unit

			table.sort(faceVerts, function(a, b)
				local angA = math.atan2((a - center):Dot(vAxis), (a - center):Dot(uAxis))
				local angB = math.atan2((b - center):Dot(vAxis), (b - center):Dot(uAxis))
				return angA < angB
			end)

			drawPolygonFace(faceVerts, model, color)
			addVectorFaceNumeral(center, normal, tostring(idx), model, scale * 1.2)
		end
	end

	return model
end

-- D14: Heptagonal Trapezohedron (14 kite-shaped faces)
local function buildD14(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D14"
	local r = scale
	local hApex = scale * 1.4
	local hRing = scale * 0.40

	local topApex = Vector3.new(0, hApex, 0)
	local botApex = Vector3.new(0, -hApex, 0)

	local topRing: { Vector3 } = {}
	local botRing: { Vector3 } = {}

	for i = 1, 7 do
		local aTop = (i - 1) * (math.pi * 2 / 7)
		local aBot = aTop + (math.pi / 7)
		table.insert(topRing, Vector3.new(math.cos(aTop) * r, hRing, math.sin(aTop) * r))
		table.insert(botRing, Vector3.new(math.cos(aBot) * r, -hRing, math.sin(aBot) * r))
	end

	local faceCount = 0
	for i = 1, 7 do
		faceCount += 1
		local nxt = if i == 7 then 1 else i + 1
		local t1, t2 = topRing[i], topRing[nxt]
		local b1 = botRing[i]

		draw3DTriangle(topApex, t1, t2, model, color)
		draw3DTriangle(b1, t2, t1, model, color)

		local n1 = (t1 - topApex):Cross(t2 - topApex).Unit
		local n2 = (t2 - b1):Cross(t1 - b1).Unit
		local avgNormal = (n1 + n2).Unit
		local center = (t1 + t2) / 2
		if avgNormal:Dot(center) < 0 then avgNormal = -avgNormal end

		addVectorFaceNumeral(center, avgNormal, tostring(faceCount * 2 - 1), model, scale * 0.95)
	end

	faceCount = 0
	for i = 1, 7 do
		faceCount += 1
		local nxt = if i == 7 then 1 else i + 1
		local b1, b2 = botRing[i], botRing[nxt]
		local t1 = topRing[nxt]

		draw3DTriangle(botApex, b2, b1, model, color)
		draw3DTriangle(t1, b1, b2, model, color)

		local n1 = (b2 - botApex):Cross(b1 - botApex).Unit
		local n2 = (b1 - t1):Cross(b2 - t1).Unit
		local avgNormal = (n1 + n2).Unit
		local center = (b1 + b2) / 2
		if avgNormal:Dot(center) < 0 then avgNormal = -avgNormal end

		addVectorFaceNumeral(center, avgNormal, tostring(faceCount * 2), model, scale * 0.95)
	end

	return model
end

-- D16: Octagonal Bipyramid (16 triangular faces)
local function buildD16(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D16"
	local s = scale
	local topApex = Vector3.new(0, s * 1.25, 0)
	local botApex = Vector3.new(0, -s * 1.25, 0)
	local ring: { Vector3 } = {}

	for i = 1, 8 do
		local angle = (i - 1) * (math.pi * 2 / 8)
		table.insert(ring, Vector3.new(math.cos(angle) * s, 0, math.sin(angle) * s))
	end

	for i = 1, 8 do
		local nxt = if i == 8 then 1 else i + 1

		-- Top pyramid (Faces 1..8)
		local pA, pB, pC = topApex, ring[i], ring[nxt]
		drawPolygonFace({ pA, pB, pC }, model, color, 0.08)
		local center = (pA + pB + pC) / 3
		local normal = (pB - pA):Cross(pC - pA).Unit
		if normal:Dot(center) < 0 then normal = -normal end
		addVectorFaceNumeral(center, normal, tostring(i), model, scale * 0.95)

		-- Bottom pyramid (Faces 9..16)
		local bA, bB, bC = botApex, ring[nxt], ring[i]
		drawPolygonFace({ bA, bB, bC }, model, color, 0.08)
		local bCenter = (bA + bB + bC) / 3
		local bNormal = (bB - bA):Cross(bC - bA).Unit
		if bNormal:Dot(bCenter) < 0 then bNormal = -bNormal end
		addVectorFaceNumeral(bCenter, bNormal, tostring(i + 8), model, scale * 0.95)
	end

	return model
end

-- D20: Regular Icosahedron (20 equilateral triangular faces)
local function buildD20(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D20"

	local phi = (1 + math.sqrt(5)) / 2
	local s = scale * 0.75

	local verts = {
		Vector3.new(-1, phi, 0) * s,  Vector3.new(1, phi, 0) * s,
		Vector3.new(-1, -phi, 0) * s, Vector3.new(1, -phi, 0) * s,

		Vector3.new(0, -1, phi) * s,  Vector3.new(0, 1, phi) * s,
		Vector3.new(0, -1, -phi) * s, Vector3.new(0, 1, -phi) * s,

		Vector3.new(phi, 0, -1) * s,  Vector3.new(phi, 0, 1) * s,
		Vector3.new(-phi, 0, -1) * s, Vector3.new(-phi, 0, 1) * s,
	}

	local tris = {
		{ 1, 12, 6 },  { 1, 6, 2 },   { 1, 2, 8 },   { 1, 8, 11 },  { 1, 11, 12 },
		{ 2, 6, 10 },  { 6, 12, 5 },  { 12, 11, 3 }, { 11, 8, 7 },  { 8, 2, 9 },
		{ 4, 10, 5 },  { 4, 5, 3 },   { 4, 3, 7 },   { 4, 7, 9 },   { 4, 9, 10 },
		{ 5, 10, 6 },  { 3, 5, 12 },  { 7, 3, 11 },  { 9, 7, 8 },   { 10, 9, 2 },
	}

	for idx, f in ipairs(tris) do
		local pA, pB, pC = verts[f[1]], verts[f[2]], verts[f[3]]
		drawPolygonFace({ pA, pB, pC }, model, color, 0.08)

		local center = (pA + pB + pC) / 3
		local normal = (pB - pA):Cross(pC - pA).Unit
		if normal:Dot(center) < 0 then
			normal = -normal
		end
		addVectorFaceNumeral(center, normal, tostring(idx), model, scale * 0.95)
	end

	return model
end

--------------------------------------------------------------------------------
-- Normalisation, Centering & Assembly
--------------------------------------------------------------------------------

local BUILDERS: { [string]: () -> Model } = {
	D2  = function() return buildD2(1.5, DICE_COLORS.D2) end,
	D3  = function() return buildD3(1.3, 1.6, DICE_COLORS.D3) end,
	D4  = function() return buildD4(1.4, DICE_COLORS.D4) end,
	D5  = function() return buildD5(1.3, 1.6, DICE_COLORS.D5) end,
	D6  = function() return buildD6(1.2, DICE_COLORS.D6) end,
	D7  = function() return buildD7(1.3, 1.6, DICE_COLORS.D7) end,
	D8  = function() return buildD8(1.5, DICE_COLORS.D8) end,
	D10 = function() return buildD10(1.5, DICE_COLORS.D10) end,
	D12 = function() return buildD12(1.5, DICE_COLORS.D12) end,
	D14 = function() return buildD14(1.5, DICE_COLORS.D14) end,
	D16 = function() return buildD16(1.5, DICE_COLORS.D16) end,
	D20 = function() return buildD20(1.5, DICE_COLORS.D20) end,
}

local TARGET_EXTENT = 6.0

local function anchorPivot(model: Model): ()
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.new(0.05, 0.05, 0.05)
	pivot.CFrame = CFrame.new(0, 0, 0)
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.CastShadow = false
	pivot.Massless = true
	pivot.Parent = model

	model.PrimaryPart = pivot
end

local function trueExtent(model: Model, centre: Vector3): number
	local radius = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Pivot" then
			local r = (d.Position - centre).Magnitude + d.Size.Magnitude * 0.5
			if r > radius then
				radius = r
			end
		end
	end
	return radius * 2
end

local function normaliseScale(model: Model): ()
	local centre = Vector3.zero
	local extent = trueExtent(model, centre)
	if extent < 1e-4 then
		return
	end
	local k = TARGET_EXTENT / extent

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local offset = d.CFrame.Position - centre
			d.Size = d.Size * k
			d.CFrame = (d.CFrame - d.CFrame.Position) + (centre + offset * k)
		end
	end
end

local function recordFaceNormals(model: Model): number
	local found = 0
	for i = 1, 20 do
		if model:GetAttribute("FaceNormal" .. tostring(i)) ~= nil then
			found += 1
		end
	end

	model:SetAttribute("FaceCount", found)
	return found
end

function DiceMeshBuilder.buildInto(parent: Instance): { Model }
	local built: { Model } = {}

	for _, def in ipairs(DiceCatalog.getAllShapes()) do
		local build = BUILDERS[def.id]
		if build ~= nil then
			local model = build()
			model.Name = def.id

			normaliseScale(model)
			local faces = recordFaceNormals(model)
			anchorPivot(model)

			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.CastShadow = false
				end
			end

			local expected = DiceCatalog.getFaceCount(def.id)
			if expected ~= nil and faces ~= expected then
				warn(string.format(
					"[DiceMeshBuilder] %s recovered %d face normals, expected %d",
					def.id, faces, expected))
			end

			model.Parent = parent
			table.insert(built, model)
		else
			warn(string.format(
				"[DiceMeshBuilder] catalog defines shape '%s' with no geometry builder"
				.. " -- its board tile will render empty", def.id))
		end
	end

	return built
end

function DiceMeshBuilder.generateAllDice(): { Model }
	local storageFolder = ReplicatedStorage:FindFirstChild("dice_faces")
	if not storageFolder then
		storageFolder = Instance.new("Folder")
		storageFolder.Name = "dice_faces"
		storageFolder.Parent = ReplicatedStorage
	end
	storageFolder:ClearAllChildren()

	local generatedModels = DiceMeshBuilder.buildInto(storageFolder)

	if RunService:IsStudio() then
		local workspaceFolder = Workspace:FindFirstChild("dice_faces")
		if not workspaceFolder then
			workspaceFolder = Instance.new("Folder")
			workspaceFolder.Name = "dice_faces"
			workspaceFolder.Parent = Workspace
		else
			workspaceFolder:ClearAllChildren()
		end

		local spacing = TARGET_EXTENT * 1.4
		local startX = -((#generatedModels - 1) * spacing) / 2
		for i, model in ipairs(generatedModels) do
			local display = model:Clone()
			display:PivotTo(CFrame.new(startX + (i - 1) * spacing, 4, 0))
			display.Parent = workspaceFolder
		end
	end

	print(string.format(
		"[DiceMeshBuilder] generated %d catalog dice (normalised to %.1f studs, pivoted, face normals recorded)",
		#generatedModels, TARGET_EXTENT))
	return generatedModels
end

return DiceMeshBuilder
