--!strict
-- DiceRenderer.luau
-- Draws the player's dice on the 2D board and animates a roll (SRS FR-1.2,
-- FR-1.3, FR-2.6; HLD §4.3).
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
-- FLAT, BY OPERATOR DECISION. This was a 3D renderer: real solids, real
-- tumbling, a face-normal rotation solve. The operator asked for a 2D board and
-- was told plainly what that costs -- see BoardView's header, which records the
-- trade in full. The short version: mass makes a face land LESS often (FR-2),
-- and in 3D you could WATCH that happen to a lopsided solid. Flat, the same rule
-- is just a number appearing less often, which looks exactly like bad luck.
--
-- SO THIS FILE FIGHTS FOR THE READ, three ways, and they are the reason it is
-- not simply a label that changes text:
--
--   1. THE DIE STILL TUMBLES. It spins through multiple whole turns and settles.
--      A roll remains an EVENT with a duration, not a state change. The spin
--      budget is carried over unchanged from the 3D version, including its
--      payout bonus -- a big win still buys a longer, fuller tumble.
--   2. EVERY FACE CARRIES A WEIGHT BAR. Mass is visible ON THE DIE while it is
--      on the board, not only inside the forge panel. A heavy face is legibly
--      heavy at a glance (FR-1.3).
--   3. THE SETTLE DRAGS AWAY FROM THE HEAVY FACE. As the spin decays the die
--      leans off its heavy side, so it visibly FIGHTS to avoid resting there.
--      This is cosmetic -- it cannot and does not alter the outcome, which
--      arrived from the server already decided -- but it makes the mechanic's
--      DIRECTION observable, which is the whole thing that flatness threatened.
--
-- WHY THE DIE IS A SQUARE REGARDLESS OF SHAPE. A D20 drawn as a flat icosagon is
-- an unreadable smudge at board size, and twenty tiny numerals around a rim are
-- illegible on a phone (NFR-3). Every shape is therefore drawn as one square
-- tile showing ONE numeral -- the face that is up -- with the shape named on it.
-- The face COUNT still comes from the catalog and still governs what can land;
-- only the silhouette is uniform.
--
-- WHY AN UNKNOWN SHAPE IS DRAWN UNNUMBERED. Until StateSync says what this die
-- is, printing a numeral would be asserting a face this module has not been
-- told. An unnumbered tile is honest; a numbered one is a guess that will
-- contradict the credited result.
--
-- EVERY COLOUR COMES FROM UITheme, for the reason UITheme's own header gives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local BoardView = require(script.Parent:WaitForChild("BoardView"))

local DiceRenderer = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_DICE = 7                 -- SRS FR-1.1
local MAX_FACES = 20               -- the D20, the largest shape in DiceCatalog
local DEFAULT_SHAPE = "D6"

-- Face counts by shape id. Mirrors DiceCatalog; the renderer needs only the
-- count, never the mass rules, and requiring the catalog here would pull a
-- server-shaped dependency into the view layer for one integer.
--
-- An id absent from this table is an UNKNOWN shape and is drawn unnumbered
-- rather than guessed at.
local FACE_COUNTS: { [string]: number } = {
	D4 = 4,
	D6 = 6,
	D8 = 8,
	D10 = 10,
	D12 = 12,
	D20 = 20,
}

-- Animation. Carried over from the 3D renderer unchanged, because the timing was
-- tuned against real rolls and flatness does not change how long a throw should
-- feel.
local MIN_DURATION = 0.85
local MAX_DURATION = 2.40

-- Spin budget, in whole turns plus a fraction. The measured 3D tumble ran 6.11
-- turns; this keeps the same band so the flat die does not feel cheaper.
local SPIN_TURNS_MIN = 3
local SPIN_TURNS_MAX = 5
local SPIN_TURNS_PAYOUT_BONUS = 2
local SPIN_FRACTION_MIN = 0.25
local SPIN_FRACTION_MAX = 0.75
local TAU = math.pi * 2

-- The arc a die travels as it is dealt in. Purely vertical would read as a drop;
-- a slight lateral drift reads as a throw.
local DEAL_DRIFT = 0.06

-- How far the die leans off its heavy side during the settle, in radians. Small
-- on purpose: this is a lean, not a wobble, and anything larger reads as the
-- animation glitching rather than as weight.
local HEAVY_LEAN = 0.14

