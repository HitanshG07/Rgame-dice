--!strict
-- ArenaView.luau
-- The contained low-poly 3D pit, the camera that looks into it, and the anchor
-- points every die rests on (SRS FR-1.1, FR-1.4; HLD §4.3).
--
-- WHY THE ARENA OWNS THE ANCHORS RATHER THAN THE RENDERER. FR-1.4 requires that
-- a die come to rest FULLY INSIDE the pit. If the renderer chose its own resting
-- places, "inside" would be a property the renderer happened to preserve; here it
-- is a property the arena ENFORCES, because `clampToArena` is the only way to
-- obtain a legal position and the renderer has nothing else to call. The pit's
-- dimensions and the containment rule therefore cannot drift apart -- they are
-- the same constants.
--
-- WHY IT IS BUILT FROM PARTS AT RUNTIME. No asset ids: an arena assembled from
-- primitives is reviewable in this file, cannot silently change under us when a
-- marketplace asset is edited or taken down, and needs no upload step to alter.
-- Six boxes and a rim is the whole geometry.
--
-- WHY IT SITS AT Y = 500. The pit is a self-contained stage, not a place in a
-- world. Parking it far above the default baseplate guarantees nothing else --
-- terrain, spawn locations, another developer's test rig -- can ever intrude
-- into a shot that is framed to be entirely pit.
--
-- EVERY COLOUR COMES FROM UITheme. The 3D stage and the 2D chrome are one
-- interface, and a maroon invented here would be a second, slightly different
-- maroon (see UITheme's own header).
--
-- This module holds no economic state and sends nothing to the server. It does
-- not require NetClient at all; `init` accepts it because ClientBootstrap calls
-- every view module the same way, and a uniform signature is worth more than
-- saving one unused parameter.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent:WaitForChild("UITheme"))

local ArenaView = {}

--------------------------------------------------------------------------------
-- Geometry. Every number here is studs.
--------------------------------------------------------------------------------

-- Interior half-extent measured from the centre to the INNER face of a wall.
local INNER_HALF = 13
local WALL_HEIGHT = 5
local WALL_THICK = 1
local FLOOR_THICK = 1
local RIM_HEIGHT = 0.35

local ORIGIN = Vector3.new(0, 500, 0)

-- The plane dice rest ON, i.e. the top surface of the floor slab.
local FLOOR_TOP = ORIGIN.Y

-- How far above the floor a resting die's underside is held. `radius` alone
-- puts the die's bounding surface EXACTLY on the floor plane, where any float
-- error -- or any caller that reports a nominal half-size rather than its true
-- maximum extent -- shows as the die sinking into the slab. One fiftieth of a
-- stud is invisible at the framing below and removes the whole class of bug.
local REST_EPSILON = 0.02

-- Camera. The baseline framing: the full 26x26 interior visible with margin,
-- tilted a few degrees off vertical, because dead-vertical reads as a flat
-- texture rather than as a pit with walls, and the tilt is small enough that
-- the view is still the top-down one FR-1.1 asks for.
--
-- BASELINE, NOT FINAL. `CAMERA_FOV` is Roblox's VERTICAL field of view, so the
-- horizontal angle it buys depends entirely on the viewport's aspect ratio. At
-- 27.9 studs out, the pit's near top corners sit ~36 degrees off axis, which a
-- 16:9 desktop covers easily and a 320x568 portrait phone (aspect 0.56, giving
-- only ~18 degrees horizontally at FOV 60) does not -- it crops both side walls
-- and every corner, and the pit stops reading as contained (NFR-3: 320px
-- through 4K). So the framing below is SOLVED against the live viewport rather
-- than assumed, widening the field of view and, if that is not enough, pulling
-- the camera back until all eight corners of the pit are inside the frustum.
local CAMERA_OFFSET = Vector3.new(0, 27, 7)
local CAMERA_FOV = 60

-- The widest vertical field of view we will accept before preferring to pull
-- the camera back instead. Past roughly this, perspective distortion bows the
-- walls badly enough that the pit reads as a funnel.
local CAMERA_FOV_MAX = 100

