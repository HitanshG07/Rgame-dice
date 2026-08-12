--!strict
-- OfflineService.luau
-- Offline earnings vault accrual, capacity/efficiency calculations, and atomic claims (SRS FR-8; threats T-20, T-23, T-24, T-30).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local OfflineService = {}

--------------------------------------------------------------------------------
-- Constants & Calculations (SRS FR-8.3)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- VAULT TIERS (operator-set 2026-08-13)
--
-- EFFICIENCY is the fraction of the player's own recent earning rate the vault
-- pays for time spent away. 0.50 means "half what you would have made playing".
--
-- EVERY SOURCE ADDS, AND THE TOTAL IS CAPPED AT 1.0.
--
--   base                    50%
--   Cash upgrades   +5%/lvl  -> +25% at level 5
--   Roblox Premium         +15%
--   VIP Vault pass         +25%
--                          ----
--   fully stacked          100%
--
-- WHY THE CAP IS 1.0 AND NOT HIGHER. The operator's first instinct was VIP 1.25x
-- and Premium 1.5x, which multiply out past 100% -- and anything above 100% means
-- the vault pays MORE than playing does. In an idle game that inverts the whole
-- proposition: the optimal move becomes closing the game, and every session a
-- player does play is time they lost money. Capping at parity keeps offline
-- generous without ever beating live play.
--
-- The additive shape is what makes all three purchases matter at once. A tiered
-- "VIP overrides everything" model, which is what this replaced, made the Cash
-- upgrades worthless the moment the pass was bought.
local BASE_CAPACITY_SEC = 4 * 3600        -- 4 hours
local BASE_EFFICIENCY = 0.5               -- 50%
local UPGRADE_CAPACITY_PER_LEVEL = 2880   -- +0.8h per level (10 levels = +8h)
local UPGRADE_EFFICIENCY_PER_LEVEL = 0.05 -- +5% per level (5 levels = +25%)

OfflineService.PREMIUM_EFFICIENCY_BONUS = 0.15
OfflineService.PREMIUM_CAPACITY_BONUS_SEC = 4 * 3600
OfflineService.VIP_EFFICIENCY_BONUS = 0.25
OfflineService.VIP_CAPACITY_SEC = 24 * 3600
OfflineService.MAX_EFFICIENCY = 1.0

