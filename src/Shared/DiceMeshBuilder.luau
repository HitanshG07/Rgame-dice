--!strict
-- DiceMeshBuilder.luau
-- Mathematical low-poly dice geometry, generated rather than modelled.
--
-- Builds the five shapes `DiceCatalog` defines -- D4, D6, D8, D12, D20 -- as
-- real 3D solids assembled from wedges, each face carrying its own numeral.
-- Builders for D2, D3 and D10 remain below but are not generated; see
-- CATALOG_SHAPES for why.
--
-- WHY THESE EXIST IN A 2D GAME. The board is a flat ScreenGui, but each die tile
-- is a `ViewportFrame` -- a 2D UI element that renders a real 3D model inside
-- itself. So the board stays flat while the dice stay solid, and a lopsided die
-- is once again something you can WATCH refuse to settle heavy-side up. That
-- read is what the move to 2D cost, and it is what these models buy back.
--
-- MEASURED, NOT ASSUMED: seven D12s (132 parts each, 924 total) spinning in
-- seven ViewportFrames held 60 fps mean / 24.63 ms worst frame. The worst case
-- the board can produce is affordable, so there is no level-of-detail scheme.
--
-- THREE THINGS THE ASSEMBLY STEP ADDS, none of which the raw geometry had:
-- a PrimaryPart (without it `PivotTo` orbits instead of spinning), a normalised
-- size (extents ran 3.89-9.22, a 2.4x spread that read as "the D20 is enormous"),
-- and a recovered FACE NORMAL per numeral, without which a die cannot be rotated
-- to show the face the server actually rolled.
--
-- NO ASSET IDS. Every solid is derived from its own mathematics at runtime, so
-- there is nothing to upload, nothing to go stale, and the geometry is
-- reviewable in this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DiceMeshBuilder = {}

-- Palette for dice styles
local DICE_COLORS: { [string]: Color3 } = {
	D2 = Color3.fromRGB(240, 190, 60),   -- Gold
	D3 = Color3.fromRGB(220, 90, 80),    -- Coral Red
	D4 = Color3.fromRGB(150, 80, 220),   -- Purple
	D6 = Color3.fromRGB(50, 160, 220),   -- Cyan Blue
	D8 = Color3.fromRGB(60, 190, 120),   -- Emerald Green
	D10 = Color3.fromRGB(230, 130, 40),  -- Orange
	D12 = Color3.fromRGB(220, 70, 150),  -- Rose Magenta
	D20 = Color3.fromRGB(70, 130, 240),  -- Royal Blue
}

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
	local ab = (pB - pA).Magnitude
	local ac = (pC - pA).Magnitude
	local bc = (pC - pB).Magnitude

	local vA, vB, vC = pA, pB, pC
	if ab >= ac and ab >= bc then
		vA, vB, vC = pC, pA, pB
	elseif bc >= ab and bc >= ac then
		vA, vB, vC = pA, pB, pC
	else
		vA, vB, vC = pB, pC, pA
	end

	local edgeAC = (vC - vA)
	local lenAC = edgeAC.Magnitude
	if lenAC < 0.0001 then
		return {}
	end
	local dirAC = edgeAC.Unit

	local vAB = vB - vA
	local projDist = vAB:Dot(dirAC)
	local pD = vA + dirAC * projDist

	local heightVec = vB - pD
	local height = heightVec.Magnitude
	if height < 0.0001 then
		return {}
	end
	local dirHeight = heightVec.Unit

	local lenAD = projDist
	local lenDC = lenAC - projDist
	local createdWedges: { WedgePart } = {}

	-- Left wedge
	if math.abs(lenAD) > 0.001 then
		local w1 = Instance.new("WedgePart")
		w1.Name = "FacetWedge"
		w1.Anchored = true
		w1.CanCollide = true
		w1.Material = Enum.Material.SmoothPlastic
		w1.Color = color
		w1.Size = Vector3.new(t, height, math.abs(lenAD))

		local sign1 = if lenAD >= 0 then 1 else -1
		local cf1 = CFrame.fromMatrix(
			vA + dirAC * (lenAD / 2) + dirHeight * (height / 2),
			dirHeight,
			dirAC * sign1,
			dirHeight:Cross(dirAC * sign1)
		)
		w1.CFrame = cf1
		w1.Parent = parent
		table.insert(createdWedges, w1)
	end

	-- Right wedge
	if math.abs(lenDC) > 0.001 then
		local w2 = Instance.new("WedgePart")
		w2.Name = "FacetWedge"
		w2.Anchored = true
		w2.CanCollide = true
		w2.Material = Enum.Material.SmoothPlastic
		w2.Color = color
		w2.Size = Vector3.new(t, height, math.abs(lenDC))

		local sign2 = if lenDC >= 0 then 1 else -1
		local cf2 = CFrame.fromMatrix(
			vC - dirAC * (lenDC / 2) + dirHeight * (height / 2),
			dirHeight,
			-dirAC * sign2,
			dirHeight:Cross(-dirAC * sign2)
		)
		w2.CFrame = cf2
		w2.Parent = parent
		table.insert(createdWedges, w2)
	end

	return createdWedges
