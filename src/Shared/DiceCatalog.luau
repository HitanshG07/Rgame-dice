--!strict
-- DiceCatalog.luau
-- Shape definitions for D4, D6, D8, D12, D20: face counts, per-shape mass floors,
-- budget caps, and native volatility characteristics. (SRS FR-6.1, FR-3.6)

local DiceCatalog = {}

export type ShapeDef = {
	id: string,
	faceCount: number,
	massFloor: number,
	defaultBudget: number,
	cashBudgetCap: number,
	diamondCeiling: number,
}

-- ON THE MASS FLOORS, stated plainly rather than left to look deliberate:
-- every shape currently carries the SAME floor of 1. The structure is per-shape
-- because the floor is per-shape data and RollService must not hold a second
-- copy of it, but the VALUES are uniform on purpose -- a uniform floor is the
-- neutral prior, and differentiating them is a balance decision that changes
-- Void probability and therefore the sniper/grinder crossover.
--
-- FR-6.3's crossover HAS now been verified numerically; see the budget note
-- immediately below for the sweep and its result.
--
-- THE BUDGET IS SHAPE-INDEPENDENT, and this is the single most important
-- balance constant in the game.
--
-- MEASURED DEFECT, 2026-08-11. These were per-shape and scaled with face count
-- (D2 = 20 ... D20 = 200, a flat 10 per face). Because payout is superlinear in
-- mass (FR-2.4, alpha = 2), more budget is STRICTLY better -- so the D20 simply
-- had ten times the mass of the D2 and won at every Streak Strength. A sweep
-- over b in {0, 0.02, 0.05, 0.10, 0.15, 0.20, 0.30, 0.50} returned D20 eight
-- times out of eight. That is FR-6.3 violated outright: "a build where one shape
-- wins at every b is a balance defect."
--
-- It was never caught because it cannot be seen by inspection -- each row looked
-- individually reasonable, and the file's own header said the numbers were
-- provisional pending a sweep that had not been run.
--
-- WITH A SHARED BUDGET the crossover FR-6.2 describes appears immediately, and
-- it appears for the right reason: shapes now differ ONLY in how many faces the
-- same mass is spread across.
--
--   b <= 0.05   D3 wins    EV ~450     Void 0.492   the volatile sniper
--   b >= 0.10   D20 wins   EV 527+     Void 0.052   the steady grinder
--
-- That is the sniper/grinder fork the whole design rests on (ledger L-016), and
-- the measured Void range 0.49 -> 0.05 brackets the SRS's predicted 0.33 -> 0.05.
--
-- CHANGING THESE THREE NUMBERS RE-OPENS FR-6.3. Re-run the sweep after any edit.
local SHARED_DEFAULT_BUDGET = 60
local SHARED_CASH_CAP = 300
local SHARED_DIAMOND_CEILING = 1500

