--!strict
-- CodesCatalog.test.luau
-- Unit tests for promo code lookup and formatting.

local CodesCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Source"):WaitForChild("Shared"):WaitForChild("CodesCatalog"))

local function Assert(condition: boolean, msg: string)
	if not condition then
		error("[TEST FAILED] " .. msg)
	end
end

print("=== Running UT-4: Promo Codes Catalog Tests ===")

-- Test 1: Case insensitivity & spaces
local codeRelease = CodesCatalog.Get("  release  ")
Assert(codeRelease ~= nil, "Code RELEASE must be found regardless of case/spaces")
Assert(codeRelease.CashReward == 500, "RELEASE code cash reward must be 500")

-- Test 2: Invalid code
local invalid = CodesCatalog.Get("FAKECODE123")
Assert(invalid == nil, "Invalid code must return nil")

print("[PASS] UT-4: Promo Codes Catalog Tests succeeded clean!")
return true
