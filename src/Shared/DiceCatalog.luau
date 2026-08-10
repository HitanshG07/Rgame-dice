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
	D6 = {
		id = "D6",
		faceCount = 6,
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
local UNLOCK_ORDER: { string } = { "D2", "D3", "D4", "D6", "D8", "D10", "D12", "D20" }

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
	D6 = 12000,
	D8 = 55000,
	D10 = 240000,
	D12 = 1000000,
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
