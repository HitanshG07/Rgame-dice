--!strict
-- PurchaseService.luau
-- Receipt processing and gamepass entitlements (SRS FR-12; threats T-16, T-17).
--
-- THIS FILE OWNS THE ONLY `ProcessReceipt` ASSIGNMENT IN THE PLACE (T-17).
--
-- Roblox allows exactly one callback per server, and a second assignment
-- silently REPLACES the first -- no error, no warning. Two modules each
-- believing they handle receipts means one of them is dead code and half the
-- purchases in the game grant nothing. The assignment is therefore made here,
-- once, at the bottom of this file, guarded so that even calling `init` twice
-- cannot reassign it.
--
-- THE MONEY RULE (FR-12.4, T-16). `PurchaseGranted` is a promise to Roblox that
-- the player has their goods, and it is irreversible: the platform stops
-- retrying and keeps the money. So it is returned on EXACTLY ONE path -- the
-- grant applied AND the profile written to disk AND the write confirmed. Every
-- other outcome returns `NotProcessedYet`, which asks the platform to try again
-- later. Getting this backwards charges players for nothing.
--
--   Not processed yet is ALWAYS the safe answer. It costs a retry.
--   Granted-when-we-did-not is unrecoverable and the player has paid.
--
-- IDEMPOTENCY (T-13, T-15). Roblox re-sends receipts, sometimes days later and
-- sometimes after a successful grant whose acknowledgement was lost. Every
-- receipt carries a `PurchaseId`; the profile keeps a ledger of the ones already
-- honoured. A replay is answered `PurchaseGranted` WITHOUT granting again --
-- the player has the goods, and the correct action is to stop the retries.
--
-- FR-12.6 -- FAIL CLOSED. A product id this build does not recognise returns
-- `NotProcessedYet`, never `PurchaseGranted`. An unknown id is far more likely
-- to be a product created on the dashboard but not yet wired here than an
-- attack; in either case granting nothing and letting the platform retry is
-- correct, and the operator can fill in the id and the retry will succeed.
--
-- NFR-5 -- nothing in this file sends a figure to a client. Grants mutate the
-- profile; StateSync then reports the resulting balances. No price, no reward
-- amount, no receipt detail crosses the wire.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("MonetisationCatalog"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local BoostService = require(script.Parent:WaitForChild("BoostService"))
local OfflineService = require(script.Parent:WaitForChild("OfflineService"))

local PurchaseService = {}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Owned passes per player, resolved at join. A cache, not a source of truth:
-- `MarketplaceService:UserOwnsGamePassAsync` is a network call and calling it
-- inside a roll would put a web request on the hot path.
local ownedPasses: { [Player]: { [string]: boolean } } = {}

-- Guards the single ProcessReceipt assignment (T-17).
local receiptHandlerInstalled = false

-- Set by ServerBootstrap so a grant can push a fresh snapshot without this
-- module depending on the sync service directly.
local announce: ((Player) -> ())? = nil

--------------------------------------------------------------------------------
-- Grants
--
-- Each returns (ok, reason). A grant that returns false MUST NOT be treated as
-- delivered -- the caller answers NotProcessedYet and the platform retries.
--------------------------------------------------------------------------------

local function grantCurrency(player: Player, currency: string, amount: number): (boolean, string?)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return false, "bad_amount"
	end
	if currency ~= "Cash" and currency ~= "Gems" and currency ~= "Diamonds" then
		return false, "bad_currency"
	end

	return PlayerProfile.mutate(player, function(data)
		if currency == "Cash" then
			data.Cash += amount
		elseif currency == "Gems" then
			data.Gems += amount
		else
			data.Diamonds += amount
		end
	end)
end

-- Applies whatever `entry` promises. Pure profile mutation; durability is the
-- caller's job, because only the caller knows whether it is inside a receipt.
local function applyGrant(player: Player, entry: Catalog.Entry): (boolean, string?)
	-- FR-12.6, checked again at the point of grant rather than trusted from the
	-- lookup. Defence in depth: a future caller that resolves an entry some other
	-- way still cannot grant an unresolved one.
	if not Catalog.isResolved(entry) then
		return false, "unresolved_product"
	end

	local kind = entry.kind

	if kind == "Currency" then
		local currency = entry.currency
		local amount = entry.amount
		if currency == nil or amount == nil then
			return false, "malformed_currency_entry"
		end
		return grantCurrency(player, currency, amount)

	elseif kind == "Bundle" then
		local parts = entry.bundle
		if parts == nil then
			return false, "malformed_bundle"
		end
		-- Applied in ONE mutation, so a bundle cannot half-apply: either the
		-- player gets everything or the profile is untouched and the platform
		-- retries the whole thing.
		local ok, reason = PlayerProfile.mutate(player, function(data)
			for _, part in ipairs(parts) do
				if part.currency == "Cash" then
					data.Cash += part.amount
				elseif part.currency == "Gems" then
					data.Gems += part.amount
				elseif part.currency == "Diamonds" then
					data.Diamonds += part.amount
				end
			end
			-- The Starter Bundle's die slot. Clamped to the ceiling FR-1.1 sets,
			-- so a bundle can never push a player past seven dice.
			--
			-- THROUGH `grantDieSlots`, which also creates the DIE. This incremented
			-- the counter alone, so a bundle raised `DieSlots` without adding
			-- anything to `d.Dice` -- the player paid for a die that was never
			-- built and the board drew fewer dice than the panel promised.
			if entry.amount ~= nil and entry.amount > 0 then
				PlayerProfile.grantDieSlots(data, entry.amount,
					DiceCatalog.MAX_DIE_SLOTS, DiceCatalog.newStartingDie)
			end
			-- FR-12.5: buying it closes the offer permanently. Latched true and
			-- never cleared -- StateSync reads this to stop advertising it, and
			-- nothing anywhere sets it back to false.
			if entry.key == "StarterBundle" then
				data.BundleOffered = true
			end
		end)
		return ok, reason

	elseif kind == "Boost" then
		local mult = entry.amount or 2.0
		local duration = entry.durationSeconds or 900
		local applied = BoostService.addBoost(player, entry.key, mult, duration)
		return applied, if applied then nil else "boost_apply_failed"

	elseif kind == "TimeSkip" then
		-- "Collect N hours of offline earnings now", so the payout is N hours at
		-- the player's OWN established rate. Nothing else is honest: a fixed
		-- number would be worth a fortune to a new player and an insult to a
		-- developed one.
		--
		-- THERE IS NO FALLBACK FIGURE HERE, DELIBERATELY. A flat floor stood here
		-- ("baseline so time skip never credits zero") and it was a live money
		-- defect: `getStatus` returns nil with no profile and `ratePerSec` is 0
		-- until the player has actually earned, so both cases fell through to a
		-- constant -- and then returned PurchaseGranted, which tells Roblox to
		-- keep the money and stop retrying. A player earning 50k/sec would have
		-- been charged for 24 hours and handed 1,000.
		--
		-- When the rate cannot be established we return FALSE, which answers
		-- NotProcessedYet and keeps the receipt alive. The player establishes a
		-- rate simply by playing, and the platform's own retry then grants the
		-- correct amount. Slower, and it cannot short-change anyone.
		local seconds = entry.durationSeconds or (24 * 3600)
		local status = OfflineService.getStatus(player)
		if status == nil then
			return false, "no_vault_status"
		end
		local rate = status.ratePerSec
		if not ForgeMath.isFinite(rate) or rate <= 0 then
			return false, "no_income_rate_established"
		end

		local payout = seconds * rate
		if not ForgeMath.isFinite(payout) or payout <= 0 then
			return false, "time_skip_payout_not_finite"
		end
		return grantCurrency(player, "Cash", payout)
	end

	-- A pass kind arriving through the receipt path means the catalog is
	-- misconfigured: passes are not consumed as receipts.
	return false, "not_a_product_grant"
end

--------------------------------------------------------------------------------
-- The receipt handler (T-16, T-17, FR-12.3, FR-12.4)
--------------------------------------------------------------------------------

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted

	if type(info) ~= "table" then
		return NOT_YET
	end

	local userId = info.PlayerId
	local productId = info.ProductId
	local purchaseId = info.PurchaseId
	if type(userId) ~= "number" or type(productId) ~= "number" or purchaseId == nil then
		return NOT_YET
	end
	local receiptKey = tostring(purchaseId)

	-- The player may have left before the receipt arrived, or between retries.
	-- Their profile is not loaded, so there is nothing to grant into and nothing
	-- to persist. NotProcessedYet keeps the receipt alive until they return.
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return NOT_YET
	end

	local data = PlayerProfile.get(player)
	if data == nil then
		return NOT_YET
	end

	-- IDEMPOTENCY, checked BEFORE the grant. A replay of an already-honoured
	-- receipt is answered granted without granting twice -- the goods are
	-- already delivered and the right outcome is to stop the retries.
	if PlayerProfile.hasPurchase(data, receiptKey) then
		return GRANTED
	end

	local entry = Catalog.productById(productId)
	if entry == nil then
		-- FR-12.6. Unknown id: grant nothing, let the platform retry. Most likely
		-- a product created on the dashboard that this build does not know about
		-- yet, in which case wiring the id makes the pending retry succeed.
		warn(string.format(
			"[PurchaseService] receipt for unrecognised product %d (user %d) -- granting nothing;"
			.. " if this product is real, add its id to MonetisationCatalog and the retry will succeed",
			productId, userId))
		return NOT_YET
	end

	-- Record the receipt IN THE SAME profile state as the grant, before the save,
	-- so the ledger entry and the goods are made durable by one write. Recording
	-- after the save would leave a window where a crash loses the ledger entry
	-- but keeps the grant, and the next retry would grant a second time.
	local recorded, recordNote = PlayerProfile.recordPurchase(data, receiptKey, os.time())
	if not recorded then
		-- Already present despite the check above: another thread beat us here.
		-- The goods are delivered; stop the retries.
		if recordNote == "already_recorded" then
			return GRANTED
		end
		return NOT_YET
	end

	local granted, grantReason = applyGrant(player, entry)
	if not granted then
		-- Roll the ledger entry back so a later retry is not mistaken for a
		-- replay of a grant that never happened.
		data.PurchaseIds[receiptKey] = nil
		for i = #data.PurchaseOrder, 1, -1 do
			if data.PurchaseOrder[i] == receiptKey then
				table.remove(data.PurchaseOrder, i)
				break
			end
		end
		warn(string.format("[PurchaseService] grant failed for %s (user %d): %s",
			entry.key, userId, tostring(grantReason)))
		return NOT_YET
	end

	-- FR-12.4 / T-16: DURABILITY BEFORE ACKNOWLEDGEMENT. Everything above lives
	-- in memory. Answering granted now would risk a crash between here and the
	-- next autosave, leaving a player who paid with nothing and a platform that
	-- will never re-send.
	local saved, saveReason = PlayerProfile.saveNow(player)
	if not saved then
		warn(string.format("[PurchaseService] durable save failed for %s (user %d): %s -- answering NotProcessedYet",
			entry.key, userId, tostring(saveReason)))
		-- Deliberately NOT rolled back. The grant is in memory and the ledger
		-- entry with it; if the profile saves later through the normal path the
		-- player keeps the goods, and the retry will then see the ledger entry
		-- and answer granted. Rolling back here could revoke goods that do
		-- ultimately persist.
		return NOT_YET
	end

	if recordNote == "ceiling_reached_all_live" then
		-- Every ledger slot holds a receipt still inside the platform's retry
		-- window, so none could be evicted. The grant IS durable, so the answer
		-- is granted -- but the ledger is at capacity and a future replay might
		-- not be recognised. Loud, because it means the ceiling needs raising.
		warn(string.format(
			"[PurchaseService] purchase ledger at capacity for user %d with every entry still"
			.. " replayable -- raise PURCHASE_ID_CEILING", userId))
	end

	local push = announce
	if push ~= nil then
		-- The client learns what changed the same way it learns everything else:
		-- a fresh snapshot of its own state. No reward figure crosses the wire
		-- (NFR-5).
		push(player)
	end

	return GRANTED
end

--------------------------------------------------------------------------------
-- Gamepass entitlements
--------------------------------------------------------------------------------

-- Resolves everything this player owns. Yields on network calls, so it is run
-- once at join rather than on any gameplay path.
local function resolveOwnership(player: Player): ()
	local owned: { [string]: boolean } = {}

	for _, entry in ipairs(Catalog.resolvedPasses()) do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.assetId :: number)
		end)
		-- A failed lookup is recorded as NOT OWNED. That is the fail-closed
		-- direction: a network blip must not hand out an entitlement. The sweep
		-- re-runs on the next join, and `PromptGamePassPurchaseFinished` corrects
		-- it within the session if they buy one.
		owned[entry.key] = ok and result == true
		if not ok then
			warn(string.format("[PurchaseService] ownership check failed for %s (user %d); treating as not owned",
				entry.key, player.UserId))
		end
	end

	ownedPasses[player] = owned
