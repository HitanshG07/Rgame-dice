--!strict
-- DiceRenderer.luau
-- Throws the player's dice into the board's shared 3D scene and lands them on
-- the face the server chose (SRS FR-1.2, FR-1.3, FR-2.6; HLD §4.3).
--
-- THIS MODULE SHOWS RESULTS. IT NEVER PRODUCES THEM. The server samples the
-- outcome from the die's mass distribution and credits the payout BEFORE this
-- module hears about it (FR-2.6). Everything here is presentation: the face is
-- already decided and already paid for, so the animation's only job is to arrive
-- at the answer convincingly. Nothing in this file may read as deciding
-- anything, and nothing in it is allowed to fail a roll -- a malformed face
-- index is substituted, never rejected, because refusing to animate would hide
-- a result the player has already been paid.
--
--------------------------------------------------------------------------------
-- THE REBUILD, AND WHAT IT REPLACED
--------------------------------------------------------------------------------
--
-- Every die used to live in its OWN ViewportFrame, with its own camera, pinned
-- to a slot looked up from a table indexed by (index, count). The operator's
-- complaint was that it "feels like its in a restricted box like area", and that
-- was not a matter of polish -- each die genuinely was in a box, and three
-- things followed that no amount of tuning could reach:
--
--   * THE SAME BOARD LANDED THE SAME WAY EVERY THROW. Positions came from
--     `LAYOUTS[count][index]`. Late jitter was bolted on top, but the underlying
--     arrangement was still a grid with noise added.
--   * DICE COULD NOT INTERMINGLE. Separate viewports are separate 3D scenes. Two
--     dice could not be near each other, because they were never in the same
--     space at all.
--   * THERE WAS NO FLOOR. Bounces were faked by moving each die's CAMERA up and
--     down within its own frame -- so the "bounce" was the viewer bobbing, not
--     the die falling, and every die bounced against its own private plane.
--
-- Now there is ONE scene, owned by BoardView, with a real felt plane and one
-- camera. Dice are models at real stud coordinates in that scene. The result:
--
--   * A GENUINE BALLISTIC ARC. `solveThrow` computes the launch velocity that
--     carries a die from its release point to its landing point under constant
--     gravity, and the die follows `p = p0 + v*t + 0.5*g*t^2`. The parabola is
--     not drawn; it is integrated.
--   * TWO DAMPED BOUNCES against the shared floor, each with its own arc solved
--     from a restitution coefficient, so the second is visibly smaller than the
--     first and both are smaller than the throw.
--   * ORGANIC SCATTER. Landing points are sampled per throw with a minimum
--     separation, so dice cluster and intermingle differently every time.
--   * NO DIE-COUNT CEILING. Visuals are pooled on demand rather than allocated
--     as a fixed array of seven. The operator's 20-dice progression ceiling
--     needs no change here.
--
-- WHAT SURVIVED, because it was right. Mass is the heart of the game (FR-2) and
-- must stay legible:
--
--   1. THE DIE STILL TUMBLES end over end for the whole flight, so a roll is an
--      EVENT with a duration rather than a state change. The spin budget and its
--      payout bonus carry over unchanged -- a big win still buys a longer,
--      fuller tumble.
--   2. EVERY DIE CARRIES A WEIGHT BAR on the board (FR-1.3), so a heavy face is
--      legible at a glance without opening the forge. It is a billboarded 2D
--      overlay tracking the die's projected position, because a bar drawn INTO
--      the scene would tumble with the die and become unreadable.
--   3. THE SETTLE DRAGS AWAY FROM THE HEAVY FACE. As the tumble decays the die
--      leans off its heavy side, so it visibly FIGHTS to avoid resting there.
--      Cosmetic -- it cannot and does not alter the outcome, which arrived from
--      the server already decided -- but it makes the mechanic's DIRECTION
--      observable.
--
-- WHY AN UNKNOWN SHAPE DRAWS NOTHING. Until StateSync says what a die is,
-- rendering some default solid would be asserting a shape this module has not
-- been told, and its numerals would contradict the credited result. An absent
-- die is honest; a guessed one is a lie that looks like a feature.
--
-- EVERY COLOUR COMES FROM UITheme, for the reason UITheme's own header gives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local BoardView = require(script.Parent:WaitForChild("BoardView"))
local DiceCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DiceCatalog"))

local DiceRenderer = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_SHAPE = "D6"

-- Face counts by shape id. An id absent from this table is an UNKNOWN shape and
-- draws no die rather than a guessed one.
--
-- DERIVED FROM THE CATALOG, never hand-listed.
--
-- THE DEFECT THIS FIXES, and it is L-041 repeating in a second file. This was a
-- hand-written mirror of eight shapes. The catalog then grew to twelve -- D5, D7,
-- D14 and D16 were added with the geometry rebuild -- and this table was never
-- updated. `readShape` returns nil for any id absent here, and a nil shape draws
-- NO MODEL by design, so a player whose die was one of those four saw an EMPTY
-- BOARD. Found exactly that way: the die count was set to 1, the server granted
-- it correctly, no error was logged anywhere, and the scene contained only the
-- felt.
--
-- The mesh builder already fixed this same class of bug by deriving its shape
-- list from `DiceCatalog.getAllShapes()`; the renderer kept its own copy and
-- drifted the moment the catalog moved. Requiring the catalog here costs one
-- import and makes the drift impossible -- which is worth more than the
-- "server-shaped dependency" the old comment was avoiding, since a face COUNT is
-- not a server rule.
local FACE_COUNTS: { [string]: number } = {}
for _, def in ipairs(DiceCatalog.getAllShapes()) do
	FACE_COUNTS[def.id] = DiceCatalog.getFaceCount(def.id)
end

-- Where the generated solids live. The renderer never builds geometry.
local DICE_SOURCE = "dice_faces"

-- Somewhere no camera looks. Used to hold a die while it is being cloned or
-- measured, so it is never visible in a pose that belongs to no part of the
-- animation -- see `measureSitHeight` and the clone in `applyModel` for the two
-- places that produced exactly that artifact.
local MEASURE_PARK_Y = -1000

--------------------------------------------------------------------------------
-- Flight timing.
--
-- Split into the throw and its two bounces rather than given as one duration,
-- because each phase is a separate ballistic solve and their lengths are what
-- make the motion read as physical. A single blended curve was what the old
-- renderer did and it read as an object being moved rather than falling.
--------------------------------------------------------------------------------

-- Gravity, in studs per second squared. NOT Roblox's 196.2: the felt is roughly
-- 26 studs across and a die is a couple of studs, so real-world gravity at that
-- scale drops a die the height of the throw in under a fifth of a second and the
-- whole roll is over before the eye registers it. This is tuned so the arc reads
-- at the scale the scene is actually built at -- which is the same reason film
-- miniatures are shot at high frame rates.
local GRAVITY = 95.0

