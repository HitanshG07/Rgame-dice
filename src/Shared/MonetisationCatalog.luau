--!strict
-- MonetisationCatalog.luau
-- Every gamepass and developer product the game sells, and what each one grants
-- (SRS FR-12; threats T-16, T-17).
--
-- WHY THIS IS SHARED AND NOT SERVER-ONLY. The client must be able to render a
-- shop -- names, descriptions, which passes are owned -- without inventing its
-- own parallel list that drifts from the server's. But note what is NOT here:
-- there are no prices. Roblox owns the price, the client reads it from the
-- platform, and a price in this file would be a number the game asserts and the
-- platform contradicts the moment it is changed on the dashboard.
--
-- NFR-5 is why the GRANT amounts live in this file but never cross the wire: the
-- server reads them, applies them, and sends the resulting balance. A client
-- message never carries a reward figure.
--
-- FR-12.6 -- FAIL CLOSED. An entry whose `assetId` is nil is UNRESOLVED: it does
-- not exist on the platform yet. Every path that could grant something checks
-- `isResolved` first and refuses. An unresolved product cannot be purchased
-- (Roblox has no id to sell) and, if one somehow arrived, grants nothing. The
-- point is that adding a row here is safe: nothing becomes purchasable until an
-- id is filled in deliberately.
--
-- T-17 -- this file DECLARES products; it does not process receipts. There is
-- exactly one `ProcessReceipt` assignment in the place and it lives in
-- `PurchaseService`. Nothing here may ever assign it.

local MonetisationCatalog = {}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type GrantKind =
	"DieSlots"      -- permanent extra dice on the board
	| "CashMult"    -- permanent multiplier on cash earned
	| "AutoRoll"    -- unlocks hands-free rolling
	| "AutoRollFast"-- faster auto-roll tier; requires AutoRoll
	| "ForgeCost"   -- permanent reduction in re-forge cost
	| "StreakShield"-- Void faces no longer break the streak
	| "OfflineCap"  -- higher offline earnings ceiling
	| "Currency"    -- a one-off currency grant
	| "Bundle"      -- a mixed one-off grant
	| "Boost"       -- a temporary, timed multiplier
	| "TimeSkip"    -- instantly grants N hours of offline earnings

export type Entry = {
	key: string,
	-- nil means UNRESOLVED: no asset exists yet. Fails closed everywhere.
	assetId: number?,
	-- TRUE when the server cannot yet deliver what this entry promises.
	--
	-- WHY THIS IS SEPARATE FROM `assetId`. An id says the item EXISTS on the
	-- platform; it says nothing about whether this build can honour it. Three
	-- products were created on the dashboard before the systems that grant them
	-- were written, which is a genuinely dangerous state: Roblox will happily
	-- sell them, the receipt handler will refuse them, and the platform will
	-- retry forever while the player has paid and received nothing.
	--
	-- Marking them lets the shop REFUSE TO OFFER them, which is the only place
	-- the problem can actually be prevented -- the receipt handler is already
	-- too late, because by then the player has been charged.
	unavailable: boolean?,
	name: string,
	blurb: string,
	kind: GrantKind,
	-- What the grant does. Interpretation depends on `kind`; the server is the
	-- only reader. Never sent to a client.
	amount: number?,
	currency: string?,
	durationSeconds: number?,
	-- Bundles grant several things at once.
	bundle: { { currency: string, amount: number } }?,
	-- A pass this one depends on; the grant is inert without it.
	requires: string?,
}

--------------------------------------------------------------------------------
-- Gamepasses -- bought once, owned forever
--------------------------------------------------------------------------------

MonetisationCatalog.Passes = {
	AutoRoll = {
		key = "AutoRoll",
		assetId = 1941930874,
		name = "Auto-Roll",
		blurb = "Roll continuously without tapping.",
		kind = "AutoRoll" :: GrantKind,
	},
	CashX2 = {
		key = "CashX2",
		assetId = 1941816910,
		name = "2x Cash",
		blurb = "Double all cash earned from rolls, permanently.",
		kind = "CashMult" :: GrantKind,
		amount = 2,
	},
	DieSlots2 = {
		key = "DieSlots2",
		assetId = 1942770917,
		name = "+2 Die Slots",
		blurb = "Two more dice on the board.",
		kind = "DieSlots" :: GrantKind,
		amount = 2,
	},
	VipForge = {
		key = "VipForge",
		assetId = 1941768890,
		name = "VIP Forge",
		blurb = "Re-forging costs less. Mass stays zero-sum.",
		kind = "ForgeCost" :: GrantKind,
		-- Multiplier on forge cost, not a discount on the mass itself: FR-3 keeps
		-- forging zero-sum, and a pass that added mass would sell power the game
		-- does not otherwise grant (FR-12.7).
		amount = 0.6,
	},

	-- ---------------------------------------------------------------------
	-- The remaining FR-12.1 passes. Created by the operator 2026-08-09 and
	-- resolved, so they are live and sellable.
	-- ---------------------------------------------------------------------
	StreakShield = {
		key = "StreakShield",
		assetId = 1941036910,
		name = "Bad Roll Shield",
		blurb = "A Void face no longer breaks your streak.",
		kind = "StreakShield" :: GrantKind,
	},
	VipVault = {
		key = "VipVault",
		assetId = 1940358891,
		name = "VIP Vault",
		blurb = "A far higher ceiling on offline earnings.",
		kind = "OfflineCap" :: GrantKind,
		amount = 3,
	},
	UltraAutoRoll = {
		key = "UltraAutoRoll",
		assetId = 1940634905,
		name = "Ultra Auto-Roll",
		blurb = "Auto-Roll, considerably faster.",
		kind = "AutoRollFast" :: GrantKind,
		-- Inert on its own: upgrading a speed the player cannot use would be
		-- selling nothing.
		requires = "AutoRoll",
	},
} :: { [string]: Entry }

