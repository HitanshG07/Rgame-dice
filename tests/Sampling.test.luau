--!strict
-- UT-3 — Sampling (TEST_PLAN.md §4)
--
-- The server decides every outcome by weighted sampling; this suite is what
-- proves the dice are honest. If the empirical distribution drifts from the
-- declared one, every balance number derived from the simulations is wrong and
-- players are being paid on maths nobody verified.
--
-- Determinism matters as much as distribution: a fixed seed must reproduce a
-- run exactly, or no future regression in the roll loop is diagnosable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
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

local function makeDie(masses: { number }, element: string?): RollService.Die
	local faces = table.create(#masses)
	for i, m in ipairs(masses) do
		faces[i] = { Mass = m, Element = element or "None" }
	end
	local total = 0
	for _, m in ipairs(masses) do total += m end
	return { Shape = "D" .. tostring(#masses), MassBudget = total, Faces = faces }
end

local function flatMasses(faces: number, budget: number): { number }
	local t = table.create(faces)
	for i = 1, faces do t[i] = budget / faces end
	return t
end

local function run(): (boolean, string?, number)
	n = 0
	local e: string?

	----------------------------------------------------------------------------
	-- probabilities normalise for every shape, flat and concentrated
	----------------------------------------------------------------------------
	for _, faces in ipairs({ 4, 6, 8, 12, 20 }) do
		local budget = faces * 10

		local p = ForgeMath.landingProbabilities(flatMasses(faces, budget))
		local sum = 0.0
		for i = 1, faces do sum += p[i] end
		e = e or check(approx(sum, 1.0, 1e-9),
			string.format("D%d flat probabilities sum to %.12f", faces, sum))

		local conc = flatMasses(faces, budget)
		conc[1] = budget * 0.5
		local rest = (budget * 0.5) / (faces - 1)
		for i = 2, faces do conc[i] = rest end
		local pc = ForgeMath.landingProbabilities(conc)
		local sc = 0.0
		for i = 1, faces do sc += pc[i] end
		e = e or check(approx(sc, 1.0, 1e-9),
			string.format("D%d concentrated probabilities sum to %.12f", faces, sc))
	end

	----------------------------------------------------------------------------
	-- 100k samples: empirical frequency must match the declared distribution.
	-- Tolerance 0.005 is roughly 5x the standard error at this sample size, so
	-- a genuine bias shows up while ordinary noise does not.
	----------------------------------------------------------------------------
	local dist = { 30, 6, 6, 6, 6, 6 }
	local expected = ForgeMath.landingProbabilities(dist)
	local counts = table.create(6, 0)
	local rng = Random.new(20260805)
	local N = 100000
	for _ = 1, N do
		counts[ForgeMath.sampleFace(dist, rng)] += 1
	end
	for i = 1, 6 do
		local observed = counts[i] / N
		e = e or check(approx(observed, expected[i], 0.005),
			string.format("face %d observed %.5f, expected %.5f (delta %.5f)",
				i, observed, expected[i], math.abs(observed - expected[i])))
	end

	-- the heavy face must genuinely be the rarest in practice, not just on paper
	local heavyRarest = true
	for i = 2, 6 do
		if counts[1] >= counts[i] then heavyRarest = false end
	end
	e = e or check(heavyRarest,
		string.format("heavy face was sampled %d times, not rarer than the light faces", counts[1]))

	-- every face must actually occur; a probability-zero face would be a bug
	for i = 1, 6 do
		e = e or check(counts[i] > 0, string.format("face %d never sampled in %d draws", i, N))
	end

	----------------------------------------------------------------------------
	-- determinism: identical seeds produce identical sequences, different seeds
	-- do not. Both directions matter -- a broken RNG that always returns the
	-- same value would pass the first check alone.
	----------------------------------------------------------------------------
	local a, b = {}, {}
	local r1, r2 = Random.new(777), Random.new(777)
	for i = 1, 1000 do
		a[i] = ForgeMath.sampleFace(dist, r1)
		b[i] = ForgeMath.sampleFace(dist, r2)
	end
	local identical = true
	for i = 1, 1000 do
		if a[i] ~= b[i] then identical = false break end
	end
	e = e or check(identical, "identical seeds produced different sequences")

	local c = {}
	local r3 = Random.new(778)
	for i = 1, 1000 do c[i] = ForgeMath.sampleFace(dist, r3) end
	local allSame = true
	for i = 1, 1000 do
		if a[i] ~= c[i] then allSame = false break end
	end
	e = e or check(not allSame, "different seeds produced an identical sequence")

	local varied = false
	for i = 2, 1000 do
		if a[i] ~= a[1] then varied = true break end
	end
	e = e or check(varied, "sampler returned a constant face - RNG is not being consumed")

	----------------------------------------------------------------------------
	-- RollService.sampleOutcomes: one outcome per die, correct shape, and the
	-- reported baseValue must equal ForgeMath's value for the sampled mass.
	----------------------------------------------------------------------------
	local dice = {
		makeDie({ 30, 6, 6, 6, 6, 6 }),
		makeDie({ 10, 10, 10, 10 }),
		makeDie(flatMasses(20, 200)),
	}
	local sRng = Random.new(31337)
	for _ = 1, 200 do
		local outcomes = RollService.sampleOutcomes(dice, sRng)
		e = e or check(#outcomes == 3, "sampleOutcomes did not return one outcome per die")
		if e then break end
		for d, o in ipairs(outcomes) do
			local die = dice[d]
			e = e or check(o.dieIndex == d, "outcome dieIndex mismatch")
			e = e or check(o.faceIndex >= 1 and o.faceIndex <= #die.Faces,
				string.format("die %d faceIndex %d out of range", d, o.faceIndex))
			e = e or check(o.mass == die.Faces[o.faceIndex].Mass, "outcome mass mismatch")
			e = e or check(approx(o.baseValue, ForgeMath.faceValue(o.mass), 1e-9),
				"outcome baseValue does not match ForgeMath.faceValue")
			if e then break end
		end
		if e then break end
	end

	-- sampleOutcomes is reproducible too
	local o1 = RollService.sampleOutcomes(dice, Random.new(4242))
	local o2 = RollService.sampleOutcomes(dice, Random.new(4242))
	local match = true
	for i = 1, #o1 do
		if o1[i].faceIndex ~= o2[i].faceIndex then match = false break end
	end
	e = e or check(match, "sampleOutcomes not reproducible from an identical seed")

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-3 Sampling", run = run }
