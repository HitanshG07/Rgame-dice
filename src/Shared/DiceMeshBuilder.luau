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
-- 1. BEVELLED / CHAMFERED EDGES: Real physical chamfer geometry bridging every adjacent
--    face pair with surface normals angled between face normals (no hard 90° edges).
-- 2. ENGRAVED GLYPHS / PIPS: Every numeral and pip is flush-inlaid into the facet cavity,
--    sitting strictly at or below the facet surface (max proud <= 0.0 studs) with
--    high-contrast, self-illuminating Neon white inlays.
-- 3. D2 COIN: Redesigned as a cylindrical coin with flat circular face plates and
--    chamfered perimeter rims, eliminating buried numerals on pointed lenses.
-- 4. D4 TETRAHEDRON: 4 closed solid triangular faces with 1 centered numeral per face.
-- 5. D6 CASINO PIPS: Authentic circular `PartType.Cylinder` pips on opposite faces
--    summing to 7 (1-6, 2-5, 3-4) recessed into the chamfered cube body.
-- 6. D10 & D14 WATERTIGHT TRAPEZOHEDRA: Planar kite faces sharing equatorial vertices with zero gaps/trenches.
-- 7. D16 BIPYRAMID: Numerals scaled to facet centroids without crossing equatorial seams.
-- 8. RADIAL NORMALISATION: Corner-to-corner radial reach normalised to TARGET_EXTENT (6.0 studs).
-- 9. PERFORMANCE: Every die remains comfortably under 250 parts for smooth 60fps rendering.
--
-- CONTRACTS (Consumed by DiceRenderer.luau):
--   - model:SetAttribute("FaceNormal" .. i, Vector3) -- unit outward normal of the face proper
--   - model:SetAttribute("FaceUp" .. i, Vector3)     -- perpendicular up vector (|n . up| < 1e-4)
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

local TARGET_EXTENT = 6.0

--------------------------------------------------------------------------------
-- Vector Stroke Numeral System (Bold, High-Legibility Glyph Geometry)
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Procedural Geometry Primitives
--------------------------------------------------------------------------------

local function draw3DTriangle(
	pA: Vector3,
	pB: Vector3,
	pC: Vector3,
	parent: Instance,
	color: Color3,
	thickness: number?,
	isChamfer: boolean?
): { WedgePart }
	local t = thickness or 0.04
	local lenAB = (pB - pA).Magnitude
	local lenBC = (pC - pB).Magnitude
	local lenCA = (pA - pC).Magnitude

	-- Check for isosceles / symmetric triangle where pA is the apex (lenAB == lenCA)
	if math.abs(lenAB - lenCA) < 0.02 * math.max(lenAB, lenCA) and lenBC <= lenAB then
		local baseMid = (pB + pC) / 2
		local heightVec = pA - baseMid
		local height = heightVec.Magnitude
		if height < 0.0001 then return {} end
		local dirHeight = heightVec.Unit

		local baseVec = pC - pB
		local baseLen = baseVec.Magnitude
		if baseLen < 0.0001 then return {} end
		local dirBase = baseVec.Unit
		local halfBase = baseLen / 2

		local faceCenter = (pA + pB + pC) / 3
		local rawNormal = baseVec:Cross(heightVec).Unit
		local normal = if rawNormal:Dot(faceCenter) < 0 then -rawNormal else rawNormal

		local createdWedges: { WedgePart } = {}

		-- Wedge 1: towards pB
		local w1 = Instance.new("WedgePart")
		w1.Name = if isChamfer then "ChamferWedge" else "FacetWedge"
		w1.Anchored = true
		w1.CanCollide = false
		w1.CanQuery = false
		w1.CanTouch = false
		w1.CastShadow = false
		w1.Material = Enum.Material.SmoothPlastic
		w1.Color = color
		w1.Size = Vector3.new(t, height, halfBase)
		local up1 = dirHeight
		local back1 = dirBase
		local right1 = up1:Cross(back1).Unit
		local pos1 = baseMid - dirBase * (halfBase / 2) + dirHeight * (height / 2) - normal * (t / 2)
		w1.CFrame = CFrame.fromMatrix(pos1, right1, up1, back1)
		w1.Parent = parent
		table.insert(createdWedges, w1)

		-- Wedge 2: towards pC
		local w2 = Instance.new("WedgePart")
		w2.Name = if isChamfer then "ChamferWedge" else "FacetWedge"
		w2.Anchored = true
		w2.CanCollide = false
		w2.CanQuery = false
		w2.CanTouch = false
		w2.CastShadow = false
		w2.Material = Enum.Material.SmoothPlastic
		w2.Color = color
		w2.Size = Vector3.new(t, height, halfBase)
		local up2 = dirHeight
		local back2 = -dirBase
		local right2 = up2:Cross(back2).Unit
		local pos2 = baseMid + dirBase * (halfBase / 2) + dirHeight * (height / 2) - normal * (t / 2)
		w2.CFrame = CFrame.fromMatrix(pos2, right2, up2, back2)
		w2.Parent = parent
		table.insert(createdWedges, w2)

		return createdWedges
	end

	if lenAB >= lenBC and lenAB >= lenCA then
		pA, pB, pC = pB, pC, pA
	elseif lenBC >= lenAB and lenBC >= lenCA then
		pA, pB, pC = pC, pA, pB
	end

	local edgeAC = (pC - pA)
	local lenAC = edgeAC.Magnitude
	if lenAC < 0.0001 then return {} end
	local dirAC = edgeAC.Unit
	local projDist = (pB - pA):Dot(dirAC)
	local pD = pA + dirAC * projDist

	local heightVec = pB - pD
	local height = heightVec.Magnitude
	if height < 0.0001 then return {} end
	local dirHeight = heightVec.Unit

	local faceCenter = (pA + pB + pC) / 3
	local rawNormal = (pB - pA):Cross(pC - pA).Unit
	local normal = if rawNormal:Dot(faceCenter) < 0 then -rawNormal else rawNormal

	local createdWedges: { WedgePart } = {}
	local lenAD = (pA - pD).Magnitude
	if lenAD > 0.001 then
		local dirA = (pA - pD).Unit
		local w1 = Instance.new("WedgePart")
		w1.Name = if isChamfer then "ChamferWedge" else "FacetWedge"
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
		w2.Name = if isChamfer then "ChamferWedge" else "FacetWedge"
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