end

function PurchaseService.ownsPass(player: Player, passKey: string): boolean
	local owned = ownedPasses[player]
	if owned == nil then
		return false
	end
	return owned[passKey] == true
end

-- The multiplier a player's passes apply to cash earned. 1.0 when they own none.
--
-- Read by EconomyService on every credit, which is why it reads a cached table
-- and never touches the network.
function PurchaseService.cashMultiplier(player: Player): number
	local entry = Catalog.Passes.CashX2
	if PurchaseService.ownsPass(player, "CashX2") and entry.amount ~= nil then
		return entry.amount
	end
	return 1
end

-- Extra die slots the +2 Die Slots pass is worth.
--
-- READ-ONLY. This used to be added to `DieSlots` inside the SNAPSHOT, so the
-- bonus existed only as a number on the client's screen: nothing persisted it
-- and no dice were ever created for it. See `applyPassSlotGrant`, which turns
-- the entitlement into real stored slots and real dice.
function PurchaseService.bonusDieSlots(player: Player): number
	local entry = Catalog.Passes.DieSlots2
	if PurchaseService.ownsPass(player, "DieSlots2") and entry.amount ~= nil then
		return entry.amount
	end
	return 0
end

-- MATERIALISES THE PASS BONUS into the profile, once.
--
-- The +2 Die Slots pass is a PERMANENT entitlement, so its slots have to exist
-- in the saved profile like any other -- with dice to fill them. Adding the
-- bonus at display time instead produced a player who was shown four slots and
-- rolled two dice (operator-reported 2026-08-13, seen as the board drawing
-- fewer dice than the panel promised, and as dice overlapping because the
-- layout was computed for a count that did not match what was drawn).
--
-- IDEMPOTENT, and that is the whole difficulty. This runs on EVERY join, so it
-- must not add two more slots each time. `PassSlotsGranted` records how much of
-- the entitlement has already been materialised, and only the shortfall is
-- granted -- so a rejoin is a no-op, and raising the pass's amount later tops
-- a player up by the difference rather than re-granting the whole thing.
function PurchaseService.applyPassSlotGrant(player: Player): ()
	local owed = PurchaseService.bonusDieSlots(player)
	if owed <= 0 then
		return
	end
	PlayerProfile.mutate(player, function(data)
		local already = tonumber(data.PassSlotsGranted) or 0
		local shortfall = owed - already
		if shortfall <= 0 then
			return
		end
		-- Bounded by the ABSOLUTE ceiling, deliberately not by the player's
		-- ascension cap. The ascension curve gates what Cash can BUY; a pass is
		-- paid for with Robux and must not be silently withheld because the
		-- player has not prestiged yet. The hard 7 still applies -- BoardView has
		-- layouts for exactly that many.
		local gained = PlayerProfile.grantDieSlots(data, shortfall,
			DiceCatalog.MAX_DIE_SLOTS, DiceCatalog.newStartingDie)
		-- Credited by what was ACTUALLY granted, not by what was owed. A player
		-- already at the seven-slot ceiling gains nothing, and recording the full
		-- entitlement anyway would permanently forfeit slots they could claim
		-- later if the ceiling ever rose.
		data.PassSlotsGranted = already + gained
	end)
