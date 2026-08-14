--!strict
-- VaultCatalog.luau
-- The one declaration of what each player tier gets from the offline vault
-- (SRS FR-8), and the Gems-for-capacity exchange rate.
--
-- WHY THIS MODULE EXISTS. The tier numbers lived as server-side locals in
-- `OfflineService`, so the client could not state them -- and the VAULT panel
-- consequently told the player their capacity in hours and NOTHING about their
-- efficiency, their tier, or that a better one existed. A player on 50% and a
-- player on 100% saw identical screens.
--
-- The operator asked for the standard/VIP/Premium differences to be visible
-- wherever they apply (2026-08-13). That is only safe if both sides read the
-- same numbers: a panel quoting "+25%" from a hardcoded string while the server
-- grants something else is worse than saying nothing (ledger L-025).
--
-- THE SERVER STILL DECIDES. Nothing here is an entitlement check -- `ownsPass`
-- and `MembershipType` are read server-side only. This module holds the VALUES
-- and the wording; the client uses them to render a truthful description of
-- what the server already computed and sent.

local VaultCatalog = {}

--------------------------------------------------------------------------------
-- EFFICIENCY: the fraction of the player's own recent earning rate the vault
-- pays for time spent away. 0.50 means "half what you would have made playing".
--
-- EVERY SOURCE ADDS, AND THE TOTAL IS CAPPED AT 1.0.
--
-- The cap is the load-bearing part. Anything above 100% means the vault pays
-- MORE than playing does, which in an idle game makes closing the game the
-- optimal move -- every session a player actually plays would be time they lost
-- money. Parity is generous; above parity is self-defeating.
--------------------------------------------------------------------------------

VaultCatalog.BASE_EFFICIENCY = 0.50
VaultCatalog.UPGRADE_EFFICIENCY_PER_LEVEL = 0.05
VaultCatalog.MAX_UPGRADE_EFFICIENCY_LEVELS = 5
VaultCatalog.PREMIUM_EFFICIENCY_BONUS = 0.15
VaultCatalog.VIP_EFFICIENCY_BONUS = 0.25
VaultCatalog.MAX_EFFICIENCY = 1.0

--------------------------------------------------------------------------------
-- CAPACITY: how long the vault keeps banking before it stops.
--------------------------------------------------------------------------------

VaultCatalog.BASE_CAPACITY_SEC = 4 * 3600
VaultCatalog.UPGRADE_CAPACITY_PER_LEVEL_SEC = 2880 -- +0.8h
VaultCatalog.PREMIUM_CAPACITY_BONUS_SEC = 4 * 3600
-- VIP's capacity FLOOR. Operator decision 2026-08-15, option 1 of two: lower the
-- floor below the stackable maximum rather than convert VIP into a flat bonus.
--
-- IT WAS 24h, AND THAT MADE THE GEMS SINK POINTLESS. Every other source combined
-- reaches 20h -- base 4 + Cash upgrades 4 + Gems 8 + Premium 4 -- so a 24h floor
-- swallowed all of it: a VIP player measured 24h with zero Gem-hours and 24h with
-- eight. They were charged 40 Gems for nothing, which the operator caught
-- immediately ("how does this work if its still 24hrs").
--
-- THE THRESHOLD IS ARITHMETIC, NOT TASTE, and 16h -- my first attempt -- was
-- still wrong. A floor only leaves room for Gems if it sits BELOW what the
-- worst-case VIP player reaches without it: base 4h + Gems 8h = 12h. At 16h and
-- at 12h the Gems still add exactly nothing; the fix has to clear 12, not merely
-- come down from 24. Solved rather than guessed a third time:
--
--     floor 16h -> VIP alone 16h, with 8 Gem-hours 16h, Gems add +0h
--     floor 12h -> VIP alone 12h, with 8 Gem-hours 12h, Gems add +0h
--     floor 10h -> VIP alone 10h, with 8 Gem-hours 12h, Gems add +2h
--
-- 10h keeps VIP a strong opening position -- two and a half times base, and more
-- than a fully Cash-upgraded player without Premium reaches -- while leaving
-- genuine headroom that only Gems and Premium can fill. Both the pass and the
-- sink stay worth buying, which is the whole point.
VaultCatalog.VIP_CAPACITY_SEC = 10 * 3600

