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
--   1. Compute the single rotation `R` that carries the target face's normal to
--      world up. `R` alone IS the answer; everything else is the journey to it.
--   2. Pick a spin axis and a total spin angle `T` of several full turns plus a
--      deliberate part-turn. The die is placed at `axisAngle(axis, T) * R`,
--      which is `T` of rotation AWAY from the answer.
--   3. Each frame, unwind the residual: `axisAngle(axis, T - spun(t)) * R`,
--      where `spun` rises monotonically from 0 to `T`. The residual therefore
--      falls monotonically to zero and the die converges onto `R` from one
--      consistent direction -- it never reverses, and it never passes through
--      the answer early, because a residual of zero happens exactly once.
--   4. At t = 1 the terminal orientation is ASSIGNED as `R`, not approached.
--      The spin chooses the CHARACTER of the tumble; it can never choose the
--      ANSWER.
--   5. Duration scales with payout, and so does the number of turns, so a large
--      win is a longer AND fuller tumble rather than a longer wait.
--
-- WHY NOT KEYFRAMES AND `CFrame:Lerp`: a slerp between two absolute
-- orientations always takes the SHORTEST arc, so it cannot represent a winding
-- number. Any multi-turn keyframe collapses mod 2*pi, and a sequence of them
-- rewinds, stalls, and passes through the final face mid-flight. Rotation here
-- is therefore accumulated as a scalar ANGLE and only ever converted to a
-- CFrame at the last moment.
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
-- True half-extent per shape (FR-1.4 containment, and floor clearance).
--
-- Half of DIE_SIZE is NOT the die's half-extent. A maximum-mass face pushes its
-- plate out to `core half + plate half-thickness + INSET_MAX`, and the plate's
-- own CORNERS reach further still. Because the resting orientation is whatever
-- the server's face demands, any facet can end up pointing down or at a wall,
-- so the only sound bound is the radius of the sphere that encloses the fully
-- built die -- computed here from the same constants the builder uses, so the
-- two cannot drift apart.
--
-- The bound is deliberately the WORST case (max-mass plates, corner-on). It
-- can leave a light die a fraction of a stud clear of the floor; that is the
-- correct side to err on, because the other side is a plate through the floor.
--------------------------------------------------------------------------------

local MAX_STANDOFF = (DIE_SIZE * CORE_SCALE * 0.5) + (PLATE_THICK * 0.5) + INSET_MAX

local function extentFor(shapeId: string): number
	local base = PLATE_BASE[shapeId] or PLATE_BASE[DEFAULT_SHAPE] or 0.5
	-- the plate's outer face, along the normal
	local outer = MAX_STANDOFF + (PLATE_THICK * 0.5)
	-- half of the plate's square face, in the two in-plane directions
	local half = DIE_SIZE * base * PLATE_SCALE_MAX * 0.5
	local plateReach = math.sqrt((outer * outer) + (2 * half * half))
	-- a block core reaches its own corners; a ball core reaches only its radius
	local coreHalf = DIE_SIZE * CORE_SCALE * 0.5
	local coreReach = if BLOCK_CORE[shapeId] then coreHalf * math.sqrt(3) else coreHalf
	return math.max(plateReach, coreReach)
end

local DIE_EXTENT: { [string]: number } = {
	D4 = extentFor("D4"),
	D6 = extentFor("D6"),
	D8 = extentFor("D8"),
	D12 = extentFor("D12"),
	D20 = extentFor("D20"),
}

--------------------------------------------------------------------------------
-- Tumble spin (HLD §4.3).
--
-- A tumble is one axis and one total angle, both chosen per die per roll. The
-- axes are pre-authored so the motion has a designed character rather than a
-- random wobble; the angle is randomised so two dice in the same throw do not
-- move in lockstep.
--
-- THE FRACTIONAL TURN IS LOAD-BEARING and is not decoration: the total angle is
-- always a whole number of turns PLUS a fraction in [0.25, 0.75]. An exact
-- multiple of 2*pi would make the opening orientation the identity, which is to
-- say the answer -- the die would spawn already showing the face it is
-- supposedly about to roll. Bounding the fraction into [0.25, 0.75] makes the
-- opening rotation 90 to 270 degrees about the spin axis, so the die's opening
-- orientation is at least 90 degrees of arc from its answer -- on every axis,
-- on every roll, with no reliance on the randomiser being kind.
--------------------------------------------------------------------------------

local SPIN_AXES: { Vector3 } = {
	Vector3.new(1, 0.35, 0.15).Unit,
	Vector3.new(0.2, 1, 0.4).Unit,
	Vector3.new(0.6, -0.3, 1).Unit,
	Vector3.new(-0.8, 0.5, 0.6).Unit,
	Vector3.new(0.1, -1, 0.25).Unit,
}

local SPIN_TURNS_MIN = 3           -- whole turns, before the payout bonus
local SPIN_TURNS_MAX = 5
local SPIN_TURNS_PAYOUT_BONUS = 2  -- extra whole turns at the longest duration
local SPIN_FRACTION_MIN = 0.25
local SPIN_FRACTION_MAX = 0.75
local TAU = math.pi * 2

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
	-- false while the authoritative shape for this slot is still unknown. An
	-- unnumbered die is honest; a numbered one would be asserting a face.
	numbered: boolean,
	extent: number,
}