-- Fraction of slack kept outside the pit's silhouette, so the rim is framed
-- rather than touching the screen edge.
local FRAMING_MARGIN = 1.06

-- Pulling the camera back changes the angles it needs to cover, so the solve is
-- iterative. It converges in two passes at the narrowest viewport Roblox will
-- ever hand us; four is the fixed, terminating budget.
local FRAMING_PASSES = 4

-- Aspect ratios outside this range are not real viewports; they are a camera
-- reporting a zero or one-pixel dimension during startup or a resize. Clamping
-- keeps a transient garbage value from producing a garbage frustum.
local ASPECT_MIN = 0.2
local ASPECT_MAX = 6

-- Where the tumble begins: above the rim, so a die falls INTO the pit.
local SPAWN_HEIGHT = WALL_HEIGHT + 9

local MAX_DICE = 7
local RING_RADIUS = 7.0

--------------------------------------------------------------------------------
-- Slot layouts, precomputed once for every legal die count (FR-1.1: 1 to 7).
--
-- Precomputed rather than derived per roll because these are the same seven
-- answers forever, and a roll is not the moment to be doing trigonometry.
--------------------------------------------------------------------------------

local function buildLayouts(): { { Vector3 } }
	local layouts: { { Vector3 } } = {}
	for count = 1, MAX_DICE do
		local slots: { Vector3 } = {}
		if count == 1 then
			slots[1] = Vector3.zero
		elseif count <= 6 then
			-- one ring; evenly spaced
			for i = 1, count do
				local angle = ((i - 1) / count) * math.pi * 2
				slots[i] = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
			end
		else
			-- seven is one in the middle and six around it, which is the only
			-- arrangement of seven that stays evenly spaced inside a square pit
			slots[1] = Vector3.zero
			for i = 2, count do
				local angle = ((i - 2) / (count - 1)) * math.pi * 2
				slots[i] = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
			end
		end
		layouts[count] = slots
	end
	return layouts
end

local LAYOUTS: { { Vector3 } } = buildLayouts()

--------------------------------------------------------------------------------
-- Numeric hygiene
--
-- Every public entry point takes numbers from another module. NaN is the
-- dangerous one: it compares false against everything, so it survives
-- `math.clamp` unchanged, survives `math.floor` unchanged, and then indexes a
-- table as a key that cannot exist. A guard here turns a crash three calls
-- later into a defined, boring answer.
--------------------------------------------------------------------------------

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- A radius we cannot reason about is treated as no radius at all: the position
-- is still inside the pit, which is the guarantee callers actually depend on.
local function safeRadius(radius: number): number
	if not isFinite(radius) or radius < 0 then
		return 0
	end
	return radius
end

--------------------------------------------------------------------------------
-- The pit's silhouette, as the eight corners of its outer bounding box, stated
-- relative to (ORIGIN.X, FLOOR_TOP, ORIGIN.Z). The camera solve frames THESE
-- points, so the framing cannot drift from the geometry: change a wall constant
-- and the corners -- and therefore the camera -- follow.
--------------------------------------------------------------------------------

-- The framing target is the pit's PLAYABLE INTERIOR, not its outer shell.
--
-- This used to bound the whole structure -- outer wall faces, rim top, and
-- the underside of the floor slab -- which is a materially bigger box than
-- the space dice actually occupy. Solving to fit it pushed the eye back far
-- enough that a die read as a speck on screen. Nothing below the floor and
-- nothing outside the walls ever needs to be visible; a rim edge clipping at
-- the frame's corner is not a defect, a die leaving frame is.
local function buildCorners(): { Vector3 }
	local half = INNER_HALF
	local top = WALL_HEIGHT
	local bottom = 0
	local corners: { Vector3 } = {}
	local n = 0
	for signX = -1, 1, 2 do
		for signZ = -1, 1, 2 do
			for level = 0, 1 do
				local y = if level == 0 then bottom else top
				n += 1
				corners[n] = Vector3.new(half * signX, y, half * signZ)
			end
		end
	end
	return corners
