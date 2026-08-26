--!strict
-- BoostEffects.test.luau
-- Phase 0a: timed boosts actually reach the payout, and the vault's `doubled`
-- flag is no longer a free 2x.
--
-- WHY THIS SUITE EXISTS. `BoostService` was built, correct, covered by nothing,
-- and called by NOTHING. Both boosts took real Robux, granted, stored an expiry,
-- drew a countdown on the HUD -- and changed no number anywhere. A suite that
-- only tested `BoostService` in isolation would have passed the whole time,
-- because the module was never the broken part. **The wiring was.** So every
-- assertion here drives the real consumer -- the payout config and the vault
-- claim -- rather than the boost module on its own.
--
-- The second half covers a live exploit found while wiring this: `ClaimVault`
-- took a client-supplied boolean, checked only that it WAS a boolean, and then
-- doubled the payout. Anyone sending `true` took 2x their vault cash, free,
-- repeatedly. The fix makes the flag a request the server prices itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")

local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local BoostService = require(Server:WaitForChild("BoostService"))
local OfflineService = require(Server:WaitForChild("OfflineService"))
local Fakes = require(ServerScriptService:WaitForChild("Tests"):WaitForChild("Fakes"))

local BoostEffectsTest = {}

function BoostEffectsTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	PlayerProfile.init()

	local player = Fakes.createFakePlayer(778899, "TestBoostPlayer")
	local liveData = PlayerProfile._reconcile({})
	PlayerProfile._injectProfileForTesting(player, Fakes.createFakeProfile(liveData))

	----------------------------------------------------------------------------
	-- 1. The default is 1.0, and it is a REAL 1.0
	----------------------------------------------------------------------------

	-- Fails closed: an absent boost must be neutral, never nil and never zero.
	-- A nil here would propagate into the payout line as an arithmetic error and
	-- a 0 would zero every payout in the game.
	check(BoostService.getMultiplier(player, "LuckBoost") == 1.0,
		"an absent LuckBoost must read exactly 1.0")
	check(BoostService.getMultiplier(player, "OfflineX2") == 1.0,
		"an absent OfflineX2 must read exactly 1.0")
	check(BoostService.isBoostActive(player, "LuckBoost") == false,
		"an absent boost must not report active")

	----------------------------------------------------------------------------
	-- 2. A granted boost reads back at its real value
	----------------------------------------------------------------------------

	check(BoostService.addBoost(player, "LuckBoost", 2, 900),
		"granting LuckBoost should succeed")
	check(BoostService.getMultiplier(player, "LuckBoost") == 2.0,
		"a granted 2x LuckBoost must read 2.0, not 1.0 -- this is the exact "
		.. "read that no code performed, which is why the purchase did nothing")
	check(BoostService.isBoostActive(player, "LuckBoost") == true,
		"a granted boost must report active")

	-- Granting one kind must not leak into another. They share a key prefix, so
	-- a formatting slip would cross them.
	check(BoostService.getMultiplier(player, "OfflineX2") == 1.0,
		"granting LuckBoost must not activate OfflineX2")

	----------------------------------------------------------------------------
	-- 3. Expiry is server-clocked and fails closed (T-20)
	----------------------------------------------------------------------------

	-- Written directly into the past rather than waiting: the point is that the
	-- SERVER's clock decides, and a stored expiry behind `os.time()` must read
	-- neutral no matter how it got there.
	PlayerProfile.mutate(player, function(d)
		d.Upgrades["Boost_LuckBoost_Expiry"] = os.time() - 1
	end)
	check(BoostService.getMultiplier(player, "LuckBoost") == 1.0,
		"an expired boost must read 1.0 -- expiry is enforced on read, so a "
		.. "client cannot hold a boost open by never asking")

	-- A negative or absurd stored multiplier must not pay out. `math.max(1.0, ..)`
	-- is the guard; this pins it, because a stored -5 would otherwise invert
	-- every payout it touched.
	PlayerProfile.mutate(player, function(d)
		d.Upgrades["Boost_LuckBoost_Expiry"] = os.time() + 600
		d.Upgrades["Boost_LuckBoost_Mult"] = -500
	end)
	check(BoostService.getMultiplier(player, "LuckBoost") == 1.0,
		"a negative stored multiplier must clamp to 1.0, never invert a payout")

	----------------------------------------------------------------------------
	-- 4. consumeBoost spends a one-shot, and only when there is one
	----------------------------------------------------------------------------

	check(BoostService.consumeBoost(player, "OfflineX2") == false,
		"consuming a boost the player does not have must report false, so a "
		.. "caller can tell 'spent' from 'there was nothing to spend'")

	check(BoostService.addBoost(player, "OfflineX2", 2, 3600),
		"granting OfflineX2 should succeed")
	check(BoostService.getMultiplier(player, "OfflineX2") == 2.0,
		"granted OfflineX2 must read 2.0")
	check(BoostService.consumeBoost(player, "OfflineX2") == true,
		"consuming a held boost must report true")
	check(BoostService.getMultiplier(player, "OfflineX2") == 1.0,
		"a consumed boost must read 1.0 -- otherwise 'double your NEXT "
		.. "collection' would double every collection forever")
	check(BoostService.consumeBoost(player, "OfflineX2") == false,
		"a boost cannot be consumed twice")

	----------------------------------------------------------------------------
	-- 5. THE EXPLOIT: `doubled` from the client must buy nothing on its own
	----------------------------------------------------------------------------

	-- This is the regression that matters most in this file. Before the fix,
	-- `claimVault(player, true)` paid 2x to ANY caller, because the flag was
	-- validated for type and never for entitlement.
	--
	-- Driven through the real `claimVault` rather than by inspecting the
	-- multiplier, because the defect lived in the consumer, not the provider.
	-- ORDER MATTERS AND COST A FAILING RUN. `beginSession` SNAPSHOTS the elapsed
	-- window from `LastSeen` at the moment it is called and freezes it for the
	-- session -- so setting `LastSeen` afterwards changes nothing and the vault
	-- reads empty. Seed the profile first, then open the session.
	PlayerProfile.mutate(player, function(d)
		d.Vault.AvgIncomePerSec = 10
		d.Vault.LastSeen = os.time() - 3600
	end)
	OfflineService.beginSession(player)

	local statusBefore = OfflineService.getStatus(player)
	check(statusBefore ~= nil, "vault status should exist for a live profile")
	local pending = (statusBefore :: any).unclaimedEarnings
	check(pending > 0, "the vault must have accrued something to claim")

	-- No boost held. Ask for the double anyway -- exactly what an exploiting
	-- client sends.
	check(BoostService.getMultiplier(player, "OfflineX2") == 1.0,
		"precondition: the player holds no OfflineX2")

	local okClaim, _, paid = OfflineService.claimVault(player, true)
	check(okClaim, "an honest claim should still succeed")
	check(paid == pending, string.format(
		"CLAIMING WITH doubled=true AND NO BOOST MUST PAY 1x. Paid %.4f against "
		.. "%.4f pending -- if these differ, the client is once again setting "
		.. "its own payout.", paid, pending))

	----------------------------------------------------------------------------
	-- 6. A player who actually OWNS the boost gets the double, and spends it
	----------------------------------------------------------------------------

	-- Re-seed and re-open, for the same reason as above. The previous claim
	-- deliberately spent the frozen window (`sessionElapsed = 0`), so without
	-- this the second claim would find an empty vault.
	PlayerProfile.mutate(player, function(d)
		d.Vault.AvgIncomePerSec = 10
		d.Vault.LastSeen = os.time() - 3600
	end)
	OfflineService.beginSession(player)

	check(BoostService.addBoost(player, "OfflineX2", 2, 3600),
		"granting OfflineX2 for the paid-path test should succeed")

	local status2 = OfflineService.getStatus(player)
	check(status2 ~= nil, "vault status should exist for the second claim")
	local pending2 = (status2 :: any).unclaimedEarnings
	check(pending2 > 0, "the vault must have accrued again")

	local okClaim2, _, paid2 = OfflineService.claimVault(player, true)
	check(okClaim2, "the boosted claim should succeed")
	check(math.abs(paid2 - pending2 * 2) < 1e-6, string.format(
		"a held OfflineX2 must actually double the claim. Paid %.4f against "
		.. "%.4f expected -- this is the read that no code performed.",
		paid2, pending2 * 2))

	-- And it must be SPENT, or "your next collection" is every collection.
	check(BoostService.getMultiplier(player, "OfflineX2") == 1.0,
		"the boost must be consumed by the claim that used it")

	PlayerProfile.releaseAll()
	return true, nil, asserts
end

return {
	name = "BoostEffects.test",
	run = BoostEffectsTest.run,
}
