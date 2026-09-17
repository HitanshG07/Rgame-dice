--!strict
-- Vault.test.luau
-- Unit test suite for UT-11: Offline vault accrual, capacity limits, clock skew protection, and atomic claims.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")

local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local OfflineService = require(Server:WaitForChild("OfflineService"))
local BoostService = require(Server:WaitForChild("BoostService"))
local Fakes = require(ServerScriptService:WaitForChild("Tests"):WaitForChild("Fakes"))

local VaultTest = {}

function VaultTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	PlayerProfile.init()

	local fakePlayer = Fakes.createFakePlayer(998877, "TestVaultPlayer")
	local liveData = PlayerProfile._reconcile({})
	local fakeProfile = Fakes.createFakeProfile(liveData)
	PlayerProfile._injectProfileForTesting(fakePlayer, fakeProfile)

	-- 1. Base Capacity & Efficiency
	local baseCap = OfflineService.getCapacity(fakePlayer)
	check(baseCap == 14400, "base capacity should be 4h (14400s)")
	local baseEff = OfflineService.getEfficiency(fakePlayer)
	check(baseEff == 0.5, "base efficiency should be 50%")

	-- 2. Status inspection on empty vault
	local status = OfflineService.getStatus(fakePlayer)
	check(status ~= nil, "status should exist")
	check(status ~= nil and status.unclaimedEarnings == 0, "unclaimed earnings should start at 0")

	-- 3. Clock Skew Protection (negative elapsed time)
	liveData.Vault.LastSeen = os.time() + 3600
	local statusSkew = OfflineService.getStatus(fakePlayer)
	check(statusSkew ~= nil and statusSkew.elapsedSeconds == 0, "clock skew (future LastSeen) should yield 0 elapsed seconds")
	liveData.Vault.LastSeen = 0

	----------------------------------------------------------------------------
	-- 3b. THE VAULT IS FROZEN FOR THE SESSION (operator-reported, 2026-08-13)
	----------------------------------------------------------------------------
	--
	-- THE DEFECT: `getStatus` measured `os.time() - LastSeen`, and `LastSeen` was
	-- written only on LEAVE and on CLAIM -- never on join. So every second a
	-- player spent sitting IN the game was counted as time spent away. Free
	-- income that scaled with session length and removed any reason to log off.
	--
	-- The fix freezes the offline window at `beginSession`. These assertions pin
	-- the three properties that make that correct, because getting any one of
	-- them wrong reintroduces either the exploit or a worse bug (losing the
	-- player's earned accrual).

	-- A) The accrual EARNED WHILE AWAY SURVIVES. Stamping LastSeen on join would
	--    be the obvious fix and would zero exactly this.
	liveData.Vault.LastSeen = os.time() - 600   -- ten minutes away
	liveData.Vault.AvgIncomePerSec = 10
	OfflineService.beginSession(fakePlayer)
	local frozen = OfflineService.getStatus(fakePlayer)
	check(frozen ~= nil and frozen.elapsedSeconds >= 595 and frozen.elapsedSeconds <= 605,
		"a ten-minute absence must still be credited after beginSession")
	local earnedAtJoin = frozen ~= nil and frozen.unclaimedEarnings or 0
	check(earnedAtJoin > 0, "an offline period must produce claimable earnings")

	-- B) IT DOES NOT GROW WHILE ONLINE. Rewinding LastSeen simulates wall-clock
	--    time passing during the session; the frozen window must ignore it.
	liveData.Vault.LastSeen = os.time() - 7200  -- as if two hours had now passed
	local stillFrozen = OfflineService.getStatus(fakePlayer)
	check(stillFrozen ~= nil and stillFrozen.elapsedSeconds == frozen.elapsedSeconds,
		"the vault must NOT accrue while the player is online -- this is the exploit")
	check(stillFrozen ~= nil and stillFrozen.unclaimedEarnings == earnedAtJoin,
		"unclaimed earnings must hold steady during a session")

	-- C) CLAIMING SPENDS THE WINDOW. Clearing it instead of zeroing it would fall
	--    back to the live clock and let the same offline period be claimed again
	--    and again for the rest of the session.
	local claimed, claimReason = OfflineService.claimVault(fakePlayer, false)
	check(claimed, "a funded vault must be claimable, got: " .. tostring(claimReason))
	local afterClaim = OfflineService.getStatus(fakePlayer)
	check(afterClaim ~= nil and afterClaim.unclaimedEarnings == 0,
		"the vault must be empty immediately after a claim")
	local secondClaim = OfflineService.claimVault(fakePlayer, false)
	check(not secondClaim, "a claimed vault must not be claimable twice in one session")

	liveData.Vault.LastSeen = 0
	liveData.Vault.AvgIncomePerSec = 0

	-- 4. Timed Boost Test
	local active = BoostService.isBoostActive(fakePlayer, "LuckBoost")
	check(not active, "LuckBoost should start inactive")
	BoostService.addBoost(fakePlayer, "LuckBoost", 2.0, 900)
	local activePost = BoostService.isBoostActive(fakePlayer, "LuckBoost")
	check(activePost, "LuckBoost should be active after addBoost")
	local mult = BoostService.getMultiplier(fakePlayer, "LuckBoost")
	check(mult == 2.0, "LuckBoost multiplier should be 2.0")

	----------------------------------------------------------------------------
	-- 5. VAULT-1: claimVault boost multiplier safety and ordering
	----------------------------------------------------------------------------
	liveData.Vault.LastSeen = os.time() - 300
	liveData.Vault.AvgIncomePerSec = 20
	OfflineService.beginSession(fakePlayer)
	BoostService.addBoost(fakePlayer, "OfflineX2", 2.0, 900)
	local preClaimCash = liveData.Cash
	local okBoostClaim, boostClaimErr, payout = OfflineService.claimVault(fakePlayer, true)
	check(okBoostClaim, "claimVault with OfflineX2 must succeed: " .. tostring(boostClaimErr))
	check(payout > 0, "vault payout must be positive")
	check(liveData.Cash == preClaimCash + payout, "player Cash must be credited exactly the payout")
	check(not BoostService.isBoostActive(fakePlayer, "OfflineX2"), "OfflineX2 boost must be consumed after claim (VAULT-1)")

	PlayerProfile.releaseAll()
	return true, nil, asserts
end

return {
	name = "Vault.test",
	run = VaultTest.run,
}
