--!strict
-- CodesCatalog.luau
-- Authoritative catalog of redeemable promo codes.

export type PromoCode = {
	Code: string,
	CashReward: number,
	GemsReward: number,
	ExpirationTimestamp: number?,
}

local CodesCatalog = {}

local CODES: { [string]: PromoCode } = {
	RELEASE = {
		Code = "RELEASE",
		CashReward = 500,
		GemsReward = 10,
	},
	BOUNCY = {
		Code = "BOUNCY",
		CashReward = 1000,
		GemsReward = 25,
	},
	LUCK = {
		Code = "LUCK",
		CashReward = 2500,
		GemsReward = 50,
	},
	VISITS1M = {
		Code = "VISITS1M",
		CashReward = 10000,
		GemsReward = 100,
	},
}

function CodesCatalog.Get(codeString: string): PromoCode?
	local formatted = string.upper(string.gsub(codeString, "%s+", ""))
	return CODES[formatted]
end

return CodesCatalog
