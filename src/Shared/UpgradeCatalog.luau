--!strict
-- UpgradeCatalog.luau
-- Cash upgrades and Diamond tree node definitions, cost curves, and max levels.
-- Guaranteed 1:1 match with PlayerProfile template keys (SRS FR-3.6, FR-5.4, FR-8.3, FR-9.3).

local Shared = script.Parent
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local UpgradeCatalog = {}

export type CashUpgradeDef = {
	id: string,
	name: string,
	maxLevel: number,
	baseCost: number,
	costMultiplier: number,
}

export type DiamondNodeDef = {
	id: string,
	name: string,
	maxLevel: number,
	baseCost: number,
	costMultiplier: number,
}

-- Keys match PlayerProfile.Upgrades table exactly
-- Mass added to a die's purchased budget per MassBudget level.
UpgradeCatalog.MASS_PER_LEVEL = 10

local CASH_UPGRADES: { [string]: CashUpgradeDef } = {
	-- FR-3.6: "Mass budget increases are purchased with Cash up to a per-shape
	-- cap, and beyond that with Prestige Diamonds."
	--
	-- THE CASH HALF DID NOT EXIST. Only the Diamond node (`MassCeiling`) was ever
	-- declared, so a player's die was stuck at its starting budget for an entire
	-- first run -- the forge was a fixed puzzle with no progression in it at all.
	--
	-- Each level adds MASS_PER_LEVEL to the die's purchased budget, and the
	-- per-shape `cashBudgetCap` in DiceCatalog is what stops it there; past that
	-- the Diamond tree takes over. maxLevel is generous because the CAP is the
	-- real limit and it differs by shape.
	MassBudget = {
		id = "MassBudget",
		name = "Mass Budget",
		maxLevel = 24,
		baseCost = 400,
		costMultiplier = 1.55,
	},
	AutoRollSpeed = {
		id = "AutoRollSpeed",
		name = "Auto-Roll Speed",
		maxLevel = 10,
		baseCost = 100,
		costMultiplier = 2.5,
	},
	VaultCapacity = {
		id = "VaultCapacity",
		name = "Vault Capacity",
		maxLevel = 10,
		baseCost = 250,
		costMultiplier = 2.0,
	},
	VaultEfficiency = {
		id = "VaultEfficiency",
		name = "Vault Efficiency",
		maxLevel = 5,
		baseCost = 500,
		costMultiplier = 3.0,
	},
	Luck = {
		id = "Luck",
		name = "Luck Boost",
		maxLevel = 20,
		baseCost = 150,
		costMultiplier = 1.8,
	},
	BadRollShield = {
		id = "BadRollShield",
		name = "Bad Roll Shield",
		maxLevel = 1,
		baseCost = 5000,
		costMultiplier = 1.0,
	},
}

-- Keys match PlayerProfile.Diamond table fields exactly
local DIAMOND_NODES: { [string]: DiamondNodeDef } = {
	StreakStrength = {
		id = "StreakStrength",
		name = "Streak Strength (b)",
		maxLevel = 20,
		baseCost = 10,
		costMultiplier = 1.5,
	},
	MassCeiling = {
		id = "MassCeiling",
		name = "Mass Budget Ceiling",
		maxLevel = 15,
		baseCost = 25,
		costMultiplier = 2.0,
	},
	SlotNodes = {
		id = "SlotNodes",
		name = "Die Slot Expansion",
		maxLevel = 4,
		baseCost = 50,
		costMultiplier = 4.0,
	},
}

function UpgradeCatalog.getCashUpgrade(id: string): CashUpgradeDef?
	return CASH_UPGRADES[id]
end

function UpgradeCatalog.getDiamondNode(id: string): DiamondNodeDef?
	return DIAMOND_NODES[id]
end

function UpgradeCatalog.getCashUpgradeCost(id: string, currentLevel: number): number
	local def = CASH_UPGRADES[id]
	if not def or currentLevel >= def.maxLevel or not ForgeMath.isFinite(currentLevel) or currentLevel < 0 then
		return math.huge
	end
	return ForgeMath.snap(def.baseCost * (def.costMultiplier ^ currentLevel))
end

function UpgradeCatalog.getDiamondNodeCost(id: string, currentLevel: number): number
	local def = DIAMOND_NODES[id]
	if not def or currentLevel >= def.maxLevel or not ForgeMath.isFinite(currentLevel) or currentLevel < 0 then
		return math.huge
	end
	return ForgeMath.snap(def.baseCost * (def.costMultiplier ^ currentLevel))
end

function UpgradeCatalog.getAllCashUpgrades(): { CashUpgradeDef }
	local list: { CashUpgradeDef } = {}
	for _, u in pairs(CASH_UPGRADES) do
		table.insert(list, u)
	end
	return list
end

function UpgradeCatalog.getAllDiamondNodes(): { DiamondNodeDef }
	local list: { DiamondNodeDef } = {}
	for _, n in pairs(DIAMOND_NODES) do
		table.insert(list, n)
	end
	return list
end

return UpgradeCatalog
