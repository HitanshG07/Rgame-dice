--!strict
-- ForgeMath.luau
-- Pure forge mathematics. No state, no side effects, no authority.
--
-- Shared between client and server ON PURPOSE (HLD §6). The client renders the
-- forge preview with it; the server decides outcomes with it. Sharing guarantees
-- the maths a player optimises against is exactly the maths that pays them
-- (SRS FR-3.4). It is safe to replicate because it is pure: a tampered client
-- can only lie to its own preview -- the server recomputes from its own stored mass.
--
-- The two rules that make the forge a real decision rather than decoration,
-- both established numerically before any code existed (ledger L-016):
--
--   value(i) = mass_i ^ ALPHA          ALPHA = 2.0, superlinear: concentration pays
--   P(i)     = (M - mass_i) / (M(n-1)) heavy sinks: concentration costs
--
-- ALPHA <= 1 makes the forge inert (flat distribution wins everywhere).
-- P proportional to 1/mass makes it worse than inert -- the optimal play becomes
-- "never forge at all". Both were measured. Do not retune these without re-running
-- the dominant-strategy simulation.

local ForgeMath = {}

-- Payout exponent. Superlinearity is a correctness requirement (SRS FR-2.4).
ForgeMath.ALPHA = 2.0

-- Masses snap to this precision before any sum check, so IEEE 754 residuals
-- cannot compound across repeated forges and drift past EPSILON (threat T-27).
ForgeMath.PRECISION = 4
ForgeMath.EPSILON = 1e-3

local POW10 = 10 ^ ForgeMath.PRECISION

export type Distribution = { number }

--------------------------------------------------------------------------------
-- Finiteness. Asserted at EVERY numeric boundary, not only inbound ones.
--
-- NaN fails every comparison, so a sum check alone passes when NaN is present
-- and the budget invariant breaks silently (threat T-25). The same hazard was
-- once closed here and left open in the leaderboard transform -- the
-- inconsistency was the actual defect (threat T-28), so this is now a rule
-- applied uniformly rather than a spot fix.
--------------------------------------------------------------------------------

local MAX_FINITE = 1e300

function ForgeMath.isFinite(n: unknown): boolean
	if type(n) ~= "number" then
		return false
	end
	local x = n :: number
	if x ~= x then          -- NaN: the only value not equal to itself
		return false
	end
	if x >= math.huge or x <= -math.huge then
		return false
	end
	return x <= MAX_FINITE and x >= -MAX_FINITE
end

-- Round-half-away-from-zero at PRECISION. Deterministic on both sides of the
-- wire, which matters because client and server both call it.
function ForgeMath.snap(n: number): number
	if not ForgeMath.isFinite(n) then
		error("[ForgeMath] snap received a non-finite value", 2)
	end
	if n >= 0 then
		return math.floor(n * POW10 + 0.5) / POW10
	end
	return -math.floor(-n * POW10 + 0.5) / POW10
end

-- Snap TOWARD ZERO instead of to nearest.
--
-- `snap` rounds half-up, which is right for a displayed value and wrong for
-- dividing a budget into equal shares: rounding each share UP makes the shares
-- sum to MORE than the budget. At 4dp that is 0.0002 on a 70-budget D6 --
-- economically nothing, and still a violated invariant, because the die then
-- holds more mass than the player bought. Use this wherever a total is being
-- split and the parts must not exceed the whole. (Block 3 Gate 3 finding F-AD-4.)
function ForgeMath.snapDown(n: number): number
	if not ForgeMath.isFinite(n) then
		error("[ForgeMath] snapDown received a non-finite value", 2)
	end
	if n >= 0 then
		return math.floor(n * POW10) / POW10
	end
	-- floor, not ceil, on the MAGNITUDE. `-math.ceil(-n * POW10)` rounds a
	-- negative away from zero, which is the opposite of what this function
	-- promises: snapDown(-1.99999) would give -2.0 rather than -1.9999.
	return -math.floor(-n * POW10) / POW10
end