-- The throw's airtime, before the first bounce. A bigger payout buys a longer
-- one, within this band.
--
-- SHORT, AND THAT IS A FRAMING CONSTRAINT RATHER THAN A TASTE. `solveThrow`
-- gives the die whatever launch velocity the requested airtime demands, and for
-- any airtime longer than a free fall that velocity points UPWARD -- the longer
-- the throw, the higher the arc. At 0.62-0.95s the apex reached about 12 studs,
-- which projects clean off the top of the frame: measured mid-roll, the felt was
-- EMPTY because every die was above the shot. The visible band above the felt is
-- only about five studs at the far edge, so the arc has to fit inside it.
--
-- Duration comes from the bounces instead, which is where it belongs.
local THROW_TIME_MIN = 0.40
local THROW_TIME_MAX = 0.50

-- COEFFICIENT OF RESTITUTION. Each bounce returns this fraction of the vertical
-- speed it arrived with, so bounce heights fall off as the square. 0.42 gives a
-- clearly visible first bounce and a small, settling second one -- dice on felt
-- are quite dead, and a bouncier value reads as a rubber ball.
local RESTITUTION = 0.55

-- How much horizontal speed survives each floor contact. Below 1.0 so a die
-- slows as it skips, which is what makes the final rest look like the end of a
-- motion rather than a stop.
--
-- 0.45 RATHER THAN 0.62, and the reason is geometric as much as physical. The
-- further a die travels after its first contact, the further BACK that contact
-- has to be for the bounces to still deliver it to its rest point -- and for a
-- die resting near the far edge, "further back" runs off the felt, where the
-- clamp takes over and the exactness is lost. Measured at 0.62 the residual the
-- settle had to absorb reached 1.4 studs; at 0.45 it stays under one, which is
-- inside a die's own radius and reads as rocking into place rather than sliding.
-- Felt is also genuinely a high-friction surface, so this is the more physical
-- value in the first place.
local FRICTION = 0.45

-- Bounces before the die is at rest. The operator asked for two.
local BOUNCE_COUNT = 2

-- After the last bounce, the die eases from wherever it touched down to its
-- exact sampled rest point, unwinding the last of its spin onto the chosen
-- face. This is the only non-ballistic segment, and it is deliberately short:
-- long enough to look like a die rocking to a halt, short enough that nobody
-- sees it slide.
local SETTLE_TIME = 0.34

-- Spin budget, in whole turns plus a fraction, spent across the whole flight.
-- Carried over from the previous renderer, whose timing was tuned against real
-- rolls.
local SPIN_TURNS_MIN = 3
local SPIN_TURNS_MAX = 5
local SPIN_TURNS_PAYOUT_BONUS = 2
local SPIN_FRACTION_MIN = 0.25
local SPIN_FRACTION_MAX = 0.75
local TAU = math.pi * 2

-- How far the die leans off its heavy side during the settle, in radians. Small
-- on purpose: this is a lean, not a wobble, and anything larger reads as the
-- animation glitching rather than as weight.
local HEAVY_LEAN = 0.14

-- THE RESTING TILT. A die parked square to the camera shows one face filling the
-- frame and reads as a flat coloured square. Resting it a few degrees off both
-- axes shows three faces at once, so the solid is legible as a solid even when
-- nothing is moving.
--
-- Applied ON TOP of the face-showing rotation, so the face the server chose
-- still points essentially at the viewer and `rotationShowingFace` stays true.
local REST_TILT = CFrame.Angles(math.rad(-9), math.rad(16), math.rad(6))

-- Mass at or above this fraction of an even share makes a face read as HEAVY:
-- its weight bar goes full-width and gold.
local GLOW_THRESHOLD = 0.55

-- The weight bar overlay, in screen scale relative to the tray interior.
local BAR_W = 0.052
local BAR_H = 0.0095

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

-- One ballistic segment: a launch point, a launch velocity, and how long the
-- die is in the air before it next touches the floor.
type Arc = {
	origin: Vector3,
	velocity: Vector3,
	duration: number,
}

type DieVisual = {
	-- The 3D solid. nil until a known shape arrives, because a die whose shape is
	-- unknown must not be drawn as some other shape.
	model: Model?,
	modelShape: string?,
	-- The solid's own bounding-sphere radius as generated, before scaling. Used
	-- to scale it to the board's chosen radius for the current die count.
	sourceRadius: number,
	-- The weight bar, a 2D overlay tracking the die's projected position.
	bar: Frame,
	barFill: Frame,
	-- Whether this die HAS a bar worth showing (its masses are readable), kept
	-- separate from the Frame's own `Visible`. The frame step also hides a bar
	-- whose die has gone behind the camera, and without a separate record of the
	-- intent there is nothing to restore it FROM -- a bar hidden once for a
	-- transient reason stays hidden for the rest of the session.
	barShown: boolean,
	shape: string,
	faceCount: number,
	-- false while the authoritative shape for this slot is still unknown.
	numbered: boolean,
	-- Normalised mass per face, as a fraction of this die's total. Display only.
	weights: { number },
	-- Board radius in studs at the current die count.
	radius: number,
	-- How far this die's pivot sits above the felt when it is at rest, measured
	-- from its own geometry in its own resting orientation. NOT derivable from
	-- `radius` -- see `measureSitHeight`.
	sitHeight: number,
}

type DieSlot = {
	visual: DieVisual,
	inUse: boolean,
	animating: boolean,
	elapsed: number,
	-- The flight: the throw arc followed by one arc per bounce.
	arcs: { Arc },
	-- Total airtime across every arc, so the settle knows when it begins.
	flightTime: number,
	restPos: Vector3,
	-- Where the last bounce put the die, which is where the settle eases FROM.
	touchdown: Vector3,
	spinTotal: number,
	spinDir: number,
	heavyLean: number,
	faceIndex: number,
	-- The axis the die tumbles about in flight, and the orientation that shows
	-- the server's face -- the destination the residual spin unwinds onto.
	spinAxis: Vector3,
	finalRot: CFrame,
}

-- Only the two subscriptions this module actually uses. Narrow on purpose: a
-- renderer that cannot NAME `roll` cannot call it.
type Net = {
	onStateSync: ((any) -> ()) -> RBXScriptConnection,
	onRollResult: ((any) -> ()) -> RBXScriptConnection,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Grown on demand rather than preallocated to a fixed seven. The old fixed pool
-- was itself the die-count ceiling: `for i = 1, MAX_DICE` appeared in the frame
-- step, the teardown and the refresh, so raising the cap meant finding every
-- one of them.
local slots: { DieSlot } = {}
local started = false
local rng = Random.new()

local connections: { RBXScriptConnection } = {}
local frameConnection: RBXScriptConnection? = nil

-- The overlay layer the weight bars are drawn on. Owned by this module and
-- parented into the board's interior.
local overlay: Frame? = nil

-- Last authoritative dice configuration seen on StateSync. Display only: it
-- decides how a die LOOKS, never what it rolls.
local diceConfig: { any } = {}

--------------------------------------------------------------------------------
-- Numeric hygiene
--------------------------------------------------------------------------------

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector(v: Vector3): boolean
	return isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)
