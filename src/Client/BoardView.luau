--!strict
-- BoardView.luau
-- The board: a felt tray drawn in screen space holding ONE shared 3D scene, and
-- the world geometry every die is thrown into (SRS FR-1.1, FR-1.4; HLD §4.3).
--
-- WHY THIS REPLACED THE 3D PIT. The operator asked for a 2D board after seeing
-- the pit render: a deep well viewed from 27 studs up, with the floor eating the
-- frame and the die reading as a speck. The tray is the answer to that, and the
-- change is confined to the view layer -- no server module, no shared module,
-- and no gameplay rule contains a single line of 3D. The server samples an
-- outcome from a mass distribution and sends a number; how that number is shown
-- was always this layer's business alone.
--
-- WHY THE GEOMETRY IS NOW 3D AGAIN, AND WHY THAT IS NOT A REVERSAL.
--
-- The tray is still a flat ScreenGui rectangle. What changed is what lives
-- INSIDE it. Every die used to occupy its own `ViewportFrame` -- its own camera,
-- its own 3D scene -- pinned to a slot looked up from a precomputed table. Three
-- consequences followed directly from that, and all three were operator
-- complaints:
--
--   * IT FELT BOXED IN, because each die genuinely was in a box.
--   * DICE COULD NOT SCATTER. Positions came from `LAYOUTS[count][index]`, so
--     the same board produced the same arrangement every single throw.
--   * THERE WAS NO FLOOR. Separate scenes cannot share one, so bounces had to be
--     faked per-die against an imaginary plane, and dice could never intermingle
--     because they were never in the same space to begin with.
--
-- So the seven viewports collapsed into ONE covering the whole interior, with a
-- single camera and a real felt plane. Dice are placed in STUDS on that plane
-- and animated in 3D. Scatter, intermingling, a shared floor and genuine damped
-- bounces all stop being effects to fake and become consequences of the dice
-- actually being in the same place.
--
-- The pit's failure was the CAMERA, not the third dimension: it looked down a
-- well from far away. This looks at a table from close and slightly above, which
-- is how a person sees dice they have just thrown.
--
-- WHAT THE MOVE TO A FLAT PRESENTATION COST, kept here because it is still true.
-- The inverted-mass mechanic (FR-2) is the heart of the game: mass poured onto a
-- face makes that face land LESS often. That read is best served by watching a
-- lopsided solid tumble, which is exactly what a shared 3D scene restores -- so
-- this rebuild buys back most of what the flat board gave up. What remains
-- unrecoverable is nothing: dice tumble, they fight the settle, and their weight
-- bars are legible. The compromise is retired rather than merely documented.
--
-- THE COORDINATE CONTRACT CHANGED, DELIBERATELY AND VISIBLY. `getAnchor`,
-- `getSpawnPoint` and `clampToBoard` now speak in `Vector3` STUDS on the felt
-- rather than `UDim2` screen scale. The names and the meanings survive; only the
-- space moved. Containment (FR-1.4) is still enforced HERE and `clampToBoard` is
-- still the only way to obtain a legal rest point -- the renderer cannot place a
-- die outside the tray even by mistake, which is the whole reason the guarantee
-- lives in this file rather than in the caller.
--
-- `getRect` and `getCenter` are UNCHANGED and still screen-space. FeedbackFX
-- anchors floating payout text with them and has no business knowing that the
-- board's interior became three-dimensional.
--
-- NO DIE-COUNT CEILING. The old layout table had exactly seven entries, so seven
-- was baked into the geometry itself. Scatter is sampled, not looked up, so this
-- module has no opinion on how many dice arrive. `MAX_DICE` remains only as the
-- current gameplay limit for `getDieRadius`'s size curve, and passing more than
-- that yields the smallest size rather than an error. The operator's 20-dice
-- progression ceiling therefore needs no change here.
--
-- EVERY COLOUR COMES FROM UITheme, for the reason UITheme's own header gives.
--
-- This module holds no economic state and sends nothing to the server. It does
-- not require NetClient at all; `init` accepts it because ClientBootstrap calls
-- every view module the same way, and a uniform signature is worth more than
-- saving one unused parameter.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local UITheme = require(script.Parent:WaitForChild("UITheme"))

local BoardView = {}

--------------------------------------------------------------------------------
-- The tray, in absolute screen scale.
--
-- EVERY NUMBER HERE IS A FRACTION OF THE SCREEN, never a pixel (FR-13.7, NFR-3).
--------------------------------------------------------------------------------

-- Centred BETWEEN THE SIDEBARS, not on the screen. MenuPanel occupies roughly
-- the outer 14% of each edge; centring on the screen leaves the board looking
-- shoved left, because the eye centres it against the gap it sits in rather
-- than against the window.
--
-- WIDER THAN IT IS TALL, on purpose. Dice thrown onto a table want horizontal
-- room; a square tray either shrinks every die or stacks them into rows that
-- read as a grid rather than a throw.
local TRAY_X = 0.165
local TRAY_Y = 0.135
local TRAY_W = 0.670
local TRAY_H = 0.660

--------------------------------------------------------------------------------
-- The felt, in world studs.
--
-- The scene is centred on the origin with +Y up. The camera looks at the origin
-- from in front and above, so +X is right on screen and +Z is toward the viewer.
--
-- THESE ARE THE ONLY NUMBERS THAT DEFINE THE PLAYABLE AREA. The half-extents
-- below are what FR-1.4 containment is measured against, and the camera solve
-- frames exactly this rectangle -- so widening the felt widens what is on screen
-- rather than pushing dice out of shot.
--------------------------------------------------------------------------------

