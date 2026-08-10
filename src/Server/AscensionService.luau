--!strict
-- AscensionService.luau
-- Prestige ascension tree, Diamond calculation, and run reset mechanics (SRS FR-9).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local AscensionService = {}

local MIN_LIFETIME_CASH = 1e6 -- Threshold required to ascend (SRS FR-9.5)

function AscensionService.calculateDiamonds(lifetimeCash: number): number
	if not ForgeMath.isFinite(lifetimeCash) or lifetimeCash < MIN_LIFETIME_CASH then
		return 0
	end
	local earned = math.floor((lifetimeCash / 1e6) ^ 0.5)
	if not ForgeMath.isFinite(earned) or earned < 0 then
		return 0
	end
	return earned
end

function AscensionService.canAscend(player: Player): (boolean, number)
	local data = PlayerProfile.get(player)
	if not data then
		return false, 0
	end
	local diamonds = AscensionService.calculateDiamonds(data.LifetimeCash)
	return diamonds > 0, diamonds
end

function AscensionService.ascend(player: Player): (boolean, string?, number)
	local can, diamondsEarned = AscensionService.canAscend(player)
	if not can or diamondsEarned <= 0 then
		return false, "insufficient_lifetime_cash", 0
	end

	local ok, reason = PlayerProfile.mutate(player, function(d)
		d.Cash = 0
		d.Gems = 0
		d.Diamonds += diamondsEarned
		d.Ascensions += 1

		-- Reset Cash upgrades only
		d.Upgrades.AutoRollSpeed = 0
		d.Upgrades.VaultCapacity = 0
		d.Upgrades.VaultEfficiency = 0
		d.Upgrades.Luck = 0

		-- Reset volatile progression
		d.Vault.AccrualId = 0
		d.Vault.AvgIncomePerSec = 0
		table.clear(d.CodesRedeemed)
		d.Quests.Slots = {}
		d.Quests.RolledOn = 0
		d.LoginStreak.Count = 0
		d.LoginStreak.ForgivenessLeft = 1

		-- Reset Dice to default initial state
		d.Dice = {
			{
				Shape = "D6",
				MassBudget = 60,
				PurchasedBudget = 60,
				Faces = {
					{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
					{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
					{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
				},
			},
		}
		d.DieSlots = 1
	end)

	if not ok then
		return false, reason or "ascension_failed", 0
	end

	return true, nil, diamondsEarned
end

return AscensionService
