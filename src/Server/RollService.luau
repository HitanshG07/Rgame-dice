--!strict
-- RollService.luau
-- The core roll loop. Server-authoritative from end to end.
--
-- HLD §4.1: client sends intent with no payload -> server samples each die's
-- face from its mass distribution -> elements resolve across the resolved face
-- set -> streak updates -> EconomyService credits -> RollResult is pushed.
--
-- THE ARCHITECTURAL CONSTRAINT (HLD §1): the server holds no rigid-body state.
-- Everything below resolves from the RESOLVED FACE SET alone -- no positions,
-- no velocities, no collisions. A feature that needs "which gap it struck" or
-- "what was nearby" cannot be built here and is rejected at design time.
--
-- SHAPE OF THIS MODULE: the payout mathematics is split into PURE functions
-- that take plain tables and an injected Random. They touch no Player, no
-- profile and no Roblox service, so UT-3 and UT-4 can test the real logic
-- rather than a reimplementation of it. `performRoll` is the thin shell that
-- wires those pure functions to profile state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local RollService = {}

--------------------------------------------------------------------------------
-- Tuning. Structure is fixed by simulation (ledger L-016); these constants are
-- the tunable surface. STREAK_CAP and the b-per-level mapping straddle the
-- measured cliff at b ~= 0.15 deliberately: a player who has invested nothing
-- sits below it and is correctly a sniper, one who has invested heavily sits
-- above it and is correctly a grinder. That split IS the build diversity.
--------------------------------------------------------------------------------

RollService.STREAK_CAP = 50
RollService.B_PER_LEVEL = 0.01           -- StreakStrength level -> b
RollService.MAX_STREAK_MULTIPLIER = 1e6  -- hard ceiling; compounding is explosive
RollService.SHIELD_COOLDOWN = 30         -- seconds, server-clocked (SRS FR-5.6)

-- A face is a Void only if it is the lightest AND sits at or near the mass
-- floor (SRS FR-5.2: "a face at or near the mass floor"). Without the
-- proximity test an UN-FORGED flat die has its face 1 treated as a Void, so a
-- brand-new player breaks their streak 1-in-n rolls with no way to avoid it.
-- Fixed 2026-08-06 from Gate 3 finding F-G3-1: the code contradicted the spec,
-- and the spec was right.
RollService.MASS_FLOOR = 1               -- moves to DiceCatalog per-shape later
RollService.VOID_FLOOR_FACTOR = 1.5      -- "near" = within 1.5x the floor

-- Offline vault rate is earned/elapsed. Without a minimum window a player who
-- rolls once immediately after joining divides a real payout by ~0.05s and
-- produces an astronomical rate, which then feeds Vault.AvgIncomePerSec and
-- inflates their offline earnings. Added 2026-08-06 from Gate 4 finding
-- F-G4-1 (threat T-30) -- a genuine currency exploit the threat model missed.
RollService.MIN_RATE_WINDOW = 60         -- seconds before the rate is trusted
RollService.MAX_RATE = 1e12              -- absolute ceiling on the reported rate

export type Face = { Mass: number, Element: string }
export type Die = { Shape: string, MassBudget: number, Faces: { Face } }

export type DieOutcome = {
	dieIndex: number,
	faceIndex: number,
	mass: number,
	element: string,
	baseValue: number,
}

export type ThrowResult = {
	outcomes: { DieOutcome },
	baseTotal: number,      -- sum of face values before elements
	elementTotal: number,   -- additive element contribution
	multiplier: number,     -- multiplicative element factor
	streakMultiplier: number,
	payout: number,         -- final credited amount
	voidHit: boolean,
	streak: number,
	elementsFired: { string },
	frozenDie: number?,     -- die locked for the NEXT throw, if any
}

--------------------------------------------------------------------------------
-- PURE: streak
--------------------------------------------------------------------------------

