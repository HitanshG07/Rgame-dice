--!strict
-- StateSyncService.luau
-- The authoritative snapshot pushed to a client (API_DATA_CONTRACT §1.2).
--
-- WHY THIS MODULE EXISTS, AND WHY LATE. `StateSync` was specified in the data
-- contract from the blueprint onward and implemented by NOTHING for three
-- blocks. It went unnoticed through five audit rounds because every one of them
-- audited what the server DID rather than what the contract PROMISED — a row
-- describing an event nobody emits reads exactly like a row describing one that
-- works.
--
-- It surfaced only when the client was built: THREE swarm workers, in isolated
-- contexts and given different slices, independently reported it. Each hit a
-- different consequence — dice with no shape or mass, a HUD with no balances, a
-- forge showing every element locked.
--
-- THE RULE THIS MODULE ENFORCES. Everything the client displays comes from here
-- or from `RollResult`. No client may derive a balance, and no client may assume
-- a default for something the server owns. That is why the payload is built by
-- explicit field, never by handing over the profile: `PurchaseIds`,
-- `CodesRedeemed` and the receipt ledger are the player's data but they are not
-- the player's business, and a snapshot that ships the whole profile leaks the
-- purchase history to anyone with a network inspector.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local MonetisationCatalog = require(Shared:WaitForChild("MonetisationCatalog"))
local VaultCatalog = require(Shared:WaitForChild("VaultCatalog"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local PurchaseService = require(script.Parent:WaitForChild("PurchaseService"))
local RollService = require(script.Parent:WaitForChild("RollService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))

local StateSyncService = {}

--------------------------------------------------------------------------------
-- Emission seam. Same rationale as RollService's and ForgeService's: the suite
-- drives this with a fake player, and the alternative is typeof-guards and a
-- swallowing pcall in the production path. STUDIO-ONLY.
--------------------------------------------------------------------------------

local RunService = game:GetService("RunService")

local function defaultEmit(player: Player, payload: any): ()
	Remotes.getEvent("StateSync"):FireClient(player, payload)
end

-- Roblox Premium, read from the platform. Duplicated from OfflineService rather
-- than imported ON PURPOSE: StateSyncService is required by nearly everything,
-- so every edge added here is a future module cycle waiting for one more import
-- (L-035). This is a one-line read of a platform property with no game logic in
-- it, which is the only kind of duplication worth accepting -- the EFFECT of
-- Premium still lives in exactly one place, `VaultCatalog`.
local function isPremium(player: Player): boolean
	local ok, result = pcall(function()
		return player.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and result == true
end

local emitState: (Player, any) -> () = defaultEmit

function StateSyncService._setEmitterForTesting(fn: ((Player, any) -> ())?): ()
	if not RunService:IsStudio() then
		error("[StateSyncService] the emitter seam is Studio-only", 2)
	end
	emitState = fn or defaultEmit
end

--------------------------------------------------------------------------------
-- VAULT STATUS PROVIDER (FR-8)
--
-- The snapshot has never carried the vault's accrued figure, so the panel could
-- only ever show a CAPACITY -- "your vault holds 4 hours" -- and the player
-- learned what had actually built up only by pressing CLAIM and watching their
-- balance jump. An idle game whose central offline reward is invisible until
-- spent has hidden the thing players open the game to see.
--
-- INJECTED rather than required. `OfflineService` does not import this module
-- today, so a direct require would not cycle right now -- but StateSync is
-- imported by nearly everything, and every hard edge added here is a future
-- cycle waiting for one more import (ledger L-035). The bootstrap wires this,
-- exactly as it wires RollService's roll observer.
--
-- nil is a VALID state and means "no vault figures in the snapshot", which the
-- client renders as unknown rather than as zero. A provider that has not been
-- installed must never look like an empty vault.
local vaultProvider: ((Player) -> any)? = nil

function StateSyncService.setVaultProvider(fn: ((Player) -> any)?): ()
	vaultProvider = fn
end

-- How many more Gem-hours would actually raise this player's vault capacity.
-- Injected for the same reason the vault provider above is (L-035): this module
-- is imported by nearly everything and must import as little as possible itself.
-- nil means "unknown", which the panel renders as no offer rather than as zero.
local buyableHoursProvider: ((Player) -> number)? = nil

function StateSyncService.setBuyableHoursProvider(fn: ((Player) -> number)?): ()
	buyableHoursProvider = fn
end

--------------------------------------------------------------------------------
-- Snapshot construction
--------------------------------------------------------------------------------

-- Copies only what the contract names. Explicit field-by-field BY DESIGN: a
-- snapshot built by handing over `profile.Data` would ship PurchaseIds,
-- PurchaseOrder and CodesRedeemed to the client, and would silently start
-- shipping every future field the moment someone added one to the template.
-- The client cannot be trusted with what it does not need to know.
function StateSyncService.buildSnapshot(data: PlayerProfile.Profile, streak: number, player: Player?): any
	local dice = {}
	for i, die in ipairs(data.Dice) do
		local faces = {}
		for j, face in ipairs(die.Faces) do
			faces[j] = { Mass = face.Mass, Element = face.Element }
		end
		dice[i] = {
			Shape = die.Shape,
			MassBudget = die.MassBudget,
			-- Schema v2. The forge needs the owned figure as well as the usable
			-- one, or it cannot show why a narrower shape is capping the player.
			PurchasedBudget = die.PurchasedBudget,
			Faces = faces,
		}
	end

	local upgrades = {}
	for id, level in pairs(data.Upgrades) do
		if not string.match(id, "^Boost_") then
			upgrades[id] = level
		end
	end

	-- The unlocked sets. Without these the forge defaults to showing EVERYTHING
	-- locked, which is the safe direction to fail but is not the truth.
	local elements = {}
	for id, unlocked in pairs(data.Diamond.Elements) do
		elements[id] = unlocked
	end
	local shapes = {}
	for id, unlocked in pairs(data.Diamond.Shapes) do
		shapes[id] = unlocked
	end
	-- Which shapes have been worn before. The client needs it to label the USE
	-- button honestly: the first equip of a shape is free, every later switch
	-- costs Diamonds (FR-6.1). This is a FLAG, not a price -- the client reads the
	-- cost from the shared catalog and never receives one over the wire (NFR-5).
	local shapesEquipped = {}
	for id, worn in pairs(data.Diamond.ShapesEquipped) do
		shapesEquipped[id] = worn
	end

	local settings = {}
	for key, enabled in pairs(data.Settings) do
		settings[key] = enabled
	end


	-- WHICH GAMEPASSES THE PLAYER OWNS (FR-12).
	--
	-- The shop rendered every card with an identical BUY button whether or not
	-- the player already owned the pass, so the only way to discover you had
	-- bought something was to buy it again and watch Roblox say "you already own
	-- this item". Ownership is a FLAG, not a price -- the client reads names and
	-- blurbs from the shared catalog and Roblox itself renders the actual cost in
	-- the purchase prompt, so no Robux figure crosses this boundary.
	local ownedPasses: { [string]: boolean } = {}
	if player ~= nil then
		for key in pairs(MonetisationCatalog.Passes) do
			if PurchaseService.ownsPass(player, key) then
				ownedPasses[key] = true
			end
		end
	end

	-- THE VAULT'S REAL FIGURES (FR-8). Absent entirely when there is no provider
	-- or no player, so the client can tell "not known" from "nothing accrued".
	--
	-- `unclaimed` IS an earned amount crossing the wire, and that is correct here
	-- rather than an NFR-5 violation: NFR-5 forbids the CLIENT naming an economic
	-- value the server then trusts. This is the reverse direction -- the server
	-- stating a figure it has already computed and will itself honour on claim.
	-- The client cannot alter it; ClaimVault recomputes from scratch and never
	-- reads anything the client sends.
	local vault: any = nil
	if player ~= nil and vaultProvider ~= nil then
		local okVault, status = pcall(vaultProvider :: any, player)
		if okVault and type(status) == "table" then
			vault = {
				unclaimed = status.unclaimedEarnings,
				claimableSeconds = status.claimableSeconds,
				capacitySeconds = status.capacitySeconds,
				elapsedSeconds = status.elapsedSeconds,
				ratePerSec = status.ratePerSec,
				-- The player's TIER, so the panel can say what they get and what a
				-- better tier would give. Efficiency is the server's computed
				-- value, not a client re-derivation, and the two flags are
				-- entitlement FACTS the server has already verified -- the client
				-- renders them, it never asserts them.
				efficiency = status.efficiency,
				hasVip = PurchaseService.ownsPass(player, "VipVault"),
				hasPremium = isPremium(player),
				-- Whether the vault is FULL, so the panel can say "stopped
				-- earning" rather than leaving the player to compare two numbers.
				atCapacity = status.claimableSeconds >= status.capacitySeconds,
				-- GEM-PURCHASED HOURS and the ceiling on them, so the VAULT panel
				-- can price the next hour and say when there is nothing left to
				-- buy. Both come from the server: the cap is enforced here (twice
				-- -- see OfflineService) and the panel only renders it.
				purchasedHours = data.Vault.PurchasedHours or 0,
				maxPurchasedHours = VaultCatalog.MAX_PURCHASED_CAPACITY_SEC / 3600,
				-- How many more Gem-hours would ACTUALLY raise capacity. Zero for a
				-- VIP player, whose 24h floor already exceeds every other source
				-- combined -- the panel needs this to stop advertising a purchase
				-- that would do nothing, and to say why.
				buyableHours = buyableHoursProvider ~= nil and buyableHoursProvider(player) or 0,
			}
		elseif not okVault then
			-- A failing provider must not take the whole snapshot down with it --
			-- the balances and dice in this payload are unrelated to the vault.
			warn(string.format("[StateSyncService] vault provider failed for UserId=%d: %s",
				player.UserId, tostring(status)))
		end
	end

	-- Active boost expiries, read straight from the profile so this cannot
	-- disagree with what BoostService charges against. Only boosts still running
	-- are listed; an expired one is simply absent rather than sent as expired,
	-- because "absent" is the state the client should render.
	local now = os.time()
	local boosts: { [string]: number } = {}
	for key, value in pairs(data.Upgrades) do
		local kind = string.match(key, "^Boost_(.+)_Expiry$")
		if kind ~= nil and type(value) == "number" and value > now then
			boosts[kind] = value
		end
	end

	-- The day's quests. `target` is included so the client can draw a progress
	-- bar without a second copy of the quest table that could drift (L-026).
	local quests: { any } = {}
	for _, slot in ipairs(data.Quests.Slots) do
		local target = ProgressionService.getQuestTarget(slot.Id)
		table.insert(quests, {
			id = slot.Id,
			progress = slot.Progress,
			target = target,
			claimed = slot.Claimed,
			ready = target ~= nil and not slot.Claimed and slot.Progress >= target,
		})
	end

	-- FR-12.5, THE ONCE-ONLY OFFER. The window opens on first sight and closes
	-- permanently; `BundleOffered` latching true is what makes it unrepeatable.
	-- `BundleExpiry` is stamped ONCE, on the player's first session, and never
	-- rewritten. That single write is the whole guarantee: there is no code path
	-- anywhere that extends it, resets it, or re-opens the offer, and
	-- `BundleOffered` latching true on purchase closes it early.
	local starterBundle = {
		offered = (not data.BundleOffered)
			and data.BundleExpiry > 0
			and now < data.BundleExpiry,
		expiresAt = data.BundleExpiry,
	}

	local inventory: { [string]: number } = {}
	if type(data.Inventory) == "table" then
		for shape, count in pairs(data.Inventory) do
			if type(count) == "number" and count > 0 then
				inventory[shape] = count
			end
		end
	end

	return {
		cash = data.Cash,
		gems = data.Gems,
		diamonds = data.Diamonds,
		dice = dice,
		inventory = inventory,
		upgrades = upgrades,
		diamondTree = {
			StreakStrength = data.Diamond.StreakStrength,
			MassCeiling = data.Diamond.MassCeiling,
			SlotNodes = data.Diamond.SlotNodes,
			Elements = elements,
			Shapes = shapes,
			ShapesEquipped = shapesEquipped,
		},
		settings = settings,
		-- nil when unknown, never a fabricated zero -- see the block above.
		vault = vault,
		ownedPasses = ownedPasses,
		streak = streak,
		-- ACTIVE BOOSTS (FR-12.2). This was a hardcoded `{}` with the comment
		-- "Block 5 populates this". Block 5 built BoostService and never came
		-- back, so a purchased boost ticked down server-side while the client was
		-- told there were none -- the player paid for a timer they could not see.
		--
		-- EXPIRY TIMES cross the wire, not multipliers. The client needs to draw a
		-- countdown; it never needs to know what the boost is WORTH, and a
		-- multiplier on the wire is a reward figure (NFR-5). The server applies
		-- the value; the client renders the clock.
		boosts = boosts,
		-- DAILY QUESTS (FR-10.1). Progress and target only. The reward amount is
		-- deliberately absent for the same NFR-5 reason -- the client shows what
		-- the quest IS and whether it is done, never what it pays.
		quests = quests,
		loginStreak = {
			count = data.LoginStreak.Count,
			forgivenessLeft = data.LoginStreak.ForgivenessLeft,
			claimedToday = data.LoginStreak.LastDay == math.floor(os.time() / 86400),
		},
		-- THE STARTER BUNDLE OFFER (FR-12.5). `expiresAt` is an absolute server
		-- timestamp, so the client renders a countdown against `serverTime` rather
		-- than running its own clock. Once past, it is GONE -- `offered` never
		-- returns to true for this player, there is no reset anywhere in the code,
		-- and nothing re-offers it under another name.
		starterBundle = starterBundle,
		serverTime = os.time(),
		-- Stats the HUD and the Statistics panel read. Present here rather than
		-- in a second event because they change on the same cadence.
		lifetimeCash = data.LifetimeCash,
		-- `runCash` WAS SENT HERE and is gone. The ASCEND panel now shows progress
		-- toward the threshold from `cash`, which this snapshot already carries and
		-- which the HUD already displays -- so the two can never disagree, which is
		-- exactly why the operator chose it. Not `lifetimeCash`, which never resets.
		highestRoll = data.HighestRoll,
		ascensions = data.Ascensions,
		totalRolls = data.TotalRolls,
		-- THE STORED VALUE, NOT A COMPUTED ONE.
		--
		-- This was `data.DieSlots + extraSlots`, adding the +2 Die Slots pass
		-- bonus at DISPLAY time only. The bonus was never persisted and no dice
		-- were ever created for it, so a pass owner was told they had four slots
		-- while `d.Dice` held two: the SLOTS panel promised four, the board drew
		-- two, and `BoardView` laid out for a count that did not match what was
		-- rendered -- which is the overlap that was reported.
		--
		-- The pass is now granted for real at join (`PurchaseService.onPlayerAdded`
		-- -> `applyPassSlotGrant`), which creates the dice as well, so the stored
		-- count IS the truth and there is nothing left to add here.
		dieSlots = data.DieSlots,
	}
end

--------------------------------------------------------------------------------
-- Push
--------------------------------------------------------------------------------

-- Fails CLOSED and silently: a player mid-teardown has no profile, and firing at
-- them would either error or deliver a snapshot of nothing. Returns whether a
-- push happened so callers and tests can assert it rather than assume it.
function StateSyncService.push(player: Player): boolean
	if player.Parent ~= Players then
		return false
	end
	local data = PlayerProfile.get(player)
	if not data then
		return false
	end
	emitState(player, StateSyncService.buildSnapshot(data, RollService.getStreak(player), player))
	return true
end

-- Convenience for the call sites that mutate state and must announce it. Named
-- for the reason it exists rather than for what it does, so the next author sees
-- the obligation: EVERY state change owes the client a snapshot, or the display
-- silently drifts from the truth.
function StateSyncService.announceChange(player: Player): ()
	StateSyncService.push(player)
end

return StateSyncService
