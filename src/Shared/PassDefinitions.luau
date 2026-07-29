--!strict
-- PassDefinitions.luau
-- Authoritative catalog for GamePasses and Developer Products.

export type PassProductData = {
	Id: number, -- Roblox Asset ID / DevProduct ID
	Name: string,
	Description: string,
	Type: "GamePass" | "DevProduct",
	PriceRobux: number,
	CashReward: number?,
	MultiplierBoost: number?,
}

local PassDefinitions = {}

local CATALOG: { [string]: PassProductData } = {
	DoubleCashPass = {
		Id = 1001,
		Name = "2X Cash GamePass",
		Description = "Permanently doubles all cash earned from ball bounces!",
		Type = "GamePass",
		PriceRobux = 299,
		MultiplierBoost = 2.0,
	},
	SuperLuckPass = {
		Id = 1002,
		Name = "Super Luck Pass",
		Description = "3X higher chance to spawn Legendary Purple & Blue balls!",
		Type = "GamePass",
		PriceRobux = 499,
		MultiplierBoost = 3.0,
	},
	InstaCashPackSmall = {
		Id = 2001,
		Name = "Insta-Cash Pack (Small)",
		Description = "Instantly grants +$50,000 cash!",
		Type = "DevProduct",
		PriceRobux = 99,
		CashReward = 50000,
	},
	InstaCashPackMega = {
		Id = 2002,
		Name = "Insta-Cash Pack (Mega)",
		Description = "Instantly grants +$1,000,000 cash!",
		Type = "DevProduct",
		PriceRobux = 499,
		CashReward = 1000000,
	},
}

function PassDefinitions.Get(key: string): PassProductData?
	return CATALOG[key]
end

function PassDefinitions.GetByAssetId(id: number): PassProductData?
	for _, item in pairs(CATALOG) do
		if item.Id == id then
			return item
		end
	end
	return nil
end

function PassDefinitions.GetAll(): { [string]: PassProductData }
	return CATALOG
end

return PassDefinitions