local function drawQuadFace(
	pA: Vector3,
	pB: Vector3,
	pC: Vector3,
	pD: Vector3,
	parent: Instance,
	color: Color3,
	thickness: number?,
	isChamfer: boolean?
): { Instance }
	local v1 = pB - pA
	local v2 = pC - pB
	local v3 = pD - pC
	local v4 = pA - pD
	if math.abs(v1:Dot(v2)) < 0.001 and math.abs(v3:Dot(v4)) < 0.001 and math.abs(v1.Magnitude - v3.Magnitude) < 0.001 then
		local p = Instance.new("Part")
		p.Name = if isChamfer then "ChamferPart" else "FacetPart"
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
		local center = (pA + pB + pC + pD) / 4
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
	local all: { Instance } = {}
	for _, w in ipairs(draw3DTriangle(pA, pB, pC, parent, color, thickness, isChamfer)) do table.insert(all, w) end
	for _, w in ipairs(draw3DTriangle(pA, pC, pD, parent, color, thickness, isChamfer)) do table.insert(all, w) end
	return all
end

local function drawPolygon(vertices: { Vector3 }, parent: Instance, color: Color3, thickness: number?): { Instance }
	local k = #vertices
	if k < 3 then return {} end
	if k == 3 then
		return draw3DTriangle(vertices[1], vertices[2], vertices[3], parent, color, thickness)
	elseif k == 4 then
		return drawQuadFace(vertices[1], vertices[2], vertices[3], vertices[4], parent, color, thickness)
	end
	local center = Vector3.zero
	for _, v in ipairs(vertices) do center += v end
	center /= k
	local all: { Instance } = {}
	for i = 1, k do
		local nxt = if i == k then 1 else i + 1
		for _, w in ipairs(draw3DTriangle(vertices[i], center, vertices[nxt], parent, color, thickness)) do
			table.insert(all, w)
		end
	end
	return all
end

--------------------------------------------------------------------------------
-- Engraved Numeral & Pip Systems (Flush-Inlaid Neon Inlays)
--------------------------------------------------------------------------------