end

--------------------------------------------------------------------------------
-- The solids, and the rotation that shows a chosen face
--------------------------------------------------------------------------------

-- The source folder. Absent is a legitimate state rather than an error: the
-- models are generated by the server at boot and replicate asynchronously, so a
-- client can be fully initialised before they arrive. A missing solid means a
-- die is not drawn this frame, and must never take the renderer down.
local function findSource(): Folder?
	local found = ReplicatedStorage:FindFirstChild(DICE_SOURCE)
	if found ~= nil and found:IsA("Folder") then
		return found
	end
	return nil
end

-- Called when the solids show up late, so dice that could not be drawn can
-- acquire their models. Assigned by `init`; nil before then.
local onDiceAvailable: (() -> ())? = nil

-- Watches for late replication. Without this, a client whose first StateSync
-- beat the models would keep an empty board until the NEXT state change --
-- which, for a player who is not rolling, may be never.
local function watchForDice(): RBXScriptConnection?
	if findSource() ~= nil then
		return nil
	end
	return ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == DICE_SOURCE and child:IsA("Folder") then
			local notify = onDiceAvailable
			if notify ~= nil then
				notify()
			end
		end
	end)
end

-- The furthest any part of a model reaches from its pivot. Measured rather than
-- assumed: `GetExtentsSize` returns an AXIS-ALIGNED box that includes the flat
-- numeral plates standing proud of each face, and on the D6 it overstates the
-- solid by more than 3x. The honest measure for a tumbling object is the
-- bounding SPHERE, because the die presents every orientation in turn.
local function measureRadius(model: Model): number
	local centre = model:GetPivot().Position
	local radius = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Pivot" then
			local reach = (d.Position - centre).Magnitude + d.Size.Magnitude * 0.5
			if reach > radius then
				radius = reach
			end
		end
	end
	return radius
end

-- HOW FAR A DIE'S PIVOT SITS ABOVE THE FELT WHEN IT IS AT REST.
--
-- WHY THIS IS MEASURED AND NOT DERIVED. The obvious answer -- rest the centre one
-- bounding-sphere radius above the floor -- is only correct for a sphere. The D2
-- is a flat coin: its sphere radius is its full width, but lying flat it stands
-- barely a fraction of that tall. Resting it a radius up left it hovering about
-- three studs above the felt, and because the camera is pitched, a hovering die
-- also projects further from the board's centre -- so a coin comfortably inside
-- the felt was drawn overhanging its edge. Every shape was wrong by a different
-- amount, which is precisely what one radius cannot express.
--
-- So the die is placed at the origin in the orientation it will REST in, and its
-- lowest surface is measured. Shape-agnostic by construction: a coin sits on its
-- half-thickness, a cube on half its edge, an icosahedron on its inradius, and a
-- shape added to the catalog tomorrow sits correctly with no entry anywhere.
--
-- Each part's downward reach is the projection of its half-extents onto world
-- -Y, which is the standard axis-aligned bound of an oriented box -- three
-- multiplies rather than eight corner transforms, because this runs once per die
-- per roll and a D12 carries 132 parts.
local function measureSitHeight(model: Model, rotation: CFrame): number
	-- MEASURED FAR BELOW THE FELT, NOT AT THE ORIGIN.
	--
	-- This posed the model with `PivotTo(rotation)` -- a rotation carrying NO
	-- translation, which puts the die at (0,0,0), the centre of the felt, at full
	-- size. It runs during `beginRoll`, one frame before the flight starts, so the
	-- die was VISIBLE there for that frame. Together with the un-parked clone this
	-- produced the "breaking and deforming" the operator reported: measured, 4
	-- frames per session rendering at the origin and jumps of up to 13.9 studs
	-- between consecutive frames.
	--
	-- Translating the pose off-screen changes nothing about the measurement --
	-- every part moves with the pivot, so the LOWEST point relative to that pivot
	-- is identical -- and it removes the only frame in which the die could be seen
	-- somewhere it does not belong.
	local probe = CFrame.new(0, MEASURE_PARK_Y, 0) * rotation
	model:PivotTo(probe)

	local lowest = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			local half = d.Size * 0.5
			local reach = math.abs(cf.RightVector.Y) * half.X
				+ math.abs(cf.UpVector.Y) * half.Y
				+ math.abs(cf.LookVector.Y) * half.Z
			local bottom = cf.Position.Y - reach
			if bottom < lowest then
				lowest = bottom
			end
		end
	end

	if lowest == math.huge or not isFinite(lowest) then
		return 0
	end
	-- The pose was translated to MEASURE_PARK_Y, so subtract it to get the depth
	-- RELATIVE TO THE PIVOT -- which is the height the pivot must sit at when the
	-- die rests on a floor at y = 0.
	lowest -= MEASURE_PARK_Y
	return -lowest
end

-- THE ROTATION SOLVE -- the whole reason the builder records face normals.
--
-- The server chose a face. This returns the rotation that turns the die so that
-- face points UP, out of the felt, because a die at rest on a table shows its
-- answer on top. (The old flat board pointed the face at the CAMERA, which was
-- right when a die was a tile in its own frame and is wrong now that it is an
-- object lying on a surface.)
--
-- The model's local face normal is read from the attribute the builder wrote
-- when it generated the geometry -- a numeral's offset from the centroid IS its
-- outward normal.
--
-- DEGENERATE CASES ARE REAL AND BOTH ARE HANDLED. When the normal is already up
-- the cross product is zero-length and its `.Unit` is NaN, which would silently
-- poison every subsequent CFrame; when it points straight down the axis is
-- likewise undefined but a half-turn IS required. Neither can be left to float
-- behaviour -- a NaN CFrame does not error, it just makes the die vanish.
local function rotationShowingFace(model: Model, faceIndex: number): CFrame
	local normal = model:GetAttribute("FaceNormal" .. tostring(faceIndex))
	if typeof(normal) ~= "Vector3" then
		return CFrame.identity
	end

	local n = normal :: Vector3
	if n.Magnitude < 1e-4 then
		return CFrame.identity
	end
	n = n.Unit

	local up = Vector3.new(0, 1, 0)
	local dot = math.clamp(n:Dot(up), -1, 1)

	if dot > 0.9999 then
		-- Already up.
		return CFrame.identity
	end
	if dot < -0.9999 then
		-- Pointing straight down: a half turn about any horizontal axis.
		return CFrame.fromAxisAngle(Vector3.new(1, 0, 0), math.pi)
	end

	local axis = n:Cross(up)
	if axis.Magnitude < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Swaps a slot's solid to `shapeId`, or clears it when the shape is unknown or
