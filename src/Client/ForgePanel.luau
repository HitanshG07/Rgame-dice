--!strict
-- ForgePanel.luau
-- THE FORGE. The primary surface of the game (SRS FR-13.8) -- not a submenu.
--
-- It is reachable in ONE tap: a permanently visible FORGE tab sits on the left
-- edge of the arena and opens this panel directly. FR-13.8 allows two; one is
-- what the core mechanic deserves.
--
-- WHAT THIS FILE IS RESPONSIBLE FOR
--   * Letting the player redistribute a FIXED mass budget across a die's faces.
--   * Showing, BEFORE anything is committed, the four numbers FR-3.4 demands:
--     per-face value, per-face landing probability, expected value per roll, and
--     Void probability.
--   * Assigning elements (FR-4.1) and changing shape (FR-6.1), showing anything
--     the player has not unlocked as LOCKED rather than hiding or faking it.
--
-- WHY THE PREVIEW USES THE SHARED ForgeMath, AND WHY THAT IS THE WHOLE POINT
-- FR-3.4 says the maths is public by design: players optimise openly. That
-- promise is only kept if the preview and the payout are the SAME maths. So this
-- file computes nothing itself -- it calls `ForgeMath.landingProbabilities`,
-- `ForgeMath.faceValue`, `ForgeMath.expectedValue` and `ForgeMath.voidProbability`
-- on the exact array it is about to send, and the server calls the same pure
-- functions on the array it receives. There is no second implementation to drift.
-- Re-deriving `mass^2` or `(M-m)/(M(n-1))` here would silently break that promise
-- the first time ALPHA is retuned, so it is not done anywhere in this file.
--
-- THE ONE NUMBER THIS FILE CANNOT SHARE: the forge COST. `ForgeService` is a
-- server module and cannot be required from the client, so `estimateCost` below
-- MIRRORS `ForgeService.computeForgeCost` rather than calling it. It is therefore
-- labelled an estimate ("~") in the UI and is never treated as truth: the panel
-- re-renders from the server's `ForgeResult`, never from its own optimism. See
-- the note on `estimateCost` for the change that would remove the duplication.
--
-- ZERO-SUM BY CONSTRUCTION. The player cannot submit a total that differs from
-- the budget, because there is no control that changes the total. Every edit
-- MOVES mass: adding to a face draws it from the others in proportion to their
-- headroom above the shape's floor, and removing from a face spreads it to the
-- others. After every edit the draft is snapped and its residual folded back, so
-- the array that reaches the wire sums to the server-held budget exactly.
--
-- AUTHORITY. The server decides. The draft is a PROPOSAL; the rendered "server"
-- column is the truth. A refusal -- throttled, unaffordable, or rejected by the
-- die invariant -- discards the draft and re-renders the unchanged server state.
--
-- BOUNDARY. Every message leaves through NetClient. No Remote is touched here,
-- and nothing outbound carries a price, balance or amount (NFR-5): this file
-- sends a distribution and ids, and the server prices the move.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))
local Format = require(Shared:WaitForChild("Format"))

local UITheme = require(script.Parent:WaitForChild("UITheme"))

local ForgePanel = {}

--------------------------------------------------------------------------------
-- The NetClient surface this module uses, declared structurally.
--
-- NetClient arrives as an argument to `init` rather than being required, so the
-- boundary is visible in the signature: this module cannot reach the network
-- except through what it was handed. Typing it structurally keeps that honest --
-- adding a call means widening this type, which is a diff a reviewer sees.
--------------------------------------------------------------------------------

type Result = { ok: boolean, reason: string? }

export type Net = {
	forge: (number, { number }) -> Result,
	setElement: (number, number, string) -> Result,
	setShape: (number, string) -> Result,
	onForgeResult: ((any) -> ()) -> RBXScriptConnection,
	onStateSync: ((any) -> ()) -> RBXScriptConnection,
}

--------------------------------------------------------------------------------
-- Pool sizes. Every instance this panel will ever need is built once, at init,
-- and thereafter only has its properties written (NFR-1). Nothing in this file
-- allocates on a frame boundary -- there is no per-frame loop at all; rendering
-- is driven by StateSync, ForgeResult and input.
--------------------------------------------------------------------------------

local MAX_FACES = 20        -- D20, the widest shape in DiceCatalog
local MAX_DIE_TABS = 8      -- 5 base slots, 7 with the gamepass, plus slack

-- Mass moved per press. Cycled by the STEP button so a D4 at budget 40 and a D20
-- at budget 5000 are both editable without a thousand presses.
local STEPS: { number } = { 1, 5, 25, 100 }

--------------------------------------------------------------------------------
-- Server-state view. Parsed DEFENSIVELY from StateSync.
--
-- StateSync is `{ cash, gems, diamonds, dice, upgrades, streak, boosts,
-- serverTime }` (API_DATA_CONTRACT §1.2) and its `dice` entries mirror the
-- profile blueprint's die shape. It is still parsed field by field with type
-- checks rather than indexed straight into the UI: a malformed or partial
-- snapshot must render as "no state" and disable the controls, never as a panel
-- full of nils that lets a player press FORGE against a budget that does not
-- exist.
--------------------------------------------------------------------------------

type FaceView = { mass: number, element: string }
type DieView = { shape: string, budget: number, faces: { FaceView } }

type ServerView = {
	dice: { DieView },
	cash: number?,
	unlockedElements: { [string]: boolean },
	unlockedShapes: { [string]: boolean },
	received: boolean,
}

