--!strict
-- NetClient.luau
-- The SOLE outbound boundary. No other client module touches a RemoteEvent or
-- RemoteFunction directly.
--
-- Same chokepoint principle as RemoteGateway on the server: one file to audit
-- rather than a search across the whole client. If a future module needs to
-- talk to the server, it adds a wrapper HERE and calls that.
--
-- THE RULE THAT MATTERS MOST (SRS NFR-5, API_DATA_CONTRACT §1.1):
--   NO OUTBOUND MESSAGE MAY CARRY A PRICE, BALANCE, REWARD, SCORE, LEVEL,
--   DURATION, MULTIPLIER OR OUTCOME.
-- Every economic quantity is resolved server-side. The signatures below are
-- deliberately narrow so that sending one is not merely discouraged but
-- awkward: there is no generic `invoke(name, ...)` escape hatch, because a
-- generic sender is how a price ends up on the wire six months from now.
--
-- The forge is the interesting case. The client sends a complete proposed mass
-- DISTRIBUTION, which looks like data but is not an economic claim: the server
-- holds the budget, validates the proposal against it, and prices the move
-- itself. The client never sends the cost.
--
-- THROTTLING HERE IS A COURTESY, NOT A CONTROL. The token buckets in
-- RateLimiter are the real enforcement. An exploiter runs their own client and
-- ignores every line of this file; the only thing this prevents is a legitimate
-- player's UI spamming the server and being rate-limited for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local NetClient = {}

export type Result = { ok: boolean, reason: string? }

--------------------------------------------------------------------------------
-- Cooperative send throttle
--------------------------------------------------------------------------------

-- Mirrors API_DATA_CONTRACT §2.2 loosely and stays deliberately LOOSER than the
-- server's buckets. A client-side limit tighter than the server's would make the
-- UI feel broken while the server was still happy to answer.
local MIN_INTERVAL: { [string]: number } = {
	Roll = 0.15,
	Forge = 0.25,
	SetElement = 0.25,
	SetShape = 0.25,
	BuyUpgrade = 0.2,
	BuyDiamondNode = 0.2,
	AddDieSlot = 0.5,
	Ascend = 1.0,
	SetAutoRoll = 0.3,
	ClaimVault = 0.5,
	ClaimQuest = 0.3,
	ClaimChest = 0.3,
	DailySpin = 1.0,
	RedeemCode = 1.0,
	ClaimGroupReward = 1.0,
	GetLeaderboard = 2.0,
}
local DEFAULT_INTERVAL = 0.25

local lastSent: { [string]: number } = {}

local function throttled(name: string): boolean
	local now = os.clock()
	local last = lastSent[name]
	local gap = MIN_INTERVAL[name] or DEFAULT_INTERVAL
	if last ~= nil and (now - last) < gap then
		return true
	end
	lastSent[name] = now
	return false
end

-- Exposed so the HUD can grey a button out instead of firing and being refused.
-- Read-only: asking does not consume the slot.
function NetClient.readyIn(name: string): number
	local last = lastSent[name]
	if last == nil then
		return 0
	end
	local gap = MIN_INTERVAL[name] or DEFAULT_INTERVAL
	local remaining = gap - (os.clock() - last)
	return if remaining > 0 then remaining else 0
end

--------------------------------------------------------------------------------
-- Invocation
--------------------------------------------------------------------------------

-- Private. Every public wrapper below funnels through here, so the throttle,
-- the pcall and the result normalisation exist exactly once.
--
-- A RemoteFunction call can error (server handler faulted, remote destroyed
-- mid-teardown). That must surface as a refusal the UI can render, never as an
-- unhandled client error that takes the whole interface down mid-session.
local function call(name: Remotes.FunctionName, ...: any): Result
	if throttled(name) then
		return { ok = false, reason = "throttled" }
	end

	local remote = Remotes.getFunction(name)
	local packed = table.pack(pcall(remote.InvokeServer, remote, ...))
	if not packed[1] then
		warn(string.format("[NetClient] '%s' failed: %s", name, tostring(packed[2])))
		return { ok = false, reason = "unavailable" }
	end

	local ok = packed[2]
	if type(ok) ~= "boolean" then
		-- A handler that answers in an unexpected shape is treated as a refusal
		-- rather than optimistically believed.
		return { ok = false, reason = "malformed_response" }
	end
	local reason = packed[3]
	return { ok = ok, reason = if type(reason) == "string" then reason else nil }
end

--------------------------------------------------------------------------------
-- Inbound wrappers (client -> server). API_DATA_CONTRACT §1.1.
--------------------------------------------------------------------------------

-- Zero arity, enforced by the signature. The server rejects any argument.
function NetClient.roll(): Result
	return call("Roll")
end