-- Half-extents of the felt rectangle.
--
-- THE DEPTH IS SET BY HOW THE FELT PROJECTS, NOT BY HOW IT MEASURES. Viewed from
-- a pitched camera the felt's depth compresses on screen by the cosine of the
-- pitch while its width does not, so a felt that looks correctly proportioned in
-- world space renders as a letterbox with dead space above and below. At a 45
-- degree pitch the depth is foreshortened to about 0.71 of itself, and the tray
-- is roughly 1.75 times wider than it is tall, so the depth that FILLS the tray
-- is `halfX / (1.75 * cos(pitch))` -- about 10.5, not the 8.0 first tried, which
-- rendered the felt as a small trapezoid adrift in a mostly empty board.
local FELT_HALF_X = 13.0
local FELT_HALF_Z = 10.5

-- The felt surface sits at Y = 0, and a die RESTS with its centre one radius
-- above it -- a solid normalised to a bounding sphere touches the floor at its
-- own radius, not at its centre. Stated once here because both the rest solve
-- and the bounce solve need it and must not disagree.
local FLOOR_Y = 0.0

-- How far above the felt a die is released.
--
-- MEASURED AGAINST THE FRUSTUM, NOT PICKED, and lowered twice.
--
-- The first value was 26, which put the release point BEHIND the camera
-- entirely -- the camera sits about 18 studs up and looks down, so anything
-- higher than it and not far away is behind the view plane. The second was 10,
-- which cleared that but still spent much of the throw above the top edge: a
-- screenshot taken mid-roll showed an EMPTY felt with every die out of shot.
--
-- The visible band above the felt is only about five studs at the far edge,
-- because a pitched camera puts the far edge high in frame already. So the
-- release sits at 5.5 and the arc peaks a stud or two over that, which keeps the
-- whole throw in view apart from a brief moment at the very start -- and a die
-- entering from just off the top edge is exactly what being thrown in looks
-- like.
local THROW_HEIGHT = 4.0

-- How far beyond the felt's FAR edge a throw begins.
--
-- FROM THE FAR SIDE, TOWARD THE VIEWER. The near side is the bottom of the frame
-- and sits close to the camera, so a die released there would be enormous and
-- would travel away from the viewer, shrinking. Coming from the far edge, dice
-- enter high in frame and grow as they approach -- and the far edge is where
-- "off screen" actually is for a camera pitched down at a table.
-- Kept small for the same reason FRICTION was lowered: the further back the
-- throw starts, the further back the first contact must be for the bounces to
-- land the die on its mark, and past the felt's far edge that becomes
-- unsatisfiable.
local THROW_BACK_Z = 0.5

-- Lateral spread of the release points. Dice do not leave the hand from one
-- pixel; a little scatter at the source makes the incoming arcs non-parallel,
-- which is most of what makes a throw look thrown.
local THROW_SPREAD_X = 9.0

-- Clearance held between a resting die's bounding sphere and the felt edge, in
-- studs. The 3D analogue of the old REST_EPSILON: an extent alone puts the die
-- EXACTLY on the boundary, where any float error shows as a die overhanging the
-- frame.
local REST_EPSILON = 0.25

-- Die size, as a bounding-sphere RADIUS in studs, interpolated by die count.
--
-- A SOLO DIE IS THE WHOLE GAME AND SHOULD LOOK LIKE IT. The flat board's first
-- attempt rendered one die as a stamp adrift in a large empty tray -- the same
-- "die is a speck" complaint that ended the 3D pit, reproduced flat. One die is
-- therefore large enough to read as the subject of the shot.
--
-- The floor exists because the curve must not collapse to nothing past the
-- current cap: the operator's progression ceiling is 20 dice and this module
-- must not be what stops them arriving.
local DIE_RADIUS_SOLO = 4.00
local DIE_RADIUS_FULL = 2.00
local DIE_RADIUS_MIN = 0.85

-- The count at which the size curve reaches DIE_RADIUS_FULL. Matches the current
-- gameplay cap (SRS FR-1.1), but is NOT a limit: beyond it the curve keeps
-- shrinking toward DIE_RADIUS_MIN so a larger board still fits.
local MAX_DICE = 7

-- Scatter separation, as a multiple of die radius. Dice may lie close enough to
-- touch and to read as a cluster; they may not occupy the same point.
local MIN_SEPARATION_FACTOR = 1.85

-- How hard the sampler tries to honour that separation before accepting the
-- best-effort placement. A crowded board can be genuinely unsatisfiable, and a
-- throw is not the moment to loop forever.
local SCATTER_ATTEMPTS = 24

--------------------------------------------------------------------------------
-- The camera.
--
-- Looks at the felt from in front and above. The angle is the single most
-- important number in this file: too shallow and the dice hide behind each
-- other, too steep and it becomes the top-down grid the old board already was.
-- Around 52 degrees shows the top face clearly -- which is the answer the player
-- is reading -- while keeping enough obliquity that the solids read as solid.
--------------------------------------------------------------------------------

local CAMERA_PITCH = math.rad(45)
local CAMERA_FOV = 42

-- Fraction of the frame the felt fills. Below 1.0 so a die mid-tumble at the
-- felt's edge, and the apex of a bounce, both stay inside the viewport -- Roblox
-- clips ViewportFrame geometry hard at the frame bounds, and a clipped die reads
-- as broken geometry rather than as a framing problem (L-044).
local CAMERA_FILL = 0.90

-- Extra vertical world-space room above the felt, in studs, reserved so a
-- bouncing die is not cropped at the top edge. The first bounce peaks around
-- four studs up, but a die is only near the top of frame when it is also near
-- the FAR edge, where the projection has already lifted it -- so the reserve
-- needed is much smaller than the bounce height itself.
-- 2.5, SOLVED RATHER THAN GUESSED. The binding case is a die at the apex of its
-- throw while still near the FAR edge, where the projection has already lifted
-- it high in frame. Measured at 1.5 that die reached 1.10 in normalised screen
-- coordinates -- 10% past the top edge -- and 14% of the frames in a sampled
-- roll had at least one die clipped. Working backwards from "apex must project
-- inside the frame at the far edge" gave 2.5, which brought the peak to 1.03 --
-- still grazing. 3.0 clears it outright.
--
-- Note the measurement is taken at the die's PIVOT, so its top surface crosses
-- the edge before its centre does; leaving the peak at exactly 1.0 would still
-- shave the top off a die. The margin is deliberate.
local CAMERA_HEADROOM = 3.0

