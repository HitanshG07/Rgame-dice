--!strict
-- ServerBootstrap.server.luau
-- Server entry point. Constructs services in explicit dependency order, wires
-- player lifecycle, registers remotes via RemoteGateway, and handles BindToClose.
--
-- HLD §3 C-1, SRS FR-14.3, Threat T-10:
--   A failed profile load FAILS CLOSED -- the player is kicked with an honest message.
--   A default profile is NEVER served to a player whose load failed.
--
-- THE JOIN RACE, and why the connection is made before anything else.
--
-- Every `require` above a `PlayerAdded:Connect` is a YIELD. A player added
-- during that window is invisible to a connection made after it. The
-- `Players:GetPlayers()` sweep that followed the connect was the only guard,
-- and it closes the window only if the sweep happens to run after the player is
-- present. That is a real ordering hazard, not a hypothetical one, and the
-- failure it produces is the worst possible shape: a player seated in a live
-- session with NO profile and NO kick -- silent, uncrashing, and a fail-OPEN on
-- the exact path SRS FR-14.3 requires to fail CLOSED.
--
-- So: connect FIRST, at the very top, before a single yielding require. Joins
-- arriving before the services exist are queued and drained once they do,
-- `admitPlayer` is idempotent so overlapping paths are harmless, and a delayed
-- sweep catches and reports anyone stranded rather than letting the state sit.
--
-- HONESTY NOTE ON PROVENANCE (2026-08-06). This hardening was written in
-- response to a diagnostic that turned out to be WRONG. The Studio MCP server's
-- `execute_luau` does not share the running server's module cache -- each call
-- re-requires modules and gets a FRESH instance -- so an introspection that
-- reported "profile is nil, player not kicked" was reading an empty duplicate of
-- PlayerProfile, not live state. The original code was never observed failing.
-- The restructure is kept because the ordering hazard above is genuine and the
-- pattern is correct regardless; it is NOT kept on the strength of an incident,
-- because there was no incident. The `[Bootstrap] admitted` line below is the
-- in-VM proof that the join path works, and it is the only such proof that
-- counts -- state read from outside the VM does not.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

--------------------------------------------------------------------------------
-- Join capture — established before any yield
--------------------------------------------------------------------------------

local servicesReady = false
local joinQueue: { Player } = {}
local admitPlayer: (Player) -> ()

local function onJoin(player: Player)
	if servicesReady then
		task.spawn(admitPlayer, player)
	else
		table.insert(joinQueue, player)
	end
end

local joinConnection = Players.PlayerAdded:Connect(onJoin)