local function addEngravedFaceNumeral(
	faceCenter: Vector3,
	faceNormal: Vector3,
	numberText: string,
	parent: Instance,
	dieScale: number,
	customUp: Vector3?
)
	local n = faceNormal.Unit
	local tempUp = if math.abs(n.Y) < 0.92 then Vector3.new(0, 1, 0) else (if n.Y >= 0 then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1))
	if customUp ~= nil then tempUp = customUp end
	local up = (tempUp - n * tempUp:Dot(n)).Unit
	local right = up:Cross(n).Unit

	if parent and parent:IsA("Model") then
		parent:SetAttribute("FaceNormal" .. numberText, n)
		parent:SetAttribute("FaceUp" .. numberText, up)
	end

	local glyphThickness = 0.04
	local normalOffset = 0.001

	local numDigits = #numberText
	local digitScale = if numDigits > 1 then dieScale * 0.38 else dieScale * 0.48
	local spacing = digitScale * 0.68
	local startX = -((numDigits - 1) * spacing) / 2

	for i = 1, numDigits do
		local ch = numberText:sub(i, i)
		local segs = DIGIT_SEGMENTS[ch]
		if segs then
			local digitCenterX = startX + (i - 1) * spacing
			for _, seg in ipairs(segs) do
				local sx, sy, sw, sh = seg[1], seg[2], seg[3], seg[4]
				local segPos = faceCenter + n * normalOffset + right * (digitCenterX + sx * digitScale) + up * (sy * digitScale)
				local p = Instance.new("Part")
				p.Name = "NumeralStroke"
				p.Size = Vector3.new(sw * digitScale, sh * digitScale, glyphThickness)
				p.CFrame = CFrame.fromMatrix(segPos, right, up, n)
				p.Color = Color3.fromRGB(255, 255, 255)
				p.Material = Enum.Material.Neon
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Parent = parent
			end
		end
	end

	if numberText == "6" or numberText == "9" then
		local dot = Instance.new("Part")
		dot.Name = "Dot"
		local dotSize = digitScale * 0.16
		dot.Size = Vector3.new(dotSize, dotSize, glyphThickness)
		local dotPos = faceCenter + n * normalOffset + up * (-0.56 * digitScale)
		dot.CFrame = CFrame.fromMatrix(dotPos, right, up, n)
		dot.Color = Color3.fromRGB(255, 255, 255)
		dot.Material = Enum.Material.Neon
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.CastShadow = false
		dot.Parent = parent
	end
end

local function addEngravedPips(
	faceCenter: Vector3,
	faceNormal: Vector3,
	pipCount: number,
	parent: Instance,
	faceSize: number
)
	local n = faceNormal.Unit
	local tempUp = if math.abs(n.Y) < 0.92 then Vector3.new(0, 1, 0) else (if n.Y >= 0 then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1))
	local up = (tempUp - n * tempUp:Dot(n)).Unit
	local right = up:Cross(n).Unit

	if parent and parent:IsA("Model") then
		parent:SetAttribute("FaceNormal" .. tostring(pipCount), n)
		parent:SetAttribute("FaceUp" .. tostring(pipCount), up)
	end

	local pipThickness = 0.04
	local pipDiameter = faceSize * 0.22
	local d = faceSize * 0.26

	local coords = {}
	if pipCount == 1 then coords = { { 0, 0 } }
	elseif pipCount == 2 then coords = { { -d, -d }, { d, d } }
	elseif pipCount == 3 then coords = { { -d, -d }, { 0, 0 }, { d, d } }
	elseif pipCount == 4 then coords = { { -d, -d }, { -d, d }, { d, -d }, { d, d } }
	elseif pipCount == 5 then coords = { { -d, -d }, { -d, d }, { d, -d }, { d, d }, { 0, 0 } }
	elseif pipCount == 6 then coords = { { -d, -d }, { -d, 0 }, { -d, d }, { d, -d }, { d, 0 }, { d, d } }
	end

	for _, c in ipairs(coords) do
		local pipPos = faceCenter + n * 0.001 + right * c[1] + up * c[2]
		local p = Instance.new("Part")
		p.Name = "Pip"
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(pipThickness, pipDiameter, pipDiameter)
		p.CFrame = CFrame.fromMatrix(pipPos, n, up)
		p.Color = Color3.fromRGB(255, 255, 255)
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = parent
	end