-- Roblox Premium, read from the platform rather than from anything the client
-- says. `MembershipType` is server-authoritative.
local function hasPremium(player: Player): boolean
	local ok, result = pcall(function()
		return player.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and result == true
end

OfflineService._hasPremium = hasPremium

function OfflineService.getCapacity(player: Player): number
	local PurchaseService = require(script.Parent:WaitForChild("PurchaseService"))
	local data = PlayerProfile.get(player)
	local level = if data ~= nil then (data.Upgrades.VaultCapacity or 0) else 0

	local capacity = BASE_CAPACITY_SEC + (level * UPGRADE_CAPACITY_PER_LEVEL)
	if hasPremium(player) then
		capacity += OfflineService.PREMIUM_CAPACITY_BONUS_SEC
	end
	-- VIP SETS A FLOOR rather than overriding. It used to return 24h outright,
	-- which meant a player with maxed Cash upgrades plus Premium could have been
	-- entitled to more and been silently cut back to 24 by buying the pass.
	if PurchaseService.ownsPass(player, "VipVault") then
		capacity = math.max(capacity, OfflineService.VIP_CAPACITY_SEC)
	end
	return capacity
end

function OfflineService.getEfficiency(player: Player): number
	local PurchaseService = require(script.Parent:WaitForChild("PurchaseService"))
	local data = PlayerProfile.get(player)
	local level = if data ~= nil then (data.Upgrades.VaultEfficiency or 0) else 0

	local efficiency = BASE_EFFICIENCY + (level * UPGRADE_EFFICIENCY_PER_LEVEL)
	if hasPremium(player) then
		efficiency += OfflineService.PREMIUM_EFFICIENCY_BONUS
	end
	if PurchaseService.ownsPass(player, "VipVault") then
		efficiency += OfflineService.VIP_EFFICIENCY_BONUS
	end
	-- The cap is the whole safety property -- see the header.
	return math.min(OfflineService.MAX_EFFICIENCY, efficiency)
end

--------------------------------------------------------------------------------
-- Accrual Inspection & Claiming
--------------------------------------------------------------------------------

export type VaultStatus = {
	unclaimedEarnings: number,
	elapsedSeconds: number,
	claimableSeconds: number,
	capacitySeconds: number,
	efficiency: number,
	ratePerSec: number,
	accrualId: number,
}

-- THE FROZEN OFFLINE WINDOW, per player, in seconds. Captured once at join and
-- never advanced while the session runs -- see `getStatus` for why.
--
-- Keyed by Player and cleared on leave, so a departed player holds no reference.
local sessionElapsed: { [Player]: number } = {}

-- Captures how long the player was away, ONCE, at the moment they join.
--
-- Called by the bootstrap immediately after the profile loads and BEFORE the
-- first snapshot is pushed, so the very first vault figure the client sees is
-- already the frozen one.
function OfflineService.beginSession(player: Player): ()
	local data = PlayerProfile.get(player)
	if not data then
		return
	end

	local lastSeen = data.Vault.LastSeen
	local elapsed = 0
	if lastSeen > 0 then
		elapsed = os.time() - lastSeen
		if elapsed < 0 then
			-- Clock skew, or a profile written by a server whose clock ran ahead.
			-- Zero rather than a negative window; never a windfall.
			warn(string.format("[OfflineService] negative elapsed time (%d s) for UserId=%d -- clock skew protection",
				elapsed, player.UserId))
			elapsed = 0
		end
	end
	sessionElapsed[player] = elapsed
end

function OfflineService.getStatus(player: Player): VaultStatus?
	local data = PlayerProfile.get(player)
	if not data then
		return nil
	end

	-- THE VAULT IS FROZEN FOR THE DURATION OF THE SESSION.
	--
	-- OPERATOR-REPORTED: the vault filled while the player sat in the game. It
	-- measured `os.time() - LastSeen`, and `LastSeen` was only ever written on
	-- LEAVE and on CLAIM -- never on join -- so every second spent playing was
	-- counted as time spent away. Free income that scaled with session length,
	-- compounded with capacity upgrades, and removed any reason to log off.
	--
	-- WHY FREEZE RATHER THAN STAMP `LastSeen` ON JOIN. Stamping on join is the
	-- obvious fix and it is wrong: it zeroes the accrual the player just came
	-- back to collect. The offline earnings have to survive until claimed, but
	-- must not GROW while the player is online.
	--
	-- So the elapsed window is captured ONCE, by `beginSession`, and read from
	-- here for the rest of the session. Absent (never joined through the normal
	-- path) falls back to the live clock, which preserves the old behaviour for
	-- the unit suite's direct callers rather than silently reporting zero.
	local frozen = sessionElapsed[player]
	local elapsed: number
	if frozen ~= nil then
		elapsed = frozen
	else
		local now = os.time()
		local lastSeen = data.Vault.LastSeen
		elapsed = 0
		if lastSeen > 0 then
			elapsed = now - lastSeen
			if elapsed < 0 then
				warn(string.format("[OfflineService] negative elapsed time (%d s) for UserId=%d -- clock skew protection",
					elapsed, player.UserId))
				elapsed = 0
			end
		end
	end

	local capacity = OfflineService.getCapacity(player)
	local efficiency = OfflineService.getEfficiency(player)
	local claimable = math.min(elapsed, capacity)

	-- Hardened against T-30 via RollService.averageIncomePerSecond
	local rate = data.Vault.AvgIncomePerSec
	if not ForgeMath.isFinite(rate) or rate < 0 then
		rate = 0
	end

	local earnings = claimable * rate * efficiency
	if not ForgeMath.isFinite(earnings) or earnings < 0 then
		earnings = 0
	end

	return {
		unclaimedEarnings = earnings,
		elapsedSeconds = elapsed,
		claimableSeconds = claimable,
		capacitySeconds = capacity,
		efficiency = efficiency,
		ratePerSec = rate,
		accrualId = data.Vault.AccrualId,
	}
end

-- Atomic claim (SRS FR-8.6, T-24).
function OfflineService.claimVault(player: Player, doubled: boolean): (boolean, string?, number)
	local status = OfflineService.getStatus(player)
	if not status then
		return false, "no_profile", 0
	end

	if status.unclaimedEarnings <= 0 then
		return false, "vault_empty", 0
	end

	local payout = status.unclaimedEarnings
	if doubled then
		payout = payout * 2
	end

	-- ATOMIC MUTATION: consume vault accrual and update LastSeen synchronously.
	local mutated, reason = PlayerProfile.mutate(player, function(d)
		d.Vault.LastSeen = os.time()
		d.Vault.AccrualId += 1
	end)

	if not mutated then
		return false, reason or "mutate_failed", 0
	end

	-- THE FROZEN WINDOW IS SPENT. Without this the claim would leave the same
	-- elapsed time sitting in `sessionElapsed`, and the next `getStatus` would
	-- report the vault as full again -- claimable repeatedly, for the whole
	-- session, from one offline period. Zeroed rather than cleared: clearing
	-- would fall back to the live-clock branch and start accruing while online,
	-- which is the exact bug this freeze exists to prevent.
	sessionElapsed[player] = 0

	local credited, creditReason = EconomyService.credit(player, "Cash", payout, "vault_claim")
	if not credited then
		return false, creditReason or "credit_failed", 0
	end

	return true, nil, payout
end

function OfflineService.onPlayerRemoving(player: Player): ()
	PlayerProfile.mutate(player, function(d)
		d.Vault.LastSeen = os.time()
	end)
	-- Released with the player. A Player key held after they leave keeps the
	-- instance alive and leaks one entry per session on a long-running server.
	sessionElapsed[player] = nil
end

return OfflineService