local SHAPES: { [string]: ShapeDef } = {
	D2 = {
		id = "D2",
		faceCount = 2,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D3 = {
		id = "D3",
		faceCount = 3,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D4 = {
		id = "D4",
		faceCount = 4,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D5 = {
		id = "D5",
		faceCount = 5,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D6 = {
		id = "D6",
		faceCount = 6,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D7 = {
		id = "D7",
		faceCount = 7,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D8 = {
		id = "D8",
		faceCount = 8,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D10 = {
		id = "D10",
		faceCount = 10,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D12 = {
		id = "D12",
		faceCount = 12,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D14 = {
		id = "D14",
		faceCount = 14,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D16 = {
		id = "D16",
		faceCount = 16,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
	D20 = {
		id = "D20",
		faceCount = 20,
		massFloor = 1,
		defaultBudget = SHARED_DEFAULT_BUDGET,
		cashBudgetCap = SHARED_CASH_CAP,
		diamondCeiling = SHARED_DIAMOND_CEILING,
	},
}

local DEFAULT_MASS_FLOOR = 1
DiceCatalog.DEFAULT_MASS_FLOOR = DEFAULT_MASS_FLOOR

function DiceCatalog.getShape(shapeId: string): ShapeDef?
	return SHAPES[shapeId]
end

function DiceCatalog.getFaceCount(shapeId: string): number?
	local shape = SHAPES[shapeId]
	return if shape then shape.faceCount else nil
end

function DiceCatalog.getMassFloor(shapeId: string): number
	local shape = SHAPES[shapeId]
	return if shape then shape.massFloor else DEFAULT_MASS_FLOOR
end

-- The highest budget ANY shape can hold. `PurchasedBudget` is shape-independent
-- -- a player who buys up to D20's ceiling keeps that entitlement when they
-- switch to a D4, where it is merely capped for as long as they stay. So the
-- absolute bound on what may be owned is the maximum ceiling across all shapes,
-- while the bound on what is USABLE right now is this shape's own ceiling.
-- Block 3 Gate 3 round 3, finding F-AD-5: the die invariant had no upper bound
-- on PurchasedBudget at all, and `diamondCeiling` was declared here and read
-- nowhere.
function DiceCatalog.maxDiamondCeiling(): number
	local highest = 0
	for _, shape in pairs(SHAPES) do
		if shape.diamondCeiling > highest then
			highest = shape.diamondCeiling
		end
	end
	return highest
end

function DiceCatalog.getAllShapes(): { ShapeDef }
	local list: { ShapeDef } = {}
	for _, shape in pairs(SHAPES) do
		table.insert(list, shape)
	end
	table.sort(list, function(a: ShapeDef, b: ShapeDef)
		return a.faceCount < b.faceCount
	end)
	return list
end

--------------------------------------------------------------------------------
-- THE UNLOCK LADDER (operator-directed 2026-08-11)
--
-- A new player starts on the D2 and works up. Shapes unlock IN ORDER: the D8 is
-- not purchasable until the D6 is owned, and so on to the D20.
--
-- HOW THIS RECONCILES WITH FR-6.1, WHICH SAYS SHAPES ARE "A BUILD CHOICE, NEVER
-- A TIER LADDER". Read carefully those are two different claims, and both hold
-- here:
--
--   THE UNLOCK IS A LADDER. You progress through the shapes in sequence, which
--   is what gives a new player a comprehensible first goal instead of eight
--   simultaneous options they cannot evaluate. This is the operator's change.
--
--   THE CHOICE IS STILL FREE. Once unlocked, a shape is never taken away and
--   switching between ANY owned shapes costs the same and is fully reversible.
--   A player who owns up to the D20 may roll a D2 forever if that suits their
--   Streak Strength -- and at low `b` it genuinely does.
--
-- So the ladder controls WHEN a shape becomes available, never whether it stays
-- viable. FR-6.3's requirement -- that no shape dominate at every `b` -- is
-- untouched by this and is still verified by the P-6B sweep, not by inspection.
--
-- THE HONEST CAVEAT: a ladder does imply "later means better" to most players,
-- and if the balance sweep confirms the intended crossover then that implication
-- is FALSE for this game. The UI must therefore present later shapes as
-- DIFFERENT rather than STRONGER, or the ladder will teach players a wrong
-- model of their own build.
local UNLOCK_ORDER: { string } = { "D2", "D3", "D4", "D5", "D6", "D7", "D8", "D10", "D12", "D14", "D16", "D20" }

DiceCatalog.STARTING_SHAPE = "D2"

-- CASH cost to unlock each shape (operator-directed 2026-08-11: "as the user
-- unlocks more dice with money").
--
-- WHY CASH AND NOT DIAMONDS. Diamonds are the PRESTIGE currency -- they arrive
-- only after an ascension, so a Diamond-priced ladder would be invisible to a
-- player during their entire first run. That is the run where the ladder has to
-- do its work: it is the new player's first goal. Cash is what they are already
-- earning every roll, so each rung reads as something to save toward.
--
-- The curve is roughly 4x per rung. Steep enough that a rung is an event, flat
-- enough that the next one is always visible from the current one. These are a
-- FIRST PASS and unvalidated against real earn rates -- the honest place to tune
-- them is a playtest, not this table.
local UNLOCK_COST: { [string]: number } = {
	D2 = 0,        -- owned from the start; listed so every shape has an entry
	D3 = 500,
	D4 = 2500,
	D5 = 6000,
	D6 = 12000,
	D7 = 25000,
	D8 = 55000,
	D10 = 240000,
	D12 = 1000000,
	D14 = 2200000,
	D16 = 3200000,
	D20 = 4200000,
}

-- Which currency the ladder is priced in. Named here rather than assumed at each
-- call site so the server, the shop UI and the tests cannot disagree.
DiceCatalog.UNLOCK_CURRENCY = "Cash"

-- SRS FR-6.1: "A shape change costs Prestige Diamonds and is freely reversible."
-- "Freely reversible" means the player may switch back and forth without losing
-- purchased progression -- NOT that switching is free of charge.
--
-- MOVED HERE FROM ForgeService (2026-08-11) so the client can DISPLAY it.
-- It was a server-side local, so the shape panel showed a bare "USE" button with
-- no price on it: a player pressed it, five Diamonds they did not have were
-- required, the server refused, and NOTHING happened on screen. The value is
-- unchanged at 5 -- this move must not retune the economy, only let the UI tell
-- the truth about it. The server still owns the charge; the client only reads
-- this to render a label and grey a button, and never sends a price (NFR-5).
DiceCatalog.SHAPE_CHANGE_DIAMOND_COST = 5

-- A FRESH DIE AT ITS SHAPE'S DEFAULT BUDGET, evenly spread.
--
-- WHY THIS EXISTS. Three places built a starting die by hand and all three
-- hardcoded `Shape = "D6"` with six 10-mass faces: the profile template, the
-- AddDieSlot handler, and the ascension reset. The starting shape became D2 on
-- 2026-08-11 and only the template was updated, so buying a die slot or
-- ascending handed the player a D6 -- a shape they may not own and cannot
-- legally switch away from for free, several rungs up a ladder they were
-- supposed to climb. Nothing errored: `SetShape` reads ownership, and a die
-- placed directly into the profile never passes through it.
--
-- The even split is the neutral layout and matches what `performSetShape` does
-- for the same reason: mass placement is the player's decision, and a reset
-- should not make it for them.
function DiceCatalog.newDie(shapeId: string): { Shape: string, MassBudget: number, PurchasedBudget: number, Faces: { { Mass: number, Element: string } } }?
	local shape = SHAPES[shapeId]
	if shape == nil then
		return nil
	end
	-- snapDown for the same reason performSetShape does it: rounding each share
	-- to nearest rounds up half the time, and the faces would then sum to more
	-- than the budget the player owns.
	local per = math.floor((shape.defaultBudget / shape.faceCount) * 1000 + 1e-9) / 1000
	if per < shape.massFloor then
		per = shape.massFloor
	end
	local faces = {}
	for i = 1, shape.faceCount do
		faces[i] = { Mass = per, Element = "None" }
	end
	local budget = per * shape.faceCount
	return {
		Shape = shapeId,
		MassBudget = budget,
		PurchasedBudget = budget,
		Faces = faces,
	}
end

-- The die a new player starts with, and the die an ascension resets to.
function DiceCatalog.newStartingDie()
	return DiceCatalog.newDie(DiceCatalog.STARTING_SHAPE)
end

-- ASCENSION (FR-9.5). Shared so the ASCEND panel can show a REAL projection of
-- what a reset would pay, and the same threshold the server enforces.
--
-- The panel previously hardcoded "+450 Diamonds" regardless of the player's
-- actual lifetime cash -- a fabricated reward figure attached to the single most
-- destructive button in the game.
-- !! TEMPORARY TEST VALUE -- REVERT TO 1e6 BEFORE SHIPPING !!
--
-- RESTORED TO THE SHIPPING VALUE on 2026-08-15 at the operator's request, after
-- being held at 100_000 since 2026-08-12 so the ascension flow could be
-- exercised without grinding to $1M.
--
-- The test value could not ship: it lets a player ascend ten times sooner than
-- the economy was tuned for, inflating Diamond income by roughly 3x per unit of
-- cash, because the reward is sqrt-scaled and ten cheap ascensions beat one
-- expensive one.
DiceCatalog.ASCEND_MIN_LIFETIME_CASH = 1e6

-- Diamonds a reset would grant at a given lifetime cash. Sub-linear on purpose:
-- doubling a run's earnings does not double its prestige payout, so a player is
-- pushed to ascend rather than to grind one run forever.
function DiceCatalog.ascensionDiamonds(lifetimeCash: number): number
	if type(lifetimeCash) ~= "number" or lifetimeCash ~= lifetimeCash then
		return 0
	end
	if lifetimeCash < DiceCatalog.ASCEND_MIN_LIFETIME_CASH then
		return 0
	end
	local earned = math.floor((lifetimeCash / 1e6) ^ 0.5)
	if earned ~= earned or earned < 0 then
		return 0
	end
	-- AT LEAST ONE DIAMOND once the threshold is met.
	--
	-- The curve divides by 1e6 independently of the threshold, so any threshold
	-- below $1M produced `floor(sqrt(<1))` = 0 -- a player who had met the
	-- requirement was told they would earn nothing and the button stayed
	-- disabled. That was invisible while the two numbers happened to be equal,
	-- and it is a real edge case at the shipping value too: crossing $1M exactly
	-- must never grant zero for having qualified.
	return math.max(1, earned)
end

-- DIE SLOTS.
--
-- RAISED FROM 7 TO 12 on 2026-08-15 at the operator's request, and the old
-- comment here claiming 7 was "a hard engineering bound" was STALE -- it
-- described a renderer that no longer exists. Both constraints it named were
-- removed by the Route A rebuild: `BoardView` no longer holds precomputed
-- `LAYOUTS[count][index]` tables (it rejection-samples rest points with a
-- minimum-separation test) and `DiceRenderer` no longer pools a fixed seven
-- visuals (`ensureSlot` grows on demand). A comment asserting a constraint that
-- has since been engineered away is worse than no comment: it deters exactly
-- the change it no longer guards against.
--
-- 12 IS A BALANCE NUMBER, and the board is not the limit. `getDieRadius` shrinks
-- dice as 1/sqrt(count) past the curve, so total occupied felt is CONSTANT at
-- any count -- measured, the dice need ~75 square studs against ~412 available
-- at twelve. The binding constraint is legibility: at twelve the die radius is
-- 1.53 studs and a numeral still reads; far beyond that the dice become tokens.
--
-- The ascension ladder below now has nine rungs instead of four, which is the
-- point of raising it -- prestige had run out of slots to give back.
DiceCatalog.MAX_DIE_SLOTS = 12
DiceCatalog.SLOT_BASE_COST = 1000

-- Slots available before the first ascension.
DiceCatalog.BASE_DIE_SLOT_CAP = 3

-- THE CEILING RISES WITH PRESTIGE (operator decision, 2026-08-13).
--
-- Cash still buys each individual slot; what ascending raises is how many a
-- player may own at all. Before this the cap was a flat 7 for everyone, so the
-- entire slot progression was spent within the first run and prestige had one
-- less thing to give back.
--
--   ascensions 0 -> 3 slots       ascensions 5 -> 8 slots
--   ascensions 1 -> 4 slots       ascensions 6 -> 9 slots
--   ascensions 2 -> 5 slots       ascensions 7 -> 10 slots
--   ascensions 3 -> 6 slots       ascensions 8 -> 11 slots
--   ascensions 4 -> 7 slots       ascensions 9+ -> 12 slots (max)
--
-- Nine rungs since MAX_DIE_SLOTS rose to 12, where there were four. The Cash
-- price doubles per slot, so the twelfth costs $1.02M against a $1M ascension
-- threshold -- the last slots are a late-run goal rather than an afterthought.
--
-- Clamped at BOTH ends. The lower clamp matters because an existing player may
-- already own more slots than their ascension count now permits -- see
-- `AddDieSlot`, which refuses new purchases without ever confiscating.
function DiceCatalog.dieSlotCapFor(ascensions: number): number
	local a = if type(ascensions) == "number" and ascensions == ascensions
		then math.max(0, math.floor(ascensions))
		else 0
	return math.clamp(DiceCatalog.BASE_DIE_SLOT_CAP + a, 1, DiceCatalog.MAX_DIE_SLOTS)
end

-- Cash cost of buying the NEXT slot, given how many the player owns now.
--
-- MOVED HERE FROM the AddDieSlot handler (2026-08-12) so the panel can show the
-- price. It was a server-side expression with no shared name, so the SLOTS
-- panel rendered a bare "ADD SLOT" button with no cost on it -- a player pressed
-- it, could not afford it, and the server's refusal produced no visible change
-- at all. Same defect the SHAPE panel had with its Diamond switch cost.
--
-- Doubling per slot: the second die is a cheap, obvious upgrade and the seventh
-- is a genuine goal. Value unchanged in the move -- 1000 * 2^(owned-1).
-- `ascensions` gates the CAP. Optional so existing callers that only know the
-- owned count still price correctly against the absolute maximum; the server
-- and the SLOTS panel both pass it, so both agree on when to stop.
function DiceCatalog.dieSlotCost(ownedSlots: number, ascensions: number?): number?
	if type(ownedSlots) ~= "number" or ownedSlots ~= ownedSlots then
		return nil
	end
	local owned = math.floor(ownedSlots)
	local cap = if ascensions ~= nil
		then DiceCatalog.dieSlotCapFor(ascensions)
		else DiceCatalog.MAX_DIE_SLOTS
	if owned < 1 or owned >= cap then
		return nil -- at the current cap; there is no next slot to price
	end
	return DiceCatalog.SLOT_BASE_COST * (2 ^ (owned - 1))
end

function DiceCatalog.getUnlockOrder(): { string }
	return table.clone(UNLOCK_ORDER)
end

function DiceCatalog.getUnlockCost(shapeId: string): number?
	return UNLOCK_COST[shapeId]
end

-- The shape that must be owned before `shapeId` may be unlocked, or nil for the
-- first rung.
function DiceCatalog.getPrerequisite(shapeId: string): string?
	for i, id in ipairs(UNLOCK_ORDER) do
		if id == shapeId then
			return if i > 1 then UNLOCK_ORDER[i - 1] else nil
		end
	end
	return nil
end

-- THE SINGLE EXECUTABLE DEFINITION of whether a shape may be unlocked right now
-- (ledger L-025: a rule kept as prose in two places gets re-derived wrongly).
-- Every caller -- server validation, client button state, tests -- asks THIS,
-- so the ladder cannot be enforced in one place and drawn differently in
-- another.
--
-- Returns (ok, reason). `owned` is the player's unlock table.
function DiceCatalog.canUnlock(shapeId: string, owned: { [string]: boolean }): (boolean, string?)
	if SHAPES[shapeId] == nil then
		return false, "unknown_shape"
	end
	if owned[shapeId] then
		return false, "already_owned"
	end
	local cost = UNLOCK_COST[shapeId]
	if cost == nil then
		return false, "shape_not_on_ladder"
	end
	local prereq = DiceCatalog.getPrerequisite(shapeId)
	if prereq ~= nil and not owned[prereq] then
		return false, "prerequisite_locked"
	end
	return true, nil
end

return DiceCatalog
