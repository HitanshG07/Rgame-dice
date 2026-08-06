--!strict
-- UT-4 — Payout (TEST_PLAN.md §4), with UT-5 element assertions folded in.
--
-- Elements were folded in rather than deferred because ElementCatalog enforces
-- the mass-coupling rule that three separate simulations proved is load-bearing
-- (ledger L-016). Leaving it unverified while building on top of it is exactly
-- the pattern that produced L-013.
--
-- Payout = (baseTotal + additive) * multiplicativeFactor * streakMultiplier * coin

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))
local RollService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("RollService"))

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

-- A die whose face 1 is overwhelmingly heavy is *rare*; to force a specific
-- face deterministically we build a die where only one face can be drawn by
-- giving every other face effectively all the mass. Simpler and more honest:
-- construct the outcome tables directly for the element tests.
local function outcome(dieIndex: number, mass: number, element: string): RollService.DieOutcome
	return {
		dieIndex = dieIndex,
		faceIndex = 1,
		mass = mass,
		element = element,
		baseValue = ForgeMath.faceValue(mass),
	}
end

local function makeDie(masses: { number }, elements: { string }?): RollService.Die
	local faces = table.create(#masses)
	for i, m in ipairs(masses) do
		faces[i] = { Mass = m, Element = if elements then elements[i] else "None" }
	end
	local total = 0
	for _, m in ipairs(masses) do total += m end
	return { Shape = "D" .. tostring(#masses), MassBudget = total, Faces = faces }
end

local function run(): (boolean, string?, number)
	n = 0
	local e: string?

	----------------------------------------------------------------------------
	-- STREAK MULTIPLIER: must COMPOUND. A linear multiplier was measured and
	-- cannot move the forge optimum at any strength (ledger L-016), so linearity
	-- here would silently collapse the sniper/grinder fork.
	----------------------------------------------------------------------------
	local b = RollService.streakStrengthToB(10)      -- 0.10
	e = e or check(approx(b, 0.10, 1e-12), "streakStrengthToB(10) should be 0.10")
	e = e or check(RollService.streakStrengthToB(0) == 0, "level 0 must give b = 0")
	e = e or check(RollService.streakStrengthToB(-5) == 0, "negative level must give b = 0")

	e = e or check(RollService.streakMultiplier(0, b) == 1, "streak 0 must be 1x")
	e = e or check(approx(RollService.streakMultiplier(1, b), 1.1, 1e-9), "streak 1 at b=0.1 should be 1.1")
	e = e or check(approx(RollService.streakMultiplier(2, b), 1.21, 1e-9), "streak 2 at b=0.1 should be 1.21")

	-- the compounding proof: successive gains must GROW, not stay constant
	local g1 = RollService.streakMultiplier(2, b) - RollService.streakMultiplier(1, b)
	local g2 = RollService.streakMultiplier(3, b) - RollService.streakMultiplier(2, b)
	e = e or check(g2 > g1,
		string.format("streak multiplier is not compounding: gain 2->3 (%.6f) <= gain 1->2 (%.6f)", g2, g1))

	e = e or check(RollService.streakMultiplier(5, 0) == 1, "b = 0 must yield 1x at any streak")

	-- cap: beyond STREAK_CAP the multiplier must stop growing
	local atCap = RollService.streakMultiplier(RollService.STREAK_CAP, b)
	local pastCap = RollService.streakMultiplier(RollService.STREAK_CAP + 500, b)
	e = e or check(approx(atCap, pastCap, 1e-9), "streak multiplier grew past STREAK_CAP")
	e = e or check(ForgeMath.isFinite(pastCap), "capped multiplier is not finite")

	-- an extreme b must not produce a non-finite payout
	local huge = RollService.streakMultiplier(RollService.STREAK_CAP, 5.0)
	e = e or check(ForgeMath.isFinite(huge) and huge <= RollService.MAX_STREAK_MULTIPLIER,
		"an extreme b escaped MAX_STREAK_MULTIPLIER")
	e = e or check(RollService.streakMultiplier(0 / 0, b) == 1, "NaN streak must fall back to 1x")
	e = e or check(RollService.streakMultiplier(5, 0 / 0) == 1, "NaN b must fall back to 1x")

	----------------------------------------------------------------------------
	-- VOID DETECTION: the lightest face is the streak breaker (SRS FR-5.2)
	----------------------------------------------------------------------------
	-- a face AT the floor is the Void
	local skewed = makeDie({ 30, 6, 6, 6, 6, 1 })
	e = e or check(RollService.isVoidFace(skewed, 6), "face 6 (mass 1, at the floor) should be the Void")
	e = e or check(not RollService.isVoidFace(skewed, 1), "the heaviest face must not be the Void")
	e = e or check(not RollService.isVoidFace(skewed, 3), "a mid-weight face must not be the Void")

	-- F-G3-1: an UN-FORGED FLAT die must have NO Void at all. Before this fix
	-- face 1 was treated as a Void on a starting die, so a brand-new player
	-- broke their streak 1-in-6 rolls with no way to avoid it. SRS FR-5.2 says
	-- a Void is "a face at or near the mass floor" -- a flat die has none.
	local flat = makeDie({ 10, 10, 10, 10, 10, 10 })
	for i = 1, 6 do
		e = e or check(not RollService.isVoidFace(flat, i),
			string.format("flat die face %d must NOT be a Void -- no face is near the floor", i))
	end

	-- the lightest face is only a Void if it is ALSO near the floor
	local mild = makeDie({ 20, 12, 12, 8, 4, 4 })
	e = e or check(not RollService.isVoidFace(mild, 5),
		"mass 4 is the lightest but sits well above the floor -- not a Void")

	----------------------------------------------------------------------------
	-- GOLD: conditional AND mass-coupled. This is the single most important
	-- assertion in the suite -- a flat conditional bonus is algebraically inert
	-- and is a DEFECT, not a tuning choice (SRS FR-4.3).
	----------------------------------------------------------------------------
	e = e or check(ElementCatalog.goldPayoff(1, 50) == 0, "a lone Gold face must pay nothing")
	e = e or check(ElementCatalog.goldPayoff(0, 0) == 0, "zero Gold faces must pay nothing")
	e = e or check(ElementCatalog.goldPayoff(2, 20) > 0, "two Gold faces must pay")

	-- scaling: doubling combined mass must MORE than double the payoff
	local small = ElementCatalog.goldPayoff(2, 20)
	local large = ElementCatalog.goldPayoff(2, 40)
	e = e or check(large > small * 2,
		string.format("Gold payoff is not superlinear in combined mass: %.2f vs %.2f", large, small))
	-- and it must not be flat in mass, which is the inert failure mode
	e = e or check(ElementCatalog.goldPayoff(2, 20) ~= ElementCatalog.goldPayoff(2, 60),
		"CRITICAL: Gold payoff is FLAT in combined mass - the element is algebraically inert")

	-- resolveElements: Gold fires only with a partner
	local loneGold = { outcome(1, 20, "Gold"), outcome(2, 20, "None") }
	local addA, facA, firedA = RollService.resolveElements(loneGold)
	e = e or check(addA == 0, "a lone Gold contributed an additive bonus")
	e = e or check(facA == 1, "a lone Gold changed the multiplier")
	e = e or check(#firedA == 0, "a lone Gold reported as fired")

	local pairGold = { outcome(1, 20, "Gold"), outcome(2, 20, "Gold") }
	local addB, _, firedB = RollService.resolveElements(pairGold)
	e = e or check(addB > 0, "a Gold pair contributed nothing")
	e = e or check(table.find(firedB, "Gold") ~= nil, "a Gold pair did not report as fired")

	-- three Gold faces must beat two at the same per-face mass
	local trioGold = { outcome(1, 20, "Gold"), outcome(2, 20, "Gold"), outcome(3, 20, "Gold") }
	local addC = RollService.resolveElements(trioGold)
	e = e or check(addC > addB, "three Gold faces did not beat two")

	----------------------------------------------------------------------------
	-- FIRE spills additively; MULTIPLIER multiplies rather than adds
	----------------------------------------------------------------------------
	local fire = { outcome(1, 20, "Fire"), outcome(2, 10, "None"), outcome(3, 10, "None") }
	local addF, facF, firedF = RollService.resolveElements(fire)
	e = e or check(addF > 0, "Fire spilled nothing onto its partners")
	e = e or check(facF == 1, "Fire altered the multiplicative factor - it should be additive")
	e = e or check(table.find(firedF, "Fire") ~= nil, "Fire did not report as fired")

	local solo = { outcome(1, 20, "Fire") }
	local addS = RollService.resolveElements(solo)
	e = e or check(addS == 0, "Fire spilled with no partner die present")

	local mult = { outcome(1, 20, "Multiplier"), outcome(2, 10, "None") }
	local addM, facM, firedM = RollService.resolveElements(mult)
	e = e or check(addM == 0, "Multiplier added instead of multiplying")
	e = e or check(facM > 1, "Multiplier did not raise the factor above 1")
	e = e or check(table.find(firedM, "Multiplier") ~= nil, "Multiplier did not report as fired")
	e = e or check(ElementCatalog.multiplierFactor(40) > ElementCatalog.multiplierFactor(20),
		"Multiplier factor does not scale with invested mass")

	----------------------------------------------------------------------------
	-- FREEZE targets a DIFFERENT die, never itself
	----------------------------------------------------------------------------
	local freeze = { outcome(1, 20, "Freeze"), outcome(2, 30, "None"), outcome(3, 10, "None") }
	local _, _, firedZ, frozen = RollService.resolveElements(freeze)
	e = e or check(frozen ~= nil, "Freeze locked nothing")
	e = e or check(frozen ~= 1, "Freeze locked itself")
	e = e or check(frozen == 2, "Freeze should lock the highest-value partner (die 2)")
	e = e or check(table.find(firedZ, "Freeze") ~= nil, "Freeze did not report as fired")

	local loneFreeze = { outcome(1, 20, "Freeze") }
	local _, _, _, frozenSolo = RollService.resolveElements(loneFreeze)
	e = e or check(frozenSolo == nil, "Freeze locked a die when it was the only die")

	----------------------------------------------------------------------------
	-- computeThrow: the assembled formula, and the shield
	----------------------------------------------------------------------------
	local plainDice = { makeDie({ 10, 10, 10, 10, 10, 10 }) }
	local res = RollService.computeThrow(plainDice, Random.new(1), {
		streak = 0, streakStrengthLevel = 0, hasShield = false, shieldReady = false,
	})
	e = e or check(ForgeMath.isFinite(res.payout) and res.payout >= 0, "payout is not finite and non-negative")
	e = e or check(approx(res.payout, res.baseTotal, 1e-6),
		"with no elements, no streak strength and no bonus, payout should equal baseTotal")

	-- F-G3-3: this previously asserted `streak == 0 or streak == 1`, which after
	-- one throw from streak 0 is a TAUTOLOGY -- it could not fail and proved
	-- nothing. Now that a flat die has no Void, the outcome is deterministic:
	-- the streak MUST advance.
	e = e or check(not res.voidHit, "a flat die must never register a Void hit")
	e = e or check(res.streak == 1, "a non-Void throw from streak 0 must advance to 1")

	-- shield: prevents the break when ready, does not when not
	local voidDice = { makeDie({ 30, 10, 10, 10, 8, 1 }) }
	local brokeWithout, savedWith = false, false
	for seed = 1, 400 do
		local r = RollService.computeThrow(voidDice, Random.new(seed), {
			streak = 5, streakStrengthLevel = 10, hasShield = false, shieldReady = false,
		})
		if r.voidHit then
			brokeWithout = true
			e = e or check(r.streak == 0, "a Void with no shield did not reset the streak to 0")
			e = e or check(approx(r.streakMultiplier, 1, 1e-9),
				"a broken streak did not pay at 1x")

			local s = RollService.computeThrow(voidDice, Random.new(seed), {
				streak = 5, streakStrengthLevel = 10, hasShield = true, shieldReady = true,
			})
			savedWith = true
			e = e or check(s.voidHit, "the same seed did not reproduce the Void")
			e = e or check(s.streak == 6, "a ready shield did not preserve the streak")

			local d = RollService.computeThrow(voidDice, Random.new(seed), {
				streak = 5, streakStrengthLevel = 10, hasShield = true, shieldReady = false,
			})
			e = e or check(d.streak == 0, "a shield on cooldown still absorbed the break")
			break
		end
	end
	e = e or check(brokeWithout, "no Void occurred in 400 seeded throws - the test proved nothing")
	e = e or check(savedWith, "the shield branch was never exercised")

	-- non-void throws advance the streak and pay above 1x at positive b
	for seed = 1, 400 do
		local r = RollService.computeThrow(voidDice, Random.new(seed), {
			streak = 3, streakStrengthLevel = 10, hasShield = false, shieldReady = false,
		})
		if not r.voidHit then
			e = e or check(r.streak == 4, "a non-Void throw did not advance the streak")
			e = e or check(r.streakMultiplier > 1, "a live streak paid at 1x")
			break
		end
	end

	-- a hostile coinBonus must not poison the payout
	local bad = RollService.computeThrow(plainDice, Random.new(9), {
		streak = 0, streakStrengthLevel = 0, hasShield = false, shieldReady = false,
		coinBonus = 0 / 0,
	})
	e = e or check(ForgeMath.isFinite(bad.payout), "a NaN coinBonus produced a non-finite payout")
	e = e or check(bad.payout > 0, "a NaN coinBonus zeroed a legitimate payout")

	----------------------------------------------------------------------------
	-- performRoll — the wired service shell, driven through the Studio-only
	-- emitter seam so no test scaffolding lives in the production path.
	----------------------------------------------------------------------------
	local Fakes = require(script.Parent:WaitForChild("Fakes"))
	local PlayerProfile = require(ServerScriptService:WaitForChild("Server"):WaitForChild("PlayerProfile"))
	local EconomyService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("EconomyService"))

	local fakePlayer = Fakes.createFakePlayer(9999, "ShellTestPlayer")
	local fakeData = PlayerProfile._reconcile({})
	PlayerProfile._injectProfileForTesting(fakePlayer, Fakes.createFakeProfile(fakeData))
	RollService.beginSession(fakePlayer)

	-- Capture the emitted RollResult, and record the balance AT THE MOMENT OF
	-- EMISSION. SRS FR-2.6 requires Cash to be credited BEFORE the event fires,
	-- so that a dropped RollResult never costs the player their money.
	local emitted: { any } = {}
	local balanceAtEmit: number? = nil
	RollService._setResultEmitterForTesting(function(player, payload)
		balanceAtEmit = EconomyService.balance(player, "Cash")
		table.insert(emitted, payload)
	end)

	local rollOk, rollReason = RollService.performRoll(fakePlayer)
	e = e or check(rollOk, string.format("performRoll should succeed, got reason: %s", tostring(rollReason)))

	local cashBal = EconomyService.balance(fakePlayer, "Cash")
	e = e or check(cashBal ~= nil and cashBal > 0, "performRoll should credit Cash")
	e = e or check(#emitted == 1, string.format("performRoll should emit exactly one RollResult, got %d", #emitted))

	if #emitted == 1 then
		local payload = emitted[1]
		e = e or check(balanceAtEmit ~= nil and balanceAtEmit > 0,
			"Cash must be credited BEFORE RollResult fires (SRS FR-2.6) -- balance was zero at emission")
		e = e or check(type(payload.faces) == "table" and #payload.faces == #fakeData.Dice,
			"RollResult must name one landed face per die")
		e = e or check(ForgeMath.isFinite(payload.payout) and payload.payout >= 0,
			"RollResult payout must be a finite, non-negative number")
		e = e or check(type(payload.streak) == "number", "RollResult must carry the streak")
		e = e or check(type(payload.voidHit) == "boolean", "RollResult must carry voidHit")
		e = e or check(math.abs(payload.payout - (cashBal :: number)) < 1e-6, string.format(
			"the reported payout (%.4f) must equal the credited amount (%.4f)",
			payload.payout, cashBal :: number))
	end

	-- The vault rate is written back, and the T-30 floor keeps it conservative
	-- rather than astronomical for a session that is barely a moment old.
	e = e or check(ForgeMath.isFinite(fakeData.Vault.AvgIncomePerSec),
		"performRoll must write a finite AvgIncomePerSec")
	e = e or check(fakeData.Vault.AvgIncomePerSec <= (cashBal :: number) / 60 + 1e-6, string.format(
		"AvgIncomePerSec (%.6f) exceeded the 60s minimum-window floor (threat T-30)",
		fakeData.Vault.AvgIncomePerSec))

	-- Ten more rolls: no errors, Cash rises monotonically, streak tracks.
	local prevCash = cashBal :: number
	local monotonic = true
	for _ = 1, 10 do
		local ok = RollService.performRoll(fakePlayer)
		if not ok then
			monotonic = false
			break
		end
		local nowCash = EconomyService.balance(fakePlayer, "Cash") :: number
		if nowCash < prevCash then
			monotonic = false
			break
		end
		prevCash = nowCash
	end
	e = e or check(monotonic, "ten consecutive rolls must all succeed with monotonically rising Cash")
	e = e or check(#emitted == 11, string.format("expected 11 emitted results, got %d", #emitted))
	e = e or check(RollService.getStreak(fakePlayer) >= 0, "performRoll should track the session streak")

	-- A roll for a player with no session is refused, not defaulted.
	local ghost = Fakes.createFakePlayer(9998, "NoSessionPlayer")
	local ghostOk = RollService.performRoll(ghost)
	e = e or check(not ghostOk, "performRoll must refuse a player with no session")

	RollService._setResultEmitterForTesting(nil)
	RollService.endSession(fakePlayer)
	PlayerProfile.release(fakePlayer)

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-4 Payout", run = run }
