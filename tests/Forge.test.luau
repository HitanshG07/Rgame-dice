--!strict
-- UT-12 — ForgeService (TEST_PLAN.md §4, added 2026-08-06)
--
-- WHY THIS SUITE EXISTS. ForgeService shipped calling `ElementCatalog.getElement`,
-- a function that has never existed -- the accessor is `exists`. Every element
-- assignment would have crashed. It reached a "MECHANICALLY-CLEAN" gate and a
-- zero-finding cross-vendor audit because no suite required the module and the
-- static-analysis procedure was never run. TEST_PLAN §5 covers the forge only at
-- integration level (IT-2), which is Block 6 -- three blocks too late.
--
-- The rule this encodes: a service module that no suite requires is a module
-- whose symbols are never resolved.
--
-- Covers: closed-system validation and atomic rejection (FR-3.2), cost scaling
-- with magnitude of mass moved (FR-3.3), element allowlisting (FR-4.1, T-5),
-- and non-destructive shape changes (FR-6.1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local ForgeService = require(Server:WaitForChild("ForgeService"))
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local EconomyService = require(Server:WaitForChild("EconomyService"))

local Fakes = require(script.Parent:WaitForChild("Fakes"))

local n = 0
local function check(cond: boolean, msg: string): string?
	n += 1
	if not cond then
		return msg
	end
	return nil
end

local function snapshotDie(data: any, index: number): { number }
	local out: { number } = {}
	for i, face in ipairs(data.Dice[index].Faces) do
		out[i] = face.Mass
	end
	return out
end

local function sameDistribution(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if math.abs(a[i] - b[i]) > 1e-9 then
			return false
		end
	end
	return true
end

local function run(): (boolean, string?, number)
	n = 0
	local e: string?

	local player = Fakes.createFakePlayer(5150, "ForgeTestPlayer")
	local data = PlayerProfile._reconcile({})
	PlayerProfile._injectProfileForTesting(player, Fakes.createFakeProfile(data))

	local emitted: { any } = {}
	ForgeService._setResultEmitterForTesting(function(_, payload)
		table.insert(emitted, payload)
	end)

	----------------------------------------------------------------------------
	-- Cost model (SRS FR-3.3): non-trivial and scaling with mass MOVED
	----------------------------------------------------------------------------

	local flat = { 10, 10, 10, 10, 10, 10 }
	e = e or check(ForgeService.computeForgeCost(flat, flat) == 0,
		"moving no mass must cost nothing")

	local small = ForgeService.computeForgeCost(flat, { 12, 8, 10, 10, 10, 10 })
	local large = ForgeService.computeForgeCost(flat, { 30, 6, 6, 6, 6, 6 })
	e = e or check(small > 0, "moving mass must cost something")
	e = e or check(large > small, string.format(
		"forge cost must scale with the MAGNITUDE of mass moved: small=%.2f large=%.2f", small, large))

	-- Free re-forging collapses the cross-die puzzle to a solved symmetric state
	-- (ledger L-016). The cost is a correctness requirement, not a monetisation
	-- lever, so a near-zero cost for a large move is a defect.
	e = e or check(large >= 100, string.format(
		"a large redistribution cost only %.2f -- effectively free re-forging (FR-3.3)", large))

	-- A mismatched or non-finite proposal is priced at infinity, never at zero.
	e = e or check(ForgeService.computeForgeCost(flat, { 10, 10, 10 }) == math.huge,
		"a wrong-length proposal must price as unaffordable, not free")
	e = e or check(ForgeService.computeForgeCost(flat, { 0 / 0, 10, 10, 10, 10, 10 }) == math.huge,
		"a NaN proposal must price as unaffordable, not free")

	----------------------------------------------------------------------------
	-- A rejected proposal mutates NOTHING (SRS FR-3.2)
	----------------------------------------------------------------------------

	EconomyService.credit(player, "Cash", 100000, "test_setup")
	local cashBefore = EconomyService.balance(player, "Cash") :: number
	local distBefore = snapshotDie(data, 1)
	local budgetBefore = data.Dice[1].MassBudget

	local rejects: { { name: string, dist: any } } = {
		{ name = "wrong length", dist = { 10, 10, 10, 10, 10 } },
		{ name = "too long", dist = { 10, 10, 10, 10, 10, 10, 10 } },
		{ name = "sum too high", dist = { 20, 10, 10, 10, 10, 10 } },
		{ name = "sum too low", dist = { 5, 10, 10, 10, 10, 10 } },
		{ name = "negative mass", dist = { -10, 14, 14, 14, 14, 14 } },
		{ name = "below floor", dist = { 0, 12, 12, 12, 12, 12 } },
		{ name = "NaN", dist = { 0 / 0, 10, 10, 10, 10, 10 } },
		{ name = "positive infinity", dist = { math.huge, 10, 10, 10, 10, 10 } },
		{ name = "negative infinity", dist = { -math.huge, 10, 10, 10, 10, 10 } },
		{ name = "not a table", dist = "cheese" },
		{ name = "string element", dist = { "10", 10, 10, 10, 10, 10 } },
	}

	for _, case in ipairs(rejects) do
		local ok = ForgeService.performForge(player, 1, case.dist :: any)
		e = e or check(not ok, string.format("forge proposal '%s' must be rejected", case.name))
		e = e or check(sameDistribution(snapshotDie(data, 1), distBefore),
			string.format("rejected proposal '%s' MUTATED the die", case.name))
		e = e or check(EconomyService.balance(player, "Cash") == cashBefore,
			string.format("rejected proposal '%s' charged the player", case.name))
		e = e or check(data.Dice[1].MassBudget == budgetBefore,
			string.format("rejected proposal '%s' altered the mass budget", case.name))
	end

	-- Out-of-range die indices are rejected before anything is read.
	for _, badIndex in ipairs({ 0, -1, 2, 999, 1.5 }) do
		local ok = ForgeService.performForge(player, badIndex, { 10, 10, 10, 10, 10, 10 })
		e = e or check(not ok, string.format("die index %s must be rejected", tostring(badIndex)))
	end
	e = e or check(sameDistribution(snapshotDie(data, 1), distBefore),
		"a bad die index mutated the die")

	----------------------------------------------------------------------------
	-- A valid proposal applies, costs Cash, and changes future sampling
	----------------------------------------------------------------------------

	local proposal = { 30, 6, 6, 6, 6, 6 }
	local expectedCost = ForgeService.computeForgeCost(distBefore, proposal)
	local okForge, forgeReason = ForgeService.performForge(player, 1, proposal)
	e = e or check(okForge, string.format("a valid proposal must be accepted, got '%s'", tostring(forgeReason)))
	e = e or check(sameDistribution(snapshotDie(data, 1), proposal),
		"an accepted proposal must be stored exactly")
	e = e or check(data.Dice[1].MassBudget == budgetBefore,
		"forging is ZERO-SUM: the budget must be unchanged by a redistribution")

	local cashAfter = EconomyService.balance(player, "Cash") :: number
	e = e or check(math.abs((cashBefore - cashAfter) - expectedCost) < 1e-6, string.format(
		"expected a charge of %.4f, actually charged %.4f", expectedCost, cashBefore - cashAfter))
	e = e or check(#emitted == 1, string.format("a successful forge should emit one result, got %d", #emitted))

	-- The masses actually drive the odds: the heaviest face is now the LEAST
	-- likely to land, which is the whole mechanic (SRS FR-2.3).
	local probs = ForgeMath.landingProbabilities(proposal)
	e = e or check(probs[1] < probs[2], string.format(
		"the heaviest face must land LESS often after forging: P(heavy)=%.4f P(light)=%.4f",
		probs[1], probs[2]))

	-- Affordability is enforced: drain the balance and the next forge fails.
	local drained = EconomyService.balance(player, "Cash") :: number
	EconomyService.debit(player, "Cash", drained, "test_drain")
	local pauperDist = snapshotDie(data, 1)
	local pauperOk = ForgeService.performForge(player, 1, { 6, 30, 6, 6, 6, 6 })
	e = e or check(not pauperOk, "a forge the player cannot afford must be rejected")
	e = e or check(sameDistribution(snapshotDie(data, 1), pauperDist),
		"an unaffordable forge mutated the die anyway")
	EconomyService.credit(player, "Cash", 100000, "test_refill")

	----------------------------------------------------------------------------
	-- Element assignment (SRS FR-4.1, threat T-5)
	----------------------------------------------------------------------------

	-- THE REGRESSION GUARD. A nonexistent element id must be REJECTED, and the
	-- rejection must come from an allowlist check that itself resolves -- the
	-- shipped code called a nonexistent accessor here and crashed instead.
	local unknownOk = ForgeService.performSetElement(player, 1, 1, "Plutonium")
	e = e or check(not unknownOk, "an unknown element id must be rejected")

	for _, bad in ipairs({ "", "none", "GOLD", "__index" }) do
		local ok = ForgeService.performSetElement(player, 1, 1, bad)
		e = e or check(not ok, string.format("element id '%s' must be rejected", bad))
	end

	local nonStringOk = ForgeService.performSetElement(player, 1, 1, 42 :: any)
	e = e or check(not nonStringOk, "a non-string element id must be rejected")

	-- A real element the player has NOT unlocked is still refused.
	e = e or check(ElementCatalog.exists("Gold"), "Gold must exist in the catalog")
	e = e or check(data.Diamond.Elements.Gold ~= true, "Gold should start locked")
	local lockedOk = ForgeService.performSetElement(player, 1, 1, "Gold")
	e = e or check(not lockedOk, "an element the player has not unlocked must be refused")
	e = e or check(data.Dice[1].Faces[1].Element == "None", "a refused element assignment mutated the face")

	-- Unlock it, then it applies and costs Cash.
	data.Diamond.Elements.Gold = true
	local cashPreElement = EconomyService.balance(player, "Cash") :: number
	local elementOk, elementReason = ForgeService.performSetElement(player, 1, 1, "Gold")
	e = e or check(elementOk, string.format("an unlocked element must apply, got '%s'", tostring(elementReason)))
	e = e or check(data.Dice[1].Faces[1].Element == "Gold", "the element was not stored on the face")
	e = e or check(math.abs((cashPreElement - (EconomyService.balance(player, "Cash") :: number))
		- ForgeService.ELEMENT_SET_COST) < 1e-6, "element assignment did not charge the stated cost")

	-- Out-of-range face indices are refused.
	for _, badFace in ipairs({ 0, 7, -3 }) do
		local ok = ForgeService.performSetElement(player, 1, badFace, "Gold")
		e = e or check(not ok, string.format("face index %d must be rejected", badFace))
	end

	----------------------------------------------------------------------------
	-- Shape change (SRS FR-6.1) — reversible, therefore non-confiscatory
	----------------------------------------------------------------------------

	local lockedShapeOk = ForgeService.performSetShape(player, 1, "D20")
	e = e or check(not lockedShapeOk, "a shape the player has not unlocked must be refused")
	e = e or check(data.Dice[1].Shape == "D6", "a refused shape change altered the die")

	e = e or check(not ForgeService.performSetShape(player, 1, "D7"),
		"a shape that does not exist must be refused")

	data.Diamond.Shapes.D20 = true

	-- Insufficient Diamonds: refused, and nothing changes.
	e = e or check((data.Diamonds :: number) == 0, "Diamonds should start at 0")
	local brokeOk = ForgeService.performSetShape(player, 1, "D20")
	e = e or check(not brokeOk, "a shape change the player cannot afford must be refused")
	e = e or check(data.Dice[1].Shape == "D6", "an unaffordable shape change altered the die")

	EconomyService.credit(player, "Diamonds", 20, "test_setup")

	-- Changing to the shape already equipped is a no-op and must not be charged.
	local diamondsBefore = EconomyService.balance(player, "Diamonds") :: number
	local sameOk = ForgeService.performSetShape(player, 1, "D6")
	e = e or check(not sameOk, "changing to the currently equipped shape must be refused")
	e = e or check(EconomyService.balance(player, "Diamonds") == diamondsBefore,
		"a no-op shape change charged Diamonds")

	-- The real change: budget carries across (clamped into the new shape's legal
	-- range) and elements carry across. Confiscating purchased progression would
	-- make the change anything but "freely reversible".
	local shapeOk, shapeReason = ForgeService.performSetShape(player, 1, "D20")
	e = e or check(shapeOk, string.format("an unlocked, affordable shape change must apply, got '%s'",
		tostring(shapeReason)))
	e = e or check(data.Dice[1].Shape == "D20", "the shape was not stored")

	local d20 = DiceCatalog.getShape("D20")
	e = e or check(d20 ~= nil, "D20 must exist in the catalog")
	if d20 then
		e = e or check(#data.Dice[1].Faces == d20.faceCount, string.format(
			"a D20 must have %d faces, got %d", d20.faceCount, #data.Dice[1].Faces))
		e = e or check(data.Dice[1].MassBudget >= d20.defaultBudget, string.format(
			"the new budget (%s) must be at least the shape default (%d)",
			tostring(data.Dice[1].MassBudget), d20.defaultBudget))
		e = e or check(data.Dice[1].MassBudget <= d20.cashBudgetCap,
			"the carried budget must be clamped to the shape's cap")

		local sum = 0
		for _, face in ipairs(data.Dice[1].Faces) do
			sum += face.Mass
		end
		e = e or check(math.abs(sum - data.Dice[1].MassBudget) < ForgeMath.EPSILON, string.format(
			"the new faces must sum to the stored budget: faces=%.4f budget=%.4f",
			sum, data.Dice[1].MassBudget))

		local floor = DiceCatalog.getMassFloor("D20")
		local aboveFloor = true
		for _, face in ipairs(data.Dice[1].Faces) do
			if face.Mass < floor then
				aboveFloor = false
			end
		end
		e = e or check(aboveFloor, "every face after a shape change must sit at or above the mass floor")
	end

	e = e or check(data.Dice[1].Faces[1].Element == "Gold",
		"a shape change CONFISCATED a purchased element -- FR-6.1 calls the change reversible")

	e = e or check(math.abs(diamondsBefore - (EconomyService.balance(player, "Diamonds") :: number)
		- ForgeService.SHAPE_CHANGE_DIAMOND_COST) < 1e-6,
		"the shape change did not charge the stated Diamond cost")

	-- And the die is immediately forgeable in its new shape: the budget and the
	-- faces agree, so a valid proposal against the stored budget is accepted.
	local newBudget = data.Dice[1].MassBudget
	local newDist: { number } = {}
	for i = 1, 20 do
		newDist[i] = newBudget / 20
	end
	newDist[1] = newDist[1] + 5
	newDist[2] = newDist[2] - 5
	local reforgeOk, reforgeReason = ForgeService.performForge(player, 1, newDist)
	e = e or check(reforgeOk, string.format(
		"the die must be forgeable immediately after a shape change, got '%s'", tostring(reforgeReason)))

	ForgeService._setResultEmitterForTesting(nil)
	PlayerProfile.release(player)

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-12 ForgeService", run = run }