-- The profile template's starting entitlements. Used only when a snapshot does
-- not carry the unlocked sets, so the panel understates what is available rather
-- than inventing an unlock the server would refuse.
local function defaultUnlockedElements(): { [string]: boolean }
	return { None = true }
end

local function defaultUnlockedShapes(): { [string]: boolean }
	return { D6 = true }
end

local function readBooleanSet(source: any, fallback: { [string]: boolean }): { [string]: boolean }
	if type(source) ~= "table" then
		return fallback
	end
	local out: { [string]: boolean } = {}
	local found = false
	for key, value in pairs(source :: { [any]: any }) do
		if type(key) == "string" and value == true then
			out[key] = true
			found = true
		end
	end
	return if found then out else fallback
end

local function readDie(raw: any): DieView?
	if type(raw) ~= "table" then
		return nil
	end
	local shape = raw.Shape
	if type(shape) ~= "string" then
		return nil
	end
	local shapeDef = DiceCatalog.getShape(shape)
	if shapeDef == nil then
		return nil
	end
	local budget = raw.MassBudget
	if not ForgeMath.isFinite(budget) or (budget :: number) <= 0 then
		return nil
	end
	local rawFaces = raw.Faces
	if type(rawFaces) ~= "table" then
		return nil
	end

	local faces: { FaceView } = {}
	for i = 1, #(rawFaces :: { any }) do
		local rawFace = (rawFaces :: { any })[i]
		if type(rawFace) ~= "table" then
			return nil
		end
		if not ForgeMath.isFinite(rawFace.Mass) then
			return nil
		end
		local element = rawFace.Element
		if type(element) ~= "string" or not ElementCatalog.exists(element) then
			element = "None"
		end
		faces[i] = { mass = ForgeMath.snap(rawFace.Mass), element = element }
	end

	-- The face count must agree with the SHAPE, not merely be plausible. Editing a
	-- die whose array length disagrees with its shape would produce a proposal the
	-- server rejects as `wrong_face_count` on every single press, with no way for
	-- the player to tell why. `ForgeService.validateStoredDice` repairs such dice
	-- on join, so this is a belt-and-braces refusal rather than an expected path --
	-- and refusing it surfaces as an honest message instead of a dead FORGE button.
	if #faces ~= shapeDef.faceCount or #faces < 2 or #faces > MAX_FACES then
		return nil
	end
	return { shape = shape, budget = ForgeMath.snap(budget :: number), faces = faces }
end

local function readState(payload: any): ServerView
	local view: ServerView = {
		dice = {},
		cash = nil,
		unlockedElements = defaultUnlockedElements(),
		unlockedShapes = defaultUnlockedShapes(),
		received = false,
	}
	if type(payload) ~= "table" then
		return view
	end
	view.received = true

	if ForgeMath.isFinite(payload.cash) then
		view.cash = payload.cash :: number
	end

	local rawDice = payload.dice
	if type(rawDice) == "table" then
		for i = 1, #(rawDice :: { any }) do
			local die = readDie((rawDice :: { any })[i])
			if die ~= nil then
				view.dice[i] = die
			end
		end
	end

	-- Entitlements live under the permanent Diamond trees in the profile
	-- blueprint. If a snapshot omits them the defaults above apply, which shows
	-- MORE as locked than may truly be locked -- the safe direction, since the
	-- server refuses an unowned element or shape either way and the player is
	-- never shown a button that lies about working.
	local diamond = payload.diamond
	if type(diamond) == "table" then
		view.unlockedElements = readBooleanSet((diamond :: any).Elements, view.unlockedElements)
		view.unlockedShapes = readBooleanSet((diamond :: any).Shapes, view.unlockedShapes)
	end

	return view
end

--------------------------------------------------------------------------------
-- Cost mirror.
--
-- A DUPLICATE OF `ForgeService.computeForgeCost`, stated as such rather than
-- disguised. The client cannot require a server module, and FR-3.3 makes cost a
-- decision input the player must see before committing, so the formula exists
-- twice. The mitigation is that it is never authoritative: the number is prefixed
-- "~" in the UI, the server prices the move independently, and the panel takes
-- the real cost from `ForgeResult`.
--
-- The clean fix is to move BASE_COST_PER_MASS_UNIT / REFERENCE_BUDGET /
-- SCALE_EXPONENT and this function into `Shared/ForgeMath.luau` beside the rest
-- of the pure forge maths, so both sides call one definition exactly as they
-- already do for probability and value. That is a change to a shared file and is
-- reported to the orchestrator rather than made here.
--------------------------------------------------------------------------------

local BASE_COST_PER_MASS_UNIT = 5.0
local REFERENCE_BUDGET = 60.0
local SCALE_EXPONENT = 2.0

local function estimateCost(oldDist: { number }, newDist: { number }, budget: number): number
	if #oldDist ~= #newDist then
		return math.huge
	end
	local deltaSum = 0.0
	for i = 1, #oldDist do
		local d = math.abs(newDist[i] - oldDist[i])
		if not ForgeMath.isFinite(d) then
			return math.huge
		end
		deltaSum += d
	end
	if not ForgeMath.isFinite(budget) or budget <= 0 then
		return math.huge
	end
	local scale = (budget / REFERENCE_BUDGET) ^ SCALE_EXPONENT
	if not ForgeMath.isFinite(scale) or scale < 1.0 then
		scale = 1.0
	end
	local cost = deltaSum * BASE_COST_PER_MASS_UNIT * scale
	if not ForgeMath.isFinite(cost) then
		return math.huge
	end
	return ForgeMath.snap(cost)
