--!strict
-- IT-2 — Integration_Forge (TEST_PLAN.md §5)
-- Valid proposal applies: cost deducted, distribution stored, subsequent sampling reflects the new masses.
-- Invalid proposal: ok=false, and BOTH budget and Cash remain byte-identical to before.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ForgeService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("ForgeService"))
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

local function approx(a: number, b: number, tol: number): boolean
	return math.abs(a - b) <= tol
end

local function run(): (boolean, string?, number)
	n = 0
	local e: any = nil

	local fakePlayer = Fakes.createFakePlayer(1002, "ForgePlayer")
	local fakeData = PlayerProfile._reconcile({})
	
	PlayerProfile._injectProfileForTesting(fakePlayer, Fakes.createFakeProfile(fakeData))
	ForgeService._setResultEmitterForTesting(function() end)
	
	-- Give the player plenty of Cash to afford forging
	EconomyService.credit(fakePlayer, "Cash", 1000000, "test_init")
	local initialCash = EconomyService.balance(fakePlayer, "Cash") or 0
	e = e or check(initialCash == 1000000, "Failed to initialize test cash")

	local initialDie = fakeData.Dice[1]
	e = e or check(initialDie ~= nil, "Player should have a starting die")
	local initialBudget = initialDie.MassBudget
	
	-- 1. INVALID proposal: both budget and Cash byte-identical to before
	local invalidDistribution = { initialDie.MassBudget + 10, 0, 0, 0, 0, 0 } -- exceeds budget
	local okInvalid, reasonInvalid = ForgeService.performForge(fakePlayer, 1, invalidDistribution)
	
	e = e or check(not okInvalid, "Invalid forge proposal should be rejected")
	local cashAfterInvalid = EconomyService.balance(fakePlayer, "Cash") or 0
	e = e or check(cashAfterInvalid == initialCash, "Cash MUST remain byte-identical after invalid proposal")
	
	local budgetAfterInvalid = fakeData.Dice[1].MassBudget
	e = e or check(budgetAfterInvalid == initialBudget, "Budget MUST remain byte-identical after invalid proposal")

	local distUnchanged = true
	for i=1, 6 do
		if fakeData.Dice[1].Faces[i].Mass ~= initialDie.Faces[i].Mass then
			distUnchanged = false
			break
		end
	end
	e = e or check(distUnchanged, "Distribution MUST remain unchanged after invalid proposal")

	-- 2. VALID proposal: cost deducted, distribution stored, subsequent sampling reflects the new masses
	local validDistribution = { 20, 20, 5, 5, 5, 5 } -- sums to 60, valid for D6 with floor=1
	
	local okValid, reasonValid = ForgeService.performForge(fakePlayer, 1, validDistribution)
	e = e or check(okValid, "Valid forge proposal should succeed")
	
	local cashAfterValid = EconomyService.balance(fakePlayer, "Cash") or 0
	e = e or check(cashAfterValid < initialCash, "Cost should be deducted after valid proposal")
	
	local newDie = fakeData.Dice[1]
	for i=1, 6 do
		e = e or check(approx(newDie.Faces[i].Mass, validDistribution[i], 1e-6), "New distribution should be stored")
	end

	-- Subsequent sampling reflects new masses (Face 1 and 2 are 20, others 5).
	-- A quick empirical check with 1000 samples.
	RollService.beginSession(fakePlayer)
	local rng = Random.new(42)
	local face1Count = 0
	for _=1, 1000 do
		local outcomes = RollService.sampleOutcomes(fakeData.Dice, rng)
		if outcomes[1].faceIndex == 1 then
			face1Count += 1
		end
	end
	
	-- P ∝ (M - m) where M=60, m=20, n=6. For face 1: (60-20) / (60*5) = 40/300 ≈ 13.33%
	-- With 1000 samples, expecting around 133 hits.
	e = e or check(face1Count > 100 and face1Count < 180, string.format("Sampling does not reflect new masses, face 1 hit %d times", face1Count))

	-- Cleanup
	RollService.endSession(fakePlayer)
	PlayerProfile.release(fakePlayer)

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "IT-2 Integration_Forge", run = run }
