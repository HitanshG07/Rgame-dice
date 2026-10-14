--!strict
-- LeaderboardFetch.test.luau
-- Pins for the failed-first-fetch poisoning defect (M3 interaction) and DIE-1 site #6.

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")

local LeaderboardService = require(Server:WaitForChild("LeaderboardService"))
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local StateSyncService = require(Server:WaitForChild("StateSyncService"))

local LeaderboardFetchTest = {}

function LeaderboardFetchTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			LeaderboardService._setTestHooks(nil, nil)
			error(msg, 2)
		end
	end

	local now = 1000
	local fetches = 0
	local failNext = true
	local yieldSec = 0
	local fakeStore = {
		GetSortedAsync = function(_self: any)
			fetches += 1
			if yieldSec > 0 then
				task.wait(yieldSec)
			end
			if failNext then
				error("429 throttled")
			end
			return {
				GetCurrentPage = function()
					return { { key = "0", value = 5000000 } }
				end,
			}
		end,
	}
	LeaderboardService._setTestHooks(function(_id: string)
		return fakeStore :: any
	end, function()
		return now
	end)

	-- 1. A failed first fetch reports "throttled", not a cached empty board.
	local e1, s1 = LeaderboardService.getBoardStatus("NetWorth")
	check(#e1 == 0 and s1 == "throttled", "failed first fetch must report throttled")

	-- 2. Inside the retry cooldown a failure is not hammered.
	LeaderboardService.getBoardStatus("NetWorth")
	check(fetches == 1, "retry inside cooldown must not refetch")

	-- 3. POISON PIN: past the cooldown but far inside CACHE_TTL_SEC, the next
	-- caller must RETRY and get the real board. Reverting to stamping lastFetch
	-- before the yield makes this return the cached empty board with fetches == 1.
	now += 10
	failNext = false
	local e3, s3 = LeaderboardService.getBoardStatus("NetWorth")
	check(fetches == 2, "failure must not poison the cache for a full TTL")
	check(#e3 == 1 and s3 == "ok", "retry after a failure must return the populated board")

	-- 4. A genuinely empty board is "empty", distinct from "throttled".
	LeaderboardService._setTestHooks(function(_id: string)
		return {
			GetSortedAsync = function()
				return { GetCurrentPage = function() return {} end }
			end,
		} :: any
	end, function()
		return now
	end)
	local _, s4 = LeaderboardService.getBoardStatus("NetWorth")
	check(s4 == "empty", "successful empty fetch must report empty")

	-- 5. M3 PIN: five simultaneous callers during a yielding fetch issue ONE
	-- GetSortedAsync. Reverting to stamp-after-yield makes this 5.
	fetches = 0
	failNext = false
	yieldSec = 0.1
	LeaderboardService._setTestHooks(function(_id: string)
		return fakeStore :: any
	end, function()
		return now
	end)
	for _ = 1, 5 do
		task.spawn(LeaderboardService.getBoardStatus, "HighestRoll")
	end
	task.wait(0.3)
	check(fetches == 1, "concurrent callers must share one in-flight fetch (M3)")
	local e5, s5 = LeaderboardService.getBoardStatus("HighestRoll")
	check(#e5 == 1 and s5 == "ok" and fetches == 1, "burst result must be cached after success")
	LeaderboardService._setTestHooks(nil, nil)

	-- 6. DIE-1 site #6: a per-die field with an explicit "ship" decision reaches
	-- the client; "withhold" and undecided fields do not. Reverting to the fixed
	-- literal drops TestShip.
	local policy = StateSyncService.DIE_FIELD_POLICY
	policy.TestShip = "ship"
	policy.TestHide = "withhold"
	local data = PlayerProfile._reconcile({})
	local die: any = data.Dice[1]
	die.TestShip = 7
	die.TestHide = 9
	die.TestUndecided = 11
	local snap = StateSyncService.buildSnapshot(data, 0, nil)
	policy.TestShip = nil
	policy.TestHide = nil
	check(snap.dice[1].TestShip == 7, "a 'ship' per-die field must reach the client")
	check(snap.dice[1].TestHide == nil, "a 'withhold' per-die field must not reach the client")
	check(snap.dice[1].TestUndecided == nil, "an undecided per-die field must fail closed")
	check(snap.dice[1].PurchasedBudget == 60 and #snap.dice[1].Faces == 2, "existing fields still ship")

	-- 7. COVERAGE PIN: every field a fresh die carries has a decision. A new field
	-- added to the profile template without choosing ship/withhold goes red here.
	for key in pairs(PlayerProfile._reconcile({}).Dice[1]) do
		check(StateSyncService.DIE_FIELD_POLICY[key :: string] ~= nil, "per-die field '" .. tostring(key) .. "' has no DIE_FIELD_POLICY decision")
	end

	return true, nil, asserts
end

return {
	name = "LeaderboardFetch",
	run = LeaderboardFetchTest.run,
}