--------------------------------------------------------------------------------
-- Numeric hygiene
--------------------------------------------------------------------------------

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- A negative, NaN or infinite radius is treated as zero rather than propagated.
-- Same contract the pit and the flat board both had: a die that cannot be
-- measured is a display problem, and an error thrown mid-roll would be a bigger
-- one -- the payout is already credited by then either way.
local function safeRadius(radius: number): number
	if not isFinite(radius) or radius < 0 then
		return 0
	end
	return radius
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local built = false
local screenGui: ScreenGui? = nil
local viewport: ViewportFrame? = nil
local sceneRoot: Folder? = nil
local connections: { RBXScriptConnection } = {}
local rng = Random.new()

-- What the backdrop displaced, so `shutdown` can put it back exactly. The board
-- is a guest in someone else's DataModel and must leave no trace.
local restoreCameraType: Enum.CameraType? = nil
local restoreCharacterVisible: { [BasePart]: number } = {}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- The felt surface itself, as a real part in the shared scene.
--
-- A REAL PART RATHER THAN A DRAWN RECTANGLE, because the dice are now 3D objects
-- in this space and need something to be visibly ON. A flat frame behind a
-- ViewportFrame would sit at a fixed screen depth and the dice would slide
-- across it without contact; a part in the scene shares their perspective, so a
-- die near the far edge is genuinely further away and reads that way.
local function buildFelt(parent: Instance): ()
	local felt = Instance.new("Part")
	felt.Name = "Felt"
	felt.Anchored = true
	felt.CanCollide = false
	felt.CanQuery = false
	felt.CanTouch = false
	felt.CastShadow = false
	felt.Material = Enum.Material.SmoothPlastic
	felt.Color = UITheme.Colors.Felt
	felt.Size = Vector3.new(FELT_HALF_X * 2, 0.4, FELT_HALF_Z * 2)
	-- Top surface flush with FLOOR_Y, so a die resting at `radius` above the
	-- floor is resting on the felt and not floating over it.
	felt.CFrame = CFrame.new(0, FLOOR_Y - 0.2, 0)
	felt.Parent = parent
end

-- THE FRAMING SOLVE.
--
-- Places the camera at the distance that makes the felt fill the frame, derived
-- from the felt's own size, the camera's own field of view and the frame's
-- measured aspect ratio -- never hand-tuned. A hand-tuned distance silently
-- stops agreeing the moment any of the three changes, which is precisely how the
-- previous renderer ended up drawing dice as specks.
--
-- THE MISTAKE THIS REPLACES, because it is an easy one to make again. The first
-- version fitted the felt's 3D bounding RADIUS to the camera's vertical
-- half-angle. That is wrong twice over: the felt's DEPTH is foreshortened on
-- screen by the cosine of the pitch, so its projected height is much less than
-- its radius; and the frame is far wider than it is tall, so the horizontal
-- limit is a different distance entirely. Fitting the radius vertically solved
-- for a requirement nothing had, and put the camera roughly twice as far away as
-- it belonged -- the felt rendered at about a third of the tray.
--
-- So both axes are solved separately, in the space they are actually measured
-- in, and the binding one wins.
local function solveCamera(vp: ViewportFrame, cam: Camera): ()
	local size = vp.AbsoluteSize
	-- Before the first layout pass `AbsoluteSize` is (0,0). A fallback keeps the
	-- camera somewhere sane for the frames before the resize signal corrects it,
	-- rather than dividing by zero into a NaN CFrame -- which does not error, it
	-- just renders nothing.
	local aspect = if size.X > 0 and size.Y > 0 then size.X / size.Y else 1.75

	local tanHalf = math.tan(math.rad(CAMERA_FOV) * 0.5)
	if tanHalf <= 1e-6 then
		return
	end

	-- The felt's half-extents AS PROJECTED. Width is unaffected by the pitch;
	-- depth compresses by its cosine.
	local halfWidth = FELT_HALF_X
	local halfHeight = FELT_HALF_Z * math.cos(CAMERA_PITCH) + CAMERA_HEADROOM

	-- The distance each axis needs on its own. Roblox's field of view is
	-- VERTICAL, so the horizontal half-angle carries the aspect ratio.
	local forHeight = halfHeight / tanHalf
	local forWidth = halfWidth / (tanHalf * aspect)

	local distance = math.max(forHeight, forWidth) / math.max(CAMERA_FILL, 0.05)

	local eye = Vector3.new(
		0,
		math.sin(CAMERA_PITCH) * distance,
		math.cos(CAMERA_PITCH) * distance
	)
	cam.CFrame = CFrame.lookAt(eye, Vector3.new(0, 0, 0))
end