-- Overshoot on the final settle, as a fraction of the die's own size. The die
-- arrives slightly past its slot and eases back, which is what makes it look
-- like it was thrown rather than moved.
local SETTLE_OVERSHOOT = 0.10

-- Mass at or above this fraction of a die's total makes a face read as HEAVY:
-- its weight bar goes full-width and gold. Matched to the 3D renderer's glow
-- threshold so "heavy" means the same thing it meant before.
local GLOW_THRESHOLD = 0.55

-- Face-tile proportions, as fractions of the die tile.
local NUMERAL_H = 0.62
local SHAPE_H = 0.17
local BAR_H = 0.07
local BAR_INSET = 0.10

-- The ViewportFrame camera.
--
-- `DiceMeshBuilder` normalises every die so its furthest corner reaches 3.0
-- studs from centre -- a 6.0 "diameter" in the builder's terms -- precisely so
-- ONE camera distance frames every shape identically. If TARGET_EXTENT changes,
-- these follow it.
--
-- THE DISTANCE IS NOT A CONSTANT. It is solved per model in `applyModel` from
-- that die's own measured radius, because two attempts at a hand-tuned number
-- were both wrong -- the value has to agree with whatever the builder's
-- normalisation actually produced, and only measuring the clone can establish
-- that. A camera three times too far away renders a perfectly good die as a
-- speck of thin edges, which is indistinguishable from broken geometry.
local CAMERA_FOV = 50
-- Fraction of the frame the die should occupy. Below 1.0 leaves breathing room
-- so a tumbling die's corners never clip the viewport edge -- but not much
-- below: the die IS the game, and a solid floating in a large empty tile is the
-- same "die is a speck" complaint that ended the 3D pit and then the first flat
-- board.
--
-- 1.34 was too far the other way -- it cropped the cube's corners and pushed the
-- die under the shape label. The radius being solved against is the worst-case
-- CORNER reach, which a die only presents briefly mid-tumble, so filling just
-- under that frames the resting solid generously while leaving the corners room
-- to swing through.
local CAMERA_FILL = 1.02

-- THE RESTING TILT. A die parked square to the camera shows one face filling the
-- frame and reads as a flat coloured square -- which is exactly what a
-- ViewportFrame was adopted to avoid. Resting it a few degrees off both axes
-- shows three faces at once, so the solid is legible as a solid even when
-- nothing is moving.
--
-- Applied to the CAMERA, not the die, so the face the server chose still points
-- squarely at the viewer and `rotationShowingFace` stays exactly true.
local REST_TILT_X = math.rad(22)
local REST_TILT_Y = math.rad(28)

-- Where the dice models live once generated. The renderer never builds geometry
-- itself -- it clones from here.
local DICE_FOLDER = "dice_faces"

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

type DieVisual = {
	tile: Frame,
	viewport: ViewportFrame,
	-- The 3D solid currently inside the viewport, and the shape it represents.
	-- nil until a known shape arrives, because a die whose shape is unknown must
	-- not be drawn as some other shape.
	model: Model?,
	modelShape: string?,
	numeral: TextLabel,
	shapeTag: TextLabel,
	bar: Frame,
	barFill: Frame,
	stroke: UIStroke,
	shape: string,
	faceCount: number,
	-- false while the authoritative shape for this slot is still unknown. An
	-- unnumbered die is honest; a numbered one would be asserting a face.
	numbered: boolean,
	-- Normalised mass per face, as a fraction of this die's total. Display only.
	weights: { number },
	-- Half-size as a fraction of the interior, INCLUDING the diagonal reach of a
	-- rotated square. BoardView's containment contract demands true maximum
	-- extent in the orientation shown, and a spinning square reaches its
	-- half-diagonal, not its half-width.
	extent: number,
}

