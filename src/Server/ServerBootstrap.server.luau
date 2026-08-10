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

RemoteGateway.register("AddDieSlot", announcing(function(player: Player)
	local data = PlayerProfile.get(player)
	if not data then
		return false, Remotes.Notice.ProfileUnavailable
	end
	if data.DieSlots >= 7 then
		return false, Remotes.Notice.InvalidRequest
	end
	local cost = 1000 * (2 ^ (data.DieSlots - 1))
	if not EconomyService.canAfford(player, "Cash", cost) then
		return false, Remotes.Notice.InsufficientFunds
	end
	local spent = EconomyService.spend(player, "Cash", cost, "add_die_slot")
	if not spent then
		return false, Remotes.Notice.InsufficientFunds
	end
	PlayerProfile.mutate(player, function(d)
		d.DieSlots = math.min(7, d.DieSlots + 1)
		table.insert(d.Dice, {
			Shape = "D6",
			MassBudget = 60,
			PurchasedBudget = 60,
			Faces = {
				{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
				{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
				{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
			},
		})
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

RemoteGateway.register("DailySpin", announcing(function(player: Player)
	local ok, reason, _, _ = ProgressionService.claimDailySpin(player)
	return ok, reason
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
	return entries, 1
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
		-- Re-push once entitlements are known, or the client would show the
		-- pre-ownership snapshot until the next state change.
		if PlayerProfile.isActive(player) then
			StateSyncService.push(player)
		end
	end)

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
