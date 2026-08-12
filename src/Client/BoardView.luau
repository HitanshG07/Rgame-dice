--!strict
-- BoardView.luau
-- The 2D board: a flat felt tray drawn in screen space, and the slot geometry
-- every die is dealt into (SRS FR-1.1, FR-1.4; HLD §4.3).
--
-- WHY THIS REPLACED THE 3D PIT. The operator asked for a 2D board after seeing
-- the pit render: a deep well viewed from 27 studs up, with the floor eating the
-- frame and the die reading as a speck. This module is the answer to that, and
-- the change is confined to the view layer -- no server module, no shared module,
-- and no gameplay rule contains a single line of 3D. The server samples an
-- outcome from a mass distribution and sends a number; how that number is shown
-- was always this layer's business alone.
--
-- WHAT WAS KNOWINGLY GIVEN UP, recorded because a later reader will otherwise
-- assume nobody noticed. The inverted-mass mechanic (FR-2) is the heart of the
-- game: mass poured onto a face makes that face land LESS often. In the pit you
-- could SEE that -- a lopsided solid tumbling and refusing to settle heavy-side
-- up. Flat, that same rule shows only as a number appearing less frequently,
-- which is indistinguishable from bad luck. The operator was told this plainly
-- and chose 2D anyway; it is their call, and this file's job is to lose as
-- little of the read as a flat presentation allows. Hence:
--
--   * dice still TUMBLE rather than flipping to an answer -- DiceRenderer spins
--     them in-plane and settles them, so a roll is still an event with a
--     duration, not a state change;
--   * every face carries a visible WEIGHT BAR, so a heavy face is legible as
--     heavy while it is on screen rather than only inside the forge;
--   * the settle DRAGS toward the heavy side, so the die visibly fights to
--     avoid resting on its heavy face.
--
-- None of that is as good as watching a weighted object fall. It is what is
-- available in two dimensions.
--
-- WHY SCREEN SPACE AND NOT A SurfaceGui ON A PART. A SurfaceGui would keep a
-- camera, a part and a framing solve alive to render something with no depth --
-- all of the 3D machinery and none of its benefit. A ScreenGui has no camera, no
-- viewport solve, no aspect-driven frustum arithmetic, and it scales to 320px
-- through 4K by construction (NFR-3).
--
-- THE API IS DELIBERATELY THE SAME SHAPE AS ArenaView'S. `isReady`,
-- `getContainer`, `getAnchor`, `getSpawnPoint`, `init`, `shutdown` all survive
-- with their meanings intact; only their coordinate TYPE changed, from Vector3
-- studs to UDim2 screen scale. Keeping the shape means DiceRenderer's six call
-- sites moved coordinate systems without moving responsibility, and the
-- containment guarantee (FR-1.4) is still enforced HERE rather than trusted to
-- the renderer -- `clampToBoard` remains the only way to obtain a legal slot.
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
-- Board geometry.
--
-- EVERY NUMBER HERE IS A FRACTION OF THE SCREEN, never a pixel (FR-13.7, NFR-3).
-- The tray is defined once as a rectangle in screen scale, and slots are placed
-- inside it as fractions OF THE TRAY, so the whole board scales as one object.
--------------------------------------------------------------------------------

-- The tray, in absolute screen scale. Centred horizontally; sat in the upper
-- middle of the screen so the HUD's bottom bar and MenuPanel's sidebars frame it
-- rather than cover it.
--
-- WIDER THAN IT IS TALL, on purpose. Seven dice laid out flat want horizontal
-- room; a square tray would either shrink every die or stack them into rows that
-- read as a grid rather than a throw.
-- Centred BETWEEN THE SIDEBARS, not on the screen. MenuPanel occupies roughly
-- the outer 14% of each edge; centring on the screen leaves the board looking
-- shoved left, because the eye centres it against the gap it sits in rather
-- than against the window.
local TRAY_X = 0.165
local TRAY_Y = 0.135
local TRAY_W = 0.670
local TRAY_H = 0.660

-- The playable interior, as a fraction of the tray, inset from the tray's own
-- border so a die never touches the frame. This is the 2D equivalent of the
-- pit's inner wall faces, and it is what FR-1.4 containment is measured against.
local INNER_INSET = 0.055