type DieSlot = {
	visual: DieVisual,
	inUse: boolean,
	animating: boolean,
	elapsed: number,
	duration: number,
	startPos: Vector3,
	endPos: Vector3,
	spinAxis: Vector3,
	spinTotal: number,
	finalRot: CFrame,
}

-- Only the two subscriptions this module actually uses. Narrow on purpose: a
-- renderer that cannot NAME `roll` cannot call it.
type Net = {
	onStateSync: ((any) -> ()) -> RBXScriptConnection,
	onRollResult: ((any) -> ()) -> RBXScriptConnection,
}

--------------------------------------------------------------------------------
-- State. Fixed size, allocated once.
--------------------------------------------------------------------------------

local slots: { DieSlot } = {}
local started = false
local rng = Random.new()

-- Every connection this module owns, so `shutdown` can give them all back.
local connections: { RBXScriptConnection } = {}
local frameConnection: RBXScriptConnection? = nil

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
		numbered = false,
		extent = DIE_EXTENT[DEFAULT_SHAPE] or (DIE_SIZE * 0.5),
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

-- Returns nil -- NOT a default -- when the slot's shape is unknown.
--
-- The distinction matters because face indices are only meaningful relative to
-- a shape. A RollResult can arrive before the first StateSync, and defaulting
-- to D6 there would take a credited face of, say, 17 and draw it as a "6": a
-- visible lie about a payout that was actually correct. Callers that cannot
-- name the shape must therefore decline to name the face.
local function readShape(die: any): string?
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
	return nil
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

-- `shapeId` is nil when the authoritative shape has not arrived yet. The die is
-- still built -- an empty pit reads as a broken game -- but it is built
-- UNNUMBERED, because a numeral is a claim about which face is which and this
-- module has nothing to base that claim on yet.
local function applyConfig(visual: DieVisual, shapeId: string?, faces: { any }): ()
	local numbered = shapeId ~= nil
	local resolved = shapeId or DEFAULT_SHAPE
	local normals = NORMALS[resolved] or NORMALS[DEFAULT_SHAPE]
	local faceCount = #normals
	local base = PLATE_BASE[resolved] or PLATE_BASE[DEFAULT_SHAPE] or 0.5

	visual.core.CFrame = CFrame.identity
	visual.core.Size = Vector3.one * (DIE_SIZE * CORE_SCALE)
	visual.core.Shape = if BLOCK_CORE[resolved] then Enum.PartType.Block else Enum.PartType.Ball
	visual.shape = resolved
	visual.faceCount = faceCount
	visual.numbered = numbered
	visual.extent = DIE_EXTENT[resolved] or DIE_EXTENT[DEFAULT_SHAPE] or (DIE_SIZE * 0.5)

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
		plate.gui.Enabled = numbered

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

