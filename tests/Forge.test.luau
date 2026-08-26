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
	-- Typed `any` rather than `string?` for one specific Luau reason: the
	-- accumulator idiom `e = e or check(...)` produces a refinement union the
	-- checker cannot collapse back to `string?`, which warns at every call site.
	-- Semantics are unchanged (check still runs only while e is nil) and nothing
	-- is hidden: `e` is a local failure message whose only use is the return below.
	local e: any = nil

	local player = Fakes.createFakePlayer(5150, "ForgeTestPlayer")
	local data = PlayerProfile._reconcile({})

	-- THIS SUITE EXERCISES A D6 EXPLICITLY, rather than whatever shape a new
	-- profile happens to start with.
	--
	-- It used to inherit the template's die and hardcode six-element proposals
	-- against it. When the starting shape became a D2 (operator-directed
	-- 2026-08-11) every proposal here began failing `bad_length` -- the suite was
	-- silently coupled to a product decision it has no interest in.
	--
	-- Six faces is the right fixture for forge maths: it is large enough that a
	-- redistribution has somewhere to go, and small enough to state inline. The
	-- coupling is now explicit and local.
	data.Dice[1] = {
		Shape = "D6",
		MassBudget = 60,
		PurchasedBudget = 60,
		Faces = {
			{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
			{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
			{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
		},
	}
	data.Diamond.Shapes.D6 = true
	-- Worn, because the die above is wearing it. `_reconcile` derives this from
	-- the dice, but it ran before this fixture replaced them -- and a profile
	-- claiming its own equipped shape has never been equipped would hand the
	-- fixture a free switch that no real player gets.
	data.Diamond.ShapesEquipped.D6 = true

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
	-- F-AD-2: the cost must scale with PROGRESSION, not only with mass moved
	----------------------------------------------------------------------------

	-- A flat per-unit cost satisfies FR-3.3's wording and defeats its purpose:
	-- at a late-game balance a flat charge is indistinguishable from free, and
	-- free re-forging collapses the cross-die puzzle (ledger L-016).
	local move = { 30, 6, 6, 6, 6, 6 }
	local atBase = ForgeService.computeForgeCost(flat, move, ForgeService.REFERENCE_BUDGET)
	local atDouble = ForgeService.computeForgeCost(flat, move, ForgeService.REFERENCE_BUDGET * 2)
	local atTen = ForgeService.computeForgeCost(flat, move, ForgeService.REFERENCE_BUDGET * 10)

	e = e or check(atBase > 0, "a forge at the reference budget must still cost something")
	e = e or check(atDouble > atBase, string.format(
		"cost must rise with the die's budget: base=%.2f double=%.2f", atBase, atDouble))
	e = e or check(atTen > atDouble, "cost must keep rising with budget")
	e = e or check(atDouble > atBase * 2.0, string.format(
		"cost must scale SUPERLINEARLY in budget, or it is outrun by income: "
		.. "doubling the budget multiplied cost by only %.3fx", atDouble / atBase))

	-- Never cheaper than the starting die, whatever is passed.
	e = e or check(ForgeService.computeForgeCost(flat, move, 1) >= atBase,
		"a tiny budget must not make forging cheaper than the reference")
	e = e or check(ForgeService.computeForgeCost(flat, move, 0) == math.huge,
		"a zero budget must price as unaffordable, not free")
	e = e or check(ForgeService.computeForgeCost(flat, move, 0 / 0) == math.huge,
		"a NaN budget must price as unaffordable, not free")
	e = e or check(ForgeService.computeForgeCost(flat, move, math.huge) == math.huge,
		"an infinite budget must price as unaffordable, not free")

	-- Omitting the budget keeps the pure mass-only cost, for callers that only
	-- want the FR-3.3 component.
	e = e or check(ForgeService.computeForgeCost(flat, move) == atBase,
		"omitting the budget must equal the cost at the reference budget")

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
	data.Inventory.D20 = 1
	data.Inventory.D6 = 1

	-- THE FIRST EQUIP OF A SHAPE IS FREE (operator decision, 2026-08-11), so an
	-- unaffordable FIRST equip is not a refusal -- it is the discount working.
	--
	-- WHY THE RULE EXISTS. The unlock ladder is priced in Cash and Diamonds only
	-- arrive at ascension, so charging Diamonds to wear a shape for the first
	-- time meant a player could buy the D3 for $500 and be unable to put it on
	-- for their entire first run. Cash buys the shape; Diamonds buy the swapping.
	e = e or check((data.Diamonds :: number) == 0, "Diamonds should start at 0")
	local freeFirstOk, freeFirstReason = ForgeService.performSetShape(player, 1, "D20")
	e = e or check(freeFirstOk, string.format(
		"the FIRST equip of an owned shape must be free, got '%s'", tostring(freeFirstReason)))
	e = e or check(data.Dice[1].Shape == "D20", "the free first equip did not apply")
	e = e or check((EconomyService.balance(player, "Diamonds") :: number) == 0,
		"a first equip must not charge Diamonds")
	e = e or check(data.Diamond.ShapesEquipped.D20 == true,
		"equipping a shape must latch it as worn, or the discount repeats forever")

	-- Back to D6, which the starting die already wore, so this one IS chargeable
	-- -- and with no Diamonds it must be refused, leaving the die untouched.
	local brokeOk = ForgeService.performSetShape(player, 1, "D6")
	e = e or check(not brokeOk,
		"a SECOND equip the player cannot afford must be refused")
	e = e or check(data.Dice[1].Shape == "D20", "an unaffordable shape change altered the die")

	EconomyService.credit(player, "Diamonds", 20, "test_setup")

	-- Now affordable: the charge really happens on a repeat equip.
	local paidBefore = EconomyService.balance(player, "Diamonds") :: number
	local paidOk = ForgeService.performSetShape(player, 1, "D6")
	e = e or check(paidOk, "an affordable repeat equip must apply")
	e = e or check(paidBefore - (EconomyService.balance(player, "Diamonds") :: number)
		== DiceCatalog.SHAPE_CHANGE_DIAMOND_COST,
		"a repeat equip must charge exactly the catalog's switch cost")

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
		-- The floor is the smallest budget the shape can physically hold (every
		-- face at its mass floor) -- deliberately NOT defaultBudget. Clamping up
		-- to defaultBudget is what manufactured budget in finding F-AD-1.
		local minViable = d20.massFloor * d20.faceCount
		e = e or check(data.Dice[1].MassBudget >= minViable, string.format(
			"the new budget (%s) must be at least the viable minimum (%d)",
			tostring(data.Dice[1].MassBudget), minViable))
		e = e or check(data.Dice[1].MassBudget <= d20.cashBudgetCap,
			"the carried budget must be clamped to the shape's cap")
		e = e or check(data.Dice[1].MassBudget <= data.Dice[1].PurchasedBudget, string.format(
			"a shape change must never exceed what was purchased: budget %s vs purchased %s (F-AD-1)",
			tostring(data.Dice[1].MassBudget), tostring(data.Dice[1].PurchasedBudget)))

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
	-- Move a fraction of one face rather than a fixed 5: the carried budget is
	-- now 60 over 20 faces (3 each), so a fixed 5 would drive face 2 negative.
	local shift = newDist[2] * 0.5
	newDist[1] = newDist[1] + shift
	newDist[2] = newDist[2] - shift
	local reforgeOk, reforgeReason = ForgeService.performForge(player, 1, newDist)
	e = e or check(reforgeOk, string.format(
		"the die must be forgeable immediately after a shape change, got '%s'", tostring(reforgeReason)))

	----------------------------------------------------------------------------
	-- Strict Die Ownership Quota: cannot equip more copies than owned in inventory
	----------------------------------------------------------------------------
	PlayerProfile.mutate(player, function(d)
		d.Inventory.D8 = 0
		d.Diamond.Shapes.D8 = true
		d.DieSlots = 2
	end)
	local zeroOwnedOk = ForgeService.performSetShape(player, 1, "D8")
	e = e or check(not zeroOwnedOk, "equipping a shape with 0 owned in inventory must be refused")

	PlayerProfile.mutate(player, function(d)
		d.Inventory.D8 = 1
	end)
	local oneOwnedOk = ForgeService.performSetShape(player, 1, "D8")
	e = e or check(oneOwnedOk, "equipping a shape with 1 owned into slot 1 must succeed")

	local secondSlotOverQuotaOk = ForgeService.performSetShape(player, 2, "D8")
	e = e or check(not secondSlotOverQuotaOk, "equipping a second D8 when only 1 is owned must be refused by quota")

	PlayerProfile.mutate(player, function(d)
		d.Inventory.D8 = 2
	end)
	local secondSlotWithQuotaOk = ForgeService.performSetShape(player, 2, "D8")
	e = e or check(secondSlotWithQuotaOk, "equipping a second D8 once 2 are owned in inventory must succeed")

	-- Clean up slot 2
	PlayerProfile.mutate(player, function(d)
		d.Dice = { d.Dice[1] }
		d.DieSlots = 1
	end)

	----------------------------------------------------------------------------
	-- F-AD-1: a shape change must never MANUFACTURE budget
	----------------------------------------------------------------------------

	-- The exploit this closes: the budget used to be clamped UP to the target
	-- shape's defaultBudget, so D6@60 -> D20 became 200, and switching back to D6
	-- kept 200. Ten Diamonds bought a permanent budget rise that FR-3.6 says must
	-- be purchased with Cash.
	local d6 = DiceCatalog.getShape("D6")
	local d20b = DiceCatalog.getShape("D20")
	if d6 and d20b then
		PlayerProfile.mutate(player, function(d)
			local freshFaces: { any } = {}
			for i = 1, 6 do
				freshFaces[i] = { Mass = 10, Element = "None" }
			end
			d.Dice[1] = { Shape = "D6", MassBudget = 60, PurchasedBudget = 60, Faces = freshFaces }
		end)
		EconomyService.credit(player, "Diamonds", 50, "test_setup")

		local startPurchased = data.Dice[1].PurchasedBudget
		e = e or check(startPurchased == 60, string.format(
			"starting PurchasedBudget should be 60, got %s", tostring(startPurchased)))

		-- D6 -> D20. The budget must NOT rise to D20's defaultBudget of 200.
		local upOk = ForgeService.performSetShape(player, 1, "D20")
		e = e or check(upOk, "D6 -> D20 should succeed")
		e = e or check(data.Dice[1].MassBudget <= startPurchased, string.format(
			"SHAPE CHANGE MANUFACTURED BUDGET: %s -> %s (F-AD-1)",
			tostring(startPurchased), tostring(data.Dice[1].MassBudget)))
		e = e or check(data.Dice[1].PurchasedBudget == startPurchased,
			"PurchasedBudget must be untouched by a shape change")

		-- Every face must still clear the floor at the carried budget.
		local floor20 = DiceCatalog.getMassFloor("D20")
		local ok20 = true
		for _, f in ipairs(data.Dice[1].Faces) do
			if f.Mass < floor20 then
				ok20 = false
			end
		end
		e = e or check(ok20, "carrying a small budget to a wide shape must still clear the mass floor")

		-- ...and back. The round trip must be a no-op on budget.
		local backOk = ForgeService.performSetShape(player, 1, "D6")
		e = e or check(backOk, "D20 -> D6 should succeed")
		e = e or check(data.Dice[1].MassBudget == startPurchased, string.format(
			"ROUND TRIP CHANGED THE BUDGET: started %s, ended %s (F-AD-1)",
			tostring(startPurchased), tostring(data.Dice[1].MassBudget)))
		e = e or check(data.Dice[1].PurchasedBudget == startPurchased,
			"a round trip must leave PurchasedBudget exactly as it was")

		-- A LARGE purchased budget must survive a trip through a small-capped
		-- shape: capped while there, restored on return. Capping is legitimate;
		-- confiscating is not (FR-6.1 calls the change reversible).
		PlayerProfile.mutate(player, function(d)
			d.Dice[1].PurchasedBudget = 800
			d.Dice[1].MassBudget = 300
			-- Unlock D4: a locked shape is refused, and a refused call would
			-- leave the die untouched and make the assertions below meaningless.
			d.Diamond.Shapes.D4 = true
			d.Inventory.D4 = 1
		end)
		local downOk = ForgeService.performSetShape(player, 1, "D4")
		e = e or check(downOk, "D6 -> D4 should succeed once D4 is unlocked")
		local d4 = DiceCatalog.getShape("D4")
		if d4 then
			e = e or check(data.Dice[1].MassBudget <= d4.diamondCeiling,
				"the usable budget must be capped by the shape's absolute ceiling")
			e = e or check(data.Dice[1].PurchasedBudget == 800,
				"a small-capped shape must CAP the usable budget, not destroy what was purchased")
		end
		ForgeService.performSetShape(player, 1, "D20")
		e = e or check(data.Dice[1].MassBudget == 800, string.format(
			"returning to a wide shape must restore the full purchased budget, got %s",
			tostring(data.Dice[1].MassBudget)))

		-- And the faces still sum to the stored budget, so the die stays forgeable.
		local sum2 = 0
		for _, f in ipairs(data.Dice[1].Faces) do
			sum2 += f.Mass
		end
		e = e or check(math.abs(sum2 - data.Dice[1].MassBudget) < ForgeMath.EPSILON,
			"faces must sum to the stored budget after a shape round trip")
	end

	----------------------------------------------------------------------------
	-- F-AD-4: the stored budget must never EXCEED what was purchased
	----------------------------------------------------------------------------

	-- Why this was missed the first time: every budget the earlier assertions
	-- used divided evenly by its face count (60/6, 60/20, 800/20, 800/4), so the
	-- rounding path was never entered. A test that only feeds clean numbers to a
	-- rounding bug reports success. These budgets are chosen NOT to divide.
	local awkward = { 70, 100, 130, 250, 333, 617 }
	local shapesToTry = { "D4", "D6", "D20" }

	PlayerProfile.mutate(player, function(d)
		d.Diamond.Shapes.D4 = true
		d.Diamond.Shapes.D6 = true
		d.Diamond.Shapes.D20 = true
		d.Inventory.D4 = 1
		d.Inventory.D6 = 1
		d.Inventory.D20 = 1
	end)
	EconomyService.credit(player, "Diamonds", 500, "test_setup")

	for _, budget in ipairs(awkward) do
		for _, shapeId in ipairs(shapesToTry) do
			local target = DiceCatalog.getShape(shapeId)
			if target and data.Dice[1].Shape ~= shapeId then
				PlayerProfile.mutate(player, function(d)
					d.Dice[1].PurchasedBudget = budget
				end)
				local okShape = ForgeService.performSetShape(player, 1, shapeId)
				if okShape then
					local stored = data.Dice[1].MassBudget
					-- diamondCeiling, not cashBudgetCap: FR-3.6 puts budget beyond the
					-- Cash cap behind Diamonds, so the Cash cap is not the die's limit.
					-- This assertion previously encoded the wrong ceiling and would have
					-- locked in the confiscation of Diamond-purchased budget.
					local cap = math.min(budget, target.diamondCeiling)
					e = e or check(stored <= cap, string.format(
						"budget %d on %s stored %s, which EXCEEDS what was purchased (F-AD-4)",
						budget, shapeId, tostring(stored)))

					-- The faces must still sum to exactly the stored budget, or the
					-- next forge proposal fails validation against a total the faces
					-- cannot reach.
					local faceSum = 0
					for _, f in ipairs(data.Dice[1].Faces) do
						faceSum += f.Mass
					end
					e = e or check(math.abs(faceSum - stored) < ForgeMath.EPSILON, string.format(
						"budget %d on %s: faces sum to %.6f but budget is %.6f",
						budget, shapeId, faceSum, stored))

					-- And every face still clears the floor.
					local floorHere = DiceCatalog.getMassFloor(shapeId)
					local allAbove = true
					for _, f in ipairs(data.Dice[1].Faces) do
						if f.Mass < floorHere then
							allAbove = false
						end
					end
					e = e or check(allAbove, string.format(
						"budget %d on %s put a face below the mass floor", budget, shapeId))

					-- PurchasedBudget itself is never touched by a shape change.
					e = e or check(data.Dice[1].PurchasedBudget == budget, string.format(
						"shape change altered PurchasedBudget: expected %d, got %s",
						budget, tostring(data.Dice[1].PurchasedBudget)))
				end
			end
		end
	end

	-- The direct arithmetic, stated once so the invariant is readable rather than
	-- only implied by the loop above: dividing a budget into equal shares must
	-- never produce shares that sum to more than the budget.
	for _, pair in ipairs({ { 70, 6 }, { 100, 6 }, { 130, 12 }, { 333, 7 }, { 617, 20 } }) do
		local budget, faces = pair[1], pair[2]
		local share = ForgeMath.snapDown(budget / faces)
		local total = ForgeMath.snap(share * faces)
		e = e or check(total <= budget, string.format(
			"%d split %d ways summed to %.6f, which exceeds the budget", budget, faces, total))
		e = e or check(budget - total < faces * (10 ^ -ForgeMath.PRECISION) + ForgeMath.EPSILON,
			string.format("%d split %d ways lost %.6f, more than rounding explains",
				budget, faces, budget - total))
	end

	-- snapDown must round toward zero on both signs, and reject non-finite input.
	e = e or check(ForgeMath.snapDown(1.99999) == 1.9999, "snapDown must truncate, not round up")
	e = e or check(ForgeMath.snapDown(2.0) == 2.0, "snapDown must leave an exact value alone")
	e = e or check(ForgeMath.snapDown(-1.99999) == -1.9999, "snapDown must round toward zero when negative")
	e = e or check(not (pcall(ForgeMath.snapDown, 0 / 0)), "snapDown must reject NaN")
	e = e or check(not (pcall(ForgeMath.snapDown, math.huge)), "snapDown must reject infinity")

	----------------------------------------------------------------------------
	-- THE DIE INVARIANT — asserted directly, then after every mutation
	----------------------------------------------------------------------------

	-- Written once in ForgeService.assertDieInvariant and checked from both
	-- sides. These cases prove each clause REJECTS, because an invariant that
	-- only ever returns true is decoration.
	local d6def = DiceCatalog.getShape("D6")
	if d6def then
		local function goodDie(): any
			local f: { any } = {}
			for i = 1, 6 do
				f[i] = { Mass = 10, Element = "None" }
			end
			return { Shape = "D6", MassBudget = 60, PurchasedBudget = 60, Faces = f }
		end

		local okBase = ForgeService.assertDieInvariant(goodDie(), d6def)
		e = e or check(okBase, "a well-formed starting die must satisfy the invariant")

		local function rejects(mutate: (any) -> (), expected: string, label: string)
			local d = goodDie()
			mutate(d)
			local ok, reason = ForgeService.assertDieInvariant(d, d6def)
			e = e or check(not ok, string.format("the invariant accepted %s", label))
			e = e or check(reason == expected, string.format(
				"%s should report '%s', got '%s'", label, expected, tostring(reason)))
		end

		rejects(function(d) d.Shape = "D20" end, "shape_mismatch", "a die claiming the wrong shape")
		rejects(function(d) table.remove(d.Faces) end, "face_count_mismatch", "a die with too few faces")
		rejects(function(d) d.PurchasedBudget = 0 end, "purchased_budget_invalid", "a zero purchased budget")
		rejects(function(d) d.PurchasedBudget = 0 / 0 end, "purchased_budget_invalid", "a NaN purchased budget")
		rejects(function(d) d.MassBudget = 0 / 0 end, "mass_budget_invalid", "a NaN mass budget")
		rejects(function(d)
			d.PurchasedBudget = 30
			d.MassBudget = 60
		end, "mass_budget_exceeds_purchased", "a budget above what was purchased")
		rejects(function(d)
			for i = 1, 6 do d.Faces[i].Mass = 0.5 end
			d.MassBudget = 3
		end, "mass_budget_below_viable", "a budget below the shape's viable minimum")
		rejects(function(d) d.Faces[1].Mass = 0 / 0 end, "face_mass_not_finite", "a NaN face")
		rejects(function(d)
			d.Faces[1].Mass = 0
			d.Faces[2].Mass = 20
		end, "face_below_floor", "a face below the mass floor")
		rejects(function(d) d.Faces[1].Element = "Plutonium" end, "face_element_unknown", "an unknown element")
		rejects(function(d) d.Faces[1].Mass = 11 end, "faces_do_not_sum_to_budget", "faces that overshoot the budget")
		rejects(function(d) d.Faces[1].Mass = 9 end, "faces_do_not_sum_to_budget", "faces that undershoot the budget")
	end

	-- And the live die must satisfy it after EVERY mutating operation, across
	-- every shape and both divisible and non-divisible budgets. This is the
	-- assertion whose absence let performSetShape be wrong three times.
	PlayerProfile.mutate(player, function(d)
		for _, id in ipairs({ "D4", "D6", "D8", "D12", "D20" }) do
			d.Diamond.Shapes[id] = true
			d.Inventory[id] = 1
		end
	end)
	EconomyService.credit(player, "Diamonds", 2000, "test_setup")
	EconomyService.credit(player, "Cash", 1e12, "test_setup")

	local sweepBudgets = { 40, 60, 70, 137, 250, 333, 900 }
	local sweepShapes = { "D4", "D6", "D8", "D12", "D20" }
	local sweepChecked = 0

	for _, budget in ipairs(sweepBudgets) do
		for _, shapeId in ipairs(sweepShapes) do
			if data.Dice[1].Shape ~= shapeId then
				PlayerProfile.mutate(player, function(d)
					d.Dice[1].PurchasedBudget = budget
				end)
				local changed = ForgeService.performSetShape(player, 1, shapeId)
				if changed then
					sweepChecked += 1
					local ok, reason = ForgeService.checkStoredDie(data.Dice[1])
					e = e or check(ok, string.format(
						"INVARIANT BROKEN after shape change to %s at purchased budget %d: %s",
						shapeId, budget, tostring(reason)))
				end
			end
		end
	end
	e = e or check(sweepChecked >= 20, string.format(
		"the shape sweep should have exercised many changes, only did %d", sweepChecked))

	-- A forge must leave the invariant intact too.
	PlayerProfile.mutate(player, function(d)
		local f: { any } = {}
		for i = 1, 6 do
			f[i] = { Mass = 10, Element = "None" }
		end
		d.Dice[1] = { Shape = "D6", MassBudget = 60, PurchasedBudget = 60, Faces = f }
	end)
	local forgeAfter = ForgeService.performForge(player, 1, { 30, 6, 6, 6, 6, 6 })
	e = e or check(forgeAfter, "the post-sweep forge should succeed")
	local okAfterForge, reasonAfterForge = ForgeService.checkStoredDie(data.Dice[1])
	e = e or check(okAfterForge, string.format(
		"INVARIANT BROKEN after a forge: %s", tostring(reasonAfterForge)))

	-- checkStoredDie must fail closed on rubbish rather than erroring.
	e = e or check(not (ForgeService.checkStoredDie(nil)), "checkStoredDie must refuse nil")
	e = e or check(not (ForgeService.checkStoredDie("cheese" :: any)), "checkStoredDie must refuse a non-table")
	e = e or check(not (ForgeService.checkStoredDie({ Shape = "D99" } :: any)),
		"checkStoredDie must refuse an unknown shape")

	----------------------------------------------------------------------------
	-- ROUND 3 FINDINGS: F-AD-5, F-AD-6, F-AD-7
	----------------------------------------------------------------------------

	local maxCeiling = DiceCatalog.maxDiamondCeiling()
	e = e or check(maxCeiling > 0, "the catalog must report a maximum diamond ceiling")
	for _, id in ipairs({ "D4", "D6", "D8", "D12", "D20" }) do
		local sd = DiceCatalog.getShape(id)
		if sd then
			e = e or check(sd.diamondCeiling <= maxCeiling, string.format(
				"%s's ceiling exceeds the reported maximum", id))
			e = e or check(sd.diamondCeiling >= sd.cashBudgetCap, string.format(
				"%s: the Diamond ceiling must be at or above the Cash cap (FR-3.6)", id))
		end
	end

	local d6r3 = DiceCatalog.getShape("D6")
	if d6r3 then
		local function dieAt(purchased: number, mass: number): any
			local f: { any } = {}
			for i = 1, 6 do
				f[i] = { Mass = mass / 6, Element = "None" }
			end
			return { Shape = "D6", MassBudget = mass, PurchasedBudget = purchased, Faces = f }
		end

		-- F-AD-5: an absurd PurchasedBudget used to pass every clause.
		local absurd = dieAt(1000000, 60)
		local okAbsurd, reasonAbsurd = ForgeService.assertDieInvariant(absurd, d6r3)
		e = e or check(not okAbsurd,
			"a PurchasedBudget of 1,000,000 must be rejected -- it is above every shape's ceiling (F-AD-5)")
		e = e or check(reasonAbsurd == "purchased_budget_exceeds_ceiling", string.format(
			"expected 'purchased_budget_exceeds_ceiling', got '%s'", tostring(reasonAbsurd)))

		-- Exactly at the maximum ceiling is legal; a hair above is not.
		local atMax = dieAt(maxCeiling, 60)
		e = e or check(ForgeService.assertDieInvariant(atMax, d6r3),
			"a PurchasedBudget exactly at the maximum ceiling must be accepted")
		local overMax = dieAt(maxCeiling + 1, 60)
		e = e or check(not (ForgeService.assertDieInvariant(overMax, d6r3)),
			"a PurchasedBudget one unit above the maximum ceiling must be rejected")

		-- FR-3.6: budget beyond the CASH cap is reachable with Diamonds, so the
		-- usable ceiling is diamondCeiling. Clamping at cashBudgetCap would have
		-- made the Diamond tier unreachable and confiscated what it bought.
		e = e or check(d6r3.diamondCeiling > d6r3.cashBudgetCap,
			"D6's Diamond ceiling should exceed its Cash cap, or the tier is pointless")
		local aboveCash = dieAt(d6r3.diamondCeiling, d6r3.diamondCeiling)
		local okAboveCash, reasonAboveCash = ForgeService.assertDieInvariant(aboveCash, d6r3)
		e = e or check(okAboveCash, string.format(
			"a budget above the CASH cap but within the Diamond ceiling must be legal "
			.. "(FR-3.6), got '%s'", tostring(reasonAboveCash)))

		-- F-AD-7: malformed input must RETURN false, never throw. A caller that
		-- gets an exception where it expected a verdict cannot fail closed.
		local function survives(label: string, d: any): ()
			local callOk, res = pcall(ForgeService.assertDieInvariant, d, d6r3)
			e = e or check(callOk, string.format("assertDieInvariant THREW on %s instead of returning false", label))
			if callOk then
				e = e or check(res == false, string.format("assertDieInvariant accepted %s", label))
			end
		end

		survives("nil", nil)
		survives("a string", "cheese")
		survives("a number", 42)
		survives("a die with no Faces", { Shape = "D6", MassBudget = 60, PurchasedBudget = 60 })
		survives("a die whose Faces is a string", { Shape = "D6", MassBudget = 60, PurchasedBudget = 60, Faces = "no" })
		survives("a SPARSE Faces array", {
			Shape = "D6", MassBudget = 60, PurchasedBudget = 60,
			Faces = { [1] = { Mass = 10, Element = "None" }, [6] = { Mass = 10, Element = "None" } },
		})
		survives("a Faces array holding a non-table", {
			Shape = "D6", MassBudget = 60, PurchasedBudget = 60,
			Faces = { 1, 2, 3, 4, 5, 6 },
		})
		survives("a die with no Shape", { MassBudget = 60, PurchasedBudget = 60, Faces = {} })

		-- checkStoredDie wraps the same guarantees for arbitrary stored data.
		local storedOk = pcall(ForgeService.checkStoredDie, {
			Shape = "D6", MassBudget = 60, PurchasedBudget = 60, Faces = nil,
		} :: any)
		e = e or check(storedOk, "checkStoredDie THREW on a die with no Faces")
	end

	-- F-AD-6: performSetElement now passes the gate like every other write to
	-- d.Dice. Prove it still succeeds on a valid die, and that the die remains
	-- invariant-clean afterwards.
	PlayerProfile.mutate(player, function(d)
		local f: { any } = {}
		for i = 1, 6 do
			f[i] = { Mass = 10, Element = "None" }
		end
		d.Dice[1] = { Shape = "D6", MassBudget = 60, PurchasedBudget = 60, Faces = f }
		d.Diamond.Elements.Fire = true
	end)
	EconomyService.credit(player, "Cash", 100000, "test_setup")
	local elOk, elReason = ForgeService.performSetElement(player, 1, 2, "Fire")
	e = e or check(elOk, string.format(
		"a valid element assignment must still succeed through the gate, got '%s'", tostring(elReason)))
	e = e or check(data.Dice[1].Faces[2].Element == "Fire", "the element was not stored")
	local afterEl, afterElReason = ForgeService.checkStoredDie(data.Dice[1])
	e = e or check(afterEl, string.format(
		"INVARIANT BROKEN after an element assignment: %s", tostring(afterElReason)))

	-- And a die already corrupted must have the element write REFUSED rather
	-- than persisting a second wrong on top of the first.
	PlayerProfile.mutate(player, function(d)
		d.Dice[1].MassBudget = 99999
	end)
	local corruptEl = ForgeService.performSetElement(player, 1, 3, "Fire")
	e = e or check(not corruptEl,
		"an element write onto an already-invalid die must be refused by the gate (F-AD-6)")
	PlayerProfile.mutate(player, function(d)
		d.Dice[1].MassBudget = 60
	end)

	----------------------------------------------------------------------------
	-- F-SELF-1: the invariant must guard the LOAD path, not only writes
	----------------------------------------------------------------------------

	-- Guarding every write is worth nothing if reads are trusted. `_reconcile`
	-- and `_migrate` both write `data.Dice` without the gate, so a die that was
	-- already illegal in storage used to load cleanly and then be honoured --
	-- performForge validates a proposal against die.MassBudget, so a stored
	-- 99999 was simply believed. Four defects in this block WROTE invalid dice.

	local function storeIllegal(mutateDie: (any) -> ())
		PlayerProfile.mutate(player, function(d)
			local f: { any } = {}
			for i = 1, 6 do
				f[i] = { Mass = 10, Element = "None" }
			end
			d.Dice[1] = { Shape = "D6", MassBudget = 60, PurchasedBudget = 60, Faces = f }
			mutateDie(d.Dice[1])
		end)
	end

	-- An inflated budget -- exactly what F-AD-1 and F-AD-4 used to write.
	storeIllegal(function(die) die.MassBudget = 99999 end)
	e = e or check(not (ForgeService.checkStoredDie(data.Dice[1])),
		"a die with an inflated budget must be recognised as illegal")
	local n1 = ForgeService.validateStoredDice(player)
	e = e or check(n1 == 1, string.format("expected 1 repair, got %d", n1))
	local ok1, reason1 = ForgeService.checkStoredDie(data.Dice[1])
	e = e or check(ok1, string.format("the repaired die is still illegal: %s", tostring(reason1)))
	e = e or check(data.Dice[1].MassBudget <= data.Dice[1].PurchasedBudget,
		"repair must not leave the budget above what was purchased")

	-- A purchased budget above every shape's ceiling.
	storeIllegal(function(die) die.PurchasedBudget = 500000 end)
	e = e or check(ForgeService.validateStoredDice(player) == 1, "an over-ceiling entitlement must be repaired")
	e = e or check(data.Dice[1].PurchasedBudget <= DiceCatalog.maxDiamondCeiling(),
		"repair must clamp PurchasedBudget to the global ceiling")
	e = e or check(ForgeService.checkStoredDie(data.Dice[1]), "the repaired die must satisfy the invariant")

	-- Faces that do not sum to the budget.
	storeIllegal(function(die) die.Faces[1].Mass = 40 end)
	e = e or check(ForgeService.validateStoredDice(player) == 1, "a non-summing die must be repaired")
	local sumRepaired = 0
	for _, f in ipairs(data.Dice[1].Faces) do
		sumRepaired += f.Mass
	end
	e = e or check(math.abs(sumRepaired - data.Dice[1].MassBudget) < ForgeMath.EPSILON,
		"the repaired faces must sum to the repaired budget")

	-- A face below the floor, and an unknown element, repaired together.
	storeIllegal(function(die)
		die.Faces[1].Mass = 0
		die.Faces[2].Element = "Plutonium"
	end)
	e = e or check(ForgeService.validateStoredDice(player) == 1, "a floor/element violation must be repaired")
	e = e or check(ForgeService.checkStoredDie(data.Dice[1]), "the repaired die must satisfy the invariant")
	local keptKnown = true
	for _, f in ipairs(data.Dice[1].Faces) do
		if not ElementCatalog.exists(f.Element) then
			keptKnown = false
		end
	end
	e = e or check(keptKnown, "repair must replace an unknown element, not preserve it")

	-- REPAIR MUST NEVER BE A REWARD. Starting from an inflated die, the repaired
	-- budget must not exceed what a legitimate die of that shape could hold.
	storeIllegal(function(die)
		die.MassBudget = 99999
		die.PurchasedBudget = 99999
	end)
	ForgeService.validateStoredDice(player)
	local d6cap = DiceCatalog.getShape("D6")
	if d6cap then
		e = e or check(data.Dice[1].MassBudget <= d6cap.diamondCeiling,
			"repairing an inflated die must not leave it above the shape ceiling")
	end

	-- A LEGAL die must be left completely alone: repair is not a reset.
	PlayerProfile.mutate(player, function(d)
		local f: { any } = {}
		for i = 1, 6 do
			f[i] = { Mass = 10, Element = "None" }
		end
		f[1].Mass = 30
		f[2].Mass = 6
		f[3].Mass = 6
		f[4].Mass = 6
		f[5].Mass = 6
		f[6].Mass = 6
		d.Dice[1] = { Shape = "D6", MassBudget = 60, PurchasedBudget = 60, Faces = f }
	end)
	e = e or check(ForgeService.checkStoredDie(data.Dice[1]), "the hand-built die should be legal")
	e = e or check(ForgeService.validateStoredDice(player) == 0,
		"a LEGAL die must not be repaired -- repair is not a reset")
	e = e or check(data.Dice[1].Faces[1].Mass == 30,
		"a legal forged layout must survive the load-time check untouched")

	----------------------------------------------------------------------------
	-- CATALOG PRECONDITIONS the repair path silently depends on
	----------------------------------------------------------------------------

	-- The round-5 delta audit called repairDie's output "mathematically
	-- guaranteed" to satisfy the invariant. It is -- GIVEN the catalog. The
	-- guarantee rests on two unstated preconditions, and `DiceCatalog` says in
	-- its own header that every constant in it is provisional until the P-6B
	-- balance sweep. If that sweep breaks one of these, `math.clamp(x, min, max)`
	-- with min > max ERRORS, inside the join path, and the failure mode is a
	-- player who is never admitted and never kicked.
	--
	-- Asserted here rather than guarded in the production path on purpose: the
	-- production code was audited clean at 778b493, and encoding the assumption
	-- in the suite makes P-6B fail loudly at the bench instead of quietly at
	-- someone's join.
	for _, id in ipairs({ "D4", "D6", "D8", "D12", "D20" }) do
		local sd = DiceCatalog.getShape(id)
		if sd then
			local minViable = sd.massFloor * sd.faceCount
			e = e or check(minViable <= sd.diamondCeiling, string.format(
				"%s: minViable (%s) exceeds diamondCeiling (%s) -- math.clamp would ERROR "
				.. "inside the join path", id, tostring(minViable), tostring(sd.diamondCeiling)))
			e = e or check(minViable <= DiceCatalog.maxDiamondCeiling(), string.format(
				"%s: minViable exceeds the global ceiling -- repair could not produce a legal die", id))
			e = e or check(sd.defaultBudget >= minViable, string.format(
				"%s: defaultBudget (%s) is below minViable (%s) -- a fresh die would be born illegal",
				id, tostring(sd.defaultBudget), tostring(minViable)))
			e = e or check(sd.defaultBudget <= sd.diamondCeiling, string.format(
				"%s: defaultBudget exceeds the shape's own ceiling", id))
			e = e or check(sd.massFloor > 0, string.format("%s: massFloor must be positive", id))
			e = e or check(sd.faceCount > 1, string.format(
				"%s: a die needs at least 2 faces, or landing probability is undefined", id))
		end
	end

	ForgeService._setResultEmitterForTesting(nil)
	PlayerProfile.release(player)

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-12 ForgeService", run = run }