type DieSlot = {
	visual: DieVisual,
	inUse: boolean,
	animating: boolean,
	elapsed: number,
	duration: number,
	startPos: UDim2,
	endPos: UDim2,
	spinTotal: number,
	spinDir: number,
	drift: number,
	heavyLean: number,
	faceIndex: number,
	-- The 3D tumble. `spinAxis` is the axis the die turns about on its way to the
	-- answer, and `finalRot` is the orientation that shows the server's face --
	-- the destination the residual spin unwinds onto.
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
-- State. Fixed size, allocated once.
--------------------------------------------------------------------------------

local slots: { DieSlot } = {}
local started = false
local rng = Random.new()

local connections: { RBXScriptConnection } = {}
local frameConnection: RBXScriptConnection? = nil

-- Last authoritative dice configuration seen on StateSync. Display only: it
-- decides how a die LOOKS, never what it rolls.
local diceConfig: { any } = {}

--------------------------------------------------------------------------------
-- Numeric hygiene
--------------------------------------------------------------------------------

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

--------------------------------------------------------------------------------
-- The 3D dice: sourcing, and the rotation that shows a chosen face
--------------------------------------------------------------------------------

-- The folder of generated solids. Absent is a legitimate state rather than an
-- error: the models are generated by the server at boot and replicate
-- asynchronously, so a client can be fully initialised before they arrive. A
-- missing die falls back to the flat numeral and must never take the renderer
-- down.
local diceFolder: Folder? = nil

local function findDiceFolder(): Folder?
	if diceFolder ~= nil and diceFolder.Parent ~= nil then
		return diceFolder
	end
	local found = ReplicatedStorage:FindFirstChild(DICE_FOLDER)
	if found ~= nil and found:IsA("Folder") then
		diceFolder = found
		return found
	end
	return nil
end

-- Called when the dice folder shows up late, so tiles that already rendered
-- without a solid can acquire one. Assigned by `init`; nil before then.
local onDiceAvailable: (() -> ())? = nil

-- Watches for late replication. Without this, a client whose first StateSync
-- beat the models would keep its blank tiles until the NEXT state change --
-- which, on a player who is not rolling, may be never.
local function watchForDice(): RBXScriptConnection?
	if findDiceFolder() ~= nil then
		return nil
	end
	return ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == DICE_FOLDER and child:IsA("Folder") then
			diceFolder = child :: Folder
			local notify = onDiceAvailable
			if notify ~= nil then
				notify()
			end
		end
	end)
end

-- THE ROTATION SOLVE -- the whole reason the builder records face normals.
--
-- The server chose a face. This returns the CFrame that turns the die so that
-- face points at the camera, which sits on +Z looking back toward the origin.
--
-- The model's local face normal is read from the attribute the builder wrote
-- when it generated the geometry (a numeral's offset from the centroid IS its
-- outward normal). `CFrame.fromMatrix` is not needed: rotating the normal onto
-- +Z is a single axis-angle turn about the axis perpendicular to both.
--
-- DEGENERATE CASES ARE REAL AND BOTH ARE HANDLED. When the normal already
-- points at the camera the cross product is zero-length and its `.Unit` is NaN,
-- which would silently poison every subsequent CFrame; when it points directly
-- away, the axis is likewise undefined but a half-turn IS required. Neither can
-- be left to float behaviour -- a NaN CFrame does not error, it just makes the
-- die vanish.
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

	local target = Vector3.new(0, 0, 1) -- toward the viewport camera
	local dot = math.clamp(n:Dot(target), -1, 1)

	if dot > 0.9999 then
		-- Already facing the camera.
		return CFrame.identity
	end
	if dot < -0.9999 then
		-- Facing directly away: any perpendicular axis gives a valid half-turn.
		return CFrame.fromAxisAngle(Vector3.new(0, 1, 0), math.pi)
	end

	local axis = n:Cross(target)
	if axis.Magnitude < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Swaps the solid inside a tile's viewport to `shapeId`, or clears it when the
