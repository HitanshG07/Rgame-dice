--!strict
-- UT-14 — Balance (SRS FR-6.2, FR-6.3)
--
-- THE ONE REQUIREMENT NOTHING ELSE CAN CHECK. FR-6.3 says: "No shape dominates
-- at all Streak Strength values. Balance must preserve a crossover: low `b`
-- favours few faces, high `b` favours many. A build where one shape wins at
-- every `b` is a balance defect."
--
-- That is a property of the NUMBERS, not of the code. Every other suite in this
-- project can pass while it is violated, and one did for the entire build: the
-- per-shape mass budgets scaled with face count (D2 = 20 ... D20 = 200), which
-- handed the D20 ten times the mass of the D2. Payout is superlinear in mass
-- (FR-2.4), so more budget is STRICTLY better and the D20 won at every single
-- `b` -- eight sweeps out of eight. DiceCatalog's own header said the crossover
-- was "NOT YET VERIFIED" and the sweep that would have caught it was a roadmap
-- item nobody had reached.
--
-- This suite is that sweep, run on every single test pass, so the defect cannot
-- come back quietly. It is deliberately written against the SHIPPING catalog
-- rather than a fixture: a balance test with its own numbers tests nothing.
--
-- WHAT IT DOES NOT CLAIM. Passing here means a crossover EXISTS -- that at least
-- two shapes each win somewhere. It does not mean the game is well tuned, that
-- the crossover sits at a good `b`, or that the middle shapes are worth owning.
-- Those are design judgements and belong to the operator.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local RollService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("RollService"))

local n = 0
local function check(cond: boolean, msg: string): string?
	n += 1
	if not cond then
		return msg
	end
	return nil
end

-- Expected value per roll for "concentrate the surplus on `k` faces, floor the
-- rest", including the expected streak multiplier.
--
-- WHY THAT FAMILY. Under inverse-mass sampling a heavy face lands LESS often, so
-- optimal play is always some split between a few heavy paying faces and the
-- rest parked at the floor. Sweeping `k` from 1 to faceCount-1 covers that whole
-- family, and the best `k` is the shape's best achievable play.
local function bestEV(faceCount: number, budget: number, floor: number, b: number): (number, number)
	local best, bestVoid = -1, 1

	for k = 1, faceCount - 1 do
		local surplus = budget - floor * faceCount
		if surplus > 0 then
			local heavy = floor + surplus / k
			local mass = table.create(faceCount, floor)
			for i = 1, k do
				mass[i] = heavy
			end

			local total = 0
			for _, m in ipairs(mass) do
				total += m
			end

			-- P(face i) proportional to (M - m_i), normalised (FR-2.3).
			local denom = total * faceCount - total
			if denom > 0 then
				local ev, voidP = 0, 0
				for i = 1, faceCount do
					local p = (total - mass[i]) / denom
					ev += p * ForgeMath.faceValue(mass[i])
					if ForgeMath.isVoidFace(mass, i, floor) then
						voidP += p
					end
				end

				-- Expected streak multiplier over a geometric run of non-Void rolls.
				local q = 1 - voidP
				local mult = 1
				if b > 0 then
					if q >= 1 then
						mult = RollService.streakMultiplier(RollService.STREAK_CAP, b)
					elseif q > 0 then
						local sum = 0
						for step = 0, RollService.STREAK_CAP do
							local w = (q ^ step)
								* (if step < RollService.STREAK_CAP then voidP else 1)
							sum += w * RollService.streakMultiplier(step, b)
						end
						mult = sum
					end
				end

				local score = ev * mult
				if score > best then
					best, bestVoid = score, voidP
				end
			end
		end
	end

	return best, bestVoid
end

local function run(): (boolean, string?, number)
	n = 0
	local e: any = nil

	local order = DiceCatalog.getUnlockOrder()
	e = e or check(#order >= 2, "the sweep needs at least two shapes to compare")

	--------------------------------------------------------------------------
	-- FR-6.3: the crossover must exist
	--------------------------------------------------------------------------

	-- Spanning the measured cliff at b ~= 0.15 (ledger L-016) in both directions.
	local strengths = { 0, 0.02, 0.05, 0.10, 0.15, 0.20, 0.30, 0.50 }
	local winners: { [string]: boolean } = {}
	local winnerAt: { string } = {}

	for _, b in ipairs(strengths) do
		local bestId, bestScore = nil, -math.huge
		for _, id in ipairs(order) do
			local def = DiceCatalog.getShape(id)
			if def ~= nil then
				local score = bestEV(def.faceCount, def.defaultBudget, def.massFloor, b)
				if score > bestScore then
					bestId, bestScore = id, score
				end
			end
		end
		if bestId ~= nil then
			winners[bestId] = true
			table.insert(winnerAt, string.format("b=%.2f:%s", b, bestId))
		end
	end

	local distinct = 0
	for _ in pairs(winners) do
		distinct += 1
	end

	e = e or check(distinct > 1, string.format(
		"FR-6.3 VIOLATED -- one shape wins at every Streak Strength. Winners: %s."
		.. " The usual cause is a mass budget that differs by shape: payout is"
		.. " superlinear in mass, so more budget is strictly better and face count"
		.. " stops mattering.",
		table.concat(winnerAt, ", ")))

	--------------------------------------------------------------------------
	-- FR-6.2: fewer faces must be MORE volatile
	--------------------------------------------------------------------------
	--
	-- The crossover is only meaningful if it comes from the intended mechanism.
	-- Void probability at best play must fall as face count rises -- that is what
	-- makes a low-face die the sniper and a high-face die the grinder.

	local prevVoid, prevId = nil, nil
	local monotone = true
	local trace: { string } = {}
	for _, id in ipairs(order) do
		local def = DiceCatalog.getShape(id)
		if def ~= nil then
			local _, voidP = bestEV(def.faceCount, def.defaultBudget, def.massFloor, 0.10)
			table.insert(trace, string.format("%s=%.3f", id, voidP))
			if prevVoid ~= nil and voidP > prevVoid + 1e-9 then
				monotone = false
			end
			prevVoid, prevId = voidP, id
		end
	end

	e = e or check(monotone, string.format(
		"FR-6.2 VIOLATED -- Void probability must not RISE with face count. Got %s",
		table.concat(trace, " ")))

	--------------------------------------------------------------------------
	-- The structural cause, asserted directly
	--------------------------------------------------------------------------
	--
	-- Both properties above depend on the budget being shape-independent. Checking
	-- it here names the cause, so a future failure reports WHY rather than only
	-- that the sweep broke.

	local firstBudget: number? = nil
	local uniform = true
	for _, id in ipairs(order) do
		local def = DiceCatalog.getShape(id)
		if def ~= nil then
			if firstBudget == nil then
				firstBudget = def.defaultBudget
			elseif def.defaultBudget ~= firstBudget then
				uniform = false
			end
		end
	end
	e = e or check(uniform,
		"the default mass budget must be identical across shapes -- a per-shape"
		.. " budget makes face count irrelevant and re-opens FR-6.3")

	if e ~= nil then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-14 Balance", run = run }