-- THE MASS LEGEND -- what the bar under each die means.
--
-- WHY THIS EXISTS. Every resting die carries a small bar showing how much of the
-- die's mass sits on the face that is showing (FR-1.3). The operator, who
-- commissioned the mechanic, asked "what is that bar below the dice what does it
-- mean" -- which settles the question of whether it was discoverable. It was
-- rendering the game's CENTRAL rule and reading as decoration.
--
-- The rule it is trying to convey is counter-intuitive on purpose (FR-2): mass
-- makes a face land LESS often. Nobody derives that from an unlabelled bar, and
-- a player who does not know it cannot tell a deliberately-forged die from bad
-- luck -- which is the entire game.
--
-- SWATCHES RATHER THAN PROSE, and real ones: each sample is drawn with the same
-- fill and the same colour `showFace` gives a bar in that state, so the player
-- matches what they see on a die to what they see here. A sentence describing
-- "grey means void" would be a second declaration of the colour rule and would
-- drift from the renderer's (L-025); these cannot, because they are the same
-- three values.
--
-- IN THE TOP-LEFT WEDGE, OUTSIDE THE FELT. This took four attempts and the three
-- failures are worth recording, because each was defeated by a different thing.
--
-- Under the felt is clear in flight but is where dice LAND. Top-left CENTRED
-- vertically is where the throw arc passes. And the bottom-left wedge -- which
-- looked right and which one screenshot appeared to confirm -- is the WRONG
-- wedge: the felt is a perspective trapezoid whose NEAR edge is the wide one, so
-- going downward the felt spreads outward and the wedge closes. Measured, the
-- tray runs x=204..1035 while the felt's near-left corner sits at x=266 and the
-- leftmost resting die at x=302, leaving about 60px. The far-left corner sits at
-- x=405, leaving 201px -- more than three times as much.
--
-- I placed it in the narrow one and called it verified off a single clean frame.
-- The operator said the dice still touched it, and instrumenting the overlap
-- rather than looking again showed 102 of 150 frames intersecting and 8 dice
-- coming to rest on it. THE LESSON IS L-031's: a screenshot proves the frame it
-- was taken in. Geometry this cheap to measure should never be eyeballed.
--
-- The top wedge is also safe in flight, despite being "the top": dice enter
-- across the felt's FAR edge, x=405..834, which is inside the felt and to the
-- right of this. Both phases are excluded by measurement, not by assumption.
--
-- Stacked vertically to fit the wedge, and small print by construction -- fixed
-- 11px, dim -- because it is a key: read once, then ignored, and it must never
-- compete with the dice.
local function buildMassLegend(parent: Instance): ()
	local legend = Instance.new("Frame")
	legend.Name = "MassLegend"
	legend.Size = UDim2.new(0, 150, 0, 62)
	legend.Position = UDim2.fromScale(0.012, 0.045)
	legend.BackgroundTransparency = 1
	legend.ZIndex = 6
	legend.Parent = parent

	-- THE RULE ITSELF, stated once and plainly.
	--
	-- The swatches say what each colour IS; this says why anyone should care.
	-- "Heavier faces land less often" is the inverted-mass mechanic (FR-2) in
	-- five words, and it is the one thing no amount of looking at the board will
	-- teach a player -- a face that rarely appears is indistinguishable from bad
	-- luck unless you already know the die is loaded against it.
	-- Wrapped over two lines: the wedge is tall and narrow, not wide.
	local rule = Instance.new("TextLabel")
	rule.Name = "Rule"
	rule.Size = UDim2.new(1, 0, 0, 24)
	rule.Position = UDim2.fromScale(0, 0)
	rule.BackgroundTransparency = 1
	rule.Font = UITheme.FontHeading
	rule.Text = "MASS \u{2013} heavier faces\nland less often"
	rule.TextSize = 11
	rule.TextScaled = false
	rule.LineHeight = 1.1
	rule.TextColor3 = UITheme.Colors.TextDim
	rule.TextXAlignment = Enum.TextXAlignment.Left
	rule.TextYAlignment = Enum.TextYAlignment.Top
	rule.ZIndex = 6
	rule.Parent = legend

	local swatches = Instance.new("Frame")
	swatches.Name = "Swatches"
	swatches.Size = UDim2.new(1, 0, 0, 36)
	swatches.Position = UDim2.new(0, 0, 0, 27)
	swatches.BackgroundTransparency = 1
	swatches.ZIndex = 6
	swatches.Parent = legend

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Vertical
	row.HorizontalAlignment = Enum.HorizontalAlignment.Left
	row.Padding = UDim.new(0, 1)
	-- SORTED BY LayoutOrder, EXPLICITLY. `UIListLayout` defaults to sorting by
	-- NAME, so the swatches came out FAIR, HEAVY, VOID -- alphabetical -- and the
	-- key read as though it ran lightest-to-heaviest while doing nothing of the
	-- sort. A legend in a misleading order is worse than none, because the reader
	-- infers a scale from the sequence.
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = swatches

	-- FILL AND COLOUR MUST MATCH `DiceRenderer.showFace`. These three are the
	-- same values that function paints, which is what lets a player match a bar
	-- on a die to a row here.
	local states = {
		{ id = "VOID", label = "never lands", fill = 0.0, colour = UITheme.Colors.VoidFace },
		{ id = "FAIR", label = "even odds", fill = 0.45, colour = UITheme.Colors.TextDim },
		{ id = "HEAVY", label = "rare, pays big", fill = 1.0, colour = UITheme.Colors.TextGold },
	}

	for index, state in ipairs(states) do
		-- CELLS ARE PIXEL-WIDTH, NOT A FRACTION OF THE TRAY.
		--
		-- At 0.31 scale each the captions ran past their cell and "HEAVY · rare,
		-- pays big" overprinted the swatch beside it. The captions are fixed 10px
		-- text -- they do not scale -- so sizing their container as a fraction of a
		-- variable-width tray was always going to collide at some window size. A
		-- fixed cell wide enough for the longest caption cannot.
		local cell = Instance.new("Frame")
		cell.Name = "Swatch_" .. state.id
		cell.Size = UDim2.new(1, 0, 0, 11)
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = index
		cell.ZIndex = 6
		cell.Parent = swatches

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Size = UDim2.new(0, 24, 0, 4)
		track.Position = UDim2.new(0, 0, 0.5, -2)
		track.BackgroundColor3 = UITheme.Colors.PanelDeep
		track.BorderSizePixel = 0
		track.ZIndex = 6
		track.Parent = cell

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track

		-- A void face's real bar is EMPTY, so a faithful swatch would be a blank
		-- track and read as "no bar" rather than as the void STATE. It is drawn
		-- as a sliver in the void colour instead -- the one place this key departs
		-- from the renderer, because a swatch showing nothing teaches nothing.
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(math.max(state.fill, 0.18), 1)
		fill.BackgroundColor3 = state.colour
		fill.BorderSizePixel = 0
		fill.ZIndex = 7
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.Size = UDim2.new(1, -30, 1, 0)
		caption.Position = UDim2.new(0, 30, 0, 0)
		caption.BackgroundTransparency = 1
		caption.Font = UITheme.Font
		caption.Text = state.id .. " \u{00B7} " .. state.label
		caption.TextSize = 10
		caption.TextScaled = false
		caption.TextColor3 = UITheme.Colors.TextDim
		caption.TextXAlignment = Enum.TextXAlignment.Left
		caption.TextYAlignment = Enum.TextYAlignment.Center
		caption.ZIndex = 6
		caption.Parent = cell
	end
