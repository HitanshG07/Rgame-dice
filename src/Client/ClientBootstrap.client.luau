--!strict
-- ClientBootstrap.client.luau
-- Client entry point. Waits for replication, verifies every remote resolved,
-- constructs client modules in dependency order, and fails LOUDLY and VISIBLY
-- if it cannot.
--
-- HLD §3 C-3.
--
-- WHY IT FAILS LOUDLY. A client that silently degrades is worse than one that
-- refuses to start: the player sees a game that looks fine and does nothing,
-- reports "it's broken", and nobody can tell which of nine modules is missing.
-- If a required remote never replicates, this puts an unmissable message on
-- screen naming what was missing.
--
-- WHAT IT DOES NOT DO. It holds no economic state. Cash, gems, budgets, streak
-- and every price live on the server and arrive by StateSync. Anything this
-- file remembers is presentation only, and losing it costs nothing but a
-- redraw (SRS FR-2.6).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- `Players.LocalPlayer` is typed `Player?` because it is nil on the server and
-- during early client startup. Narrow it ONCE here, loudly, rather than casting
-- at each use: a `:: Player` cast would silence the checker and still index nil
-- if this file were ever parented somewhere it does not belong. If there is no
-- LocalPlayer there is also no PlayerGui to report a failure into, so erroring
-- is the only honest option left.
local maybeLocalPlayer = Players.LocalPlayer
if maybeLocalPlayer == nil then
	error("[ClientBootstrap] no LocalPlayer -- this must run as a LocalScript "
		.. "under StarterPlayerScripts", 0)
end
local localPlayer: Player = maybeLocalPlayer

--------------------------------------------------------------------------------
-- Fatal reporting
--------------------------------------------------------------------------------

-- Deliberately does not depend on any module that might itself be the thing
-- that failed to load, so it is written inline with only Roblox primitives.
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
	border.Color = Color3.fromRGB(196, 158, 72)
	border.Thickness = 1
	border.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.9, 0.8)
	label.Position = UDim2.fromScale(0.05, 0.1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(236, 226, 208)
	label.Text = "DICE FORGE could not start.\n\n" .. message
		.. "\n\nYour saved data has NOT been touched. Please rejoin."
	label.Parent = panel

	local target = localPlayer:FindFirstChildOfClass("PlayerGui")
	if target then
		gui.Parent = target
	end
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

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

-- Every declared remote must resolve before any surface is built. Discovering a
-- missing remote at first button press instead of at startup is how a bug gets
-- reported as "the roll button does nothing".
local ready, missing = NetClient.awaitReady()
if not ready then
	fatal("Remote '" .. tostring(missing) .. "' never replicated.")
	return
end

--------------------------------------------------------------------------------
-- Module construction, in dependency order
--------------------------------------------------------------------------------

-- Block 4A builds the spine only. ArenaView, DiceRenderer, ForgePanel, HUD,
-- MenuPanel, FeedbackFX and AudioDirector arrive in 4B and 4C and are appended
-- here in dependency order as they land.
--
-- Each entry is optional-by-presence ON PURPOSE while the client is under
-- construction: a module that is not on disk yet is skipped with a note, but a
-- module that IS present and fails to load is FATAL. "Not built yet" and
-- "broken" must never look the same.
-- Order is DEPENDENCY order, not importance order. ArenaView owns the camera and
-- the pit, so DiceRenderer needs it first; FeedbackFX anchors floating text into
-- the arena, so it needs both. The 2D surfaces depend on none of them.
local MODULE_ORDER: { string } = {
	"ArenaView",       -- 4B  owns the pit, the camera, and the die anchor points
	"DiceRenderer",    -- 4B  tumble-to-target; needs ArenaView's anchors
	"FeedbackFX",      -- 4B  floating payout text; needs the arena to anchor into
	"HUD",             -- 4C  top and bottom bars
	"ForgePanel",      -- 4C  the primary surface (FR-13.8)
	"MenuPanel",       -- 4C  left and right sidebars
	"AudioDirector",   -- 4C  depends on nothing; last so a sound fault cannot
	                   --     stop a visual surface from being built
}

local loaded: { [string]: any } = {}

for _, name in ipairs(MODULE_ORDER) do
	local instance = clientRoot:FindFirstChild(name)
	if instance == nil then
		warn(string.format("[ClientBootstrap] '%s' not present yet -- skipping (still under construction)", name))
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
-- Baseline subscriptions
--------------------------------------------------------------------------------

-- Wired here rather than in a view so that the authoritative snapshot is being
-- received from the first frame, even while the surfaces that display it are
-- still being built. A dropped RollResult costs a visual, never a credit
-- (SRS FR-2.6) -- the server credited before it fired.

NetClient.onStateSync(function(_state: any)
	-- 4C's HUD consumes this. Until then the subscription exists so the
	-- connection is proven live during the 4A smoke.
end)

NetClient.onRollResult(function(_result: any)
	-- 4B's DiceRenderer consumes this.
end)

NetClient.onNotice(function(notice: any)
	-- Enumerated CODES only, never internal detail (threat T-7). Surfaced in the
	-- log until 4C gives it a toast.
	if type(notice) == "table" and type(notice.code) == "string" then
		warn(string.format("[Notice] %s (%s)", notice.code, tostring(notice.severity)))
	end
end)

print("[ClientBootstrap] ready -- NetClient online, "
	.. tostring(#MODULE_ORDER) .. " view modules declared")
