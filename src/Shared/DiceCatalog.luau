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
-- SRS FR-6.3 requires that no shape dominate at every Streak Strength `b`.
-- THAT CROSSOVER IS NOT YET VERIFIED for these numbers. It cannot be verified
-- by inspection; it needs the numerical sweep in roadmap prompt P-6B. Until
-- that sweep runs, treat every constant in this file as provisional. Budgets
-- are set to 10 mass per face at every shape so the sweep starts from a clean
-- baseline where shape differs only in face count.
local SHAPES: { [string]: ShapeDef } = {
	D2 = {
		id = "D2",
		faceCount = 2,
		massFloor = 1,
		defaultBudget = 20,
		cashBudgetCap = 100,
		diamondCeiling = 500,
	},
	D3 = {
		id = "D3",
		faceCount = 3,
		massFloor = 1,
		defaultBudget = 30,
		cashBudgetCap = 150,
		diamondCeiling = 750,
	},
	D4 = {
		id = "D4",
		faceCount = 4,
		massFloor = 1,
		defaultBudget = 40,
		cashBudgetCap = 200,
		diamondCeiling = 1000,
	},
	D6 = {
		id = "D6",
		faceCount = 6,
		massFloor = 1,
		defaultBudget = 60,
		cashBudgetCap = 300,
		diamondCeiling = 1500,
	},
	D8 = {
		id = "D8",
		faceCount = 8,
		massFloor = 1,
		defaultBudget = 80,
		cashBudgetCap = 400,
		diamondCeiling = 2000,
	},
	D10 = {
		id = "D10",
		faceCount = 10,
		massFloor = 1,
		defaultBudget = 100,
		cashBudgetCap = 500,
		diamondCeiling = 2500,
	},
	D12 = {
		id = "D12",
		faceCount = 12,
		massFloor = 1,
		defaultBudget = 120,
		cashBudgetCap = 600,
		diamondCeiling = 3000,
	},
	D20 = {
		id = "D20",
		faceCount = 20,
		massFloor = 1,
		defaultBudget = 200,
		cashBudgetCap = 1000,
		diamondCeiling = 5000,
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

-- Diamond cost to unlock each shape. Rises with position on the ladder, not with
-- face count, so the curve is a progression cost rather than a power price.
local UNLOCK_COST: { [string]: number } = {
	D2 = 0,      -- owned from the start; listed so every shape has an entry
	D3 = 5,
	D4 = 15,
	D6 = 40,
	D8 = 90,
	D10 = 180,
	D12 = 320,
	D20 = 600,
}

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
