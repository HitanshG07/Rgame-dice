--!strict
-- UpgradeView.luau
-- The read-only view model behind the UPGRADES panel: for one upgrade id, what
-- it costs the player right now, what a level of it actually does, and whether
-- they can pay for it.
--
-- WHY THIS MODULE EXISTS. Seven of the nine upgrades in the game had no buy
-- path at all. Every one of them was finished server-side -- costed, capped,
-- reset on ascension, wired to a real effect -- and the client reached exactly
-- two of them: `buyUpgrade("MassBudget")`, hardcoded to that single id, and
-- `buyDiamondNode(shapeId)`, which lands in the SHAPE-UNLOCK branch of the
-- handler and never touches a node. `getAllDiamondNodes()` had zero callers
-- anywhere in the repository. The accessors were written for a panel nobody
-- built, and `StreakStrength` being unreachable is why `b` is permanently 0 and
-- the streak multiplier is 1x for every player forever (FR-5.4).
--
-- NOTHING HERE NAMES AN UPGRADE IN ORDER TO LIST IT. The rows come from
-- enumerating the catalog, so an id added to `UpgradeCatalog` appears in the
-- panel with no edit here and no edit in the panel. That is deliberate: a
-- hand-written list of ids is the producer-outward failure this project has
-- already paid for twice -- it reads as complete and silently drifts. The only
-- per-id knowledge in this file is the effect blurb, and an id without one
-- falls back to the catalog's own display name rather than rendering blank.
--
-- NFR-5: NOT ONE FIGURE HERE CROSSES THE WIRE. Costs are computed from
-- `UpgradeCatalog`, which client and server both require; levels and balances
-- come from the state snapshot the client already receives. The server
-- re-derives every one of these before it charges, from the same functions, so
-- a row cannot quote a price the server then rejects -- which is the SLOT-2
-- defect class.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpgradeCatalog = require(Shared:WaitForChild("UpgradeCatalog"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local StreakMath = require(Shared:WaitForChild("StreakMath"))
local VaultCatalog = require(Shared:WaitForChild("VaultCatalog"))

local UpgradeView = {}

-- Which catalog a row came from, and therefore which remote buys it and which
-- balance pays for it. Not a display string -- the panel derives its labels
-- from this, and `ServerBootstrap` has one handler per value.
export type Kind = "Cash" | "Diamond"

export type Status = {
	level: number,
	maxLevel: number,
	atMax: boolean,
	-- nil at max level, never `math.huge`. The catalog returns infinity there as
	-- a sentinel and the panel must render "MAX", not "$inf".
	cost: number?,
	affordable: boolean,
	balance: number,
	currency: string,
	detail: string,
}

--------------------------------------------------------------------------------
-- Effect blurbs
--
-- Every number in these strings is read from the shared constant the effect
-- actually uses, never retyped. A panel that states a figure the game does not
-- honour is the same defect as the fabricated "+$2,500 CASH" quest reward that
-- was removed -- a surface asserting something untrue -- and a literal here
-- would go stale the first time anyone tuned the constant.
--
-- `AutoRollSpeed` is described without a figure ON PURPOSE. Its per-level step
-- lives on `RollService`, which is server-only and which the client cannot
-- require, so there is no shared constant to read. A number invented to fill
-- the gap is exactly what this file exists to prevent.
--------------------------------------------------------------------------------

local CASH_DETAIL: { [string]: string } = {
	MassBudget = string.format(
		"+%d mass budget on every die you own, up to each shape's Cash cap.",
		UpgradeCatalog.MASS_PER_LEVEL),
	AutoRollSpeed =
		"Shortens the gap between automatic rolls. Requires the Auto-Roll pass to have any effect.",
	VaultCapacity = string.format(
		"+%.1fh of offline vault storage per level (base %dh).",
		VaultCatalog.UPGRADE_CAPACITY_PER_LEVEL_SEC / 3600,
		math.floor(VaultCatalog.BASE_CAPACITY_SEC / 3600)),
	VaultEfficiency = string.format(
		"+%d%% of your earning rate while offline (base %d%%, hard cap %d%%).",
		math.floor(VaultCatalog.UPGRADE_EFFICIENCY_PER_LEVEL * 100 + 0.5),
		math.floor(VaultCatalog.BASE_EFFICIENCY * 100 + 0.5),
		math.floor(VaultCatalog.MAX_EFFICIENCY * 100 + 0.5)),
	BadRollShield =
		"A Void face still pays nothing, but it no longer breaks your streak.",
}

local DIAMOND_DETAIL: { [string]: string } = {
	StreakStrength = string.format(
		"+%.2f to streak growth b. Payout multiplies by (1+b)^streak, streak capped at %d. "
			.. "At level 0 that multiplier is exactly 1x.",
		StreakMath.B_PER_LEVEL, StreakMath.STREAK_CAP),
	MassCeiling = string.format(
		"Raises every die's mass ceiling by %d and grants that mass immediately, "
			.. "up to the shape's own limit.",
		DiceCatalog.MASS_CEILING_PER_LEVEL),
	SlotNodes = string.format(
		"+1 die slot on top of your ascension count (hard cap %d slots).",
		DiceCatalog.MAX_DIE_SLOTS),
}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- The upgrades of one kind, in a STABLE order.
--
-- Both catalog accessors build their list with `pairs`, so their order is
-- whatever the hash happens to give and differs between runs. A panel that
-- creates its rows once from an unstable list puts the same upgrade in a
-- different place every session, and a test that pins a row by index is
-- meaningless. Sorted by cost then id, which is also the order a player meets
-- them in: cheapest first.
--
-- SORTED, NOT LISTED. There is no id written down here, so an upgrade added to
-- the catalog -- `Luck` is being restored as this is written -- appears in the
-- panel without this function being touched.
function UpgradeView.rows(kind: Kind): { UpgradeCatalog.CashUpgradeDef }
	local defs = if kind == "Diamond"
		then (UpgradeCatalog.getAllDiamondNodes() :: any)
		else (UpgradeCatalog.getAllCashUpgrades() :: any)
	table.sort(defs, function(a, b): boolean
		if a.baseCost ~= b.baseCost then
			return a.baseCost < b.baseCost
		end
		return a.id < b.id
	end)
	return defs
end

-- The player's current level in one upgrade, read from the snapshot.
--
-- The two kinds live in different places in the payload -- Cash levels in
-- `upgrades`, nodes in `diamondTree` -- because they live in different places
-- in the profile, and `StateSyncService` copies each field explicitly. Absent
-- means zero: a profile that has never bought one has no key for it.
function UpgradeView.levelOf(kind: Kind, id: string, state: any): number
	if type(state) ~= "table" then
		return 0
	end
	local source = if kind == "Diamond" then state.diamondTree else state.upgrades
	if type(source) ~= "table" then
		return 0
	end
	local level = tonumber(source[id])
	if level == nil or level ~= level or level < 0 then
		return 0
	end
	return math.floor(level)
end

-- Everything one row needs to draw itself and decide whether its button works.
--
-- The cost is taken from the SAME catalog function the handler calls with the
-- SAME level, so the quote on screen and the charge on the server are one
-- expression evaluated twice rather than two expressions that agree by luck.
-- `affordable` uses `>=` to match `EconomyService.canAfford`, so a player
-- holding exactly the price is offered the purchase the server will accept.
function UpgradeView.status(kind: Kind, id: string, state: any): Status?
	local isDiamond = kind == "Diamond"
	local def: any = if isDiamond
		then UpgradeCatalog.getDiamondNode(id)
		else UpgradeCatalog.getCashUpgrade(id)
	if def == nil then
		return nil
	end

	local level = UpgradeView.levelOf(kind, id, state)
	local atMax = level >= def.maxLevel

	local rawCost = if isDiamond
		then UpgradeCatalog.getDiamondNodeCost(id, level)
		else UpgradeCatalog.getCashUpgradeCost(id, level)
	-- `math.huge` is the catalog's way of saying "there is no next level". It is
	-- a sentinel, not a price, and must never reach a label.
	local cost: number? = if rawCost == math.huge or rawCost ~= rawCost then nil else rawCost

	local balance = 0
	if type(state) == "table" then
		balance = tonumber(if isDiamond then state.diamonds else state.cash) or 0
	end

	return {
		level = level,
		maxLevel = def.maxLevel,
		atMax = atMax,
		cost = cost,
		affordable = cost ~= nil and balance >= cost,
		balance = balance,
		currency = if isDiamond then "Diamonds" else "Cash",
		detail = (if isDiamond then DIAMOND_DETAIL[id] else CASH_DETAIL[id]) or def.name,
	}
end

return UpgradeView