-- Returns the rotation R with R * normal == world up. Left-multiplying R by the
-- residual spin therefore guarantees the target face is up at the instant that
-- residual reaches zero -- and only then.
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
--
-- ACCEPTED, NOT OVERLOOKED: CFrame and Vector3 are Roblox userdata values, so
-- composing the pivot does produce short-lived temporaries each frame per
-- animating die. That is at most seven dice for at most 2.4 seconds, it is
-- generational-GC cheap, and every alternative (caching CFrames, mutating in
-- place) is impossible for immutable userdata or costs more than it saves. The
-- NFR-1 prohibition this file honours is on Lua TABLES, CLOSURES and
-- INSTANCES, none of which are created below.
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

		local inverse = 1 - a

		-- Position: cubic ease-out toward the anchor, with a decaying hop so the
		-- die reads as landing rather than as descending on a string.
		local eased = 1 - inverse * inverse * inverse
		local hop = HOP_HEIGHT * math.abs(math.sin(a * math.pi * BOUNCES)) * inverse
		local position = slot.startPos:Lerp(slot.endPos, eased)

		-- Orientation: the residual spin still owed, unwound onto the answer.
		--
		-- `spun = total * (1 - (1 - a)^2)` is a QUADRATIC ease-out, which is
		-- exactly constant angular deceleration -- a die losing speed to
		-- friction. Its residual is the algebraically identical
		-- `total * (1 - a)^2` written below, one multiply cheaper.
		--
		-- This is deliberately NOT the positional `eased` above. Sharing the
		-- cubic would have three quarters of the spin done by a = 0.37 and
		-- leave the back half of every tumble visually frozen; the quadratic
		-- still owes a quarter of its turns at the halfway mark.
		--
		-- Monotonicity: `inverse^2` is strictly decreasing on [0, 1] and
		-- `spinTotal` is positive, so the residual angle only ever shrinks. The
		-- axis is fixed for the whole tumble, so the die turns one way and
		-- never rewinds, and it reaches residual zero exactly once -- at the
		-- end. No CFrame is interpolated, so no shortest-arc slerp can eat the
		-- winding number.
		local rotation: CFrame
		if a >= 1 then
			-- Exact terminal assignment. Not "close to R" -- R.
			rotation = slot.finalRot
		else
			local residual = slot.spinTotal * inverse * inverse
			rotation = CFrame.fromAxisAngle(slot.spinAxis, residual) * slot.finalRot
		end

		slot.visual.model:PivotTo(
			CFrame.new(position.X, position.Y + hop, position.Z) * rotation
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

	-- A longer tumble buys MORE TURNS, not more waiting. Whole turns only, so
	-- the fractional part of the total is still the guaranteed [0.25, 0.75]
	-- that keeps the opening orientation off the answer.
	local span = MAX_DURATION - MIN_DURATION
	local reach = if span > 0 then math.clamp((duration - MIN_DURATION) / span, 0, 1) else 0
	local bonusTurns = math.floor((SPIN_TURNS_PAYOUT_BONUS * reach) + 0.5)

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
		local normals = NORMALS[shapeId or DEFAULT_SHAPE] or NORMALS[DEFAULT_SHAPE]

		applyConfig(slot.visual, shapeId, readFaces(config))

		-- The server's chosen face. A malformed index is substituted, never
		-- rejected: the payout is already credited and refusing to animate
		-- would only hide a result the player has been paid for.
		local target = faces[i]
		local faceIndex = 1
		if type(target) == "number" and target == target and target >= 1 and target < math.huge then
			faceIndex = math.floor(target)
		end

		if shapeId == nil then
			-- Shape unknown, so this die is drawn unnumbered (see applyConfig)
			-- and no numeral will contradict the credited face. The tumble
			-- still has to end on SOME facet; wrap into the placeholder solid
			-- rather than clamp, so a high index does not always pile onto the
			-- same face. Nothing here is displayed as a face number.
			faceIndex = ((faceIndex - 1) % #normals) + 1
		else
			faceIndex = math.clamp(faceIndex, 1, #normals)
		end

		slot.finalRot = rotationBringingUp(normals[faceIndex])
		slot.spinAxis = SPIN_AXES[rng:NextInteger(1, #SPIN_AXES)]
		slot.spinTotal = (
			rng:NextInteger(SPIN_TURNS_MIN, SPIN_TURNS_MAX)
			+ bonusTurns
			+ rng:NextNumber(SPIN_FRACTION_MIN, SPIN_FRACTION_MAX)
		) * TAU

		-- FR-1.4: the resting place comes from ArenaView, which is the only
		-- thing that knows where "inside" is, and is clamped by the die's own
		-- true half-extent -- plates and corners included -- before it is ever
		-- used.
		slot.endPos = ArenaView.getAnchor(i, count, slot.visual.extent).Position
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
		-- This is the a == 0 orientation, residual == spinTotal: a full
		-- multi-turn rotation AWAY from the answer, never the answer itself.
		slot.visual.model:PivotTo(
			CFrame.new(slot.startPos)
			* CFrame.fromAxisAngle(slot.spinAxis, slot.spinTotal)
			* slot.finalRot
		)
	end
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function DiceRenderer.init(net: Net): ()
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
			spinAxis = SPIN_AXES[1],
			spinTotal = 0,
			finalRot = CFrame.identity,
		}
	end

	-- Show the player's dice at rest before they have rolled anything, so the
	-- arena is never empty and FR-1.3 is readable the moment they arrive.
	table.insert(connections, net.onStateSync(function(state: any)
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
			slot.endPos = ArenaView.getAnchor(i, count, slot.visual.extent).Position
			slot.visual.model:PivotTo(CFrame.new(slot.endPos) * slot.finalRot)
			if not slot.inUse then
				slot.inUse = true
				slot.visual.model.Parent = ArenaView.getContainer()
			end
		end
	end))

	-- The server has already credited before this fires (FR-2.6). Everything
	-- below is presentation.
	table.insert(connections, net.onRollResult(function(result: any)
		if type(result) ~= "table" then
			return
		end
		local faces = result.faces
		if type(faces) ~= "table" then
			return
		end
		local payout = result.payout
		beginRoll(faces :: { any }, if type(payout) == "number" then payout else 0)
	end))

	frameConnection = RunService.RenderStepped:Connect(step)
end

-- Give back everything `init` took: both wire subscriptions, the render step,
-- and the pooled Instances. Symmetric with `HUD.shutdown`.
--
-- Tearing down mid-tumble is safe by construction and always was: the payout
-- was credited before this module heard about the roll (FR-2.6), so an
-- animation that never finishes costs a visual and nothing else.
function DiceRenderer.shutdown(): ()
	if not started then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}

	local frame = frameConnection
	if frame ~= nil then
		frame:Disconnect()
	end
	frameConnection = nil

	-- Destroyed rather than merely unparented: `init` builds a fresh pool, so
	-- keeping the old one would leak seven models on every restart.
	-- Indexed defensively: `init` errors if ArenaView is not ready, which can
	-- leave the pool half built with `started` already latched.
	for i = 1, MAX_DICE do
		local slot: DieSlot? = slots[i]
		if slot ~= nil then
			slot.visual.model:Destroy()
		end
	end
	slots = {}
	diceConfig = {}

	started = false
end

return DiceRenderer
