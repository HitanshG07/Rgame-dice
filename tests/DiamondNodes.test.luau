--!strict
-- DiamondNodes.test.luau
-- Phase 0b: the two Diamond nodes that charged for nothing.
--
-- WHY THIS SUITE EXISTS. `Diamond.MassCeiling` and `Diamond.SlotNodes` were both
-- purchasable, both persisted, and both had exactly ONE read in the entire
-- codebase -- in `StateSyncService`, echoing the number back to the client for
-- display. Every check that actually decided anything used a flat constant
-- (`shape.diamondCeiling`) or counted ascensions alone. A player could max both
-- trees and nothing about their dice or their slots would change.
--
-- That is the shape L-027 names: the requirement was specified, the READ was
-- implemented, the WRITE was missing -- except here it is the reverse, the write
-- was implemented and nothing read it. Both fail the same way, silently, because
-- a stored number that nobody consults looks identical to one that works.
--
-- So these assertions deliberately compare the node level against the thing it
-- is supposed to MOVE, never against itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local UpgradeCatalog = require(Shared:WaitForChild("UpgradeCatalog"))

local DiamondNodesTest = {}

function DiamondNodesTest.run(): (boolean, string?, number)
	local asserts = 0
	local function check(cond: boolean, msg: string)
		asserts += 1
		if not cond then
			error(msg, 2)
		end
	end

	local shapeId = "D6"
	local shape = DiceCatalog.getShape(shapeId)
	check(shape ~= nil, "D6 must exist in the catalog")
	local cashCap = (shape :: any).cashBudgetCap
	local diamondCap = (shape :: any).diamondCeiling

	----------------------------------------------------------------------------
	-- 1. MassCeiling spans exactly the gap FR-3.6 describes
	----------------------------------------------------------------------------

	-- "Purchased with Cash up to a per-shape cap, AND BEYOND THAT with Prestige
	-- Diamonds." Level 0 must land exactly where the Cash path stops -- not
	-- above it (which would hand out free budget) and not below it (which would
	-- strand budget a player already bought with Cash).
	check(DiceCatalog.massCeilingFor(shapeId, 0) == cashCap, string.format(
		"at level 0 the ceiling must equal the Cash cap (%d), so the Diamond tier "
		.. "begins exactly where the Cash tier ends", cashCap))

	local maxLevel = (UpgradeCatalog.getDiamondNode("MassCeiling") :: any).maxLevel
	check(maxLevel == 15, "MassCeiling is expected to have 15 levels")

	-- And the top must land exactly on the value that used to apply to everyone
	-- flat. That is the whole design of this fix: 1500 stops being the default
	-- and becomes the reward for maxing the tree.
	check(DiceCatalog.massCeilingFor(shapeId, maxLevel) == diamondCap, string.format(
		"at max level the ceiling must equal the shape's diamondCeiling (%d) -- "
		.. "the flat value becomes the MAX rather than the default", diamondCap))

	-- 15 levels x 80 must actually close the gap, with no rounding slop left.
	check(maxLevel * DiceCatalog.MASS_CEILING_PER_LEVEL == diamondCap - cashCap,
		"15 levels at MASS_CEILING_PER_LEVEL must span the cap gap exactly")

	-- Monotonic, and moving by the stated amount every single level. A node that
	-- rose only on some levels would still "work" on a spot check.
	for lvl = 1, maxLevel do
		local prev = DiceCatalog.massCeilingFor(shapeId, lvl - 1)
		local curr = DiceCatalog.massCeilingFor(shapeId, lvl)
		check(curr - prev == DiceCatalog.MASS_CEILING_PER_LEVEL, string.format(
			"level %d must raise the ceiling by exactly %d (got %d)",
			lvl, DiceCatalog.MASS_CEILING_PER_LEVEL, curr - prev))
	end

	-- Past max it must not keep climbing. The clamp is what keeps every die
	-- inside `maxDiamondCeiling`, which is the bound the die validator uses.
	check(DiceCatalog.massCeilingFor(shapeId, maxLevel + 50) == diamondCap,
		"the ceiling must clamp at diamondCeiling however high the level goes")
	check(DiceCatalog.massCeilingFor(shapeId, maxLevel) <= DiceCatalog.maxDiamondCeiling(),
		"the raised ceiling must never exceed the absolute bound the die "
		.. "validator checks against, or a legally-bought die would fail validation")

	-- Junk in, floor out. These reach the function from a saved profile.
	check(DiceCatalog.massCeilingFor(shapeId, -5) == cashCap,
		"a negative level must floor to the Cash cap, never below it")
	check(DiceCatalog.massCeilingFor(shapeId, 0 / 0) == cashCap,
		"NaN must floor to the Cash cap rather than propagate")
	check(DiceCatalog.massCeilingFor("NotAShape", 5) == 0,
		"an unknown shape must return 0 rather than inventing a ceiling")

	----------------------------------------------------------------------------
	-- 2. SlotNodes actually adds slots, and cannot break the spec cap
	----------------------------------------------------------------------------

	local base = DiceCatalog.BASE_DIE_SLOT_CAP

	check(DiceCatalog.dieSlotCapFor(0, 0) == base,
		"no ascensions and no nodes must give the base cap")
	check(DiceCatalog.dieSlotCapFor(0) == base,
		"omitting slotNodes must behave exactly as passing 0, so the existing "
		.. "call sites keep their old meaning")

	-- The defect: this used to ignore the second argument entirely.
	check(DiceCatalog.dieSlotCapFor(0, 1) == base + 1,
		"one SlotNodes level must add exactly one slot -- this is the read that "
		.. "no code performed")
	check(DiceCatalog.dieSlotCapFor(2, 3) == base + 5,
		"ascensions and nodes must both count, and add together")

	-- SRS FR-1.1 says 1..12 dice. The tree must not be able to break that.
	local nodeMax = (UpgradeCatalog.getDiamondNode("SlotNodes") :: any).maxLevel
	check(nodeMax == 4, "SlotNodes is expected to have 4 levels")
	check(DiceCatalog.dieSlotCapFor(999, nodeMax) == DiceCatalog.MAX_DIE_SLOTS,
		"the hard cap must hold no matter how much the tree grants -- this is "
		.. "what keeps SRS FR-1.1 true")
	check(DiceCatalog.dieSlotCapFor(0, 9999) == DiceCatalog.MAX_DIE_SLOTS,
		"an absurd stored node level must clamp, not overflow the cap")

	check(DiceCatalog.dieSlotCapFor(0, -3) == base,
		"a negative node level must floor to 0 rather than REMOVE slots -- "
		.. "confiscation is the one outcome this must never produce")

	----------------------------------------------------------------------------
	-- 3. The slot PRICE must see the node too
	----------------------------------------------------------------------------

	-- Without threading the node through, this reports "at the cap, nothing to
	-- price" while the player's tree has already raised the cap -- and the panel
	-- silently hides a slot they can afford.
	local atOldCap = base -- owns exactly the no-node cap
	check(DiceCatalog.dieSlotCost(atOldCap, 0, 0) == nil,
		"with no nodes, owning the base cap means there is no next slot to price")
	check(DiceCatalog.dieSlotCost(atOldCap, 0, 1) ~= nil,
		"with one node level the next slot MUST have a price -- otherwise the "
		.. "panel hides a slot the player has already paid to unlock")

	return true, nil, asserts
end

return {
	name = "DiamondNodes.test",
	run = DiamondNodesTest.run,
}
