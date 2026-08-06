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
	local e: string?

	local p1 = Fakes.createFakePlayer(1001, "PlayerOne")
	local p2 = Fakes.createFakePlayer(1002, "PlayerTwo")

	RateLimiter.clearPlayer(p1)
	RateLimiter.clearPlayer(p2)

	----------------------------------------------------------------------------
	-- Configured limits match the data contract
	----------------------------------------------------------------------------

	local rollLimit = RateLimiter.limitFor("Roll")
	e = e or check(rollLimit.burst == 10 and rollLimit.sustained == 5,
		"Roll limit must be sustained=5 burst=10 per API_DATA_CONTRACT §2.2")

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

	-- Anchored ahead of the real monotonic clock, so the hostile-clock cases
	-- below (which fall back to os.clock()) see a BACKWARDS jump and therefore
	-- no refill. A fixed literal would be behind os.clock() on a long-lived
	-- server and the fallback would silently refill the bucket.
	local t = os.clock() + 100000.0
	for i = 1, 10 do
		local ok = RateLimiter.consume(p1, "Roll", t)
		e = e or check(ok, string.format("token %d should be granted within the burst cap", i))
	end

	local rejected = RateLimiter.consume(p1, "Roll", t)
	e = e or check(not rejected, "the 11th token in the same instant must be rejected")
	e = e or check(RateLimiter.rejectionCount(p1) == 1,
		string.format("rejection count should be 1, got %d", RateLimiter.rejectionCount(p1)))

	local rejectedAgain = RateLimiter.consume(p1, "Roll", t)
	e = e or check(not rejectedAgain, "a second over-budget call must also be rejected")
	e = e or check(RateLimiter.rejectionCount(p1) == 2,
		string.format("rejection count should be 2, got %d", RateLimiter.rejectionCount(p1)))

	----------------------------------------------------------------------------
	-- BUCKETS REFILL at the sustained rate
	----------------------------------------------------------------------------

	-- One second later, at sustained=5, five tokens are back -- no more, no less.
	local ok1 = RateLimiter.consume(p1, "Roll", t + 1.0)
	e = e or check(ok1, "a token must be available one second after exhaustion (refill)")
	for i = 2, 5 do
		local ok = RateLimiter.consume(p1, "Roll", t + 1.0)
		e = e or check(ok, string.format("refilled token %d should be granted", i))
	end
	local overRefill = RateLimiter.consume(p1, "Roll", t + 1.0)
	e = e or check(not overRefill,
		"refill must grant exactly `sustained` tokens per second, not more")

	-- Refill is CAPPED at burst: waiting an hour does not bank 18,000 tokens.
	for i = 1, 10 do
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
	for _ = 1, 10 do
		RateLimiter.consume(p2, "Roll", t)
	end
	local nanAttempt = RateLimiter.consume(p2, "Roll", 0 / 0)
	e = e or check(not nanAttempt, "a NaN clock must not refill an exhausted bucket")
	local infAttempt = RateLimiter.consume(p2, "Roll", math.huge)
	e = e or check(not infAttempt, "an infinite clock must not refill an exhausted bucket")

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