end

local PIT_CORNERS: { Vector3 } = buildCorners()

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local container: Folder? = nil
local built = false

-- Every signal subscription this module makes, so `shutdown` can undo all of
-- them without knowing what they were for.
local connections: { RBXScriptConnection } = {}

-- The camera settings as we found them, so shutdown hands the player's camera
-- back the way it was borrowed rather than the way we happened to leave it.
local restoreFov: number? = nil
local restoreFovMode: Enum.FieldOfViewMode? = nil

local function makeSlab(name: string, size: Vector3, position: Vector3, colour: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = colour
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- CanCollide is false on EVERY part of the pit, deliberately. HLD §4.3: the
-- physics body is decorative. Nothing in this game is simulated -- dice are
-- driven kinematically to a face the server already chose -- so collision
-- geometry would cost solver time to enforce a containment rule that
-- `clampToArena` already guarantees exactly.
local function build(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "DiceForgeArena"

	local span = (INNER_HALF + WALL_THICK) * 2

	makeSlab(
		"Floor",
		Vector3.new(span, FLOOR_THICK, span),
		ORIGIN - Vector3.new(0, FLOOR_THICK / 2, 0),
		UITheme.Colors.PanelDark,
		folder
	)

	-- A recessed inner well, one shade deeper, so the play area reads as a pit
	-- floor rather than as a tabletop.
	makeSlab(
		"Well",
		Vector3.new(INNER_HALF * 2, 0.08, INNER_HALF * 2),
		ORIGIN + Vector3.new(0, 0.04, 0),
		UITheme.Colors.PanelDeep,
		folder
	)

	local wallY = FLOOR_TOP + WALL_HEIGHT / 2
	local wallOffset = INNER_HALF + WALL_THICK / 2
	local wallLong = Vector3.new(span, WALL_HEIGHT, WALL_THICK)
	local wallSide = Vector3.new(WALL_THICK, WALL_HEIGHT, span)

	makeSlab("WallNorth", wallLong, Vector3.new(ORIGIN.X, wallY, ORIGIN.Z - wallOffset), UITheme.Colors.PanelMaroon, folder)
	makeSlab("WallSouth", wallLong, Vector3.new(ORIGIN.X, wallY, ORIGIN.Z + wallOffset), UITheme.Colors.PanelMaroon, folder)
	makeSlab("WallWest", wallSide, Vector3.new(ORIGIN.X - wallOffset, wallY, ORIGIN.Z), UITheme.Colors.PanelMaroon, folder)
	makeSlab("WallEast", wallSide, Vector3.new(ORIGIN.X + wallOffset, wallY, ORIGIN.Z), UITheme.Colors.PanelMaroon, folder)

	-- The gold rim is the 3D echo of FR-13.1's 1-pixel gold border. Same colour
	-- constant, same job: it tells the eye where the surface ends.
	local rimY = FLOOR_TOP + WALL_HEIGHT + RIM_HEIGHT / 2
	local rimLong = Vector3.new(span, RIM_HEIGHT, WALL_THICK)
	local rimSide = Vector3.new(WALL_THICK, RIM_HEIGHT, span)

	makeSlab("RimNorth", rimLong, Vector3.new(ORIGIN.X, rimY, ORIGIN.Z - wallOffset), UITheme.Colors.BorderGold, folder)
	makeSlab("RimSouth", rimLong, Vector3.new(ORIGIN.X, rimY, ORIGIN.Z + wallOffset), UITheme.Colors.BorderGold, folder)
	makeSlab("RimWest", rimSide, Vector3.new(ORIGIN.X - wallOffset, rimY, ORIGIN.Z), UITheme.Colors.BorderGold, folder)
	makeSlab("RimEast", rimSide, Vector3.new(ORIGIN.X + wallOffset, rimY, ORIGIN.Z), UITheme.Colors.BorderGold, folder)

	-- One contained light source. Lighting itself is NOT touched: the pit is
	-- lit from inside its own folder, so nothing this module does can alter how
	-- any other surface in the game is lit.
	local anchor = Instance.new("Part")
	anchor.Name = "PitLight"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = ORIGIN + Vector3.new(0, WALL_HEIGHT + 6, 0)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = folder

	local light = Instance.new("PointLight")
	-- The pit is lit in the same gold as its rim, so the light reads as coming
	-- from the stage rather than from nowhere. UITheme has no constant NAMED for
	-- lighting; BorderGold is used because gold is what this light IS, and
	-- because tying it to the rim keeps one warm tone in the pit instead of two.
	-- (A dedicated `UITheme.Colors.PitLight` would say it better -- UITheme is
	-- outside this module's write set, so that is reported, not added.)
	light.Color = UITheme.Colors.BorderGold
	light.Brightness = 2.4
	light.Range = 46
	light.Shadows = false
	light.Parent = anchor

	folder.Parent = Workspace
	return folder
end

--------------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------------

-- The half-angles, as tangents, that an eye at `eye` needs in order to see every
-- corner of the pit. Returned as tangents rather than degrees because the aspect
-- correction below is a multiplication on tangents and a transcendental on
-- angles.
local function requiredTangents(eye: Vector3): (number, number)
	local view = CFrame.lookAt(eye, ORIGIN)
	local maxHorizontal = 0
	local maxVertical = 0
	for _, corner in ipairs(PIT_CORNERS) do
		local point = Vector3.new(ORIGIN.X + corner.X, FLOOR_TOP + corner.Y, ORIGIN.Z + corner.Z)
		local viewPoint = view:PointToObjectSpace(point)
		-- The camera looks down its own -Z, so depth is the negated Z. A corner
		-- at or behind the eye has no meaningful angle and is skipped; at this
		-- framing none ever is.
		local depth = -viewPoint.Z
		if depth > 0.01 then
			local horizontal = math.abs(viewPoint.X) / depth
			local vertical = math.abs(viewPoint.Y) / depth
			if horizontal > maxHorizontal then
				maxHorizontal = horizontal
			end
			if vertical > maxVertical then
				maxVertical = vertical
			end
		end
	end
	return maxHorizontal, maxVertical
end

-- Solve the camera placement for one viewport shape.
--
-- `CAMERA_FOV` is the FLOOR of the answer, never the ceiling: the view never
-- zooms in past the baseline framing on a wide monitor, and widens only as much
-- as the pit's own silhouette demands. Note that the demand is nonzero even on
-- 16:9 -- the baseline 60 covers the floor plane but clips the top corners of
-- the near wall, which are the widest points of the pit from this angle -- so a
-- desktop settles a few degrees above the baseline and a narrow phone settles
-- far above it and further back.
--
-- Returns the eye offset from ORIGIN, and the vertical field of view in degrees.
local function solveFraming(aspect: number): (Vector3, number)
	local offset = CAMERA_OFFSET
	local fov = CAMERA_FOV
	for _ = 1, FRAMING_PASSES do
		local maxHorizontal, maxVertical = requiredTangents(ORIGIN + offset)
		-- Horizontal coverage is vertical coverage times the aspect ratio, so a
		-- horizontal requirement converts into the vertical field of view that
		-- would deliver it by dividing through.
		local needed = math.max(maxVertical, maxHorizontal / aspect) * FRAMING_MARGIN
		local neededFov = math.deg(math.atan(needed)) * 2
		if neededFov <= CAMERA_FOV_MAX then
			fov = math.clamp(neededFov, CAMERA_FOV, CAMERA_FOV_MAX)
			break
		end
		-- Too wide to solve with angle alone: back off along the same viewing
		-- axis by the shortfall and re-solve. Retreating shrinks every angle, so
		-- the sequence is monotone and terminates.
		fov = CAMERA_FOV_MAX
		local affordable = math.tan(math.rad(CAMERA_FOV_MAX * 0.5))
		offset = offset * math.max(needed / affordable, 1)
	end
	return offset, fov
end

-- Re-applied rather than set once. Roblox hands the camera back to the default
-- Custom controller whenever the character respawns, which would silently drop
-- the player out of the arena view mid-session; re-applying on the signals that
-- cause it is cheaper and steadier than policing the camera every frame (NFR-1:
-- no per-frame work that a signal can do instead).
--
-- ViewportSize is one of those signals. A rotated phone, a resized window and a
-- Studio emulator switch all change the aspect ratio without touching
-- CurrentCamera, and a framing solved for the old shape crops the pit in the new
-- one -- so the solve is re-run on resize, not only on camera change.
local applyCamera: () -> ()

local trackedCamera: Camera? = nil
local viewportConnection: RBXScriptConnection? = nil

applyCamera = function(): ()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	if camera ~= trackedCamera then
		local previous = viewportConnection
		if previous ~= nil then
			previous:Disconnect()
		end
		trackedCamera = camera
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyCamera)
	end

	local viewport = camera.ViewportSize
	local aspect = 1
	if viewport.X > 0 and viewport.Y > 0 then
		aspect = math.clamp(viewport.X / viewport.Y, ASPECT_MIN, ASPECT_MAX)
	end

	local offset, fov = solveFraming(aspect)

	camera.CameraType = Enum.CameraType.Scriptable
	-- Stated explicitly rather than left to the default, because every angle
	-- computed above is a VERTICAL one and a changed default would silently
	-- invalidate the whole solve.
	camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(ORIGIN + offset, ORIGIN)
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function ArenaView.isReady(): boolean
	return built
end

function ArenaView.getContainer(): Folder
	local folder = container
	if folder == nil then
		error("[ArenaView] getContainer before init", 2)
	end
	return folder
end

function ArenaView.getCenter(): Vector3
	return Vector3.new(ORIGIN.X, FLOOR_TOP, ORIGIN.Z)
end

function ArenaView.getCamera(): Camera?
	return Workspace.CurrentCamera
end

-- FR-1.4, the containment guarantee.
--
-- CONTRACT
--   `radius` is the TRUE MAXIMUM EXTENT of the thing being placed, measured from
--   its centre to the furthest point of its geometry in ANY direction and in the
--   orientation it will actually be shown in -- not a nominal half-size. A cube
--   tumbled to a corner-down pose reaches its half-diagonal, not its half-width,
--   and a caller that passes the half-width has told the arena the die is
--   smaller than it is. Containment is then exact for the size it was given and
--   wrong for the die on screen; the arena cannot detect the difference.
--   A negative or non-finite `radius` is treated as zero.
--
-- GUARANTEES, for finite `position` and any `radius`:
--   * Never errors, for any input, at any pit or die size.
--   * The returned X and Z lie within `INNER_HALF - radius` of the pit centre;
--     if the die is wider than the pit, they degrade to the centre exactly.
--   * The returned Y is at least `FLOOR_TOP + radius + REST_EPSILON` and at most
--     `FLOOR_TOP + WALL_HEIGHT - radius`; if the die is taller than the pit is
--     deep that range inverts, and Y degrades to the pit's mid-height -- the
--     same "dead centre" answer the horizontal axes give, and never a position
--     above the rim.
--
-- Every degradation is deliberate. A die that cannot fit is a display problem;
-- an error thrown mid-roll would be a bigger one, and `math.clamp` RAISES on an
-- inverted range rather than doing something sensible, so each of the three
-- ranges is proven non-inverted before it is used.
function ArenaView.clampToArena(position: Vector3, radius: number): Vector3
	local extent = safeRadius(radius)

	local limit = INNER_HALF - extent
	if limit < 0 then
		limit = 0
	end
	local x = ORIGIN.X + math.clamp(position.X - ORIGIN.X, -limit, limit)
	local z = ORIGIN.Z + math.clamp(position.Z - ORIGIN.Z, -limit, limit)

	local yMin = FLOOR_TOP + extent + REST_EPSILON
	local yMax = FLOOR_TOP + WALL_HEIGHT - extent
	local y: number
	if yMin > yMax then
		y = FLOOR_TOP + WALL_HEIGHT / 2
	else
		y = math.clamp(position.Y, yMin, yMax)
	end

	return Vector3.new(x, y, z)
end

-- The resting CFrame for slot `index` of `count`. Rotation is identity: the
-- renderer supplies the orientation, because orientation is where the server's
-- chosen face is expressed and the arena must have no opinion on it.
--
-- CONTRACT
--   `radius` carries the same meaning and the same demand as in `clampToArena`:
--   the die's TRUE MAXIMUM EXTENT in its displayed orientation. The resting
--   centre is placed `radius + REST_EPSILON` above the floor, so an honest
--   extent leaves the die visibly clear of the slab and an understated one puts
--   it through the slab by exactly the amount understated.
--
-- GUARANTEES:
--   * Never errors. Any `index` or `count` -- fractional, negative, out of
--     range, infinite or NaN -- resolves to the centre slot rather than
--     throwing. A die count the arena has no layout for is a display problem; a
--     thrown error mid-roll would be a bigger one, and the payout is already
--     credited either way.
--   * The returned position satisfies `clampToArena`'s guarantees for the same
--     `radius`.
function ArenaView.getAnchor(index: number, count: number, radius: number): CFrame
	local extent = safeRadius(radius)

	local offset = Vector3.zero
	if isFinite(index) and isFinite(count) then
		local slots = LAYOUTS[math.clamp(math.floor(count), 1, MAX_DICE)]
		if slots ~= nil then
			offset = slots[math.floor(index)] or Vector3.zero
		end
	end

	local resting = Vector3.new(
		ORIGIN.X + offset.X,
		FLOOR_TOP + extent + REST_EPSILON,
		ORIGIN.Z + offset.Z
	)
	return CFrame.new(ArenaView.clampToArena(resting, extent))
end

-- Where a die begins its tumble: directly above its own slot, above the rim.
-- Deliberately NOT clamped in Y -- the start point is outside the pit on
-- purpose, and FR-1.4 constrains where a die comes to REST.
function ArenaView.getSpawnPoint(index: number, count: number): Vector3
	local anchor = ArenaView.getAnchor(index, count, 0)
	local p = anchor.Position
	return Vector3.new(p.X, FLOOR_TOP + SPAWN_HEIGHT, p.Z)
end

function ArenaView.init(_net: any): ()
	if built then
		return
	end

	container = build()
	built = true

	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		restoreFov = camera.FieldOfView
		restoreFovMode = camera.FieldOfViewMode
	end

	-- Solves the framing and, as its first act on a new camera, subscribes to
	-- that camera's ViewportSize.
	applyCamera()

	table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyCamera))

	local player = Players.LocalPlayer
	if player ~= nil then
		table.insert(connections, player.CharacterAdded:Connect(applyCamera))
	end
end

-- Symmetry with HUD.shutdown. Without it the arena is a permanent fixture of the
-- Workspace with two live signal subscriptions behind it: re-initialising after
-- a teardown would leave the old folder lit and the old handlers fighting the
-- new ones for the camera. Returns the module to its pre-init state exactly, so
-- `init` after `shutdown` rebuilds cleanly.
function ArenaView.shutdown(): ()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}

	local viewport = viewportConnection
	if viewport ~= nil then
		viewport:Disconnect()
	end
	viewportConnection = nil
	trackedCamera = nil

	local folder = container
	if folder ~= nil then
		folder:Destroy()
	end
	container = nil
	built = false

	-- The camera is handed back to Roblox's default controller rather than left
	-- Scriptable and pointed at an arena that no longer exists.
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
		local mode = restoreFovMode
		if mode ~= nil then
			camera.FieldOfViewMode = mode
		end
		local fov = restoreFov
		if fov ~= nil then
			camera.FieldOfView = fov
		end
	end
	restoreFov = nil
	restoreFovMode = nil
end

return ArenaView
