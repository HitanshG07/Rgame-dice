--!strict
-- UT-6 — RateLimit (TEST_PLAN.md §4)
--
-- Token buckets enforce the API_DATA_CONTRACT §2.2 sustained and burst rates
-- per remote. Over-budget calls are dropped and counted, buckets REFILL over
-- time, and one player's exhaustion does not affect another's.
--
-- Refill and per-remote independence were absent from the original draft. The
-- refill path is the half of a token bucket that decides whether a legitimate
-- player is permanently locked out after one burst, so it is not optional
-- coverage.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local RateLimiter = require(Server:WaitForChild("RateLimiter"))

local Fakes = require(script.Parent:WaitForChild("Fakes"))

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
	-- Typed `any` rather than `string?` for one specific Luau reason: the
	-- accumulator idiom `e = e or check(...)` produces a refinement union the
	-- checker cannot collapse back to `string?`, which warns at every call site.
	-- Semantics are unchanged (check still runs only while e is nil) and nothing
	-- is hidden: `e` is a local failure message whose only use is the return below.
	local e: any = nil

	local p1 = Fakes.createFakePlayer(1001, "PlayerOne")
	local p2 = Fakes.createFakePlayer(1002, "PlayerTwo")

	RateLimiter.clearPlayer(p1)
	RateLimiter.clearPlayer(p2)

	----------------------------------------------------------------------------
	-- Configured limits match the data contract
	----------------------------------------------------------------------------

	-- MANUAL ROLLING IS SLOWER THAN AUTO-ROLL (operator decision, 2026-08-13;
	-- API_DATA_CONTRACT §2.2 amended the same day).
	--
	-- This asserted 5/s burst 10, matching the FR-2.4 AUTO-ROLL ceiling. That
	-- made the Auto-Roll gamepass worthless -- a tapping player got the paid
	-- rate for free -- and let the button be spammed. The auto-roll loop is
	-- server-driven and never passes through this bucket, so lowering the remote
	-- does not slow auto-roll down.
	local rollLimit = RateLimiter.limitFor("Roll")
	e = e or check(rollLimit.sustained == 2.5 and rollLimit.burst == 5,
		"manual Roll must be sustained=2.5 burst=5 per API_DATA_CONTRACT §2.2")

	-- THE RELATIONSHIP, not just the number. The point of the change is that
	-- manual is strictly slower than the paid auto ceiling; asserting only the
	-- literal would let a future edit raise it back to parity and stay green.
	e = e or check(rollLimit.sustained < 5,
		"manual Roll must stay BELOW the 5/s auto-roll ceiling, or the Auto-Roll"
		.. " gamepass confers no advantage")

	local forgeLimit = RateLimiter.limitFor("Forge")
	e = e or check(forgeLimit.burst == 8 and forgeLimit.sustained == 4,
		"Forge limit must be sustained=4 burst=8 per API_DATA_CONTRACT §2.2")

	-- An unknown remote name gets the restrictive default, never unlimited.
	local unknown = RateLimiter.limitFor("SomeRemoteThatDoesNotExist")
	e = e or check(unknown.burst > 0 and unknown.burst <= 10,
		"an unregistered remote must fall back to a bounded default limit")

	----------------------------------------------------------------------------
	-- Burst cap, and over-budget calls are dropped AND counted
	----------------------------------------------------------------------------

	-- DERIVED FROM THE CONFIGURED LIMIT, not hardcoded. These asserted a literal
	-- burst of 10 and sustained of 5, so lowering the manual roll rate broke
	-- tests that were meant to prove the BUCKET WORKS, not what the number is.
	-- The number itself is asserted once, above; everything here tests behaviour
	-- and now survives a retune.
	local burst = rollLimit.burst
	local sustained = rollLimit.sustained

	-- Anchored ahead of the real monotonic clock, so the hostile-clock cases
	-- below (which fall back to os.clock()) see a BACKWARDS jump and therefore
	-- no refill. A fixed literal would be behind os.clock() on a long-lived
	-- server and the fallback would silently refill the bucket.
	local t = os.clock() + 100000.0
	for i = 1, burst do
		local ok = RateLimiter.consume(p1, "Roll", t)
		e = e or check(ok, string.format("token %d should be granted within the burst cap", i))
	end

	local rejected = RateLimiter.consume(p1, "Roll", t)
	e = e or check(not rejected, string.format(
		"token %d in the same instant must be rejected (burst is %d)", burst + 1, burst))
	e = e or check(RateLimiter.rejectionCount(p1) == 1,
		string.format("rejection count should be 1, got %d", RateLimiter.rejectionCount(p1)))

	local rejectedAgain = RateLimiter.consume(p1, "Roll", t)
	e = e or check(not rejectedAgain, "a second over-budget call must also be rejected")
	e = e or check(RateLimiter.rejectionCount(p1) == 2,
		string.format("rejection count should be 2, got %d", RateLimiter.rejectionCount(p1)))

	----------------------------------------------------------------------------
	-- BUCKETS REFILL at the sustained rate
	----------------------------------------------------------------------------

	-- One second later exactly `sustained` tokens are back -- no more, no less.
	-- `sustained` may be fractional (2.5), so the whole-token count available
	-- after one second is its floor.
	local refilled = math.floor(sustained)
	local ok1 = RateLimiter.consume(p1, "Roll", t + 1.0)
	e = e or check(ok1, "a token must be available one second after exhaustion (refill)")
	for i = 2, refilled do
		local ok = RateLimiter.consume(p1, "Roll", t + 1.0)
		e = e or check(ok, string.format("refilled token %d should be granted", i))
	end
	local overRefill = RateLimiter.consume(p1, "Roll", t + 1.0)
	e = e or check(not overRefill,
		"refill must grant exactly `sustained` tokens per second, not more")

	-- Refill is CAPPED at burst: waiting an hour does not bank thousands.
	for i = 1, burst do
		local ok = RateLimiter.consume(p1, "Roll", t + 3600.0)
		e = e or check(ok, string.format("token %d should be granted after a long idle", i))
	end
	local overCap = RateLimiter.consume(p1, "Roll", t + 3600.0)
	e = e or check(not overCap,
		"an idle bucket must cap at `burst`, never accumulate unbounded tokens")

	----------------------------------------------------------------------------
	-- Buckets are independent PER REMOTE
	----------------------------------------------------------------------------

	-- Roll is exhausted for p1 at this instant; Forge must be untouched.
	local forgeOk = RateLimiter.consume(p1, "Forge", t + 3600.0)
	e = e or check(forgeOk,
		"exhausting one remote's bucket must not exhaust another remote's bucket")

	----------------------------------------------------------------------------
	-- Buckets are independent PER PLAYER
	----------------------------------------------------------------------------

	local p2Ok = RateLimiter.consume(p2, "Roll", t + 3600.0)
	e = e or check(p2Ok, "one player's exhaustion must not affect another player")
	e = e or check(RateLimiter.rejectionCount(p2) == 0,
		"player 2's rejection count must remain 0")

	----------------------------------------------------------------------------
	-- A hostile `atTime` cannot manufacture tokens
	----------------------------------------------------------------------------

	-- The seam accepts an optional clock for testing. Non-finite values must be
	-- ignored in favour of the real clock rather than being used to refill.
	RateLimiter.clearPlayer(p2)
	for _ = 1, burst do
		RateLimiter.consume(p2, "Roll", t)
	end
	local nanAttempt = RateLimiter.consume(p2, "Roll", 0 / 0)
	e = e or check(not nanAttempt, "a NaN clock must not refill an exhausted bucket")
	local infAttempt = RateLimiter.consume(p2, "Roll", math.huge)
	e = e or check(not infAttempt, "an infinite clock must not refill an exhausted bucket")

	----------------------------------------------------------------------------
	-- F-4A-1: declared arity must cover every remote in the contract
	----------------------------------------------------------------------------

	-- `Roll(999)` used to be accepted and processed. The contract says any
	-- argument rejects the call. Arity is now declared centrally and enforced in
	-- bind(); the enforcement itself needs a real RemoteFunction, so what is
	-- testable here is that the DECLARATION is complete and correct -- a remote
	-- missing from the table would be wired with no arity check at all.
	local RemoteGateway = require(Server:WaitForChild("RemoteGateway"))
	local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)

	local undeclared: { string } = {}
	for _, name in pairs(Remotes.Fn) do
		if RemoteGateway.arityFor(name) == nil then
			table.insert(undeclared, name)
		end
	end
	e = e or check(#undeclared == 0, string.format(
		"remotes with no declared arity: %s", table.concat(undeclared, ", ")))

	-- Spot-check the values against API_DATA_CONTRACT §1.1 directly, so a typo in
	-- the table is caught rather than merely being present.
	e = e or check(RemoteGateway.arityFor("Roll") == 0, "Roll must be declared zero-arity")
	-- AddDieSlot takes ONE argument as of 2026-08-13: the shape for the new die,
	-- or the empty string for the starting shape (API_DATA_CONTRACT §1.1). It was
	-- zero-arity when it could only ever create the starting shape.
	e = e or check(RemoteGateway.arityFor("AddDieSlot") == 1,
		"AddDieSlot must take one argument -- the shape id, or \"\" for the default")
	e = e or check(RemoteGateway.arityFor("Ascend") == 0, "Ascend must be declared zero-arity")
	e = e or check(RemoteGateway.arityFor("DailySpin") == 0, "DailySpin must be declared zero-arity")
	e = e or check(RemoteGateway.arityFor("ClaimGroupReward") == 0, "ClaimGroupReward must be declared zero-arity")
	e = e or check(RemoteGateway.arityFor("Forge") == 2, "Forge takes dieIndex and distribution")
	e = e or check(RemoteGateway.arityFor("SetElement") == 3, "SetElement takes dieIndex, faceIndex, elementId")
	e = e or check(RemoteGateway.arityFor("SetShape") == 2, "SetShape takes dieIndex and shapeId")
	e = e or check(RemoteGateway.arityFor("BuyUpgrade") == 1, "BuyUpgrade takes an id only -- never a price")
	e = e or check(RemoteGateway.arityFor("SetAutoRoll") == 1, "SetAutoRoll takes a boolean -- never an interval")
	e = e or check(RemoteGateway.arityFor("RedeemCode") == 1, "RedeemCode takes a code")
	e = e or check(RemoteGateway.arityFor("GetLeaderboard") == 1, "GetLeaderboard takes a boardId")

	-- An undeclared name reports nil rather than defaulting to something
	-- permissive; bind() turns that into a startup error.
	e = e or check(RemoteGateway.arityFor("NotARealRemote") == nil,
		"an undeclared remote must report nil arity, never a default")

	----------------------------------------------------------------------------
	-- Cleanup releases per-player state
	----------------------------------------------------------------------------

	RateLimiter.clearPlayer(p1)
	RateLimiter.clearPlayer(p2)
	e = e or check(RateLimiter.rejectionCount(p1) == 0, "clearPlayer must reset p1's rejections")
	e = e or check(RateLimiter.rejectionCount(p2) == 0, "clearPlayer must reset p2's rejections")
	local afterClear = RateLimiter.consume(p1, "Roll", t)
	e = e or check(afterClear, "a cleared player must get a fresh full bucket")

	RateLimiter.clearPlayer(p1)
	RateLimiter.clearPlayer(p2)

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-6 RateLimit", run = run }
