--!strict
-- PrestigeDefinitions.luau
-- Definitions and mathematical formulas for Prestige system and Prestige Upgrades.

export type PrestigeUpgrade = {
	Id: string,
	Name: string,
	Description: string,
	BaseCost: number,
	GrowthFactor: number,
	MaxLevel: number,
	MultiplierPerLevel: number,
}

local PrestigeDefinitions = {}

local PRESTIGE_REQUIREMENT = 1000000 -- $1,000,000 required to prestige

local UPGRADES: { [string]: PrestigeUpgrade } = {
	NebulaBoost = {
		Id = "NebulaBoost",
		Name = "Nebula Multiplier",
		Description = "Permanently boosts all ball bounce earnings by +25% per level.",
		BaseCost = 1,
		GrowthFactor = 2.0,
		MaxLevel = 20,
		MultiplierPerLevel = 0.25,
	},
	GoldenSpikes = {
		Id = "GoldenSpikes",
		Name = "Golden Spikes",
		Description = "Spikes yield 4X payout instead of 2X.",
		BaseCost = 5,
		GrowthFactor = 2.5,
		MaxLevel = 5,
		MultiplierPerLevel = 1.0,
	},
	AutoSaver = {
		Id = "AutoSaver",
		Name = "Prestige Retainer",
		Description = "Start every prestige with +$5,000 bonus cash.",
		BaseCost = 2,
		GrowthFactor = 1.8,
		MaxLevel = 10,
		MultiplierPerLevel = 5000,
	},
}

function PrestigeDefinitions.GetRequirement(): number
	return PRESTIGE_REQUIREMENT
end

function PrestigeDefinitions.CalculatePointsEarned(currentCash: number): number
	if currentCash < PRESTIGE_REQUIREMENT then
		return 0
	end
	return math.floor((currentCash / PRESTIGE_REQUIREMENT) ^ 0.6)
end

function PrestigeDefinitions.GetUpgrade(id: string): PrestigeUpgrade?
	return UPGRADES[id]
end

function PrestigeDefinitions.GetAllUpgrades(): { [string]: PrestigeUpgrade }
	return UPGRADES
end

function PrestigeDefinitions.CalculateUpgradeCost(id: string, level: number): number
	local def = UPGRADES[id]
	if not def or level >= def.MaxLevel then
		return math.huge
	end
	return math.floor(def.BaseCost * (def.GrowthFactor ^ level))
end

return PrestigeDefinitions