-- shape is unknown or unavailable. Idempotent: re-applying the same shape is a
-- no-op, so a StateSync every roll does not rebuild seven models a second.
local function applyModel(visual: DieVisual, shapeId: string?): ()
	-- THE GUARD MUST NOT CACHE A FAILURE AS A SUCCESS.
	--
	-- Comparing `modelShape` alone is not enough. The models are generated by the
	-- server at boot and replicate asynchronously, so the FIRST StateSync can
	-- easily arrive before `dice_faces` exists on this client. That call records
	-- the shape, finds no folder, and returns with no model -- and every
	-- subsequent call then matches on shape and returns early. The die is
	-- permanently blank, the tile falls back to the numeral forever, and nothing
	-- reports an error because each individual step behaved as written.
	--
	-- Found exactly that way: the tile rendered empty while a manual clone of the
	-- same model into the same viewport worked perfectly.
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

	local folder = findDiceFolder()
	if folder == nil then
		return
	end
	local source = folder:FindFirstChild(shapeId)
	if source == nil or not source:IsA("Model") then
		return
	end

	local clone = source:Clone()
	clone.Parent = visual.viewport
	visual.model = clone

	-- FRAME THE DIE THAT IS ACTUALLY THERE, rather than the one a constant says
	-- should be. Camera distance is solved from this model's own measured radius
	-- so every shape fills the tile identically -- a D12 and a D4 are visually
	-- the same size on the board even though their geometry is not.
	--
	-- Solved here rather than fixed at the top of the file because two attempts
	-- at a hand-tuned constant were wrong: the number has to agree with whatever
	-- the builder's normalisation actually produced, and the only way to be sure
	-- of that is to measure the clone. A camera three times too far away renders
	-- a perfectly good die as a speck of thin edges, which is indistinguishable
	-- from broken geometry until you measure it.
	local camera = visual.viewport.CurrentCamera
	if camera ~= nil then
		local centre = clone:GetPivot().Position
		local radius = 0
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Pivot" then
				local reach = (d.Position - centre).Magnitude + d.Size.Magnitude * 0.5
				if reach > radius then
					radius = reach
				end
			end
		end
		if radius > 1e-3 then
			local distance = (radius / CAMERA_FILL) / math.tan(math.rad(CAMERA_FOV) * 0.5)
			-- Orbited off both axes so three faces are visible at rest. The die
			-- itself is never tilted -- moving the CAMERA keeps the server's
			-- chosen face pointing squarely down +Z, which is the assumption
			-- `rotationShowingFace` is built on.
			local eye = CFrame.Angles(0, REST_TILT_Y, 0)
				* CFrame.Angles(REST_TILT_X, 0, 0)
				* CFrame.new(0, 0, distance)
			camera.CFrame = CFrame.lookAt(centre + eye.Position, centre)
			camera.FieldOfView = CAMERA_FOV
		end
	end
end

--------------------------------------------------------------------------------
-- Construction (init only -- never called during a roll)
--------------------------------------------------------------------------------