-- Compounding, per SRS FR-5.3. A LINEAR multiplier was measured and cannot move
-- the forge optimum at any strength -- only compounding creates the fork
-- between sniper and grinder builds (ledger L-016).
function RollService.streakMultiplier(streak: number, b: number): number
	if not ForgeMath.isFinite(streak) or not ForgeMath.isFinite(b) then
		return 1
	end
	if streak <= 0 or b <= 0 then
		return 1
	end
	local capped = math.min(streak, RollService.STREAK_CAP)
	local m = (1 + b) ^ capped
	if not ForgeMath.isFinite(m) or m > RollService.MAX_STREAK_MULTIPLIER then
		return RollService.MAX_STREAK_MULTIPLIER
	end
	return m
end

function RollService.streakStrengthToB(level: number): number
	if not ForgeMath.isFinite(level) or level <= 0 then
		return 0
	end
	return level * RollService.B_PER_LEVEL
end

-- A face at or near the mass floor is a Void (SRS FR-5.2). Because it is the
-- lightest face it lands most often -- the visible cost of concentrating mass.
function RollService.isVoidFace(die: Die, faceIndex: number, massFloor: number?): boolean
	local faces = die.Faces
	local floor = massFloor or RollService.MASS_FLOOR
	local lightest = 1
	for i = 2, #faces do
		if faces[i].Mass < faces[lightest].Mass then
			lightest = i
		end
	end
	if faceIndex ~= lightest then
		return false
	end
	-- Proximity test: a flat, un-forged die has no face near the floor and so
	-- has NO Void. Only mass deliberately stripped off a face creates one --
	-- which is the design intent: the Void is the visible cost of concentrating
	-- mass elsewhere, not a tax on players who have not forged yet.
	return faces[lightest].Mass <= floor * RollService.VOID_FLOOR_FACTOR
end

--------------------------------------------------------------------------------
-- PURE: sampling
--------------------------------------------------------------------------------

