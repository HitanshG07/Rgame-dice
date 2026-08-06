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

return DiceCatalog
