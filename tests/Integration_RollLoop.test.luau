--!strict
-- IT-1 — Integration_RollLoop (TEST_PLAN.md §5)
-- Full roll intent -> sample -> elements -> streak -> credit -> RollResult.
-- Asserts Cash is credited BEFORE the event fires, and that a dropped RollResult leaves the credit intact (FR-2.6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RollService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("RollService"))
local PlayerProfile = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerProfile"))
local EconomyService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("EconomyService"))
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

	local fakePlayer = Fakes.createFakePlayer(1001, "RollLoopPlayer")
	local fakeData = PlayerProfile._reconcile({})
	
	-- Inject a fake profile to test the roll loop
	PlayerProfile._injectProfileForTesting(fakePlayer, Fakes.createFakeProfile(fakeData))
	RollService.beginSession(fakePlayer)

	local emitted: { any } = {}
	local balanceAtEmit: number? = nil

	RollService._setResultEmitterForTesting(function(player, payload)
		balanceAtEmit = EconomyService.balance(player, "Cash")
		table.insert(emitted, payload)
	end)

	local initialCash = EconomyService.balance(fakePlayer, "Cash") or 0
	e = e or check(initialCash == 0, "Initial cash should be 0")

	-- 1. Full roll intent -> sample -> elements -> streak -> credit -> RollResult
	local rollOk, rollReason = RollService.performRoll(fakePlayer)
	e = e or check(rollOk, "performRoll should succeed")
	
	local cashAfterRoll = EconomyService.balance(fakePlayer, "Cash") or 0
	e = e or check(cashAfterRoll > initialCash, "Cash should increase after a roll")
	e = e or check(#emitted == 1, "Exactly one RollResult should be emitted")

	-- 2. Asserts Cash is credited BEFORE the event fires
	e = e or check(balanceAtEmit ~= nil, "balanceAtEmit should not be nil")
	e = e or check((balanceAtEmit or 0) > initialCash, "Cash must be credited BEFORE RollResult fires (FR-2.6)")
	e = e or check((balanceAtEmit or 0) == cashAfterRoll, "Balance at emission must equal final balance")

	-- 3. Asserts that a dropped/never-delivered RollResult leaves the credit intact
	-- Simulate a dropped event by setting the emitter to do nothing, but still perform the roll
	RollService._setResultEmitterForTesting(function(player, payload)
		-- Dropped event: do nothing, do not record it
	end)

	local cashBeforeDrop = cashAfterRoll
	local rollOkDrop, rollReasonDrop = RollService.performRoll(fakePlayer)
	e = e or check(rollOkDrop, "Second roll should succeed")
	
	local cashAfterDrop = EconomyService.balance(fakePlayer, "Cash") or 0
	e = e or check(cashAfterDrop > cashBeforeDrop, "Credit MUST remain intact even if RollResult is dropped")

	-- Cleanup
	RollService._setResultEmitterForTesting(nil)
	RollService.endSession(fakePlayer)
	PlayerProfile.release(fakePlayer)

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "IT-1 Integration_RollLoop", run = run }