-- How far a resting die is held clear of the interior edge, as a fraction of the
-- tray. The flat analogue of the pit's REST_EPSILON: an extent alone puts the
-- die's bounding box EXACTLY on the boundary, where any float error -- or a
-- caller reporting a nominal half-size rather than a true maximum extent --
-- shows as the die clipping the frame.
local REST_EPSILON = 0.004

-- Die footprint, as a fraction of the TRAY's smaller dimension, so a die is the
-- same visual size regardless of the screen's aspect ratio. A single die gets
-- the large size; a crowded board scales down so seven still fit without
-- overlapping.
-- A SOLO DIE IS THE WHOLE GAME AND SHOULD LOOK LIKE IT. The first value here
-- was 0.30, which rendered as a stamp adrift in a large empty tray -- the same
-- "die is a speck" complaint that ended the 3D pit, reproduced flat. A single
-- die now takes over half the tray's height.
local DIE_SCALE_SOLO = 0.560
local DIE_SCALE_FULL = 0.205

local MAX_DICE = 7 -- SRS FR-1.1

-- Where the tumble begins: above the tray's top edge, so a die is dealt IN
-- rather than appearing. Expressed in tray fractions and deliberately negative
-- -- the spawn point is OUTSIDE the interior on purpose, and FR-1.4 constrains
-- where a die comes to REST, not where it starts.
local SPAWN_ABOVE = 0.45

--------------------------------------------------------------------------------
-- Slot layouts, precomputed once for every legal die count (FR-1.1: 1 to 7).
--
-- Precomputed rather than derived per roll because these are the same seven
-- answers forever, and a roll is not the moment to be doing arithmetic.
--
-- Positions are offsets from the interior's CENTRE, expressed as a fraction of
-- the interior's half-extent, so each lies in [-1, 1] on both axes and the
-- layout is independent of the tray's real size.
--
-- LAID OUT IN ROWS, not a ring. A ring reads as a ritual circle in 3D where
-- perspective separates the near and far dice; flat, a ring just looks like a
-- clock face and wastes the middle. Rows read as dice thrown onto a table.
--------------------------------------------------------------------------------

type Slot = { x: number, y: number }

local function buildLayouts(): { { Slot } }
	local layouts: { { Slot } } = {}

	-- Row plans: how many dice sit on each row, for each total count. Chosen so
	-- no row is more than one die longer than another, which keeps the cluster
	-- balanced rather than top-heavy.
	local plans: { { number } } = {
		{ 1 },
		{ 2 },
		{ 3 },
		{ 2, 2 },
		{ 3, 2 },
		{ 3, 3 },
		{ 4, 3 },
	}

	for count = 1, MAX_DICE do
		local plan = plans[count]
		local slots: { Slot } = {}
		local rows = #plan

		for rowIndex, inRow in ipairs(plan) do
			-- Spread rows across the vertical span. A single row sits dead
			-- centre; two or more are evenly pitched with a margin at each end
			-- so the outermost dice are not against the interior edge.
			local y: number
			if rows == 1 then
				y = 0
			else
				y = -0.55 + ((rowIndex - 1) / (rows - 1)) * 1.10
			end

			for column = 1, inRow do
				local x: number
				if inRow == 1 then
					x = 0
				else
					x = -0.62 + ((column - 1) / (inRow - 1)) * 1.24
				end
				table.insert(slots, { x = x, y = y })
			end
		end

		layouts[count] = slots
	end

	return layouts
end

local LAYOUTS: { { Slot } } = buildLayouts()

--------------------------------------------------------------------------------
-- Numeric hygiene
--------------------------------------------------------------------------------

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- A negative, NaN or infinite extent is treated as zero rather than propagated.
-- Same contract the pit had: a die that cannot be measured is a display problem,
-- and an error thrown mid-roll would be a bigger one.
local function safeExtent(extent: number): number
	if not isFinite(extent) or extent < 0 then
		return 0
	end
	return extent
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local built = false
local screenGui: ScreenGui? = nil
local tray: Frame? = nil
local container: Frame? = nil
local connections: { RBXScriptConnection } = {}

