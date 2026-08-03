--!strict
-- RemoteGateway.luau
-- The SINGLE inbound trust boundary. Every remote in the game registers here;
-- no other module exposes one. Every exploit attempt arrives through this file.
--
-- Order is fixed and specified (API_DATA_CONTRACT.md §2):
--   rate limit -> arity -> type -> finiteness -> bounds -> allowlist -> affordability
--
-- Finiteness precedes bounds and sums because NaN fails every comparison, so a
-- range or sum check alone silently passes it (threats T-25, T-28).
--
-- A rejected call MUTATES NOTHING, logs server-side with the UserId, and returns
-- a generic enumerated reason. No stack trace, path, or internal value crosses
-- the boundary (threat T-7, Matrix E-8).
--
-- Never auto-kick on rate limit: lag produces false positives, and banning a
-- laggy player is worse than absorbing a dropped request (threat T-4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local RemoteGateway = {}

export type Handler = (player: Player, ...any) -> ...any

type Bucket = { tokens: number, last: number }
type Limit = { sustained: number, burst: number }

-- API_DATA_CONTRACT.md §2.2. `Roll` is refined at runtime against the player's
-- SERVER-KNOWN auto-roll tier; this is the hard ceiling no tier may exceed.
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

local MAX_STRING_CODE = 32
local MAX_STRING_ID = 64

local buckets: { [Player]: { [string]: Bucket } } = {}
local rejections: { [Player]: number } = {}
local handlers: { [string]: Handler } = {}

--------------------------------------------------------------------------------
-- Rate limiting (token bucket, per player per remote)
--------------------------------------------------------------------------------

local function limitFor(name: string): Limit
	return LIMITS[name] or DEFAULT_LIMIT
end

local function consume(player: Player, name: string): boolean
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end

	local limit = limitFor(name)
	local now = os.clock()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = limit.burst, last = now }
		perPlayer[name] = bucket
	end

	-- refill
	local elapsed = now - bucket.last
	if elapsed > 0 then
		bucket.tokens = math.min(limit.burst, bucket.tokens + elapsed * limit.sustained)
		bucket.last = now
	end

	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

--------------------------------------------------------------------------------
-- Validators. Every one returns ok, reason -- never throws across the boundary.
--------------------------------------------------------------------------------

local V = {}
RemoteGateway.validate = V

function V.finiteNumber(value: unknown): (boolean, string?)
	if not ForgeMath.isFinite(value) then
		return false, "not_finite"
	end
	return true, nil
end

function V.integerInRange(value: unknown, lo: number, hi: number): (boolean, string?)
	local ok, reason = V.finiteNumber(value)
	if not ok then
		return false, reason
	end
	local n = value :: number
	if n ~= math.floor(n) then
		return false, "not_integer"
	end
	if n < lo or n > hi then
		return false, "out_of_range"
	end
	return true, nil
end

function V.boundedString(value: unknown, maxLen: number): (boolean, string?)
	if type(value) ~= "string" then
		return false, "not_string"
	end
	if #(value :: string) == 0 then
		return false, "empty_string"
	end
	if #(value :: string) > maxLen then
		return false, "too_long"
	end
	return true, nil
end

function V.strictBoolean(value: unknown): (boolean, string?)
	if type(value) ~= "boolean" then
		return false, "not_boolean"
	end
	return true, nil
end

-- Allowlist resolution. The client's string is used to LOOK UP, never to index
-- directly into a live table (threats T-5, Matrix E-1/E-2).
function V.allowlisted(value: unknown, allow: { [string]: any }): (boolean, string?)
	local ok, reason = V.boundedString(value, MAX_STRING_ID)
	if not ok then
		return false, reason
	end
	if rawget(allow, value :: string) == nil then
		return false, "not_allowlisted"
	end
	return true, nil
end

function V.numberArray(value: unknown, maxLen: number): (boolean, string?)
	if type(value) ~= "table" then
		return false, "not_table"
	end
	local t = value :: { any }
	local n = #t
	if n == 0 or n > maxLen then
		return false, "bad_length"
	end
	for i = 1, n do
		if not ForgeMath.isFinite(t[i]) then
			return false, "non_finite_element"
		end
	end
	return true, nil
end

RemoteGateway.MAX_STRING_CODE = MAX_STRING_CODE
RemoteGateway.MAX_STRING_ID = MAX_STRING_ID

--------------------------------------------------------------------------------
-- Registration and dispatch
--------------------------------------------------------------------------------

local function reject(player: Player, name: string, reason: string): (boolean, string)
	rejections[player] = (rejections[player] or 0) + 1
	warn(string.format("[Gateway] rejected %s from UserId=%d: %s (total %d)",
		name, player.UserId, reason, rejections[player]))
	-- generic code outward; the detailed reason stays in the server log
	return false, Remotes.Notice.InvalidRequest
end

-- Handlers receive an already rate-limited call. They own their own argument
-- validation using the V.* helpers, and must return (ok, ...) without throwing.
function RemoteGateway.register(name: string, handler: Handler): ()
	if handlers[name] then
		error("[Gateway] duplicate registration for '" .. name .. "'", 2)
	end
	handlers[name] = handler
end

function RemoteGateway.rejectionCount(player: Player): number
	return rejections[player] or 0
end

-- Wires every registered handler onto its RemoteFunction. Called once by the
-- bootstrap after all services have registered.
function RemoteGateway.bind(): ()
	if not RunService:IsServer() then
		error("[Gateway] server-only", 2)
	end

	for name, handler in pairs(handlers) do
		local remote = Remotes.getFunction(name :: any)
		remote.OnServerInvoke = function(player: Player, ...): ...any
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return false, Remotes.Notice.InvalidRequest
			end

			if not consume(player, name) then
				rejections[player] = (rejections[player] or 0) + 1
				return false, Remotes.Notice.RateLimited
			end

			-- A handler error must never surface to the client as a Luau message.
			local results = table.pack(pcall(handler, player, ...))
			if not results[1] then
				warn(string.format("[Gateway] handler '%s' errored for UserId=%d: %s",
					name, player.UserId, tostring(results[2])))
				return false, Remotes.Notice.ServerError
			end
			return table.unpack(results, 2, results.n)
		end
	end
end

function RemoteGateway.clearPlayer(player: Player): ()
	buckets[player] = nil
	rejections[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	RemoteGateway.clearPlayer(player)
end)

RemoteGateway._reject = reject

return RemoteGateway
