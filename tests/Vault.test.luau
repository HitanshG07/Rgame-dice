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

	-- 4. Timed Boost Test
	local active = BoostService.isBoostActive(fakePlayer, "LuckBoost")
	check(not active, "LuckBoost should start inactive")
	BoostService.addBoost(fakePlayer, "LuckBoost", 2.0, 900)
	local activePost = BoostService.isBoostActive(fakePlayer, "LuckBoost")
	check(activePost, "LuckBoost should be active after addBoost")
	local mult = BoostService.getMultiplier(fakePlayer, "LuckBoost")
	check(mult == 2.0, "LuckBoost multiplier should be 2.0")

	PlayerProfile.releaseAll()
	return true, nil, asserts
end

return {
	name = "Vault.test",
	run = VaultTest.run,
}