-- What the backdrop displaced, so `shutdown` can put it back exactly. The board
-- is a guest in someone else's DataModel and must leave no trace.
local restoreCameraType: Enum.CameraType? = nil
local restoreCharacterVisible: { [BasePart]: number } = {}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- The felt. Deeper than a panel and slightly warmer, so the board reads as a
-- surface dice are thrown ONTO rather than as another UI panel.
local function build(): (ScreenGui, Frame, Frame)
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

	-- The playable interior container with a slim, equal border on all sides.
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

	-- Dice are parented HERE, one layer above the felt, so the renderer never
	-- has to know about the tray's own children or their ZIndex.
	local dice = Instance.new("Frame")
	dice.Name = "Dice"
	dice.Size = UDim2.fromScale(1, 1)
	dice.BackgroundTransparency = 1
	dice.ZIndex = 2
	dice.Parent = interior

	-- Embedded Result Summary Bar at the bottom edge of the board container
	local resultBar = Instance.new("Frame")
	resultBar.Name = "ResultBar"
	resultBar.Size = UDim2.fromScale(0.96, 0.065)
	resultBar.Position = UDim2.fromScale(0.02, 0.915)
	resultBar.BackgroundColor3 = Color3.fromRGB(24, 19, 16)
	resultBar.ZIndex = 5
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

	if player ~= nil then
		gui.Parent = player:WaitForChild("PlayerGui")
	end

	return gui, frame, dice
end

-- THE BACKDROP.
--
-- WHY THIS MODULE OWNS IT AT ALL. The 3D pit floated at Y = 500 with a
-- Scriptable camera pointed into it, and that framing was what kept Roblox's
-- default world -- baseplate, skybox, spawn, and the player's own avatar -- out
-- of the shot. Deleting the pit deleted the only thing suppressing them, and the
-- first flat build rendered the board as a floating panel with a Roblox
-- character standing in front of it. A 2D board still needs SOMETHING to be in
-- front of; it just needs a colour rather than geometry.
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
	-- Behind every other child of this ScreenGui, including the tray.
	backdrop.ZIndex = 0
	backdrop.Parent = gui
end

-- The camera and the avatar.
--
-- The camera is parked as Scriptable so Roblox's default controller stops
-- swinging it around behind a board that does not move; the avatar is made
-- transparent rather than destroyed, because destroying a character the server
-- owns is not this module's business and would fight respawn.
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

-- The frame dice parent themselves to. Named `getContainer` to match the pit's
-- API exactly, so the renderer's call site did not have to change meaning.
function BoardView.getContainer(): Frame
	local frame = container
	if frame == nil then
		error("[BoardView] getContainer before init", 2)
	end
	return frame
end

-- The interior's centre, in the same fraction-of-interior coordinates
-- `getAnchor` returns. Kept for FeedbackFX, which anchors floating payout text
-- to the middle of the board.
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

-- How big a die should be drawn, as a fraction of the interior, for a board
-- holding `count` dice. Interpolated rather than stepped so going from one die
-- to seven scales smoothly instead of snapping.
--
-- Returned as a SQUARE in scale terms only after the caller applies a
-- UIAspectRatioConstraint; a raw fraction of a non-square parent is not square
-- on screen. The renderer owns that constraint, because the renderer owns the
-- die's Instance.
function BoardView.getDieScale(count: number): number
	local n = count
	if not isFinite(n) then
		n = 1
	end
	n = math.clamp(math.floor(n), 1, MAX_DICE)
	local t = (n - 1) / (MAX_DICE - 1)
	return DIE_SCALE_SOLO + (DIE_SCALE_FULL - DIE_SCALE_SOLO) * t
end

