--!strict
-- ForgeService.luau
-- Closed-system mass redistribution, element assignment, and shape changes.
--
-- HLD §3 C-1, SRS FR-3.2, FR-3.3, FR-4.1, FR-6.1.
-- Forging moves mass between faces within a fixed budget; it never creates mass.
-- Costs scale with magnitude of mass moved -- free re-forging is a correctness
-- defect (ledger L-016). Any violation rejects the whole proposal atomically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local PurchaseService = require(script.Parent:WaitForChild("PurchaseService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local RemoteGateway = require(script.Parent:WaitForChild("RemoteGateway"))

local ForgeService = {}

local BASE_COST_PER_MASS_UNIT = 5.0
-- The starting D6 budget. A die at this budget pays exactly BASE per mass unit;
-- everything above it pays more. Tuning surface for P-6B.
local REFERENCE_BUDGET = 60.0
local SCALE_EXPONENT = 2.0
local ELEMENT_SET_COST = 50.0
-- Read from the shared catalog, not restated here. The client has to render this
-- price on the USE button and the server has to charge it; two copies of one
-- number is how a button ends up quoting a cost the server does not take.
local SHAPE_CHANGE_DIAMOND_COST = DiceCatalog.SHAPE_CHANGE_DIAMOND_COST

ForgeService.BASE_COST_PER_MASS_UNIT = BASE_COST_PER_MASS_UNIT
ForgeService.REFERENCE_BUDGET = REFERENCE_BUDGET
ForgeService.SCALE_EXPONENT = SCALE_EXPONENT
ForgeService.ELEMENT_SET_COST = ELEMENT_SET_COST
ForgeService.SHAPE_CHANGE_DIAMOND_COST = SHAPE_CHANGE_DIAMOND_COST

--------------------------------------------------------------------------------
-- Result-emission seam. Same rationale as RollService's: the unit suite drives
-- these handlers with a fake player, and the alternative to an injected emitter
-- is typeof-guards and a swallowing pcall in the production path. STUDIO-ONLY.
--------------------------------------------------------------------------------

local function defaultEmit(player: Player, payload: any): ()
	Remotes.getEvent("ForgeResult"):FireClient(player, payload)
end

local emitForgeResult: (Player, any) -> () = defaultEmit

-- Notified after every SUCCESSFUL forge. Set by ServerBootstrap so quests can
-- observe forging without this module depending on ProgressionService -- the
-- forge should not know what watches it, and the indirection keeps the module
-- graph acyclic (ledger L-035).
local forgeObserver: ((Player) -> ())? = nil

function ForgeService.setForgeObserver(fn: ((Player) -> ())?): ()
	forgeObserver = fn
end

function ForgeService._setResultEmitterForTesting(fn: ((Player, any) -> ())?): ()
	if not RunService:IsStudio() then
		error("[ForgeService] the result-emitter seam is Studio-only", 2)
	end
	emitForgeResult = fn or defaultEmit
end

--------------------------------------------------------------------------------
-- THE DIE INVARIANT — written down ONCE, executable, enforced from both sides.
--
-- This function exists because `performSetShape` was wrong three times running,
-- in three different directions: it confiscated the purchased budget, then
-- manufactured budget on a shape toggle (F-AD-1), then inflated the stored
-- budget by a rounding residue (F-AD-4). Three fixes, three new defects.
--
-- The root cause was never the arithmetic. It was that the rules a die must
-- satisfy lived as prose scattered across SRS FR-3.6, FR-6.1 and a comment, so
-- every fix re-derived them from memory and silently broke a clause nobody had
-- written down. The tests had the same gap: each asserted the symptom last
-- reported, never the whole contract.
--
-- So the contract is stated here, in one place, as the single definition. The
-- mutating handlers check a CANDIDATE die against it before persisting, and
-- UT-12 checks the stored die against it after every mutation. "Did we break a
-- clause this time?" stops being a question the next auditor has to re-derive
-- and becomes one the suite answers on every run.
--
-- Adding a clause here is how a future rule gets enforced. Do not restate one
-- inline in a handler.
--------------------------------------------------------------------------------

export type CandidateDie = {
	Shape: string,
	MassBudget: number,
	PurchasedBudget: number,
	Faces: { PlayerProfile.Face },
	[string]: any,
}

function ForgeService.assertDieInvariant(die: CandidateDie, shape: DiceCatalog.ShapeDef): (boolean, string?)
	-- 0. Shape of the ARGUMENT before any clause about its contents. This
	--    function is called on stored data of unknown provenance, so it must
	--    RETURN false, never throw: `#die.Faces` on a nil errors, and a caller
	--    that gets an exception where it expected a verdict cannot fail closed.
	--    (F-AD-7.)
	if type(die) ~= "table" then
		return false, "die_not_a_table"
	end
	if type(die.Faces) ~= "table" then
		return false, "faces_not_a_table"
	end

	if die.Shape ~= shape.id then
		return false, "shape_mismatch"
	end
	if #die.Faces ~= shape.faceCount then
		return false, "face_count_mismatch"
	end

	-- 1. Every slot up to the face count actually holds a face table. `#` on a
	--    SPARSE array is undefined in Lua -- {[1]=a,[3]=b} may report 1 or 3 --
	--    so the length check above can pass while a slot is nil, and the loop
	--    below would then index nil. Verified here rather than assumed.
	for i = 1, shape.faceCount do
		if type(die.Faces[i]) ~= "table" then
			return false, "face_missing_or_not_a_table"
		end
	end

	-- 2. Purchased budget is a real, positive quantity. It is what the player
	--    owns (FR-3.6) and every other clause is measured against it.
	if not ForgeMath.isFinite(die.PurchasedBudget) or die.PurchasedBudget <= 0 then
		return false, "purchased_budget_invalid"
	end
	-- ...and BOUNDED ABOVE. Without this the invariant answered "is this die
	-- valid?" with no opinion on the one field the whole design rests on: a die
	-- carrying a PurchasedBudget of a million passed every clause, and a
	-- corrupted or hand-edited profile would have kept that entitlement forever
	-- (F-AD-5). The bound is the maximum ceiling across ALL shapes, because
	-- PurchasedBudget is shape-independent -- a player who bought up to D20's
	-- ceiling still owns it while standing on a D4.
	if die.PurchasedBudget > DiceCatalog.maxDiamondCeiling() + ForgeMath.EPSILON then
		return false, "purchased_budget_exceeds_ceiling"
	end

	-- 3. The usable budget sits inside the shape's legal range and NEVER above
	--    what was purchased. The upper bound is the whole of F-AD-1: a shape
	--    change may cap what is usable, never mint more.
	if not ForgeMath.isFinite(die.MassBudget) then
		return false, "mass_budget_invalid"
	end
	local minViable = shape.massFloor * shape.faceCount
	-- `diamondCeiling`, NOT `cashBudgetCap`. FR-3.6: "Mass budget increases are
	-- purchased with Cash up to a per-shape cap, AND BEYOND THAT WITH PRESTIGE
	-- DIAMONDS." cashBudgetCap is where the Cash path stops, not where the die
	-- stops. Clamping the usable budget at cashBudgetCap made the entire Diamond
	-- budget tier unreachable and would have silently confiscated any budget
	-- bought with Diamonds -- a fourth direction of wrongness in this same
	-- function, surfaced by asking whether the invariant was complete (F-AD-5).
	local ceiling = math.min(die.PurchasedBudget, shape.diamondCeiling)
	if die.MassBudget < minViable - ForgeMath.EPSILON then
		return false, "mass_budget_below_viable"
	end
	if die.MassBudget > ceiling + ForgeMath.EPSILON then
		return false, "mass_budget_exceeds_purchased"
	end

	-- 4. Every face is finite, at or above the floor, and carries a known
	--    element. Finiteness first: NaN fails every comparison silently (T-25).
	for i = 1, #die.Faces do
		local face = die.Faces[i]
		if not ForgeMath.isFinite(face.Mass) then
			return false, "face_mass_not_finite"
		end
		if face.Mass < shape.massFloor - ForgeMath.EPSILON then
			return false, "face_below_floor"
		end
		if type(face.Element) ~= "string" or not ElementCatalog.exists(face.Element) then
			return false, "face_element_unknown"
		end
	end

	-- 5. Zero-sum: the faces account for the budget exactly. Checked LAST so a
	--    non-finite face is reported as such rather than as a sum failure.
	local sum = 0.0
	for i = 1, #die.Faces do
		sum += die.Faces[i].Mass
	end
	if math.abs(sum - die.MassBudget) > ForgeMath.EPSILON then
		return false, "faces_do_not_sum_to_budget"
	end

	return true, nil
end

-- Convenience for callers holding a stored die whose shape must be looked up.
-- Bring an illegal die back inside the contract, in place.
--
-- WHY REPAIR RATHER THAN QUARANTINE. A die can be illegal through no fault of
-- the player -- four defects in this block WROTE invalid dice before they were
-- caught, and any profile touched by that code still carries the result.
-- Refusing the load would kick a player over data our own bugs produced.
-- Repairing clamps them back to what the contract allows, which can only ever
-- reduce an illegal advantage, never grant one.
--
-- Deliberately NOT clever: it does not try to preserve a layout that was
-- illegal. It keeps what is defensible -- the shape, the elements, and the
-- purchased entitlement clamped into range -- and redistributes mass evenly,
-- which is the same neutral result a shape change produces.
local function repairDie(die: any, shape: DiceCatalog.ShapeDef): CandidateDie
	local maxCeiling = DiceCatalog.maxDiamondCeiling()

	local purchased = if type(die) == "table" then die.PurchasedBudget else nil
	if not ForgeMath.isFinite(purchased) or (purchased :: number) <= 0 then
		purchased = if type(die) == "table" and ForgeMath.isFinite(die.MassBudget)
			then die.MassBudget
			else shape.defaultBudget
	end
	local minViable = shape.massFloor * shape.faceCount
	purchased = math.clamp(purchased :: number, minViable, maxCeiling)

	local budget = math.clamp(purchased :: number, minViable, shape.diamondCeiling)
	local faceMass = ForgeMath.snapDown(budget / shape.faceCount)
	if faceMass < shape.massFloor then
		faceMass = shape.massFloor
	end
	local exact = ForgeMath.snap(faceMass * shape.faceCount)

	local faces: { PlayerProfile.Face } = {}
	local priorFaces = if type(die) == "table" and type(die.Faces) == "table" then die.Faces else {}
	for i = 1, shape.faceCount do
		local prior = priorFaces[i]
		local element = "None"
		if type(prior) == "table" and type(prior.Element) == "string"
			and ElementCatalog.exists(prior.Element) then
			element = prior.Element
		end
		faces[i] = { Mass = faceMass, Element = element }
	end

	local result: any = {
		Shape = shape.id,
		MassBudget = exact,
		PurchasedBudget = purchased :: number,
		Faces = faces,
	}
	if type(die) == "table" then
		for k, v in pairs(die) do
			if result[k] == nil then
				result[k] = v
			end
		end
	end

	return result
end

-- Validate every stored die at LOAD and repair any that breaks the contract.
--
-- THE GAP THIS CLOSES. The invariant gated every WRITE and nothing on READ.
-- `PlayerProfile._reconcile` and `_migrate` both write `data.Dice` directly, and
-- neither passes the gate, so a die that was already illegal in storage loaded
-- cleanly and was then honoured -- `performForge` validates a proposal against
-- `die.MassBudget`, so a stored 99999 is simply believed.
--
-- Found by carrying the round-4 brief's own question one step further: the
-- invariant was complete as a STATEMENT and incomplete as an ENFORCEMENT
-- SURFACE. Guarding writes is worth nothing if reads are trusted.
--
-- Returns the number of dice repaired, so the caller can log a real number
-- rather than a boolean.
function ForgeService.validateStoredDice(player: Player): number
	local data = PlayerProfile.get(player)
	if not data or type(data.Dice) ~= "table" then
		return 0
	end

	local repairs: { { index: number, die: CandidateDie, reason: string } } = {}
	for i = 1, #data.Dice do
		local ok, reason = ForgeService.checkStoredDie(data.Dice[i])
		if not ok then
			local stored = data.Dice[i]
			local shape = if type(stored) == "table" then DiceCatalog.getShape(stored.Shape) else nil
			-- An unrecognisable shape falls back to the starting shape rather
			-- than deleting the die: losing a die is worse than resetting one.
			local target = shape or DiceCatalog.getShape("D6")
			if target then
				table.insert(repairs, {
					index = i,
					die = repairDie(stored, target),
					reason = tostring(reason),
				})
			end
		end
	end

	if #repairs == 0 then
		return 0
	end

	local applied = PlayerProfile.mutate(player, function(d)
		for _, r in ipairs(repairs) do
			d.Dice[r.index] = r.die
		end
	end)
	if not applied then
		return 0
	end

	for _, r in ipairs(repairs) do
		warn(string.format(
			"[ForgeService] repaired an illegal stored die for UserId=%d: die %d violated '%s'"
			.. " -- reset to %s budget %s",
			player.UserId, r.index, r.reason, r.die.Shape, tostring(r.die.MassBudget)))
	end
	return #repairs
end

function ForgeService.checkStoredDie(die: any): (boolean, string?)
	if type(die) ~= "table" then
		return false, "die_not_a_table"
	end
	local shape = DiceCatalog.getShape(die.Shape)
	if not shape then
		return false, "unknown_shape"
	end
	return ForgeService.assertDieInvariant(die :: CandidateDie, shape)
end

--------------------------------------------------------------------------------
-- PURE: cost calculation
--------------------------------------------------------------------------------

-- F-AD-2, Block 3 Gate 3 audit. The cost was a flat 5 Cash per mass unit moved.
-- That satisfies FR-3.3's letter ("scales with the magnitude of mass moved") and
-- fails its purpose: at a late-game balance, moving 100 mass costs 500 Cash
-- against a per-roll payout in the millions, so re-forging becomes free in every
-- sense that matters. Free re-forging collapses the cross-die puzzle to a solved
-- symmetric state -- a CORRECTNESS failure, not a tuning miss (ledger L-016).
--
-- The cost therefore scales on two independent axes:
--   * MASS MOVED, linearly -- the FR-3.3 requirement, unchanged.
--   * PROGRESSION, superlinearly in the die's own budget -- a die with more mass
--     invested in it is a bigger machine to re-tune. Budget is used rather than
--     the player's Cash balance deliberately: pricing off a balance punishes
--     saving and can be gamed by spending down before forging, while budget is
--     server-held, monotonic, and the thing actually being re-tuned.
--
-- SCALE_EXPONENT and BASE are the tuning surface; the STRUCTURE is what closes
-- the finding. Real numbers come from the P-6B balance sweep, which is the only
-- place a claim about late-game triviality can actually be settled.
function ForgeService.computeForgeCost(oldDist: { number }, newDist: { number }, budget: number?, player: Player?): number
	-- DELEGATES to the shared implementation. The formula used to live here, in
	-- a server-only module, which meant the forge UI could not quote a price
	-- without reimplementing it -- and a quoted price that drifts from the
	-- actual charge is the worst possible version of ledger L-026.
	--
	-- The pure maths is shared; the ENTITLEMENT DISCOUNT stays here, because
	-- pass ownership is server state and no client may compute it.
	local cost = ForgeMath.forgeCost(oldDist, newDist, budget)
	if not ForgeMath.isFinite(cost) then
		return math.huge
	end
	if player ~= nil then
		cost = ForgeMath.snap(cost * PurchaseService.forgeCostMultiplier(player))
	end
	if not ForgeMath.isFinite(cost) then
		return math.huge
	end
	return cost
end

--------------------------------------------------------------------------------
-- Handlers
--------------------------------------------------------------------------------

function ForgeService.performForge(player: Player, dieIndex: number, distribution: { number }): (boolean, string?)
	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end

	local v = RemoteGateway.validate
	local okIdx, rIdx = v.integerInRange(dieIndex, 1, #data.Dice)
	if not okIdx then
		return false, rIdx
	end

	local die = data.Dice[dieIndex]
	local shape = DiceCatalog.getShape(die.Shape)
	local expectedFaces = if shape then shape.faceCount else #die.Faces
	local floor = if shape then shape.massFloor else DiceCatalog.DEFAULT_MASS_FLOOR

	local okArr, rArr = v.numberArray(distribution, expectedFaces)
	if not okArr then
		return false, rArr
	end

	if #distribution ~= expectedFaces then
		return false, Remotes.Notice.InvalidRequest
	end

	-- Finiteness checked BEFORE sum inside ForgeMath.validate (threat T-25)
	local valid, reason = ForgeMath.validate(distribution, expectedFaces, die.MassBudget, floor)
	if not valid then
		return false, reason or Remotes.Notice.InvalidRequest
	end

	local oldDist: { number } = table.create(#die.Faces, 0)
	for i = 1, #die.Faces do
		oldDist[i] = die.Faces[i].Mass
	end

	-- THE INVARIANT GATE. Build the die this call would produce and check it
	-- against the single definition BEFORE any money moves. Checking the
	-- candidate rather than the stored result means a violation is a refusal,
	-- not a refund of a write that already happened.
	if shape then
		local candidateFaces: { PlayerProfile.Face } = {}
		for i = 1, #die.Faces do
			candidateFaces[i] = {
				Mass = ForgeMath.snap(distribution[i]),
				Element = die.Faces[i].Element,
			}
		end
		local invOk, invReason = ForgeService.assertDieInvariant({
			Shape = die.Shape,
			MassBudget = die.MassBudget,
			PurchasedBudget = die.PurchasedBudget,
			Faces = candidateFaces,
		}, shape)
		if not invOk then
			warn(string.format("[ForgeService] forge refused by the die invariant for UserId=%d: %s",
				player.UserId, tostring(invReason)))
			return false, Remotes.Notice.InvalidRequest
		end
	end

	local cost = ForgeService.computeForgeCost(oldDist, distribution, die.MassBudget, player)
	if not EconomyService.canAfford(player, "Cash", cost) then
		return false, Remotes.Notice.InsufficientFunds
	end

	local spent, spendReason = EconomyService.spend(player, "Cash", cost, "forge")
	if not spent then
		return false, spendReason
	end

	-- The mutate result is CHECKED. Cash has already left the player's balance;
	-- if the write is refused (released profile, threat T-26) the mass must not
	-- silently fail to apply, or the player has paid for nothing. There is no
	-- yield between the spend and this call, so a refusal here means the session
	-- ended mid-transaction -- refund and report.
	local applied, applyReason = PlayerProfile.mutate(player, function(d)
		local targetDie = d.Dice[dieIndex]
		for i = 1, #distribution do
			targetDie.Faces[i].Mass = ForgeMath.snap(distribution[i])
		end
	end)
	if not applied then
		EconomyService.credit(player, "Cash", cost, "forge_refund")
		warn(string.format("[ForgeService] forge write refused for UserId=%d: %s",
			player.UserId, tostring(applyReason)))
		return false, Remotes.Notice.ProfileUnavailable
	end

	emitForgeResult(player, {
		dieIndex = dieIndex,
		distribution = distribution,
		cost = cost,
		ok = true,
	})

	-- Wrapped: an observer defect must not fail a forge whose mass and Cash have
	-- already moved.
	local observe = forgeObserver
	if observe ~= nil then
		local okObs, obsErr = pcall(observe, player)
		if not okObs then
			warn("[ForgeService] forge observer failed: " .. tostring(obsErr))
		end
	end

	return true, nil
end

function ForgeService.performSetElement(player: Player, dieIndex: number, faceIndex: number, elementId: string): (boolean, string?)
	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end

	local v = RemoteGateway.validate
	local okIdx, rIdx = v.integerInRange(dieIndex, 1, #data.Dice)
	if not okIdx then
		return false, rIdx
	end

	local die = data.Dice[dieIndex]
	local okFace, rFace = v.integerInRange(faceIndex, 1, #die.Faces)
	if not okFace then
		return false, rFace
	end

	-- Allowlist check against the static catalog (threat T-5). The accessor is
	-- `exists`; there is no `getElement`.
	if type(elementId) ~= "string" or not ElementCatalog.exists(elementId) then
		return false, Remotes.Notice.InvalidRequest
	end

	-- Verify element is unlocked in player profile
	if not data.Diamond.Elements[elementId] then
		return false, Remotes.Notice.InvalidRequest
	end

	-- Prevent charging Cash for a no-op if the face already has this element
	if die.Faces[faceIndex].Element == elementId then
		return false, Remotes.Notice.InvalidRequest
	end

	if not EconomyService.canAfford(player, "Cash", ELEMENT_SET_COST) then
		return false, Remotes.Notice.InsufficientFunds
	end

	-- THE INVARIANT GATE. This handler only writes `Element`, so no mass clause
	-- can move -- but the ELEMENT clause can, and more to the point the rule is
	-- "every write to d.Dice passes the gate". A rule with one documented
	-- exception is a rule the next author will add a second exception to
	-- (F-AD-6). It also catches a die that was already invalid before this call.
	local elementShape = DiceCatalog.getShape(die.Shape)
	if elementShape then
		local candidateFaces: { PlayerProfile.Face } = {}
		for i = 1, #die.Faces do
			candidateFaces[i] = {
				Mass = die.Faces[i].Mass,
				Element = if i == faceIndex then elementId else die.Faces[i].Element,
			}
		end
		local invOk, invReason = ForgeService.assertDieInvariant({
			Shape = die.Shape,
			MassBudget = die.MassBudget,
			PurchasedBudget = die.PurchasedBudget,
			Faces = candidateFaces,
		}, elementShape)
		if not invOk then
			warn(string.format("[ForgeService] element write refused by the die invariant for UserId=%d: %s",
				player.UserId, tostring(invReason)))
			return false, Remotes.Notice.InvalidRequest
		end
	end

	local spent, spendReason = EconomyService.spend(player, "Cash", ELEMENT_SET_COST, "set_element")
	if not spent then
		return false, spendReason
	end

	local applied, applyReason = PlayerProfile.mutate(player, function(d)
		d.Dice[dieIndex].Faces[faceIndex].Element = elementId
	end)
	if not applied then
		EconomyService.credit(player, "Cash", ELEMENT_SET_COST, "set_element_refund")
		warn(string.format("[ForgeService] element write refused for UserId=%d: %s",
			player.UserId, tostring(applyReason)))
		return false, Remotes.Notice.ProfileUnavailable
	end

	return true, nil
end

function ForgeService.performSetShape(player: Player, dieIndex: number, shapeId: string): (boolean, string?)
	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end

	local v = RemoteGateway.validate
	local maxAllowedIndex = math.min(data.DieSlots, #data.Dice + 1)
	local okIdx, rIdx = v.integerInRange(dieIndex, 1, maxAllowedIndex)
	if not okIdx then
		return false, rIdx
	end

	local shape = DiceCatalog.getShape(shapeId)
	if not shape then
		return false, Remotes.Notice.InvalidRequest
	end

	if not data.Diamond.Shapes[shapeId] then
		return false, Remotes.Notice.InvalidRequest
	end

	-- Quota check: player must own enough purchased instances of shapeId
	local ownedCount = if type(data.Inventory) == "table" then (tonumber(data.Inventory[shapeId]) or 0) else 0
	local inUseCount = 0
	for i, d in ipairs(data.Dice) do
		if i ~= dieIndex and type(d) == "table" and d.Shape == shapeId then
			inUseCount += 1
		end
	end
	if inUseCount + 1 > ownedCount then
		return false, Remotes.Notice.InsufficientFunds
	end

	-- If equipping to the next empty unlocked slot
	if dieIndex == #data.Dice + 1 then
		local newDie = DiceCatalog.newDie(shapeId)
		if not newDie then
			return false, Remotes.Notice.ServerError
		end
		local applied, applyReason = PlayerProfile.mutate(player, function(d)
			table.insert(d.Dice, newDie)
			d.Diamond.ShapesEquipped[shapeId] = true
		end)
		if not applied then
			return false, Remotes.Notice.ProfileUnavailable
		end
		return true, nil
	end

	-- Changing to the shape already equipped is a no-op, and a no-op must never
	-- cost Diamonds.
	if data.Dice[dieIndex].Shape == shapeId then
		return false, Remotes.Notice.InvalidRequest
	end

	-- SRS FR-6.1: a shape change is "freely reversible". It therefore must NOT
	-- confiscate purchased progression. The mass BUDGET the player bought with
	-- Cash and Diamonds (FR-3.6) carries across, clamped into the new shape's
	-- legal range, and per-face ELEMENTS carry across for as many faces as the
	-- new shape has. Only the mass LAYOUT resets -- it cannot be preserved
	-- across a change in face count, and the even split is the neutral result.
	local oldDie = data.Dice[dieIndex]

	-- F-AD-1, Block 3 Gate 3 audit. The previous line clamped the carried budget
	-- up to `shape.defaultBudget`, which MANUFACTURED budget on a shape change:
	-- D6@60 -> D20 clamped to 200, and switching back to D6 clamped to
	-- max(200, 60) = 200. Ten Diamonds bought a permanent 60 -> 200 budget rise
	-- that FR-3.6 says must be purchased with Cash. That was my own regression,
	-- introduced in this block while fixing the opposite defect (confiscation).
	--
	-- The budget is now DERIVED, never carried: PurchasedBudget is the shape-
	-- independent thing the player owns, and MassBudget is that value clamped
	-- into this shape's legal range. The lower bound is the smallest budget the
	-- shape can physically hold (every face at its floor) -- NOT defaultBudget,
	-- which is a starting value and has no business acting as a floor.
	local purchased = oldDie.PurchasedBudget
	if not ForgeMath.isFinite(purchased) or purchased <= 0 then
		purchased = if ForgeMath.isFinite(oldDie.MassBudget) then oldDie.MassBudget else shape.defaultBudget
	end
	local minViable = shape.massFloor * shape.faceCount
	-- diamondCeiling, not cashBudgetCap -- see the invariant's clause 3. The
	-- Cash cap is where one PURCHASE PATH stops, never where the die stops.
	local newBudget = math.clamp(purchased, minViable, shape.diamondCeiling)

	-- snapDOWN, not snap. Rounding each face's share to NEAREST rounds it up
	-- half the time, and faceCount shares each rounded up sum to more than the
	-- budget: 70 across a D6 gives 11.6667 per face and 70.0002 stored, so the
	-- die ends up holding more mass than the player bought. 0.0002 is worth
	-- nothing; the violated invariant is worth something, and rounding drift in
	-- an economic quantity is exactly the class of bug that grows teeth later.
	-- (Block 3 Gate 3 round 2, finding F-AD-4.)
	local faceMass = ForgeMath.snapDown(newBudget / shape.faceCount)
	if faceMass < shape.massFloor then
		-- Cannot happen while minViable = massFloor * faceCount, but the two are
		-- computed independently and a future catalog edit could separate them.
		faceMass = shape.massFloor
	end
	-- Re-derive the budget from the snapped face mass so the stored budget and
	-- the stored faces sum to the same number. Otherwise the very next forge
	-- proposal fails validation against a budget the faces cannot reach.
	local exactBudget = ForgeMath.snap(faceMass * shape.faceCount)

	local carriedElements: { string } = table.create(shape.faceCount, "")
	for i = 1, shape.faceCount do
		local prior = oldDie.Faces[i]
		carriedElements[i] = if prior ~= nil and ElementCatalog.exists(prior.Element)
			then prior.Element
			else "None"
	end

	-- THE INVARIANT GATE. This is the function that has been wrong three times
	-- in three different directions; it is now the one that cannot persist a die
	-- the contract rejects. Checked on the CANDIDATE and BEFORE any Diamonds
	-- move, so a violation is a clean refusal rather than a refund of a write
	-- that already happened.
	local candidateFaces: { PlayerProfile.Face } = {}
	for i = 1, shape.faceCount do
		candidateFaces[i] = { Mass = faceMass, Element = carriedElements[i] }
	end
	local invOk, invReason = ForgeService.assertDieInvariant({
		Shape = shapeId,
		MassBudget = exactBudget,
		PurchasedBudget = purchased,
		Faces = candidateFaces,
	}, shape)
	if not invOk then
		warn(string.format("[ForgeService] shape change refused by the die invariant for UserId=%d: %s -> %s (%s)",
			player.UserId, oldDie.Shape, shapeId, tostring(invReason)))
		return false, Remotes.Notice.InvalidRequest
	end

	-- THE FIRST EQUIP IS FREE (operator decision, 2026-08-11).
	--
	-- FR-6.1 charges Diamonds for a shape change, and that is right for the thing
	-- it is pricing: the freedom to keep changing your mind. It was wrong for the
	-- FIRST time a shape is worn, because the ladder is bought with Cash and
	-- Diamonds do not exist before a player's first ascension -- so a player could
	-- pay $500 for the D3 and be unable to put it on for the rest of the run. Cash
	-- buys the shape; Diamonds buy the swapping.
	--
	-- `ShapesEquipped` is only ever added to, and ascension does not clear it, so
	-- this discount cannot be farmed by re-ascending.
	local firstEquip = not data.Diamond.ShapesEquipped[shapeId]
	local switchCost = if firstEquip then 0 else SHAPE_CHANGE_DIAMOND_COST

	if switchCost > 0 then
		if not EconomyService.canAfford(player, "Diamonds", switchCost) then
			return false, Remotes.Notice.InsufficientFunds
		end

		local spent, spendReason = EconomyService.spend(player, "Diamonds", switchCost, "set_shape")
		if not spent then
			return false, spendReason
		end
	end

	local applied, applyReason = PlayerProfile.mutate(player, function(d)
		local faces: { PlayerProfile.Face } = {}
		for i = 1, shape.faceCount do
			faces[i] = { Mass = faceMass, Element = carriedElements[i] }
		end
		local existingDie = d.Dice[dieIndex]
		local newDie: any = {
			Shape = shapeId,
			MassBudget = exactBudget,
			-- Carried UNCHANGED. This is the value the player bought; a shape
			-- change may cap what is usable, never alter what is owned.
			PurchasedBudget = purchased,
			Faces = faces,
		}
		if type(existingDie) == "table" then
			for k, v in pairs(existingDie) do
				if newDie[k] == nil then
					newDie[k] = v
				end
			end
		end
		d.Dice[dieIndex] = newDie
		-- Latched INSIDE the same mutation that equips it, so the free equip and
		-- the record of it cannot come apart -- a write that half-applied would
		-- otherwise leave the discount available forever.
		d.Diamond.ShapesEquipped[shapeId] = true
	end)
	if not applied then
		if switchCost > 0 then
			EconomyService.credit(player, "Diamonds", switchCost, "set_shape_refund")
		end
		warn(string.format("[ForgeService] shape write refused for UserId=%d: %s",
			player.UserId, tostring(applyReason)))
		return false, Remotes.Notice.ProfileUnavailable
	end

	return true, nil
end

-- `wrap` is supplied by the composition root so every successful mutation
-- announces a fresh StateSync. Optional so the suite can register handlers
-- without a snapshot pipeline; identity when absent.
function ForgeService.registerHandlers(wrap: ((any) -> any)?): ()
	local w = wrap or function(f: any): any
		return f
	end
	RemoteGateway.register("Forge", w(function(player, dieIndex, distribution)
		return ForgeService.performForge(player, dieIndex, distribution)
	end))
	RemoteGateway.register("SetElement", w(function(player, dieIndex, faceIndex, elementId)
		return ForgeService.performSetElement(player, dieIndex, faceIndex, elementId)
	end))
	RemoteGateway.register("SetShape", w(function(player, dieIndex, shapeId)
		return ForgeService.performSetShape(player, dieIndex, shapeId)
	end))
end

return ForgeService