local function makeVisual(index: number): DieVisual
	local tile = Instance.new("Frame")
	tile.Name = "Die" .. tostring(index)
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.BackgroundColor3 = UITheme.Colors.PanelMaroon
	tile.BorderSizePixel = 0
	tile.Visible = false

	-- A die must be SQUARE on screen. A fraction of a non-square parent is not,
	-- so the aspect is constrained rather than assumed.
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = tile

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.BorderGold
	stroke.Thickness = UITheme.BorderThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tile

	-- THE DIE ITSELF: a real 3D solid, rendered inside the flat tile.
	--
	-- A `ViewportFrame` draws a 3D model inside a 2D UI element with its own
	-- camera and no relationship to the world. That is what lets the board stay
	-- a flat ScreenGui while the dice stay solid -- and it is what buys back the
	-- thing flatness cost: a die with uneven mass is VISIBLY lopsided as it
	-- tumbles, so FR-2's inverted-mass rule is once again something you watch
	-- happen rather than infer from a number appearing less often.
	--
	-- Empty until `applyConfig` learns the shape. A ViewportFrame with no model
	-- draws nothing, which is the honest state before StateSync arrives.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Die3D"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Position = UDim2.fromScale(0, 0)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	-- Lit from the front so facets read as facets. Ambient alone flattens the
	-- solid back into a silhouette, which would defeat the entire purpose.
	viewport.LightDirection = Vector3.new(-0.3, -0.6, -1).Unit
	viewport.Ambient = Color3.fromRGB(120, 112, 120)
	viewport.LightColor = Color3.fromRGB(255, 248, 232)
	viewport.Parent = tile

	-- Placed provisionally; `applyModel` re-solves the distance against the
	-- actual die once one is cloned in. Until then there is nothing to frame.
	local vpCamera = Instance.new("Camera")
	vpCamera.CFrame = CFrame.lookAt(Vector3.new(0, 0, 8), Vector3.zero)
	vpCamera.FieldOfView = CAMERA_FOV
	vpCamera.Parent = viewport
	viewport.CurrentCamera = vpCamera

	-- The numeral. STILL PRESENT, and deliberately so.
	--
	-- The 3D die carries its own numerals on its faces, but at seven-dice size on
	-- a 320px screen those are a few pixels tall (NFR-3). This label is the
	-- readable answer; the solid is the read of HOW the answer happened. It sits
	-- in the corner rather than the centre so it does not cover the die.
	local numeral = Instance.new("TextLabel")
	numeral.Name = "Numeral"
	numeral.Size = UDim2.fromScale(0.34, 0.26)
	numeral.Position = UDim2.fromScale(0.63, 0.05)
	numeral.BackgroundTransparency = 1
	numeral.Font = UITheme.Font
	numeral.TextScaled = true
	numeral.TextColor3 = UITheme.Colors.TextPrimary
	numeral.TextXAlignment = Enum.TextXAlignment.Right
	numeral.Text = ""
	numeral.ZIndex = 3
	numeral.Parent = tile

	-- The shape, named on the tile. In 3D the silhouette said what the die was;
	-- flat, every shape is the same square, so the name has to be printed or the
	-- information is simply gone.
	local shapeTag = Instance.new("TextLabel")
	shapeTag.Name = "Shape"
	-- Left-aligned in the top corner, opposite the numeral. Centred, it sat
	-- behind the die and read as a smudge on the solid.
	shapeTag.Size = UDim2.fromScale(0.44, 0.18)
	shapeTag.Position = UDim2.fromScale(0.05, 0.04)
	shapeTag.BackgroundTransparency = 1
	shapeTag.Font = UITheme.Font
	shapeTag.TextScaled = true
	shapeTag.TextColor3 = UITheme.Colors.TextDim
	shapeTag.TextXAlignment = Enum.TextXAlignment.Left
	shapeTag.ZIndex = 3
	shapeTag.Text = ""
	shapeTag.Parent = tile

	-- THE WEIGHT BAR (FR-1.3). How much mass sits on the face currently showing,
	-- as a fraction of this die's total. This is the compensation for losing the
	-- lopsided silhouette: without it, mass would be invisible outside the forge.
	local bar = Instance.new("Frame")
	bar.Name = "Weight"
	bar.Size = UDim2.fromScale(1 - BAR_INSET * 2, BAR_H)
	bar.Position = UDim2.fromScale(BAR_INSET, 1 - BAR_H - 0.06)
	bar.BackgroundColor3 = UITheme.Colors.PanelDeep
	bar.BorderSizePixel = 0
	bar.Parent = tile

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = UITheme.Colors.TextGold
	barFill.BorderSizePixel = 0
	barFill.Parent = bar

	return {
		tile = tile,
		viewport = viewport,
		model = nil,
		modelShape = nil,
		numeral = numeral,
		shapeTag = shapeTag,
		bar = bar,
		barFill = barFill,
		stroke = stroke,
		shape = DEFAULT_SHAPE,
		faceCount = FACE_COUNTS[DEFAULT_SHAPE],
		numbered = false,
		weights = {},
		extent = 0,
	}
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
-- rotation -- those belong to the animation, and a config arriving mid-tumble
-- must not snap a die that is in the air.
local function applyConfig(visual: DieVisual, shapeId: string?, faces: { any }): ()
	local resolved = shapeId or DEFAULT_SHAPE
	visual.shape = resolved
	visual.faceCount = FACE_COUNTS[resolved] or FACE_COUNTS[DEFAULT_SHAPE]
	visual.numbered = shapeId ~= nil
	visual.weights = readWeights(faces, visual.faceCount)
	visual.shapeTag.Text = if shapeId ~= nil then resolved else ""

	-- The solid follows the shape. Passing `shapeId` rather than `resolved` on
	-- purpose: an unknown shape must draw NO die, not a default D6 that would be
	-- asserting a shape the client has not been told.
	applyModel(visual, shapeId)
end

