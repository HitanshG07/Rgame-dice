--!strict
-- UT-5 — Elements (TEST_PLAN.md §4)
--
-- Asserts that element payoffs resolve strictly from the RESOLVED FACE SET with
-- zero positional state, and that:
--   * Gold pays only at >=2 participating faces and SCALES WITH COMBINED
--     INVESTED MASS (SRS FR-4.3, ledger L-016 -- a flat conditional bonus is a
--     defect, not a tuning choice)
--   * Fire spills to other dice
--   * Freeze re-rolls its target and KEEPS THE BETTER result (FR-4.4)
--   * Multiplier MULTIPLIES the total rather than adding to it
--
-- The Freeze keep-better and Multiplier multiplies-not-adds assertions were
-- absent from the original draft. Freeze's re-roll was, at that point, not
-- implemented at all: `frozenDie` was recorded on the session and never read.
-- A test that only asserted "a die was marked frozen" passed over a feature
-- that did nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local RollService = require(Server:WaitForChild("RollService"))

local n = 0
local function check(cond: boolean, msg: string): string?
	n += 1
	if not cond then
		return msg
	end
	return nil
end

-- A die whose face 1 is overwhelmingly heavy is NOT the most likely to land
-- face 1 -- P is inverse in mass. To force a known landing we make every OTHER
-- face maximally heavy, so the target face is the lightest and dominates.
local function dieLandingOn(shape: string, faceCount: number, targetFace: number,
	targetMass: number, element: string): RollService.Die
	local faces: { RollService.Face } = {}
	for i = 1, faceCount do
		faces[i] = {
			Mass = if i == targetFace then targetMass else targetMass * 50,
			Element = if i == targetFace then element else "None",
		}
	end
	local budget = 0
	for i = 1, faceCount do
		budget += faces[i].Mass
	end
	return { Shape = shape, MassBudget = budget, Faces = faces }
end

