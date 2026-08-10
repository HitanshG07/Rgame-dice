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

local BASE_CAPACITY_SEC = 4 * 3600        -- 4 hours
local BASE_EFFICIENCY = 0.5               -- 50%
local UPGRADE_CAPACITY_PER_LEVEL = 2880   -- +0.8h per level (10 levels = +8h -> 12h max)
local UPGRADE_EFFICIENCY_PER_LEVEL = 0.05 -- +5% per level (5 levels = +25% -> 75% max)
local VIP_CAPACITY_SEC = 24 * 3600        -- 24 hours for VIP
local VIP_EFFICIENCY = 1.0                -- 100% for VIP

function OfflineService.getCapacity(player: Player): number
	local PurchaseService = require(script.Parent:WaitForChild("PurchaseService"))
	if PurchaseService.ownsPass(player, "VipVault") then
		return VIP_CAPACITY_SEC
	end
	local data = PlayerProfile.get(player)
	local level = if data ~= nil then (data.Upgrades.VaultCapacity or 0) else 0
	return BASE_CAPACITY_SEC + (level * UPGRADE_CAPACITY_PER_LEVEL)
end

function OfflineService.getEfficiency(player: Player): number
	local PurchaseService = require(script.Parent:WaitForChild("PurchaseService"))
	if PurchaseService.ownsPass(player, "VipVault") then
		return VIP_EFFICIENCY
	end
	local data = PlayerProfile.get(player)
	local level = if data ~= nil then (data.Upgrades.VaultEfficiency or 0) else 0
	return math.min(0.75, BASE_EFFICIENCY + (level * UPGRADE_EFFICIENCY_PER_LEVEL))
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

function OfflineService.getStatus(player: Player): VaultStatus?
	local data = PlayerProfile.get(player)
	if not data then
		return nil
	end

	local now = os.time()
	local lastSeen = data.Vault.LastSeen
	local elapsed = 0

	if lastSeen > 0 then
		elapsed = now - lastSeen
		if elapsed < 0 then
			warn(string.format("[OfflineService] negative elapsed time (%d s) for UserId=%d -- clock skew protection",
				elapsed, player.UserId))
			elapsed = 0
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
end

return OfflineService
