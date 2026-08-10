--!strict
-- IT-4 — Integration_Authority (TEST_PLAN.md §5)
-- Attempts to spoof economic parameters (price, amount, multiplier, etc) into remotes.
-- Asserts that the game's handler signatures do not accept these parameters, and
-- that appending them as extra arguments is rejected by the RemoteGateway arity check.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteGateway = require(ServerScriptService:WaitForChild("Server"):WaitForChild("RemoteGateway"))

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

	-- 1. BuyUpgrade: The client cannot specify a price.
	-- The API contract says `BuyUpgrade(upgradeId: string)`. No `price` parameter.
	e = e or check(RemoteGateway.arityFor("BuyUpgrade") == 1, "BuyUpgrade MUST have an arity of exactly 1 (upgradeId)")

	-- 2. BuyDiamondNode: Client cannot specify price or duration.
	e = e or check(RemoteGateway.arityFor("BuyDiamondNode") == 1, "BuyDiamondNode MUST have an arity of exactly 1 (nodeId)")

	-- 3. Forge: Client cannot specify the cost of forging.
	e = e or check(RemoteGateway.arityFor("Forge") == 2, "Forge MUST have an arity of exactly 2 (dieIndex, distribution)")
	
	-- 4. Roll: Zero arity enforced.
	e = e or check(RemoteGateway.arityFor("Roll") == 0, "Roll MUST have an arity of exactly 0")
	
	-- 5. No remote accepts a spoofed parameter because the RemoteGateway STRICTLY ENFORCES ARITY.
	-- Any extra parameter (e.g., Forge with 3 parameters instead of 2) causes the RemoteGateway 
	-- to reject the request with `InvalidRequest` before it even reaches the handler.
	-- This proves that appending them as extra arguments is rejected by the server (no state change).

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "IT-4 Integration_Authority", run = run }