-- unavailable. Idempotent: re-applying the same shape is a no-op, so a StateSync
-- on every roll does not rebuild the whole board.
local function applyModel(visual: DieVisual, shapeId: string?): ()
	-- THE GUARD MUST NOT CACHE A FAILURE AS A SUCCESS.
	--
	-- Comparing `modelShape` alone is not enough. The models replicate
	-- asynchronously, so the FIRST StateSync can easily arrive before they exist
	-- on this client. That call records the shape, finds no folder, and returns
	-- with no model -- and every subsequent call then matches on shape and
	-- returns early. The die is permanently absent and nothing reports an error,
	-- because each individual step behaved as written.
	--
	-- So the early exit requires the shape to match AND the model to actually be
	-- there. A shape that wanted no model (nil) is satisfied by having none.
	local satisfied = if shapeId == nil then visual.model == nil else visual.model ~= nil
	if visual.modelShape == shapeId and satisfied then
		return
	end

	local existing = visual.model
	if existing ~= nil then
		existing:Destroy()
	end
	visual.model = nil
	visual.modelShape = shapeId

	if shapeId == nil then
		return
	end

	local folder = findSource()
	if folder == nil then
		return
	end
	local source = folder:FindFirstChild(shapeId)
	if source == nil or not source:IsA("Model") then
		return
	end

	local clone = source:Clone()

	-- THE PIVOT MUST EXIST OR THE DIE ORBITS INSTEAD OF SPINNING.
	--
	-- `Model:PivotTo` turns the model about its pivot, and without a PrimaryPart
	-- that pivot is the bounding-box centre of whatever Roblox picks. The builder
	-- creates an invisible `Pivot` part at the centroid for exactly this reason,
	-- but a clone can arrive with `PrimaryPart` unset, so it is re-established
	-- here rather than assumed. Without a PrimaryPart the tumble becomes an
	-- orbit, which is the single most obvious way this animation can look wrong.
	if clone.PrimaryPart == nil then
		local pivot = clone:FindFirstChild("Pivot")
		if pivot ~= nil and pivot:IsA("BasePart") then
			clone.PrimaryPart = pivot
		end
	end

	-- PARKED OFF-SCREEN BEFORE IT IS PARENTED, and this is not defensive tidying.
	--
	-- Operator-reported 2026-08-15 as dice "breaking and deforming and then
	-- falling", with screenshots of coins appearing as fragments mid-flight.
	-- Sampling a die's pivot every frame through a roll found two discontinuities
	-- of ~11 studs, and printing the positions showed exactly what they were:
	--
	--     t=0.050  pos=(-2.44, 0.37,  7.08)   <- at rest
	--     t=0.118  pos=( 0.00, 0.00,  0.00)   <- ONE FRAME AT THE ORIGIN
	--     t=0.183  pos=( 4.72, 5.88,-10.87)   <- throw start
	--
	-- A freshly cloned model sits at whatever CFrame it was authored at -- the
	-- origin -- and `Parent` makes it visible IMMEDIATELY. The frame step does not
	-- run until the next frame, so for exactly one frame the die renders at the
	-- centre of the felt, at full size, in a pose belonging to no part of the
	-- animation. Two of those per roll, and at speed they read as the die tearing
	-- apart rather than as a position glitch.
	--
	-- Positioning BEFORE parenting closes the window entirely: the model is never
	-- visible anywhere it should not be. Far below the felt rather than at the
	-- rest point, because the rest point is not known yet at clone time and a
	-- wrong-but-plausible position is harder to spot than an obviously absent one.
	clone:PivotTo(CFrame.new(0, MEASURE_PARK_Y, 0))
	clone.Parent = BoardView.getScene()
	visual.model = clone
	visual.sourceRadius = measureRadius(clone)
end

-- Scales a solid so its bounding sphere matches the board's chosen radius for
-- the current die count.
--
-- Scaled here rather than at generation because the size depends on how many
-- dice are on the board, which the builder cannot know. `ScaleTo` is used rather
-- than walking parts by hand: it is pivot-relative and preserves the face
-- normals the rotation solve depends on.
local function applyRadius(visual: DieVisual, radius: number): ()
	visual.radius = radius

	local model = visual.model
	if model == nil then
		return
	end
	if visual.sourceRadius <= 1e-4 then
		return
	end

	local want = radius / visual.sourceRadius
	local current = model:GetScale()
	if current > 1e-6 and math.abs(current - want) < 1e-3 then
		return
	end
	model:ScaleTo(want)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- A die's screen-space furniture. The solid itself is created lazily by
-- `applyModel`, because a shape that has not arrived must not be drawn.
local function makeVisual(index: number): DieVisual
	local layer = overlay

	local bar = Instance.new("Frame")
	bar.Name = "Weight" .. tostring(index)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Size = UDim2.fromScale(BAR_W, BAR_H)
	bar.BackgroundColor3 = UITheme.Colors.PanelDeep
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.ZIndex = 4
	if layer ~= nil then
		bar.Parent = layer
	end

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = UITheme.Colors.TextGold
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 5
	barFill.Parent = bar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = barFill

	return {
		model = nil,
		modelShape = nil,
		sourceRadius = 0,
		bar = bar,
		barFill = barFill,
		barShown = false,
		shape = DEFAULT_SHAPE,
		faceCount = FACE_COUNTS[DEFAULT_SHAPE],
		numbered = false,
		weights = {},
		radius = 1,
		sitHeight = 0,
	}
end

-- Returns slot `index`, creating it if the board has never been this large.
-- This is what removes the die-count ceiling: there is no preallocated array to
-- run off the end of.
local function ensureSlot(index: number): DieSlot
	local existing = slots[index]
	if existing ~= nil then
		return existing
	end

	local slot: DieSlot = {
		visual = makeVisual(index),
		inUse = false,
		animating = false,
		elapsed = 0,
		arcs = {},
		flightTime = 0,
		restPos = Vector3.new(0, 1, 0),
		touchdown = Vector3.new(0, 1, 0),
		spinTotal = 0,
		spinDir = 1,
		heavyLean = 0,
		faceIndex = 1,
		spinAxis = Vector3.new(0, 1, 0),
		finalRot = CFrame.identity,
	}
	slots[index] = slot
	return slot
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------

local function readShape(config: any): string?
	if type(config) ~= "table" then
		return nil
	end
	local shape = config.Shape or config.shape
	if type(shape) == "string" and FACE_COUNTS[shape] ~= nil then
		return shape
	end
	return nil
end

local function readFaces(config: any): { any }
	if type(config) ~= "table" then
		return {}
	end
	local faces = config.Faces or config.faces
	if type(faces) == "table" then
		return faces :: { any }
	end
	return {}
end