end

-- The tray, the shared viewport, and the scene inside it.
local function build(): (ScreenGui, Frame, ViewportFrame, Folder)
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DiceForgeBoard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = UITheme.Layer.Arena

	local frame = UITheme.panel(
		UDim2.fromScale(TRAY_W, TRAY_H),
		UDim2.fromScale(TRAY_X, TRAY_Y)
	)
	frame.Name = "Tray"
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	local interior = Instance.new("Frame")
	interior.Name = "Interior"
	interior.Size = UDim2.fromScale(1, 1)
	interior.Position = UDim2.fromScale(0, 0)
	interior.BackgroundTransparency = 1
	interior.BorderSizePixel = 0
	interior.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(56, 44, 36)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = interior

	-- THE ONE SHARED SCENE. Every die in the game renders here.
	--
	-- FLAT, SHADOWLESS LIGHTING (operator-directed 2026-08-13). Reported as "some
	-- of its face ahve a dark shade on them like shadow". The cause was lighting,
	-- not geometry: an ambient of RGB 80 with a directional light meant any face
	-- angled away from that one corner received only the dim ambient term and
	-- rendered noticeably darker. On a tumbling die that reads as faces
	-- flickering between shades. Full white ambient with the directional
	-- contribution set to black gives every face identical illumination whichever
	-- way it lands, which is also what keeps a numeral legible at any angle.
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Scene"
	vp.Size = UDim2.fromScale(1, 1)
	vp.Position = UDim2.fromScale(0, 0)
	vp.BackgroundTransparency = 1
	vp.BorderSizePixel = 0
	-- CLIPPED, unlike the old per-die frames. This one covers the whole tray, so
	-- clipping is the containment backstop rather than a thing that cuts dice in
	-- half: FR-1.4 already keeps every resting die inside the felt, and the
	-- camera solve keeps the throw arc inside the frustum. Anything reaching this
	-- boundary is a bug, and cropping it at the tray edge is better than letting
	-- it draw over the HUD.
	vp.ClipsDescendants = true
	vp.Ambient = Color3.fromRGB(255, 255, 255)
	vp.LightColor = Color3.fromRGB(0, 0, 0)
	vp.LightDirection = Vector3.new(0, -1, 0)
	vp.ZIndex = 2
	vp.Parent = interior

	local scene = Instance.new("Folder")
	scene.Name = "Scene"
	scene.Parent = vp

	buildFelt(scene)

	local cam = Instance.new("Camera")
	cam.Name = "SceneCamera"
	cam.FieldOfView = CAMERA_FOV
	cam.Parent = vp
	vp.CurrentCamera = cam

	solveCamera(vp, cam)

	-- RE-SOLVED WHENEVER THE FRAME CHANGES SIZE. The solve depends on the tray's
	-- aspect ratio, which is not known until the GUI has been laid out -- at
	-- construction `AbsoluteSize` is still (0,0) -- and changes again whenever the
	-- window is resized or the device is rotated. A one-shot solve at build time
	-- would therefore be computed from a fallback and then never corrected, which
	-- is a framing bug that only appears on other people's screens (NFR-3).
	table.insert(connections, vp:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		solveCamera(vp, cam)
	end))

	-- The result summary bar, at the bottom edge of the board. Drawn OVER the
	-- viewport rather than inside the scene: it is a readout, not an object on
	-- the table, and a 3D label would tumble with the perspective.
	local resultBar = Instance.new("Frame")
	resultBar.Name = "ResultBar"
	resultBar.Size = UDim2.fromScale(0.96, 0.065)
	resultBar.Position = UDim2.fromScale(0.02, 0.915)
	resultBar.BackgroundColor3 = Color3.fromRGB(24, 19, 16)
	resultBar.ZIndex = 5
	-- HIDDEN UNTIL THERE IS A RESULT TO SHOW. It defaulted to visible, so a
	-- player who had just joined and not yet rolled was shown an empty black
	-- strip across the bottom of their board -- a readout of nothing, which reads
	-- as a UI element that failed to load rather than as one with nothing to say.
	resultBar.Visible = false
	resultBar.Parent = interior

	local rbCorner = Instance.new("UICorner")
	rbCorner.CornerRadius = UDim.new(0.4, 0)
	rbCorner.Parent = resultBar

	local rbStroke = Instance.new("UIStroke")
	rbStroke.Color = Color3.fromRGB(52, 42, 36)
	rbStroke.Thickness = 1
	rbStroke.Parent = resultBar

	local rbLayout = Instance.new("UIListLayout")
	rbLayout.Name = "Layout"
	rbLayout.FillDirection = Enum.FillDirection.Horizontal
	rbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rbLayout.Padding = UDim.new(0.01, 0)
	rbLayout.Parent = resultBar

	-- Built last so it sits above the scene in sibling ZIndex order, and parented
	-- to the interior rather than into the viewport -- it is a key to the board,
	-- not an object on the table.
	buildMassLegend(interior)

	if player ~= nil then
		gui.Parent = player:WaitForChild("PlayerGui")
	end

	return gui, frame, vp, scene