--------------------------------------------------------------------------------
-- Developer products -- repeatable
--------------------------------------------------------------------------------

MonetisationCatalog.Products = {
	GemsSmall = {
		key = "GemsSmall",
		assetId = 3655134862,
		name = "Small Gem Pack",
		blurb = "100 Gems.",
		kind = "Currency" :: GrantKind,
		currency = "Gems",
		amount = 100,
	},
	GemsLarge = {
		key = "GemsLarge",
		assetId = 3655091493,
		name = "Large Gem Pack",
		blurb = "650 Gems.",
		kind = "Currency" :: GrantKind,
		currency = "Gems",
		amount = 650,
	},
	DiamondCache = {
		key = "DiamondCache",
		assetId = 3655106265,
		name = "Diamond Cache",
		blurb = "25 Diamonds.",
		kind = "Currency" :: GrantKind,
		currency = "Diamonds",
		amount = 25,
	},
	StarterBundle = {
		key = "StarterBundle",
		assetId = 3654933328,
		name = "Starter Bundle",
		blurb = "Gems, Diamonds and a die slot, once.",
		kind = "Bundle" :: GrantKind,
		bundle = {
			{ currency = "Gems", amount = 250 },
			{ currency = "Diamonds", amount = 10 },
		},
		-- The die slot is granted separately by the handler; `bundle` carries
		-- currencies only.
		amount = 1,
	},

	-- ---------------------------------------------------------------------
	-- The remaining FR-12.2 products. Created by the operator 2026-08-09.
	--
	-- RESOLVED BUT NOT YET GRANTABLE. Unlike the passes above, these three need
	-- server systems that do not exist: timed boosts and an offline-earnings
	-- accrual. `applyGrant` refuses them with `not_implemented_boosts`, which
	-- answers NotProcessedYet -- so a purchase is never consumed and the
	-- platform keeps retrying until the feature ships. See PurchaseService.
	-- ---------------------------------------------------------------------
	LuckBoost = {
		key = "LuckBoost",
		unavailable = true,
		assetId = 3655545836,
		name = "2x Luck Boost",
		blurb = "Heavy faces bite less, for a while.",
		kind = "Boost" :: GrantKind,
		amount = 2,
		durationSeconds = 15 * 60,
	},
	OfflineX2 = {
		key = "OfflineX2",
		unavailable = true,
		assetId = 3655618937,
		name = "2x Offline Payout",
		blurb = "Double your next offline collection.",
		kind = "Boost" :: GrantKind,
		amount = 2,
	},
	TimeSkip24 = {
		key = "TimeSkip24",
		unavailable = true,
		assetId = 3655695933,
		name = "Time Skip (24h)",
		blurb = "Collect a full day of offline earnings now.",
		kind = "TimeSkip" :: GrantKind,
		durationSeconds = 24 * 60 * 60,
	},
} :: { [string]: Entry }

--------------------------------------------------------------------------------
-- Lookup
--------------------------------------------------------------------------------

-- FR-12.6, the fail-closed test. Everything that grants MUST call this first.
function MonetisationCatalog.isResolved(entry: Entry?): boolean
	if entry == nil then
		return false
	end
	local id = entry.assetId
	return type(id) == "number" and id > 0 and id == id and id ~= math.huge
end

-- Reverse lookup: Roblox hands the receipt handler a numeric ProductId, and the
-- handler needs to know what was bought. Built once at require time rather than
-- scanned per receipt, and it deliberately skips unresolved rows so a nil id can
-- never collide with another nil id and resolve to the wrong product.
local productsById: { [number]: Entry } = {}
local passesById: { [number]: Entry } = {}

for _, entry in pairs(MonetisationCatalog.Products) do
	if MonetisationCatalog.isResolved(entry) then
		productsById[entry.assetId :: number] = entry
	end
end
for _, entry in pairs(MonetisationCatalog.Passes) do
	if MonetisationCatalog.isResolved(entry) then
		passesById[entry.assetId :: number] = entry
	end
end

function MonetisationCatalog.productById(assetId: number): Entry?
	if type(assetId) ~= "number" then
		return nil
	end
	return productsById[assetId]
end

function MonetisationCatalog.passById(assetId: number): Entry?
	if type(assetId) ~= "number" then
		return nil
	end
	return passesById[assetId]
end

-- Whether this entry may be OFFERED to a player.
--
-- Stricter than `isResolved` on purpose. `isResolved` asks "does the asset
-- exist"; this asks "can we actually deliver it". An entry that exists but
-- cannot be honoured must never reach a purchase prompt, because a refused
-- receipt still means the player was charged and is waiting on a retry that
-- will keep failing until the feature ships.
--
-- Any shop UI MUST gate on this, not on `isResolved`.
function MonetisationCatalog.isSellable(entry: Entry?): boolean
	if not MonetisationCatalog.isResolved(entry) then
		return false
	end
	return (entry :: Entry).unavailable ~= true
end

-- Every resolved pass, for the join-time ownership sweep.
function MonetisationCatalog.resolvedPasses(): { Entry }
	local out: { Entry } = {}
	for _, entry in pairs(MonetisationCatalog.Passes) do
		if MonetisationCatalog.isResolved(entry) then
			table.insert(out, entry)
		end
	end
	-- Sorted so iteration order is stable across servers and runs; a pass sweep
	-- that varies in order makes a bug reproduce only sometimes.
	table.sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

return MonetisationCatalog