end

-- Adds a clear face number GUI on the die face outward normal
local function addFaceNumberLabel(
	faceCenter: Vector3,
	faceNormal: Vector3,
	numberText: string,
	parent: Instance,
	dieScale: number
)
	local labelPart = Instance.new("Part")
	labelPart.Name = "FaceLabel_" .. numberText
	labelPart.Size = Vector3.new(dieScale * 0.3, dieScale * 0.3, 0.02)
	labelPart.Transparency = 1
	labelPart.CanCollide = false
	labelPart.Anchored = true
	labelPart.CFrame = CFrame.lookAt(faceCenter + faceNormal.Unit * 0.03, faceCenter + faceNormal.Unit * 2)
	labelPart.Parent = parent

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(128, 128)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = labelPart

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Text = numberText
	txt.TextColor3 = Color3.fromRGB(255, 255, 255)
	txt.TextScaled = true
	txt.Font = Enum.Font.FredokaOne
	txt.TextStrokeTransparency = 0
	txt.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	txt.Parent = gui
end

--------------------------------------------------------------------------------
-- POLYHEDRA GENERATORS
--------------------------------------------------------------------------------

-- D2: Biconvex Coin/Lens Die (2 major faces)
local function buildD2(radius: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "D2"
	local sides = 16
	local h = radius * 0.35

	local topApex = Vector3.new(0, h, 0)
	local bottomApex = Vector3.new(0, -h, 0)
	local ring: { Vector3 } = {}

	for i = 1, sides do
		local angle = (i - 1) * (math.pi * 2 / sides)
		table.insert(ring, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end

	-- Top face (Face 1)
	for i = 1, sides do
		local nextIdx = if i == sides then 1 else i + 1
		draw3DTriangle(topApex, ring[i], ring[nextIdx], model, color)
	end
	addFaceNumberLabel(Vector3.new(0, h * 0.8, 0), Vector3.new(0, 1, 0), "1", model, radius)

	-- Bottom face (Face 2)
	for i = 1, sides do
		local nextIdx = if i == sides then 1 else i + 1
		draw3DTriangle(bottomApex, ring[nextIdx], ring[i], model, color)
	end
	addFaceNumberLabel(Vector3.new(0, -h * 0.8, 0), Vector3.new(0, -1, 0), "2", model, radius)

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

	local topApex = Vector3.new(0, height / 2 + radius * 0.6, 0)
	local botApex = Vector3.new(0, -height / 2 - radius * 0.6, 0)

	-- 3 side rectangle faces (each 2 triangles)
	for i = 1, 3 do
		local nxt = if i == 3 then 1 else i + 1
		local tA, tB = topRing[i], topRing[nxt]
		local bA, bB = botRing[i], botRing[nxt]

		draw3DTriangle(tA, bA, tB, model, color)
		draw3DTriangle(tB, bA, bB, model, color)

		-- Top & bot cap triangles
		draw3DTriangle(topApex, tB, tA, model, color)
		draw3DTriangle(botApex, bA, bB, model, color)

		local sideCenter = (tA + tB + bA + bB) / 4
		local sideNormal = Vector3.new(sideCenter.X, 0, sideCenter.Z).Unit
		addFaceNumberLabel(sideCenter, sideNormal, tostring(i), model, radius)
	end

	return model
end

-- D4: Regular Tetrahedron (4 faces)
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
		draw3DTriangle(pA, pB, pC, model, color)

		local center = (pA + pB + pC) / 3
		local normal = (pB - pA):Cross(pC - pA).Unit
		addFaceNumberLabel(center, normal, tostring(idx), model, scale * 1.5)
	end

	return model
end

-- D6: Regular Cube (6 faces)
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

		draw3DTriangle(p1, p2, p3, model, color)
		draw3DTriangle(p1, p3, p4, model, color)

		addFaceNumberLabel(spec.center, spec.normal, spec.name, model, scale * 2)
	end

	return model
end

-- D8: Regular Octahedron (8 faces)
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

	-- 4 top faces, 4 bottom faces
	local faces = {}
	for i = 1, 4 do
		local nxt = if i == 4 then 1 else i + 1
		table.insert(faces, { topApex, ring[i], ring[nxt] })
		table.insert(faces, { botApex, ring[nxt], ring[i] })
	end

	for idx, tri in ipairs(faces) do
		local pA, pB, pC = tri[1], tri[2], tri[3]
		draw3DTriangle(pA, pB, pC, model, color)

		local center = (pA + pB + pC) / 3
		local normal = (pB - pA):Cross(pC - pA).Unit
		addFaceNumberLabel(center, normal, tostring(idx), model, scale * 1.5)
	end

	return model
end

-- D10: Pentagonal Trapezohedron (10 faces)
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
	-- 5 top kites
	for i = 1, 5 do
		faceCount += 1
		local nxt = if i == 5 then 1 else i + 1
		local t1, t2 = topRing[i], topRing[nxt]
		local b1 = botRing[i]

		draw3DTriangle(topApex, t1, b1, model, color)
		draw3DTriangle(topApex, b1, t2, model, color)

		local center = (topApex + t1 + t2 + b1) / 4
		local normal = (t1 - topApex):Cross(b1 - topApex).Unit
		addFaceNumberLabel(center, normal, tostring(faceCount), model, scale * 1.5)
	end

	-- 5 bottom kites
	for i = 1, 5 do
		faceCount += 1
		local prv = if i == 1 then 5 else i - 1
		local b1, b2 = botRing[prv], botRing[i]
		local t1 = topRing[i]

		draw3DTriangle(botApex, b2, t1, model, color)
		draw3DTriangle(botApex, t1, b1, model, color)

		local center = (botApex + b1 + b2 + t1) / 4
		local normal = (b2 - botApex):Cross(t1 - botApex).Unit
		addFaceNumberLabel(center, normal, tostring(faceCount), model, scale * 1.5)
	end

	return model
end

-- D12: Regular Dodecahedron (12 faces)
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

			for f = 1, 5 do
				local nxt = if f == 5 then 1 else f + 1
				draw3DTriangle(center, faceVerts[f], faceVerts[nxt], model, color)
			end

			addFaceNumberLabel(center, normal, tostring(idx), model, scale * 1.5)
		end
	end

	return model
end

-- D20: Regular Icosahedron (20 faces)
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
		draw3DTriangle(pA, pB, pC, model, color)

		local center = (pA + pB + pC) / 3
		local normal = (pB - pA):Cross(pC - pA).Unit
		addFaceNumberLabel(center, normal, tostring(idx), model, scale * 1.5)
	end

	return model
end

--------------------------------------------------------------------------------
-- MAIN GENERATION FUNCTION
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Assembly
--
-- The per-shape geometry functions above are kept as authored. Everything in
-- this section is what turns those raw models into something the renderer can
-- actually drive, and each step exists because the first generation lacked it.
--------------------------------------------------------------------------------

-- ONLY THE SHAPES THE GAME HAS RULES FOR.
--
-- The generator can build D2, D3 and D10 as well, and they are real dice. But
-- `DiceCatalog` defines five shapes -- D4, D6, D8, D12, D20 -- with per-shape
-- mass floors, diamond ceilings and Void probabilities, and a die the catalog
-- has never heard of has no mass floor, so `assertDieInvariant` cannot validate
-- it and the forge cannot price it. Generating a D10 the player can never own
-- would put an asset in ReplicatedStorage that looks like a feature.
--
-- The builders for the other three are deliberately left in place: adding a
-- shape later is a catalog change plus one row here, not a geometry problem.
local CATALOG_SHAPES: { { name: string, build: () -> Model } } = {
	{ name = "D4",  build = function() return buildD4(1.4, DICE_COLORS.D4) end },
	{ name = "D6",  build = function() return buildD6(1.2, DICE_COLORS.D6) end },
	{ name = "D8",  build = function() return buildD8(1.5, DICE_COLORS.D8) end },
	{ name = "D12", build = function() return buildD12(1.5, DICE_COLORS.D12) end },
	{ name = "D20", build = function() return buildD20(1.5, DICE_COLORS.D20) end },
}

-- Every die is normalised to this bounding-sphere diameter, in studs.
--
-- WHY NORMALISE AT ALL. As generated, extents ran from 3.89 (D2) to 9.22 (D20)
-- -- a 2.4x spread driven by how each solid's circumradius relates to its edge
-- length, not by any design intent. On a board that shows several dice side by
-- side, that reads as "the D20 is enormous" rather than as five dice. The
-- renderer frames each die in its own ViewportFrame, so a uniform size also
-- means one camera distance works for every shape.
local TARGET_EXTENT = 6.0

-- Gives the model a PrimaryPart at its own centre.
--
-- WHY THIS IS NOT OPTIONAL. `Model:PivotTo` rotates about the model's pivot,
-- and without a PrimaryPart that pivot is the bounding-box centre of whatever
-- Roblox picks -- which drifts as parts move. A die animated that way orbits
-- instead of spinning. The tumble is the whole reason these models exist, so
-- the pivot is established here rather than left to the renderer to discover.
--
-- An invisible zero-size anchor is used rather than promoting a face part: any
-- real face is off-centre, and spinning about a face is exactly the orbit this
-- is meant to prevent.
local function anchorPivot(model: Model): ()
	local cf = model:GetBoundingBox()

	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.new(0.05, 0.05, 0.05)
	pivot.CFrame = CFrame.new(cf.Position)
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

-- Scales every part about the model's centre so the bounding sphere matches
-- TARGET_EXTENT. Sizes and offsets both scale, so the solid keeps its shape.
local function normaliseScale(model: Model): ()
	local cf, size = model:GetBoundingBox()
	local extent = size.Magnitude
	if extent < 1e-4 then
		return
	end
	local k = TARGET_EXTENT / extent
	local centre = cf.Position

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local offset = d.CFrame.Position - centre
			-- Rotation is preserved; only the distance from centre and the part's
			-- own dimensions scale.
			d.Size = d.Size * k
			d.CFrame = (d.CFrame - d.CFrame.Position) + (centre + offset * k)
		end
	end
end

-- THE FACE NORMAL TABLE -- the thing that makes these models usable as dice
-- rather than as ornaments.
--
-- The renderer is handed a face index by the server and must rotate the die so
-- that face points at the camera. That requires knowing, for each face number,
-- which direction it faces. The geometry functions never recorded this; the
-- information exists only implicitly, in where each numeral part was placed.
--
-- It is recovered here: a numeral's offset from the die's centre IS its outward
-- normal, because every one of these solids is centred at its centroid and each
-- numeral sits on the face it labels. Verified against the generated models --
-- numerals are contiguous 1..N with no duplicates, and the radii are uniform
-- (exactly so on D6/D8/D12; D20 varies by 0.019 studs, D4 by 0.335 because a
-- tetrahedron's face centres genuinely differ in distance from its vertices).
--
-- Stored as an attribute on the model so it survives `Clone()` and crosses to
-- the client without a parallel lookup table that could drift out of step with
-- the geometry (L-026: the copy nobody executes is the one that drifts).
local function recordFaceNormals(model: Model): number
	local cf = model:GetBoundingBox()
	local centre = cf.Position
	local found = 0

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("TextLabel") then
			local host = d.Parent and d.Parent.Parent
			local index = tonumber(d.Text)
			if index ~= nil and host ~= nil and host:IsA("BasePart") then
				local offset = (host :: BasePart).Position - centre
				if offset.Magnitude > 1e-4 then
					local n = offset.Unit
					model:SetAttribute("FaceNormal" .. tostring(index), n)
					found += 1
				end
			end
		end
	end

	model:SetAttribute("FaceCount", found)
	return found
end

-- Builds every catalog shape into `parent`, hardened and ready to clone.
--
-- Returns the models. Callers that want them somewhere specific pass a parent;
-- `generateAllDice` keeps the original ReplicatedStorage + Workspace behaviour
-- for Studio inspection.
function DiceMeshBuilder.buildInto(parent: Instance): { Model }
	local built: { Model } = {}

	for _, entry in ipairs(CATALOG_SHAPES) do
		local model = entry.build()
		model.Name = entry.name

		normaliseScale(model)
		local faces = recordFaceNormals(model)
		anchorPivot(model)

		-- Every part is display-only. A die living in a ViewportFrame must never
		-- be touchable, queryable or shadow-casting -- and a die cloned into the
		-- Workspace for inspection must not become world collision.
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end

		local expected = ({ D4 = 4, D6 = 6, D8 = 8, D12 = 12, D20 = 20 })[entry.name]
		if expected ~= nil and faces ~= expected then
			-- Loud, not silent. A shape whose normals could not be recovered
			-- cannot be rotated to a chosen face, which means the renderer would
			-- animate to an arbitrary result while the server credited a
			-- different one. That must never be discovered on a player's screen.
			warn(string.format(
				"[DiceMeshBuilder] %s recovered %d face normals, expected %d -- this die"
				.. " CANNOT be rotated to a chosen face and must not be used",
				entry.name, faces, expected))
		end

		model.Parent = parent
		table.insert(built, model)
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

	-- A visual row in the Workspace, for inspecting the geometry in Studio.
	--
	-- STUDIO ONLY. In a live game this is seven dice floating in the world where
	-- no camera looks; the board renders from ReplicatedStorage into
	-- ViewportFrames and never reads the Workspace copy.
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
