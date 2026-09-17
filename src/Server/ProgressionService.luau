--!strict
-- ProgressionService.luau
-- Quests, login streak, daily spin, playtime chests, group rewards, promo codes, and like goal (SRS FR-10).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local ProgressionService = {}

--------------------------------------------------------------------------------
-- Promo Codes & Constants
--------------------------------------------------------------------------------

local PROMO_CODES: { [string]: { type: "Cash" | "Gems" | "Diamonds", amount: number } } = {
	RELEASE = { type = "Cash", amount = 1000 },
	DICEFORGE = { type = "Gems", amount = 100 },
	FORGE2026 = { type = "Diamonds", amount = 10 },
}

local CHEST_TIMES_SEC = {
	Tier1 = 5 * 60,   -- 5 mins
	Tier2 = 15 * 60,  -- 15 mins
	Tier3 = 30 * 60,  -- 30 mins
	Tier4 = 45 * 60,  -- 45 mins
	Tier5 = 60 * 60,  -- 60 mins
	Tier6 = 90 * 60,  -- 90 mins
}

--------------------------------------------------------------------------------
-- Daily Spin (SRS FR-10.4)
--------------------------------------------------------------------------------

function ProgressionService.canSpin(player: Player): boolean
	local data = PlayerProfile.get(player)
	if not data then
		return false
	end
	return (os.time() - data.LastSpin) >= (24 * 3600)
end

function ProgressionService.claimDailySpin(player: Player): (boolean, string?, string?, number?)
	if not ProgressionService.canSpin(player) then
		return false, "on_cooldown", nil, nil
	end

	-- Weighted outcome table (server-decided)
	local rng = Random.new()
	local roll = rng:NextNumber()

	local currency = "Cash"
	local amount = 1000

	if roll < 0.50 then
		currency = "Cash"
		amount = 5000
	elseif roll < 0.85 then
		currency = "Gems"
		amount = 150
	else
		currency = "Diamonds"
		amount = 15
	end

	local ok, reason = PlayerProfile.mutate(player, function(d)
		d.LastSpin = os.time()
	end)

	if not ok then
		return false, reason or "mutate_failed", nil, nil
	end

	local okCredit, creditReason = EconomyService.credit(player, currency :: any, amount, "daily_spin")
	if not okCredit then
		PlayerProfile.mutate(player, function(d)
			d.LastSpin = 0
		end)
		return false, creditReason or "credit_failed", nil, nil
	end
	return true, nil, currency, amount
end

--------------------------------------------------------------------------------
-- Promo Codes (SRS FR-10.6)
--------------------------------------------------------------------------------

function ProgressionService.redeemCode(player: Player, submittedCode: string): (boolean, string?)
	if type(submittedCode) ~= "string" then
		return false, "invalid_code"
	end

	-- `gsub` returns TWO values -- the string and a replacement count -- so
	-- nesting it inside `string.upper` passes both and the analyser reports an
	-- argument-count mismatch. Parenthesising truncates to the first value.
	local stripped = (string.gsub(submittedCode, "%s+", ""))
	local cleanCode = string.upper(stripped)
	local codeData = PROMO_CODES[cleanCode]
	if not codeData then
		return false, "invalid_code" -- generic response, never echo input
	end

	local data = PlayerProfile.get(player)
	if not data then
		return false, "no_profile"
	end

	if data.CodesRedeemed[cleanCode] then
		return false, "already_redeemed"
	end

	local ok, reason = PlayerProfile.mutate(player, function(d)
		d.CodesRedeemed[cleanCode] = true
	end)

	if not ok then
		return false, reason or "mutate_failed"
	end

	local okCredit, creditReason = EconomyService.credit(player, codeData.type, codeData.amount, "code_redemption")
	if not okCredit then
		PlayerProfile.mutate(player, function(d)
			d.CodesRedeemed[cleanCode] = nil
		end)
		return false, creditReason or "credit_failed"
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Group Rewards (SRS FR-10.5)
--------------------------------------------------------------------------------

-- The Roblox group whose members earn the reward.
--
-- ZERO IS "NOT CONFIGURED" AND FAILS CLOSED. Until the operator supplies a real
-- group id, `isInGroup` cannot return true and the reward cannot be claimed.
-- That is the correct direction: handing out a membership reward to non-members
-- is unrecoverable, while a claim that has to wait for configuration is not.
ProgressionService.GROUP_ID = 0

