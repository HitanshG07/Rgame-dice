--!strict
-- RateLimiter.luau
-- Dedicated token-bucket rate limiter module (HLD §3 C-1).
-- Per-player, per-remote buckets enforcing sustained and burst limits (API_DATA_CONTRACT.md §2.2).

local RateLimiter = {}

export type Limit = { sustained: number, burst: number }
export type Bucket = { tokens: number, last: number }

local LIMITS: { [string]: Limit } = {
	-- MANUAL ROLLING IS SLOWER THAN AUTO-ROLL (operator decision, 2026-08-13).
	--
	-- This was 5/sec sustained with a burst of 10 -- the same ceiling FR-2.4
	-- gives AUTO-ROLL, which is a paid gamepass. Two problems with that: holding
	-- the button spammed the server as fast as an exploiter could, and the pass
	-- bought nothing except not having to tap.
	--
	-- RETUNED 2026-08-13 (operator): 5 manual rolls per 5 seconds -- 1/sec --
	-- against auto-roll's 8 per 5 seconds. Auto keeps a 1.6x advantage so the
	-- gamepass is worth owning, and the overall pace is calmer than the 2.5/sec
	-- it replaced: a roll becomes a deliberate act rather than something to hold
	-- the button down for.
	--
	-- The burst of 3 absorbs an impatient double-tap without letting a player
	-- bank a long idle into a flurry.
	--
	-- THIS IS THE ENFORCEMENT. The client's cooldown is presentation only -- an
	-- exploiter runs their own client and never sees it.
	Roll = { sustained = 1.0, burst = 3 },
	Forge = { sustained = 4, burst = 8 },
	SetElement = { sustained = 4, burst = 8 },
	SetShape = { sustained = 4, burst = 8 },
	BuyUpgrade = { sustained = 4, burst = 8 },
	BuyDiamondNode = { sustained = 4, burst = 8 },
	AddDieSlot = { sustained = 4, burst = 8 },
	GetLeaderboard = { sustained = 0.5, burst = 2 },
	RedeemCode = { sustained = 0.2, burst = 3 },
	-- Settings are cheap to write and a player flicking four toggles in a row is
	-- ordinary behaviour, so the burst is generous. The sustained rate still
	-- stops a loop from hammering the profile.
	SetSetting = { sustained = 3, burst = 8 },
	-- Dragging dice around is a fiddly, repeated action, so the burst is
	-- generous. It moves no value -- the same dice in a different order -- so a
	-- high rate costs nothing but a profile write.
	SwapDice = { sustained = 4, burst = 8 },
}

local DEFAULT_LIMIT: Limit = { sustained = 2, burst = 5 }

local buckets: { [Player]: { [string]: Bucket } } = {}
local rejections: { [Player]: number } = {}

function RateLimiter.limitFor(name: string): Limit
	return LIMITS[name] or DEFAULT_LIMIT
end

-- `atTime` exists so a test can advance the clock and observe refill without
-- sleeping. It is OPTIONAL and defaults to the real monotonic clock; the only
-- production caller (RemoteGateway) never passes it. A supplied value is
-- treated as untrusted: non-finite or backwards time falls back to os.clock(),
-- so it can never be used to manufacture tokens.
function RateLimiter.consume(player: Player, name: string, atTime: number?): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end

	local limit = RateLimiter.limitFor(name)
	local now = os.clock()
	if type(atTime) == "number" and atTime == atTime
		and atTime < math.huge and atTime > -math.huge then
		now = atTime
	end
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = limit.burst, last = now }
		perPlayer[name] = bucket
	end

	-- Refill
	local elapsed = now - bucket.last
	if elapsed > 0 then
		bucket.tokens = math.min(limit.burst, bucket.tokens + elapsed * limit.sustained)
		bucket.last = now
	end

	if bucket.tokens < 1 then
		RateLimiter.recordRejection(player)
		return false
	end

	bucket.tokens -= 1
	return true
end

function RateLimiter.recordRejection(player: Player): ()
	rejections[player] = (rejections[player] or 0) + 1
end

function RateLimiter.rejectionCount(player: Player): number
	return rejections[player] or 0
end

function RateLimiter.clearPlayer(player: Player): ()
	buckets[player] = nil
	rejections[player] = nil
end

return RateLimiter