end

-- THE BACKDROP.
--
-- WHY THIS MODULE OWNS IT AT ALL. The 3D pit floated at Y = 500 with a
-- Scriptable camera pointed into it, and that framing was what kept Roblox's
-- default world -- baseplate, skybox, spawn, and the player's own avatar -- out
-- of the shot. Deleting the pit deleted the only thing suppressing them, and the
-- first flat build rendered the board as a floating panel with a Roblox
-- character standing in front of it. The board still needs SOMETHING to be in
-- front of; it just needs a colour rather than geometry.
--
-- NOTE THE SCENE INSIDE THE VIEWPORT IS NOT THE WORLD. A ViewportFrame renders
-- its own children with its own camera and never sees the Workspace, so the
-- dice's 3D scene cannot be intruded upon by the baseplate or the avatar. The
-- backdrop is still needed for everything around the tray.
--
-- A FULL-SCREEN FRAME, NOT A SKYBOX CHANGE OR A LIGHTING EDIT. Both of those are
-- global, shared, and would outlive this module in ways a teardown cannot
-- reliably undo. A Frame at the back of our own ScreenGui is owned entirely by
-- this file and disappears with it.
local function buildBackdrop(gui: ScreenGui): ()
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Position = UDim2.fromScale(0, 0)
	backdrop.BackgroundColor3 = UITheme.Colors.BaseCream
	backdrop.BackgroundTransparency = 0
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 0
	backdrop.Parent = gui
end