-- Normalised mass per face. Returns fractions summing to 1 across the die, or an
-- empty table when the masses cannot be read -- in which case no bar is drawn,
-- rather than a bar drawn at a guessed value.
local function readWeights(faces: { any }, faceCount: number): { number }
	local raw: { number } = {}
	local total = 0
	for i = 1, faceCount do
		local face = faces[i]
		local mass = 0
		if type(face) == "table" then
			local m = face.Mass or face.mass
			if type(m) == "number" and isFinite(m) and m > 0 then
				mass = m
			end
		end
		raw[i] = mass
		total += mass
	end
	if total <= 0 then
		return {}
	end
	for i = 1, faceCount do
		raw[i] = raw[i] / total
	end
	return raw
end

-- Applies shape and mass to a die's appearance. Never touches position or
-- rotation -- those belong to the animation, and a config arriving mid-flight
-- must not snap a die that is in the air.
local function applyConfig(visual: DieVisual, shapeId: string?, faces: { any }): ()
	local resolved = shapeId or DEFAULT_SHAPE
	visual.shape = resolved
	visual.faceCount = FACE_COUNTS[resolved] or FACE_COUNTS[DEFAULT_SHAPE]
	visual.numbered = shapeId ~= nil
	visual.weights = readWeights(faces, visual.faceCount)

	-- Passing `shapeId` rather than `resolved` on purpose: an unknown shape must
	-- draw NO die, not a default D6 that would be asserting a shape the client
	-- has not been told.
	applyModel(visual, shapeId)
end

-- Paints the weight bar for `faceIndex`: its share of the die's mass.
local function showFace(visual: DieVisual, faceIndex: number): ()
	if not visual.numbered then
		visual.barShown = false
		visual.bar.Visible = false
		return
	end

	local weight = visual.weights[faceIndex]
	if weight == nil then
		-- Masses unreadable. Better to draw no bar than a bar at a guess.
		visual.barShown = false
		visual.bar.Visible = false
		return
	end

	visual.barShown = true

	-- The bar is scaled against an EVEN share, not against 1.0. A D20 face
	-- holding 10% of the die's mass is carrying twice its share and must read as
	-- heavy; against 1.0 it would render as a nearly empty bar and read as light.
	-- Even share is the only baseline that means the same thing on a D4 and a
	-- D20.
	local evenShare = 1 / math.max(1, visual.faceCount)
	local relative = weight / evenShare
	-- 2x even share fills the bar. Beyond that it is already full and the colour
	-- carries the rest.
	local fill = math.clamp(relative / 2, 0, 1)
	visual.barFill.Size = UDim2.fromScale(fill, 1)

	-- A VOID face -- one carrying so little mass it effectively never lands -- is
	-- drawn dim and grey. This mirrors what the HUD's VOID readout reports, so
	-- the two cannot tell the player different stories.
	if fill <= 0.001 then
		visual.barFill.BackgroundColor3 = UITheme.Colors.VoidFace
	elseif fill >= GLOW_THRESHOLD then
		visual.barFill.BackgroundColor3 = UITheme.Colors.TextGold
	else
		visual.barFill.BackgroundColor3 = UITheme.Colors.TextDim
	end
end

--------------------------------------------------------------------------------
-- The ballistics
--------------------------------------------------------------------------------

-- Solves the launch velocity that carries a die from `origin` to `target` in
-- exactly `duration` seconds under constant downward gravity.
--
-- Straight from `p = p0 + v*t + 0.5*g*t^2`, rearranged for v. The horizontal
-- components are simply distance over time; the vertical one carries the extra
-- term that makes the path a parabola rather than a line.
--
-- THIS IS WHY THE ARC IS REAL. The old renderer interpolated a position and then
-- added a hand-shaped hump to the height, which is a drawing of a parabola. This
-- computes the velocity an object would actually need, and the position is then
-- integrated from it -- so the die accelerates downward correctly, arrives with
-- the right speed for its bounce, and looks the way it does because of physics
-- rather than in imitation of it.
local function solveThrow(origin: Vector3, target: Vector3, duration: number): Arc
	local t = math.max(duration, 1e-3)
	local delta = target - origin
	local velocity = Vector3.new(
		delta.X / t,
		delta.Y / t + 0.5 * GRAVITY * t,
		delta.Z / t
	)
	return { origin = origin, velocity = velocity, duration = t }
end

-- Position and elapsed-relative velocity along an arc at local time `t`.
local function arcPosition(arc: Arc, t: number): Vector3
	return arc.origin + arc.velocity * t + Vector3.new(0, -0.5 * GRAVITY * t * t, 0)
end

-- A bounce too small to see is not worth its own arc; the settle absorbs it.
local MIN_BOUNCE_TIME = 0.02

-- How long the die spends in the air on each bounce, given the vertical speed it
-- arrived at the floor with.
--
-- Each bounce returns RESTITUTION of the vertical speed it arrived with, and its
-- airtime follows from that speed -- `2*v/g`, up and back down -- rather than
-- being chosen. That is what makes each bounce visibly SMALLER than the last
-- rather than merely shorter.
--
-- STATED ONCE, because two things need it: `buildFlight` builds the arcs from
-- it, and `solveFirstContact` needs the same numbers to work out where the die
-- must first touch down. Computing it twice is exactly the duplication that
-- drifts (L-025) -- and here a drift would put the dice down in the wrong place
-- with no error to show for it.
local function bounceAirtimes(arrivalVy: number): { number }
	local out: { number } = {}
	local vy = math.abs(arrivalVy)
	for _ = 1, BOUNCE_COUNT do
		vy = vy * RESTITUTION
		local airtime = (2 * vy) / GRAVITY
		if airtime < MIN_BOUNCE_TIME then
			break
		end
		table.insert(out, airtime)
	end
	return out
end

-- The vertical speed a die is travelling at when it first reaches the floor.
-- Depends only on heights and airtime, never on where it lands horizontally,
-- which is what makes the contact solve below tractable.
local function arrivalSpeed(originY: number, floorY: number, throwTime: number): number
	local t = math.max(throwTime, 1e-3)
	local launch = (floorY - originY) / t + 0.5 * GRAVITY * t
	return launch - GRAVITY * t
end