end

--------------------------------------------------------------------------------
-- Zero-sum draft arithmetic.
--
-- These three functions are the reason the UI cannot submit an illegal total.
-- `normalise` is the invariant keeper: it snaps every face to ForgeMath.PRECISION
-- (the same precision the server snaps to, so the sum check on the far side sees
-- the same numbers), clamps each face to the floor, and folds the remaining
-- residual back onto a face that can legally absorb it.
--------------------------------------------------------------------------------

local function sumOf(dist: { number }): number
	local total = 0.0
	for i = 1, #dist do
		total += dist[i]
	end
	return total
end

local function normalise(dist: { number }, budget: number, floor: number, prefer: number): ()
	local n = #dist
	if n == 0 then
		return
	end
	for i = 1, n do
		local m = dist[i]
		if not ForgeMath.isFinite(m) then
			m = floor
		end
		m = ForgeMath.snap(m)
		if m < floor then
			m = floor
		end
		dist[i] = m
	end

	-- Bounded: each pass either finishes or strictly reduces the surplus on one
	-- face, and there are n faces. No unbounded `while` on floating point.
	local safePrefer = if prefer >= 1 and prefer <= n then prefer else 1
	for _ = 1, n + 1 do
		local residual = ForgeMath.snap(budget - sumOf(dist))
		if math.abs(residual) < 1e-9 then
			break
		end
		if residual > 0 then
			-- Always legal: raising a face can never breach the floor.
			dist[safePrefer] = ForgeMath.snap(dist[safePrefer] + residual)
			break
		end
		-- Over budget: take it off the heaviest face that has headroom, so the
		-- correction lands where it is least visible and never breaches a floor.
		local target = 0
		local heaviest = floor
		for i = 1, n do
			if dist[i] > heaviest then
				heaviest = dist[i]
				target = i
			end
		end
		if target == 0 then
			break
		end
		local take = math.min(-residual, dist[target] - floor)
		if take <= 0 then
			break
		end
		dist[target] = ForgeMath.snap(dist[target] - take)
	end
end

-- Returns ok, reason. `delta > 0` pulls mass ONTO face `index` from the others in
-- proportion to their headroom; `delta < 0` pushes mass off it, spread evenly.
-- Neither branch can change the total, which is why no "total" control exists.
local function moveMass(
	dist: { number },
	index: number,
	delta: number,
	budget: number,
	floor: number
): (boolean, string?)
	local n = #dist
	if n < 2 or index < 1 or index > n then
		return false, "NO DIE SELECTED"
	end

	if delta > 0 then
		local headroom = 0.0
		for j = 1, n do
			if j ~= index then
				local h = dist[j] - floor
				if h > 0 then
					headroom += h
				end
			end
		end
		if headroom <= 0 then
			return false, "EVERY OTHER FACE IS AT THE FLOOR"
		end
		local want = math.min(delta, headroom)
		for j = 1, n do
			if j ~= index then
				local h = dist[j] - floor
				if h > 0 then
					dist[j] -= want * (h / headroom)
				end
			end
		end
		dist[index] += want
		normalise(dist, budget, floor, index)
		return true, nil
	end

	local give = math.min(-delta, dist[index] - floor)
	if give <= 0 then
		return false, "THIS FACE IS AT THE MASS FLOOR"
	end
	dist[index] -= give
	local share = give / (n - 1)
	local spill = 1
	for j = 1, n do
		if j ~= index then
			dist[j] += share
			spill = j
		end
	end
	normalise(dist, budget, floor, spill)
	return true, nil
end

--------------------------------------------------------------------------------
-- Ordered catalog views.
--
-- `ElementCatalog.all()` is a dictionary, so iteration order is undefined and the
-- element strip would shuffle between sessions. The preferred order below is
-- filtered against the catalog and then any UNLISTED catalog id is appended, so
-- adding an element to the catalog surfaces it here instead of hiding it.
--------------------------------------------------------------------------------

local PREFERRED_ELEMENT_ORDER: { string } = { "None", "Fire", "Freeze", "Gold", "Multiplier" }

local function orderedElementIds(): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in ipairs(PREFERRED_ELEMENT_ORDER) do
		if ElementCatalog.exists(id) then
			table.insert(out, id)
			seen[id] = true
		end
	end
	local extra: { string } = {}
	for id in pairs(ElementCatalog.all()) do
		if not seen[id] then
			table.insert(extra, id)
		end
	end
	table.sort(extra)
	for _, id in ipairs(extra) do
		table.insert(out, id)
	end
	return out
end

local function elementAbbrev(id: string): string
	if id == "None" then
		return "-"
	end
	return string.upper(string.sub(id, 1, 2))
end

--------------------------------------------------------------------------------
-- Widget records
--------------------------------------------------------------------------------

type FaceRow = {
	-- The holder is kept on the record rather than reached through `root.Parent`,
	-- which is typed `Instance?` and would need a cast at every use.
	holder: Frame,
	root: TextButton,
	index: TextLabel,
	element: TextLabel,
	mass: TextLabel,
	value: TextLabel,
	probability: TextLabel,
	minus: TextButton,
	plus: TextButton,
}

type ElementButton = { button: TextButton, id: string }
type ShapeButton = { button: TextButton, id: string }

--------------------------------------------------------------------------------
-- Module state
--------------------------------------------------------------------------------

local net: Net? = nil
local initialised = false

local server: ServerView = {
	dice = {},
	cash = nil,
	unlockedElements = defaultUnlockedElements(),
	unlockedShapes = defaultUnlockedShapes(),
	received = false,
}

