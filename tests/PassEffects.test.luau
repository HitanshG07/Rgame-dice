--!strict
-- PassEffects.test.luau
-- Unit tests for P-5A2: Gamepass entitlement wiring into Economy, Roll, Forge, and StateSync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local PurchaseService = require(Server:WaitForChild("PurchaseService"))
local EconomyService = require(Server:WaitForChild("EconomyService"))
local ForgeService = require(Server:WaitForChild("ForgeService"))
local StateSyncService = require(Server:WaitForChild("StateSyncService"))
local Fakes = require(ServerScriptService:WaitForChild("Tests"):WaitForChild("Fakes"))

local PassEffectsTest = {}

function PassEffectsTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	PlayerProfile.init()
	PurchaseService.init()

	local fakePlayer = Fakes.createFakePlayer(999888, "TestPassPlayer")
	local liveData = PlayerProfile._reconcile({})
	local fakeProfile = Fakes.createFakeProfile(liveData)
	PlayerProfile._injectProfileForTesting(fakePlayer, fakeProfile)

	-- 1. Test forgeCostMultiplier
	local baseCost = ForgeService.computeForgeCost({ 10, 10, 10, 10, 10, 10 }, { 20, 10, 10, 10, 5, 5 }, 60.0, fakePlayer)
	check(baseCost > 0 and baseCost ~= math.huge, "base forge cost should be finite")
	check(baseCost == 100, "base forge cost should be 100")

	-- 2. Test cashMultiplier via EconomyService
	local startCash = PlayerProfile.get(fakePlayer).Cash
	local ok, _ = EconomyService.credit(fakePlayer, "Cash", 100, "roll")
	check(ok, "roll cash credit failed")
	local postCash = PlayerProfile.get(fakePlayer).Cash
	check(postCash == startCash + 100, "unowned cashMultiplier should credit 1x")

	-- 3. Test bonusDieSlots in StateSyncService
	local snapshot = StateSyncService.buildSnapshot(PlayerProfile.get(fakePlayer), 0, fakePlayer)
	check(snapshot.dieSlots == 1, "default dieSlots should be 1")

	----------------------------------------------------------------------------
	-- 3b. THE SNAPSHOT REPORTS STORED SLOTS, NEVER A COMPUTED BONUS
	----------------------------------------------------------------------------
	--
	-- THE DEFECT (operator-reported 2026-08-13, seen as "the maximum number of
	-- slots shows 7 but in game its only 6" and as dice overlapping):
	-- `buildSnapshot` returned `data.DieSlots + bonusDieSlots(player)`, adding the
	-- +2 Die Slots pass at DISPLAY time. The bonus was never persisted and no
	-- dice were ever created for it, so a pass owner was told they had four slots
	-- while `d.Dice` held two. DiceRenderer correctly draws one tile per entry in
	-- `state.dice`, so the board showed fewer dice than the panel promised, and
	-- BoardView laid out for a count that did not match what was drawn.
	--
	-- The invariant: whatever the snapshot claims, there must be that many DICE.
	local liveNow = PlayerProfile.get(fakePlayer)
	check(snapshot.dieSlots == #liveNow.Dice, string.format(
		"snapshot dieSlots (%s) must equal the number of real dice (%d) -- a"
		.. " display-only bonus is what produced the overlap bug",
		tostring(snapshot.dieSlots), #liveNow.Dice))

	-- The grant is IDEMPOTENT. It runs on every join, so a second call must not
	-- stack -- otherwise a pass owner gains two slots per rejoin, forever.
	PurchaseService.applyPassSlotGrant(fakePlayer)
	local afterFirst = PlayerProfile.get(fakePlayer).DieSlots
	PurchaseService.applyPassSlotGrant(fakePlayer)
	PurchaseService.applyPassSlotGrant(fakePlayer)
	check(PlayerProfile.get(fakePlayer).DieSlots == afterFirst,
		"applyPassSlotGrant must be idempotent -- it runs on every join")

	-- And the two representations stay in lockstep through it.
	local afterGrants = PlayerProfile.get(fakePlayer)
	check(afterGrants.DieSlots == #afterGrants.Dice, string.format(
		"DieSlots (%d) and #Dice (%d) must agree after repeated grants",
		afterGrants.DieSlots, #afterGrants.Dice))

	----------------------------------------------------------------------------
	-- 3c. Mid-session pass purchase and rejoin idempotency (PASS-1)
	--
	-- Buying DieSlots2 mid-session must increment PassSlotsGranted so that
	-- applyPassSlotGrant on subsequent joins does NOT grant another 2 slots.
	----------------------------------------------------------------------------
	local Catalog = require(Shared:WaitForChild("MonetisationCatalog"))
	local slotsBeforePurchase = PlayerProfile.get(fakePlayer).DieSlots
	local passId = Catalog.Passes.DieSlots2.assetId :: number
	PurchaseService._onGamePassPurchaseFinished(fakePlayer, passId, true)

	local dataAfterBuy = PlayerProfile.get(fakePlayer)
	check(dataAfterBuy.DieSlots == slotsBeforePurchase + 2,
		"mid-session purchase of DieSlots2 must grant exactly 2 slots")
	check(dataAfterBuy.PassSlotsGranted == 2,
		"mid-session purchase of DieSlots2 MUST credit PassSlotsGranted counter (PASS-1)")

	-- Now simulate rejoining / applying pass slot grants
	PurchaseService.applyPassSlotGrant(fakePlayer)
	PurchaseService.applyPassSlotGrant(fakePlayer)
	local dataAfterRejoin = PlayerProfile.get(fakePlayer)
	check(dataAfterRejoin.DieSlots == slotsBeforePurchase + 2,
		"rejoining must NOT grant additional slots when PassSlotsGranted was credited (PASS-1)")
	check(dataAfterRejoin.PassSlotsGranted == 2,
		"PassSlotsGranted remains 2 after rejoin checks")
	check(#dataAfterRejoin.Dice == dataAfterRejoin.DieSlots,
		"dice count must match DieSlots after pass purchase and rejoin")

	-- 4. Test non-roll credits do NOT apply cashMultiplier
	local okRefund, _ = EconomyService.credit(fakePlayer, "Cash", 50, "forge_refund")
	check(okRefund, "refund credit failed")
	check(PlayerProfile.get(fakePlayer).Cash == postCash + 50, "refund should credit exact 50 without multiplier")

	----------------------------------------------------------------------------
	-- 5. CURR-1: Reject invalid currencies and protect Diamonds
	----------------------------------------------------------------------------
	local diamondsBefore = PlayerProfile.get(fakePlayer).Diamonds
	local okBadCredit, badReason = EconomyService.credit(fakePlayer, "Shards" :: any, 100, "test_bad")
	check(not okBadCredit and badReason == "invalid_currency", "EconomyService.credit must reject invalid currency (CURR-1)")
	check(PlayerProfile.get(fakePlayer).Diamonds == diamondsBefore, "Diamonds must not be mutated on invalid credit (CURR-1)")

	local okBadDebit, badDebitReason = EconomyService.debit(fakePlayer, "Shards" :: any, 100, "test_bad")
	check(not okBadDebit and badDebitReason == "invalid_currency", "EconomyService.debit must reject invalid currency (CURR-1)")

	local badBal = EconomyService.balance(fakePlayer, "Shards" :: any)
	check(badBal == nil, "EconomyService.balance must return nil for unknown currency (CURR-1)")

	local canAffordBad = EconomyService.canAfford(fakePlayer, "Shards" :: any, 10)
	check(not canAffordBad, "EconomyService.canAfford must return false for unknown currency (CURR-1)")

	PlayerProfile.releaseAll()
	return true, nil, asserts
end

return {
	name = "PassEffects.test",
	run = PassEffectsTest.run,
}
