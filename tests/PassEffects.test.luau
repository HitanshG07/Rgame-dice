--!strict
-- PassEffects.test.luau
-- Unit tests for P-5A2: Gamepass entitlement wiring into Economy, Roll, Forge, and StateSync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local PurchaseService = require(Server:WaitForChild("PurchaseService"))
local EconomyService = require(Server:WaitForChild("EconomyService"))
local ForgeService = require(Server:WaitForChild("ForgeService"))
local StateSyncService = require(Server:WaitForChild("StateSyncService"))
local Fakes = require(ServerScriptService:WaitForChild("Tests"):WaitForChild("Fakes"))

local PassEffectsTest = {}

function PassEffectsTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	PlayerProfile.init()
	PurchaseService.init()

	local fakePlayer = Fakes.createFakePlayer(999888, "TestPassPlayer")
	local liveData = PlayerProfile._reconcile({})
	local fakeProfile = Fakes.createFakeProfile(liveData)
	PlayerProfile._injectProfileForTesting(fakePlayer, fakeProfile)

	-- 1. Test forgeCostMultiplier
	local baseCost = ForgeService.computeForgeCost({ 10, 10, 10, 10, 10, 10 }, { 20, 10, 10, 10, 5, 5 }, 60.0, fakePlayer)
	check(baseCost > 0 and baseCost ~= math.huge, "base forge cost should be finite")
	check(baseCost == 100, "base forge cost should be 100")

	-- 2. Test cashMultiplier via EconomyService
	local startCash = PlayerProfile.get(fakePlayer).Cash
	local ok, _ = EconomyService.credit(fakePlayer, "Cash", 100, "roll")
	check(ok, "roll cash credit failed")
	local postCash = PlayerProfile.get(fakePlayer).Cash
	check(postCash == startCash + 100, "unowned cashMultiplier should credit 1x")

	-- 3. Test bonusDieSlots in StateSyncService
	local snapshot = StateSyncService.buildSnapshot(PlayerProfile.get(fakePlayer), 0, fakePlayer)
	check(snapshot.dieSlots == 1, "default dieSlots should be 1")

	-- 4. Test non-roll credits do NOT apply cashMultiplier
	local okRefund, _ = EconomyService.credit(fakePlayer, "Cash", 50, "forge_refund")
	check(okRefund, "refund credit failed")
	check(PlayerProfile.get(fakePlayer).Cash == postCash + 50, "refund should credit exact 50 without multiplier")

	PlayerProfile.releaseAll()
	return true, nil, asserts
end

return {
	name = "PassEffects.test",
	run = PassEffectsTest.run,
}
