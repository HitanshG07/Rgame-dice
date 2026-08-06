--!strict
-- DiceRenderer.luau
--
-- ============================================================================
-- THE ANIMATION IS NOT AUTHORITATIVE. READ THIS BEFORE CHANGING ANYTHING HERE.
--
-- By the time this module hears about a roll, the server has ALREADY sampled
-- the face, ALREADY computed the payout, and ALREADY credited the player's
-- Cash. `RollResult` arrives after the transaction is committed (SRS FR-2.2,
-- API_DATA_CONTRACT §1.2). What follows in this file is a tumble that RESOLVES
-- TO a face that is already true.
--
-- IF THE CLIENT DISCONNECTS, TABS OUT, OR DROPS EVERY FRAME OF THIS ANIMATION,
-- THE CREDITED PAYOUT IS COMPLETELY UNAFFECTED (SRS FR-2.6). Nothing in this
-- module is on the economic path. There is no branch anywhere below that can
-- change a face, a payout, or a balance, and there must never be one.
--
-- The temptation this comment exists to defuse: it will one day look natural to
-- "let the die decide" -- to simulate a real tumble and read the up-face off the
-- result, because that is how dice work in the physical world. Doing that hands
-- outcome authority to the client, which is threat T-1 and the single thing the
-- entire server design exists to prevent. The physics body is decorative
-- (HLD §4.3); the die is driven kinematically to an orientation computed FROM
-- the server's answer.
-- ============================================================================
--
-- HOW THE RESOLUTION WORKS (HLD §4.3, implemented literally):
--   1. Pick one of several PRE-AUTHORED tumble trajectories. Each is a fixed
--      list of orientation keyframes whose LAST keyframe is the identity, so
--      every trajectory ends with a known face up by construction.
--   2. Compute the single rotation `R` that carries the target face's normal to
--      world up.
--   3. Play `R * keyframe(t)`. At t = 1 the keyframe is identity, so the die
--      finishes at exactly `R` -- the server's face, up. The trajectory chooses
--      the CHARACTER of the tumble; it can never choose the ANSWER.
--   4. Duration scales with payout, so a large win physically takes longer to
--      land than a small one.
--
-- ON POOLING (NFR-1): every Instance this module will ever need is created in
-- `init` -- seven dice, each with a core and twenty face plates. Nothing is
-- created, destroyed, or reparented during a roll, and the per-frame loop
-- allocates no Lua table, no closure, and no Instance. Changing shape moves
-- existing plates; it never makes new ones.
--
-- ON FR-1.3, mass legibility without a menu: a face's invested mass is carried
-- on THREE simultaneous channels -- plate scale, how far the plate protrudes
-- from the core (inset depth), and emissive glow. Three channels rather than
-- one because any single channel is ambiguous at a glance and because a
-- colour-blind player must still be able to read the die.

local RunService = game:GetService("RunService")

local Client = script.Parent
local UITheme = require(Client:WaitForChild("UITheme"))
local ArenaView = require(Client:WaitForChild("ArenaView"))

local DiceRenderer = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_DICE = 7                 -- SRS FR-1.1
local MAX_FACES = 20               -- the D20, the largest shape in DiceCatalog
local DEFAULT_SHAPE = "D6"

local DIE_SIZE = 2.0               -- studs, the full width of a die
local DIE_RADIUS = DIE_SIZE * 0.5  -- half-extent, used for FR-1.4 containment
local CORE_SCALE = 0.74            -- the core solid, as a fraction of DIE_SIZE
local PLATE_THICK = 0.16

-- Inset depth range (FR-1.3). A minimum-mass face sits flush; a maximum-mass
-- face stands proud. The difference is deliberately large enough to read from
-- the top-down camera.
local INSET_MIN = -0.06
local INSET_MAX = 0.16

-- Plate scale range (FR-1.3), as a multiplier on the shape's base plate size.
local PLATE_SCALE_MIN = 0.66
local PLATE_SCALE_MAX = 1.12

-- Above this normalised mass a face is lit rather than merely tinted.
local GLOW_THRESHOLD = 0.55

