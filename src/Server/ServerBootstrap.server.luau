--!strict
-- ServerBootstrap.server.luau
-- Server entry point. Constructs services in explicit dependency order, wires
-- player lifecycle, registers remotes via RemoteGateway, and handles BindToClose.
--
-- HLD §3 C-1, SRS FR-14.3, Threat T-10:
--   A failed profile load FAILS CLOSED -- the player is kicked with an honest message.
--   A default profile is NEVER served to a player whose load failed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Server = ServerScriptService:WaitForChild("Server")
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local EconomyService = require(Server:WaitForChild("EconomyService"))
local RemoteGateway = require(Server:WaitForChild("RemoteGateway"))
local RollService = require(Server:WaitForChild("RollService"))
local ForgeService = require(Server:WaitForChild("ForgeService"))

--------------------------------------------------------------------------------
-- Handler registration
--------------------------------------------------------------------------------

-- Persistence comes up FIRST and explicitly. A lazy init hidden inside load()
-- would make the failure surface at a player's join instead of at server start.
PlayerProfile.init()

-- Materialise every declared remote before any handler binds, so a client that
-- joins early resolves its WaitForChild immediately instead of racing first use.
Remotes.createAll()

RemoteGateway.register("Roll", function(player: Player)
	return RollService.performRoll(player)
end)

ForgeService.registerHandlers()

RemoteGateway.bind()

--------------------------------------------------------------------------------
-- Player lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local loaded, reason = PlayerProfile.load(player)
	if not loaded then
		-- Threat T-10: fail closed. Never serve a phantom profile that could
		-- overwrite real saved data. The reason stays in the server log; the
		-- player sees an honest, non-diagnostic message.
		warn(string.format("[Bootstrap] profile load failed for UserId=%d: %s",
			player.UserId, tostring(reason)))
		player:Kick("Your data could not be loaded safely. Please rejoin.")
		return
	end

	RollService.beginSession(player)
end

local function onPlayerRemoving(player: Player)
	RollService.endSession(player)
	PlayerProfile.release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

--------------------------------------------------------------------------------
-- Graceful Shutdown
--------------------------------------------------------------------------------

game:BindToClose(function()
	PlayerProfile.releaseAll()
end)