local selectedDie = 1
local selectedFace = 1
local stepIndex = 1
local submitting = false

-- The proposal, and the server masses it was seeded from. `baseline` is how an
-- unrelated StateSync (a roll crediting Cash, say) is told apart from one that
-- actually changed this die: the draft survives the former and is discarded by
-- the latter, so a player mid-edit is not reset every time they earn money.
local draft: { number } = {}
local baseline: { number } = {}
local draftDieIndex = 0

local root: Frame? = nil
local tabButton: TextButton? = nil

local dieTabs: { TextButton } = {}
local faceRows: { FaceRow } = {}
local elementButtons: { ElementButton } = {}
local shapeButtons: { ShapeButton } = {}

local titleLabel: TextLabel? = nil
local evValue: TextLabel? = nil
local voidValue: TextLabel? = nil
local budgetValue: TextLabel? = nil
local costValue: TextLabel? = nil
local elementHeading: TextLabel? = nil
local statusLabel: TextLabel? = nil
local stepButton: TextButton? = nil
local evenButton: TextButton? = nil
local resetButton: TextButton? = nil
local commitButton: TextButton? = nil

local render: () -> ()

--------------------------------------------------------------------------------
-- Draft lifecycle
--------------------------------------------------------------------------------

local function currentDie(): DieView?
	return server.dice[selectedDie]
end