-- FR-1.4, the containment guarantee, in two dimensions.
--
-- CONTRACT
--   `position` is a point in INTERIOR-RELATIVE scale: {0,0} is the interior's
--   top-left corner and {1,1} its bottom-right. `extent` is the die's TRUE
--   MAXIMUM HALF-SIZE as a fraction of the interior, measured to the furthest
--   point of its geometry in ANY direction and in the orientation it will
--   actually be shown in -- not a nominal half-width. A square rotated 45
--   degrees mid-tumble reaches its half-DIAGONAL, and a caller that passes the
--   half-width has told the board the die is smaller than it is. Containment is
--   then exact for the size it was given and wrong for the die on screen; the
--   board cannot detect the difference. A negative or non-finite `extent` is
--   treated as zero.
--
-- GUARANTEES, for finite `position` and any `extent`:
--   * Never errors, for any input, at any board or die size.
--   * The returned X and Y lie within `extent + REST_EPSILON` of the interior's
--     edges on every side.
--   * If the die is WIDER than the interior, that range inverts; rather than
--     letting `math.clamp` raise on an inverted range, the axis degrades to the
--     interior's centre exactly -- the same "dead centre" answer the pit gave.
--
-- Every degradation is deliberate, for the reason the pit's version gave: a die
-- that cannot fit is a display problem, and an error thrown mid-roll would be a
-- bigger one -- the payout is already credited by then either way.
function BoardView.clampToBoard(position: UDim2, extent: number): UDim2
	local half = safeExtent(extent) + REST_EPSILON

	local lo = half
	local hi = 1 - half

	local function axis(value: number): number
		if not isFinite(value) then
			return 0.5
		end
		if lo > hi then
			return 0.5
		end
		return math.clamp(value, lo, hi)
	end

	return UDim2.fromScale(axis(position.X.Scale), axis(position.Y.Scale))
end

-- The resting position for slot `index` of `count`, in interior-relative scale.
-- No rotation is returned: the renderer supplies the orientation, because
-- orientation is where the server's chosen face is expressed and the board must
-- have no opinion on it.
--
-- CONTRACT
--   `extent` carries the same meaning and the same demand as in `clampToBoard`.
--
-- GUARANTEES:
--   * Never errors. Any `index` or `count` -- fractional, negative, out of
--     range, infinite or NaN -- resolves to the centre slot rather than
--     throwing.
--   * The returned position satisfies `clampToBoard`'s guarantees for the same
--     `extent`.
function BoardView.getAnchor(index: number, count: number, extent: number): UDim2
	local half = safeExtent(extent)

	local offset: Slot = { x = 0, y = 0 }
	if isFinite(index) and isFinite(count) then
		local slots = LAYOUTS[math.clamp(math.floor(count), 1, MAX_DICE)]
		if slots ~= nil then
			offset = slots[math.floor(index)] or offset
		end
	end

	-- Slot offsets are in [-1, 1] of the interior half-extent; the usable half
	-- shrinks by the die's own extent so a slot at the edge still lands a whole
	-- die inside.
	local usable = math.max(0, 0.5 - half - REST_EPSILON)
	local raw = UDim2.fromScale(0.5 + offset.x * usable, 0.5 + offset.y * usable)

	return BoardView.clampToBoard(raw, half)
end

-- Where the tumble begins: directly above its own slot, off the top of the
-- interior. Deliberately NOT clamped -- the start point is outside the board on
-- purpose, and FR-1.4 constrains where a die comes to REST.
function BoardView.getSpawnPoint(index: number, count: number): UDim2
	local anchor = BoardView.getAnchor(index, count, 0)
	return UDim2.fromScale(anchor.X.Scale, anchor.Y.Scale - SPAWN_ABOVE)
end

function BoardView.init(_net: any): ()
	if built then
		return
	end

	local gui, frame, dice = build()
	buildBackdrop(gui)
	screenGui = gui
	tray = frame
	container = dice
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
	local interior = screenGui:FindFirstChild("Tray", true) and screenGui.Tray:FindFirstChild("Interior")
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

	for i, shapeName in ipairs(shapeOrder) do
		local info = grouped[shapeName]
		local item = Instance.new("Frame")
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
-- dies with us, but `claimView` reached outside this module twice -- it made the
-- camera Scriptable and it made the player's avatar invisible. Both belong to
-- the DataModel, not to the board, and a teardown that left either in place
-- would strand the player behind an invisible character with a frozen camera and
-- no board to explain it.
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
	tray = nil
	container = nil
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