-- FR-10.5 requires membership "verified server-side ... and re-verified on each
-- join", so this is a real platform call, not a cached client claim.
--
-- THIS FUNCTION DID NOT EXIST. The claim path below carried the comment
-- "-- Verified server-side" above code that verified nothing: `GroupService` was
-- required at the top of this file and never called, and ANY player could claim
-- 250 Gems and 15 Diamonds by invoking the remote once. The comment asserted the
-- control; the control was absent.
function ProgressionService.isInGroup(player: Player): boolean
	local groupId = ProgressionService.GROUP_ID
	if type(groupId) ~= "number" or groupId <= 0 then
		return false
	end
	-- A failed lookup is NOT membership. A network blip must never mint a reward.
	--
	-- `IsInGroupAsync`, not the deprecated `IsInGroup`. It YIELDS on a web call,
	-- which is why the existing pcall matters: an unguarded network failure here
	-- would propagate out of a reward path. Callers are already on a remote
	-- handler thread, so yielding is safe.
	local ok, result = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	return ok and result == true
end

function ProgressionService.claimGroupReward(player: Player): (boolean, string?)
	local data = PlayerProfile.get(player)
	if not data then
		return false, "no_profile"
	end

	if data.GroupClaimed then
		return false, "already_claimed"
	end

	if not ProgressionService.isInGroup(player) then
		return false, "not_in_group"
	end

	-- Flag written BEFORE crediting, and the credit only proceeds if the write
	-- took. Crediting first would pay a player whose profile then refused the
	-- write, and the next call would pay them again.
	local ok, reason = PlayerProfile.mutate(player, function(d)
		d.GroupClaimed = true
	end)

	if not ok then
		return false, reason or "mutate_failed"
	end

	EconomyService.credit(player, "Gems", 250, "group_reward")
	EconomyService.credit(player, "Diamonds", 15, "group_reward")
	return true, nil
end

--------------------------------------------------------------------------------
-- Daily quests (SRS FR-10.1)
--
-- Three rotating objectives per UTC day, server-defined and server-tracked. The
-- profile already carried `Quests = { Slots, RolledOn }` with a default; nothing
-- ever wrote it, and the ClaimQuest remote answered `true` without granting
-- anything (ledger L-027 and worse -- a handler that reports success it did not
-- deliver teaches the player their reward was taken).
--------------------------------------------------------------------------------

export type QuestDef = {
	id: string,
	metric: string,   -- which counter advances it
	target: number,
	rewardKind: EconomyService.Currency,
	rewardAmount: number,
}

-- The pool. Objectives are all things the SERVER already counts, which is the
-- constraint that keeps them un-spoofable: a quest the server cannot observe
-- would have to trust a client report.
local QUEST_POOL: { QuestDef } = {
	{ id = "roll25",    metric = "rolls",       target = 25,   rewardKind = "Cash", rewardAmount = 500 },
	{ id = "roll100",   metric = "rolls",       target = 100,  rewardKind = "Cash", rewardAmount = 2500 },
	{ id = "roll500",   metric = "rolls",       target = 500,  rewardKind = "Gems", rewardAmount = 40 },
	{ id = "streak5",   metric = "bestStreak",  target = 5,    rewardKind = "Cash", rewardAmount = 750 },
	{ id = "streak15",  metric = "bestStreak",  target = 15,   rewardKind = "Gems", rewardAmount = 30 },
	{ id = "forge3",    metric = "forges",      target = 3,    rewardKind = "Cash", rewardAmount = 600 },
	{ id = "forge10",   metric = "forges",      target = 10,   rewardKind = "Gems", rewardAmount = 25 },
}

local QUESTS_PER_DAY = 3

local function utcDay(now: number): number
	return math.floor(now / 86400)
end

