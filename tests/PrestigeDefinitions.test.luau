--!strict
-- PrestigeDefinitions.test.luau
-- Unit tests for Prestige calculation math and Prestige upgrades.

local PrestigeDefinitions = require(game:GetService("ReplicatedStorage"):WaitForChild("Source"):WaitForChild("Shared"):WaitForChild("PrestigeDefinitions"))

local function Assert(condition: boolean, msg: string)
	if not condition then
		error("[TEST FAILED] " .. msg)
	end
end

print("=== Running UT-3: Prestige Definitions & Formula Tests ===")

-- Test 1: Requirement threshold
local req = PrestigeDefinitions.GetRequirement()
Assert(req == 1000000, "Prestige requirement must be $1,000,000")

-- Test 2: Point Calculation Math
local ptsBelow = PrestigeDefinitions.CalculatePointsEarned(500000)
Assert(ptsBelow == 0, "Cash below requirement must return 0 prestige points")

local ptsAtReq = PrestigeDefinitions.CalculatePointsEarned(1000000)
Assert(ptsAtReq == 1, "At $1,000,000 cash, exactly 1 prestige point must be earned")

local ptsHigh = PrestigeDefinitions.CalculatePointsEarned(10000000)
Assert(ptsHigh > 1, "At $10,000,000 cash, multiple prestige points must be earned")

-- Test 3: Prestige Upgrade Cost Scaling
local cost0 = PrestigeDefinitions.CalculateUpgradeCost("NebulaBoost", 0)
Assert(cost0 == 1, "Level 0 cost should equal 1 point")

local cost1 = PrestigeDefinitions.CalculateUpgradeCost("NebulaBoost", 1)
Assert(cost1 == 2, "Level 1 cost should equal 2 points")

print("[PASS] UT-3: Prestige Definitions & Formula Tests succeeded clean!")
return true