end

-- Multiplier on forge cost. Below 1.0 is a discount.
function PurchaseService.forgeCostMultiplier(player: Player): number
	local entry = Catalog.Passes.VipForge
	if PurchaseService.ownsPass(player, "VipForge") and entry.amount ~= nil then
		return entry.amount
	end
	return 1
end

function PurchaseService.hasStreakShield(player: Player): boolean
	return PurchaseService.ownsPass(player, "StreakShield")
end

function PurchaseService.hasAutoRoll(player: Player): boolean
	return PurchaseService.ownsPass(player, "AutoRoll")
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function PurchaseService.onPlayerAdded(player: Player): ()
	-- Yields; the caller runs it in its own thread so a slow ownership lookup
	-- cannot delay admission.
	resolveOwnership(player)
end

function PurchaseService.onPlayerRemoving(player: Player): ()
	ownedPasses[player] = nil
end

function PurchaseService.setAnnouncer(fn: (Player) -> ()): ()
	announce = fn
end

function PurchaseService.init(): ()
	-- T-17: THE SINGLE ASSIGNMENT. Guarded so a second `init` -- from a reload,
	-- a test harness, or a future caller that does not know this already ran --
	-- cannot silently replace a live handler with an identical one and lose any
	-- receipt in flight.
	if receiptHandlerInstalled then
		return
	end
	receiptHandlerInstalled = true

	MarketplaceService.ProcessReceipt = processReceipt

	-- Ownership can change mid-session. Without this a player who buys a pass
	-- would see nothing until they rejoined, which reads as the purchase having
	-- failed.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			local entry = Catalog.passById(gamePassId)
			if entry == nil then
				return
			end
			local owned = ownedPasses[player]
			if owned == nil then
				owned = {}
				ownedPasses[player] = owned
			end
			owned[entry.key] = true

			-- A pass that changes a persisted value must write it, not merely be
			-- remembered in a cache that dies with the session.
			--
			-- THIS IS THE ONE THE OPERATOR HIT. It raised `DieSlots` by two and
			-- never touched `d.Dice`, so a player who owned the +2 Die Slots pass
			-- had `DieSlots = 4` and two actual dice: the SLOTS panel promised four,
			-- the board drew two, and the layout was computed for a count that did
			-- not match what was rendered -- which is the overlap that was reported.
			--
			-- `grantDieSlots` backfills from `#d.Dice`, so this ALSO repairs an
			-- already-drifted profile the next time the pass resolves at join,
			-- rather than leaving existing owners permanently short.
			if entry.key == "DieSlots2" and entry.amount ~= nil then
				PlayerProfile.mutate(player, function(data)
					PlayerProfile.grantDieSlots(data, entry.amount :: number,
						DiceCatalog.MAX_DIE_SLOTS, DiceCatalog.newStartingDie)
				end)
			end

			local push = announce
			if push ~= nil then
				push(player)
			end
		end
	)
end

return PurchaseService
