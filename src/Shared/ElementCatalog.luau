--!strict
-- ElementCatalog.luau
-- Element definitions and their payoff functions. Pure data + pure maths.
--
-- THE BINDING RULE (SRS FR-4.3, ledger L-016): every conditional element's
-- payoff SCALES WITH THE COMBINED INVESTED MASS of the participating faces.
-- A flat conditional bonus is algebraically inert -- the partner die's trigger
-- probability enters as a constant multiplier on a term linear in one's own,
-- which cannot shift any optimum. That was measured across three separate
-- models before it was believed. A flat conditional bonus appearing here is
-- a DEFECT, not a tuning choice.
--
-- SECOND BINDING RULE (HLD §1): every element resolves from the RESOLVED FACE
-- SET alone. The server holds no die positions, velocities or collisions, so
-- an element that needs to know "which gap it struck" or "what is nearby"
-- cannot be built. Rejected at design time, not implemented.

local ElementCatalog = {}

export type ElementId = "None" | "Fire" | "Freeze" | "Gold" | "Multiplier"

export type Element = {
	id: string,
	displayName: string,
	-- true when the payoff depends on OTHER dice in the same throw
	conditional: boolean,
	-- tuning coefficient; meaning is per-element and documented below
	coefficient: number,
}

local CATALOG: { [string]: Element } = {
	None = { id = "None", displayName = "Plain", conditional = false, coefficient = 0 },

	-- Fire: spills a share of its own face value onto every other die.
	-- Unconditional, so it may be flat in the partner count.
	Fire = { id = "Fire", displayName = "Fire", conditional = false, coefficient = 0.25 },

	-- Gold: pays ONLY if at least one other die also landed Gold this throw,
	-- and the bonus scales with the COMBINED mass of every participating Gold
	-- face. This is the mass-coupling rule made concrete.
	Gold = { id = "Gold", displayName = "Gold", conditional = true, coefficient = 6.0 },

	-- Freeze: locks another die, re-rolling it next throw and keeping the
	-- better result. Worth more when partners are high-variance.
	Freeze = { id = "Freeze", displayName = "Freeze", conditional = true, coefficient = 1.0 },

	-- Multiplier: multiplies the throw total rather than adding to it.
	-- Scales with its own invested mass so it is not a flat switch.
	Multiplier = { id = "Multiplier", displayName = "Multiplier", conditional = false, coefficient = 0.02 },
}

function ElementCatalog.get(id: string): Element?
	return CATALOG[id]
end

function ElementCatalog.exists(id: string): boolean
	return CATALOG[id] ~= nil
end

function ElementCatalog.all(): { [string]: Element }
	return CATALOG
end

-- Gold payoff. `participatingMass` is the SUM of the mass on every Gold face
-- that landed this throw. Returns 0 when fewer than two Gold faces landed --
-- that is the whole point of a conditional element.
function ElementCatalog.goldPayoff(participatingCount: number, participatingMass: number): number
	if participatingCount < 2 then
		return 0
	end
	local def = CATALOG.Gold
	-- superlinear in combined mass, matching the forge's own value curve so
	-- investing in Gold competes properly against investing in cash faces
	return def.coefficient * (participatingMass ^ 2)
end

-- Fire spill: a share of the Fire face's own value, added to each other die.
function ElementCatalog.firePayoff(ownFaceValue: number, otherDiceCount: number): number
	if otherDiceCount <= 0 then
		return 0
	end
	return CATALOG.Fire.coefficient * ownFaceValue * otherDiceCount
end

-- Multiplier: returns the FACTOR applied to the throw total, never an addend.
-- 1.0 means no effect.
function ElementCatalog.multiplierFactor(ownMass: number): number
	return 1 + (CATALOG.Multiplier.coefficient * ownMass)
end

return ElementCatalog
