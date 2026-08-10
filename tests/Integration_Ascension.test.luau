--!strict
-- IT-5 — Integration_Ascension (TEST_PLAN.md §5)
-- Triggers Ascension.
-- Asserts Cash, Gems, Upgrades, Quests, Vault, Codes, Streak are WIPED.
-- Asserts Diamonds, Ascensions, LifetimeCash, and Diamond Tree (Shapes, Elements) are PRESERVED.
-- Asserts the new base profile is fully playable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerProfile = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerProfile"))
local EconomyService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("EconomyService"))
local RollService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("RollService"))
local AscensionService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("AscensionService"))
local Fakes = require(script.Parent:WaitForChild("Fakes"))

local n = 0
local function check(cond: boolean, msg: string): string?
	n += 1
	if not cond then
		return msg
	end
	return nil
end

local function run(): (boolean, string?, number)
	n = 0
	local e: any = nil

	local fakePlayer = Fakes.createFakePlayer(1005, "AscensionPlayer")
	local fakeData = PlayerProfile._reconcile({})
	
	-- Pre-ascension setup
	fakeData.Cash = 50000000000 -- Give enough cash to ascend (threshold varies, typically 10B+ depending on rules)
	fakeData.LifetimeCash = 50000000000
	fakeData.Gems = 500
	fakeData.Diamonds = 10
	fakeData.Ascensions = 1
	
	fakeData.Upgrades.AutoRollSpeed = 5
	fakeData.Vault.AccrualId = 123
	fakeData.CodesRedeemed["BETA2026"] = true
	fakeData.LoginStreak.Count = 7
	
	fakeData.Diamond.Elements["Fire"] = true
	fakeData.Diamond.Shapes["D8"] = true
	fakeData.Diamond.StreakStrength = 2
	
	PlayerProfile._injectProfileForTesting(fakePlayer, Fakes.createFakeProfile(fakeData))
	
	-- Note: AscensionService may require a certain lifetime cash threshold.
	-- If this fails, we force the ascension through internal mechanics or ensure the threshold is met.
	local ascensionHandler = AscensionService.ascend :: any
	local ok, diamondsGained, reason = ascensionHandler(fakePlayer)
	
	-- If the game enforces a minimum LifetimeCash, we gave 50B which should be well above typical thresholds.
	e = e or check(ok, "Ascension should succeed. Reason: " .. tostring(reason))
	
	local postData = PlayerProfile.get(fakePlayer)
	e = e or check(postData ~= nil, "Profile should exist after ascension")

	if postData then
		-- 1. Asserts WIPED state
		e = e or check(postData.Cash == 0, "Cash MUST be wiped")
		e = e or check(postData.Gems == 0, "Gems MUST be wiped")
		
		e = e or check(postData.Upgrades.AutoRollSpeed == 0, "Upgrades MUST be wiped")
		e = e or check(postData.Vault.AccrualId == 0, "Vault MUST be wiped")
		e = e or check(postData.CodesRedeemed["BETA2026"] == nil, "Codes MUST be wiped")
		e = e or check(postData.LoginStreak.Count == 0, "LoginStreak MUST be wiped")

		-- 2. Asserts PRESERVED state
		e = e or check(postData.Diamonds > 10, "Diamonds MUST be preserved and granted")
		e = e or check(postData.Ascensions == 2, "Ascensions MUST be incremented (was 1, now 2)")
		e = e or check(postData.LifetimeCash == 50000000000, "LifetimeCash MUST be preserved")
		
		e = e or check(postData.Diamond.Elements["Fire"] == true, "Diamond Tree Elements MUST be preserved")
		e = e or check(postData.Diamond.Shapes["D8"] == true, "Diamond Tree Shapes MUST be preserved")
		e = e or check(postData.Diamond.StreakStrength == 2, "Diamond Tree StreakStrength MUST be preserved")
		
		-- 3. Playable check (can roll and accrue cash again)
		RollService.beginSession(fakePlayer)
		
		RollService._setResultEmitterForTesting(function() end)
		local rollOk, rollReason = RollService.performRoll(fakePlayer)
		e = e or check(rollOk, "Player MUST be able to roll after ascension")
		
		local cashAfterRoll = EconomyService.balance(fakePlayer, "Cash") or 0
		e = e or check(cashAfterRoll > 0, "Player MUST accrue Cash from rolling after ascension")
		
		RollService.endSession(fakePlayer)
	end
	
	PlayerProfile.release(fakePlayer)

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "IT-5 Integration_Ascension", run = run }