local MIN_DURATION = 0.85
local MAX_DURATION = 2.40
local BOUNCES = 2.5
local HOP_HEIGHT = 2.6

--------------------------------------------------------------------------------
-- Face normals, generated from the actual polyhedra.
--
-- These are the real face normals of the tetrahedron, cube, octahedron,
-- dodecahedron and icosahedron, so face index i genuinely corresponds to a
-- distinct direction on the solid and no two faces can share one. Generated
-- once at load in a fixed order, which makes "face 3" mean the same direction
-- on every client, every session.
--------------------------------------------------------------------------------

local PHI = (1 + math.sqrt(5)) / 2

local function normalsFor(shapeId: string): { Vector3 }
	local out: { Vector3 } = {}

	local function push(x: number, y: number, z: number): ()
		out[#out + 1] = Vector3.new(x, y, z).Unit
	end

	if shapeId == "D4" then
		push(1, 1, 1); push(1, -1, -1); push(-1, 1, -1); push(-1, -1, 1)
	elseif shapeId == "D6" then
		push(0, 1, 0); push(1, 0, 0); push(0, 0, 1)
		push(-1, 0, 0); push(0, 0, -1); push(0, -1, 0)
	elseif shapeId == "D8" then
		for _, sx in ipairs({ 1, -1 }) do
			for _, sy in ipairs({ 1, -1 }) do
				for _, sz in ipairs({ 1, -1 }) do
					push(sx, sy, sz)
				end
			end
		end
	elseif shapeId == "D12" then
		-- the twelve cyclic permutations of (0, +/-1, +/-phi)
		for _, sa in ipairs({ 1, -1 }) do
			for _, sb in ipairs({ 1, -1 }) do
				push(0, sa * 1, sb * PHI)
				push(sa * 1, sb * PHI, 0)
				push(sa * PHI, 0, sb * 1)
			end
		end
	elseif shapeId == "D20" then
		-- eight cube corners plus twelve cyclic permutations of (0, +/-1/phi, +/-phi)
		for _, sx in ipairs({ 1, -1 }) do
			for _, sy in ipairs({ 1, -1 }) do
				for _, sz in ipairs({ 1, -1 }) do
					push(sx, sy, sz)
				end
			end
		end
		for _, sa in ipairs({ 1, -1 }) do
			for _, sb in ipairs({ 1, -1 }) do
				push(0, sa / PHI, sb * PHI)
				push(sa / PHI, sb * PHI, 0)
				push(sa * PHI, 0, sb / PHI)
			end
		end
	end

	return out
end

local NORMALS: { [string]: { Vector3 } } = {
	D4 = normalsFor("D4"),
	D6 = normalsFor("D6"),
	D8 = normalsFor("D8"),
	D12 = normalsFor("D12"),
	D20 = normalsFor("D20"),
}

-- Base plate half-size per shape. A d20's faces are small; a d4's are enormous.
-- Ball-cored shapes also want a slightly larger stand-off so the plates read as
-- facets rather than as decals.
local PLATE_BASE: { [string]: number } = {
	D4 = 0.62,
	D6 = 0.56,
	D8 = 0.44,
	D12 = 0.33,
	D20 = 0.27,
}

local BLOCK_CORE: { [string]: boolean } = { D4 = true, D6 = true }

--------------------------------------------------------------------------------
-- Pre-authored tumble trajectories (HLD §4.3).
--
-- Each spec is an axis and a number of full turns. The keyframes count that
-- rotation DOWN to zero, so the final keyframe is the identity and the terminal
-- face of every trajectory is known before the server has said anything.
--------------------------------------------------------------------------------

local KEYFRAMES = 7

local TRAJECTORY_SPECS: { { axis: Vector3, turns: number } } = {
	{ axis = Vector3.new(1, 0.35, 0.15), turns = 3 },
	{ axis = Vector3.new(0.2, 1, 0.4), turns = 4 },
	{ axis = Vector3.new(0.6, -0.3, 1), turns = 3 },
	{ axis = Vector3.new(-0.8, 0.5, 0.6), turns = 5 },
	{ axis = Vector3.new(0.1, -1, 0.25), turns = 4 },
}

local function buildTrajectories(): { { CFrame } }
	local all: { { CFrame } } = {}
	for t, spec in ipairs(TRAJECTORY_SPECS) do
		local axis = spec.axis.Unit
		local total = spec.turns * math.pi * 2
		local frames: { CFrame } = {}
		for k = 1, KEYFRAMES do
			-- remaining rotation, easing out so the die slows as it settles
			local progress = (k - 1) / (KEYFRAMES - 1)
			local remaining = total * (1 - progress) * (1 - progress)
			frames[k] = CFrame.fromAxisAngle(axis, remaining)
		end
		frames[KEYFRAMES] = CFrame.identity  -- exact, not merely near-zero
		all[t] = frames
	end
	return all
end

local TRAJECTORIES: { { CFrame } } = buildTrajectories()

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

type Plate = {
	part: Part,
	gui: SurfaceGui,
	label: TextLabel,
}

type DieVisual = {
	model: Model,
	core: Part,
	plates: { Plate },
	shape: string,
	faceCount: number,
}

type DieSlot = {
	visual: DieVisual,
	inUse: boolean,
	animating: boolean,
	elapsed: number,
	duration: number,
	startPos: Vector3,
	endPos: Vector3,
	trajectory: number,
	finalRot: CFrame,
}

--------------------------------------------------------------------------------
-- State. Fixed size, allocated once.
--------------------------------------------------------------------------------

local slots: { DieSlot } = {}
local started = false
local rng = Random.new()

-- Last authoritative dice configuration seen on StateSync. Display only: it
-- decides how a die LOOKS, never what it rolls.
local diceConfig: { any } = {}

--------------------------------------------------------------------------------
-- Construction (init only -- never called during a roll)
--------------------------------------------------------------------------------

local function makePlate(parent: Instance, index: number): Plate
	local part = Instance.new("Part")
	part.Name = "Face" .. tostring(index)
	part.Size = Vector3.new(1, 1, PLATE_THICK)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = UITheme.Colors.PanelMaroon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	-- Emissive numerals (FR-1.2). LightInfluence = 0 is what makes the numeral
	-- self-lit rather than a painted decal that goes black in the pit's shadow.
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Numeral"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 64
	surface.LightInfluence = 0
	surface.AlwaysOnTop = false
	surface.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font
	label.TextScaled = true
	label.TextColor3 = UITheme.Colors.TextPrimary
	label.Text = tostring(index)
	label.Parent = surface

	return { part = part, gui = surface, label = label }
end

local function makeVisual(index: number): DieVisual
	local model = Instance.new("Model")
	model.Name = "Die" .. tostring(index)

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.one * (DIE_SIZE * CORE_SCALE)
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Material = Enum.Material.SmoothPlastic
	core.Color = UITheme.Colors.PanelDeep
	core.TopSurface = Enum.SurfaceType.Smooth
	core.BottomSurface = Enum.SurfaceType.Smooth
	core.Parent = model

	model.PrimaryPart = core

	local plates: { Plate } = {}
	for f = 1, MAX_FACES do
		plates[f] = makePlate(model, f)
	end

	return {
		model = model,
		core = core,
		plates = plates,
		shape = "",
		faceCount = 0,
	}
end

--------------------------------------------------------------------------------
-- Reading the authoritative config, defensively.
--
-- Everything below treats the payload as untrusted SHAPE (not untrusted TRUTH
-- -- the server sent it). A malformed or absent field degrades to a sensible
-- default rather than erroring, because an error here would leave a die frozen
-- mid-air after its payout had already been paid.
--------------------------------------------------------------------------------

local function readShape(die: any): string
	if type(die) == "table" then
		local s = die.Shape
		if type(s) == "string" and NORMALS[s] ~= nil then
			return s
		end
		s = die.shape
		if type(s) == "string" and NORMALS[s] ~= nil then
			return s
		end
	end
	return DEFAULT_SHAPE
end

local function readFaces(die: any): { any }
	if type(die) == "table" then
		local f = die.Faces
		if type(f) == "table" then
			return f
		end
		f = die.faces
		if type(f) == "table" then
			return f
		end
	end
	return {}
end

local function readMass(face: any): number
	if type(face) == "table" then
		local m = face.Mass
		if type(m) == "number" and m == m and m > 0 and m < math.huge then
			return m
		end
		m = face.mass
		if type(m) == "number" and m == m and m > 0 and m < math.huge then
			return m
		end
	end
	return 0
end

local function readElement(face: any): string
	if type(face) == "table" then
		local e = face.Element
		if type(e) == "string" then
			return e
		end
		e = face.element
		if type(e) == "string" then
			return e
		end
	end
	return "None"
end

--------------------------------------------------------------------------------
-- Applying a shape and a mass distribution to a pooled die.
--
-- Runs at most once per die per roll, OUTSIDE the frame loop, and creates
-- nothing: it moves, resizes and recolours plates that already exist.
--
-- The die is laid out in its own canonical frame -- core at the identity -- so
-- that `Model:PivotTo` alone can drive it afterwards. Laying out in world space
-- would make every plate offset depend on where the die happened to be sitting.
--------------------------------------------------------------------------------

local function applyConfig(visual: DieVisual, shapeId: string, faces: { any }): ()
	local normals = NORMALS[shapeId] or NORMALS[DEFAULT_SHAPE]
	local faceCount = #normals
	local base = PLATE_BASE[shapeId] or PLATE_BASE[DEFAULT_SHAPE] or 0.5

	visual.core.CFrame = CFrame.identity
	visual.core.Size = Vector3.one * (DIE_SIZE * CORE_SCALE)
	visual.core.Shape = if BLOCK_CORE[shapeId] then Enum.PartType.Block else Enum.PartType.Ball
	visual.shape = shapeId
	visual.faceCount = faceCount

	-- Normalise mass across the die's own faces. Relative, not absolute: FR-1.3
	-- asks a player to read THIS die's build, and a die with a 60 budget and one
	-- with a 200 budget should both show their own heaviest face as heaviest.
	local heaviest = 0.0
	for f = 1, faceCount do
		local m = readMass(faces[f])
		if m > heaviest then
			heaviest = m
		end
	end

	for f = 1, MAX_FACES do
		local plate = visual.plates[f]
		if f > faceCount then
			-- Parked, not destroyed. A shape change must never allocate.
			-- Parked INSIDE the core rather than off in the distance: a hidden
			-- part a thousand studs away is still a part being dragged around
			-- by every PivotTo, and it inflates the model's extents.
			plate.part.Transparency = 1
			plate.gui.Enabled = false
			plate.part.Size = Vector3.one * 0.05
			plate.part.CFrame = CFrame.identity
			continue
		end

		local mass = readMass(faces[f])
		local weight = if heaviest > 0 then math.clamp(mass / heaviest, 0, 1) else 0

		-- channel 1: scale
		local scale = PLATE_SCALE_MIN + (PLATE_SCALE_MAX - PLATE_SCALE_MIN) * weight
		local extent = DIE_SIZE * base * scale
		plate.part.Size = Vector3.new(extent, extent, PLATE_THICK)

		-- channel 2: inset depth -- heavy faces protrude, light faces sink in
		local inset = INSET_MIN + (INSET_MAX - INSET_MIN) * weight
		local normal = normals[f]
		local standoff = (DIE_SIZE * CORE_SCALE * 0.5) + (PLATE_THICK * 0.5) + inset
		local position = normal * standoff

		-- CFrame.lookAt's default up vector is degenerate for a face pointing
		-- straight up or straight down; swap axes rather than let it collapse.
		local upHint = if math.abs(normal.Y) > 0.985 then Vector3.xAxis else Vector3.yAxis
		plate.part.CFrame = CFrame.lookAt(position, position + normal, upHint)

		-- channel 3: glow, plus the element tint when the face carries one
		local element = readElement(faces[f])
		local colour: Color3
		if element ~= "None" and element ~= "" then
			colour = UITheme.elementColor(element)
		else
			colour = UITheme.Colors.VoidFace:Lerp(UITheme.Colors.TextGold, weight)
		end
		plate.part.Color = colour
		plate.part.Material = if weight >= GLOW_THRESHOLD then Enum.Material.Neon else Enum.Material.SmoothPlastic
		plate.part.Transparency = 0
		plate.gui.Enabled = true

		plate.label.Text = tostring(f)
		plate.label.TextColor3 = if weight >= GLOW_THRESHOLD
			then UITheme.Colors.PanelDeep
			else UITheme.Colors.TextPrimary
	end
end

--------------------------------------------------------------------------------
-- The resolution rotation. THIS is the line that makes the server's answer the
-- animation's answer, and it is the only place the target face is consumed.
--------------------------------------------------------------------------------

-- Returns the rotation R with R * normal == world up. Post-multiplying a
-- trajectory keyframe by R therefore guarantees the target face is up at the
-- instant the trajectory reaches identity.
local function rotationBringingUp(normal: Vector3): CFrame
	local dot = math.clamp(normal:Dot(Vector3.yAxis), -1, 1)
	if dot > 0.9999 then
		return CFrame.identity
	end
	if dot < -0.9999 then
		-- antiparallel: the cross product is zero and gives no axis, so pick one
		return CFrame.fromAxisAngle(Vector3.xAxis, math.pi)
	end
	return CFrame.fromAxisAngle(normal:Cross(Vector3.yAxis).Unit, math.acos(dot))
end

-- Tumble duration scales with payout so a large win feels large (HLD §4.3).
-- Non-finite or non-positive payouts fall to the floor duration rather than
-- producing a NaN duration that would divide by zero in the frame loop.
local function durationFor(payout: number): number
	if type(payout) ~= "number" or payout ~= payout or payout <= 0 or payout >= math.huge then
		return MIN_DURATION
	end
	-- log10 keeps the whole 1..1e12+ range legible in one curve; six decades
	-- spans the full extra second and a half.
	local decades = math.log10(payout + 1)
	local t = math.clamp(decades / 6, 0, 1)
	return MIN_DURATION + (MAX_DURATION - MIN_DURATION) * t
end

--------------------------------------------------------------------------------
-- The frame loop. One connection for the entire renderer.
--
-- No Lua table, closure or Instance is allocated here (NFR-1). The loop is a
-- numeric `for` over a fixed-size array whose entries are mutated in place.
--------------------------------------------------------------------------------

local function step(deltaTime: number): ()
	for i = 1, MAX_DICE do
		local slot = slots[i]
		if not slot.inUse or not slot.animating then
			continue
		end

		slot.elapsed += deltaTime
		local a = slot.elapsed / slot.duration
		if a >= 1 then
			a = 1
			slot.animating = false
		end

		-- Position: ease-out toward the anchor, with a decaying hop so the die
		-- reads as landing rather than as descending on a string.
		local eased = 1 - (1 - a) * (1 - a) * (1 - a)
		local hop = HOP_HEIGHT * math.abs(math.sin(a * math.pi * BOUNCES)) * (1 - a)
		local position = slot.startPos:Lerp(slot.endPos, eased)

		-- Orientation: R * keyframe(t). At a == 1 the keyframe is exactly the
		-- identity, so the die finishes at exactly R -- the server's face, up.
		local frames = TRAJECTORIES[slot.trajectory]
		local segment = eased * (KEYFRAMES - 1)
		local lower = math.floor(segment)
		if lower > KEYFRAMES - 2 then
			lower = KEYFRAMES - 2
		end
		local blend = segment - lower
		local rotation = frames[lower + 1]:Lerp(frames[lower + 2], blend)

		slot.visual.model:PivotTo(
			CFrame.new(position.X, position.Y + hop, position.Z) * slot.finalRot * rotation
		)
	end
end

--------------------------------------------------------------------------------
-- Roll handling
--------------------------------------------------------------------------------

local function beginRoll(faces: { any }, payout: number): ()
	local count = math.clamp(#faces, 0, MAX_DICE)
	if count == 0 then
		return
	end

	local duration = durationFor(payout)

	for i = 1, MAX_DICE do
		local slot = slots[i]
		if i > count then
			if slot.inUse then
				slot.inUse = false
				slot.animating = false
				slot.visual.model.Parent = nil
			end
			continue
		end

		local config = diceConfig[i]
		local shapeId = readShape(config)
		local normals = NORMALS[shapeId] or NORMALS[DEFAULT_SHAPE]

		applyConfig(slot.visual, shapeId, readFaces(config))

		-- The server's chosen face. Out-of-range is clamped, never rejected:
		-- the payout is already credited and refusing to animate would only
		-- hide a result the player has been paid for.
		local target = faces[i]
		local faceIndex = if type(target) == "number" then math.floor(target) else 1
		faceIndex = math.clamp(faceIndex, 1, #normals)

		slot.finalRot = rotationBringingUp(normals[faceIndex])
		slot.trajectory = rng:NextInteger(1, #TRAJECTORIES)

		-- FR-1.4: the resting place comes from ArenaView, which is the only
		-- thing that knows where "inside" is, and is clamped by the die's own
		-- half-extent before it is ever used.
		slot.endPos = ArenaView.getAnchor(i, count, DIE_RADIUS).Position
		slot.startPos = ArenaView.getSpawnPoint(i, count)

		slot.elapsed = 0
		slot.duration = duration
		slot.animating = true

		if not slot.inUse then
			slot.inUse = true
			slot.visual.model.Parent = ArenaView.getContainer()
		end

		-- Place it at the start immediately, so a die that appears this frame
		-- appears in the pit rather than at the world origin for one frame.
		slot.visual.model:PivotTo(CFrame.new(slot.startPos) * slot.finalRot * TRAJECTORIES[slot.trajectory][1])
	end
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function DiceRenderer.init(net: any): ()
	if started then
		return
	end
	started = true

	if not ArenaView.isReady() then
		-- ClientBootstrap constructs in dependency order, so this cannot happen
		-- from the normal path. Failing loudly beats rendering into nothing.
		error("[DiceRenderer] ArenaView must be initialised first", 0)
	end

	for i = 1, MAX_DICE do
		slots[i] = {
			visual = makeVisual(i),
			inUse = false,
			animating = false,
			elapsed = 0,
			duration = MIN_DURATION,
			startPos = Vector3.zero,
			endPos = Vector3.zero,
			trajectory = 1,
			finalRot = CFrame.identity,
		}
	end

	-- Show the player's dice at rest before they have rolled anything, so the
	-- arena is never empty and FR-1.3 is readable the moment they arrive.
	net.onStateSync(function(state: any)
		if type(state) ~= "table" then
			return
		end
		local incoming = state.dice
		if type(incoming) ~= "table" then
			incoming = state.Dice
		end
		if type(incoming) ~= "table" then
			return
		end
		diceConfig = incoming :: { any }

		local count = math.clamp(#diceConfig, 0, MAX_DICE)
		for i = 1, MAX_DICE do
			local slot = slots[i]
			if i > count then
				if slot.inUse then
					slot.inUse = false
					slot.animating = false
					slot.visual.model.Parent = nil
				end
				continue
			end
			if slot.animating then
				-- A config change mid-tumble re-skins the die on the next roll
				-- rather than snapping it while it is in the air.
				continue
			end
			applyConfig(slot.visual, readShape(diceConfig[i]), readFaces(diceConfig[i]))
			slot.endPos = ArenaView.getAnchor(i, count, DIE_RADIUS).Position
			slot.visual.model:PivotTo(CFrame.new(slot.endPos) * slot.finalRot)
			if not slot.inUse then
				slot.inUse = true
				slot.visual.model.Parent = ArenaView.getContainer()
			end
		end
	end)

	-- The server has already credited before this fires (FR-2.6). Everything
	-- below is presentation.
	net.onRollResult(function(result: any)
		if type(result) ~= "table" then
			return
		end
		local faces = result.faces
		if type(faces) ~= "table" then
			return
		end
		local payout = result.payout
		beginRoll(faces :: { any }, if type(payout) == "number" then payout else 0)
	end)

	RunService.RenderStepped:Connect(step)
end

return DiceRenderer
