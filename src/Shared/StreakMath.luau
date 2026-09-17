--!strict
-- StreakMath.luau
-- Shared pure streak compounding mathematics and constants (SRS FR-5.3, CONST-1, MULT-1).
--
-- Shared between client and server ON PURPOSE (ForgeMath pattern). The client
-- HUD estimates current multiplier with it; the server rolls and pays with it.
-- Sharing guarantees the multiplier on screen cannot drift from the multiplier that pays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local StreakMath = {}

-- Tuning constants (FR-5.3, CONST-1)
StreakMath.STREAK_CAP = 50
StreakMath.B_PER_LEVEL = 0.01           -- StreakStrength level -> b
StreakMath.MAX_MULTIPLIER = 1e6         -- Absolute ceiling on compounding multiplier

function StreakMath.streakStrengthToB(level: number): number
	if not ForgeMath.isFinite(level) or level <= 0 then
		return 0
	end
	return level * StreakMath.B_PER_LEVEL
end

function StreakMath.multiplier(streak: number, b: number): number
	if not ForgeMath.isFinite(streak) or not ForgeMath.isFinite(b) then
		return 1
	end
	if streak <= 0 or b <= 0 then
		return 1
	end
	local capped = math.min(streak, StreakMath.STREAK_CAP)
	local m = (1 + b) ^ capped
	if not ForgeMath.isFinite(m) or m > StreakMath.MAX_MULTIPLIER then
		return StreakMath.MAX_MULTIPLIER
	end
	return m
end

return StreakMath
