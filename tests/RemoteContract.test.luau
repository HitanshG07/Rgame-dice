--!strict
-- UT-15 — RemoteContract
--
-- WHY THIS SUITE EXISTS. Eight registered remote handlers threw on their first
-- line and returned `server_error` to every caller, for the whole build:
--
--   SetAutoRoll, BuyUpgrade, BuyDiamondNode, ClaimVault, RedeemCode,
--   ClaimQuest, ClaimChest, GetLeaderboard
--
-- All of them called `RemoteGateway.V.boundedString(...)` or
-- `RemoteGateway.V.strictBoolean(...)`. `V` was a module-local and was never
-- exported, so `RemoteGateway.V` was nil and indexing it errored immediately.
--
-- NOTHING CAUGHT IT, and each layer had a reason:
--
--   * every handler WAS registered, so the producer-direction sweep -- the check
--     written after ledger L-027 -- counted all sixteen as present;
--   * the gateway catches handler errors by design and converts them to an
--     enumerated Notice (threat T-7), so a total failure and an ordinary refusal
--     are indistinguishable from outside;
--   * `RemoteGateway.MAX_STRING_ID` on the SAME LINE resolved perfectly, because
--     that constant was exported. The omission was one missing assignment beside
--     two present ones.
--
-- So the lesson is narrow and mechanical: a handler being REGISTERED says
-- nothing about whether it RUNS. This suite calls the module surface each
-- handler depends on and fails if any piece is missing.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local RemoteGateway = require(Server:WaitForChild("RemoteGateway"))

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
	local e: any = nil

	----------------------------------------------------------------------------
	-- The validator surface the handlers actually reach for
	----------------------------------------------------------------------------

	e = e or check(type(RemoteGateway.V) == "table",
		"RemoteGateway.V must be exported -- eight handlers index it on their"
		.. " first line and every one of them threw when it was nil")

	if type(RemoteGateway.V) == "table" then
		local V = RemoteGateway.V :: any
		for _, fn in ipairs({ "finiteNumber", "integerInRange", "boundedString",
			"strictBoolean", "allowlisted" }) do
			e = e or check(type(V[fn]) == "function",
				string.format("RemoteGateway.V.%s must exist and be callable", fn))
		end

		-- Exercised, not merely present. A validator that errors on real input is
		-- as broken as a missing one, and this is the input shape the handlers
		-- pass it.
		if type(V.boundedString) == "function" then
			local ok = V.boundedString("AutoRollSpeed", RemoteGateway.MAX_STRING_ID)
			e = e or check(ok == true, "boundedString must accept an ordinary upgrade id")
			local bad = V.boundedString(12345, RemoteGateway.MAX_STRING_ID)
			e = e or check(bad == false, "boundedString must reject a non-string")
		end
		if type(V.strictBoolean) == "function" then
			e = e or check(V.strictBoolean(true) == true, "strictBoolean must accept true")
			e = e or check(V.strictBoolean("true") == false,
				"strictBoolean must reject a string, or a client can spoof a toggle")
		end
	end

	----------------------------------------------------------------------------
	-- The constants beside it
	----------------------------------------------------------------------------
	--
	-- These WERE exported, which is precisely what hid the missing one: the same
	-- line that failed on `.V` resolved `.MAX_STRING_ID` without complaint.

	e = e or check(type(RemoteGateway.MAX_STRING_ID) == "number",
		"RemoteGateway.MAX_STRING_ID must be exported")
	e = e or check(type(RemoteGateway.MAX_STRING_CODE) == "number",
		"RemoteGateway.MAX_STRING_CODE must be exported")

	----------------------------------------------------------------------------
	-- Registration surface
	----------------------------------------------------------------------------

	e = e or check(type(RemoteGateway.register) == "function",
		"RemoteGateway.register must exist")
	e = e or check(type(RemoteGateway.bind) == "function",
		"RemoteGateway.bind must exist")

	if e ~= nil then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-15 RemoteContract", run = run }
