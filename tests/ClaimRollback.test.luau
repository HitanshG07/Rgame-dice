--!strict
-- ClaimRollback.test.luau
-- LOGIN-1: a once-only claim flag must never be left set when the payment did not land.
--
-- WHY THIS SUITE EXISTS. Four ProgressionService paths (daily spin, promo code,
-- quest claim, login streak) all share one shape: set a once-only flag in one
-- `mutate`, pay in a second, and -- if the payment fails -- unset the flag. A path
-- that forgets the last step turns a transient failure into a permanently
-- forfeited reward, and a path that pays without the flag turns a rejoin into a
-- repeatable mint. `git grep recordLogin|claimDailySpin|redeemCode tests/` was
-- empty: none of it was covered.
--
-- THE CONTRACT, not the line numbers, is what is asserted: after ANY single
-- failed `mutate`, `flagSet == paymentLanded`. Both directions matter -- flag set
-- with no payment is a forfeit; payment with no flag is a mint.
--
-- HOW A MUTATE IS FORCED TO FAIL. `PlayerProfile.mutate` calls `profile:IsActive()`
-- exactly once per mutation and refuses (returning false) when it is false. The
-- fake profile's `IsActive` is replaced with one that is false on the Nth call
-- only. Sweeping N over 1..3 fails, in turn, the flag write, the payment, and the
-- rollback's slot, so the sweep does not depend on how many mutates a path makes
-- or in which order -- an N that lands past the last mutate is just the happy path.
-- Single faults only: a failed payment AND a failed rollback is unrecoverable by
-- design and has no contract to assert.
--
-- NOT COVERED: `claimChest`. Its once-only flag is in-memory, gated by
-- `os.clock() - sessionStart >= 300s`, and there is no seam to advance that clock
-- short of yielding five real minutes. See the report; no vacuous test is written.

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local ProgressionService = require(Server:WaitForChild("ProgressionService"))
local Fakes = require(ServerScriptService:WaitForChild("Tests"):WaitForChild("Fakes"))

local ClaimRollbackTest = {}

type Path = {
	name: string,
	-- Builds any precondition (profile is healthy here), returns the data table.
	prepare: (player: Player, data: any) -> (),
	-- Is the once-only flag currently set?
	flag: (data: any) -> boolean,
	-- Runs the claim; returns whether it reported success.
	claim: (player: Player, data: any) -> boolean,
}

local paths: { Path } = {
	{
		name = "claimDailySpin",
		prepare = function(_player, _data) end,
		flag = function(data)
			return data.LastSpin ~= 0
		end,
		claim = function(player, _data)
			return (ProgressionService.claimDailySpin(player))
		end,
	},
	{
		name = "redeemCode",
		prepare = function(_player, _data) end,
		flag = function(data)
			return data.CodesRedeemed["RELEASE"] == true
		end,
		claim = function(player, _data)
			return (ProgressionService.redeemCode(player, "RELEASE"))
		end,
	},
	{
		name = "claimQuest",
		prepare = function(player, data)
			ProgressionService.refreshQuests(player)
			local slot = data.Quests.Slots[1]
			slot.Progress = ProgressionService.getQuestTarget(slot.Id) :: number
		end,
		flag = function(data)
			return data.Quests.Slots[1].Claimed == true
		end,
		claim = function(player, data)
			return (ProgressionService.claimQuest(player, data.Quests.Slots[1].Id))
		end,
	},
	{
		name = "recordLogin",
		prepare = function(_player, _data) end,
		flag = function(data)
			return data.LoginStreak.LastDay ~= 0
		end,
		claim = function(player, _data)
			return (ProgressionService.recordLogin(player))
		end,
	},
}

local function wealth(data: any): number
	return data.Cash + data.Gems + data.Diamonds
end

function ClaimRollbackTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	PlayerProfile.init()

	local nextId = 771000
	-- failAt = 0 means never fail (the happy path).
	local function trial(path: Path, failAt: number): (boolean, boolean, boolean)
		nextId += 1
		local player = Fakes.createFakePlayer(nextId, "RollbackPlayer" .. nextId)
		local data = PlayerProfile._reconcile({})
		local profile = Fakes.createFakeProfile(data)
		PlayerProfile._injectProfileForTesting(player, profile)

		path.prepare(player, data)

		-- Armed only AFTER preparation, so the counter starts at the claim.
		local calls = 0
		;(profile :: any).IsActive = function(_self: any): boolean
			calls += 1
			return calls ~= failAt
		end

		local before = wealth(data)
		local reportedOk = path.claim(player, data)
		return reportedOk, path.flag(data), wealth(data) > before
	end

	for _, path in ipairs(paths) do
		-- Happy path first: without it the sweep below could pass vacuously
		-- (a claim that never pays and never sets a flag satisfies flag == paid).
		local okHappy, flagHappy, paidHappy = trial(path, 0)
		check(okHappy, path.name .. ": the unfaulted claim must succeed (test setup is wrong otherwise)")
		check(flagHappy, path.name .. ": the unfaulted claim must set its once-only flag")
		check(paidHappy, path.name .. ": the unfaulted claim must pay")

		for failAt = 1, 3 do
			local reportedOk, flagSet, paid = trial(path, failAt)
			check(flagSet == paid, string.format(
				"%s: with mutate #%d failing, the once-only flag is %s but the payment %s (LOGIN-1: "
					.. "a flag set without payment forfeits the reward; payment without the flag is a mint)",
				path.name, failAt, if flagSet then "SET" else "unset", if paid then "landed" else "did not land"))
			check(not reportedOk or paid, string.format(
				"%s: with mutate #%d failing, the claim reported success but nothing was paid", path.name, failAt))
		end
	end

	PlayerProfile.releaseAll()
	return true, nil, asserts
end

return {
	name = "ClaimRollback.test",
	run = ClaimRollbackTest.run,
}
