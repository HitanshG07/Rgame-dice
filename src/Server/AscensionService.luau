--!strict
-- AscensionService.luau
-- Prestige ascension tree, Diamond calculation, and run reset mechanics (SRS FR-9).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local AscensionService = {}

-- Threshold required to ascend (SRS FR-9.5). Read from the shared catalog so the
-- ASCEND panel quotes the same number the server enforces.
local MIN_LIFETIME_CASH = DiceCatalog.ASCEND_MIN_LIFETIME_CASH

-- DELEGATES to the shared implementation. The formula moved to DiceCatalog so
-- the client could show an honest projection of the reward instead of the
-- hardcoded "+450 Diamonds" the panel used to display; keeping a second copy
-- here is exactly the drift L-025 exists to prevent. The finiteness guard stays
-- because this is the path a real grant runs through.
function AscensionService.calculateDiamonds(lifetimeCash: number): number
	if not ForgeMath.isFinite(lifetimeCash) then
		return 0
	end
	return DiceCatalog.ascensionDiamonds(lifetimeCash)
end

function AscensionService.canAscend(player: Player): (boolean, number)
	local data = PlayerProfile.get(player)
	if not data then
		return false, 0
	end
	-- CASH ON HAND. Not `LifetimeCash`, which never resets -- it is what the
	-- NetWorth leaderboard ranks on, so reading it here meant a player
	-- permanently qualified after their first ascension and the reward was
	-- computed from earnings they had already spent.
	--
	-- Nor `RunCash`, a separate "earned this run" counter that used to live here
	-- and has been deleted. Operator decision 2026-08-13: "holding -- because
	-- after ascension I'm holding 0 so it would anyways be showing 0 in the
	-- ascension tab as well". The reasoning is the whole argument for it:
	-- ascension sets `Cash = 0`, so the HUD and the ASCEND panel read the same
	-- number immediately afterwards and can never disagree again. Two internally
	-- correct figures a player cannot reconcile is worse than one.
	--
	-- THE TRADEOFF, STATED: spending Cash on upgrades now pushes ascension
	-- further away, because the threshold measures what you HOLD rather than what
	-- you earned. That makes upgrade-vs-prestige a real decision, and it is the
	-- price of the two numbers always agreeing.
	local diamonds = AscensionService.calculateDiamonds(data.Cash or 0)
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
		-- `d.Cash = 0` above IS the run reset now. A separate `RunCash` counter
		-- used to be zeroed here as well; it has been deleted, because the
		-- threshold reads cash on hand and that is already back to zero.
		-- `LifetimeCash` is deliberately untouched -- the NetWorth leaderboard
		-- ranks on it and it must survive prestige.

		-- Reset Cash upgrades only
		d.Upgrades.AutoRollSpeed = 0
		d.Upgrades.VaultCapacity = 0
		d.Upgrades.VaultEfficiency = 0
		d.Upgrades.Luck = 0

		-- Reset volatile progression
		d.Vault.AccrualId = 0
		d.Vault.AvgIncomePerSec = 0

		-- WHAT ASCENSION RESETS IS AN ENUMERATED LIST, AND IT IS SHORT.
		--
		-- FR-9.1: "Ascending resets Cash, face layouts, mass budgets, and
		-- Cash-purchased upgrades." Everything above is on that list. Three
		-- things that WERE reset here are not, and each was a real defect:
		--
		--   `CodesRedeemed` was cleared, which made every promo code redeemable
		--   ONCE PER ASCENSION rather than once per player. FR-10.6 specifies an
		--   "already-redeemed" response, and a table named CodesRedeemed exists to
		--   produce it; wiping it defeated the only mechanism enforcing it and
		--   turned each ascension into a repeatable +100 Gems and +10 Diamonds.
		--   Diamonds are the premium prestige currency, so this was a mint.
		--
		--   `LoginStreak` was zeroed. A login streak is an ACCOUNT-level record of
		--   days attended; ascending is a thing the player does inside one run and
		--   has nothing to do with whether they showed up yesterday. Resetting it
		--   punished the player for engaging with the core prestige loop.
		--
		--   `Quests` were cleared and the roll date zeroed, which let a player
		--   re-roll the day's quests by ascending, and claim them again.
		--
		-- Anything added to this reset in future belongs in FR-9.1 first. The list
		-- there is the specification; this block is only allowed to implement it.

		-- Face layouts and mass budgets, per FR-9.1 -- via the shared factory, so
		-- the die a player restarts with is the STARTING shape and cannot drift
		-- from what a new profile gets. This used to hardcode a D6 with six
		-- 10-mass faces, which after the ladder landed handed the ascending player
		-- a shape three rungs up that they may not even own.
		local fresh = DiceCatalog.newStartingDie()
		if fresh ~= nil then
			d.Dice = { fresh :: any }
			d.DieSlots = 1
			d.Inventory = { D2 = 1 }
		end
	end)

	if not ok then
		return false, reason or "ascension_failed", 0
	end

	return true, nil, diamondsEarned
end

return AscensionService