local function run(): (boolean, string?, number)
	n = 0
	local e: string?

	----------------------------------------------------------------------------
	-- Gold: conditional, and mass-coupled (SRS FR-4.3)
	----------------------------------------------------------------------------

	e = e or check(ElementCatalog.goldPayoff(0, 0) == 0, "Gold must pay 0 with no participating faces")
	e = e or check(ElementCatalog.goldPayoff(1, 50) == 0, "Gold must pay 0 with exactly 1 Gold face")
	e = e or check(ElementCatalog.goldPayoff(2, 0) == 0, "Gold with zero combined mass must pay 0")

	local g1 = ElementCatalog.goldPayoff(2, 20)
	local g2 = ElementCatalog.goldPayoff(2, 40)
	e = e or check(g1 > 0, "Gold must pay something at 2 participating faces")
	e = e or check(g2 > g1, string.format(
		"Gold payoff did not scale with combined mass: mass=20 -> %.2f, mass=40 -> %.2f", g1, g2))

	-- SUPERLINEAR, not merely increasing. Doubling the combined mass must more
	-- than double the payoff, or Gold cannot compete with plain cash faces for
	-- the same mass and the element is inert in practice.
	e = e or check(g2 > g1 * 2.0, string.format(
		"Gold payoff must be SUPERLINEAR in combined mass: 2x mass gave only %.3fx payoff", g2 / g1))

	-- And it must not be flat in the participant COUNT alone: a flat conditional
	-- bonus is algebraically inert (ledger L-016).
	local sameCountMoreMass = ElementCatalog.goldPayoff(2, 100)
	e = e or check(sameCountMoreMass > g2,
		"Gold payoff is flat with respect to mass at a fixed count -- this is the inert-bonus defect")

	----------------------------------------------------------------------------
	-- Fire: unconditional spill onto other dice
	----------------------------------------------------------------------------

	e = e or check(ElementCatalog.firePayoff(100, 0) == 0, "Fire must pay 0 when there are no other dice")
	local f1 = ElementCatalog.firePayoff(100, 1)
	local f2 = ElementCatalog.firePayoff(100, 2)
	e = e or check(f1 > 0, "Fire must pay when at least one other die exists")
	e = e or check(f2 > f1, "Fire spill must scale with the number of other dice")
	e = e or check(ElementCatalog.firePayoff(200, 1) > f1, "Fire spill must scale with its own face value")

	----------------------------------------------------------------------------
	-- Multiplier: MULTIPLIES the total, never adds to it
	----------------------------------------------------------------------------

	local m1 = ElementCatalog.multiplierFactor(10)
	local m2 = ElementCatalog.multiplierFactor(20)
	e = e or check(m1 > 1.0, "Multiplier factor must exceed 1")
	e = e or check(m2 > m1, "Multiplier factor must scale with its own invested mass")
	e = e or check(ElementCatalog.multiplierFactor(0) == 1.0,
		"Multiplier at zero mass must be exactly 1.0 (no effect), not an additive floor")

	-- The structural assertion: resolveElements returns the multiplier in the
	-- FACTOR channel and contributes nothing to the ADDITIVE channel. If a future
	-- edit turns it into a flat bonus, this fails.
	local multOutcomes: { RollService.DieOutcome } = {
		{ dieIndex = 1, faceIndex = 1, mass = 20, element = "Multiplier", baseValue = 400 },
		{ dieIndex = 2, faceIndex = 1, mass = 20, element = "None", baseValue = 400 },
	}
	local mAdd, mFac, mFired = RollService.resolveElements(multOutcomes)
	e = e or check(mAdd == 0, string.format(
		"Multiplier must contribute NOTHING additively, got %.4f -- it multiplies, it does not add", mAdd))
	e = e or check(mFac > 1.0, string.format("Multiplier must raise the factor channel, got %.4f", mFac))
	e = e or check(#mFired == 1 and mFired[1] == "Multiplier", "Multiplier should report as fired")

	----------------------------------------------------------------------------
	-- Gold through the full resolver
	----------------------------------------------------------------------------

	local goldOutcomes: { RollService.DieOutcome } = {
		{ dieIndex = 1, faceIndex = 1, mass = 20, element = "Gold", baseValue = 400 },
		{ dieIndex = 2, faceIndex = 1, mass = 20, element = "Gold", baseValue = 400 },
	}
	local add, fac, fired, frozen = RollService.resolveElements(goldOutcomes)
	e = e or check(add > 0, "two Gold faces must produce an additive bonus")
	e = e or check(fac == 1.0, "Gold must not touch the multiplicative channel")
	e = e or check(#fired == 1 and fired[1] == "Gold", "fired list should contain exactly 'Gold'")
	e = e or check(frozen == nil, "Gold must not freeze a die")

	-- One Gold face alone fires nothing at all.
	local loneGold: { RollService.DieOutcome } = {
		{ dieIndex = 1, faceIndex = 1, mass = 20, element = "Gold", baseValue = 400 },
		{ dieIndex = 2, faceIndex = 1, mass = 20, element = "None", baseValue = 400 },
	}
	local loneAdd, _, loneFired = RollService.resolveElements(loneGold)
	e = e or check(loneAdd == 0, "a single Gold face must add nothing")
	e = e or check(#loneFired == 0, "a single Gold face must not report as fired")

	----------------------------------------------------------------------------
	-- Freeze: marks a partner, then RE-ROLLS IT AND KEEPS THE BETTER (FR-4.4)
	----------------------------------------------------------------------------

	local freezeOutcomes: { RollService.DieOutcome } = {
		{ dieIndex = 1, faceIndex = 1, mass = 10, element = "Freeze", baseValue = 100 },
		{ dieIndex = 2, faceIndex = 1, mass = 30, element = "None", baseValue = 900 },
	}
	local _, _, firedFz, frozenFz = RollService.resolveElements(freezeOutcomes)
	e = e or check(frozenFz == 2, "Freeze must lock the highest-value partner die")
	e = e or check(#firedFz == 1 and firedFz[1] == "Freeze", "fired list should contain 'Freeze'")

	-- Freeze must never target its own die -- that would be a self-reroll loop.
	local selfFreeze: { RollService.DieOutcome } = {
		{ dieIndex = 1, faceIndex = 1, mass = 10, element = "Freeze", baseValue = 100 },
	}
	local _, _, _, soloFrozen = RollService.resolveElements(selfFreeze)
	e = e or check(soloFrozen == nil, "Freeze with no partner must freeze nothing, never itself")

	-- THE KEEP-THE-BETTER ASSERTION.
	--
	-- Two dice. Die 2 is built so its faces differ enormously in value, so a
	-- re-roll has a real chance of improving. Across many seeds, the average
	-- payout WITH die 2 frozen must strictly exceed the average WITHOUT it.
	-- A "keep the better of two draws" rule can only ever raise the mean; if
	-- the re-roll is unimplemented, or keeps the worse, this fails.
	local dieA = dieLandingOn("D6", 6, 1, 10, "None")
	local dieB: RollService.Die = {
		Shape = "D6",
		MassBudget = 60,
		Faces = {
			{ Mass = 30, Element = "None" }, { Mass = 2, Element = "None" },
			{ Mass = 2, Element = "None" }, { Mass = 2, Element = "None" },
			{ Mass = 2, Element = "None" }, { Mass = 22, Element = "None" },
		},
	}
	local dice: { RollService.Die } = { dieA, dieB }

	local TRIALS = 400
	local sumPlain, sumFrozen = 0.0, 0.0
	for seed = 1, TRIALS do
		local plain = RollService.computeThrow(dice, Random.new(seed), {
			streak = 0, streakStrengthLevel = 0, hasShield = false, shieldReady = false,
		})
		local withFreeze = RollService.computeThrow(dice, Random.new(seed), {
			streak = 0, streakStrengthLevel = 0, hasShield = false, shieldReady = false,
			frozenDie = 2,
		})
		sumPlain += plain.baseTotal
		sumFrozen += withFreeze.baseTotal
	end
	local avgPlain = sumPlain / TRIALS
	local avgFrozen = sumFrozen / TRIALS
	e = e or check(avgFrozen > avgPlain, string.format(
		"a frozen die must be re-rolled keeping the BETTER result: avg without freeze %.2f, with freeze %.2f",
		avgPlain, avgFrozen))

	-- Never worse: keep-the-better cannot reduce a single throw below the
	-- un-frozen draw made from the same seed.
	local anyWorse = false
	for seed = 1, 100 do
		local plain = RollService.computeThrow(dice, Random.new(seed), {
			streak = 0, streakStrengthLevel = 0, hasShield = false, shieldReady = false,
		})
		local withFreeze = RollService.computeThrow(dice, Random.new(seed), {
			streak = 0, streakStrengthLevel = 0, hasShield = false, shieldReady = false,
			frozenDie = 2,
		})
		if withFreeze.baseTotal < plain.baseTotal - ForgeMath.EPSILON then
			anyWorse = true
			break
		end
	end
	e = e or check(not anyWorse, "a frozen die produced a WORSE result than the un-frozen draw")

	-- An out-of-range frozen index must be ignored, not indexed.
	local outOfRange = RollService.computeThrow(dice, Random.new(7), {
		streak = 0, streakStrengthLevel = 0, hasShield = false, shieldReady = false,
		frozenDie = 99,
	})
	e = e or check(ForgeMath.isFinite(outOfRange.payout),
		"an out-of-range frozenDie must be ignored safely")

	----------------------------------------------------------------------------
	-- No positional input: outcomes alone determine every element result
	----------------------------------------------------------------------------

	-- The resolver's ONLY argument is the resolved face set. Re-running it on an
	-- identical face set must give an identical answer, and reordering the array
	-- must not change the additive or multiplicative totals -- position in the
	-- list is not physical position, and neither exists server-side (HLD §1).
	local orderA: { RollService.DieOutcome } = {
		{ dieIndex = 1, faceIndex = 2, mass = 15, element = "Gold", baseValue = 225 },
		{ dieIndex = 2, faceIndex = 3, mass = 25, element = "Gold", baseValue = 625 },
		{ dieIndex = 3, faceIndex = 1, mass = 5, element = "None", baseValue = 25 },
	}
	local orderB: { RollService.DieOutcome } = {
		{ dieIndex = 3, faceIndex = 1, mass = 5, element = "None", baseValue = 25 },
		{ dieIndex = 2, faceIndex = 3, mass = 25, element = "Gold", baseValue = 625 },
		{ dieIndex = 1, faceIndex = 2, mass = 15, element = "Gold", baseValue = 225 },
	}
	local addA, facA = RollService.resolveElements(orderA)
	local addA2, facA2 = RollService.resolveElements(orderA)
	local addB, facB = RollService.resolveElements(orderB)
	e = e or check(addA == addA2 and facA == facA2,
		"element resolution must be deterministic for an identical face set")
	e = e or check(math.abs(addA - addB) < ForgeMath.EPSILON,
		string.format("element resolution depended on list ORDER: %.6f vs %.6f", addA, addB))
	e = e or check(math.abs(facA - facB) < ForgeMath.EPSILON,
		"element multiplicative resolution depended on list order")

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-5 Elements", run = run }
