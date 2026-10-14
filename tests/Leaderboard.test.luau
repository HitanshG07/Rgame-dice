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

	-- 5. LUCK-1 REVERSED (operator decision): "Luck" is purchasable again, as a payout
	-- add-on folded into LuckBoost. The old pin here asserted its ABSENCE; it now
	-- asserts presence, and Payout.test pins the behaviour.
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local UpgradeCatalog = require(Shared:WaitForChild("UpgradeCatalog"))
	check(UpgradeCatalog.getCashUpgrade("Luck") ~= nil, "Luck must be purchasable in CASH_UPGRADES (LUCK-1 reversed)")
	local allCash = UpgradeCatalog.getAllCashUpgrades()
	local luckCount = 0
	for _, u in ipairs(allCash) do
		if u.id == "Luck" then
			luckCount += 1
		end
	end
	check(luckCount == 1, "Luck must appear exactly once in getAllCashUpgrades")

	-- 6. BOARD-1: LeaderboardService safely handles unranked players and unknown boards
	local fakePlayer = { UserId = 99999999 } :: any
	check(LeaderboardService.getPlayerRank(fakePlayer, "NetWorth") == nil, "getPlayerRank must return nil for unranked player")
	check(#LeaderboardService.getBoard("NonExistentBoard_v1") == 0, "getBoard must return empty table for unknown board")
	local updateOk = pcall(function()
		LeaderboardService.updatePlayer(fakePlayer)
	end)
	check(updateOk, "updatePlayer must safely exit when player has no loaded profile")

	-- 7. BOARD-1: THE EXIT HOOK ITSELF. Section 6 above only proves the service is
	-- safe to call; deleting `pcall(LeaderboardService.updatePlayer, player)` from
	-- ServerBootstrap left all of it green while no score was ever submitted.
	--
	-- A SOURCE SCAN, because the harness cannot fire PlayerRemoving through the
	-- composition root (requiring ServerBootstrap would start the whole server).
	-- It proves the call text exists in `onPlayerRemoving`, is pcall-wrapped, and
	-- sits in the right ORDER. It does not prove the handler is reached at runtime
	-- beyond checking that it is connected to Players.PlayerRemoving by name.
	--
	-- ORDER IS THE CONTRACT: `updatePlayer` reads the profile, and a released
	-- profile refuses reads, so it must precede `PlayerProfile.release`; and it
	-- must precede `OfflineService.onPlayerRemoving` per the bootstrap's own note.
	local bootstrap = Server:FindFirstChild("ServerBootstrap")
	check(bootstrap ~= nil and bootstrap:IsA("LuaSourceContainer"), "ServerBootstrap script must exist beside the services")
	local okSrc, src = pcall(function()
		return (bootstrap :: any).Source :: string
	end)
	if okSrc then
		-- Comments stripped: the handler's own BOARD-1 comment names PlayerProfile.release.
		local code = string.gsub(src, "%-%-[^\n]*", "")
		local fnStart = string.find(code, "local function onPlayerRemoving", 1, true)
		check(fnStart ~= nil, "ServerBootstrap must define onPlayerRemoving")
		local connectAt = string.find(code, "Players.PlayerRemoving:Connect(onPlayerRemoving)", 1, true)
		check(connectAt ~= nil and fnStart ~= nil and connectAt > fnStart,
			"onPlayerRemoving must be connected to Players.PlayerRemoving")
		local body = string.sub(code, fnStart or 1, connectAt or #code)
		local atBoard = string.find(body, "pcall(LeaderboardService.updatePlayer, player)", 1, true)
		local atOffline = string.find(body, "OfflineService.onPlayerRemoving(player)", 1, true)
		local atRelease = string.find(body, "PlayerProfile.release(player)", 1, true)
		check(atBoard ~= nil, "onPlayerRemoving must submit the score via pcall(LeaderboardService.updatePlayer, player) (BOARD-1)")
		check(atOffline ~= nil and atRelease ~= nil, "onPlayerRemoving must still call OfflineService.onPlayerRemoving and PlayerProfile.release")
		check((atBoard :: number) < (atOffline :: number), "BOARD-1: updatePlayer must run BEFORE OfflineService.onPlayerRemoving")
		check((atBoard :: number) < (atRelease :: number), "BOARD-1: updatePlayer must run BEFORE PlayerProfile.release (a released profile refuses reads)")
	else
		print("[UT-10] BOARD-1 exit-hook scan SKIPPED -- this thread cannot read Source (needs PluginOrOpenCloud).")
	end

	return true, nil, asserts
end

return {
	name = "Leaderboard.test",
	run = LeaderboardTest.run,
}
