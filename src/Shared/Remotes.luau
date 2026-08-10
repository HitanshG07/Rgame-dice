--!strict
-- Remotes.luau
-- The single canonical registry of every remote name in the game.
--
-- Contract (API_DATA_CONTRACT.md §1):
--   * The SERVER creates every remote instance. The client only ever waits.
--   * RemoteFunction:InvokeClient() is PROHIBITED project-wide (threat T-8):
--     an exploiting client can yield forever and hang the server thread.
--     Server-to-client is RemoteEvent:FireClient() only.
--   * Names live here and nowhere else, so a typo is a compile-time-ish error
--     rather than a silently dead remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local CLIENT_WAIT_TIMEOUT = 30

local Remotes = {}

-- Inbound: client calls, server returns. RemoteFunction.
export type FunctionName =
	"Roll" | "Forge" | "SetElement" | "SetShape" | "BuyUpgrade" | "AddDieSlot"
	| "Ascend" | "BuyDiamondNode" | "SetAutoRoll" | "ClaimVault" | "ClaimQuest"
	| "ClaimChest" | "DailySpin" | "RedeemCode" | "ClaimGroupReward" | "GetLeaderboard"
	| "SetSetting"

-- Outbound: server fires, client listens. RemoteEvent. Display only.
export type EventName =
	"RollResult" | "StateSync" | "ForgeResult" | "VaultSummary" | "EventState" | "Notice"

-- Typed via a local: Luau does not permit a type annotation on a table-field
-- assignment (`T.x: Type = v` is a syntax error), so the annotation lives here.
local FN: { [string]: FunctionName } = {
	Roll = "Roll",
	Forge = "Forge",
	SetElement = "SetElement",
	SetShape = "SetShape",
	BuyUpgrade = "BuyUpgrade",
	AddDieSlot = "AddDieSlot",
	Ascend = "Ascend",
	BuyDiamondNode = "BuyDiamondNode",
	SetAutoRoll = "SetAutoRoll",
	ClaimVault = "ClaimVault",
	ClaimQuest = "ClaimQuest",
	ClaimChest = "ClaimChest",
	DailySpin = "DailySpin",
	RedeemCode = "RedeemCode",
	ClaimGroupReward = "ClaimGroupReward",
	GetLeaderboard = "GetLeaderboard",
	-- FR-13.6. Presentation preferences only -- see SettingsCatalog for why no
	-- setting may carry an economic consequence.
	SetSetting = "SetSetting",
}
Remotes.Fn = FN

local EV: { [string]: EventName } = {
	RollResult = "RollResult",
	StateSync = "StateSync",
	ForgeResult = "ForgeResult",
	VaultSummary = "VaultSummary",
	EventState = "EventState",
	Notice = "Notice",
}
Remotes.Ev = EV

-- Enumerated Notice codes. The client is told a CODE, never an internal detail:
-- no stack traces, paths, query text, or configuration values cross the
-- boundary (threat T-7, Matrix E-8).
Remotes.Notice = {
	RateLimited = "rate_limited",
	InvalidRequest = "invalid_request",
	InsufficientFunds = "insufficient_funds",
	NotUnlocked = "not_unlocked",
	AtCap = "at_cap",
	ProfileUnavailable = "profile_unavailable",
	ServerError = "server_error",
}

local function folder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end

	local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_WAIT_TIMEOUT)
	if not found or not found:IsA("Folder") then
		error("[Remotes] Remotes folder did not replicate within "
			.. tostring(CLIENT_WAIT_TIMEOUT) .. "s", 2)
	end
	return found
end

-- Server: create-or-fetch. Client: wait. Never the other way round, so the
-- client cannot conjure a remote the server never declared.
local function resolve(className: string, name: string): Instance
	local parent = folder()

	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing then
			if not existing:IsA(className) then
				error(string.format(
					"[Remotes] '%s' exists as %s, expected %s",
					name, existing.ClassName, className), 2)
			end
			return existing
		end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = parent
		return created
	end

	local found = parent:WaitForChild(name, CLIENT_WAIT_TIMEOUT)
	if not found then
		error("[Remotes] '" .. name .. "' did not replicate within "
			.. tostring(CLIENT_WAIT_TIMEOUT) .. "s", 2)
	end
	if not found:IsA(className) then
		error(string.format(
			"[Remotes] '%s' replicated as %s, expected %s",
			name, found.ClassName, className), 2)
	end
	return found
end

function Remotes.getFunction(name: FunctionName): RemoteFunction
	return resolve("RemoteFunction", name) :: RemoteFunction
end

function Remotes.getEvent(name: EventName): RemoteEvent
	return resolve("RemoteEvent", name) :: RemoteEvent
end

-- Server-only: materialise every declared remote up front, so the client's
-- WaitForChild calls resolve immediately instead of racing first use.
function Remotes.createAll(): ()
	if not RunService:IsServer() then
		error("[Remotes] createAll is server-only", 2)
	end
	for _, name in pairs(FN) do
		Remotes.getFunction(name)
	end
	for _, name in pairs(EV) do
		Remotes.getEvent(name)
	end
end

return Remotes