local function distributionsEqual(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if math.abs(a[i] - b[i]) > ForgeMath.EPSILON then
			return false
		end
	end
	return true
end

local function seedDraft(): ()
	local die = currentDie()
	draft = {}
	baseline = {}
	draftDieIndex = selectedDie
	if die == nil then
		return
	end
	for i = 1, #die.faces do
		draft[i] = die.faces[i].mass
		baseline[i] = die.faces[i].mass
	end
	if selectedFace < 1 or selectedFace > #draft then
		selectedFace = 1
	end
end

local function setStatus(text: string, colour: Color3): ()
	if statusLabel then
		statusLabel.Text = text
		statusLabel.TextColor3 = colour
	end
end

-- The FORGE tab sits at the left edge of the arena and the open panel covers
-- that edge, so the two are mutually exclusive rather than stacked: FR-13.7
-- forbids overlap, and a tab peeking out from under its own panel is exactly
-- the kind of thing that reads as fine at 1080p and clips at 320px.
local function setPanelVisible(visible: boolean): ()
	if root then
		root.Visible = visible
	end
	if tabButton then
		tabButton.Visible = not visible
	end
end

--------------------------------------------------------------------------------
-- Construction. Runs ONCE. Everything below is Scale-based (FR-13.7, NFR-3);
-- the only pixel quantities in this file are UITheme's 1px borders.
--------------------------------------------------------------------------------

local function buildFaceRow(parent: Frame): FaceRow
	local row = UITheme.button("", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	row.Parent = parent

	local indexLabel = UITheme.label("F1", UDim2.fromScale(0.09, 0.7), UDim2.fromScale(0.005, 0.15))
	indexLabel.Parent = row

	local elementLabel = UITheme.label("-", UDim2.fromScale(0.09, 0.7), UDim2.fromScale(0.095, 0.15))
	elementLabel.TextXAlignment = Enum.TextXAlignment.Center
	elementLabel.Parent = row

	local massLabel = UITheme.label("0", UDim2.fromScale(0.185, 0.7), UDim2.fromScale(0.19, 0.15))
	massLabel.Parent = row

	local valueLabel = UITheme.label("0", UDim2.fromScale(0.185, 0.7), UDim2.fromScale(0.38, 0.15),
		UITheme.Colors.TextGold)
	valueLabel.Parent = row

	local probabilityLabel = UITheme.label("0%", UDim2.fromScale(0.17, 0.7), UDim2.fromScale(0.57, 0.15),
		UITheme.Colors.TextDim)
	probabilityLabel.Parent = row

	local minus = UITheme.button("-", UDim2.fromScale(0.11, 0.74), UDim2.fromScale(0.75, 0.13))
	minus.Parent = row

	local plus = UITheme.button("+", UDim2.fromScale(0.11, 0.74), UDim2.fromScale(0.875, 0.13))
	plus.Parent = row

	return {
		holder = parent,
		root = row,
		index = indexLabel,
		element = elementLabel,
		mass = massLabel,
		value = valueLabel,
		probability = probabilityLabel,
		minus = minus,
		plus = plus,
	}
end

local function buildInterface(target: PlayerGui): ()
	local screen = Instance.new("ScreenGui")
	screen.Name = "ForgePanel"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = UITheme.Layer.Panel
	screen.Enabled = true

	-- FR-13.8: ONE tap from the arena. Always on screen, never behind a menu.
	local tab = UITheme.button("FORGE", UDim2.fromScale(0.14, 0.07), UDim2.fromScale(0.006, 0.40))
	tab.Name = "ForgeTab"
	tab.Parent = screen
	tabButton = tab

	local panel = UITheme.panel(UDim2.fromScale(0.9, 0.86), UDim2.fromScale(0.05, 0.07))
	panel.Name = "ForgeRoot"
	panel.Visible = false
	panel.Parent = screen
	root = panel

	local title = UITheme.label("FORGE", UDim2.fromScale(0.5, 0.055), UDim2.fromScale(0.02, 0.012),
		UITheme.Colors.TextGold)
	title.Parent = panel
	titleLabel = title

	local close = UITheme.button("X", UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.93, 0.014))
	close.Parent = panel

	-- Die tabs
	for i = 1, MAX_DIE_TABS do
		local button = UITheme.button(
			"DIE " .. tostring(i),
			UDim2.fromScale(0.11, 0.05),
			UDim2.fromScale(0.02 + (i - 1) * 0.115, 0.085)
		)
		button.Visible = false
		button.Parent = panel
		dieTabs[i] = button
	end

	-- Faces column
	local facesPanel = UITheme.panel(UDim2.fromScale(0.56, 0.70), UDim2.fromScale(0.02, 0.155), true)
	facesPanel.Parent = panel

	local header = UITheme.label(
		"FACE   EL    MASS      VALUE     P(LAND)",
		UDim2.fromScale(0.72, 0.05),
		UDim2.fromScale(0.01, 0.012),
		UITheme.Colors.TextDim
	)
	header.Parent = facesPanel

	for i = 1, MAX_FACES do
		local holder = Instance.new("Frame")
		holder.Name = "FaceRow" .. tostring(i)
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.fromScale(0.97, 0.05)
		holder.Position = UDim2.fromScale(0.015, 0.08)
		holder.Visible = false
		holder.Parent = facesPanel
		faceRows[i] = buildFaceRow(holder)
	end

	-- Readouts and controls
	local sidePanel = UITheme.panel(UDim2.fromScale(0.38, 0.70), UDim2.fromScale(0.60, 0.155), true)
	sidePanel.Parent = panel

	local evCaption = UITheme.label("EXPECTED VALUE / ROLL", UDim2.fromScale(0.94, 0.045),
		UDim2.fromScale(0.03, 0.02), UITheme.Colors.TextDim)
	evCaption.Parent = sidePanel
	local ev = UITheme.label("--", UDim2.fromScale(0.94, 0.07), UDim2.fromScale(0.03, 0.07),
		UITheme.Colors.TextGold)
	ev.Parent = sidePanel
	evValue = ev

	local voidCaption = UITheme.label("VOID PROBABILITY", UDim2.fromScale(0.94, 0.045),
		UDim2.fromScale(0.03, 0.155), UITheme.Colors.TextDim)
	voidCaption.Parent = sidePanel
	local voidReadout = UITheme.label("--", UDim2.fromScale(0.94, 0.07), UDim2.fromScale(0.03, 0.205),
		UITheme.Colors.VoidFace)
	voidReadout.Parent = sidePanel
	voidValue = voidReadout

	local budgetCaption = UITheme.label("MASS BUDGET (FIXED)", UDim2.fromScale(0.94, 0.045),
		UDim2.fromScale(0.03, 0.295), UITheme.Colors.TextDim)
	budgetCaption.Parent = sidePanel
	local budget = UITheme.label("--", UDim2.fromScale(0.94, 0.06), UDim2.fromScale(0.03, 0.345))
	budget.Parent = sidePanel
	budgetValue = budget

	local costCaption = UITheme.label("FORGE COST (SERVER PRICES IT)", UDim2.fromScale(0.94, 0.045),
		UDim2.fromScale(0.03, 0.42), UITheme.Colors.TextDim)
	costCaption.Parent = sidePanel
	local cost = UITheme.label("--", UDim2.fromScale(0.94, 0.06), UDim2.fromScale(0.03, 0.47),
		UITheme.Colors.Cash)
	cost.Parent = sidePanel
	costValue = cost

	local elementCaption = UITheme.label("ELEMENT - FACE 1", UDim2.fromScale(0.94, 0.045),
		UDim2.fromScale(0.03, 0.555), UITheme.Colors.TextDim)
	elementCaption.Parent = sidePanel
	elementHeading = elementCaption

	local ids = orderedElementIds()
	for i, id in ipairs(ids) do
		local column = (i - 1) % 3
		local rowIndex = math.floor((i - 1) / 3)
		local button = UITheme.button(
			id,
			UDim2.fromScale(0.30, 0.065),
			UDim2.fromScale(0.03 + column * 0.325, 0.605 + rowIndex * 0.075)
		)
		button.Parent = sidePanel
		elementButtons[i] = { button = button, id = id }
	end

	local shapeCaption = UITheme.label("SHAPE (FREELY REVERSIBLE)", UDim2.fromScale(0.94, 0.045),
		UDim2.fromScale(0.03, 0.755), UITheme.Colors.TextDim)
	shapeCaption.Parent = sidePanel

	-- Same 3-wide grid as the elements rather than five buttons in one row: a
	-- fifth-of-a-panel button cannot legibly say "D12 LOCKED", and shrinking the
	-- word until it fits is how a locked control ends up looking available.
	local shapes = DiceCatalog.getAllShapes()
	for i, shape in ipairs(shapes) do
		local column = (i - 1) % 3
		local rowIndex = math.floor((i - 1) / 3)
		local button = UITheme.button(
			shape.id,
			UDim2.fromScale(0.30, 0.065),
			UDim2.fromScale(0.03 + column * 0.325, 0.805 + rowIndex * 0.075)
		)
		button.Parent = sidePanel
		shapeButtons[i] = { button = button, id = shape.id }
	end

	-- Footer
	local status = UITheme.label("AWAITING SERVER STATE", UDim2.fromScale(0.44, 0.055),
		UDim2.fromScale(0.02, 0.875), UITheme.Colors.TextDim)
	status.Parent = panel
	statusLabel = status

	local even = UITheme.button("EVEN", UDim2.fromScale(0.10, 0.06), UDim2.fromScale(0.47, 0.873))
	even.Parent = panel
	evenButton = even

	local step = UITheme.button("STEP 1", UDim2.fromScale(0.11, 0.06), UDim2.fromScale(0.58, 0.873))
	step.Parent = panel
	stepButton = step

	local reset = UITheme.button("REVERT", UDim2.fromScale(0.10, 0.06), UDim2.fromScale(0.70, 0.873))
	reset.Parent = panel
	resetButton = reset

	local commit = UITheme.button("FORGE", UDim2.fromScale(0.16, 0.06), UDim2.fromScale(0.81, 0.873))
	commit.Parent = panel
	commitButton = commit

	screen.Parent = target

	--------------------------------------------------------------------------
	-- Input. Connected once, at build time.
	--------------------------------------------------------------------------

	tab.Activated:Connect(function()
		setPanelVisible(true)
		render()
	end)

	close.Activated:Connect(function()
		setPanelVisible(false)
	end)

	for i = 1, MAX_DIE_TABS do
		local index = i
		dieTabs[i].Activated:Connect(function()
			if server.dice[index] == nil or index == selectedDie then
				return
			end
			selectedDie = index
			selectedFace = 1
			seedDraft()
			setStatus("DIE " .. tostring(index) .. " SELECTED", UITheme.Colors.TextDim)
			render()
		end)
	end

	for i = 1, MAX_FACES do
		local index = i
		local row = faceRows[i]

		row.root.Activated:Connect(function()
			if draft[index] == nil then
				return
			end
			selectedFace = index
			render()
		end)

		row.minus.Activated:Connect(function()
			local die = currentDie()
			if die == nil or draft[index] == nil then
				return
			end
			selectedFace = index
			local floor = DiceCatalog.getMassFloor(die.shape)
			local ok, reason = moveMass(draft, index, -STEPS[stepIndex], die.budget, floor)
			if not ok then
				setStatus(reason or "REFUSED", UITheme.Colors.Negative)
			else
				setStatus("MASS MOVED - NOT YET COMMITTED", UITheme.Colors.TextDim)
			end
			render()
		end)

		row.plus.Activated:Connect(function()
			local die = currentDie()
			if die == nil or draft[index] == nil then
				return
			end
			selectedFace = index
			local floor = DiceCatalog.getMassFloor(die.shape)
			local ok, reason = moveMass(draft, index, STEPS[stepIndex], die.budget, floor)
			if not ok then
				setStatus(reason or "REFUSED", UITheme.Colors.Negative)
			else
				setStatus("MASS MOVED - NOT YET COMMITTED", UITheme.Colors.TextDim)
			end
			render()
		end)
	end

	for _, entry in ipairs(elementButtons) do
		local id = entry.id
		entry.button.Activated:Connect(function()
			local client = net
			local die = currentDie()
			if client == nil or die == nil or submitting then
				return
			end
			if not server.unlockedElements[id] then
				-- Shown as locked and REFUSED as locked. Never quietly no-ops.
				setStatus(string.upper(id) .. " IS LOCKED - UNLOCK IT IN THE DIAMOND TREE",
					UITheme.Colors.Negative)
				return
			end
			if die.faces[selectedFace] == nil then
				return
			end
			submitting = true
			local result = client.setElement(selectedDie, selectedFace, id)
			submitting = false
			if result.ok then
				setStatus("ELEMENT SENT - AWAITING SERVER", UITheme.Colors.Positive)
			else
				setStatus("REFUSED: " .. string.upper(result.reason or "UNKNOWN"),
					UITheme.Colors.Negative)
			end
			render()
		end)
	end

	for _, entry in ipairs(shapeButtons) do
		local id = entry.id
		entry.button.Activated:Connect(function()
			local client = net
			local die = currentDie()
			if client == nil or die == nil or submitting then
				return
			end
			if not server.unlockedShapes[id] then
				setStatus(id .. " IS LOCKED - UNLOCK IT IN THE DIAMOND TREE",
					UITheme.Colors.Negative)
				return
			end
			if die.shape == id then
				setStatus(id .. " IS ALREADY EQUIPPED", UITheme.Colors.TextDim)
				return
			end
			submitting = true
			local result = client.setShape(selectedDie, id)
			submitting = false
			if result.ok then
				setStatus("SHAPE SENT - MASS LAYOUT RESETS", UITheme.Colors.Positive)
			else
				setStatus("REFUSED: " .. string.upper(result.reason or "UNKNOWN"),
					UITheme.Colors.Negative)
			end
			render()
		end)
	end

	step.Activated:Connect(function()
		stepIndex = (stepIndex % #STEPS) + 1
		render()
	end)

	even.Activated:Connect(function()
		local die = currentDie()
		if die == nil or #draft == 0 then
			return
		end
		local floor = DiceCatalog.getMassFloor(die.shape)
		-- snapDOWN, never snap: rounding each share to NEAREST rounds up half the
		-- time and the shares then sum to MORE than the budget (F-AD-4). The
		-- residual is folded back by `normalise`.
		local share = ForgeMath.snapDown(die.budget / #draft)
		if share < floor then
			share = floor
		end
		for i = 1, #draft do
			draft[i] = share
		end
		normalise(draft, die.budget, floor, 1)
		setStatus("EVENLY SPREAD - NOT YET COMMITTED", UITheme.Colors.TextDim)
		render()
	end)

	reset.Activated:Connect(function()
		seedDraft()
		setStatus("REVERTED TO THE SERVER'S DIE", UITheme.Colors.TextDim)
		render()
	end)

	commit.Activated:Connect(function()
		local client = net
		local die = currentDie()
		if client == nil or die == nil or submitting then
			return
		end
		if distributionsEqual(draft, baseline) then
			setStatus("NOTHING TO FORGE - THE LAYOUT IS UNCHANGED", UITheme.Colors.TextDim)
			return
		end

		-- Structural pre-flight with the SAME validator the server runs. This is
		-- a courtesy that saves a round trip; it grants nothing, because the
		-- server re-validates against its own stored budget regardless.
		local floor = DiceCatalog.getMassFloor(die.shape)
		local valid, reason = ForgeMath.validate(draft, #draft, die.budget, floor)
		if not valid then
			setStatus("PROPOSAL INVALID: " .. string.upper(reason or "UNKNOWN"),
				UITheme.Colors.Negative)
			seedDraft()
			render()
			return
		end

		local proposal: { number } = table.create(#draft, 0)
		for i = 1, #draft do
			proposal[i] = draft[i]
		end

		submitting = true
		local result = client.forge(selectedDie, proposal)
		submitting = false

		if result.ok then
			setStatus("FORGED - AWAITING THE SERVER'S CONFIRMATION", UITheme.Colors.Positive)
		else
			-- The proposal died. Show the SERVER's die, not the one that failed.
			setStatus("REFUSED: " .. string.upper(result.reason or "UNKNOWN"),
				UITheme.Colors.Negative)
			seedDraft()
		end
		render()
	end)
end

--------------------------------------------------------------------------------
-- Render. Property writes only -- no instance is created past `buildInterface`.
--------------------------------------------------------------------------------

local function renderEmpty(): ()
	for i = 1, MAX_FACES do
		faceRows[i].holder.Visible = false
	end
	for i = 1, MAX_DIE_TABS do
		dieTabs[i].Visible = false
	end
	if titleLabel then
		titleLabel.Text = "FORGE"
	end
	if evValue then
		evValue.Text = "--"
	end
	if voidValue then
		voidValue.Text = "--"
	end
	if budgetValue then
		budgetValue.Text = "--"
	end
	if costValue then
		costValue.Text = "--"
	end
	for _, entry in ipairs(elementButtons) do
		UITheme.setEnabled(entry.button, false)
	end
	for _, entry in ipairs(shapeButtons) do
		UITheme.setEnabled(entry.button, false)
	end
	if commitButton then
		UITheme.setEnabled(commitButton, false)
	end
	if evenButton then
		UITheme.setEnabled(evenButton, false)
	end
	if resetButton then
		UITheme.setEnabled(resetButton, false)
	end
end

render = function(): ()
	if root == nil or not root.Visible then
		return
	end

	if stepButton then
		stepButton.Text = "STEP " .. tostring(STEPS[stepIndex])
	end

	local die = currentDie()
	if die == nil or #draft == 0 then
		renderEmpty()
		if not server.received then
			setStatus("AWAITING SERVER STATE", UITheme.Colors.TextDim)
		else
			-- Received a snapshot and still have no editable die. Say so plainly
			-- rather than showing an empty forge that looks merely slow.
			setStatus("NO VALID DIE IN THE SERVER'S SNAPSHOT", UITheme.Colors.Negative)
		end
		return
	end

	local floor = DiceCatalog.getMassFloor(die.shape)
	local faceCount = #draft

	-- Die tabs
	for i = 1, MAX_DIE_TABS do
		local button = dieTabs[i]
		local present = server.dice[i] ~= nil
		button.Visible = present
		if present then
			UITheme.setEnabled(button, i == selectedDie)
		end
	end

	if titleLabel then
		titleLabel.Text = string.format("FORGE - DIE %d - %s", selectedDie, die.shape)
	end

	-- THE PREVIEW. Every number below comes from the shared ForgeMath, evaluated
	-- on the exact array that would be sent. No local arithmetic on masses.
	local probabilities = ForgeMath.landingProbabilities(draft)
	local expected = ForgeMath.expectedValue(draft)
	local voidChance = ForgeMath.voidProbability(draft, floor)

	for i = 1, MAX_FACES do
		local row = faceRows[i]
		local holder = row.holder
		if i > faceCount then
			holder.Visible = false
			continue
		end

		local slotHeight = 0.90 / faceCount
		holder.Size = UDim2.fromScale(0.97, slotHeight * 0.88)
		holder.Position = UDim2.fromScale(0.015, 0.08 + (i - 1) * slotHeight)
		holder.Visible = true

		local mass = draft[i]
		local element = if die.faces[i] ~= nil then die.faces[i].element else "None"
		local atFloor = mass <= floor + ForgeMath.EPSILON

		UITheme.setEnabled(row.root, i == selectedFace)
		row.index.Text = "F" .. tostring(i)
		row.index.TextColor3 = if i == selectedFace
			then UITheme.Colors.TextGold
			else UITheme.Colors.TextPrimary
		row.element.Text = elementAbbrev(element)
		row.element.TextColor3 = UITheme.elementColor(element)
		row.mass.Text = Format.formatNumber(mass)
		-- FR-3.5: a face at the floor is a VOID face and is coloured as one.
		row.mass.TextColor3 = if atFloor then UITheme.Colors.VoidFace else UITheme.Colors.TextPrimary
		row.value.Text = Format.formatNumber(ForgeMath.faceValue(mass))
		row.probability.Text = string.format("%.1f%%", probabilities[i] * 100)
	end

	if evValue then
		evValue.Text = Format.formatNumber(expected)
	end
	if voidValue then
		voidValue.Text = string.format("%.1f%%", voidChance * 100)
	end
	if budgetValue then
		budgetValue.Text = string.format("%s / %s",
			Format.formatNumber(ForgeMath.snap(sumOf(draft))),
			Format.formatNumber(die.budget))
	end

	local cost = estimateCost(baseline, draft, die.budget)
	local dirty = not distributionsEqual(draft, baseline)
	local affordable = true
	if costValue then
		if not dirty then
			costValue.Text = "0"
			costValue.TextColor3 = UITheme.Colors.TextDim
		elseif not ForgeMath.isFinite(cost) then
			costValue.Text = "UNPRICEABLE"
			costValue.TextColor3 = UITheme.Colors.Negative
			affordable = false
		else
			costValue.Text = "~" .. Format.formatNumber(cost)
			local cash = server.cash
			affordable = cash == nil or cash >= cost
			costValue.TextColor3 = if affordable then UITheme.Colors.Cash else UITheme.Colors.Negative
		end
	end

	if commitButton then
		UITheme.setEnabled(commitButton, dirty and affordable)
	end
	if evenButton then
		UITheme.setEnabled(evenButton, true)
	end
	if resetButton then
		-- REVERT is only meaningful while there is an uncommitted edit to revert.
		UITheme.setEnabled(resetButton, dirty)
	end

	-- Elements. Locked entries are SHOWN and marked, never hidden and never
	-- presented as working (swarm rule 5).
	if elementHeading then
		elementHeading.Text = string.format("ELEMENT - FACE %d", selectedFace)
	end
	local currentElement = if die.faces[selectedFace] ~= nil
		then die.faces[selectedFace].element
		else "None"
	for _, entry in ipairs(elementButtons) do
		local unlocked = server.unlockedElements[entry.id] == true
		local equipped = entry.id == currentElement
		local suffix = if not unlocked then " [LOCKED]" elseif equipped then " *" else ""
		entry.button.Text = entry.id .. suffix
		UITheme.setEnabled(entry.button, unlocked)
	end

	for _, entry in ipairs(shapeButtons) do
		local unlocked = server.unlockedShapes[entry.id] == true
		local equipped = entry.id == die.shape
		entry.button.Text = if not unlocked
			then entry.id .. " [LOCKED]"
			elseif equipped then "[" .. entry.id .. "]"
			else entry.id
		UITheme.setEnabled(entry.button, unlocked and not equipped)
	end
end

--------------------------------------------------------------------------------
-- Authoritative inbound
--------------------------------------------------------------------------------

local function onStateSync(payload: any): ()
	local view = readState(payload)
	if not view.received then
		return
	end
	server = view

	if server.dice[selectedDie] == nil then
		selectedDie = 1
		while server.dice[selectedDie] == nil and selectedDie < MAX_DIE_TABS do
			selectedDie += 1
		end
	end

	local die = currentDie()
	if die == nil then
		draft = {}
		baseline = {}
		render()
		return
	end

	-- Keep an in-progress edit alive across a snapshot that did not touch this
	-- die -- rolling credits Cash and re-syncs constantly, and wiping the
	-- player's half-finished layout each time would make the forge unusable.
	local serverMasses: { number } = table.create(#die.faces, 0)
	for i = 1, #die.faces do
		serverMasses[i] = die.faces[i].mass
	end

	if draftDieIndex ~= selectedDie or not distributionsEqual(serverMasses, baseline) then
		seedDraft()
	end
	render()
end

local function onForgeResult(payload: any): ()
	if type(payload) ~= "table" then
		return
	end
	local index = payload.dieIndex
	if type(index) == "number" and index ~= selectedDie and server.dice[index] ~= nil then
		selectedDie = index
	end

	if payload.ok == true then
		local distribution = payload.distribution
		local die = currentDie()
		if die ~= nil and type(distribution) == "table" then
			local incoming = distribution :: { any }
			if #incoming == #die.faces then
				for i = 1, #incoming do
					if ForgeMath.isFinite(incoming[i]) then
						die.faces[i].mass = ForgeMath.snap(incoming[i] :: number)
					end
				end
			end
		end
		seedDraft()
		local cost = payload.cost
		if ForgeMath.isFinite(cost) then
			setStatus("FORGED - COST " .. Format.formatNumber(cost :: number), UITheme.Colors.Positive)
		else
			setStatus("FORGED", UITheme.Colors.Positive)
		end
	else
		-- Rejected: the draft is discarded and the SERVER's die is what shows.
		seedDraft()
		local reason = payload.reason
		setStatus("REFUSED: " .. string.upper(if type(reason) == "string" then reason else "UNKNOWN"),
			UITheme.Colors.Negative)
	end
	render()
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

-- Lets another surface (the left sidebar, FR-13.3) open the forge without
-- duplicating the panel. Exposed so MenuPanel never needs to build its own.
function ForgePanel.setVisible(visible: boolean): ()
	if root == nil then
		return
	end
	setPanelVisible(visible)
	if visible then
		render()
	end
end

function ForgePanel.isVisible(): boolean
	return root ~= nil and root.Visible
end

function ForgePanel.init(client: Net): ()
	if initialised then
		return
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		error("[ForgePanel] no LocalPlayer -- this is a client surface", 2)
	end
	local playerGui = (localPlayer :: Player):WaitForChild("PlayerGui") :: PlayerGui

	net = client
	buildInterface(playerGui)
	initialised = true

	client.onStateSync(onStateSync)
	client.onForgeResult(onForgeResult)
end

return ForgePanel
