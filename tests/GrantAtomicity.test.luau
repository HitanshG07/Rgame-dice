--!strict
-- GrantAtomicity.test.luau
-- CURR-1 and LOGIN-1: the two paid grants that wrote currency without going
-- through EconomyService, and what each one lost by doing so.
--
-- WHY THESE TWO ARE PINNED TOGETHER. Both are the same shape -- a grant that
-- the player has already paid for (Robux for the bundle, a seven-day streak for
-- the login reward) resolved by code that reaches around the one module allowed
-- to move currency. The bundle lost the ceiling clamp and the LifetimeCash
-- accumulation and silently skipped any currency its three branches did not
-- name; the login reward discarded the credit result entirely. Neither had a
-- test, which is how both survived seven batches of review.
--
-- EVERY ASSERTION HERE FAILS IF ITS FIX IS REVERTED. The two atomicity pins do
-- it by forcing a write to fail mid-grant, which is the only state where a
-- correct and an incorrect ordering look different.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Catalog = require(Shared:WaitForChild("MonetisationCatalog"))
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local PurchaseService = require(Server:WaitForChild("PurchaseService"))
local ProgressionService = require(Server:WaitForChild("ProgressionService"))
local Fakes = require(ServerScriptService:WaitForChild("Tests"):WaitForChild("Fakes"))

local GrantAtomicityTest = {}

-- A resolved Bundle entry that exists only in this file. `assetId` is positive
-- so `isResolved` passes; the id names no real product and the entry is never
-- registered with the catalog, so nothing can be bought with it. `amount` is
-- left nil deliberately: a positive one would also grant a die slot and this
-- suite is about the currency parts.
local function bundleEntry(parts: { { currency: string, amount: number } }): Catalog.Entry
	return {
		key = "GrantAtomicityFixture",
		assetId = 999000111,
		name = "Fixture Bundle",
		blurb = "test fixture",
		kind = "Bundle" :: Catalog.GrantKind,
		bundle = parts,
	}
end

function GrantAtomicityTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	PlayerProfile.init()

	----------------------------------------------------------------------------
	-- CURR-1 (a): a bundle's Cash must count like any other Cash
	----------------------------------------------------------------------------
	--
	-- The loop did `data.Cash += part.amount` directly, which moves the balance
	-- and nothing else. `LifetimeCash` is what the NetWorth leaderboard ranks on,
	-- so bundle Cash was worth strictly less than identical Cash bought through a
	-- `Currency` product -- the same money, two different values, depending on
	-- which row of the shop it came from.
	local buyer = Fakes.createFakePlayer(778801, "TestBundleBuyer")
	local buyerData = PlayerProfile._reconcile({})
	local buyerProfile = Fakes.createFakeProfile(buyerData)
	PlayerProfile._injectProfileForTesting(buyer, buyerProfile)

	buyerData.Cash = 0
	buyerData.Gems = 0
	buyerData.LifetimeCash = 0

	local okCash, cashReason = PurchaseService._applyGrantForTesting(buyer, bundleEntry({
		{ currency = "Cash", amount = 5000 },
		{ currency = "Gems", amount = 250 },
	}))
	check(okCash, "a well-formed bundle must grant: " .. tostring(cashReason))
	check(buyerData.Cash == 5000, "the bundle's Cash part must reach the balance")
	check(buyerData.Gems == 250, "the bundle's Gems part must reach the balance")
	check(buyerData.LifetimeCash == 5000,
		"bundle Cash must accumulate into LifetimeCash exactly as Currency-product Cash does (CURR-1)")

	----------------------------------------------------------------------------
	-- CURR-1 (b): the ceiling applies to bundles too
	----------------------------------------------------------------------------
	--
	-- A raw `+=` has no clamp, so a player already at the representable ceiling
	-- was written straight past it -- the direction that ends in a non-finite
	-- balance and a poisoned profile.
	buyerData.Cash = 1e300
	buyerData.LifetimeCash = 1e300
	local okClamp = PurchaseService._applyGrantForTesting(buyer, bundleEntry({
		{ currency = "Cash", amount = 1e300 },
	}))
	check(okClamp, "a bundle granted at the ceiling must still succeed")
	check(buyerData.Cash <= 1e300,
		"a bundle must not write Cash past the MAX_CURRENCY ceiling (CURR-1)")
	check(buyerData.LifetimeCash <= 1e300,
		"a bundle must not write LifetimeCash past the MAX_CURRENCY ceiling (CURR-1)")

	----------------------------------------------------------------------------
	-- CURR-1 (c): an unrecognised currency fails the WHOLE grant
	----------------------------------------------------------------------------
	--
	-- This is the pin that matters the day `Shards` is added. The old loop had no
	-- `else`, so an unlisted currency was skipped in silence and the grant still
	-- reported success -- the player paid Robux and received the other parts
	-- only, with the type system unable to flag it once the union widened.
	--
	-- Totality is only half of it: the refusal must also leave the profile
	-- untouched, because a half-applied bundle that reports failure gets retried
	-- by the platform and grants its landed parts a second time.
	buyerData.Gems = 7
	local okUnknown, unknownReason = PurchaseService._applyGrantForTesting(buyer, bundleEntry({
		{ currency = "Gems", amount = 250 },
		{ currency = "Shards", amount = 10 },
	}))
	check(not okUnknown, "a bundle part naming an unrecognised currency must fail the whole grant (CURR-1)")
	check(unknownReason == "invalid_currency",
		"the refusal must name the cause, got: " .. tostring(unknownReason))
	check(buyerData.Gems == 7,
		"a refused bundle must write NOTHING -- a part that landed before the refusal would be"
		.. " granted twice by the platform retry (CURR-1)")

	----------------------------------------------------------------------------
	-- LOGIN-1: the streak advance and the reward are one write
	----------------------------------------------------------------------------
	--
	-- `recordLogin` advanced the streak and then called `credit` discarding its
	-- result. A profile released between those two calls cost the player the
	-- reward PERMANENTLY: the streak had moved, so that day was never offered
	-- again. The three sibling claim paths roll their flag back instead, which
	-- cannot help here -- the rollback is itself a mutate, and it fails for the
	-- same reason the credit just did.
	--
	-- FORCING IT: the profile reports active only until the streak day is
	-- written, so any SECOND write in the same call is refused exactly as a
	-- release between the two would refuse it.
	local claimer = Fakes.createFakePlayer(778802, "TestLoginPlayer")
	local claimerData = PlayerProfile._reconcile({})
	local claimerProfile = Fakes.createFakeProfile(claimerData)
	PlayerProfile._injectProfileForTesting(claimer, claimerProfile)

	claimerData.Cash = 0
	claimerData.LoginStreak.Count = 0
	claimerData.LoginStreak.LastDay = 0

	claimerProfile.IsActive = function(self: any): boolean
		return self._is_active and claimerData.LoginStreak.LastDay == 0
	end

	local okLogin = ProgressionService.recordLogin(claimer)

	claimerProfile.IsActive = function(self: any): boolean
		return self._is_active
	end

	local streakMoved = claimerData.LoginStreak.LastDay ~= 0
	local wasPaid = claimerData.Cash > 0
	check(streakMoved == wasPaid,
		"the streak advance and the login reward must land in the SAME write (LOGIN-1) -- streakMoved="
		.. tostring(streakMoved) .. ", wasPaid=" .. tostring(wasPaid))
	check(okLogin == wasPaid,
		"recordLogin must not report success for a day it did not pay for")

	-- And the ordinary path still works: a healthy profile gets the day-1 reward
	-- and the streak, so the fix above did not buy its safety by paying nobody.
	claimerData.Cash = 0
	claimerData.LoginStreak.Count = 0
	claimerData.LoginStreak.LastDay = 0
	local okHealthy, countHealthy = ProgressionService.recordLogin(claimer)
	check(okHealthy, "a healthy profile must record the login")
	check(countHealthy == 1, "a first login must set the streak to 1")
	check(claimerData.Cash == 300, "the day-1 login reward must be credited")
	check(claimerData.LoginStreak.LastDay ~= 0, "a recorded login must stamp the day")

	PlayerProfile.releaseAll()
	return true, nil, asserts
end

return {
	name = "GrantAtomicity.test",
	run = GrantAtomicityTest.run,
}