--------------------------------------------------------------------------------
-- Services, in dependency order
--------------------------------------------------------------------------------

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UpgradeCatalog = require(Shared:WaitForChild("UpgradeCatalog"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local SettingsCatalog = require(Shared:WaitForChild("SettingsCatalog"))
local VaultCatalog = require(Shared:WaitForChild("VaultCatalog"))

local Server = ServerScriptService:WaitForChild("Server")
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local RemoteGateway = require(Server:WaitForChild("RemoteGateway"))
local RollService = require(Server:WaitForChild("RollService"))
local ForgeService = require(Server:WaitForChild("ForgeService"))
local StateSyncService = require(Server:WaitForChild("StateSyncService"))
local PurchaseService = require(Server:WaitForChild("PurchaseService"))
local OfflineService = require(Server:WaitForChild("OfflineService"))
local LeaderboardService = require(Server:WaitForChild("LeaderboardService"))
local ProgressionService = require(Server:WaitForChild("ProgressionService"))
local AscensionService = require(Server:WaitForChild("AscensionService"))
local EconomyService = require(Server:WaitForChild("EconomyService"))

-- Persistence comes up FIRST and explicitly. A lazy init hidden inside load()
-- would make the failure surface at a player's join instead of at server start.
PlayerProfile.init()

-- Materialise every declared remote before any handler binds, so a client that
-- joins early resolves its WaitForChild immediately instead of racing first use.
Remotes.createAll()

-- MONETISATION. This installs the place's ONE `ProcessReceipt` assignment
-- (threat T-17) and must happen before any player can be admitted: a receipt
-- can arrive the instant a session begins, and an unassigned handler means
-- Roblox has nowhere to deliver it.
--
-- The announcer is injected rather than imported so PurchaseService does not
-- depend on StateSyncService directly; a grant pushes a fresh snapshot the
-- same way every other mutation does.
PurchaseService.setAnnouncer(StateSyncService.push)
PurchaseService.init()

-- THE VAULT'S FIGURES IN THE SNAPSHOT (FR-8), injected at the composition root
-- for the same reason the announcer above is: StateSyncService is imported by
-- nearly everything, so it must import as little as possible itself (L-035).
--
-- Before this, the snapshot carried nothing about the vault at all. The panel
-- could only state a CAPACITY in hours and the player discovered what had
-- actually accrued by pressing CLAIM -- the offline reward, which is the reason
-- an idle player opens the game, was invisible until the moment it was spent.
StateSyncService.setVaultProvider(OfflineService.getStatus)

-- How many more Gem-hours would actually help. A VIP player's 24h floor already
-- exceeds every other capacity source combined, so for them the answer is zero
-- and the VAULT panel must not offer a purchase that would do nothing.
StateSyncService.setBuyableHoursProvider(OfflineService.effectiveBuyableHours)

-- THE 2x-CASH MULTIPLIER, injected for the same reason and to break a real
-- cycle. `EconomyService.award` needs the gamepass multiplier that
-- `PurchaseService` owns, but PurchaseService already depends on this module's
-- siblings, so requiring it back formed
-- EconomyService -> PurchaseService -> OfflineService -> EconomyService.
--
-- That was previously worked around with a lazy require inside `award` (L-035),
-- which runs correctly and still leaves the analyser reporting the cycle at
-- four sites -- the edge exists, merely deferred. Registering the function here
-- inverts the edge instead of hiding it: EconomyService never names
-- PurchaseService, and the dependency graph is genuinely acyclic.
EconomyService.setCashMultiplierProvider(PurchaseService.cashMultiplier)

-- VIP VAULT OWNERSHIP, injected for the same reason. `OfflineService` applies
-- the VIP capacity floor in three places and needed `PurchaseService.ownsPass`
-- for each, which it reached by lazy-requiring PurchaseService inside all three
-- function bodies. One registration replaces all three, and removes the
-- per-call `WaitForChild` they each performed.
OfflineService.setOwnsPassProvider(PurchaseService.ownsPass)

-- THE DICE SOLIDS. Generated ONCE, on the server, into ReplicatedStorage.
do
	local ok, err = pcall(function()
		local DiceMeshBuilder = require(ReplicatedStorage.Shared:WaitForChild("DiceMeshBuilder"))
		DiceMeshBuilder.generateAllDice()
	end)
	if not ok then
		warn("[Bootstrap] dice geometry generation failed; tiles will fall back to flat numerals: " .. tostring(err))
	end
end

-- QUEST PROGRESS, wired at the composition root.
--
-- RollService and ForgeService do not require ProgressionService: quests OBSERVE
-- play, and the systems being observed should not know about the observer. This
-- is also what keeps the module graph acyclic (ledger L-035).
RollService.setRollObserver(function(player: Player, streak: number)
	ProgressionService.advanceQuests(player, "rolls", 1, false)
	-- bestStreak is a GAUGE, not a counter: the quest wants the highest streak
	-- reached, so it takes a maximum rather than a sum.
	ProgressionService.advanceQuests(player, "bestStreak", streak, true)
end)

ForgeService.setForgeObserver(function(player: Player)
	ProgressionService.advanceQuests(player, "forges", 1, false)
end)

--------------------------------------------------------------------------------
-- STUDIO-ONLY PLAYTEST DIE COUNT
--
-- Sets the player's die count to exactly this on join, so the board can be felt
-- at populations the normal progression takes a long time to reach. Requested by
-- the operator 2026-08-13 to try thirty dice rolling together.
--
-- ZERO DISABLES IT, AND ZERO IS WHAT SHIPS. **SET THIS BACK TO 0 BEFORE
-- RELEASE** -- it is listed in the handoff's housekeeping alongside the
-- ascension threshold, the other constant currently carrying a test value.
--
-- WHY A GUARD AND NOT JUST A COMMENT. `RunService:IsStudio()` is false in every
-- live server, so this cannot touch a real player's profile even if it ships set
-- to thirty. A comment saying "remember to turn this off" protects nobody; the
-- guard does. It is also why this is not a remote: a client-triggerable "give me
-- thirty dice" is an economic exploit surface, and there is no reason to build
-- one when the playtest runs in Studio anyway.
--
-- EXACT, NOT ADDITIVE. It trims as well as grants, so lowering the number gives
-- a smaller board on the next join rather than stranding the profile at whatever
-- the high-water mark was. Without that this would be a one-way door.
-- ZERO = OFF, which is the shipping state (restored 2026-08-15 at the
-- operator's request). Set it to a positive number in Studio to force that many
-- dice on the board for a playtest; the guard below makes it inert in any live
-- server regardless.
local PLAYTEST_DIE_COUNT = 0

local function applyPlaytestDieCount(player: Player): ()
	if PLAYTEST_DIE_COUNT <= 0 or not RunService:IsStudio() then
		return
	end

	local target = math.floor(PLAYTEST_DIE_COUNT)
	local applied = 0

	PlayerProfile.mutate(player, function(d)
		while #d.Dice > target do
			table.remove(d.Dice)
		end
		while #d.Dice < target do
			table.insert(d.Dice, DiceCatalog.newStartingDie())
		end
		d.DieSlots = #d.Dice
		applied = #d.Dice
	end)

	warn(string.format(
		"[Bootstrap] STUDIO PLAYTEST: die count forced to %d for UserId=%d."
		.. " PLAYTEST_DIE_COUNT must be 0 before release.",
		applied, player.UserId))
end

-- How long a new player's starter offer stays open. 48 hours: long enough to
-- span a weekend and see the game properly, short enough to mean something.
--
-- FR-12.5 -- this is a REAL deadline. It is stamped once per player and never
-- moved, and there is deliberately no code anywhere that can extend it.
local STARTER_BUNDLE_WINDOW_SEC = 48 * 3600

local function announcing<T...>(handler: (Player, T...) -> (boolean, string?))
	return function(player: Player, ...: T...): (boolean, string?)
		local ok, reason = handler(player, ...)
		if ok then
			StateSyncService.push(player)
		end
		return ok, reason
	end
end

--------------------------------------------------------------------------------
-- Remote Handlers (P-5C2: 100% of declared remotes registered)
--------------------------------------------------------------------------------

RemoteGateway.register("Roll", announcing(function(player: Player)
	return RollService.performRoll(player)
end))

RemoteGateway.register("SetAutoRoll", announcing(function(player: Player, enabled: boolean)
	local ok, reason = RemoteGateway.V.strictBoolean(enabled)
	if not ok then
		return false, reason
	end
	if enabled and not PurchaseService.hasAutoRoll(player) then
		return false, Remotes.Notice.NotUnlocked
	end
	-- WAS `return true, nil` after the ownership check: the preference was
	-- validated and then DISCARDED, so toggling auto-roll changed nothing and
	-- the server never learned the player wanted it. RollService owns the
	-- interval enforcement (FR-7.2); this records the intent it acts on.
	return RollService.setAutoRoll(player, enabled)
end))

RemoteGateway.register("BuyUpgrade", announcing(function(player: Player, upgradeId: string)
	local ok, reason = RemoteGateway.V.boundedString(upgradeId, RemoteGateway.MAX_STRING_ID)
	if not ok then
		return false, reason
	end
	local def = UpgradeCatalog.getCashUpgrade(upgradeId)
	if not def then
		return false, Remotes.Notice.InvalidRequest
	end
	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end
	local currentLvl = data.Upgrades[upgradeId] or 0
	if currentLvl >= def.maxLevel then
		return false, Remotes.Notice.InvalidRequest
	end
	local cost = UpgradeCatalog.getCashUpgradeCost(upgradeId, currentLvl)
	if not EconomyService.canAfford(player, "Cash", cost) then
		return false, Remotes.Notice.InsufficientFunds
	end
	local spent = EconomyService.spend(player, "Cash", cost, "buy_upgrade")
	if not spent then
		return false, Remotes.Notice.InsufficientFunds
	end
	PlayerProfile.mutate(player, function(d)
		d.Upgrades[upgradeId] = currentLvl + 1

		-- MASS BUDGET is the one Cash upgrade that changes a DIE rather than a
		-- multiplier, so the level alone is not the effect -- the die has to
		-- actually get bigger, and the new mass has to land somewhere legal or
		-- `assertDieInvariant` will reject the next write.
		--
		-- Applied to EVERY die the player owns: the upgrade is an account-level
		-- entitlement, and granting it to die 1 only would make extra slots
		-- strictly worse the moment a player bought one.
		if upgradeId == "MassBudget" then
			local grant = UpgradeCatalog.MASS_PER_LEVEL
			for _, die in ipairs(d.Dice) do
				local shape = DiceCatalog.getShape(die.Shape)
				if shape ~= nil then
					-- Capped by the SHAPE. Past this the Diamond tree is the only
					-- way up, which is FR-3.6's two-stage design.
					local ceiling = shape.cashBudgetCap
					local target = math.min(ceiling, die.PurchasedBudget + grant)
					local added = target - die.PurchasedBudget
					if added > 0 then
						die.PurchasedBudget = target
						die.MassBudget += added
						-- The new mass goes onto the LIGHTEST face. Anywhere else
						-- would silently reshape a distribution the player tuned;
						-- the lightest face is the one they have already chosen to
						-- starve, so adding there disturbs their build least.
						local lightest, lightestIdx = math.huge, 1
						for i, f in ipairs(die.Faces) do
							if f.Mass < lightest then
								lightest, lightestIdx = f.Mass, i
							end
						end
						die.Faces[lightestIdx].Mass += added
					end
				end
			end
		end
	end)
	return true, nil
end))

RemoteGateway.register("BuyDiamondNode", announcing(function(player: Player, nodeId: string)
	local ok, reason = RemoteGateway.V.boundedString(nodeId, RemoteGateway.MAX_STRING_ID)
	if not ok then
		return false, reason
	end
	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end

	-- SHAPE UNLOCKS (FR-9.3, and the ladder added 2026-08-11).
	--
	-- Shapes live in the Diamond tree as a BOOLEAN table, not a level counter, so
	-- they cannot go through the numeric path below -- it would write
	-- `Diamond.Shapes = 1` and destroy the table.
	--
	-- THIS PATH DID NOT EXIST BEFORE. `SetShape` has always checked
	-- `data.Diamond.Shapes[shapeId]`, and nothing anywhere set it to true beyond
	-- the one shape granted in the profile template. Every other shape was
	-- therefore permanently unreachable: the requirement was specified (FR-9.3),
	-- the READ was implemented, and the WRITE was missing -- ledger L-027 exactly.
	if DiceCatalog.getUnlockCost(nodeId) ~= nil then
		-- The ladder rule is asked of DiceCatalog rather than restated here, so
		-- the server, the client's button state and the tests cannot disagree
		-- about what is unlockable (L-025).
		local allowed, why = DiceCatalog.canUnlock(nodeId, data.Diamond.Shapes)
		if not allowed then
			return false, if why == "prerequisite_locked"
				then Remotes.Notice.NotUnlocked
				else Remotes.Notice.InvalidRequest
		end

		local shapeCost = DiceCatalog.getUnlockCost(nodeId) :: number
		-- Priced in Cash, not Diamonds. The currency is read from the catalog so
		-- this cannot drift from what the shop displays.
		local currency = DiceCatalog.UNLOCK_CURRENCY
		if not EconomyService.canAfford(player, currency, shapeCost) then
			return false, Remotes.Notice.InsufficientFunds
		end
		if not EconomyService.spend(player, currency, shapeCost, "unlock_shape") then
			return false, Remotes.Notice.InsufficientFunds
		end
		-- Re-checked INSIDE the mutation. `canAfford`/`spend` are separate calls
		-- and the ladder must not be satisfiable by two requests racing between
		-- them (T-26's shape: verify synchronously with the write).
		local wrote = PlayerProfile.mutate(player, function(d)
			local stillAllowed = DiceCatalog.canUnlock(nodeId, d.Diamond.Shapes)
			if stillAllowed then
				d.Diamond.Shapes[nodeId] = true
			end
		end)
		return wrote, if wrote then nil else Remotes.Notice.ProfileUnavailable
	end

	local def = UpgradeCatalog.getDiamondNode(nodeId)
	if not def then
		return false, Remotes.Notice.InvalidRequest
	end
	local currentLvl = data.Diamond[nodeId] or 0
	if currentLvl >= def.maxLevel then
		return false, Remotes.Notice.InvalidRequest
	end
	local cost = UpgradeCatalog.getDiamondNodeCost(nodeId, currentLvl)
	if not EconomyService.canAfford(player, "Diamonds", cost) then
		return false, Remotes.Notice.InsufficientFunds
	end
	local spent = EconomyService.spend(player, "Diamonds", cost, "buy_diamond_node")
	if not spent then
		return false, Remotes.Notice.InsufficientFunds
	end
	PlayerProfile.mutate(player, function(d)
		d.Diamond[nodeId] = currentLvl + 1
	end)
	return true, nil
end))

-- BUYS ANOTHER DIE, optionally of a chosen shape.
--
-- `shapeId` is OPTIONAL (operator decision, 2026-08-13: "in shape we need to add
-- options to buy multiple of the same dice - this helps progression"). Omitted,
-- the new die is the starting shape, which is what the SLOTS panel has always
-- asked for. Supplied, the player gets another die of a shape they already own,
-- so SHAPE becomes a second route to growing the board.
--
-- ONE HANDLER, ONE PRICE, ONE CAP. Buying "a second D6" and buying "one more
-- die" are the same transaction with a different starting shape, so they share
-- the slot price curve and the ascension cap rather than getting a parallel set
-- that could drift out of step (L-025).
--
-- OWNERSHIP STAYS BOOLEAN. Nothing in the saved schema changes: `Diamond.Shapes`
-- still records whether a shape is unlocked, and the repeat purchase is what
-- adds the die. Turning that set into counts would have meant migrating every
-- live profile for no gain the player can see.
RemoteGateway.register("AddDieSlot", announcing(function(player: Player, shapeId: string)
	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end

	-- The shape for the new die. THE EMPTY STRING means "the starting shape",
	-- which is what the SLOTS panel asks for and the safe default. A sentinel
	-- rather than nil because the gateway's arity check is exact -- see ARITY.
	if type(shapeId) ~= "string" then
		return false, Remotes.Notice.InvalidRequest
	end
	local chosen = DiceCatalog.STARTING_SHAPE
	if shapeId ~= "" then
		local okShape, shapeReason = RemoteGateway.V.boundedString(shapeId, RemoteGateway.MAX_STRING_ID)
		if not okShape then
			return false, shapeReason
		end
		-- MUST BE OWNED. Without this, `AddDieSlot("D20")` would hand a new player
		-- the top of the ladder for the price of a slot -- the die array is written
		-- directly and never passes through `SetShape`'s ownership check.
		if data.Diamond.Shapes[shapeId] ~= true then
			return false, Remotes.Notice.NotUnlocked
		end
		if DiceCatalog.getShape(shapeId) == nil then
			return false, Remotes.Notice.InvalidRequest
		end
		chosen = shapeId
	end
	-- THE CAP RISES WITH ASCENSIONS (operator decision, 2026-08-13). A player at
	-- zero ascensions tops out at 3 dice; each prestige adds one, to a hard
	-- maximum of 7.
	--
	-- NEVER CONFISCATES. A player who already owns more slots than their current
	-- ascension count permits -- which every existing profile does, since the cap
	-- used to be a flat 7 -- keeps every die they have. This check only refuses
	-- to sell them ANOTHER one. Taking a purchased slot away because a rule
	-- changed underneath them would be the worst possible reading of this.
	local slotCap = DiceCatalog.dieSlotCapFor(data.Ascensions)
	if data.DieSlots >= slotCap then
		return false, Remotes.Notice.InvalidRequest
	end
	-- Priced by the shared catalog, which is also what the SLOTS panel reads to
	-- print the number on the button -- so the quoted price and the charged price
	-- are the same expression, not two copies of it (L-025).
	local cost = DiceCatalog.dieSlotCost(data.DieSlots, data.Ascensions)
	if cost == nil then
		return false, Remotes.Notice.InvalidRequest
	end
	if not EconomyService.canAfford(player, "Cash", cost) then
		return false, Remotes.Notice.InsufficientFunds
	end
	local spent = EconomyService.spend(player, "Cash", cost, "add_die_slot")
	if not spent then
		return false, Remotes.Notice.InsufficientFunds
	end
	-- THE NEW DIE, built from the shared factory at the chosen shape.
	--
	-- This used to hardcode a D6 with six 10-mass faces. Once the Cash ladder
	-- landed and the starting shape became D2, buying a slot handed the player a
	-- D6 -- three rungs up a ladder they were meant to climb, and a shape they
	-- very likely did not own. Nothing refused it, because a die written straight
	-- into the profile never passes through `SetShape`'s ownership check, which
	-- is also why `chosen` is validated against ownership above.
	local makeDie = function()
		return DiceCatalog.newDie(chosen)
	end
	if makeDie() == nil then
		return false, Remotes.Notice.ServerError
	end
	-- Through the shared helper, so all THREE grant paths -- this, the +2 Die
	-- Slots pass and the Starter Bundle -- increment the counter and create the
	-- die by the same code. Two of the three used to write the counter alone.
	PlayerProfile.mutate(player, function(d)
		PlayerProfile.grantDieSlots(d, 1, slotCap, makeDie)
	end)
	return true, nil
end))

RemoteGateway.register("Ascend", announcing(function(player: Player)
	local ok, reason, _ = AscensionService.ascend(player)
	return ok, reason
end))

RemoteGateway.register("ClaimVault", announcing(function(player: Player, doubled: boolean)
	local okBool, reason = RemoteGateway.V.strictBoolean(doubled)
	if not okBool then
		return false, reason
	end
	local ok, claimReason, _ = OfflineService.claimVault(player, doubled)
	return ok, claimReason
end))

-- BUY VAULT CAPACITY WITH GEMS (FR-8; operator decision 2026-08-13, "5 gems
-- means 1 hour of storage", +8h cap approved).
--
-- THE GAME'S FIRST AND ONLY GEMS SINK, so it is treated as an economic surface
-- rather than a UI feature:
--
--   * ARITY AND RANGE ARE VALIDATED HERE, at the boundary, before the request
--     reaches anything that can move currency (F-4A-1). `integerInRange` rejects
--     a non-integer, a non-finite, and anything outside 1..MAX_PURCHASE_HOURS
--     -- so no absurd figure can enter the cost arithmetic.
--   * THE CAP IS ENFORCED SERVER-SIDE, twice, and neither place trusts the
--     other: `buyVaultHours` refuses past it on write, and `getCapacity` clamps
--     on read. The panel also shows it, but a client-side cap is a suggestion.
--   * RATE LIMITED by the gateway's token bucket like every other remote, so a
--     spend loop cannot be driven faster than a person can press a button.
--
-- `announcing` pushes a fresh snapshot on success, so the panel repaints from
-- server truth rather than predicting the new balance (L-042).
RemoteGateway.register("BuyVaultHours", announcing(function(player: Player, hours: number)
	local okRange, reason = RemoteGateway.V.integerInRange(hours, 1, VaultCatalog.MAX_PURCHASE_HOURS_PER_CALL)
	if not okRange then
		return false, reason
	end
	local ok, buyReason, _ = OfflineService.buyVaultHours(player, hours)
	return ok, buyReason
end))

RemoteGateway.register("DailySpin", announcing(function(player: Player)
	local ok, reason, _, _ = ProgressionService.claimDailySpin(player)
	return ok, reason
end))

-- SWAP TWO DICE (FR-1.1, operator-requested 2026-08-13: "in forge there has to
-- be an option for you to select which dice sits on which slot").
--
-- Position in `d.Dice` IS the board slot -- the renderer walks the array in
-- order and the forge's tabs are indexed by it -- so reordering the array is the
-- whole feature. The data model already supported this; nothing exposed it.
--
-- (The board itself no longer derives a POSITION from the index: dice scatter
-- organically across a shared felt. Order still decides which die a forge tab
-- edits, which is what this remote is for.)
--
-- CARRIES NO ECONOMIC VALUE. The same dice end up in the player's profile, in a
-- different order: no mass is created, destroyed or moved between dice, and no
-- currency changes hands. That is what makes it safe to allow freely.
--
-- Both indices are validated against the player's ACTUAL die count rather than
-- the slot entitlement, because those can differ and only the array is real.
RemoteGateway.register("SwapDice", announcing(function(player: Player, a: number, b: number)
	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end

	local count = #data.Dice
	local okA, reasonA = RemoteGateway.V.integerInRange(a, 1, count)
	if not okA then
		return false, reasonA
	end
	local okB, reasonB = RemoteGateway.V.integerInRange(b, 1, count)
	if not okB then
		return false, reasonB
	end
	-- Swapping a die with itself is a no-op, not an error, but it must not cost a
	-- profile write or a snapshot push.
	if a == b then
		return false, Remotes.Notice.InvalidRequest
	end

	-- Re-read the bounds INSIDE the mutation. `#data.Dice` was measured before
	-- this write was queued, and an ascension resolving in between would shrink
	-- the array under us -- writing to a stale index would then create a hole.
	local wrote = PlayerProfile.mutate(player, function(d)
		local n = #d.Dice
		if a < 1 or a > n or b < 1 or b > n then
			return
		end
		d.Dice[a], d.Dice[b] = d.Dice[b], d.Dice[a]
	end)
	return wrote, if wrote then nil else Remotes.Notice.ProfileUnavailable
end))

-- SETTINGS (FR-13.6). The write path that made the panel possible.
--
-- WHAT WAS TRUE BEFORE: `PlayerProfile` declared four settings, StateSyncService
-- faithfully emitted them, and `FeedbackFX` read two of them off every snapshot.
-- Everything was in place except the ability to CHANGE one -- there was no
-- remote, so the values were permanently whatever the template said. Read
-- implemented, write absent: ledger L-027, for the third time.
--
-- THE KEY IS ALLOWLISTED THROUGH `SettingsCatalog.isSetting`, never used to
-- index the profile directly. `d.Settings[key] = value` with an unchecked key
-- would let a client create arbitrary profile fields and grow the saved document
-- without bound (threats T-5, Matrix E-1/E-2).
--
-- NOTHING ECONOMIC CAN CROSS HERE by construction: the payload is one allowlisted
-- key and one strict boolean, and no setting in the catalog gates a reward, a
-- rate or a price. There is no shape of call that could name a value.
RemoteGateway.register("SetSetting", announcing(function(player: Player, key: string, enabled: boolean)
	local okKey, keyReason = RemoteGateway.V.boundedString(key, RemoteGateway.MAX_STRING_ID)
	if not okKey then
		return false, keyReason
	end
	if not SettingsCatalog.isSetting(key) then
		return false, Remotes.Notice.InvalidRequest
	end
	-- STRICT boolean. Accepting a truthy value would let a client send the string
	-- "false" and have it stored as an enabled setting.
	local okVal, valReason = RemoteGateway.V.strictBoolean(enabled)
	if not okVal then
		return false, valReason
	end

	local wrote = PlayerProfile.mutate(player, function(d)
		d.Settings[key] = enabled
	end)
	return wrote, if wrote then nil else Remotes.Notice.ProfileUnavailable
end))

RemoteGateway.register("RedeemCode", announcing(function(player: Player, code: string)
	local ok, reason = RemoteGateway.V.boundedString(code, RemoteGateway.MAX_STRING_CODE)
	if not ok then
		return false, reason
	end
	return ProgressionService.redeemCode(player, code)
end))

-- GROUP REWARDS -- UNPLUGGED 2026-08-11 (operator-directed), not deleted.
--
-- WHY IT IS COMMENTED RATHER THAN REMOVED: the feature is complete and correct
-- on the server side -- `ProgressionService.claimGroupReward` really does verify
-- membership through the platform and fails closed on an unset group id. What is
-- missing is the OPERATOR'S GROUP, and there is no reason to throw away working
-- code while waiting for a configuration value.
--
-- TO BRING IT BACK: set `ProgressionService.GROUP_ID` to the real group and
-- uncomment the two lines below. Nothing else needs changing -- the claim path,
-- the once-only flag and the membership check are all still in place and still
-- covered by their own logic.
--
-- While unplugged the remote is DECLARED but unhandled, so a call returns the
-- gateway's default refusal rather than reaching a reward path. That is the
-- correct failure: silence, not a grant.
--
-- RemoteGateway.register("ClaimGroupReward", announcing(function(player: Player)
-- 	return ProgressionService.claimGroupReward(player)
-- end))

RemoteGateway.register("ClaimQuest", announcing(function(player: Player, questId: string)
	-- WAS `return true, nil`: it granted nothing and reported SUCCESS, so the
	-- client showed a claimed quest and the player received no reward. A handler
	-- that lies about delivering is worse than one that is missing.
	local okStr, reason = RemoteGateway.V.boundedString(questId, RemoteGateway.MAX_STRING_ID)
	if not okStr then
		return false, reason
	end
	return ProgressionService.claimQuest(player, questId)
end))

RemoteGateway.register("ClaimChest", announcing(function(player: Player, tierId: string)
	-- WAS `return true, nil`, same defect as ClaimQuest.
	local okStr, reason = RemoteGateway.V.boundedString(tierId, RemoteGateway.MAX_STRING_ID)
	if not okStr then
		return false, reason
	end
	return ProgressionService.claimChest(player, tierId)
end))

RemoteGateway.register("GetLeaderboard", function(player: Player, boardId: string)
	local ok, reason = RemoteGateway.V.boundedString(boardId, RemoteGateway.MAX_STRING_ID)
	if not ok then
		return nil, nil
	end
	local entries = LeaderboardService.getBoard(boardId)
	-- The player's REAL rank, or nil when they are not on the board. This
	-- returned a hardcoded `1` -- every player was told they were first in the
	-- world, which is a fabricated score and exactly the kind of invented figure
	-- the client must never be handed.
	return entries, LeaderboardService.getPlayerRank(player, boardId)
end)

ForgeService.registerHandlers(announcing)

RemoteGateway.bind()

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------

-- Idempotent by contract: the queue drain, the PlayerAdded connection, and the
-- post-init sweep can all reach the same player, and admitting twice must be a
-- no-op rather than a second session claim.
admitPlayer = function(player: Player)
	if player.Parent ~= Players then
		return -- left during startup; nothing to admit
	end
	if PlayerProfile.isActive(player) then
		return -- already admitted by another path
	end

	local loaded, reason = PlayerProfile.load(player)
	if not loaded then
		-- Threat T-10: fail closed. Never serve a phantom profile that could
		-- overwrite real saved data, and never leave the player seated with no
		-- profile either. The reason stays in the server log; the player sees an
		-- honest, non-diagnostic message.
		warn(string.format("[Bootstrap] profile load FAILED for UserId=%d: %s -- kicking",
			player.UserId, tostring(reason)))
		if player.Parent == Players then
			player:Kick("Your data could not be loaded safely. Please rejoin.")
		end
		return
	end

	-- STUDIO-ONLY PLAYTEST DIE COUNT. Applied before validation so the dice it
	-- creates are checked like any other.
	applyPlaytestDieCount(player)

	-- Validate the loaded profile against the die contract BEFORE the session
	-- starts, so the first roll cannot be resolved against an illegal die. The
	-- invariant guards every write in ForgeService; without this it guarded
	-- nothing on the way IN, and four defects in this block wrote invalid dice
	-- before they were caught. Repairs are logged with a count, never silent.
	local repaired = ForgeService.validateStoredDice(player)

	-- Gamepass ownership. Resolved in its own thread because it makes network
	-- calls: a slow or hanging Roblox lookup must not delay admission, and the
	-- entitlements it caches are read only after the player is already seated.
	-- Until it completes every pass reads as NOT owned, which is the
	-- fail-closed direction.
	task.spawn(function()
		PurchaseService.onPlayerAdded(player)
		-- MATERIALISE PASS-GRANTED SLOTS once ownership is known. The +2 Die
		-- Slots bonus used to be added to the snapshot at display time only, so
		-- it was never persisted and no dice were created for it -- the player
		-- saw four slots and rolled two dice. Idempotent, so running it on every
		-- join does not stack.
		if PlayerProfile.isActive(player) then
			PurchaseService.applyPassSlotGrant(player)
		end
		-- Re-push once entitlements are known, or the client would show the
		-- pre-ownership snapshot until the next state change.
		if PlayerProfile.isActive(player) then
			StateSyncService.push(player)
		end
	end)

	-- FREEZE THE OFFLINE WINDOW before anything can read the vault.
	--
	-- Must run BEFORE the first StateSync push, or the client's opening snapshot
	-- carries a live-clock figure that then jumps when the freeze lands. It also
	-- must run AFTER `PlayerProfile.load`, since it reads `Vault.LastSeen`.
	OfflineService.beginSession(player)

	RollService.beginSession(player)
	-- Quests, chests and the login streak are all session- or day-scoped and
	-- must start their clocks at admission, not at first use.
	ProgressionService.beginSession(player)

	-- FR-12.5, THE ONCE-ONLY STARTER OFFER, stamped here and nowhere else.
	--
	-- Written only when it is still zero, so this runs exactly once in a player's
	-- lifetime. There is no path that extends, resets, or re-opens it -- which is
	-- the entire requirement: "once it expires the offer is permanently gone for
	-- that player and never reappears under any name."
	--
	-- If this ever needs changing, changing it is the violation.
	do
		local d = PlayerProfile.get(player)
		if d ~= nil and d.BundleExpiry == 0 then
			PlayerProfile.mutate(player, function(profile)
				profile.BundleExpiry = os.time() + STARTER_BUNDLE_WINDOW_SEC
			end)
		end
	end

	-- The client displays NOTHING until this lands: no balances, no die shapes,
	-- no entitlements, no settings. Pushed after beginSession so the snapshot
	-- carries a real streak rather than a zero that is about to change.
	StateSyncService.push(player)

	print(string.format("[Bootstrap] admitted UserId=%d%s", player.UserId,
		if repaired > 0 then string.format(" (%d die/dice repaired)", repaired) else ""))
end

--------------------------------------------------------------------------------
-- THE AUTO-ROLL HEARTBEAT (FR-7.1, FR-7.2)
--
-- One server-side loop drives every auto-rolling session. The tick rate here is
-- only how often intervals are CHECKED; the interval each player actually gets
-- is decided inside RollService from their upgrades and entitlements, so a fast
-- tick cannot make anyone roll faster than they are entitled to.
--
-- 0.25 s is comfortably below the 0.4 s Ultra floor, so the fastest entitled
-- player is not throttled by the checking cadence itself.
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.25)
		-- The whole sweep is wrapped: an error in one tick must never kill the
		-- loop and silently strand every auto-rolling player on the server.
		local ok, err = pcall(RollService.stepAutoRoll)
		if not ok then
			warn("[Bootstrap] auto-roll tick failed: " .. tostring(err))
		end
	end
end)

local function onPlayerRemoving(player: Player)
	RollService.endSession(player)
	ProgressionService.endSession(player)

	-- STAMP THE VAULT CLOCK (FR-8). This call did not exist, and its absence
	-- disabled the entire offline-earnings feature: `Vault.LastSeen` is what
	-- `getStatus` measures elapsed time from, nothing else ever writes it on
	-- exit, and a LastSeen that never advances means `elapsed` is computed from
	-- a stale or zero timestamp forever.
	--
	-- It stayed invisible because the snapshot carried no vault figures until
	-- today -- the panel showed a capacity in hours and no accrual, so there was
	-- nothing on screen that could have looked wrong. Wiring the display is what
	-- surfaced it: the vault read 0s after a real 90-second absence.
	--
	-- MUST run before `PlayerProfile.release`, because it MUTATES the profile and
	-- a released profile refuses writes.
	OfflineService.onPlayerRemoving(player)

	-- Released BEFORE the profile: the entitlement cache is keyed by Player and
	-- would otherwise hold a reference to a departed one.
	PurchaseService.onPlayerRemoving(player)
	PlayerProfile.release(player)
end

Players.PlayerRemoving:Connect(onPlayerRemoving)

--------------------------------------------------------------------------------
-- Open the doors
--------------------------------------------------------------------------------

servicesReady = true

-- Drain anyone who joined while the services were still coming up.
local queued = joinQueue
joinQueue = {}
for _, player in ipairs(queued) do
	task.spawn(admitPlayer, player)
end

-- Belt and braces: anyone already present who reached neither path. admitPlayer
-- is idempotent, so overlap with the drain is harmless.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(admitPlayer, player)
end

-- A player with no profile is a player the join path lost. Rather than let that
-- state persist silently -- which is exactly how it went unnoticed the first
-- time -- sweep once shortly after startup and admit or kick anyone stranded.
task.delay(10, function()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent == Players and not PlayerProfile.isActive(player) then
			warn(string.format(
				"[Bootstrap] UserId=%d was seated with no profile -- the join path missed them",
				player.UserId))
			task.spawn(admitPlayer, player)
		end
	end
end)

--------------------------------------------------------------------------------
-- Graceful shutdown
--------------------------------------------------------------------------------

game:BindToClose(function()
	joinConnection:Disconnect()
	PlayerProfile.releaseAll()
end)
