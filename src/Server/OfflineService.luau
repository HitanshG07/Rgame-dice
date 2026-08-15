--!strict
-- OfflineService.luau
-- Offline earnings vault accrual, capacity/efficiency calculations, and atomic claims (SRS FR-8; threats T-20, T-23, T-24, T-30).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local VaultCatalog = require(Shared:WaitForChild("VaultCatalog"))

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
-- READ FROM THE SHARED CATALOG. These were locals here, which is why the VAULT
-- panel could not state the player's efficiency or their tier -- the client had
-- no way to reach the numbers. Both sides now read one declaration (L-025).
local BASE_CAPACITY_SEC = VaultCatalog.BASE_CAPACITY_SEC
local BASE_EFFICIENCY = VaultCatalog.BASE_EFFICIENCY
local UPGRADE_CAPACITY_PER_LEVEL = VaultCatalog.UPGRADE_CAPACITY_PER_LEVEL_SEC
local UPGRADE_EFFICIENCY_PER_LEVEL = VaultCatalog.UPGRADE_EFFICIENCY_PER_LEVEL

OfflineService.PREMIUM_EFFICIENCY_BONUS = VaultCatalog.PREMIUM_EFFICIENCY_BONUS
OfflineService.PREMIUM_CAPACITY_BONUS_SEC = VaultCatalog.PREMIUM_CAPACITY_BONUS_SEC
OfflineService.VIP_EFFICIENCY_BONUS = VaultCatalog.VIP_EFFICIENCY_BONUS
OfflineService.VIP_CAPACITY_SEC = VaultCatalog.VIP_CAPACITY_SEC
OfflineService.MAX_EFFICIENCY = VaultCatalog.MAX_EFFICIENCY