-- Deterministic per player per day: the same player gets the same three quests
-- all day across every server they join, and a rejoin cannot reroll for a
-- friendlier set.
local function pickQuests(userId: number, day: number): { any }
	local rng = Random.new(userId * 7919 + day)
	local pool = table.clone(QUEST_POOL)
	local chosen: { any } = {}
	for _ = 1, math.min(QUESTS_PER_DAY, #pool) do
		local idx = rng:NextInteger(1, #pool)
		local def = table.remove(pool, idx) :: QuestDef
		table.insert(chosen, {
			Id = def.id,
			Progress = 0,
			Claimed = false,
		})
	end
	return chosen
end

local function questDef(id: string): QuestDef?
	for _, def in ipairs(QUEST_POOL) do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Rolls the day's quests if the stored set is stale. Safe to call on every join
-- and before every read.
function ProgressionService.refreshQuests(player: Player): ()
	local data = PlayerProfile.get(player)
	if not data then
		return
	end
	local today = utcDay(os.time())
	if data.Quests.RolledOn == today and #data.Quests.Slots > 0 then
		return
	end
	PlayerProfile.mutate(player, function(d)
		d.Quests.Slots = pickQuests(player.UserId, today)
		d.Quests.RolledOn = today
	end)
end

-- Advances every quest watching `metric`. Called by the systems that own the
-- counters, so quest progress is a consequence of play rather than a parallel
-- tally that could drift from it.
--
-- `value` is an ABSOLUTE reading for gauge metrics (bestStreak) and an INCREMENT
-- for counters (rolls, forges); `absolute` says which, because taking the max of
-- an increment or summing a gauge are both silently wrong.
function ProgressionService.advanceQuests(player: Player, metric: string, value: number, absolute: boolean?): ()
	local data = PlayerProfile.get(player)
	if not data or not ForgeMath.isFinite(value) then
		return
	end
	PlayerProfile.mutate(player, function(d)
		for _, slot in ipairs(d.Quests.Slots) do
			local def = questDef(slot.Id)
			if def ~= nil and def.metric == metric and not slot.Claimed then
				if absolute then
					if value > slot.Progress then
						slot.Progress = value
					end
				else
					slot.Progress += value
				end
			end
		end
	end)
end

-- The target for a quest id, for callers that must draw a progress bar. Exposed
-- so StateSyncService does not keep a second copy of the quest table -- the copy
-- nobody executes is the one that drifts (L-026).
function ProgressionService.getQuestTarget(questId: string): number?
	local def = questDef(questId)
	return if def ~= nil then def.target else nil
end

function ProgressionService.claimQuest(player: Player, questId: string): (boolean, string?)
	local data = PlayerProfile.get(player)
	if not data then
		return false, "no_profile"
	end
	ProgressionService.refreshQuests(player)

	local def = questDef(questId)
	if def == nil then
		return false, "unknown_quest"
	end

	-- Eligibility is re-read INSIDE the mutation and the claim flag is set there
	-- too, so two requests racing cannot both pass the check and both pay out.
	local granted = false
	local ok, reason = PlayerProfile.mutate(player, function(d)
		for _, slot in ipairs(d.Quests.Slots) do
			if slot.Id == questId then
				if slot.Claimed then
					return
				end
				if slot.Progress < def.target then
					return
				end
				slot.Claimed = true
				granted = true
				return
			end
		end
	end)
	if not ok then
		return false, reason or "mutate_failed"
	end
	if not granted then
		return false, "not_claimable"
	end

	local okCredit, creditReason = EconomyService.credit(player, def.rewardKind, def.rewardAmount, "quest_" .. questId)
	if not okCredit then
		PlayerProfile.mutate(player, function(d)
			for _, slot in ipairs(d.Quests.Slots) do
				if slot.Id == questId then
					slot.Claimed = false
					return
				end
			end
		end)
		return false, creditReason or "credit_failed"
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Playtime chests (SRS FR-10.3)
--
-- Server-clocked at 5, 15 and 45 minutes of SESSION time. Session-scoped by
-- design: the timer starts at join and is not persisted, so it rewards time
-- actually spent in this session and cannot be accumulated across rejoins.
--------------------------------------------------------------------------------

local CHEST_REWARDS: { [string]: { kind: EconomyService.Currency, amount: number } } = {
	Tier1 = { kind = "Cash", amount = 500 },
	Tier2 = { kind = "Cash", amount = 1500 },
	Tier3 = { kind = "Gems", amount = 25 },
	Tier4 = { kind = "Gems", amount = 50 },
	Tier5 = { kind = "Cash", amount = 10000 },
	Tier6 = { kind = "Diamonds", amount = 3 },
}

-- Session start and which tiers this session has already paid.
local sessionStart: { [Player]: number } = {}
local chestsTaken: { [Player]: { [string]: boolean } } = {}

function ProgressionService.beginSession(player: Player): ()
	sessionStart[player] = os.clock()
	chestsTaken[player] = {}
	ProgressionService.refreshQuests(player)
	ProgressionService.recordLogin(player)
end

function ProgressionService.endSession(player: Player): ()
	sessionStart[player] = nil
	chestsTaken[player] = nil
end

-- Seconds this player has been in THIS session, from the server's own clock.
function ProgressionService.sessionSeconds(player: Player): number
	local started = sessionStart[player]
	if started == nil then
		return 0
	end
	return math.max(0, os.clock() - started)
end

function ProgressionService.claimChest(player: Player, tierId: string): (boolean, string?)
	local required = CHEST_TIMES_SEC[tierId]
	local reward = CHEST_REWARDS[tierId]
	if required == nil or reward == nil then
		return false, "unknown_tier"
	end
	if PlayerProfile.get(player) == nil then
		return false, "no_profile"
	end

	local taken = chestsTaken[player]
	if taken == nil then
		return false, "no_session"
	end
	if taken[tierId] then
		return false, "already_claimed"
	end
	if ProgressionService.sessionSeconds(player) < required then
		return false, "not_ready"
	end

	-- Marked before crediting so a duplicate request in the same frame cannot
	-- pass the check twice.
	taken[tierId] = true
	local okCredit, creditReason = EconomyService.credit(player, reward.kind, reward.amount, "chest_" .. tierId)
	if not okCredit then
		taken[tierId] = nil
		return false, creditReason or "credit_failed"
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Daily login streak (SRS FR-10.2)
--
-- Escalating rewards with EXACTLY ONE forgiveness token, as specified. The
-- profile carried `LoginStreak = { Count, LastDay, ForgivenessLeft }` from the
-- beginning and nothing ever wrote it.
--------------------------------------------------------------------------------

local LOGIN_REWARDS: { { kind: EconomyService.Currency, amount: number } } = {
	{ kind = "Cash", amount = 300 },
	{ kind = "Cash", amount = 700 },
	{ kind = "Gems", amount = 20 },
	{ kind = "Cash", amount = 2000 },
	{ kind = "Gems", amount = 45 },
	{ kind = "Cash", amount = 5000 },
	{ kind = "Diamonds", amount = 5 },
}

-- Called once per session at join. Idempotent within a UTC day: joining five
-- times does not advance the streak five times.
function ProgressionService.recordLogin(player: Player): (boolean, number)
	local data = PlayerProfile.get(player)
	if not data then
		return false, 0
	end

	local today = utcDay(os.time())
	local last = data.LoginStreak.LastDay
	if last == today then
		return false, data.LoginStreak.Count
	end

	local gap = today - last
	local newCount: number
	local spendForgiveness = false

	if last == 0 or gap == 1 then
		-- First ever login, or a clean consecutive day.
		newCount = data.LoginStreak.Count + 1
	elseif gap == 2 and data.LoginStreak.ForgivenessLeft > 0 then
		-- Exactly one missed day, and a token to cover it. FR-10.2 allows one.
		newCount = data.LoginStreak.Count + 1
		spendForgiveness = true
	else
		-- A longer gap, or the token is spent. The streak restarts honestly --
		-- and the token does NOT come back, because a renewable forgiveness is
		-- not a streak.
		newCount = 1
	end

	local awarded = LOGIN_REWARDS[math.min(newCount, #LOGIN_REWARDS)]

	local ok, reason = PlayerProfile.mutate(player, function(d)
		d.LoginStreak.Count = newCount
		d.LoginStreak.LastDay = today
		if spendForgiveness then
			d.LoginStreak.ForgivenessLeft -= 1
		end
	end)

	if not ok then
		-- NOT CREDITED (LOGIN-1). The streak write is what makes this reward once-only;
		-- if it did not land, paying anyway turns a rejoin into a repeatable mint.
		return false, 0
	end

	if awarded ~= nil then
		EconomyService.credit(player, awarded.kind, awarded.amount, "login_streak")
	end
	return true, newCount
end

return ProgressionService
