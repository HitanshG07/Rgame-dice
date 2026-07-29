--!strict
-- UpgradeDefinitions.luau
-- Authoritative configuration catalog for all upgrades and pricing math.

export type UpgradeData = {
	Id: string,
	Name: string,
	Description: string,
	BaseCost: number,
	GrowthFactor: number,
	MaxLevel: number,
	Category: string,
}

local UpgradeDefinitions = {}

local CATALOG: { [string]: UpgradeData } = {
	AddBall = {
		Id = "AddBall",
		Name = "Add Ball",
		Description = "Spawns an extra ball in the spinning ring.",
		BaseCost = 23,
		GrowthFactor = 1.35,
		MaxLevel = 15,
		Category = "Balls",
	},
	RingSpin = {
		Id = "RingSpin",
		Name = "Ring Spin",
		Description = "Increases the rotation RPM of the ring.",
		BaseCost = 25,
		GrowthFactor = 1.25,
		MaxLevel = 50,
		Category = "Ring",
	},
	WidenGap = {
		Id = "WidenGap",
		Name = "Widen Gap",
		Description = "Expands the angular opening gap for easier escapes.",
		BaseCost = 200,
		GrowthFactor = 1.40,
		MaxLevel = 20,
		Category = "Ring",
	},
	CoinBonus = {
		Id = "CoinBonus",
		Name = "Coin Bonus",
		Description = "Multiplies cash earned per ball bounce.",
		BaseCost = 5,
		GrowthFactor = 1.30,
		MaxLevel = 100,
		Category = "Income",
	},
	IncreaseLuck = {
		Id = "IncreaseLuck",
		Name = "Increase Luck",
		Description = "Higher chance to spawn rare high-multiplier balls.",
		BaseCost = 75,
		GrowthFactor = 1.50,
		MaxLevel = 25,
		Category = "Luck",
	},
	RingSpikes = {
		Id = "RingSpikes",
		Name = "Ring Spikes",
		Description = "Adds spikes around the ring that double bounce payout.",
		BaseCost = 500,
		GrowthFactor = 1.60,
		MaxLevel = 10,
		Category = "Ring",
	},
}

function UpgradeDefinitions.Get(upgradeId: string): UpgradeData?
	return CATALOG[upgradeId]
end

function UpgradeDefinitions.GetAll(): { [string]: UpgradeData }
	return CATALOG
end

function UpgradeDefinitions.CalculateCost(upgradeId: string, currentLevel: number): number
	local def = CATALOG[upgradeId]
	if not def then
		return math.huge
	end
	if currentLevel >= def.MaxLevel then
		return math.huge
	end
	return math.floor(def.BaseCost * (def.GrowthFactor ^ currentLevel))
end

return UpgradeDefinitions
