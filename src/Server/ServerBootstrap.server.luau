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

local Server = ServerScriptService:WaitForChild("Server")
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local RemoteGateway = require(Server:WaitForChild("RemoteGateway"))
local RollService = require(Server:WaitForChild("RollService"))
local ForgeService = require(Server:WaitForChild("ForgeService"))
local StateSyncService = require(Server:WaitForChild("StateSyncService"))
local PurchaseService = require(Server:WaitForChild("PurchaseService"))

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
--
-- WHY THE SERVER AND NOT EACH CLIENT. Built here, the models replicate to every
-- player automatically and the geometry is computed a single time for the whole
-- server. Built per-client, each machine would spend the same work privately and
-- two clients could in principle disagree about what a die looks like.
--
-- WHY AT BOOT AND NOT ON DEMAND. The renderer clones these into ViewportFrames
-- the moment StateSync delivers a shape. Generating lazily would mean the first
-- player to arrive sees empty tiles until the build finished -- and a die that
-- is *absent* looks exactly like a die that is *broken*.
--
-- THE RENDERER TOLERATES THEIR ABSENCE ANYWAY. If this ever fails, tiles fall
-- back to the flat numeral rather than rendering nothing, which is why this is
-- wrapped: dice geometry is presentation, and no failure of it may stop a server
-- that can still roll, credit and save.
do
	local ok, err = pcall(function()
		local DiceMeshBuilder = require(ReplicatedStorage.Shared:WaitForChild("DiceMeshBuilder"))
		DiceMeshBuilder.generateAllDice()
	end)
	if not ok then
		warn("[Bootstrap] dice geometry generation failed; tiles will fall back to flat numerals: " .. tostring(err))
	end
end

-- EVERY state change owes the client a snapshot, or the display silently drifts
-- from the truth. Wrapping the handlers here rather than pushing from inside
-- each service keeps that obligation in ONE place: a future handler added
-- without a push is visible as a missing wrapper, not as a UI that quietly
-- stops updating.
local function announcing<T...>(handler: (Player, T...) -> (boolean, string?))
	return function(player: Player, ...: T...): (boolean, string?)
		local ok, reason = handler(player, ...)
		if ok then
			StateSyncService.push(player)
		end
		return ok, reason
	end
end

RemoteGateway.register("Roll", announcing(function(player: Player)
	return RollService.performRoll(player)
end))

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

	-- The client displays NOTHING until this lands: no balances, no die shapes,
	-- no entitlements, no settings. Pushed after beginSession so the snapshot
	-- carries a real streak rather than a zero that is about to change.
	StateSyncService.push(player)

	print(string.format("[Bootstrap] admitted UserId=%d%s", player.UserId,
		if repaired > 0 then string.format(" (%d die/dice repaired)", repaired) else ""))
end

local function onPlayerRemoving(player: Player)
	RollService.endSession(player)
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
