--!strict
-- UT-2 — ForgeValidation (TEST_PLAN.md §4)
--
-- The forge validator is the highest-risk code in the game: it is what stands
-- between a player and inventing mass out of nothing (threat T-4).
--
-- The centrepiece is the NaN case. NaN fails EVERY comparison, so a validator
-- that checks `sum == budget` without first rejecting non-finite values passes
-- NaN straight through and the zero-sum invariant breaks silently. That is
-- threat T-25, and it is why ordering is specified in the contract rather than
-- left to the implementer. These tests assert the ORDER, not just the outcome.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ForgeMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ForgeMath"))

local FACES = 6
local BUDGET = 60
local FLOOR = 1

local n = 0
local function check(cond: boolean, msg: string): string?
	n += 1
	if not cond then
		return msg
	end
	return nil
end

local NAN = 0 / 0
local INF = math.huge

local function run(): (boolean, string?, number)
	n = 0
	local e: string?

	--------------------------------------------------------------------------
	-- isFinite: the primitive everything else depends on
	--------------------------------------------------------------------------
	e = e or check(NAN ~= NAN, "environment sanity: NaN should not equal itself")
	e = e or check(not ForgeMath.isFinite(NAN), "isFinite(NaN) must be false")
	e = e or check(not ForgeMath.isFinite(INF), "isFinite(inf) must be false")
	e = e or check(not ForgeMath.isFinite(-INF), "isFinite(-inf) must be false")
	e = e or check(not ForgeMath.isFinite("10" :: any), "isFinite('10') must be false")
	e = e or check(not ForgeMath.isFinite(nil :: any), "isFinite(nil) must be false")
	e = e or check(not ForgeMath.isFinite({} :: any), "isFinite(table) must be false")
	e = e or check(ForgeMath.isFinite(0), "isFinite(0) must be true")
	e = e or check(ForgeMath.isFinite(-5.5), "isFinite(-5.5) must be true")
	e = e or check(ForgeMath.isFinite(1e299), "isFinite(1e299) must be true")

	--------------------------------------------------------------------------
	-- the happy path must actually pass, or every rejection below is vacuous
	--------------------------------------------------------------------------
	local valid = { 10, 10, 10, 10, 10, 10 }
	local ok, reason = ForgeMath.validate(valid, FACES, BUDGET, FLOOR)
	e = e or check(ok, "a valid flat distribution was rejected: " .. tostring(reason))

	local concentrated = { 30, 6, 6, 6, 6, 6 }
	ok = ForgeMath.validate(concentrated, FACES, BUDGET, FLOOR)
	e = e or check(ok, "a valid concentrated distribution was rejected")

	--------------------------------------------------------------------------
	-- THE T-25 CASE. NaN placed so the naive arithmetic sum is NOT obviously
	-- wrong. A validator summing first would compute NaN, compare NaN <= EPSILON
	-- (false)... but a validator using `sum == budget` or any comparison chain
	-- that treats a failed comparison as "close enough" lets it through.
	-- We assert BOTH that it is rejected AND that it is rejected for the RIGHT
	-- reason, which is what proves finiteness ran before the sum.
	--------------------------------------------------------------------------
	local withNaN = { 10, 10, NAN, 10, 10, 10 }
	ok, reason = ForgeMath.validate(withNaN, FACES, BUDGET, FLOOR)
	e = e or check(not ok, "CRITICAL: a distribution containing NaN was ACCEPTED (threat T-25)")
	e = e or check(reason == "non_finite_mass",
		string.format("NaN rejected as '%s', expected 'non_finite_mass' — "
			.. "a different reason means the sum check ran before the finiteness check",
			tostring(reason)))

	-- NaN in every position, so the result cannot depend on iteration order
	for i = 1, FACES do
		local d = { 10, 10, 10, 10, 10, 10 }
		d[i] = NAN
		local o, r = ForgeMath.validate(d, FACES, BUDGET, FLOOR)
		e = e or check(not o, string.format("NaN at face %d was accepted", i))
		e = e or check(r == "non_finite_mass",
			string.format("NaN at face %d gave reason '%s'", i, tostring(r)))
	end

	-- infinities, same treatment
	ok, reason = ForgeMath.validate({ INF, 10, 10, 10, 10, 10 }, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "non_finite_mass", "+inf was not rejected as non-finite")
	ok, reason = ForgeMath.validate({ -INF, 10, 10, 10, 10, 10 }, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "non_finite_mass", "-inf was not rejected as non-finite")

	--------------------------------------------------------------------------
	-- structural rejections
	--------------------------------------------------------------------------
	ok, reason = ForgeMath.validate({ 10, 10, 10 }, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "wrong_face_count", "short array was not rejected")

	ok, reason = ForgeMath.validate({ 10, 10, 10, 10, 10, 10, 10 }, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "wrong_face_count", "long array was not rejected")

	ok, reason = ForgeMath.validate("not a table" :: any, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "not_a_table", "a non-table was not rejected")

	ok, reason = ForgeMath.validate({ -5, 15, 10, 10, 10, 20 }, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "below_floor", "negative mass was not rejected")

	ok, reason = ForgeMath.validate({ 0, 12, 12, 12, 12, 12 }, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "below_floor", "zero mass was not rejected")

	-- inflation: sums above budget
	ok, reason = ForgeMath.validate({ 100, 10, 10, 10, 10, 10 }, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "sum_mismatch", "an inflated distribution was ACCEPTED")

	-- deflation: sums below budget
	ok, reason = ForgeMath.validate({ 5, 5, 5, 5, 5, 5 }, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "sum_mismatch", "a deflated distribution was accepted")

	-- bad budget / floor arguments are rejected before touching the array
	ok, reason = ForgeMath.validate(valid, FACES, NAN, FLOOR)
	e = e or check(not ok and reason == "bad_budget", "NaN budget was not rejected")
	ok, reason = ForgeMath.validate(valid, FACES, BUDGET, NAN)
	e = e or check(not ok and reason == "bad_floor", "NaN floor was not rejected")

	--------------------------------------------------------------------------
	-- epsilon behaviour: tolerate representation error, reject real theft
	--------------------------------------------------------------------------
	local tiny = { 10.00001, 10, 10, 10, 10, 9.99999 }
	ok = ForgeMath.validate(tiny, FACES, BUDGET, FLOOR)
	e = e or check(ok, "a distribution within EPSILON was rejected")

	local justOver = { 10 + (ForgeMath.EPSILON * 50), 10, 10, 10, 10, 10 }
	ok, reason = ForgeMath.validate(justOver, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "sum_mismatch",
		"mass well beyond EPSILON was accepted — the invariant leaks")

	--------------------------------------------------------------------------
	-- T-27: residual accumulation.
	--
	-- NOTE ON A CORRECTED TEST: the first version of this block moved 0.1 from
	-- one face to another 500 times and asserted the result stayed valid. It
	-- failed -- correctly -- because after 90 iterations the donor face fell
	-- below the mass floor. The sum never drifted at all. The test was wrong,
	-- not the validator, and it modelled a flow that does not exist: the client
	-- submits a COMPLETE distribution each time, validated fresh against the
	-- server-held budget, so residuals cannot accumulate ACROSS operations by
	-- construction. What follows tests the real properties instead.
	--------------------------------------------------------------------------

	-- snap is idempotent: re-snapping never moves a value again
	for _, v in ipairs({ 0.1, 1 / 3, 9.99995, 1e-5, 12345.678912 }) do
		local once = ForgeMath.snap(v)
		e = e or check(ForgeMath.snap(once) == once,
			string.format("snap not idempotent for %.9f", v))
	end

	-- a long sequence of independently-valid proposals each validates, and the
	-- floor is respected throughout. This is the real flow.
	local rng = Random.new(4242)
	local cur = { 10, 10, 10, 10, 10, 10 }
	for iter = 1, 2000 do
		local from = rng:NextInteger(1, FACES)
		local to = rng:NextInteger(1, FACES)
		if from ~= to then
			-- transfer amounts are themselves snapped, mirroring the server
			-- storing only snapped masses
			local amount = ForgeMath.snap(rng:NextNumber(0.0001, 0.5))
			if cur[from] - amount >= FLOOR then
				local candidate = table.clone(cur)
				candidate[from] = ForgeMath.snap(candidate[from] - amount)
				candidate[to] = ForgeMath.snap(candidate[to] + amount)
				local o, r = ForgeMath.validate(candidate, FACES, BUDGET, FLOOR)
				if not o then
					e = e or check(false, string.format(
						"iteration %d: a snapped transfer of %.4f from %d to %d was "
						.. "rejected as '%s' -- residuals are accumulating",
						iter, amount, from, to, tostring(r)))
					break
				end
				cur = candidate
			end
		end
	end

	-- and after all that churn the invariant still holds exactly
	if not e then
		local total = 0.0
		for i = 1, FACES do total += cur[i] end
		e = e or check(math.abs(total - BUDGET) <= ForgeMath.EPSILON,
			string.format("after 2000 transfers the total is %.9f, expected %d", total, BUDGET))
	end

	-- the floor genuinely blocks a transfer that would breach it. This is the
	-- behaviour the broken test stumbled into, now asserted deliberately.
	local atFloor = { 55, FLOOR, FLOOR, FLOOR, FLOOR, FLOOR }
	ok = ForgeMath.validate(atFloor, FACES, BUDGET, FLOOR)
	e = e or check(ok, "a distribution sitting exactly on the floor should be valid")

	local belowFloor = { 55.5, FLOOR - 0.1, FLOOR, FLOOR, FLOOR, FLOOR }
	ok, reason = ForgeMath.validate(belowFloor, FACES, BUDGET, FLOOR)
	e = e or check(not ok and reason == "below_floor",
		"a face one notch below the floor was not rejected")

	-- every shape validates at its own face count
	for _, faces in ipairs({ 4, 6, 8, 12, 20 }) do
		local budget = faces * 10
		local dist = table.create(faces)
		for i = 1, faces do dist[i] = 10 end
		local o, r = ForgeMath.validate(dist, faces, budget, FLOOR)
		e = e or check(o, string.format("D%d flat distribution rejected: %s", faces, tostring(r)))
	end

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-2 ForgeValidation", run = run }
