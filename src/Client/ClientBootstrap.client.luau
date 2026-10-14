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

-- For computing the ACTIVE DIE'S void risk client-side (streak strip). The
-- server never sends a risk percentage -- that would be an outcome-shaped value
-- on the wire (NFR-5) -- but the die's own mass distribution is already public
-- data in every StateSync snapshot, and `ForgeMath.voidProbability` is the exact
-- function `RollService` uses server-side, so this cannot compute a different
-- answer than the roll it is describing.
local ForgeMath = require(shared:WaitForChild("ForgeMath"))
local StreakMath = require(shared:WaitForChild("StreakMath"))
local DiceCatalog = require(shared:WaitForChild("DiceCatalog"))

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

-- Hoisted so the single StateSync subscription below can reach them. They were
-- previously locals nested three `if` blocks deep, which is why no snapshot
-- could ever be routed to them.
local forgeController: any = nil
local menuController: any = nil

local V7HUDModule = loaded["V7HUD"]
local V7ForgeModule = loaded["V7ForgePanel"]
local V7MenuModule = loaded["V7MenuPanel"]

local hudCtrl: any = nil
if type(V7HUDModule) == "table" and type(V7HUDModule.new) == "function" then
	local okHud, resultHud = pcall(V7HUDModule.new)
	if not okHud then
		fatal(string.format("V7HUD failed to instantiate:\n%s", tostring(resultHud)))
		return
	end
	hudCtrl = resultHud
end

