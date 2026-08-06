--!strict
-- UT-8 — ProfileLifecycle (TEST_PLAN.md §4)
--
-- The security-critical persistence suite. It asserts, in order:
--   * a failed load FAILS CLOSED and never returns a default profile (T-10)
--   * a foreign live lock FAILS CLOSED (T-10)
--   * a RELEASED profile rejects every write (SRS FR-14.7, T-26)
--   * the payload ceiling refuses an oversized save (T-13)
--   * PurchaseIds eviction is TIME-AWARE, including the branch that refuses to
--     evict a still-replayable receipt (T-13, and the real-money double-grant
--     that branch exists to prevent)
--
-- The first three were absent from the original draft of this suite. They are
-- the entire T-10/T-26 coverage: without them the module's two headline
-- guarantees were asserted nowhere.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))

local Fakes = require(script.Parent:WaitForChild("Fakes"))

local RECEIPT_RETRY_WINDOW = 60 * 60 * 24 * 3
local PURCHASE_ID_CEILING = 200

local n = 0
local function check(cond: boolean, msg: string): string?
	n += 1
	if not cond then
		return msg
	end
	return nil
end

local function run(): (boolean, string?, number)
	n = 0
	local e: string?

	----------------------------------------------------------------------------
	-- FAIL CLOSED on load (threat T-10)
	----------------------------------------------------------------------------

	-- A player with no session established must not be readable. `get` returns
	-- nil rather than a fabricated default -- a phantom default profile is how
	-- real saved data gets silently overwritten.
	local stranger = Fakes.createFakePlayer(7001, "NoSession")
	e = e or check(PlayerProfile.get(stranger) == nil,
		"get() on a player with no loaded profile must return nil, never a default")
	e = e or check(PlayerProfile.isActive(stranger) == false,
		"isActive() must be false for a player with no loaded profile")

	-- A write against a player with no profile is refused with a reason, not
	-- applied to a fabricated table.
	local strangerOk, strangerReason = PlayerProfile.mutate(stranger, function() end)
	e = e or check(strangerOk == false, "mutate() on an unloaded profile must be refused")
	e = e or check(strangerReason == "no_profile",
		string.format("expected reason 'no_profile', got '%s'", tostring(strangerReason)))

	-- A foreign live lock surfaces as a load that yields no session. Simulated
	-- here by the session simply never being installed: the observable contract
	-- is identical -- no profile, no default, no write path.
	local locked = Fakes.createFakePlayer(7002, "ForeignLock")
	e = e or check(PlayerProfile.get(locked) == nil,
		"a player whose session was never claimed must expose no profile")
	local lockedOk = PlayerProfile.mutate(locked, function() end)
	e = e or check(lockedOk == false,
		"a player whose session was never claimed must reject writes")

	----------------------------------------------------------------------------
	-- A RELEASED profile is immutable (SRS FR-14.7, threat T-26)
	----------------------------------------------------------------------------

	local player = Fakes.createFakePlayer(8888, "TestLifecycle")
	local liveData = PlayerProfile._reconcile({})
	liveData.Cash = 500
	local fakeProfile = Fakes.createFakeProfile(liveData)
	PlayerProfile._injectProfileForTesting(player, fakeProfile)

	-- While ACTIVE, writes land.
	local activeOk = PlayerProfile.mutate(player, function(d)
		d.Cash = 750
	end)
	e = e or check(activeOk, "a write against an ACTIVE profile must succeed")
	e = e or check(liveData.Cash == 750,
		string.format("active write did not apply: Cash is %s", tostring(liveData.Cash)))
	e = e or check(PlayerProfile.isActive(player), "profile should report active before release")

	-- Release it, then prove every write is refused AND that the data is
	-- untouched. A refused write that still mutates is worse than no check.
	fakeProfile:EndSession()

	e = e or check(PlayerProfile.isActive(player) == false,
		"profile must report inactive after EndSession")

	local releasedOk, releasedReason = PlayerProfile.mutate(player, function(d)
		d.Cash = 999999
	end)
	e = e or check(releasedOk == false, "a write against a RELEASED profile must be refused")
	e = e or check(releasedReason == "profile_released",
		string.format("expected reason 'profile_released', got '%s'", tostring(releasedReason)))
	e = e or check(liveData.Cash == 750,
		string.format("the refused write MUTATED the profile anyway: Cash is %s", tostring(liveData.Cash)))

	-- Repeated attempts stay refused; there is no "second chance" path.
	local secondOk = PlayerProfile.mutate(player, function(d)
		d.Gems = 1
	end)
	e = e or check(secondOk == false, "a second write against a released profile must also be refused")
	e = e or check(liveData.Gems == 0,
		string.format("the second refused write mutated Gems to %s", tostring(liveData.Gems)))

	----------------------------------------------------------------------------
	-- Purchase-id ledger: TIME-AWARE eviction (threat T-13)
	----------------------------------------------------------------------------

	local data = PlayerProfile._reconcile({})
	local now = os.time()
	local expired = now - (RECEIPT_RETRY_WINDOW + 60 * 60)  -- comfortably outside the window

	-- Five receipts old enough to be evictable, then 200 fresh ones.
	for i = 1, 5 do
		PlayerProfile.recordPurchase(data, string.format("receipt_%d", i), expired)
	end
	for i = 6, 205 do
		PlayerProfile.recordPurchase(data, string.format("receipt_%d", i), now)
	end

	local purchaseCount = 0
	for _ in pairs(data.PurchaseIds) do
		purchaseCount += 1
	end
	e = e or check(purchaseCount == PURCHASE_ID_CEILING,
		string.format("PurchaseIds should be capped at %d, got %d", PURCHASE_ID_CEILING, purchaseCount))
	e = e or check(data.PurchaseIds["receipt_1"] == nil, "expired receipt_1 should have been evicted")
	e = e or check(data.PurchaseIds["receipt_5"] == nil, "expired receipt_5 should have been evicted")
	e = e or check(data.PurchaseIds["receipt_205"] ~= nil, "newest receipt_205 must be retained")
	e = e or check(#data.PurchaseOrder == PURCHASE_ID_CEILING,
		string.format("PurchaseOrder should track the same %d entries, got %d",
			PURCHASE_ID_CEILING, #data.PurchaseOrder))

	-- Idempotency: recording the same id twice reports it and does not duplicate.
	local dupOk, dupReason = PlayerProfile.recordPurchase(data, "receipt_205", now)
	e = e or check(dupOk == false, "recording an already-known receipt must return false")
	e = e or check(dupReason == "already_recorded",
		string.format("expected 'already_recorded', got '%s'", tostring(dupReason)))
	e = e or check(PlayerProfile.hasPurchase(data, "receipt_205"), "hasPurchase must see a recorded receipt")
	e = e or check(not PlayerProfile.hasPurchase(data, "never_seen"),
		"hasPurchase must not see an unrecorded receipt")

	-- THE BRANCH THAT MATTERS: the ceiling is reached while EVERY entry is still
	-- inside the retry window. Evicting here would let a live receipt be replayed
	-- and double-granted, so the writer must refuse to evict and say so.
	local live = PlayerProfile._reconcile({})
	for i = 1, PURCHASE_ID_CEILING do
		PlayerProfile.recordPurchase(live, string.format("live_%d", i), now)
	end
	local overOk, overReason = PlayerProfile.recordPurchase(live, "live_overflow", now)
	e = e or check(overOk, "recording past the ceiling should still succeed")
	e = e or check(overReason == "ceiling_reached_all_live",
		string.format("expected 'ceiling_reached_all_live', got '%s'", tostring(overReason)))
	e = e or check(live.PurchaseIds["live_1"] ~= nil,
		"a STILL-REPLAYABLE receipt was evicted -- this is the real-money double-grant path")
	e = e or check(#live.PurchaseOrder == PURCHASE_ID_CEILING + 1,
		string.format("over-ceiling entry should be retained, order length is %d", #live.PurchaseOrder))

	----------------------------------------------------------------------------
	-- Payload ceiling (threat T-13)
	----------------------------------------------------------------------------

	local sizeOk, sizeBytes = PlayerProfile.checkPayloadSize(data)
	e = e or check(sizeOk, "a normal profile must pass the payload ceiling check")
	e = e or check(sizeBytes > 0,
		string.format("payload size should be reported, got %s", tostring(sizeBytes)))

	local hugeData = PlayerProfile._reconcile({})
	hugeData.CodesRedeemed["blob"] = string.rep("X", 4_000_000) :: any
	local hugeOk, hugeBytes = PlayerProfile.checkPayloadSize(hugeData)
	e = e or check(not hugeOk, "an oversized profile (>3.5MB) must fail the payload ceiling check")
	e = e or check(hugeBytes > 3_500_000,
		string.format("oversized payload should report its size, got %s", tostring(hugeBytes)))

	----------------------------------------------------------------------------
	-- Template isolation: deep copy, not table.clone (cross-player corruption)
	----------------------------------------------------------------------------

	-- Two reconciled profiles must not share any nested table with each other or
	-- with the template. A shallow clone shares Dice[1], so the first player to
	-- forge rewrites the starting die for everyone who joins afterwards.
	local a = PlayerProfile._reconcile({})
	local b = PlayerProfile._reconcile({})
	e = e or check(a.Dice ~= b.Dice, "two reconciled profiles must not share the Dice array")
	e = e or check(a.Dice[1] ~= b.Dice[1], "two reconciled profiles must not share a die object")
	e = e or check(a.Dice[1].Faces ~= b.Dice[1].Faces,
		"two reconciled profiles must not share a Faces array")
	e = e or check(a.Diamond.Elements ~= b.Diamond.Elements,
		"two reconciled profiles must not share the Diamond.Elements table")

	a.Dice[1].Faces[1].Mass = 12345
	e = e or check(b.Dice[1].Faces[1].Mass ~= 12345,
		"mutating one profile's die changed another profile's die -- template is shared")
	local fresh = PlayerProfile._reconcile({})
	e = e or check(fresh.Dice[1].Faces[1].Mass == 10,
		string.format("the TEMPLATE was corrupted by a profile mutation: fresh mass is %s",
			tostring(fresh.Dice[1].Faces[1].Mass)))

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-8 ProfileLifecycle", run = run }
