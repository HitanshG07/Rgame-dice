--!strict
-- UT-1 — ForgeMath (TEST_PLAN.md §4)
-- Asserts the two rules the whole game balances on, which were established
-- numerically before any code existed (ledger L-016):
--     P(face i) proportional to (M - mass_i)   heavy sinks
--     value(i)  = mass_i ^ 2.0                 superlinear, concentration pays
-- If either regresses, the forge stops being a decision and becomes decoration.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ForgeMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ForgeMath"))

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

local function flat(faces: number, budget: number): { number }
	local t: { number } = table.create(faces, 0)
	for i = 1, faces do
		t[i] = budget / faces
	end
	return t
end

local function run(): (boolean, string?, number)
	n = 0
	-- Typed `any` rather than `string?` for one specific Luau reason: the
	-- accumulator idiom `e = e or check(...)` produces a refinement union the
	-- checker cannot collapse back to `string?`, which warns at every call site.
	-- Semantics are unchanged (check still runs only while e is nil) and nothing
	-- is hidden: `e` is a local failure message whose only use is the return below.
	local e: any = nil

	-- probabilities sum to 1 for every shape, flat and concentrated
	for _, faces in ipairs({ 4, 6, 8, 12, 20 }) do
		local budget = faces * 10

		local p = ForgeMath.landingProbabilities(flat(faces, budget))
		local sum = 0.0
		for i = 1, faces do sum += p[i] end
		e = e or check(approx(sum, 1.0, 1e-9),
			string.format("D%d flat probabilities sum to %.12f, expected 1", faces, sum))

		-- flat means uniform
		e = e or check(approx(p[1], 1 / faces, 1e-9),
			string.format("D%d flat face probability %.9f, expected %.9f", faces, p[1], 1 / faces))

		-- concentrated: one heavy face, remainder even
		local conc: { number } = table.create(faces, 0)
		conc[1] = budget * 0.5
		for i = 2, faces do conc[i] = (budget * 0.5) / (faces - 1) end
		local pc = ForgeMath.landingProbabilities(conc)
		local sc = 0.0
		for i = 1, faces do sc += pc[i] end
		e = e or check(approx(sc, 1.0, 1e-9),
			string.format("D%d concentrated probabilities sum to %.12f", faces, sc))

		-- THE core inversion: the heavy face must be strictly less likely
		e = e or check(pc[1] < pc[2],
			string.format("D%d heavy face p=%.6f is not below light face p=%.6f", faces, pc[1], pc[2]))
	end

	-- superlinearity: the gain from 2m->3m must EXCEED the gain from m->2m.
	-- At alpha <= 1 this fails and concentrating mass stops paying.
	local m = 10
	local g1 = ForgeMath.faceValue(2 * m) - ForgeMath.faceValue(m)
	local g2 = ForgeMath.faceValue(3 * m) - ForgeMath.faceValue(2 * m)
	e = e or check(g2 > g1,
		string.format("value not superlinear: gain(2m->3m)=%.3f <= gain(m->2m)=%.3f", g2, g1))
	e = e or check(approx(ForgeMath.faceValue(10), 100, 1e-9),
		"faceValue(10) should be 100 at alpha=2")
	e = e or check(ForgeMath.faceValue(0) == 0, "faceValue(0) should be 0")

	-- expected value is positive and finite for both shapes of build
	local evFlat = ForgeMath.expectedValue(flat(6, 60))
	e = e or check(ForgeMath.isFinite(evFlat) and evFlat > 0,
		"expectedValue(flat D6) not finite-positive")

	-- voidProbability tracks the LIGHTEST face, which is the streak breaker
	local d = { 30, 6, 6, 6, 6, 6 }
	local pv = ForgeMath.landingProbabilities(d)
	e = e or check(approx(ForgeMath.voidProbability(d), pv[2], 1e-12),
		"voidProbability did not return the lightest face's probability")
	-- and a flat die's void probability is exactly 1/n
	e = e or check(approx(ForgeMath.voidProbability(flat(20, 200)), 1 / 20, 1e-9),
		"flat D20 void probability should be 1/20")
	-- D4 must be meaningfully more volatile than D20 (SRS FR-6.2)
	e = e or check(ForgeMath.voidProbability(flat(4, 40)) > ForgeMath.voidProbability(flat(20, 200)),
		"D4 should break streaks more often than D20")

	-- snapping is deterministic and kills residual accumulation (threat T-27)
	e = e or check(ForgeMath.snap(10.000049) == 10.0, "snap should round 10.000049 to 10.0")
	e = e or check(ForgeMath.snap(-2.00005) == -2.0001 or ForgeMath.snap(-2.00005) == -2.0,
		"snap must be defined and symmetric for negatives")
	local acc = 0.0
	for _ = 1, 1000 do acc += ForgeMath.snap(0.1) end
	e = e or check(approx(acc, 100.0, 1e-6),
		string.format("snapped accumulation drifted to %.9f, expected 100", acc))

	-- sampleFace is in range and reproducible from a fixed seed
	local dist = { 30, 6, 6, 6, 6, 6 }
	local a1, a2 = {}, {}
	local r1, r2 = Random.new(12345), Random.new(12345)
	for i = 1, 500 do
		a1[i] = ForgeMath.sampleFace(dist, r1)
		a2[i] = ForgeMath.sampleFace(dist, r2)
	end
	local same, inRange = true, true
	for i = 1, 500 do
		if a1[i] ~= a2[i] then same = false end
		if a1[i] < 1 or a1[i] > 6 then inRange = false end
	end
	e = e or check(same, "sampleFace not reproducible from an identical seed")
	e = e or check(inRange, "sampleFace returned an out-of-range index")

	-- empirical frequency must match the declared distribution
	local counts: { number } = table.create(6, 0)
	local rng = Random.new(99)
	local N = 60000
	for _ = 1, N do
		local f = ForgeMath.sampleFace(dist, rng)
		counts[f] += 1
	end
	local pd = ForgeMath.landingProbabilities(dist)
	for i = 1, 6 do
		local observed = counts[i] / N
		e = e or check(approx(observed, pd[i], 0.02),
			string.format("face %d observed %.4f vs expected %.4f", i, observed, pd[i]))
	end

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-1 ForgeMath", run = run }