-- WHERE THE DIE MUST FIRST TOUCH DOWN so that its bounces carry it to exactly
-- the rest point it was assigned.
--
-- THE DEFECT THIS FIXES, because the symptom was subtle and the cause was not.
-- The die used to be aimed at its rest point (plus a little jitter) for the
-- FIRST contact, and the two bounces then carried it several studs PAST there.
-- The settle had to drag it back -- measured at 5.6 studs on one sampled roll --
-- so every die finished by skating across the felt to its mark. The bounces
-- looked right and the ending looked staged.
--
-- Solved backwards instead. After the first contact the die travels
-- `v_h * FRICTION * a1 + v_h * FRICTION^2 * a2`, and `v_h` is itself
-- `(contact - origin) / throwTime`. Writing `K` for the bracketed airtime sum,
-- the rest point is `contact * (1 + K/T) - origin * K/T`, which rearranges to
-- give the contact directly. The bounces then DELIVER the die rather than
-- overshooting it, and the settle is left with nothing to correct.
local function solveFirstContact(origin: Vector3, rest: Vector3, throwTime: number): Vector3
	local t = math.max(throwTime, 1e-3)
	local airtimes = bounceAirtimes(arrivalSpeed(origin.Y, rest.Y, t))

	local k = 0
	local carry = FRICTION
	for _, airtime in ipairs(airtimes) do
		k += carry * airtime
		carry *= FRICTION
	end

	local ratio = k / t
	local denom = 1 + ratio
	if denom < 1e-6 then
		return rest
	end

	return Vector3.new(
		(rest.X + origin.X * ratio) / denom,
		rest.Y,
		(rest.Z + origin.Z * ratio) / denom
	)
end

-- Builds the whole flight: the throw, then one arc per bounce.
local function buildFlight(origin: Vector3, landing: Vector3, throwTime: number): ({ Arc }, number, Vector3)
	local arcs: { Arc } = {}

	local first = solveThrow(origin, landing, throwTime)
	table.insert(arcs, first)

	local total = first.duration
	local contact = landing
	local velocity = first.velocity + Vector3.new(0, -GRAVITY * first.duration, 0)

	for _, airtime in ipairs(bounceAirtimes(velocity.Y)) do
		local bounceVelocity = Vector3.new(
			velocity.X * FRICTION,
			math.abs(velocity.Y) * RESTITUTION,
			velocity.Z * FRICTION
		)

		local arc: Arc = {
			origin = contact,
			velocity = bounceVelocity,
			duration = airtime,
		}
		table.insert(arcs, arc)

		total += airtime
		contact = arcPosition(arc, airtime)
		velocity = bounceVelocity + Vector3.new(0, -GRAVITY * airtime, 0)
	end

	return arcs, total, contact
end

-- Where the die is at flight-time `t`, walking the arcs in order.
local function flightPosition(slot: DieSlot, t: number): Vector3
	local remaining = t
	for _, arc in ipairs(slot.arcs) do
		if remaining <= arc.duration then
			return arcPosition(arc, remaining)
		end
		remaining -= arc.duration
	end
	return slot.touchdown
end

--------------------------------------------------------------------------------
-- The roll
--------------------------------------------------------------------------------

-- Which face is heaviest, used only to decide which way the settle leans.
-- Returns 0 when masses are unknown.
local function heaviestFace(visual: DieVisual): number
	local best, bestIndex = -1, 0
	for i = 1, visual.faceCount do
		local w = visual.weights[i]
		if w ~= nil and w > best then
			best, bestIndex = w, i
		end
	end
	return bestIndex
end

-- Hides slots beyond `count`, and releases their solids. Called whenever the
-- board shrinks, which the old fixed pool handled by iterating to seven.
local function hideFrom(count: number): ()
	for i = count + 1, #slots do
		local slot = slots[i]
		if slot ~= nil and slot.inUse then
			slot.inUse = false
			slot.animating = false
			slot.visual.barShown = false
			slot.visual.bar.Visible = false
			local model = slot.visual.model
			if model ~= nil then
				model:Destroy()
			end
			slot.visual.model = nil
			slot.visual.modelShape = nil
		end
	end
end

local function beginRoll(faces: { any }, payout: number): ()
	local count = #diceConfig
	if count <= 0 then
		return
	end

	-- A bigger payout buys a longer, fuller tumble.
	local magnitude = 0
	if type(payout) == "number" and isFinite(payout) and payout > 0 then
		magnitude = math.clamp(math.log(1 + payout) / math.log(1 + 1e6), 0, 1)
	end
	local throwTime = THROW_TIME_MIN + (THROW_TIME_MAX - THROW_TIME_MIN) * magnitude
	local bonusTurns = math.floor(SPIN_TURNS_PAYOUT_BONUS * magnitude + 0.5)

	local radius = BoardView.getDieRadius(count)
	local rollSummaryData: { { shape: string, value: number } } = {}

	-- Rest points are sampled together so each can be kept clear of the ones
	-- already chosen. This is what produces organic scatter without stacking.
	local taken: { Vector3 } = {}

	for i = 1, count do
		local slot = ensureSlot(i)

		local config = diceConfig[i]
		local shapeId = readShape(config)
		applyConfig(slot.visual, shapeId, readFaces(config))
		applyRadius(slot.visual, radius)

		local target = faces[i]
		local faceIndex = 1
		if type(target) == "number" and isFinite(target) and target >= 1 then
			faceIndex = math.floor(target)
		end
		faceIndex = math.clamp(faceIndex, 1, math.max(1, slot.visual.faceCount))
		slot.faceIndex = faceIndex

		table.insert(rollSummaryData, {
			shape = shapeId or DEFAULT_SHAPE,
			value = faceIndex,
		})

		slot.spinTotal = (
			rng:NextInteger(SPIN_TURNS_MIN, SPIN_TURNS_MAX)
			+ bonusTurns
			+ rng:NextNumber(SPIN_FRACTION_MIN, SPIN_FRACTION_MAX)
		) * TAU
		slot.spinDir = if rng:NextNumber() < 0.5 then -1 else 1

		-- The tumble axis is random per die and deliberately off-axis -- dice that
		-- all spun about Y would read as a carousel. Normalised because
		-- `CFrame.fromAxisAngle` on a non-unit axis scales the angle silently, and
		-- a near-zero random vector has no meaningful direction at all.
		local axis = Vector3.new(
			rng:NextNumber(-1, 1),
			rng:NextNumber(-1, 1),
			rng:NextNumber(-1, 1)
		)
		slot.spinAxis = if axis.Magnitude > 1e-3 then axis.Unit else Vector3.new(0, 1, 0)

		-- `finalRot` is where the die must END: the orientation showing the face
		-- the server chose, face up. The flight then unwinds its residual spin
		-- ONTO that destination, so the die arrives correct without ever having
		-- been placed there early.
		local model = slot.visual.model
		slot.finalRot = if model ~= nil
			then rotationShowingFace(model, faceIndex)
			else CFrame.identity

		-- THE HEAVY-SIDE DRAG. If the face that landed is NOT the heaviest one,
		-- the die leans away from the heavy face as it settles -- it visibly
		-- avoided resting there. If the heavy face DID land, the lean is zero: the
		-- die gave in, which is the rarer, more notable event and should look
		-- different. Cosmetic only; the outcome arrived decided.
		local heavy = heaviestFace(slot.visual)
		if heavy ~= 0 and heavy ~= faceIndex then
			slot.heavyLean = HEAVY_LEAN * slot.spinDir
		else
			slot.heavyLean = 0
		end

		-- The die's own resting height, measured now that `finalRot` is known --
		-- the sit height depends on WHICH face is up, so it cannot be cached per
		-- shape. Measured before the rest point is used, because the rest point's
		-- Y comes from it.
		local sit = if model ~= nil
			then measureSitHeight(model, slot.finalRot * REST_TILT)
			else 0
		slot.visual.sitHeight = sit

		-- ORGANIC SCATTER, sampled per throw and kept clear of its neighbours.
		-- `sampleRestPoint` gives the point on the FELT; the die's centre sits its
		-- own measured height above that.
		local sample = BoardView.sampleRestPoint(radius, taken)
		table.insert(taken, sample)
		local rest = Vector3.new(sample.X, BoardView.getFloorY() + sit, sample.Z)
		slot.restPos = rest

		-- The die touches down SHORT of where it stops and the bounces carry it the
		-- rest of the way -- a die that first lands exactly where it ends up has
		-- not bounced, it has been placed. The contact point is solved so those
		-- bounces arrive precisely on the rest point rather than past it.
		--
		-- Clamped because a rest point near the far edge can put its first contact
		-- just off the felt. Clamping costs a little exactness, which the settle
		-- then absorbs, and that is much the better trade: a die contacting thin
		-- air outside the tray is a visible break of FR-1.4's whole premise.
		-- EACH DIE GETS ITS OWN AIRTIME. Sharing one throw time across the roll
		-- made every die rise, peak and land on the same beat -- six dice moving
		-- as one clump, which is the single clearest tell that a throw was
		-- animated rather than thrown. A small per-die jitter staggers the arcs
		-- and, because airtime sets the launch velocity, gives each die its own
		-- arc height too. Staggering the START instead would have left dice
		-- hovering visibly at their release point, which is worse.
		local ownTime = math.max(0.2, throwTime + rng:NextNumber(-0.07, 0.07))

		local origin = BoardView.sampleThrowPoint()
		local aim = BoardView.clampToBoard(
			solveFirstContact(origin, rest, ownTime),
			radius
		)
		local arcs, flightTime, touchdown = buildFlight(origin, aim, ownTime)
		slot.arcs = arcs
		slot.flightTime = flightTime
		slot.touchdown = touchdown

		slot.elapsed = 0
		slot.animating = true
		slot.inUse = true

		showFace(slot.visual, faceIndex)
	end

	hideFrom(count)
	BoardView.updateResultSummary(rollSummaryData)