-- Roblox Premium, read from the platform rather than from anything the client
-- says. `MembershipType` is server-authoritative.
local function hasPremium(player: Player): boolean
	local ok, result = pcall(function()
		return player.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and result == true
end

OfflineService._hasPremium = hasPremium

--------------------------------------------------------------------------------
-- PASS OWNERSHIP, INJECTED RATHER THAN REQUIRED.
--
-- Three functions here need `PurchaseService.ownsPass` to apply the VIP Vault
-- floor, and `PurchaseService` already requires this module -- so importing it
-- back is a cycle. It was previously worked around with a lazy `require` in
-- each of the three function bodies (L-035), which runs correctly and still
-- leaves the analyser reporting the cycle at every one of those sites.
--
-- Inverting the edge removes it: the bootstrap registers the check, and this
-- module never names PurchaseService. Three lazy requires collapse to one
-- injected function, and the per-call `WaitForChild` they each performed goes
-- with them.
--
-- FAIL-CLOSED DEFAULT: `false`, meaning "does not own the pass". An entitlement
-- must never be granted because wiring is missing -- if the provider is absent
-- the player gets the standard tier, which is the safe direction to be wrong in.
local ownsPassProvider: ((Player, string) -> boolean)? = nil

function OfflineService.setOwnsPassProvider(fn: (Player, string) -> boolean): ()
	ownsPassProvider = fn
end

local function ownsPass(player: Player, passKey: string): boolean
	local provider = ownsPassProvider
	if provider == nil then
		return false
	end
	local ok, result = pcall(provider, player, passKey)
	return ok and result == true
end

function OfflineService.getCapacity(player: Player): number
	local data = PlayerProfile.get(player)
	local level = if data ~= nil then (data.Upgrades.VaultCapacity or 0) else 0

	local capacity = BASE_CAPACITY_SEC + (level * UPGRADE_CAPACITY_PER_LEVEL)

	-- GEM-PURCHASED HOURS, AND THE CAP THAT KEEPS THEM FROM BEING PAY-TO-WIN.
	--
	-- Gems are buyable with Robux, and vault capacity is an economic advantage,
	-- so "Gems buy capacity" is pay-to-win by construction unless something stops
	-- it. That something is this clamp: purchased capacity stops at
	-- MAX_PURCHASED_CAPACITY_SEC, the same total a maxed Cash upgrade reaches.
	-- Paying buys SPEED TO THE CAP, never a higher cap.
	--
	-- CLAMPED ON READ, not only on purchase. The buy path also refuses past the
	-- cap, but a clamp there alone would be one bug away from unbounded -- a bad
	-- migration, a future grant path, or a hand-edited profile would all sail
	-- past it. Enforcing it here means no stored value can produce more capacity
	-- than the ceiling allows, whatever wrote it.
	local purchased = tonumber(data ~= nil and data.Vault.PurchasedHours or 0) or 0
	if purchased ~= purchased or purchased < 0 then
		purchased = 0
	end
	capacity += math.min(purchased * 3600, VaultCatalog.MAX_PURCHASED_CAPACITY_SEC)

	if hasPremium(player) then
		capacity += OfflineService.PREMIUM_CAPACITY_BONUS_SEC
	end
	-- VIP SETS A FLOOR rather than overriding. It used to return 24h outright,
	-- which meant a player with maxed Cash upgrades plus Premium could have been
	-- entitled to more and been silently cut back to 24 by buying the pass.
	if ownsPass(player, "VipVault") then
		capacity = math.max(capacity, OfflineService.VIP_CAPACITY_SEC)
	end
	return capacity
end

-- HOW MANY MORE GEM-HOURS WOULD ACTUALLY RAISE THIS PLAYER'S CAPACITY.
--
-- THE DEFECT THIS EXISTS TO CLOSE (operator-reported 2026-08-15, "how does this
-- work if its still 24hrs"). VIP sets a 24h FLOOR, and every other source sums
-- to at most 20h -- base 4 + upgrades 4 + Gems 8 + Premium 4. So for a VIP
-- player the floor swallows the entire Gem purchase: 0 gem-hours gives 24h and
-- 8 gem-hours also gives 24h. They were charged 40 Gems for literally nothing,
-- and the panel then told them "+8h of that is Gem-bought", which was false.
--
-- Selling something that provably does nothing is the worst kind of economy bug,
-- so the buy path refuses it and the panel says why -- rather than taking the
-- Gems and reporting a benefit that did not exist.
--
-- Returns the number of WHOLE HOURS still worth buying: how far the capacity
-- would have to climb before it clears whatever floor is already in effect, on
-- top of what has already been bought, bounded by the purchase cap.
function OfflineService.effectiveBuyableHours(player: Player): number
	local data = PlayerProfile.get(player)
	if not data then
		return 0
	end

	local owned = tonumber(data.Vault.PurchasedHours) or 0
	if owned ~= owned or owned < 0 then
		owned = 0
	end
	local capHours = VaultCatalog.MAX_PURCHASED_CAPACITY_SEC / 3600
	local remainingByCap = math.max(0, capHours - owned)
	if remainingByCap <= 0 then
		return 0
	end

	-- What the capacity would be with the Gem hours removed. Anything at or
	-- below a floor that already exceeds that is capacity the player has for
	-- free, and buying into it changes nothing.
	local level = data.Upgrades.VaultCapacity or 0
	local withoutGems = BASE_CAPACITY_SEC + (level * UPGRADE_CAPACITY_PER_LEVEL)
	if hasPremium(player) then
		withoutGems += OfflineService.PREMIUM_CAPACITY_BONUS_SEC
	end

	local floor = 0
	if ownsPass(player, "VipVault") then
		floor = OfflineService.VIP_CAPACITY_SEC
	end

	-- Hours that would be absorbed before the sum clears the floor.
	local absorbed = math.max(0, floor - withoutGems) / 3600
	local useful = remainingByCap - math.max(0, absorbed - owned)
	return math.max(0, math.floor(useful))
end

function OfflineService.getEfficiency(player: Player): number
	local data = PlayerProfile.get(player)
	local level = if data ~= nil then (data.Upgrades.VaultEfficiency or 0) else 0

	local efficiency = BASE_EFFICIENCY + (level * UPGRADE_EFFICIENCY_PER_LEVEL)
	if hasPremium(player) then
		efficiency += OfflineService.PREMIUM_EFFICIENCY_BONUS
	end
	if ownsPass(player, "VipVault") then
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

-- BUYS VAULT CAPACITY WITH GEMS. The game's only Gems sink (FR-8, operator
-- decision 2026-08-13: "5 gems means 1 hour of storage", "+8h cap" approved).
--
-- Returns (ok, reason, newPurchasedHours).
--
-- THE ORDER OF OPERATIONS IS THE WHOLE SAFETY PROPERTY. Every refusal is checked
-- BEFORE any Gems leave the player, and the capacity is written only after the
-- debit reports success. A grant that ran before a failed debit would mint
-- capacity; a debit that ran before a refused grant would burn Gems for nothing.
-- `EconomyService.debit` refuses rather than going negative, so the failure mode
-- here is "nothing happened", which is the only acceptable one.
function OfflineService.buyVaultHours(player: Player, hours: number): (boolean, string?, number)
	local data = PlayerProfile.get(player)
	if not data then
		return false, "no_profile", 0
	end

	-- Arity and range are validated at the gateway, but this is a currency path
	-- and must not depend on its caller for that.
	if type(hours) ~= "number" or hours ~= hours or hours < 1 then
		return false, "invalid_hours", 0
	end
	hours = math.floor(hours)
	if hours > VaultCatalog.MAX_PURCHASE_HOURS_PER_CALL then
		return false, "invalid_hours", 0
	end

	local owned = tonumber(data.Vault.PurchasedHours) or 0
	if owned ~= owned or owned < 0 then
		owned = 0
	end
	local capHours = VaultCatalog.MAX_PURCHASED_CAPACITY_SEC / 3600
	if owned >= capHours then
		return false, "at_cap", owned
	end

	-- REFUSE A PURCHASE THAT WOULD NOT RAISE CAPACITY. A VIP player's 24h floor
	-- already exceeds everything else combined, so Gems spent there buy nothing
	-- -- see `effectiveBuyableHours`. Taking the payment anyway and reporting a
	-- benefit is the defect the operator caught; refusing is the honest answer.
	if OfflineService.effectiveBuyableHours(player) <= 0 then
		return false, "no_benefit", owned
	end
	-- Trim the request to what is still buyable rather than refusing outright: a
	-- player two hours short of the cap asking for five should get two, not an
	-- error they cannot act on.
	local buyable = math.min(hours, capHours - owned)

	local cost = VaultCatalog.gemCostForHours(buyable)
	if cost == nil or cost <= 0 then
		return false, "invalid_hours", owned
	end

	if not EconomyService.canAfford(player, "Gems", cost) then
		return false, "insufficient_gems", owned
	end

	local spent, spendReason = EconomyService.spend(player, "Gems", cost, "vault_hours")
	if not spent then
		return false, spendReason or "spend_failed", owned
	end

	local applied = owned
	local mutated, mutateReason = PlayerProfile.mutate(player, function(d)
		local cur = tonumber(d.Vault.PurchasedHours) or 0
		if cur ~= cur or cur < 0 then
			cur = 0
		end
		-- Clamped again on write. The read path clamps too (see getCapacity), but
		-- storing a value above the ceiling would still be a lie in the save file.
		cur = math.min(cur + buyable, capHours)
		d.Vault.PurchasedHours = cur
		applied = cur
	end)

	if not mutated then
		-- The Gems are already gone and the capacity did not land. Refund rather
		-- than leave the player short: the debit succeeded, so this is our fault,
		-- not theirs.
		EconomyService.credit(player, "Gems", cost, "vault_hours_refund")
		return false, mutateReason or "mutate_failed", owned
	end

	return true, nil, applied
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