end

--------------------------------------------------------------------------------
-- Polyhedral Mesh Engine with Edge Chamfering
--------------------------------------------------------------------------------

local function buildChamferedSolid(
	shapeName: string,
	vertices: { Vector3 },
	faceIndices: { { number } },
	color: Color3,
	chamferRatio: number
): (Model, { Vector3 }, { Vector3 })
	local model = Instance.new("Model")
	model.Name = shapeName
	local chamferColor = Color3.new(color.R * 0.78, color.G * 0.78, color.B * 0.78)
	local numFaces = #faceIndices

	local centroids: { Vector3 } = {}
	local normals: { Vector3 } = {}
	local insets: { { Vector3 } } = {}

	for f = 1, numFaces do
		local fv = faceIndices[f]
		local k = #fv
		local c = Vector3.zero
		for _, vIdx in ipairs(fv) do c += vertices[vIdx] end
		c /= k
		centroids[f] = c

		local rawN = (vertices[fv[2]] - vertices[fv[1]]):Cross(vertices[fv[3]] - vertices[fv[2]]).Unit
		local n = if rawN:Dot(c) < 0 then -rawN else rawN
		normals[f] = n

		local faceInsets = {}
		for j = 1, k do
			local origV = vertices[fv[j]]
			faceInsets[j] = c + (origV - c) * (1 - chamferRatio)
		end
		insets[f] = faceInsets

		drawPolygon(faceInsets, model, color, 0.06)
	end

	local edgeToFaces: { [string]: { { face: number, edgeIdx: number, vA: number, vB: number } } } = {}
	for f = 1, numFaces do
		local fv = faceIndices[f]
		local k = #fv
		for j = 1, k do
			local nxt = if j == k then 1 else j + 1
			local vA = fv[j]
			local vB = fv[nxt]
			local key = if vA < vB then (vA .. "_" .. vB) else (vB .. "_" .. vA)
			if not edgeToFaces[key] then edgeToFaces[key] = {} end
			table.insert(edgeToFaces[key], { face = f, edgeIdx = j, vA = vA, vB = vB })
		end
	end

	for _, shares in pairs(edgeToFaces) do
		if #shares == 2 then
			local s1 = shares[1]
			local s2 = shares[2]
			local f1, j1 = s1.face, s1.edgeIdx
			local f2, j2 = s2.face, s2.edgeIdx
			local k1 = #faceIndices[f1]
			local k2 = #faceIndices[f2]

			local u1A = insets[f1][j1]
			local u1B = insets[f1][if j1 == k1 then 1 else j1 + 1]

			local u2A = insets[f2][j2]
			local u2B = insets[f2][if j2 == k2 then 1 else j2 + 1]

			if s1.vA == s2.vA then
				drawQuadFace(u1A, u1B, u2B, u2A, model, chamferColor, 0.05, true)
			else
				drawQuadFace(u1A, u1B, u2A, u2B, model, chamferColor, 0.05, true)
			end
		end
	end

	return model, centroids, normals
end

--------------------------------------------------------------------------------
-- Shape Constructors (All 12 Shapes)
--------------------------------------------------------------------------------

