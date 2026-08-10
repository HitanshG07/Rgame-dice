--!strict
-- Leaderboard.test.luau
-- Unit test suite for UT-10: Logarithmic integer transform bounds and non-overflow guarantees.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")

local LeaderboardService = require(Server:WaitForChild("LeaderboardService"))

local LeaderboardTest = {}

function LeaderboardTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	-- 1. Zero and negative inputs return 0
	check(LeaderboardService.transform(0) == 0, "transform(0) should be 0")
	check(LeaderboardService.transform(-100) == 0, "transform(-100) should be 0")
	check(LeaderboardService.transform(0/0) == 0, "transform(NaN) should be 0")

	-- 2. Monotonicity test
	local t1 = LeaderboardService.transform(1e3)
	local t2 = LeaderboardService.transform(1e6)
	local t3 = LeaderboardService.transform(1e12)
	check(t1 < t2, "transform(1e3) < transform(1e6)")
	check(t2 < t3, "transform(1e6) < transform(1e12)")

	-- 3. Extreme 1e300 bound check (T-20, SRS FR-11.4)
	local tMax = LeaderboardService.transform(1e300)
	check(tMax > 0, "transform(1e300) should be > 0")
	check(tMax <= 2e9, "transform(1e300) must fit in 64-bit integer signed limits (<= 2e9)")

	-- 4. Inverse transform precision
	local inv1e6 = LeaderboardService.inverseTransform(LeaderboardService.transform(1e6))
	check(math.abs(inv1e6 - 1e6) <= 2.0, "inverseTransform should roundtrip 1e6 within 2.0 margin")

	return true, nil, asserts
end

return {
	name = "Leaderboard.test",
	run = LeaderboardTest.run,
}
