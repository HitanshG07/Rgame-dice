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
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local RemoteGateway = require(script.Parent:WaitForChild("RemoteGateway"))

local ForgeService = {}

local BASE_COST_PER_MASS_UNIT = 5.0
-- The starting D6 budget. A die at this budget pays exactly BASE per mass unit;
-- everything above it pays more. Tuning surface for P-6B.
local REFERENCE_BUDGET = 60.0
local SCALE_EXPONENT = 2.0
local ELEMENT_SET_COST = 50.0
local SHAPE_CHANGE_DIAMOND_COST = 5

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

function ForgeService._setResultEmitterForTesting(fn: ((Player, any) -> ())?): ()
	if not RunService:IsStudio() then
		error("[ForgeService] the result-emitter seam is Studio-only", 2)
	end
	emitForgeResult = fn or defaultEmit
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
function ForgeService.computeForgeCost(oldDist: { number }, newDist: { number }, budget: number?): number
	if #oldDist ~= #newDist then
		return math.huge
	end
	local deltaSum = 0.0
	for i = 1, #oldDist do
		local d = math.abs(newDist[i] - oldDist[i])
		if not ForgeMath.isFinite(d) then
			return math.huge
		end
		deltaSum += d
	end

	local scale = 1.0
	if budget ~= nil then
		if not ForgeMath.isFinite(budget) or budget <= 0 then
			return math.huge
		end
		scale = (budget / REFERENCE_BUDGET) ^ SCALE_EXPONENT
		if not ForgeMath.isFinite(scale) or scale < 1.0 then
			scale = 1.0  -- never cheaper than the starting die
		end
	end

	local cost = ForgeMath.snap(deltaSum * BASE_COST_PER_MASS_UNIT * scale)
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

	local cost = ForgeService.computeForgeCost(oldDist, distribution, die.MassBudget)
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

	if not EconomyService.canAfford(player, "Cash", ELEMENT_SET_COST) then
		return false, Remotes.Notice.InsufficientFunds
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
	local okIdx, rIdx = v.integerInRange(dieIndex, 1, #data.Dice)
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

	-- Changing to the shape already equipped is a no-op, and a no-op must never
	-- cost Diamonds.
	if data.Dice[dieIndex].Shape == shapeId then
		return false, Remotes.Notice.InvalidRequest
	end

	if not EconomyService.canAfford(player, "Diamonds", SHAPE_CHANGE_DIAMOND_COST) then
		return false, Remotes.Notice.InsufficientFunds
	end

	local spent, spendReason = EconomyService.spend(player, "Diamonds", SHAPE_CHANGE_DIAMOND_COST, "set_shape")
	if not spent then
		return false, spendReason
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
	local newBudget = math.clamp(purchased, minViable, shape.cashBudgetCap)

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

	local applied, applyReason = PlayerProfile.mutate(player, function(d)
		local faces: { PlayerProfile.Face } = {}
		for i = 1, shape.faceCount do
			faces[i] = { Mass = faceMass, Element = carriedElements[i] }
		end
		d.Dice[dieIndex] = {
			Shape = shapeId,
			MassBudget = exactBudget,
			-- Carried UNCHANGED. This is the value the player bought; a shape
			-- change may cap what is usable, never alter what is owned.
			PurchasedBudget = purchased,
			Faces = faces,
		}
	end)
	if not applied then
		EconomyService.credit(player, "Diamonds", SHAPE_CHANGE_DIAMOND_COST, "set_shape_refund")
		warn(string.format("[ForgeService] shape write refused for UserId=%d: %s",
			player.UserId, tostring(applyReason)))
		return false, Remotes.Notice.ProfileUnavailable
	end

	return true, nil
end

function ForgeService.registerHandlers(): ()
	RemoteGateway.register("Forge", function(player, dieIndex, distribution)
		return ForgeService.performForge(player, dieIndex, distribution)
	end)
	RemoteGateway.register("SetElement", function(player, dieIndex, faceIndex, elementId)
		return ForgeService.performSetElement(player, dieIndex, faceIndex, elementId)
	end)
	RemoteGateway.register("SetShape", function(player, dieIndex, shapeId)
		return ForgeService.performSetShape(player, dieIndex, shapeId)
	end)
end

return ForgeService
