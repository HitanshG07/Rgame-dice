--!strict
-- ClientBootstrap.client.luau
-- Client entry point for V7 UI. Initialises modules in dependency order,
-- sets up seams, handles StateSync, and provides loud startup error reporting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local maybeLocalPlayer = Players.LocalPlayer
if maybeLocalPlayer == nil then
	error("[ClientBootstrap] no LocalPlayer -- this must run as a LocalScript under StarterPlayerScripts", 0)
end
local localPlayer: Player = maybeLocalPlayer

local function fatal(message: string): ()
	warn("[ClientBootstrap] FATAL: " .. message)

	local gui = Instance.new("ScreenGui")
	gui.Name = "DiceForgeStartupError"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.8, 0.3)
	panel.Position = UDim2.fromScale(0.1, 0.35)
	panel.BackgroundColor3 = Color3.fromRGB(38, 14, 18)
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(245, 158, 11)
	border.Thickness = 1
	border.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(243, 244, 246)
	label.Text = "DICE FORGE V7 UI could not start.\n\n" .. message
		.. "\n\nYour saved data has NOT been touched. Please rejoin."
	label.Parent = panel

	local target = localPlayer:FindFirstChildOfClass("PlayerGui")
	if target then
		gui.Parent = target
	end
end

if not RunService:IsClient() then
	error("[ClientBootstrap] client-only", 2)
end

local SHARED_TIMEOUT = 20
local shared = ReplicatedStorage:WaitForChild("Shared", SHARED_TIMEOUT)
if not shared then
	fatal("Shared modules did not replicate within " .. tostring(SHARED_TIMEOUT) .. "s.")
	return
end

local clientRoot = script.Parent
local netModule = clientRoot:WaitForChild("NetClient", SHARED_TIMEOUT)
if not netModule then
	fatal("NetClient did not replicate.")
	return
end

local okRequire, NetClient = pcall(require, netModule)
if not okRequire then
	fatal("NetClient failed to load:\n" .. tostring(NetClient))
	return
end

local ready, missing = NetClient.awaitReady()
if not ready then
	fatal("Remote '" .. tostring(missing) .. "' never replicated.")
	return
end

--------------------------------------------------------------------------------
-- Module construction in dependency order
--------------------------------------------------------------------------------

local MODULE_ORDER: { string } = {
	"BoardView",
	"DiceRenderer",
	"FeedbackFX",
	"V7HUD",
	"V7ForgePanel",
	"V7MenuPanel",
	"AudioDirector",
}

local loaded: { [string]: any } = {}
local ClientBootstrap = {}
_G.DiceForgeClientBootstrap = ClientBootstrap

for _, name in ipairs(MODULE_ORDER) do
	local instance = clientRoot:FindFirstChild(name)
	if instance == nil then
		warn(string.format("[ClientBootstrap] '%s' not present yet -- skipping", name))
		continue
	end
	local ok, moduleOrErr = pcall(require, instance)
	if not ok then
		fatal(string.format("Module '%s' failed to load:\n%s", name, tostring(moduleOrErr)))
		return
	end
	loaded[name] = moduleOrErr
end

for _, name in ipairs(MODULE_ORDER) do
	local m = loaded[name]
	if m ~= nil and type(m) == "table" and type(m.init) == "function" then
		local ok, err = pcall(m.init, NetClient)
		if not ok then
			fatal(string.format("Module '%s' failed to initialise:\n%s", name, tostring(err)))
			return
		end
	end
end

--------------------------------------------------------------------------------
-- V7 Seams & Event Wiring
--------------------------------------------------------------------------------

local V7HUDModule = loaded["V7HUD"]
local V7ForgeModule = loaded["V7ForgePanel"]
local V7MenuModule = loaded["V7MenuPanel"]

if type(V7HUDModule) == "table" and type(V7HUDModule.new) == "function" then
	local hudCtrl = V7HUDModule.new()

	if type(V7ForgeModule) == "table" and type(V7ForgeModule.new) == "function" then
		local forgeCtrl = V7ForgeModule.new()

		if type(V7MenuModule) == "table" and type(V7MenuModule.new) == "function" then
			local menuCtrl = V7MenuModule.new()

			hudCtrl:onMenuClicked(function(menuId: string)
				if menuId == "forge" then
					menuCtrl:closeAll()
					forgeCtrl:show()
				else
					forgeCtrl:hide()
					menuCtrl:openOverlay(menuId)
				end
			end)
		end
	end

	hudCtrl:onRollClicked(function()
		NetClient.roll()
	end)

	hudCtrl:onAutoToggled(function(enabled: boolean)
		NetClient.setAutoRoll(enabled)
	end)

	NetClient.onStateSync(function(state: any)
		if type(state) == "table" then
			hudCtrl:updateBalances(state.cash or 0, state.gems or 0, state.diamonds or 0)
		end
	end)
end

function ClientBootstrap.shutdown(): ()
	for i = #MODULE_ORDER, 1, -1 do
		local m = loaded[MODULE_ORDER[i]]
		if type(m) == "table" and type((m :: any).shutdown) == "function" then
			local ok, err = pcall((m :: any).shutdown)
			if not ok then
				warn(string.format("[ClientBootstrap] %s.shutdown() errored: %s",
					MODULE_ORDER[i], tostring(err)))
			end
		end
	end
end

print("[ClientBootstrap] V7 UI ready -- NetClient online, " .. tostring(#MODULE_ORDER) .. " modules loaded.")
