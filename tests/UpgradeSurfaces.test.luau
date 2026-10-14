--!strict
-- UpgradeSurfaces.test.luau
-- The purchase surfaces for the seven upgrades nothing could reach.
--
-- WHY THIS SUITE EXISTS. Seven of the nine upgrades in the game had no buy path
-- of any kind. The client's entire purchase surface was two call sites:
-- `buyUpgrade("MassBudget")`, hardcoded to that one id, and
-- `buyDiamondNode(shapeId)` -- a SHAPE id, which lands in the shape-unlock
-- branch of the handler and never reaches a node. `getAllDiamondNodes()`, the
-- enumerator a tree panel would loop, had zero callers anywhere.
--
-- The consequence that mattered most: `StreakStrength` was unbuyable, so `b`
-- was 0 for every player, so `(1+b)^streak` was 1 for every player forever, and
-- the sniper/grinder fork `FR-5.4` calls "the primary build-defining axis" did
-- not exist in the shipped game.
--
-- WHAT THESE ASSERTIONS ARE BUILT FROM. Not from a list of what the panel
-- contains -- that is the producer-outward direction this project has already
-- lost two audit rounds to. They are built from what the PLAYER pressing a
-- button needs to be true, and each one compares the surface against the thing
-- it is supposed to move:
--
--   1. every upgrade the catalog defines is offered, with no id written down
--   2. the row order is stable between runs
--   3. the price quoted equals the price the handler will charge, at every level
--   4. the id sent lands in the NODE branch, not the shape-unlock branch
--   5. affordability matches `EconomyService.canAfford` exactly, at the boundary
--   6. levels are read from the snapshot field that actually carries them
--   7. every row says something, including an id nobody wrote a blurb for
--   8. the nodes move what the panel says they move
--
-- The UI itself -- that the overlay draws, that the pod does not overlap, that
-- the button opens the panel -- cannot be asserted from a headless suite and is
-- named for eye verification in the handover report.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpgradeCatalog = require(Shared:WaitForChild("UpgradeCatalog"))
local UpgradeView = require(Shared:WaitForChild("UpgradeView"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local StreakMath = require(Shared:WaitForChild("StreakMath"))

local UpgradeSurfacesTest = {}

function UpgradeSurfacesTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	----------------------------------------------------------------------------
	-- 1. EVERY UPGRADE THE CATALOG DEFINES IS OFFERED
	--
	-- The panel must not be able to go stale. `rows()` is compared against the
	-- catalog itself rather than against a list of expected ids, so an upgrade
	-- added to `UpgradeCatalog` -- `Luck` is being restored in parallel with
	-- this work -- is covered here without this file being edited.
	----------------------------------------------------------------------------

	local function idSet(defs: { any }): ({ [string]: boolean }, number)
		local set: { [string]: boolean } = {}
		local n = 0
		for _, d in ipairs(defs) do
			check(set[d.id] ~= true, "duplicate id in rows: " .. tostring(d.id))
			set[d.id] = true
			n += 1
		end
		return set, n
	end

	local catalogCash, cashCount = idSet(UpgradeCatalog.getAllCashUpgrades())
	local catalogDiamond, diamondCount = idSet(UpgradeCatalog.getAllDiamondNodes())

	-- A silently empty panel is the exact failure this whole change exists to
	-- end, and it would otherwise satisfy every assertion below vacuously.
	check(cashCount > 0, "the Cash catalog must define at least one upgrade")
	check(diamondCount > 0, "the Diamond catalog must define at least one node")

	local rowCash, rowCashCount = idSet(UpgradeView.rows("Cash"))
	local rowDiamond, rowDiamondCount = idSet(UpgradeView.rows("Diamond"))

	check(rowCashCount == cashCount, string.format(
		"the Cash section must offer every Cash upgrade: catalog has %d, panel rows %d",
		cashCount, rowCashCount))
	check(rowDiamondCount == diamondCount, string.format(
		"the Diamond section must offer every node: catalog has %d, panel rows %d",
		diamondCount, rowDiamondCount))

	for id in pairs(catalogCash) do
		check(rowCash[id] == true, "Cash upgrade is defined but not offered: " .. id)
	end
	for id in pairs(catalogDiamond) do
		check(rowDiamond[id] == true, "Diamond node is defined but not offered: " .. id)
	end

	-- The named casualties, pinned by hand on top of the enumeration above. If
	-- someone re-hardcodes the surface to one id, the counts might still agree
	-- while these do not.
	for _, id in ipairs({ "MassBudget", "AutoRollSpeed", "VaultCapacity", "VaultEfficiency" }) do
		check(rowCash[id] == true, string.format(
			"%s was unreachable before this panel and must be offered by it", id))
	end
	for _, id in ipairs({ "StreakStrength", "MassCeiling", "SlotNodes" }) do
		check(rowDiamond[id] == true, string.format(
			"%s was unreachable before this panel and must be offered by it", id))
	end

	----------------------------------------------------------------------------
	-- 2. THE ROW ORDER IS STABLE
	--
	-- Both catalog accessors build their list with `pairs`, whose order is the
	-- hash's and differs between runs. The panel creates its rows ONCE, so an
	-- unstable list puts the same upgrade somewhere different every session.
	----------------------------------------------------------------------------

	for _, kind in ipairs({ "Cash", "Diamond" }) do
		local first = UpgradeView.rows(kind :: any)
		local second = UpgradeView.rows(kind :: any)
		check(#first == #second, kind .. ": row count must not vary between calls")
		for i = 1, #first do
			check(first[i].id == second[i].id, string.format(
				"%s: row %d must be the same upgrade on every call (%s vs %s)",
				kind, i, first[i].id, second[i].id))
		end
		-- And the order is the stated one: cheapest first, id breaking ties.
		for i = 2, #first do
			local prev, cur = first[i - 1], first[i]
			local ordered = (prev.baseCost < cur.baseCost)
				or (prev.baseCost == cur.baseCost and prev.id < cur.id)
			check(ordered, string.format(
				"%s: rows must be ordered by cost then id, but %s (%d) precedes %s (%d)",
				kind, prev.id, prev.baseCost, cur.id, cur.baseCost))
		end
	end

	----------------------------------------------------------------------------
	-- 3. THE QUOTED PRICE IS THE PRICE THE HANDLER WILL CHARGE
	--
	-- SLOT-2 is the defect class: the client quoted a cost the server then
	-- refused, and the press produced no visible change at all. `BuyUpgrade`
	-- charges `getCashUpgradeCost(id, data.Upgrades[id] or 0)` and
	-- `BuyDiamondNode` charges `getDiamondNodeCost(id, data.Diamond[id] or 0)`.
	-- Checked at EVERY level, not just level 0, because the cost curve is
	-- exponential and an off-by-one in the level would agree at the start.
	----------------------------------------------------------------------------

	local function stateWith(cash: number, diamonds: number, upgrades: any, tree: any): any
		return { cash = cash, diamonds = diamonds, upgrades = upgrades, diamondTree = tree }
	end

	for _, def in ipairs(UpgradeView.rows("Cash")) do
		for level = 0, def.maxLevel do
			local st = UpgradeView.status("Cash", def.id, stateWith(0, 0, { [def.id] = level }, {}))
			check(st ~= nil, "Cash status must resolve for " .. def.id)
			local status = st :: any
			check(status.level == level, string.format(
				"%s: the panel must read level %d from the snapshot, got %d",
				def.id, level, status.level))

			local serverCost = UpgradeCatalog.getCashUpgradeCost(def.id, level)
			if level >= def.maxLevel then
				-- The handler refuses at `currentLvl >= maxLevel`, and the catalog
				-- returns infinity. Infinity is a sentinel, not a price, and must
				-- never reach a label.
				check(status.atMax, def.id .. ": must report MAX at its top level")
				check(status.cost == nil, def.id
					.. ": must not quote a price at max level (the handler refuses)")
				check(serverCost == math.huge, def.id
					.. ": the catalog is expected to return infinity past max level")
			else
				check(not status.atMax, string.format("%s: level %d is not max", def.id, level))
				check(status.cost == serverCost, string.format(
					"%s at level %d: panel quotes %s, handler charges %s",
					def.id, level, tostring(status.cost), tostring(serverCost)))
			end
			check(status.currency == "Cash", def.id .. ": Cash upgrades are paid in Cash")
		end
	end

	for _, def in ipairs(UpgradeView.rows("Diamond")) do
		for level = 0, def.maxLevel do
			local st = UpgradeView.status("Diamond", def.id, stateWith(0, 0, {}, { [def.id] = level }))
			check(st ~= nil, "Diamond status must resolve for " .. def.id)
			local status = st :: any
			check(status.level == level, string.format(
				"%s: the panel must read level %d from the snapshot, got %d",
				def.id, level, status.level))

			local serverCost = UpgradeCatalog.getDiamondNodeCost(def.id, level)
			if level >= def.maxLevel then
				check(status.atMax, def.id .. ": must report MAX at its top level")
				check(status.cost == nil, def.id
					.. ": must not quote a price at max level (the handler refuses)")
			else
				check(status.cost == serverCost, string.format(
					"%s at level %d: panel quotes %s, handler charges %s",
					def.id, level, tostring(status.cost), tostring(serverCost)))
			end
			check(status.currency == "Diamonds", def.id .. ": nodes are paid in Diamonds")
		end
	end

	----------------------------------------------------------------------------
	-- 4. THE ID LANDS IN THE NODE BRANCH, NOT THE SHAPE-UNLOCK BRANCH
	--
	-- `BuyDiamondNode` is two handlers in one. Its first test is
	-- `DiceCatalog.getUnlockCost(nodeId) ~= nil`, and anything that passes it is
	-- treated as a shape unlock -- priced in CASH, checked against the unlock
	-- ladder, written into `Diamond.Shapes` as a boolean. The old client call
	-- site passed a shape id and never left that branch, which is why no node
	-- was ever bought.
	--
	-- So every id this panel can send must be invisible to `getUnlockCost`, and
	-- no shape id may be mistakable for a node. Both directions, because a
	-- future shape named after a node would break this as surely as the reverse.
	----------------------------------------------------------------------------

	for _, def in ipairs(UpgradeView.rows("Diamond")) do
		check(DiceCatalog.getUnlockCost(def.id) == nil, string.format(
			"%s must not be priced as a shape unlock, or BuyDiamondNode would "
				.. "charge Cash and write a boolean instead of buying the node", def.id))
		check(UpgradeCatalog.getDiamondNode(def.id) ~= nil,
			def.id .. " must resolve in the node catalog the handler reads")
	end

	for _, shape in ipairs(DiceCatalog.getAllShapes()) do
		check(UpgradeCatalog.getDiamondNode(shape.id) == nil, string.format(
			"shape %s must not also resolve as a Diamond node", shape.id))
		check(UpgradeView.status("Diamond", shape.id, nil) == nil, string.format(
			"the panel must refuse to build a node row for shape id %s", shape.id))
	end

	----------------------------------------------------------------------------
	-- 5. AFFORDABILITY MATCHES THE SERVER, AT THE BOUNDARY
	--
	-- `EconomyService.canAfford` is `balance >= cost`. A panel using `>` would
	-- grey out a purchase the server would have accepted; one using a tolerance
	-- would offer one it refuses.
	----------------------------------------------------------------------------

	local massCost0 = UpgradeCatalog.getCashUpgradeCost("MassBudget", 0)
	check(massCost0 > 0 and massCost0 < math.huge, "MassBudget must have a finite level-0 cost")

	local exact = UpgradeView.status("Cash", "MassBudget", stateWith(massCost0, 0, {}, {})) :: any
	check(exact.affordable, "holding exactly the price must be affordable, as canAfford uses >=")

	local oneShort = UpgradeView.status("Cash", "MassBudget", stateWith(massCost0 - 1, 0, {}, {})) :: any
	check(not oneShort.affordable, "one short of the price must not be affordable")

	-- Read from the catalog rather than written down, so retuning `maxLevel`
	-- does not quietly turn this into a check of some mid-tier level.
	local massMax = (UpgradeCatalog.getCashUpgrade("MassBudget") :: any).maxLevel
	local maxedOut = UpgradeView.status("Cash", "MassBudget",
		stateWith(math.huge, 0, { MassBudget = massMax }, {})) :: any
	check(not maxedOut.affordable,
		"a maxed upgrade is never affordable, however much Cash is held")

	local streakCost0 = UpgradeCatalog.getDiamondNodeCost("StreakStrength", 0)
	local dExact = UpgradeView.status("Diamond", "StreakStrength",
		stateWith(0, streakCost0, {}, {})) :: any
	check(dExact.affordable, "nodes must price against the Diamond balance, not Cash")
	local dWrongPurse = UpgradeView.status("Diamond", "StreakStrength",
		stateWith(1e12, 0, {}, {})) :: any
	check(not dWrongPurse.affordable, "Cash must not pay for a Diamond node")

	----------------------------------------------------------------------------
	-- 6. LEVELS COME FROM THE FIELD THAT ACTUALLY CARRIES THEM
	--
	-- `StateSyncService` puts Cash levels in `upgrades` and node levels in
	-- `diamondTree`, because that is where they live in the profile. Reading the
	-- wrong one reports level 0 forever, which looks exactly like a player who
	-- has bought nothing -- and would quote the level-0 price for an upgrade
	-- they have already maxed.
	----------------------------------------------------------------------------

	local crossed = stateWith(0, 0, { StreakStrength = 9 }, { MassBudget = 9 })
	check(UpgradeView.levelOf("Diamond", "StreakStrength", crossed) == 0,
		"a node level must not be read out of the Cash `upgrades` table")
	check(UpgradeView.levelOf("Cash", "MassBudget", crossed) == 0,
		"a Cash level must not be read out of `diamondTree`")

	local proper = stateWith(0, 0, { MassBudget = 3 }, { StreakStrength = 7 })
	check(UpgradeView.levelOf("Cash", "MassBudget", proper) == 3,
		"Cash levels come from `upgrades`")
	check(UpgradeView.levelOf("Diamond", "StreakStrength", proper) == 7,
		"node levels come from `diamondTree`")

	-- The panel builds its rows before any snapshot has arrived, and a player
	-- can open it in that window. Nothing may error and nothing may invent a
	-- level.
	for _, kind in ipairs({ "Cash", "Diamond" }) do
		for _, def in ipairs(UpgradeView.rows(kind :: any)) do
			local blank = UpgradeView.status(kind :: any, def.id, nil) :: any
			check(blank ~= nil, def.id .. ": must resolve with no snapshot at all")
			check(blank.level == 0, def.id .. ": no snapshot means level 0, not nil")
			check(blank.balance == 0, def.id .. ": no snapshot means no balance")
			check(not blank.affordable, def.id .. ": nothing is affordable with no snapshot")
			local junk = UpgradeView.status(kind :: any, def.id, "not a table") :: any
			check(junk ~= nil and junk.level == 0, def.id .. ": a junk snapshot must not error")
		end
	end

	----------------------------------------------------------------------------
	-- 7. EVERY ROW SAYS SOMETHING
	--
	-- Including an id nobody has written a blurb for. The blurb table is the one
	-- piece of per-id knowledge in the view model, and a per-id map built from
	-- the author's own list is precisely how this project has twice shipped a
	-- status map with a missing entry. The fallback to the catalog's display
	-- name is what makes a missing entry render a name instead of a blank, and
	-- this loop is driven by the CATALOG so a newly added id is covered the day
	-- it lands.
	----------------------------------------------------------------------------

	for _, kind in ipairs({ "Cash", "Diamond" }) do
		for _, def in ipairs(UpgradeView.rows(kind :: any)) do
			local status = UpgradeView.status(kind :: any, def.id, nil) :: any
			check(type(status.detail) == "string" and #status.detail > 0, string.format(
				"%s: every offered upgrade must describe itself", def.id))
			check(type(def.name) == "string" and #def.name > 0,
				def.id .. ": must have a display name to fall back to")
			check(def.maxLevel >= 1, def.id .. ": an upgrade with no levels cannot be bought")
		end
	end

	----------------------------------------------------------------------------
	-- 8. THE NODES MOVE WHAT THE PANEL SAYS THEY MOVE
	--
	-- A purchase surface over an inert number is worth nothing, which is the
	-- defect `DiamondNodes.test` was written for. These compare the node level
	-- against the gameplay function that reads it -- never against itself.
	----------------------------------------------------------------------------

	-- STREAKSTRENGTH. This is the one that was costing the game its primary
	-- build axis. Level 0 is exactly 1x -- the state every player has shipped in
	-- -- and every level after it must be strictly larger, or buying it from the
	-- new panel would charge Diamonds for nothing.
	local SAMPLE_STREAK = 10
	check(StreakMath.multiplier(SAMPLE_STREAK, StreakMath.streakStrengthToB(0)) == 1,
		"at StreakStrength 0 the multiplier is exactly 1x -- the shipped state, "
			.. "and the reason this panel exists")

	local streakDef = UpgradeCatalog.getDiamondNode("StreakStrength") :: any
	local previous = StreakMath.multiplier(SAMPLE_STREAK, StreakMath.streakStrengthToB(0))
	for level = 1, streakDef.maxLevel do
		local m = StreakMath.multiplier(SAMPLE_STREAK, StreakMath.streakStrengthToB(level))
		check(m > previous, string.format(
			"StreakStrength level %d must pay strictly more than level %d (%f vs %f)",
			level, level - 1, m, previous))
		previous = m
	end
	check(previous > 1, "a maxed StreakStrength must leave the 1x the game shipped with")

	-- MASSCEILING. The panel tells the player each level is worth
	-- MASS_CEILING_PER_LEVEL of ceiling. Checked against the authoritative
	-- reader, below the shape's hard clamp where the step is the full amount.
	local shapeId = "D6"
	local shape = DiceCatalog.getShape(shapeId) :: any
	check(shape ~= nil, "D6 must exist for this comparison")
	local step = DiceCatalog.MASS_CEILING_PER_LEVEL
	local movedAtLeastOnce = false
	for level = 0, ((UpgradeCatalog.getDiamondNode("MassCeiling") :: any).maxLevel - 1) do
		local here = DiceCatalog.massCeilingFor(shapeId, level)
		local next_ = DiceCatalog.massCeilingFor(shapeId, level + 1)
		check(next_ >= here, "the mass ceiling must never fall as the node is bought")
		if next_ < shape.diamondCeiling then
			check(next_ - here == step, string.format(
				"MassCeiling level %d -> %d must raise the ceiling by the %d the "
					.. "panel advertises, raised it by %d",
				level, level + 1, step, next_ - here))
			movedAtLeastOnce = true
		end
	end
	check(movedAtLeastOnce,
		"MassCeiling must raise D6's ceiling somewhere below its hard clamp, or "
			.. "the panel is selling a level that cannot move")

	-- SLOTNODES. +1 slot per level until MAX_DIE_SLOTS, which is what the panel
	-- says. Ascensions held at 0 so the node is the only thing moving.
	local slotDef = UpgradeCatalog.getDiamondNode("SlotNodes") :: any
	for level = 0, slotDef.maxLevel - 1 do
		local here = DiceCatalog.dieSlotCapFor(0, level)
		local next_ = DiceCatalog.dieSlotCapFor(0, level + 1)
		check(next_ - here == 1, string.format(
			"SlotNodes level %d -> %d must add exactly the 1 slot the panel "
				.. "advertises, added %d", level, level + 1, next_ - here))
		check(next_ <= DiceCatalog.MAX_DIE_SLOTS,
			"the node must never carry the cap past MAX_DIE_SLOTS")
	end
	check(DiceCatalog.dieSlotCapFor(0, slotDef.maxLevel) > DiceCatalog.dieSlotCapFor(0, 0),
		"a maxed SlotNodes must leave the player with more slots than they started")

	return true, nil, asserts
end

return {
	name = "UpgradeSurfaces.test",
	run = UpgradeSurfacesTest.run,
}