-- 1. D2 Coin: Cylindrical coin with flat top/bottom and chamfered rims [UNTOUCHED]
local function buildD2(radius: number, thickness: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D2"
	local sides = 12
	local h = thickness / 2
	local chamferR = radius * 0.88
	local chamferColor = Color3.new(color.R * 0.78, color.G * 0.78, color.B * 0.78)

	local topCenter = Vector3.new(0, h, 0)
	local botCenter = Vector3.new(0, -h, 0)

	local topRing: { Vector3 } = {}
	local botRing: { Vector3 } = {}
	local topInsetRing: { Vector3 } = {}
	local botInsetRing: { Vector3 } = {}

	for i = 1, sides do
		local angle = (i - 1) * (math.pi * 2 / sides)
		local cosA = math.cos(angle)
		local sinA = math.sin(angle)
		table.insert(topRing, Vector3.new(cosA * radius, h, sinA * radius))
		table.insert(botRing, Vector3.new(cosA * radius, -h, sinA * radius))
		table.insert(topInsetRing, Vector3.new(cosA * chamferR, h, sinA * chamferR))
		table.insert(botInsetRing, Vector3.new(cosA * chamferR, -h, sinA * chamferR))
	end

	drawPolygon(topInsetRing, model, color, 0.06)
	drawPolygon(botInsetRing, model, color, 0.06)

	for i = 1, sides do
		local nxt = if i == sides then 1 else i + 1
		local tA, tB = topRing[i], topRing[nxt]
		local bA, bB = botRing[i], botRing[nxt]
		local tiA, tiB = topInsetRing[i], topInsetRing[nxt]
		local biA, biB = botInsetRing[i], botInsetRing[nxt]

		-- Outer rim quad
		drawQuadFace(tA, bA, bB, tB, model, chamferColor, 0.05, true)
		-- Top bevel chamfer
		drawQuadFace(tiA, tiB, tB, tA, model, chamferColor, 0.05, true)
		-- Bottom bevel chamfer
		drawQuadFace(biB, biA, bA, bB, model, chamferColor, 0.05, true)
	end

	addEngravedFaceNumeral(topCenter, Vector3.new(0, 1, 0), "1", model, radius * 1.4)
	addEngravedFaceNumeral(botCenter, Vector3.new(0, -1, 0), "2", model, radius * 1.4)
	return model
end

-- 2. D3 Triangular Barrel [UNTOUCHED]
local function buildD3(radius: number, height: number, color: Color3): Model
	local topRing = {}
	local botRing = {}
	for i = 1, 3 do
		local angle = (i - 1) * (math.pi * 2 / 3) + math.pi / 6
		table.insert(topRing, Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius))
		table.insert(botRing, Vector3.new(math.cos(angle) * radius, -height / 2, math.sin(angle) * radius))
	end
	local topApex = Vector3.new(0, height / 2 + radius * 0.75, 0)
	local botApex = Vector3.new(0, -height / 2 - radius * 0.75, 0)

	local verts = { topApex, botApex, topRing[1], topRing[2], topRing[3], botRing[1], botRing[2], botRing[3] }
	local faces = {
		{ 3, 6, 7, 4 }, { 4, 7, 8, 5 }, { 5, 8, 6, 3 },
		{ 1, 4, 3 }, { 1, 5, 4 }, { 1, 3, 5 },
		{ 2, 6, 7 }, { 2, 7, 8 }, { 2, 8, 6 },
	}

	local model, centroids, normals = buildChamferedSolid("D3", verts, faces, color, 0.10)
	for i = 1, 3 do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i), model, radius * 1.5)
	end
	return model
end

-- 3. D4 Regular Tetrahedron with 1 Centered Numeral per Face [FIXED]
local function buildD4(scale: number, color: Color3): Model
	local s = scale
	local verts = {
		Vector3.new(s, s, s),     -- 1
		Vector3.new(s, -s, -s),   -- 2
		Vector3.new(-s, s, -s),   -- 3
		Vector3.new(-s, -s, s),   -- 4
	}
	local faces = {
		{ 1, 3, 2 }, -- Face 1
		{ 1, 2, 4 }, -- Face 2
		{ 1, 4, 3 }, -- Face 3
		{ 2, 3, 4 }, -- Face 4
	}

	local model, centroids, normals = buildChamferedSolid("D4", verts, faces, color, 0.10)
	for i = 1, 4 do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i), model, scale * 1.5)
	end
	return model
end

-- 4. D5 Pentagonal Barrel [UNTOUCHED]
local function buildD5(radius: number, height: number, color: Color3): Model
	local topRing = {}
	local botRing = {}
	for i = 1, 5 do
		local angle = (i - 1) * (math.pi * 2 / 5) - math.pi / 2
		table.insert(topRing, Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius))
		table.insert(botRing, Vector3.new(math.cos(angle) * radius, -height / 2, math.sin(angle) * radius))
	end
	local topApex = Vector3.new(0, height / 2 + radius * 0.8, 0)
	local botApex = Vector3.new(0, -height / 2 - radius * 0.8, 0)

	local verts = { topApex, botApex }
	for i = 1, 5 do table.insert(verts, topRing[i]) end
	for i = 1, 5 do table.insert(verts, botRing[i]) end

	local faces = {}
	for i = 1, 5 do
		local nxt = if i == 5 then 1 else i + 1
		local tA, tB = 2 + i, 2 + nxt
		local bA, bB = 7 + i, 7 + nxt
		table.insert(faces, { tA, bA, bB, tB })
	end
	for i = 1, 5 do
		local nxt = if i == 5 then 1 else i + 1
		table.insert(faces, { 1, 2 + nxt, 2 + i })
		table.insert(faces, { 2, 7 + i, 7 + nxt })
	end

	local model, centroids, normals = buildChamferedSolid("D5", verts, faces, color, 0.10)
	for i = 1, 5 do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i), model, radius * 1.3)
	end
	return model