function ForgeMath.snapAll(mass: Distribution): Distribution
	local out: Distribution = table.create(#mass, 0)
	for i = 1, #mass do
		out[i] = ForgeMath.snap(mass[i])
	end
	return out
end

--------------------------------------------------------------------------------
-- Structural validation. Pure -- knows nothing about players, budgets or costs;
-- the server layers affordability and ownership on top (API contract §2.1).
--------------------------------------------------------------------------------

-- Returns ok, reason. Ordering is deliberate and specified: finiteness is
-- checked BEFORE summation, because a sum check alone cannot reject NaN.
function ForgeMath.validate(
	mass: Distribution,
	faceCount: number,
	budget: number,
	massFloor: number
): (boolean, string?)
	if type(mass) ~= "table" then
		return false, "not_a_table"
	end
	if #mass ~= faceCount then
		return false, "wrong_face_count"
	end
	if not ForgeMath.isFinite(budget) or budget <= 0 then
		return false, "bad_budget"
	end
	if not ForgeMath.isFinite(massFloor) or massFloor <= 0 then
		return false, "bad_floor"
	end

	-- pass 1: finiteness and floor, before any arithmetic on the values
	for i = 1, faceCount do
		local m = mass[i]
		if not ForgeMath.isFinite(m) then
			return false, "non_finite_mass"
		end
		if (m :: number) < massFloor then
			return false, "below_floor"
		end
	end

	-- pass 2: snap, then sum. Snapping first keeps residuals from compounding.
	local total = 0.0
	for i = 1, faceCount do
		total += ForgeMath.snap(mass[i])
	end
	if math.abs(total - budget) > ForgeMath.EPSILON then
		return false, "sum_mismatch"
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- The maths proper. Every entry point re-checks its inputs: these are called
-- from both sides of a trust boundary and must never be assumed clean.
--------------------------------------------------------------------------------

-- P(face i lands up) = (M - mass_i) / (M * (n - 1)).
-- Heavier faces land face-down more often. Sums to exactly 1 by construction:
-- sum(M - m_i) = nM - M = M(n-1).
function ForgeMath.landingProbabilities(mass: Distribution): { number }
	local n = #mass
	if n < 2 then
		error("[ForgeMath] a die needs at least 2 faces", 2)
	end

	local total = 0.0
	for i = 1, n do
		if not ForgeMath.isFinite(mass[i]) then
			error("[ForgeMath] non-finite mass at face " .. tostring(i), 2)
		end
		total += mass[i]
	end
	if total <= 0 then
		error("[ForgeMath] total mass must be positive", 2)
	end

	local denom = total * (n - 1)
	local out: Distribution = table.create(n, 0)
	for i = 1, n do
		local p = (total - mass[i]) / denom
		-- A face holding the entire budget would yield p = 0; clamp so no face is
		-- ever strictly impossible, which keeps sampling well-defined.
		out[i] = if p < 0 then 0 else p
	end
	return out
end

-- value(i) = mass_i ^ ALPHA
function ForgeMath.faceValue(faceMass: number): number
	if not ForgeMath.isFinite(faceMass) then
		error("[ForgeMath] faceValue received a non-finite mass", 2)
	end
	if faceMass <= 0 then
		return 0
	end
	local v = faceMass ^ ForgeMath.ALPHA
	if not ForgeMath.isFinite(v) then
		error("[ForgeMath] faceValue overflowed", 2)
	end
	return v
end

function ForgeMath.faceValues(mass: Distribution): { number }
	local out: { number } = table.create(#mass, 0)
	for i = 1, #mass do
		out[i] = ForgeMath.faceValue(mass[i])
	end
	return out
end

-- Expected payout per roll, before elements, streak and boosts.
function ForgeMath.expectedValue(mass: Distribution): number
	local p = ForgeMath.landingProbabilities(mass)
	local ev = 0.0
	for i = 1, #mass do
		ev += p[i] * ForgeMath.faceValue(mass[i])
	end
	return ev
end

-- The streak breaker: probability of landing the LIGHTEST face (SRS FR-5.2).
-- Lightest means most likely, so this is the visible cost of concentrating
-- mass elsewhere. This -- not the hit-frequency of the best face -- is the
-- consistency metric the design is balanced against.
-- "Near" the floor. A face at or below floor * this factor is a Void.
-- THE SINGLE DEFINITION -- RollService.isVoidFace delegates here rather than
-- restating it, because it already drifted once.
ForgeMath.VOID_FLOOR_FACTOR = 1.5

-- Is this face a Void? Lightest AND at or near the mass floor (SRS FR-5.2).
--
-- Both halves matter. Without the proximity test an UN-FORGED flat die has its
-- face 1 treated as a Void, so a new player breaks their streak 1-in-n rolls
-- with no way to avoid it. Without the lightest test every face on a heavily
-- stripped die would count.
function ForgeMath.isVoidFace(mass: Distribution, faceIndex: number, massFloor: number): boolean
	local lightest = 1
	for i = 2, #mass do
		if mass[i] < mass[lightest] then
			lightest = i
		end
	end
	if faceIndex ~= lightest then
		return false
	end
	return mass[lightest] <= massFloor * ForgeMath.VOID_FLOOR_FACTOR
end

-- P(this die lands a Void this throw).
--
-- `massFloor` IS REQUIRED, and that is the fix. This function used to return
-- P(lightest face) unconditionally, with no floor argument and no proximity
-- gate -- so for a starting D6 (six faces at mass 10, floor 1) it reported
-- 16.7% while the server's own isVoidFace reported that NO face is a Void and
-- the true probability is ZERO.
--
-- The divergence dates from the F-G3-1 fix, which added the proximity gate to
-- RollService and left this function untouched. It survived five Block 3 audit
-- rounds because no SERVER code calls it -- only the client does, and the client
-- did not exist yet. It is the number FR-3.4 puts in front of the player to
-- optimise against, and it was wrong by its entire value for every un-forged
-- die. Found by the Block 4 HUD verifier. Third instance of ledger L-025: a rule
-- living in two places drifts, and the copy nobody executes drifts silently.
function ForgeMath.voidProbability(mass: Distribution, massFloor: number): number
	local lightest = 1
	for i = 2, #mass do
		if mass[i] < mass[lightest] then
			lightest = i
		end
	end
	if not ForgeMath.isVoidFace(mass, lightest, massFloor) then
		return 0
	end
	return ForgeMath.landingProbabilities(mass)[lightest]
end

-- Everything the forge preview needs, in one pass (SRS FR-3.4).
export type Preview = {
	probabilities: { number },
	values: { number },
	expectedValue: number,
	voidProbability: number,
}

function ForgeMath.preview(mass: Distribution, massFloor: number): Preview
	return {
		probabilities = ForgeMath.landingProbabilities(mass),
		values = ForgeMath.faceValues(mass),
		expectedValue = ForgeMath.expectedValue(mass),
		voidProbability = ForgeMath.voidProbability(mass, massFloor),
	}
end

-- Weighted sample of a landed face index. SERVER-ONLY BY CONVENTION: the client
-- has no reason to call this, and calling it grants no authority since the
-- server never reads a client-supplied outcome (threat T-1). `rng` is injected
-- so tests can pin a seed and reproduce exactly.
function ForgeMath.sampleFace(mass: Distribution, rng: Random): number
	local p = ForgeMath.landingProbabilities(mass)
	local roll = rng:NextNumber()
	local cumulative = 0.0
	for i = 1, #p do
		cumulative += p[i]
		if roll <= cumulative then
			return i
		end
	end
	-- Floating-point shortfall on the final comparison: award the last face
	-- rather than returning nil. Reaching here is expected occasionally.
	return #p
end


--------------------------------------------------------------------------------
-- FORGE COST (SRS FR-3.3)
--
-- SHARED, not server-only, and that is the point. FR-3.4 requires the forge UI
-- to show what a change will cost BEFORE it is committed, and the only honest
-- way to do that is for the client to run the SAME function the server charges
-- with. A client-side reimplementation is exactly the failure ledger L-026
-- records: the copy nobody executes is the one that drifts, and here the two
-- copies would be a quoted price and an actual charge.
--
-- PURE. No Player, no profile, no entitlements -- so the server can apply its
-- pass multiplier on top and the client can render the base figure.
--------------------------------------------------------------------------------

ForgeMath.BASE_COST_PER_MASS_UNIT = 5.0
ForgeMath.COST_REFERENCE_BUDGET = 60.0
ForgeMath.COST_SCALE_EXPONENT = 2.0

-- Cost of moving from `oldDist` to `newDist`, before any ownership discount.
--
-- Scales with the SUM OF ABSOLUTE DELTAS across faces. Note this counts a
-- zero-sum move at both ends -- moving 5 mass from face A to face B registers as
-- 10 units of change. That is the behaviour the shipped cost curve was tuned
-- against, so it is preserved EXACTLY here rather than "corrected" to 5; halving
-- it would quietly halve every forge price in the game.
--
-- Scales again with the die's budget, so re-forging a developed
-- die is not free relative to its earnings (FR-3.3, and ledger L-016 -- free
-- re-forging collapses the cross-die puzzle into a solved symmetric state).
--
-- Returns math.huge for any malformed input, which every caller treats as
-- unaffordable rather than as zero.
function ForgeMath.forgeCost(oldDist: { number }, newDist: { number }, budget: number?): number
	if type(oldDist) ~= "table" or type(newDist) ~= "table" then
		return math.huge
	end
	if #oldDist ~= #newDist then
		return math.huge
	end

	local deltaSum = 0
	for i = 1, #newDist do
		local a, b = oldDist[i], newDist[i]
		if type(a) ~= "number" or type(b) ~= "number" then
			return math.huge
		end
		local d = math.abs(b - a)
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
		scale = (budget / ForgeMath.COST_REFERENCE_BUDGET) ^ ForgeMath.COST_SCALE_EXPONENT
		if not ForgeMath.isFinite(scale) or scale < 1.0 then
			scale = 1.0  -- never cheaper than the starting die
		end
	end

	local cost = ForgeMath.snap(deltaSum * ForgeMath.BASE_COST_PER_MASS_UNIT * scale)
	if not ForgeMath.isFinite(cost) then
		return math.huge
	end
	return cost
end

return ForgeMath
