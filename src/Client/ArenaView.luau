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

-- Camera. Framed so the full 26x26 interior is visible with margin at the
-- default field of view, tilted a few degrees off vertical: dead-vertical reads
-- as a flat texture rather than as a pit with walls, and the tilt is small
-- enough that the view is still the top-down one FR-1.1 asks for.
local CAMERA_OFFSET = Vector3.new(0, 27, 7)
local CAMERA_FOV = 60

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
-- Construction
--------------------------------------------------------------------------------

local container: Folder? = nil
local built = false

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
	light.Color = UITheme.Colors.TextPrimary
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

-- Re-applied rather than set once. Roblox hands the camera back to the default
-- Custom controller whenever the character respawns, which would silently drop
-- the player out of the arena view mid-session; re-applying on the two signals
-- that cause it is cheaper and steadier than policing the camera every frame
-- (NFR-1: no per-frame work that a signal can do instead).
local function applyCamera(): ()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CAMERA_FOV
	camera.CFrame = CFrame.lookAt(ORIGIN + CAMERA_OFFSET, ORIGIN)
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

-- FR-1.4, the containment guarantee. `radius` is the half-extent of the thing
-- being placed, so a die of any size is contained by its OWN size rather than
-- by an assumption about how big dice are.
--
-- Returns a position that is inside the pit on all three axes. If the pit were
-- ever made smaller than the die, `limit` would go negative and clamp would
-- error on an inverted range -- hence the floor at zero, which degrades to
-- "dead centre" instead of throwing during a roll.
function ArenaView.clampToArena(position: Vector3, radius: number): Vector3
	local limit = INNER_HALF - radius
	if limit < 0 then
		limit = 0
	end
	local x = ORIGIN.X + math.clamp(position.X - ORIGIN.X, -limit, limit)
	local z = ORIGIN.Z + math.clamp(position.Z - ORIGIN.Z, -limit, limit)
	local y = math.clamp(position.Y, FLOOR_TOP + radius, FLOOR_TOP + WALL_HEIGHT - radius)
	return Vector3.new(x, y, z)
end

-- The resting CFrame for slot `index` of `count`. Rotation is identity: the
-- renderer supplies the orientation, because orientation is where the server's
-- chosen face is expressed and the arena must have no opinion on it.
--
-- Out-of-range inputs resolve to the centre rather than erroring. A die count
-- the arena has no layout for is a display problem; a thrown error mid-roll
-- would be a bigger one, and the payout is already credited either way.
function ArenaView.getAnchor(index: number, count: number, radius: number): CFrame
	local clampedCount = math.clamp(math.floor(count), 1, MAX_DICE)
	local slots = LAYOUTS[clampedCount]
	local offset = slots[index] or Vector3.zero
	local resting = Vector3.new(
		ORIGIN.X + offset.X,
		FLOOR_TOP + radius,
		ORIGIN.Z + offset.Z
	)
	return CFrame.new(ArenaView.clampToArena(resting, radius))
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

	applyCamera()

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyCamera)

	local player = Players.LocalPlayer
	if player ~= nil then
		player.CharacterAdded:Connect(applyCamera)
	end
end

return ArenaView