end

--------------------------------------------------------------------------------
-- The frame step
--------------------------------------------------------------------------------

-- Ease-out cubic. Fast in, slow out -- what a settling object does.
local function easeOut(a: number): number
	local inv = 1 - a
	return 1 - inv * inv * inv
end

-- Projects a scene point to the overlay's scale coordinates, so a weight bar can
-- follow its die.
--
-- SOLVED BY HAND RATHER THAN VIA `Camera:WorldToViewportPoint`, and that is not
-- a preference. That method projects using the camera's `ViewportSize`, which
-- Roblox maintains for the Workspace camera against the real screen -- a camera
-- belonging to a ViewportFrame is not the screen and its `ViewportSize` does not
-- describe the frame it draws into. Using it would put every bar somewhere
-- plausible and wrong, and would be wrong differently at each window size, which
-- is the hardest kind of visual bug to catch.
--
-- The perspective divide is four lines and depends only on values this module
-- can see: the camera's own CFrame and field of view, and the frame's measured
-- size. Roblox's FOV is VERTICAL, so the horizontal term carries the aspect
-- ratio.
--
-- Returns the point in [0,1] scale of the viewport rectangle, and whether it is
-- in front of the camera at all -- behind it the divide inverts and the bar
-- would be drawn mirrored across the frame.
local function project(vp: ViewportFrame, cam: Camera, point: Vector3): (UDim2, boolean)
	local size = vp.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return UDim2.fromScale(0.5, 0.5), false
	end

	-- Camera space looks down its own -Z, so a visible point has negative Z.
	local local_ = cam.CFrame:PointToObjectSpace(point)
	local depth = -local_.Z
	if depth <= 0.05 then
		return UDim2.fromScale(0.5, 0.5), false
	end

	local tanHalf = math.tan(math.rad(cam.FieldOfView) * 0.5)
	if tanHalf <= 1e-6 then
		return UDim2.fromScale(0.5, 0.5), false
	end
	local aspect = size.X / size.Y

	local ndcX = (local_.X / depth) / (tanHalf * aspect)
	local ndcY = (local_.Y / depth) / tanHalf

	-- NDC is [-1,1] with +Y up; scale coordinates are [0,1] with +Y down.
	return UDim2.fromScale(0.5 + ndcX * 0.5, 0.5 - ndcY * 0.5), true
end