-- Shows `faceIndex` on the tile: its numeral, and its share of the die's mass.
local function showFace(visual: DieVisual, faceIndex: number): ()
	if not visual.numbered then
		-- Shape unknown. No numeral, no bar -- nothing asserted.
		visual.numeral.Text = ""
		visual.bar.Visible = false
		visual.stroke.Color = UITheme.Colors.BorderDim
		return
	end

	visual.numeral.Text = tostring(faceIndex)

	local weight = visual.weights[faceIndex]
	if weight == nil then
		-- Masses unreadable. Better to draw no bar than a bar at a guess.
		visual.bar.Visible = false
		visual.numeral.TextColor3 = UITheme.Colors.TextPrimary
		visual.stroke.Color = UITheme.Colors.BorderGold
		return
	end

	visual.bar.Visible = true

	-- The bar is scaled against an EVEN share, not against 1.0. A D20 face
	-- holding 10% of the die's mass is carrying twice its share and must read as
	-- heavy; against 1.0 it would render as a nearly empty bar and read as
	-- light. Even share is the only baseline that means the same thing on a D4
	-- and a D20.
	local evenShare = 1 / math.max(1, visual.faceCount)
	local relative = weight / evenShare
	-- 2x even share fills the bar. Beyond that it is already full and the colour
	-- carries the rest.
	local fill = math.clamp(relative / 2, 0, 1)
	visual.barFill.Size = UDim2.fromScale(fill, 1)

	-- A VOID face -- one carrying so little mass it effectively never lands --
	-- is drawn dim and grey. This mirrors what the HUD's VOID readout reports,
	-- so the two cannot tell the player different stories.
	local heavy = fill >= GLOW_THRESHOLD
	if fill <= 0.001 then
		visual.barFill.BackgroundColor3 = UITheme.Colors.VoidFace
		visual.numeral.TextColor3 = UITheme.Colors.VoidFace
		visual.stroke.Color = UITheme.Colors.BorderDim
	elseif heavy then
		visual.barFill.BackgroundColor3 = UITheme.Colors.TextGold
		visual.numeral.TextColor3 = UITheme.Colors.TextGold
		visual.stroke.Color = UITheme.Colors.BorderGold
	else
		visual.barFill.BackgroundColor3 = UITheme.Colors.TextDim
		visual.numeral.TextColor3 = UITheme.Colors.TextPrimary
		visual.stroke.Color = UITheme.Colors.BorderGold
	end
end

-- Sizes a die tile for a board holding `count` dice, and records the true
-- maximum extent BoardView's containment contract demands.
local function applyScale(visual: DieVisual, count: number): ()
	local scale = BoardView.getDieScale(count)
	visual.tile.Size = UDim2.fromScale(scale, scale)

	-- A square spun to 45 degrees reaches its HALF-DIAGONAL, which is
	-- sqrt(2)/2 further out than its half-width. Reporting the half-width would
	-- tell the board this die is smaller than it is, and the board cannot detect
	-- the difference -- it would clamp exactly, to the wrong number, and corners
	-- would clip the frame mid-tumble.
	visual.extent = (scale * 0.5) * math.sqrt(2)
end

--------------------------------------------------------------------------------
-- The roll
--------------------------------------------------------------------------------

-- Which face the die is "resting on" heavy-wise, used only to decide which way
-- the settle leans. Returns the heaviest face's index, or 0 when masses are
-- unknown.
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