-- Samples one face per die. `rng` is injected so a seeded test reproduces
-- exactly and so no hidden global RNG can drift between runs.
function RollService.sampleOutcomes(dice: { Die }, rng: Random): { DieOutcome }
	local outcomes: { DieOutcome } = {}
	for d = 1, #dice do
		local die = dice[d]
		local masses = table.create(#die.Faces)
		for f = 1, #die.Faces do
			masses[f] = die.Faces[f].Mass
		end
		local faceIndex = ForgeMath.sampleFace(masses, rng)
		local face = die.Faces[faceIndex]
		outcomes[d] = {
			dieIndex = d,
			faceIndex = faceIndex,
			mass = face.Mass,
			element = face.Element,
			baseValue = ForgeMath.faceValue(face.Mass),
		}
	end
	return outcomes
end

--------------------------------------------------------------------------------
-- PURE: element resolution across the resolved face set
--------------------------------------------------------------------------------

-- Returns additive contribution, multiplicative factor, the element ids that
-- actually fired, and the die index frozen for next throw (if any).
--
-- Gold is the load-bearing case: it pays ONLY when two or more Gold faces
-- landed, and scales with their COMBINED mass. A flat conditional bonus is
-- algebraically inert -- the partner's trigger probability enters as a constant
-- multiplier and cannot shift any optimum. That was measured across three
-- models before it was believed (SRS FR-4.3, ledger L-016).
function RollService.resolveElements(outcomes: { DieOutcome }): (number, number, { string }, number?)
	local additive = 0.0
	local factor = 1.0
	local fired: { string } = {}
	local frozenDie: number? = nil

	local goldCount, goldMass = 0, 0.0
	for _, o in ipairs(outcomes) do
		if o.element == "Gold" then
			goldCount += 1
			goldMass += o.mass
		end
	end
	if goldCount >= 2 then
		local bonus = ElementCatalog.goldPayoff(goldCount, goldMass)
		if ForgeMath.isFinite(bonus) and bonus > 0 then
			additive += bonus
			table.insert(fired, "Gold")
		end
	end

	local otherCount = #outcomes - 1
	for _, o in ipairs(outcomes) do
		if o.element == "Fire" and otherCount > 0 then
			local spill = ElementCatalog.firePayoff(o.baseValue, otherCount)
			if ForgeMath.isFinite(spill) and spill > 0 then
				additive += spill
				table.insert(fired, "Fire")
			end
		elseif o.element == "Multiplier" then
			local f = ElementCatalog.multiplierFactor(o.mass)
			if ForgeMath.isFinite(f) and f > 0 then
				factor *= f
				table.insert(fired, "Multiplier")
			end
		elseif o.element == "Freeze" and #outcomes > 1 then
			-- Locks a DIFFERENT die for the next throw. Picks the highest-value
			-- partner, which is deterministic and needs no positional state.
			local best, bestVal = nil, -1
			for _, other in ipairs(outcomes) do
				if other.dieIndex ~= o.dieIndex and other.baseValue > bestVal then
					best, bestVal = other.dieIndex, other.baseValue
				end
			end
			if best then
				frozenDie = best
				table.insert(fired, "Freeze")
			end
		end
	end

	return additive, factor, fired, frozenDie
end

--------------------------------------------------------------------------------
-- PURE: the whole throw
--------------------------------------------------------------------------------

export type ThrowConfig = {
	streak: number,
	streakStrengthLevel: number,
	hasShield: boolean,
	shieldReady: boolean,
	coinBonus: number?,   -- multiplicative, defaults to 1
}

-- The complete payout computation, with no Roblox dependency beyond Random.
-- UT-3 and UT-4 drive this directly.
function RollService.computeThrow(dice: { Die }, rng: Random, cfg: ThrowConfig): ThrowResult
	local outcomes = RollService.sampleOutcomes(dice, rng)

	local baseTotal = 0.0
	for _, o in ipairs(outcomes) do
		baseTotal += o.baseValue
	end

	local additive, factor, fired, frozenDie = RollService.resolveElements(outcomes)

	-- Void detection: ANY die landing its lightest face breaks the streak.
	local voidHit = false
	for _, o in ipairs(outcomes) do
		if RollService.isVoidFace(dice[o.dieIndex], o.faceIndex) then
			voidHit = true
			break
		end
	end

	-- Shield absorbs exactly one break, then goes on cooldown (SRS FR-5.6).
	local breaks = voidHit
	if voidHit and cfg.hasShield and cfg.shieldReady then
		breaks = false
	end

	local newStreak = if breaks then 0 else cfg.streak + 1
	local b = RollService.streakStrengthToB(cfg.streakStrengthLevel)
	-- The multiplier applies to the streak the throw LANDS on. A broken streak
	-- pays at 1x, which is what makes a Void sting.
	local streakMult = RollService.streakMultiplier(newStreak, b)

	local coin = cfg.coinBonus or 1
	if not ForgeMath.isFinite(coin) or coin <= 0 then
		coin = 1
	end

	local payout = (baseTotal + additive) * factor * streakMult * coin
	if not ForgeMath.isFinite(payout) or payout < 0 then
		payout = 0
	end

	return {
		outcomes = outcomes,
		baseTotal = baseTotal,
		elementTotal = additive,
		multiplier = factor,
		streakMultiplier = streakMult,
		payout = payout,
		voidHit = voidHit,
		streak = newStreak,
		elementsFired = fired,
		frozenDie = frozenDie,
	}
end

--------------------------------------------------------------------------------
-- SERVICE SHELL: transient per-session state, then the wired entry point.
-- Streak and shield timing are DELIBERATELY not persisted -- they are
-- session-scoped, so a rejoin cannot be used to farm a fresh shield.
--------------------------------------------------------------------------------

type Session = {
	streak: number,
	lastShieldUse: number,
	frozenDie: number?,
	rng: Random,
	rollsThisSession: number,
	earnedThisSession: number,
	sessionStart: number,
}

local sessions: { [Player]: Session } = {}

function RollService.beginSession(player: Player): ()
	sessions[player] = {
		streak = 0,
		lastShieldUse = -math.huge,
		frozenDie = nil,
		-- Seeded from the server clock only. No client value participates.
		rng = Random.new(),
		rollsThisSession = 0,
		earnedThisSession = 0,
		sessionStart = os.clock(),
	}
end

function RollService.endSession(player: Player): ()
	sessions[player] = nil
end

function RollService.getStreak(player: Player): number
	local s = sessions[player]
	return if s then s.streak else 0
end

-- Rolling average income per second, fed to the offline vault (SRS FR-8.2).
function RollService.averageIncomePerSecond(player: Player): number
	local s = sessions[player]
	if not s then
		return 0
	end
	local elapsed = os.clock() - s.sessionStart
	if elapsed <= 0 then
		return 0
	end
	-- Divide by at least MIN_RATE_WINDOW. A short session cannot manufacture a
	-- huge rate by dividing a real payout by a near-zero elapsed time
	-- (threat T-30). This makes the early-session rate CONSERVATIVE, which is
	-- the correct direction to be wrong in for an offline-earnings input.
	local window = math.max(elapsed, RollService.MIN_RATE_WINDOW)
	local rate = s.earnedThisSession / window
	if not ForgeMath.isFinite(rate) or rate < 0 then
		return 0
	end
	return math.min(rate, RollService.MAX_RATE)
end

-- The wired entry point. Returns ok, reason. Called by RemoteGateway's `Roll`
-- handler, which has already rate-limited (threat T-3).
function RollService.performRoll(player: Player): (boolean, string?)
	local session = sessions[player]
	if not session then
		return false, Remotes.Notice.ProfileUnavailable
	end

	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end

	local dice = data.Dice
	if type(dice) ~= "table" or #dice == 0 then
		return false, Remotes.Notice.InvalidRequest
	end

	local now = os.clock()
	local hasShield = data.Diamond ~= nil and (data.Upgrades.BadRollShield or 0) > 0
	local shieldReady = hasShield and (now - session.lastShieldUse) >= RollService.SHIELD_COOLDOWN

	local result = RollService.computeThrow(dice :: any, session.rng, {
		streak = session.streak,
		streakStrengthLevel = data.Diamond.StreakStrength,
		hasShield = hasShield,
		shieldReady = shieldReady,
		coinBonus = 1,
	})

	-- Shield consumed only when it actually prevented a break.
	if result.voidHit and hasShield and shieldReady then
		session.lastShieldUse = now
	end

	session.streak = result.streak
	session.frozenDie = result.frozenDie
	session.rollsThisSession += 1
	session.earnedThisSession += result.payout

	-- Cash is credited BEFORE the event fires. If the client never receives
	-- RollResult -- disconnect, lag, tab-out -- the player still has the money
	-- (SRS FR-2.6). Presentation is downstream of truth.
	if result.payout > 0 then
		local credited, reason = EconomyService.credit(player, "Cash", result.payout, "roll")
		if not credited then
			return false, reason
		end
	end
	EconomyService.recordRoll(player, result.payout)

	PlayerProfile.mutate(player, function(d)
		d.Vault.AvgIncomePerSec = RollService.averageIncomePerSecond(player)
	end)

	local faces = table.create(#result.outcomes)
	for i, o in ipairs(result.outcomes) do
		faces[i] = o.faceIndex
	end

	Remotes.getEvent("RollResult"):FireClient(player, {
		faces = faces,
		payout = result.payout,
		streak = result.streak,
		multiplier = result.streakMultiplier,
		elementsFired = result.elementsFired,
		voidHit = result.voidHit,
	})

	return true, nil
end

return RollService