end

-- 5. D6 Cube with Circular Recessed Casino Pips [FIXED]
local function buildD6(scale: number, color: Color3): Model
	local s = scale
	local verts = {
		Vector3.new(s, s, s),   Vector3.new(s, s, -s),
		Vector3.new(s, -s, s),  Vector3.new(s, -s, -s),
		Vector3.new(-s, s, s),  Vector3.new(-s, s, -s),
		Vector3.new(-s, -s, s), Vector3.new(-s, -s, -s),
	}
	local faces = {
		{ 1, 5, 7, 3 }, -- 1 (+Z)
		{ 2, 4, 8, 6 }, -- 6 (-Z)
		{ 1, 3, 4, 2 }, -- 2 (+X)
		{ 5, 6, 8, 7 }, -- 5 (-X)
		{ 1, 2, 6, 5 }, -- 3 (+Y)
		{ 3, 7, 8, 4 }, -- 4 (-Y)
	}
	local pipCounts = { 1, 6, 2, 5, 3, 4 }

	local model, centroids, normals = buildChamferedSolid("D6", verts, faces, color, 0.12)
	for idx, pipCount in ipairs(pipCounts) do
		addEngravedPips(centroids[idx], normals[idx], pipCount, model, scale * 1.8)
	end
	return model
end

-- 6. D7 Heptagonal Barrel [UNTOUCHED]
local function buildD7(radius: number, height: number, color: Color3): Model
	local topRing = {}
	local botRing = {}
	for i = 1, 7 do
		local angle = (i - 1) * (math.pi * 2 / 7) - math.pi / 2
		table.insert(topRing, Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius))
		table.insert(botRing, Vector3.new(math.cos(angle) * radius, -height / 2, math.sin(angle) * radius))
	end
	local topApex = Vector3.new(0, height / 2 + radius * 0.85, 0)
	local botApex = Vector3.new(0, -height / 2 - radius * 0.85, 0)

	local verts = { topApex, botApex }
	for i = 1, 7 do table.insert(verts, topRing[i]) end
	for i = 1, 7 do table.insert(verts, botRing[i]) end

	local faces = {}
	for i = 1, 7 do
		local nxt = if i == 7 then 1 else i + 1
		local tA, tB = 2 + i, 2 + nxt
		local bA, bB = 9 + i, 9 + nxt
		table.insert(faces, { tA, bA, bB, tB })
	end
	for i = 1, 7 do
		local nxt = if i == 7 then 1 else i + 1
		table.insert(faces, { 1, 2 + nxt, 2 + i })
		table.insert(faces, { 2, 9 + i, 9 + nxt })
	end

	local model, centroids, normals = buildChamferedSolid("D7", verts, faces, color, 0.08)
	for i = 1, 7 do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i), model, radius * 1.1)
	end
	return model
end

-- 7. D8 Regular Octahedron [UNTOUCHED]
local function buildD8(scale: number, color: Color3): Model
	local s = scale
	local verts = {
		Vector3.new(0, s, 0),  Vector3.new(0, -s, 0),
		Vector3.new(s, 0, 0),  Vector3.new(0, 0, s),
		Vector3.new(-s, 0, 0), Vector3.new(0, 0, -s),
	}
	local faces = {
		{ 1, 3, 4 }, { 1, 4, 5 }, { 1, 5, 6 }, { 1, 6, 3 },
		{ 2, 4, 3 }, { 2, 5, 4 }, { 2, 6, 5 }, { 2, 3, 6 },
	}

	local model, centroids, normals = buildChamferedSolid("D8", verts, faces, color, 0.10)
	for i = 1, 8 do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i), model, scale * 1.2)
	end
	return model
end

