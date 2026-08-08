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

-- A LocalScript returns nothing, so the teardown entry point is published on a
-- named table rather than returned. The Orchestrator and any future test
-- harness reach it through this.
local ClientBootstrap = {}
_G.DiceForgeClientBootstrap = ClientBootstrap

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
-- THE SEAMS
--
-- Every module above was built in isolation and knows nothing about its
-- siblings. That is what kept them independently reviewable -- and it means the
-- connections between them exist NOWHERE until they are made here. This is the
-- composition root; if a seam is missing, the surfaces are all individually
-- correct and the game does not work.
--
-- Each seam is defensive: a module absent from disk (still true for nothing
-- today, but true again the moment someone adds an eighth) must not take the
-- client down. Everything below checks before it wires.
--------------------------------------------------------------------------------

local ForgePanel = loaded["ForgePanel"]
local MenuPanel = loaded["MenuPanel"]
local FeedbackFX = loaded["FeedbackFX"]
local AudioDirector = loaded["AudioDirector"]

-- SEAM 1 -- the sidebar opens the forge.
--
-- ForgePanel's own edge tab was removed: it was a second control for one
-- surface, and it sat a layer above the sidebar where it covered a button. The
-- sidebar entry is now the only way in, so this wiring is not a convenience --
-- without it the core mechanic of the game is unreachable, and MenuPanel
-- renders the entry as "(UNWIRED)" to say so out loud.
if type(MenuPanel) == "table" and type(ForgePanel) == "table" then
	MenuPanel.setSurfaceOpener("Forge", function(_dieIndex: number?)
		ForgePanel.setVisible(true)
	end)
	-- Shape lives inside the forge panel rather than on its own surface.
	MenuPanel.setSurfaceOpener("Shape", function(_dieIndex: number?)
		ForgePanel.setVisible(true)
	end)

	-- SEAM 2 -- mutual exclusion.
	--
	-- MenuPanel's overlay and ForgePanel's panel both sit at UITheme.Layer.Panel
	-- with overlapping rectangles, and Roblox does not define stacking on a tie.
	-- MenuPanel already yields outbound (it closes its overlay before invoking an
	-- opener); this is the inbound half, so opening a sidebar surface closes the
	-- forge instead of two opaque panels racing.
	MenuPanel.setSurfaceCloser(function()
		ForgePanel.setVisible(false)
	end)
end

-- SEAM 3 -- the settings bridge (FR-13.6).
--
-- MenuPanel owns the particle and motion-blur toggles; FeedbackFX and
-- AudioDirector are the modules that must obey them, and neither can reach
-- MenuPanel without violating the isolation that made them reviewable. Two
-- separate rework agents independently reported this gap, which is why it is
-- wired here rather than inside either of them.
if type(MenuPanel) == "table" then
	local function pushSettings(settings: any): ()
		if type(FeedbackFX) == "table" and type(FeedbackFX.applySettings) == "function" then
			FeedbackFX.applySettings({
				particles = settings.particles,
				motionBlur = settings.motionBlur,
			})
		end
		if type(AudioDirector) == "table" and type(AudioDirector.applySettings) == "function" then
			AudioDirector.applySettings({ sfx = settings.sfx, music = settings.music })
		end
	end

	-- Prime immediately: a module built before the first toggle must not start
	-- out disagreeing with a switch the player can already see.
	pushSettings(MenuPanel.getSettings())
	MenuPanel.onSettingsChanged(pushSettings)

	-- THE HAZARD THIS CLOSES, reported independently by BOTH the FeedbackFX and
	-- MenuPanel reworks.
	--
	-- StateSync carries a `settings` block read from the saved profile, and the
	-- contract says it is re-sent "after any state change" -- which includes
	-- every roll. There is no server handler that WRITES settings yet, so that
	-- block always carries the profile defaults. A client that adopted it would
	-- silently revert a toggle the player just flipped, on their very next roll.
	--
	-- MenuPanel refused to adopt the field for exactly that reason. But
	-- FeedbackFX still reads StateSync as its authoritative source, so a snapshot
	-- can still overwrite a live toggle. Re-asserting MenuPanel's values after
	-- every snapshot makes the in-session choice win until the persistence
	-- handler exists.
	--
	-- This is a WORKAROUND for a missing server feature, not a design. FR-13.6
	-- requires the toggles to be "persisted per player"; that needs a remote and
	-- a profile write that do not exist, and MenuPanel says on screen that the
	-- toggles are session-scoped rather than implying otherwise.
	NetClient.onStateSync(function(_state: any)
		pushSettings(MenuPanel.getSettings())
	end)
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

-- TEARDOWN, in reverse dependency order.
--
-- Every view module acquires connections, a ScreenGui or an instance pool, and
-- six of the seven grew a `shutdown` during rework -- but NOTHING CALLED ANY OF
-- THEM. A release path that no caller reaches is not a release path; it is a
-- function that makes the leak look handled. Reported by the ArenaView rework,
-- which noticed its own new shutdown was unreachable.
--
-- Reverse order because construction order is dependency order: FeedbackFX
-- anchors into ArenaView, so it must release before the arena it points at.
function ClientBootstrap.shutdown(): ()
	for i = #MODULE_ORDER, 1, -1 do
		local m = loaded[MODULE_ORDER[i]]
		if type(m) == "table" and type((m :: any).shutdown) == "function" then
			-- One module failing to release must not strand the rest.
			local ok, err = pcall((m :: any).shutdown)
			if not ok then
				warn(string.format("[ClientBootstrap] %s.shutdown() errored: %s",
					MODULE_ORDER[i], tostring(err)))
			end
		end
	end
end

print("[ClientBootstrap] ready -- NetClient online, "
	.. tostring(#MODULE_ORDER) .. " view modules declared")
