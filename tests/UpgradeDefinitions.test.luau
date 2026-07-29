--!strict
-- UpgradeDefinitions.test.luau
-- Unit tests for upgrade price scaling math and catalog definitions.

local UpgradeDefinitions = require(game:GetService("ReplicatedStorage"):WaitForChild("Source"):WaitForChild("Shared"):WaitForChild("UpgradeDefinitions"))

local function Assert(condition: boolean, msg: string)
	if not condition then
		error("[TEST FAILED] " .. msg)
	end
end

print("=== Running UT-1: Upgrade Definitions & Price Scaling Tests ===")

-- Test 1: Upgrade Catalog Retrieval
local addBall = UpgradeDefinitions.Get("AddBall")
Assert(addBall ~= nil, "AddBall definition must exist")
Assert(addBall.BaseCost == 23, "AddBall base cost must be 23")
Assert(addBall.GrowthFactor == 1.35, "AddBall growth factor must be 1.35")

-- Test 2: Price Scaling Math Across Levels
local costLvl0 = UpgradeDefinitions.CalculateCost("AddBall", 0)
Assert(costLvl0 == 23, "Level 0 cost should equal base cost 23, got: " .. tostring(costLvl0))

local costLvl1 = UpgradeDefinitions.CalculateCost("AddBall", 1)
local expectedLvl1 = math.floor(23 * 1.35)
Assert(costLvl1 == expectedLvl1, "Level 1 cost mismatch. Got: " .. tostring(costLvl1) .. ", expected: " .. tostring(expectedLvl1))

local costMax = UpgradeDefinitions.CalculateCost("AddBall", 15)
Assert(costMax == math.huge, "Exceeding max level 15 should return math.huge")

-- Test 3: Invalid Upgrade ID
local invalidCost = UpgradeDefinitions.CalculateCost("NonExistentUpgrade", 0)
Assert(invalidCost == math.huge, "Invalid upgrade ID must return math.huge")

print("[PASS] UT-1: Upgrade Definitions & Price Scaling Tests succeeded clean!")
return true