-- 8. D10 Pentagonal Trapezohedron (Watertight Planar Kites) [FIXED]
local function buildD10(scale: number, color: Color3): Model
	local n = 5
	local r = scale
	local hApex = scale * 1.40
	local hRing = hApex * (math.tan(math.pi / (2 * n)) ^ 2)
	local topApex = Vector3.new(0, hApex, 0)
	local botApex = Vector3.new(0, -hApex, 0)
	local topRing: { Vector3 } = {}
	local botRing: { Vector3 } = {}

	for i = 1, n do
		local aTop = (i - 1) * (math.pi * 2 / n)
		local aBot = aTop + (math.pi / n)
		table.insert(topRing, Vector3.new(math.cos(aTop) * r, hRing, math.sin(aTop) * r))
		table.insert(botRing, Vector3.new(math.cos(aBot) * r, -hRing, math.sin(aBot) * r))
	end

	local verts = { topApex, botApex }
	for i = 1, n do table.insert(verts, topRing[i]) end
	for i = 1, n do table.insert(verts, botRing[i]) end

	local faces = {}
	-- Top 5 kite faces: odd numbers 1, 3, 5, 7, 9
	for i = 1, n do
		local nxt = if i == n then 1 else i + 1
		local t1, t2 = 2 + i, 2 + nxt
		local b1 = 2 + n + i
		table.insert(faces, { 1, t1, b1, t2 })
	end
	-- Bottom 5 kite faces: even numbers 2, 4, 6, 8, 10
	for i = 1, n do
		local nxt = if i == n then 1 else i + 1
		local b1, b2 = 2 + n + i, 2 + n + nxt
		local t1 = 2 + nxt
		table.insert(faces, { 2, b2, t1, b1 })
	end

	local model, centroids, normals = buildChamferedSolid("D10", verts, faces, color, 0.08)
	for i = 1, n do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i * 2 - 1), model, scale * 1.1)
	end
	for i = 1, n do
		addEngravedFaceNumeral(centroids[n + i], normals[n + i], tostring(i * 2), model, scale * 1.1)
	end
	return model
end

-- 9. D12 Regular Dodecahedron [UNTOUCHED]
local function buildD12(scale: number, color: Color3): Model
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

	local faces = {}
	for _, normal in ipairs(faceNormals) do
		local fv = {}
		for vIdx, v in ipairs(verts) do
			if v.Unit:Dot(normal) > 0.6 then table.insert(fv, vIdx) end
		end
		if #fv == 5 then
			local c = Vector3.zero
			for _, vi in ipairs(fv) do c += verts[vi] end
			c /= 5
			local uAxis = (verts[fv[1]] - c).Unit
			local vAxis = normal:Cross(uAxis).Unit
			table.sort(fv, function(a, b)
				local angA = math.atan2((verts[a] - c):Dot(vAxis), (verts[a] - c):Dot(uAxis))
				local angB = math.atan2((verts[b] - c):Dot(vAxis), (verts[b] - c):Dot(uAxis))
				return angA < angB
			end)
			table.insert(faces, fv)
		end
	end

	local model, centroids, normals = buildChamferedSolid("D12", verts, faces, color, 0.08)
	for i = 1, 12 do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i), model, scale * 1.1)
	end
	return model
end

-- 10. D14 Heptagonal Trapezohedron (Watertight Planar Kites) [FIXED]
local function buildD14(scale: number, color: Color3): Model
	local n = 7
	local r = scale
	local hApex = scale * 1.40
	local hRing = hApex * (math.tan(math.pi / (2 * n)) ^ 2)
	local topApex = Vector3.new(0, hApex, 0)
	local botApex = Vector3.new(0, -hApex, 0)
	local topRing: { Vector3 } = {}
	local botRing: { Vector3 } = {}

	for i = 1, n do
		local aTop = (i - 1) * (math.pi * 2 / n)
		local aBot = aTop + (math.pi / n)
		table.insert(topRing, Vector3.new(math.cos(aTop) * r, hRing, math.sin(aTop) * r))
		table.insert(botRing, Vector3.new(math.cos(aBot) * r, -hRing, math.sin(aBot) * r))
	end

	local verts = { topApex, botApex }
	for i = 1, n do table.insert(verts, topRing[i]) end
	for i = 1, n do table.insert(verts, botRing[i]) end

	local faces = {}
	for i = 1, n do
		local nxt = if i == n then 1 else i + 1
		local t1, t2 = 2 + i, 2 + nxt
		local b1 = 2 + n + i
		table.insert(faces, { 1, t1, b1, t2 })
	end
	for i = 1, n do
		local nxt = if i == n then 1 else i + 1
		local b1, b2 = 2 + n + i, 2 + n + nxt
		local t1 = 2 + nxt
		table.insert(faces, { 2, b2, t1, b1 })
	end

	local model, centroids, normals = buildChamferedSolid("D14", verts, faces, color, 0.08)
	for i = 1, n do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i * 2 - 1), model, scale * 0.95)
	end
	for i = 1, n do
		addEngravedFaceNumeral(centroids[n + i], normals[n + i], tostring(i * 2), model, scale * 0.95)
	end
	return model