if hudCtrl ~= nil then
	if type(V7ForgeModule) == "table" and type(V7ForgeModule.new) == "function" then
		local okForge, resultForge = pcall(V7ForgeModule.new)
		if okForge then
			forgeController = resultForge
		else
			warn("[ClientBootstrap] V7ForgePanel failed to instantiate: " .. tostring(resultForge))
		end
	end

	if type(V7MenuModule) == "table" and type(V7MenuModule.new) == "function" then
		local okMenu, resultMenu = pcall(V7MenuModule.new)
		if okMenu then
			menuController = resultMenu
		else
			warn("[ClientBootstrap] V7MenuPanel failed to instantiate: " .. tostring(resultMenu))
		end
	end

	local forgeCtrl = forgeController
	local menuCtrl = menuController

	-- FANOUT-1 (finish): each wiring needs only the panel it touches. Gating the
	-- whole block on BOTH panels meant a forge-only failure left the MENU button
	-- unwired and all eight overlays unreachable. Now only the dead panel's own
	-- path is dead: no forge -> the forge entry is inert, overlays still open;
	-- no menu panel -> overlays are inert, the forge still opens.
	if menuCtrl ~= nil then
		-- CAPABILITY REPORTING, from the one place that holds both modules.
		--
		-- The settings panel must not offer a live-looking switch over a
		-- feature that does not exist. Every audio asset id is still a
		-- `DUMMY_ID_*` placeholder, so no Sound is ever built and the Music
		-- and SFX toggles control silence; the panel shows them disabled
		-- with an honest note instead.
		--
		-- ASKED rather than assumed, so dropping real ids into
		-- `AudioDirector.ASSET_IDS` is the ONLY change needed to bring both
		-- rows to life -- nothing here and nothing in the panel needs
		-- revisiting. A hardcoded "audio is not ready" would have to be
		-- remembered and removed, and would not be.
		local audioModule = loaded["AudioDirector"]
		local hasAudio = false
		if type(audioModule) == "table" and type(audioModule.hasAudio) == "function" then
			local okAudio, result = pcall(audioModule.hasAudio)
			hasAudio = okAudio and result == true
		end
		menuCtrl:setCapability("audio", hasAudio)
	end

	if menuCtrl ~= nil or forgeCtrl ~= nil then
		hudCtrl:onMenuClicked(function(menuId: string)
			if menuId == "forge" then
				if forgeCtrl == nil then
					return
				end
				if menuCtrl ~= nil then
					menuCtrl:closeAll()
				end
				forgeCtrl:show()
			else
				if menuCtrl == nil then
					return
				end
				if forgeCtrl ~= nil then
					forgeCtrl:hide()
				end
				menuCtrl:openOverlay(menuId)
			end
		end)
	end

	hudCtrl:onRollClicked(function()
		NetClient.roll()
	end)

	-- RETURNS THE SERVER'S ANSWER. The HUD paints the button only when the toggle
	-- was accepted -- Auto-Roll is a gamepass entitlement and `SetAutoRoll`
	-- refuses without it, so an optimistic flip would show a player ON while the
	-- server never rolled for them.
	hudCtrl:onAutoToggled(function(enabled: boolean): boolean
		local result = NetClient.setAutoRoll(enabled)
		return result.ok
	end)

	-- VOID RISK, computed here rather than sent by the server.
	-- RISK-1: Aggregate void risk ACROSS EVERY DIE, not just the first.
	-- FR-5.1 resets the streak when ANY die lands Void, so the combined risk
	-- is the complement of "no die voids": 1 - Π(1 - p_i).
	-- Reading only dice[1] caused multi-dice loadouts to severely understate risk
	-- (e.g. 12 dice at 33% showed 33% instead of real 99.2%) and forging any die
	-- other than die 1 never moved the readout.
	local function computeVoidRiskPct(state: any): number?
		if type(state) ~= "table" or type(state.dice) ~= "table" or #state.dice == 0 then
			return nil
		end

		local survive = 1.0
		for _, die in ipairs(state.dice) do
			if type(die) ~= "table" or type(die.Faces) ~= "table" or type(die.Shape) ~= "string" then
				return nil
			end

			-- A FACE MAY BE A NUMBER OR A TABLE, and reading only one shape is what
			-- took the whole client down. This accepted `{ Mass = n }` and scored
			-- anything else as 0 -- so a snapshot carrying plain numeric faces
			-- produced an all-zero mass list, `ForgeMath.voidProbability` raised
			-- "total mass must be positive", and the error escaped the StateSync
			-- handler ENTIRELY.
			local masses: { number } = {}
			local total = 0
			for i, face in ipairs(die.Faces) do
				local m: number
				if type(face) == "table" then
					m = tonumber(face.Mass) or 0
				else
					m = tonumber(face) or 0
				end
				if m < 0 or m ~= m then
					m = 0
				end
				masses[i] = m
				total += m
			end

			-- GUARD THE PRECONDITION, not just the emptiness. `voidProbability`
			-- requires a positive total; a list of zeros is the wrong input, not an
			-- error to propagate. Unknown risk is `nil`, which the HUD renders as
			-- "--" -- honest about not knowing rather than fatal.
			if #masses < 2 or total <= 0 then
				return nil
			end

			-- AN UNRECOGNISED SHAPE IS UNKNOWN RISK, NOT A GUESS. `getMassFloor`
			-- answers DEFAULT_MASS_FLOOR (1) for an id it does not know, which would
			-- print a confident percentage measured against a gate the server never
			-- applied.
			if DiceCatalog.getShape(die.Shape) == nil then
				return nil
			end

			-- `voidProbability` has no internal guards. A failure is UNKNOWN (nil),
			-- never 0: a false "0% risk" tells the player the streak is safe when
			-- it is not.
			local okP, p = pcall(ForgeMath.voidProbability, masses, DiceCatalog.getMassFloor(die.Shape))
			if not okP or type(p) ~= "number" or not ForgeMath.isFinite(p) then
				return nil
			end
			local pClamped = math.clamp(p, 0, 1)
			survive *= (1.0 - pClamped)
		end

		return math.clamp((1.0 - survive) * 100, 0, 100)
	end

	-- MULT-1 & CONST-1: The streak MULTIPLIER is computed from shared StreakMath
	-- so client and server share the identical STREAK_CAP (50, not 500), B_PER_LEVEL (0.01),
	-- and MAX_MULTIPLIER ceiling (1e6).
	local function estimateMultiplier(state: any): (number, boolean)
		local level = tonumber(state.diamondTree and state.diamondTree.StreakStrength) or 0
		local unlocked = level > 0
		local b = StreakMath.streakStrengthToB(level)
		local streak = tonumber(state.streak) or 0
		if b <= 0 or streak <= 0 then
			return 1, unlocked
		end
		local m = StreakMath.multiplier(streak, b)
		return m, unlocked
	end

	-- Held so the RollResult handler below can redraw risk without waiting for
	-- the next snapshot. `RollResult` fires before the post-roll StateSync in
	-- practice, and the die's mass distribution does not change from a roll, so
	-- the last known risk is still correct at that instant.
	local lastVoidRiskPct: number? = nil

	-- Held for the same reason as `lastVoidRiskPct`: `RollResult` carries the
	-- authoritative multiplier but says nothing about whether the bonus is
	-- UNLOCKED, and without the last snapshot's answer the post-roll repaint
	-- would drop the "LOCKED" caption straight back to a misleading x1.00.
	local lastMultUnlocked = true

	NetClient.onStateSync(function(state: any)
		if type(state) ~= "table" then
			return
		end

		-- ISOLATED, because a display calculation must never abort the snapshot fanout (FANOUT-1).
		local okBal, balErr = pcall(function()
			hudCtrl:updateBalances(state.cash or 0, state.gems or 0, state.diamonds or 0)
		end)
		if not okBal then
			warn("[ClientBootstrap] balance update failed: " .. tostring(balErr))
		end

		local okRisk, risk = pcall(computeVoidRiskPct, state)
		if okRisk then
			lastVoidRiskPct = risk
		else
			lastVoidRiskPct = nil
			warn("[ClientBootstrap] void-risk calculation failed: " .. tostring(risk))
		end

		local okStreak, streakErr = pcall(function()
			local mult, multUnlocked = estimateMultiplier(state)
			lastMultUnlocked = multUnlocked
			hudCtrl:updateStreak(mult, tonumber(state.streak) or 0,
				lastVoidRiskPct, multUnlocked)
		end)
		if not okStreak then
			warn("[ClientBootstrap] streak update failed: " .. tostring(streakErr))
		end

		-- THE SEAM THAT WAS MISSING. Fan out to menu and forge controllers.
		if menuController ~= nil then
			local okMenu, errMenu = pcall(function()
				menuController:applyState(state)
			end)
			if not okMenu then
				warn("[ClientBootstrap] menuController:applyState failed: " .. tostring(errMenu))
			end
		end
		if forgeController ~= nil then
			local okForge, errForge = pcall(function()
				forgeController:applyState(state)
			end)
			if not okForge then
				warn("[ClientBootstrap] forgeController:applyState failed: " .. tostring(errForge))
			end
		end
	end)

	-- THE STREAK STRIP ON A REAL ROLL. `RollResult` carries the EXACT server
	-- values for the throw that just landed -- `multiplier` and `streak` are
	-- authoritative, not the client's between-rolls estimate -- so the strip
	-- corrects itself to ground truth on every roll rather than drifting on the
	-- approximation above.
	NetClient.onRollResult(function(result: any)
		if type(result) ~= "table" then
			return
		end
		local mult = tonumber(result.multiplier) or 1
		local streak = tonumber(result.streak) or 0
		hudCtrl:updateStreak(mult, streak, lastVoidRiskPct, lastMultUnlocked)
		local payout = tonumber(result.payout)
		if payout ~= nil then
			hudCtrl:flashPayout(payout, result.voidHit == true)
		end
	end)

	NetClient.onNotice(function(notice: any)
		warn("[ClientBootstrap] server notice: " .. tostring(notice))
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