-- The camera and the avatar.
--
-- The camera is parked as Scriptable so Roblox's default controller stops
-- swinging it around behind a board that does not move; the avatar is made
-- transparent rather than destroyed, because destroying a character the server
-- owns is not this module's business and would fight respawn.
--
-- THIS IS THE WORKSPACE CAMERA, NOT THE SCENE'S. The viewport has its own,
-- solved in `build`, and the two never interact. The previous renderer's frame
-- step re-parked the Workspace camera on EVERY frame, which was both redundant
-- and a per-frame write to global state from a draw loop; doing it once here is
-- the whole of what was needed.
local function claimView(): ()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		restoreCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.new(0, 10000, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	end

	local player = Players.LocalPlayer
	if player == nil then
		return
	end

	local function hide(character: Model): ()
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") then
				restoreCharacterVisible[d] = d.LocalTransparencyModifier
				d.LocalTransparencyModifier = 1
			end
		end
	end

	local character = player.Character
	if character ~= nil then
		hide(character)
	end
	-- A respawn hands us a fresh character that has never been hidden.
	table.insert(connections, player.CharacterAdded:Connect(function(added: Model)
		-- The previous character's parts are gone; keeping them would grow this
		-- table without bound across a long session and give `shutdown` a pile
		-- of destroyed Instances to walk.
		restoreCharacterVisible = {}
		-- Descendants stream in after the model does.
		task.defer(hide, added)
	end))
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function BoardView.isReady(): boolean
	return built
end

-- The scene dice parent themselves into. Named to match the old `getContainer`
-- in role -- "the thing a die is put inside" -- but it is a Folder in a 3D scene
-- now rather than a Frame, so the name says `Scene` and the type change is
-- visible at every call site rather than silently reinterpreted.
function BoardView.getScene(): Folder
	local scene = sceneRoot
	if scene == nil then
		error("[BoardView] getScene before init", 2)
	end
	return scene
end

-- The viewport the scene renders through. The renderer needs it only to confirm
-- the scene is live; nothing outside this module changes its camera.
function BoardView.getViewport(): ViewportFrame
	local vp = viewport
	if vp == nil then
		error("[BoardView] getViewport before init", 2)
	end
	return vp
end

-- The interior's centre in SCREEN scale. Unchanged, and deliberately still 2D:
-- FeedbackFX anchors floating payout text to the middle of the board and has no
-- business knowing the interior became three-dimensional.
function BoardView.getCenter(): UDim2
	return UDim2.fromScale(0.5, 0.5)
end

-- The tray's rectangle in ABSOLUTE screen scale, so a caller holding an
-- interior-relative point can compose it up into a screen position.
--
-- EXPOSED RATHER THAN LET CALLERS RESTATE IT. FeedbackFX needs to place payout
-- text over the board, which means it needs the tray's rectangle. A second copy
-- of these four numbers in that file is the exact failure L-026 records: the
-- copy nobody executes is the one that drifts, and moving the board would then
-- leave the text behind with nothing to flag it.
function BoardView.getRect(): (number, number, number, number)
	return TRAY_X, TRAY_Y, TRAY_W, TRAY_H
end

-- The felt's half-extents in studs, for a caller that needs to reason about the
-- playable area. Exposed for the same reason `getRect` is.
function BoardView.getFeltExtents(): (number, number)
	return FELT_HALF_X, FELT_HALF_Z
end

-- The height of the felt's surface. A die rests with its LOWEST GEOMETRY on this
-- plane, which is not the same as its centre sitting one bounding-sphere radius
-- above it.
--
-- THIS USED TO RETURN `FLOOR_Y + radius` AND THAT WAS WRONG. A bounding-sphere
-- radius only describes where the centre goes for an actual sphere. The D2 is a
-- flat coin whose sphere radius is its full width but whose half-THICKNESS is a
-- fraction of that, so resting its centre a radius up left it hovering about
-- three studs above the felt -- and because the camera is pitched, a hovering
-- die also projects further out, so a coin well inside the felt in world
-- coordinates was drawn overhanging its edge on screen. Every shape was wrong by
-- a different amount, which is exactly what a single radius cannot express.
--
-- The renderer measures each die's true resting height from its own geometry in
-- the orientation it will actually rest in, and adds it to this.
function BoardView.getFloorY(): number
	return FLOOR_Y
end

-- How big a die should be drawn, as a bounding-sphere RADIUS in studs, for a
-- board holding `count` dice. Interpolated rather than stepped so going from one
-- die to seven scales smoothly instead of snapping.
--
-- BEYOND `MAX_DICE` THE CURVE CONTINUES rather than clamping, down to a floor.
-- The old `getDieScale` clamped its input to 7, which meant an eighth die would
-- have been drawn at the seven-die size and the board would have overflowed. The
-- operator's stated progression ceiling is 20, so shrinking past the current cap
-- is a requirement, not a defensive nicety.
function BoardView.getDieRadius(count: number): number
	local n = count
	if not isFinite(n) then
		n = 1
	end
	n = math.max(1, math.floor(n))

	if n <= MAX_DICE then
		local t = (n - 1) / (MAX_DICE - 1)
		return DIE_RADIUS_SOLO + (DIE_RADIUS_FULL - DIE_RADIUS_SOLO) * t
	end

	-- Past the cap, area-conserving: radius falls as 1/sqrt(count) so twice the
	-- dice take the same total felt. Floored so a very large board still renders
	-- something rather than converging on zero.
	local shrink = math.sqrt(MAX_DICE / n)
	return math.max(DIE_RADIUS_MIN, DIE_RADIUS_FULL * shrink)
end

-- FR-1.4, THE CONTAINMENT GUARANTEE, in three dimensions.
--
-- CONTRACT
--   `position` is a point in WORLD STUDS in the scene. `radius` is the die's
--   TRUE MAXIMUM bounding-sphere radius -- the furthest any part of its geometry
--   reaches from its pivot, in ANY orientation. A sphere is used rather than a
--   box precisely because the die tumbles: a box bound is only correct for one
--   orientation, and the die passes through every other one on the way.
--
-- GUARANTEES, for any `position` and any `radius`:
--   * Never errors, for any input, at any board or die size.
--   * The returned X and Z lie at least `radius + REST_EPSILON` inside the
--     felt's edges on every side.
--   * Y is untouched. Height is the animation's business; containment is about
--     staying ON the table, and a die mid-throw is legitimately above it.
--   * If the die is WIDER than the felt, that range inverts; rather than letting
--     `math.clamp` raise on an inverted range, the axis degrades to the felt's
--     centre exactly -- the same "dead centre" answer the pit and the flat board
--     both gave.
--
-- Every degradation is deliberate, for the reason the pit's version gave: a die
-- that cannot fit is a display problem, and an error thrown mid-roll would be a
-- bigger one -- the payout is already credited by then either way.
function BoardView.clampToBoard(position: Vector3, radius: number): Vector3
	local margin = safeRadius(radius) + REST_EPSILON

	local function axis(value: number, halfExtent: number): number
		if not isFinite(value) then
			return 0
		end
		local limit = halfExtent - margin
		if limit <= 0 then
			return 0
		end
		return math.clamp(value, -limit, limit)
	end

	local y = if isFinite(position.Y) then position.Y else FLOOR_Y

	return Vector3.new(
		axis(position.X, FELT_HALF_X),
		y,
		axis(position.Z, FELT_HALF_Z)
	)
end

-- WHERE A DIE COMES TO REST -- sampled, not looked up.
--
-- THIS IS THE HEART OF THE REBUILD. The old `getAnchor(index, count, extent)`
-- returned a deterministic point from a precomputed table, so the same board
-- produced an identical arrangement on every single throw and no amount of
-- animation polish could make a roll feel unrehearsed. Positions are now
-- SAMPLED uniformly across the felt.
--
-- `taken` carries the rest points already chosen for this same throw, and a
-- candidate is rejected if it lands within `MIN_SEPARATION_FACTOR` radii of one
-- of them. That is what lets dice intermingle -- they may sit close enough to
-- touch, in any arrangement -- while never stacking into the same point.
--
-- BEST-EFFORT, NOT GUARANTEED. A crowded board can be genuinely unsatisfiable,
-- and after `SCATTER_ATTEMPTS` the least-bad candidate is accepted rather than
-- looping. Two dice slightly closer than ideal is a visual imperfection; a
-- frame-time spike during a roll is a defect. Containment is applied to whatever
-- is chosen, so the guarantee that matters is never the thing given up.
--
-- GUARANTEES:
--   * Never errors. Any `count`, any `radius`, any `taken` contents.
--   * The result satisfies `clampToBoard` for the same `radius`.
--   * Y is the FLOOR, not a resting centre height. The caller adds the die's own
--     measured sit height, because only it knows the die's geometry -- see
--     `getFloorY` for why a radius cannot stand in for that.
function BoardView.sampleRestPoint(radius: number, taken: { Vector3 }): Vector3
	local r = safeRadius(radius)
	local minGap = r * 2 * MIN_SEPARATION_FACTOR * 0.5
	local minGapSq = minGap * minGap

	-- Sample within the region a die can legally rest in, so a candidate is
	-- rarely wasted on a point the clamp would pull back to the edge -- which
	-- would pile dice along the borders.
	local spanX = math.max(0, FELT_HALF_X - r - REST_EPSILON)
	local spanZ = math.max(0, FELT_HALF_Z - r - REST_EPSILON)

	local restY = FLOOR_Y

	local best: Vector3? = nil
	local bestClearance = -1

	for _ = 1, SCATTER_ATTEMPTS do
		local candidate = Vector3.new(
			rng:NextNumber(-spanX, spanX),
			restY,
			rng:NextNumber(-spanZ, spanZ)
		)

		-- Distance to the nearest die already placed this throw, squared.
		local nearestSq = math.huge
		for _, other in ipairs(taken) do
			local dx = candidate.X - other.X
			local dz = candidate.Z - other.Z
			local dSq = dx * dx + dz * dz
			if dSq < nearestSq then
				nearestSq = dSq
			end
		end

		if nearestSq >= minGapSq then
			return BoardView.clampToBoard(candidate, r)
		end

		-- Keep the roomiest near-miss, so the fallback is the best of what was
		-- seen rather than simply the last thing tried.
		if nearestSq > bestClearance then
			bestClearance = nearestSq
			best = candidate
		end
	end

	local fallback = best or Vector3.new(0, restY, 0)
	return BoardView.clampToBoard(fallback, r)
end

-- WHERE A THROW BEGINS: above and in front of the felt, spread laterally.
--
-- Deliberately OUTSIDE the felt on both axes -- FR-1.4 constrains where a die
-- comes to REST, not where it starts, and a die that begins inside the tray has
-- not been thrown into it.
--
-- Randomised per die, so the incoming arcs are not parallel. Parallel arcs are
-- the single strongest tell that a throw was animated rather than simulated, and
-- they were unavoidable in the old renderer because every die started directly
-- above its own fixed slot.
function BoardView.sampleThrowPoint(): Vector3
	return Vector3.new(
		rng:NextNumber(-THROW_SPREAD_X, THROW_SPREAD_X),
		THROW_HEIGHT + rng:NextNumber(-1.5, 1.5),
		-(FELT_HALF_Z + THROW_BACK_Z) + rng:NextNumber(-1.5, 1.5)
	)
end

function BoardView.init(_net: any): ()
	if built then
		return
	end

	local gui, _frame, vp, scene = build()
	buildBackdrop(gui)
	screenGui = gui
	viewport = vp
	sceneRoot = scene
	built = true

	claimView()
end

local diceColorsByShape = {
	D2 = Color3.fromRGB(240, 180, 50),
	D3 = Color3.fromRGB(230, 120, 60),
	D4 = Color3.fromRGB(150, 80, 220),
	D6 = Color3.fromRGB(50, 160, 220),
	D8 = Color3.fromRGB(60, 190, 120),
	D10 = Color3.fromRGB(230, 140, 40),
	D12 = Color3.fromRGB(220, 70, 150),
	D20 = Color3.fromRGB(70, 130, 240),
}

function BoardView.updateResultSummary(rollResults: { { shape: string, value: number } }?): ()
	if screenGui == nil then return end
	local trayFrame = screenGui:FindFirstChild("Tray")
	if trayFrame == nil then return end
	local interior = trayFrame:FindFirstChild("Interior")
	if interior == nil then return end
	local resultBar = interior:FindFirstChild("ResultBar")
	if resultBar == nil then return end

	for _, child in ipairs(resultBar:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	if rollResults == nil or #rollResults == 0 then
		resultBar.Visible = false
		return
	end

	resultBar.Visible = true

	-- Group results by shape type
	local grouped: { [string]: { count: number, sum: number } } = {}
	local shapeOrder: { string } = {}

	for _, res in ipairs(rollResults) do
		local s = res.shape or "D6"
		local v = res.value or 0
		if not grouped[s] then
			grouped[s] = { count = 0, sum = 0 }
			table.insert(shapeOrder, s)
		end
		grouped[s].count += 1
		grouped[s].sum += v
	end

	local totalItems = #shapeOrder
	local itemWidth = math.min(0.18, 0.90 / math.max(1, totalItems))

	for _, shapeName in ipairs(shapeOrder) do
		local info = grouped[shapeName]
		local item = Instance.new("Frame")
		item.Name = "Result_" .. shapeName
		item.Size = UDim2.fromScale(itemWidth, 0.76)
		item.BackgroundColor3 = Color3.fromRGB(16, 13, 11)
		item.ZIndex = 6
		item.Parent = resultBar

		local iCorner = Instance.new("UICorner")
		iCorner.CornerRadius = UDim.new(0.3, 0)
		iCorner.Parent = item

		local iStroke = Instance.new("UIStroke")
		iStroke.Color = diceColorsByShape[shapeName] or Color3.fromRGB(200, 200, 200)
		iStroke.Thickness = 1.2
		iStroke.Parent = item

		local displayText = if info.count == 1
			then string.format("%s: %d", shapeName, info.sum)
			else string.format("%dx %s (SUM: %d)", info.count, shapeName, info.sum)

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = UITheme.FontHeading
		lbl.Text = displayText
		lbl.TextColor3 = UITheme.Colors.TextPrimary
		lbl.TextScaled = true
		lbl.ZIndex = 7
		lbl.Parent = item
	end
end

-- Symmetry with every other view module. Without it the board is a permanent
-- fixture of the PlayerGui: re-initialising after a teardown would leave the old
-- tray lit behind the new one. Returns the module to its pre-init state exactly,
-- so `init` after `shutdown` rebuilds cleanly.
--
-- THE BACKDROP IS GLOBAL STATE AND IS PUT BACK. The ScreenGui itself is ours and
-- dies with it -- including the whole 3D scene, which is parented inside it --
-- but `claimView` reached outside this module twice: it made the camera
-- Scriptable and it made the player's avatar invisible. Both belong to the
-- DataModel, not to the board, and a teardown that left either in place would
-- strand the player behind an invisible character with a frozen camera and no
-- board to explain it.
function BoardView.shutdown(): ()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}

	local gui = screenGui
	if gui ~= nil then
		gui:Destroy()
	end
	screenGui = nil
	viewport = nil
	sceneRoot = nil
	built = false

	local camera = Workspace.CurrentCamera
	local cameraType = restoreCameraType
	if camera ~= nil and cameraType ~= nil then
		camera.CameraType = cameraType
	end
	restoreCameraType = nil

	-- Parts are re-checked for existence: a character can despawn between being
	-- hidden and being restored, and writing to a destroyed Instance throws.
	for part, transparency in pairs(restoreCharacterVisible) do
		if part.Parent ~= nil then
			part.LocalTransparencyModifier = transparency
		end
	end
	restoreCharacterVisible = {}
end

return BoardView