local function step(delta: number): ()
	if not BoardView.isReady() then
		return
	end

	local vp = BoardView.getViewport()
	local cam = vp.CurrentCamera
	if cam == nil then
		return
	end

	for _, slot in ipairs(slots) do
		if not slot.inUse then
			continue
		end

		local model = slot.visual.model
		if model == nil then
			slot.visual.bar.Visible = false
			continue
		end

		if slot.animating then
			slot.elapsed += delta
		end

		local total = slot.flightTime + SETTLE_TIME

		-- WHERE THE DIE ENDS UP, as one orientation used by every phase.
		--
		-- EVERY PHASE MUST AGREE ON THIS OR THE DIE POPS. An earlier pass applied
		-- `REST_TILT` only during the settle and gave the settle its own residual
		-- spin, so at the instant flight became settle the die jumped by the tilt
		-- plus about 31 degrees -- a visible snap at exactly the moment the eye is
		-- on the die waiting for the answer. Both the flight and the settle now
		-- rotate AROUND this same target and decay to it, so every phase boundary
		-- is continuous by construction rather than by tuning.
		local target = slot.finalRot * REST_TILT

		local position: Vector3
		local rotation: CFrame

		if slot.elapsed >= total then
			-- AT REST. Exactly on the sampled point, exactly on the chosen face.
			slot.animating = false
			slot.elapsed = total
			position = slot.restPos
			rotation = target
		elseif slot.elapsed < slot.flightTime then
			-- IN FLIGHT: the throw and its bounces, integrated.
			position = flightPosition(slot, slot.elapsed)

			-- The tumble decays across the flight, so the die turns fastest as it
			-- leaves the hand and has stopped turning exactly as it touches down.
			-- Reaching zero AT the flight's end is what makes the handover to the
			-- settle seamless.
			local a = math.clamp(slot.elapsed / math.max(slot.flightTime, 1e-3), 0, 1)
			local remaining = (1 - a) * (1 - a)
			rotation = target * CFrame.fromAxisAngle(
				slot.spinAxis,
				remaining * slot.spinTotal * slot.spinDir
			)
		else
			-- THE SETTLE: from wherever the last bounce left the die to its exact
			-- rest point, rocking off the heavy face on the way.
			local a = math.clamp((slot.elapsed - slot.flightTime) / SETTLE_TIME, 0, 1)
			local eased = easeOut(a)

			position = slot.touchdown:Lerp(slot.restPos, eased)

			-- A small hop out of the last contact, dying to nothing. Without it the
			-- die slides to its rest point, which is the one motion a thrown die
			-- never makes.
			local hop = math.sin(a * math.pi) * slot.visual.radius * 0.28 * (1 - a)
			position = Vector3.new(position.X, position.Y + hop, position.Z)

			-- The lean peaks mid-settle and resolves to zero at both ends, so the
			-- die rocks off its heavy side and comes down flat -- and, because
			-- sin(0) and sin(pi) are both zero, it adds nothing at either boundary.
			rotation = target * CFrame.fromAxisAngle(
				Vector3.new(0, 0, 1),
				slot.heavyLean * math.sin(a * math.pi)
			)
		end

		-- A non-finite CFrame does not error -- it makes the die vanish, silently
		-- and permanently. Cheaper to check than to diagnose.
		if not isFiniteVector(position) then
			position = slot.restPos
			rotation = slot.finalRot * REST_TILT
		end

		model:PivotTo(CFrame.new(position) * rotation)

		-- The weight bar tracks the die, sitting just below it.
		--
		-- SHOWN ONLY WHEN THE DIE IS AT REST, which is what FR-1.3 asks for -- it
		-- is a readout of the die's mass, to be studied, not a part of the throw.
		-- Bars chasing tumbling dice through the air added motion that competed
		-- with the dice themselves for attention and told the player nothing they
		-- could read at that speed.
		--
		-- Recomputed from the INTENT every frame rather than latched, so a bar
		-- hidden for a transient reason comes back when the reason passes.
		local bar = slot.visual.bar
		if slot.visual.barShown and not slot.animating then
			-- Anchored just under the die's own footprint. Uses the measured sit
			-- height rather than the bounding radius, which for a flat coin would
			-- have placed the bar several studs below the felt.
			local anchor = position - Vector3.new(0, slot.visual.sitHeight + 0.5, 0)
			local at, inFront = project(vp, cam, anchor)
			bar.Visible = inFront
			if inFront then
				bar.Position = at
			end
		else
			bar.Visible = false
		end
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

	if not BoardView.isReady() then
		-- ClientBootstrap constructs in dependency order, so this cannot happen
		-- from the normal path. Failing loudly beats rendering into nothing.
		error("[DiceRenderer] BoardView must be initialised first", 0)
	end

	-- The overlay the weight bars live on. Parented over the viewport, inside the
	-- same interior, so its scale coordinates and the viewport's projected ones
	-- refer to the same rectangle.
	local vp = BoardView.getViewport()
	local layer = Instance.new("Frame")
	layer.Name = "DiceOverlay"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	-- CLIPPED TO THE TRAY. Bars are positioned by projecting a 3D point, and a
	-- die above the top of the frame projects to a point above the tray -- so
	-- without this the bars escaped the board entirely and drew across the HUD's
	-- currency bar. Observed exactly that way in a mid-roll screenshot.
	layer.ClipsDescendants = true
	layer.ZIndex = 3
	layer.Parent = vp.Parent
	overlay = layer

	-- Redraws every resting die from the last known config. Extracted from the
	-- StateSync handler so the late-replication watcher can reuse it: a client
	-- whose first snapshot arrived before the models did needs to rebuild WITHOUT
	-- waiting for another state change, which for a player who is not rolling may
	-- never come.
	local function refreshResting(): ()
		local count = #diceConfig
		if count <= 0 then
			hideFrom(0)
			BoardView.updateResultSummary(nil)
			return
		end

		local radius = BoardView.getDieRadius(count)
		local taken: { Vector3 } = {}

		for i = 1, count do
			local slot = ensureSlot(i)
			if slot.animating then
				-- A config change mid-flight re-skins the die on the next roll
				-- rather than snapping it while it is in the air.
				table.insert(taken, slot.restPos)
				continue
			end

			applyConfig(slot.visual, readShape(diceConfig[i]), readFaces(diceConfig[i]))
			applyRadius(slot.visual, radius)

			local sample = BoardView.sampleRestPoint(radius, taken)
			table.insert(taken, sample)

			-- Face-up orientation first, because the sit height depends on it.
			local model = slot.visual.model
			local sit = 0
			if model ~= nil then
				slot.finalRot = rotationShowingFace(model, slot.faceIndex)
				sit = measureSitHeight(model, slot.finalRot * REST_TILT)
			end
			slot.visual.sitHeight = sit

			local rest = Vector3.new(sample.X, BoardView.getFloorY() + sit, sample.Z)
			slot.restPos = rest
			slot.touchdown = rest
			slot.arcs = {}
			slot.flightTime = 0
			-- Parked past the end of its own timeline, so the frame step draws it
			-- at rest without animating it in.
			slot.elapsed = SETTLE_TIME
			slot.animating = false
			slot.inUse = true

			-- Park the solid showing the same face the last roll reported. Without
			-- this a die at rest sits in whatever orientation it was built in, and
			-- would contradict the result bar beside it. (`measureSitHeight` left
			-- it at the origin, so this is also what puts it on the felt.)
			if model ~= nil then
				model:PivotTo(CFrame.new(rest) * slot.finalRot * REST_TILT)
			end

			showFace(slot.visual, slot.faceIndex)
		end

		hideFrom(count)
	end

	-- Show the player's dice at rest before they have rolled anything, so the
	-- board is never empty and FR-1.3 is readable the moment they arrive.
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
		refreshResting()
	end))

	-- If the solids replicate after this client has already drawn, redraw once so
	-- the dice appear rather than staying absent until the next state change.
	onDiceAvailable = refreshResting
	local watcher = watchForDice()
	if watcher ~= nil then
		table.insert(connections, watcher)
	end

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
-- the overlay and every pooled Instance. Symmetric with `BoardView.shutdown`.
--
-- Tearing down mid-flight is safe by construction and always was: the payout was
-- credited before this module heard about the roll (FR-2.6), so an animation
-- that never finishes costs a visual and nothing else.
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
	-- keeping the old one would leak a solid and a bar per die on every restart.
	for _, slot in ipairs(slots) do
		local model = slot.visual.model
		if model ~= nil then
			model:Destroy()
		end
		slot.visual.bar:Destroy()
	end
	slots = {}
	diceConfig = {}

	local layer = overlay
	if layer ~= nil then
		layer:Destroy()
	end
	overlay = nil

	-- The late-replication callback closes over `refreshResting`, which closes
	-- over the slot pool this function just destroyed. Its own connection is
	-- released above, but clearing the reference means a stale closure cannot
	-- outlive the pool it would write into.
	onDiceAvailable = nil

	started = false
end

return DiceRenderer