-- The complete proposed distribution. Carries no cost: the server holds the
-- budget and prices the move.
function NetClient.forge(dieIndex: number, distribution: { number }): Result
	return call("Forge", dieIndex, distribution)
end

function NetClient.setElement(dieIndex: number, faceIndex: number, elementId: string): Result
	return call("SetElement", dieIndex, faceIndex, elementId)
end

function NetClient.setShape(dieIndex: number, shapeId: string): Result
	return call("SetShape", dieIndex, shapeId)
end

-- An id only. The PRICE is resolved server-side and is never a parameter.
function NetClient.buyUpgrade(upgradeId: string): Result
	return call("BuyUpgrade", upgradeId)
end

function NetClient.buyDiamondNode(nodeId: string): Result
	return call("BuyDiamondNode", nodeId)
end

function NetClient.addDieSlot(): Result
	return call("AddDieSlot")
end

function NetClient.ascend(): Result
	return call("Ascend")
end

-- A boolean only. The auto-roll INTERVAL is server-owned; a client that could
-- name its own interval would be naming its own income rate (SRS FR-7.2).
function NetClient.setAutoRoll(enabled: boolean): Result
	return call("SetAutoRoll", enabled == true)
end

function NetClient.claimVault(doubled: boolean): Result
	return call("ClaimVault", doubled == true)
end

function NetClient.claimQuest(questId: string): Result
	return call("ClaimQuest", questId)
end

function NetClient.claimChest(tierId: string): Result
	return call("ClaimChest", tierId)
end

function NetClient.dailySpin(): Result
	return call("DailySpin")
end

function NetClient.redeemCode(code: string): Result
	return call("RedeemCode", code)
end

function NetClient.claimGroupReward(): Result
	return call("ClaimGroupReward")
end

-- Reads the server's cache; never triggers a fetch (threat T-22). Returns the
-- raw tuple rather than a Result, because it answers with data rather than an
-- ok/reason pair.
function NetClient.getLeaderboard(boardId: string): (any?, number?)
	if throttled("GetLeaderboard") then
		return nil, nil
	end
	local remote = Remotes.getFunction("GetLeaderboard")
	local ok, entries, myRank = pcall(remote.InvokeServer, remote, boardId)
	if not ok then
		warn(string.format("[NetClient] 'GetLeaderboard' failed: %s", tostring(entries)))
		return nil, nil
	end
	return entries, if type(myRank) == "number" then myRank else nil
end

--------------------------------------------------------------------------------
-- Outbound subscriptions (server -> client). API_DATA_CONTRACT §1.2.
--------------------------------------------------------------------------------

-- Display only. Every payload here is already TRUE -- the server committed the
-- state before firing. The client renders it; it never treats one of these as a
-- request it could have declined.
local function subscribe(name: Remotes.EventName, handler: (any) -> ()): RBXScriptConnection
	local event = Remotes.getEvent(name)
	return event.OnClientEvent:Connect(function(payload: any)
		-- A handler that throws must not kill the connection for every
		-- subsequent message, which is what an unprotected Connect would do.
		local ok, err = pcall(handler, payload)
		if not ok then
			warn(string.format("[NetClient] handler for '%s' errored: %s", name, tostring(err)))
		end
	end)
end

function NetClient.onRollResult(handler: (any) -> ()): RBXScriptConnection
	return subscribe("RollResult", handler)
end

function NetClient.onStateSync(handler: (any) -> ()): RBXScriptConnection
	return subscribe("StateSync", handler)
end

function NetClient.onForgeResult(handler: (any) -> ()): RBXScriptConnection
	return subscribe("ForgeResult", handler)
end

function NetClient.onVaultSummary(handler: (any) -> ()): RBXScriptConnection
	return subscribe("VaultSummary", handler)
end

function NetClient.onEventState(handler: (any) -> ()): RBXScriptConnection
	return subscribe("EventState", handler)
end

function NetClient.onNotice(handler: (any) -> ()): RBXScriptConnection
	return subscribe("Notice", handler)
end

--------------------------------------------------------------------------------
-- Readiness
--------------------------------------------------------------------------------

-- Resolves every declared remote up front so a UI module can assume they exist.
-- Returns ok, missingName -- the bootstrap fails LOUDLY on a missing remote
-- rather than letting the first button press be the thing that discovers it.
function NetClient.awaitReady(): (boolean, string?)
	if not RunService:IsClient() then
		error("[NetClient] client-only", 2)
	end
	for _, name in pairs(Remotes.Fn) do
		local ok = pcall(Remotes.getFunction, name)
		if not ok then
			return false, name
		end
	end
	for _, name in pairs(Remotes.Ev) do
		local ok = pcall(Remotes.getEvent, name)
		if not ok then
			return false, name
		end
	end
	return true, nil
end

return NetClient
