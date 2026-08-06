--!strict
-- RateLimiter.luau
-- Dedicated token-bucket rate limiter module (HLD §3 C-1).
-- Per-player, per-remote buckets enforcing sustained and burst limits (API_DATA_CONTRACT.md §2.2).

local RateLimiter = {}

export type Limit = { sustained: number, burst: number }
export type Bucket = { tokens: number, last: number }

local LIMITS: { [string]: Limit } = {
	Roll = { sustained = 5, burst = 10 },
	Forge = { sustained = 4, burst = 8 },
	SetElement = { sustained = 4, burst = 8 },
	SetShape = { sustained = 4, burst = 8 },
	BuyUpgrade = { sustained = 4, burst = 8 },
	BuyDiamondNode = { sustained = 4, burst = 8 },
	AddDieSlot = { sustained = 4, burst = 8 },
	GetLeaderboard = { sustained = 0.5, burst = 2 },
	RedeemCode = { sustained = 0.2, burst = 3 },
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