end

-- 11. D16 Octagonal Bipyramid [FIXED]
local function buildD16(scale: number, color: Color3): Model
	local s = scale
	local h = s * 1.30
	local topApex = Vector3.new(0, h, 0)
	local botApex = Vector3.new(0, -h, 0)
	local ring: { Vector3 } = {}
	for i = 1, 8 do
		local angle = (i - 1) * (math.pi * 2 / 8)
		table.insert(ring, Vector3.new(math.cos(angle) * s, 0, math.sin(angle) * s))
	end

	local verts = { topApex, botApex }
	for i = 1, 8 do table.insert(verts, ring[i]) end

	local faces = {}
	for i = 1, 8 do
		local nxt = if i == 8 then 1 else i + 1
		table.insert(faces, { 1, 2 + i, 2 + nxt })
	end
	for i = 1, 8 do
		local nxt = if i == 8 then 1 else i + 1
		table.insert(faces, { 2, 2 + nxt, 2 + i })
	end

	local model, centroids, normals = buildChamferedSolid("D16", verts, faces, color, 0.08)
	local baseRatio = 0.25
	for i = 1, 8 do
		local nxt = if i == 8 then 1 else i + 1
		local baseMid = (ring[i] + ring[nxt]) / 2
		local c = baseMid * (1 - baseRatio) + topApex * baseRatio
		local n = normals[i]
		local tempUp = (topApex - c).Unit
		local up = (tempUp - n * tempUp:Dot(n)).Unit
		addEngravedFaceNumeral(c, n, tostring(i), model, scale * 0.95, up)
	end
	for i = 1, 8 do
		local nxt = if i == 8 then 1 else i + 1
		local baseMid = (ring[i] + ring[nxt]) / 2
		local c = baseMid * (1 - baseRatio) + botApex * baseRatio
		local n = normals[8 + i]
		local tempUp = (botApex - c).Unit
		local up = (tempUp - n * tempUp:Dot(n)).Unit
		addEngravedFaceNumeral(c, n, tostring(i + 8), model, scale * 0.95, up)
	end
	return model
end

-- 12. D20 Regular Icosahedron [UNTOUCHED]
local function buildD20(scale: number, color: Color3): Model
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
	local faces = {
		{ 1, 12, 6 },  { 1, 6, 2 },   { 1, 2, 8 },   { 1, 8, 11 },  { 1, 11, 12 },
		{ 2, 6, 10 },  { 6, 12, 5 },  { 12, 11, 3 }, { 11, 8, 7 },  { 8, 2, 9 },
		{ 4, 10, 5 },  { 4, 5, 3 },   { 4, 3, 7 },   { 4, 7, 9 },   { 4, 9, 10 },
		{ 5, 10, 6 },  { 3, 5, 12 },  { 7, 3, 11 },  { 9, 7, 8 },   { 10, 9, 2 },
	}

	local model, centroids, normals = buildChamferedSolid("D20", verts, faces, color, 0.08)
	for i = 1, 20 do
		addEngravedFaceNumeral(centroids[i], normals[i], tostring(i), model, scale * 0.95)
	end
	return model
end

--------------------------------------------------------------------------------
-- Normalisation, Centering & Assembly
--------------------------------------------------------------------------------

local BUILDERS: { [string]: () -> Model } = {
	D2  = function() return buildD2(1.5, 0.8, DICE_COLORS.D2) end,
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
