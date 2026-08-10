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
local RateLimiter = require(script.Parent:WaitForChild("RateLimiter"))

local RemoteGateway = {}

export type Handler = (player: Player, ...any) -> ...any

local MAX_STRING_CODE = 32
local MAX_STRING_ID = 64

--------------------------------------------------------------------------------
-- Declared arity, from API_DATA_CONTRACT.md §1.1. Enforced centrally in bind().
--
-- F-4A-1, found by the Block 4A wire test on 2026-08-07: `Roll(999)` was
-- accepted and processed as a normal roll. The contract says "Zero arity
-- enforced -- any argument rejects the call", and it was not. Nothing was
-- exploitable, because RollService.performRoll ignores extras and the value
-- reached no decision -- but an unexpected argument means either the caller is
-- not our client or the API has drifted, and both are worth refusing rather
-- than absorbing.
--
-- No unit test could have caught it: the suite calls handlers directly and never
-- crosses a RemoteFunction. It took a real client invoking a real remote.
--
-- Declared here in ONE table for the same reason the die invariant is declared
-- in one function: a rule restated per-handler is a rule that drifts per-handler.
--------------------------------------------------------------------------------
local ARITY: { [string]: number } = {
	Roll = 0,
	Forge = 2,
	SetElement = 3,
	SetShape = 2,
	BuyUpgrade = 1,
	AddDieSlot = 0,
	Ascend = 0,
	BuyDiamondNode = 1,
	SetAutoRoll = 1,
	ClaimVault = 1,
	ClaimQuest = 1,
	ClaimChest = 1,
	DailySpin = 0,
	RedeemCode = 1,
	ClaimGroupReward = 0,
	GetLeaderboard = 1,
}

-- Returns the declared arity, or nil if the remote is not declared. A remote
-- with no declaration is a contract gap, not a licence to accept anything --
-- bind() refuses to wire one.
function RemoteGateway.arityFor(name: string): number?
	return ARITY[name]
end

local handlers: { [string]: Handler } = {}

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

-- THE VALIDATOR TABLE, EXPORTED.
--
-- `V` was a module-local and every caller reached for `RemoteGateway.V`, which
-- was nil -- so EIGHT registered handlers threw on their first line and returned
-- `server_error`: SetAutoRoll, BuyUpgrade, BuyDiamondNode, ClaimVault,
-- RedeemCode, ClaimQuest, ClaimChest and GetLeaderboard.
--
-- Every one of them LOOKED implemented. They were registered, they had real
-- bodies, and a producer-direction sweep counted them as present. They failed
-- at runtime, uniformly, on a nil index -- and because the gateway catches
-- handler errors and returns an enumerated code, the failure surfaced to the
-- player as a generic refusal rather than as a crash anyone would investigate.
--
-- The neighbouring constants WERE exported, which is what made the omission
-- invisible: `RemoteGateway.MAX_STRING_ID` resolves fine on the same line that
-- `RemoteGateway.V` does not.
RemoteGateway.V = V

RemoteGateway.MAX_STRING_CODE = MAX_STRING_CODE
RemoteGateway.MAX_STRING_ID = MAX_STRING_ID

--------------------------------------------------------------------------------
-- Registration and dispatch
--------------------------------------------------------------------------------

local function reject(player: Player, name: string, reason: string): (boolean, string)
	RateLimiter.recordRejection(player)
	warn(string.format("[Gateway] rejected %s from UserId=%d: %s (total %d)",
		name, player.UserId, reason, RateLimiter.rejectionCount(player)))
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
	return RateLimiter.rejectionCount(player)
end

-- Wires every registered handler onto its RemoteFunction. Called once by the
-- bootstrap after all services have registered.
function RemoteGateway.bind(): ()
	if not RunService:IsServer() then
		error("[Gateway] server-only", 2)
	end

	for name, handler in pairs(handlers) do
		local expectedArity = ARITY[name]
		if expectedArity == nil then
			-- Fail closed at STARTUP rather than at the first call. A remote with
			-- no declared arity is a gap in API_DATA_CONTRACT §1.1, and wiring it
			-- anyway would mean accepting whatever arrives.
			error(string.format(
				"[Gateway] remote '%s' has no declared arity in ARITY -- add it to "
				.. "API_DATA_CONTRACT §1.1 and to the table in RemoteGateway", name), 2)
		end

		local remote = Remotes.getFunction(name :: any)
		remote.OnServerInvoke = function(player: Player, ...): ...any
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return false, Remotes.Notice.InvalidRequest
			end

			if not RateLimiter.consume(player, name) then
				return false, Remotes.Notice.RateLimited
			end

			-- ARITY, before type or bounds. A call with the wrong shape is not a
			-- call with a bad value; it is a caller that is not speaking our
			-- protocol, and it is refused without being interpreted (F-4A-1).
			if select("#", ...) ~= expectedArity then
				return reject(player, name, string.format(
					"arity %d, expected %d", select("#", ...), expectedArity))
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
	RateLimiter.clearPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	RemoteGateway.clearPlayer(player)
end)

RemoteGateway._reject = reject

return RemoteGateway