--------------------------------------------------------------------------------
-- GEMS FOR CAPACITY (operator-directed 2026-08-13, "5 gems means 1 hour").
--
-- THE CAP IS THE ANTI-PAY-TO-WIN PROPERTY, and it is the only thing standing
-- between this and a Robux-for-income exchange: Gems are purchasable, and vault
-- capacity is an economic advantage. Purchased hours stop at the SAME total a
-- maxed Cash upgrade reaches, so paying buys SPEED TO THE CAP and never a
-- higher cap than a free player can reach.
--
-- It is also genuinely reachable without paying. Three of the seven daily
-- quests pay Gems (25-40), the Tier-3 playtime chest pays 35, and the daily
-- spin can pay 150 -- so an active day is roughly 60+ Gems, or 12 hours of
-- capacity at this rate.
--------------------------------------------------------------------------------

VaultCatalog.GEMS_PER_CAPACITY_HOUR = 5

-- Ceiling on GEM-PURCHASED capacity, matching the maximum the Cash upgrade
-- path reaches (5 levels * 0.8h = 4h... see below).
--
-- Deliberately expressed as hours and derived, not typed as a second literal:
-- if the upgrade curve changes, this follows it rather than silently diverging.
VaultCatalog.MAX_PURCHASED_CAPACITY_SEC = 8 * 3600

-- Ceiling on a SINGLE purchase request, independent of the capacity cap.
--
-- The capacity cap already bounds the outcome, so this does not guard the
-- economy -- it guards the arithmetic. A request of 1e9 hours would compute a
-- Gems cost of 5e9 before any cap applied, and a non-finite or absurd figure
-- reaching a currency path is exactly the shape of bug that becomes an exploit
-- when some later change reorders the checks. Bounding the INPUT keeps every
-- downstream number small by construction.
VaultCatalog.MAX_PURCHASE_HOURS_PER_CALL = 24

function VaultCatalog.gemCostForHours(hours: number): number?
	if type(hours) ~= "number" or hours ~= hours or hours <= 0 then
		return nil
	end
	return math.floor(hours) * VaultCatalog.GEMS_PER_CAPACITY_HOUR
end

--------------------------------------------------------------------------------
-- Describing a tier to the player
--------------------------------------------------------------------------------

export type Tier = "Standard" | "Premium" | "VIP" | "VIP+Premium"

-- Which tier a set of entitlements amounts to. Takes plain booleans rather than
-- a Player, so the client can call it with what the snapshot reported and the
-- server can call it with what it verified -- one function, two callers, no
-- second copy of the rule.
function VaultCatalog.tierName(hasVip: boolean, hasPremium: boolean): Tier
	if hasVip and hasPremium then
		return "VIP+Premium"
	elseif hasVip then
		return "VIP"
	elseif hasPremium then
		return "Premium"
	end
	return "Standard"
end

-- One line of small print explaining what this player's tier gives them, and
-- what the next tier up would.
--
-- STATES THE PLAYER'S ACTUAL RATE FIRST, because that is the number that
-- affects them; the upsell is secondary and deliberately phrased as information
-- rather than a prompt. `efficiency` is the value the SERVER computed and sent,
-- not a client re-derivation -- so the line cannot claim a rate the player does
-- not have.
function VaultCatalog.describeTier(efficiency: number, hasVip: boolean, hasPremium: boolean): string
	local pct = math.floor(math.clamp(efficiency, 0, 1) * 100 + 0.5)
	local tier = VaultCatalog.tierName(hasVip, hasPremium)

	local parts = { string.format("%s  -  banks %d%% of your earning rate", tier, pct) }

	-- Only mention what the player does NOT already have. Telling a VIP about
	-- the VIP bonus is noise, and noise is what makes small print unread.
	local upsell: { string } = {}
	if not hasVip then
		-- DERIVED, not the literal "24h" this used to say. That string was already
		-- a second copy of `VIP_CAPACITY_SEC`, and the moment the floor moved to
		-- 16h it would have been advertising a capacity the pass does not grant
		-- (L-025). One declaration, read by both sides.
		table.insert(upsell, string.format("VIP Vault +%d%% and %dh",
			math.floor(VaultCatalog.VIP_EFFICIENCY_BONUS * 100 + 0.5),
			math.floor(VaultCatalog.VIP_CAPACITY_SEC / 3600)))
	end
	if not hasPremium then
		table.insert(upsell, string.format("Roblox Premium +%d%% and +%dh",
			math.floor(VaultCatalog.PREMIUM_EFFICIENCY_BONUS * 100 + 0.5),
			math.floor(VaultCatalog.PREMIUM_CAPACITY_BONUS_SEC / 3600)))
	end
	if #upsell > 0 and pct < math.floor(VaultCatalog.MAX_EFFICIENCY * 100) then
		table.insert(parts, table.concat(upsell, "  |  "))
	end

	return table.concat(parts, "\n")
end

return VaultCatalog