local function beginRoll(faces: { any }, payout: number): ()
	local count = math.clamp(#diceConfig, 0, MAX_DICE)
	if count == 0 then
		return
	end

	-- A bigger payout buys a longer, fuller tumble. Carried over from the 3D
	-- renderer: the reward for a good roll should be a better THROW, never extra
	-- stillness.
	local magnitude = 0
	if type(payout) == "number" and isFinite(payout) and payout > 0 then
		magnitude = math.clamp(math.log(1 + payout) / math.log(1 + 1e6), 0, 1)
	end
	local duration = MIN_DURATION + (MAX_DURATION - MIN_DURATION) * magnitude
	local bonusTurns = math.floor(SPIN_TURNS_PAYOUT_BONUS * magnitude + 0.5)

	for i = 1, count do
		local slot = slots[i]
		if slot == nil then
			continue
		end

		local config = diceConfig[i]
		local shapeId = readShape(config)
		applyConfig(slot.visual, shapeId, readFaces(config))
		applyScale(slot.visual, count)

		-- The server's chosen face. A malformed index is substituted, never
		-- rejected: the payout is already credited and refusing to animate would
		-- only hide a result the player has been paid for.
		local target = faces[i]
		local faceIndex = 1
		if type(target) == "number" and isFinite(target) and target >= 1 then
			faceIndex = math.floor(target)
		end
		faceIndex = math.clamp(faceIndex, 1, math.max(1, slot.visual.faceCount))
		slot.faceIndex = faceIndex

		slot.spinTotal = (
			rng:NextInteger(SPIN_TURNS_MIN, SPIN_TURNS_MAX)
			+ bonusTurns
			+ rng:NextNumber(SPIN_FRACTION_MIN, SPIN_FRACTION_MAX)
		) * TAU
		slot.spinDir = if rng:NextNumber() < 0.5 then -1 else 1
		slot.drift = rng:NextNumber(-DEAL_DRIFT, DEAL_DRIFT)

		-- THE 3D TUMBLE.
		--
		-- `finalRot` is where the die must END: the orientation that shows the
		-- face the server chose. The animation then unwinds a whole-turn residual
		-- ONTO that destination, so the die arrives showing the right face
		-- without ever having been placed there early.
		--
		-- The axis is random per roll and deliberately off-axis -- a die that
		-- always spun about Y would read as a carousel. It is normalised because
		-- `CFrame.fromAxisAngle` on a non-unit axis scales the angle silently.
		local model = slot.visual.model
		slot.finalRot = if model ~= nil
			then rotationShowingFace(model, faceIndex)
			else CFrame.identity

		local axis = Vector3.new(
			rng:NextNumber(-1, 1),
			rng:NextNumber(-1, 1),
			rng:NextNumber(-1, 1)
		)
		-- A near-zero random vector has no meaningful direction; fall back rather
		-- than normalise it into a NaN axis.
		slot.spinAxis = if axis.Magnitude > 1e-3 then axis.Unit else Vector3.new(0, 1, 0)

		-- THE HEAVY-SIDE DRAG. If the face that landed is NOT the heaviest one,
		-- the die leans away from the heavy face as it settles -- it visibly
		-- avoided resting there. If the heavy face DID land, the lean is zero:
		-- the die gave in, which is exactly the rarer, more notable event and
		-- should look different. Cosmetic only; the outcome arrived decided.
		local heavy = heaviestFace(slot.visual)
		if heavy ~= 0 and heavy ~= faceIndex then
			slot.heavyLean = HEAVY_LEAN * slot.spinDir
		else
			slot.heavyLean = 0
		end

		-- FR-1.4: the resting place comes from BoardView, which is the only
		-- thing that knows where "inside" is, and is clamped by the die's own
		-- true extent -- diagonal included -- before it is ever used.
		slot.endPos = BoardView.getAnchor(i, count, slot.visual.extent)
		slot.startPos = BoardView.getSpawnPoint(i, count)

		slot.elapsed = 0
		slot.duration = duration
		slot.animating = true

		if not slot.inUse then
			slot.inUse = true
			slot.visual.tile.Parent = BoardView.getContainer()
		end

		-- Place it at the start immediately, so a die that appears this frame
		-- appears at the top of the board rather than at its slot for one frame.
		-- This is the a == 0 pose: a full multi-turn rotation AWAY from the
		-- answer, never the answer itself.
		slot.visual.tile.Visible = true
		slot.visual.tile.Position = slot.startPos
		slot.visual.tile.Rotation = math.deg(slot.spinTotal * slot.spinDir)
		showFace(slot.visual, faceIndex)
	end
end

--------------------------------------------------------------------------------
-- The frame step
--------------------------------------------------------------------------------

-- Ease-out cubic. The die travels fast and arrives slowly, which is what a
-- thrown object does.
local function easeOut(a: number): number
	local inv = 1 - a
	return 1 - inv * inv * inv
end

local function step(_delta: number): ()
	for i = 1, MAX_DICE do
		local slot = slots[i]
		if slot == nil or not slot.animating then
			continue
		end

		slot.elapsed += _delta
		local a = math.clamp(slot.elapsed / math.max(slot.duration, 1e-3), 0, 1)
		local eased = easeOut(a)

		-- Position: from the spawn point to the slot, with a lateral drift that
		-- decays out, plus a small overshoot that eases back so the die looks
		-- thrown rather than moved.
		local overshoot = math.sin(a * math.pi) * SETTLE_OVERSHOOT * slot.visual.extent
		local x = slot.startPos.X.Scale + (slot.endPos.X.Scale - slot.startPos.X.Scale) * eased
			+ slot.drift * (1 - eased)
		local y = slot.startPos.Y.Scale + (slot.endPos.Y.Scale - slot.startPos.Y.Scale) * eased
			+ overshoot

		slot.visual.tile.Position = UDim2.fromScale(x, y)

		-- Rotation: the RESIDUAL spin still to be unwound. At a == 0 this is the
		-- full multi-turn budget and at a == 1 it is exactly zero, so the die
		-- always finishes on its answer and never rewinds -- the property the
		-- very first 3D renderer had to be rewritten to obtain.
		local residual = slot.spinTotal * (1 - eased)

		-- The heavy-side lean, applied only through the settle. It grows as the
		-- spin dies and fades to nothing at rest, so the die leans off its heavy
		-- face and then straightens.
		local lean = slot.heavyLean * math.sin(a * math.pi) * eased

		local model = slot.visual.model
		if model ~= nil then
			-- THE TUMBLE, IN THREE DIMENSIONS. The residual turn is applied about
			-- the random axis and composed ONTO the destination orientation, so
			-- the die spins its way to the server's face rather than being placed
			-- there and jittered. At a == 1 the residual is zero and what remains
			-- is exactly `finalRot`.
			--
			-- The lean is a small extra turn about the view axis, which reads as
			-- the die tipping as it loses momentum.
			local spin = CFrame.fromAxisAngle(slot.spinAxis, residual * slot.spinDir)
			local tip = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), lean)
			model:PivotTo(tip * spin * slot.finalRot)
			-- The tile itself stays square; only the solid inside it turns. A
			-- rotating ViewportFrame would rotate the numeral and weight bar too.
			slot.visual.tile.Rotation = 0
		else
			-- No solid available (shape unknown, or the models have not been
			-- generated yet). Fall back to turning the flat tile, so a roll is
			-- still visibly a roll rather than a silent text change.
			slot.visual.tile.Rotation = math.deg(residual * slot.spinDir + lean)
		end

		if a >= 1 then
			slot.animating = false
			slot.visual.tile.Position = slot.endPos
			slot.visual.tile.Rotation = 0
			if model ~= nil then
				model:PivotTo(slot.finalRot)
			end
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

	for i = 1, MAX_DICE do
		slots[i] = {
			visual = makeVisual(i),
			inUse = false,
			animating = false,
			elapsed = 0,
			duration = MIN_DURATION,
			startPos = UDim2.fromScale(0.5, 0.5),
			endPos = UDim2.fromScale(0.5, 0.5),
			spinTotal = 0,
			spinDir = 1,
			drift = 0,
			heavyLean = 0,
			faceIndex = 1,
			spinAxis = Vector3.new(0, 1, 0),
			finalRot = CFrame.identity,
		}
	end

	-- Redraws every resting die from the last known config. Extracted from the
	-- StateSync handler so the late-replication watcher can reuse it: a client
	-- whose first snapshot arrived before the models did needs to be able to
	-- rebuild its tiles WITHOUT waiting for another state change, which for a
	-- player who is not rolling may never come.
	local function refreshResting(): ()
		local count = math.clamp(#diceConfig, 0, MAX_DICE)
		for i = 1, MAX_DICE do
			local slot = slots[i]
			if i > count then
				if slot.inUse then
					slot.inUse = false
					slot.animating = false
					slot.visual.tile.Visible = false
					slot.visual.tile.Parent = nil
				end
				continue
			end
			if slot.animating then
				-- A config change mid-tumble re-skins the die on the next roll
				-- rather than snapping it while it is in the air.
				continue
			end
			applyConfig(slot.visual, readShape(diceConfig[i]), readFaces(diceConfig[i]))
			applyScale(slot.visual, count)
			slot.endPos = BoardView.getAnchor(i, count, slot.visual.extent)
			slot.visual.tile.Position = slot.endPos
			slot.visual.tile.Rotation = 0
			slot.visual.tile.Visible = true
			showFace(slot.visual, slot.faceIndex)

			-- Park the solid showing the same face the numeral reports. Without
			-- this a die at rest sits in whatever orientation it was built in,
			-- and the 3D face would contradict the label beside it -- two
			-- readings of the same die disagreeing on screen.
			local resting = slot.visual.model
			if resting ~= nil then
				slot.finalRot = rotationShowingFace(resting, slot.faceIndex)
				resting:PivotTo(slot.finalRot)
			end
			if not slot.inUse then
				slot.inUse = true
				slot.visual.tile.Parent = BoardView.getContainer()
			end
		end
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

	-- If the solids replicate after this client has already drawn its tiles,
	-- redraw them once so the dice appear rather than staying flat until the
	-- next state change.
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
-- and the pooled Instances. Symmetric with `HUD.shutdown`.
--
-- Tearing down mid-tumble is safe by construction and always was: the payout was
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
	-- keeping the old one would leak seven tiles on every restart.
	-- Indexed defensively: `init` errors if BoardView is not ready, which can
	-- leave the pool half built with `started` already latched.
	for i = 1, MAX_DICE do
		local slot: DieSlot? = slots[i]
		if slot ~= nil then
			slot.visual.tile:Destroy()
		end
	end
	slots = {}
	diceConfig = {}

	-- The late-replication callback closes over `refreshResting`, which closes
	-- over the slot pool this function just destroyed. Its own connection is
	-- released above, but clearing the reference means a stale closure cannot
	-- outlive the pool it would write into.
	onDiceAvailable = nil

	started = false
end

return DiceRenderer
