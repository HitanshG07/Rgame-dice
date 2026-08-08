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

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

type DieVisual = {
	tile: Frame,
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

	-- The face numeral (FR-1.2). Centred, dominating the tile, so it is legible
	-- at seven-dice size on a 320px screen.
	local numeral = Instance.new("TextLabel")
	numeral.Name = "Numeral"
	numeral.Size = UDim2.fromScale(1, NUMERAL_H)
	numeral.Position = UDim2.fromScale(0, 0.10)
	numeral.BackgroundTransparency = 1
	numeral.Font = UITheme.Font
	numeral.TextScaled = true
	numeral.TextColor3 = UITheme.Colors.TextPrimary
	numeral.TextXAlignment = Enum.TextXAlignment.Center
	numeral.Text = ""
	numeral.Parent = tile

	-- The shape, named on the tile. In 3D the silhouette said what the die was;
	-- flat, every shape is the same square, so the name has to be printed or the
	-- information is simply gone.
	local shapeTag = Instance.new("TextLabel")
	shapeTag.Name = "Shape"
	shapeTag.Size = UDim2.fromScale(1, SHAPE_H)
	shapeTag.Position = UDim2.fromScale(0, 0.015)
	shapeTag.BackgroundTransparency = 1
	shapeTag.Font = UITheme.Font
	shapeTag.TextScaled = true
	shapeTag.TextColor3 = UITheme.Colors.TextDim
	shapeTag.TextXAlignment = Enum.TextXAlignment.Center
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
		-- always finishes square and never rewinds -- the same property the 3D
		-- version had to be rewritten to obtain.
		local residual = slot.spinTotal * (1 - eased)

		-- The heavy-side lean, applied only through the settle. It grows as the
		-- spin dies and fades to nothing at rest, so the die leans off its heavy
		-- face and then straightens.
		local lean = slot.heavyLean * math.sin(a * math.pi) * eased

		slot.visual.tile.Rotation = math.deg(residual * slot.spinDir + lean)

		if a >= 1 then
			slot.animating = false
			slot.visual.tile.Position = slot.endPos
			slot.visual.tile.Rotation = 0
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
		}
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
			if not slot.inUse then
				slot.inUse = true
				slot.visual.tile.Parent = BoardView.getContainer()
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

	started = false
end

return DiceRenderer
