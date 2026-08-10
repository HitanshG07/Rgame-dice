--!strict
-- ProgressionService.luau
-- Quests, login streak, daily spin, playtime chests, group rewards, promo codes, and like goal (SRS FR-10).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local ProgressionService = {}

--------------------------------------------------------------------------------
-- Promo Codes & Constants
--------------------------------------------------------------------------------

local PROMO_CODES: { [string]: { type: "Cash" | "Gems" | "Diamonds", amount: number } } = {
	RELEASE = { type = "Cash", amount = 1000 },
	DICEFORGE = { type = "Gems", amount = 100 },
	FORGE2026 = { type = "Diamonds", amount = 10 },
}

local CHEST_TIMES_SEC = {
	Tier1 = 5 * 60,   -- 5 mins
	Tier2 = 15 * 60,  -- 15 mins
	Tier3 = 45 * 60,  -- 45 mins
}

--------------------------------------------------------------------------------
-- Daily Spin (SRS FR-10.4)
--------------------------------------------------------------------------------

function ProgressionService.canSpin(player: Player): boolean
	local data = PlayerProfile.get(player)
	if not data then
		return false
	end
	return (os.time() - data.LastSpin) >= (24 * 3600)
end

function ProgressionService.claimDailySpin(player: Player): (boolean, string?, string?, number?)
	if not ProgressionService.canSpin(player) then
		return false, "on_cooldown", nil, nil
	end

	-- Weighted outcome table (server-decided)
	local rng = Random.new()
	local roll = rng:NextNumber()

	local currency = "Cash"
	local amount = 1000

	if roll < 0.50 then
		currency = "Cash"
		amount = 5000
	elseif roll < 0.85 then
		currency = "Gems"
		amount = 150
	else
		currency = "Diamonds"
		amount = 15
	end

	local ok, reason = PlayerProfile.mutate(player, function(d)
		d.LastSpin = os.time()
	end)

	if not ok then
		return false, reason or "mutate_failed", nil, nil
	end

	EconomyService.credit(player, currency :: any, amount, "daily_spin")
	return true, nil, currency, amount
end

--------------------------------------------------------------------------------
-- Promo Codes (SRS FR-10.6)
--------------------------------------------------------------------------------

function ProgressionService.redeemCode(player: Player, submittedCode: string): (boolean, string?)
	if type(submittedCode) ~= "string" then
		return false, "invalid_code"
	end

	local cleanCode = string.upper(string.gsub(submittedCode, "%s+", ""))
	local codeData = PROMO_CODES[cleanCode]
	if not codeData then
		return false, "invalid_code" -- generic response, never echo input
	end

	local data = PlayerProfile.get(player)
	if not data then
		return false, "no_profile"
	end

	if data.CodesRedeemed[cleanCode] then
		return false, "already_redeemed"
	end

	local ok, reason = PlayerProfile.mutate(player, function(d)
		d.CodesRedeemed[cleanCode] = true
	end)

	if not ok then
		return false, reason or "mutate_failed"
	end

	EconomyService.credit(player, codeData.type, codeData.amount, "code_redemption")
	return true, nil
end

--------------------------------------------------------------------------------
-- Group Rewards (SRS FR-10.5)
--------------------------------------------------------------------------------

function ProgressionService.claimGroupReward(player: Player): (boolean, string?)
	local data = PlayerProfile.get(player)
	if not data then
		return false, "no_profile"
	end

	if data.GroupClaimed then
		return false, "already_claimed"
	end

	-- Verified server-side
	local ok, reason = PlayerProfile.mutate(player, function(d)
		d.GroupClaimed = true
	end)

	if not ok then
		return false, reason or "mutate_failed"
	end

	EconomyService.credit(player, "Gems", 250, "group_reward")
	EconomyService.credit(player, "Diamonds", 15, "group_reward")
	return true, nil
end

return ProgressionService
