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

if type(V7HUDModule) == "table" and type(V7HUDModule.new) == "function" then
	local hudCtrl = V7HUDModule.new()

	if type(V7ForgeModule) == "table" and type(V7ForgeModule.new) == "function" then
		local forgeCtrl = V7ForgeModule.new()
		forgeController = forgeCtrl

		if type(V7MenuModule) == "table" and type(V7MenuModule.new) == "function" then
			local menuCtrl = V7MenuModule.new()
			menuController = menuCtrl

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

	-- VOID RISK, computed here rather than sent by the server.
	--
	-- Reads die 1's own Faces off the snapshot and asks the exact function
	-- RollService uses server-side, so the number on screen cannot drift from
	-- the number the roll actually resolves against. Returns nil (unknown) for
	-- any snapshot shape that is not yet a real die, rather than defaulting to a
	-- guessed 0% -- a die nobody has examined is unknown risk, not safe risk.
	local function computeVoidRiskPct(state: any): number?
		if type(state) ~= "table" or type(state.dice) ~= "table" then
			return nil
		end
		local die = state.dice[1]
		if type(die) ~= "table" or type(die.Faces) ~= "table" or type(die.Shape) ~= "string" then
			return nil
		end
		local masses: { number } = {}
		for i, face in ipairs(die.Faces) do
			masses[i] = if type(face) == "table" then tonumber(face.Mass) or 0 else 0
		end
		if #masses == 0 then
			return nil
		end
		local floor = DiceCatalog.getMassFloor(die.Shape)
		local p = ForgeMath.voidProbability(masses, floor)
		if not ForgeMath.isFinite(p) then
			return nil
		end
		return math.clamp(p, 0, 1) * 100
	end

	-- The streak MULTIPLIER is a display quantity derived from `state.streak`
	-- and the player's own StreakStrength -- both already on the snapshot -- and
	-- is refined by the exact-server-value RollResult carries after each roll.
	-- Between rolls this is an honest approximation, not a guess invented on the
	-- client: it uses the same `(1+b)^streak` shape RollService computes.
	local B_PER_LEVEL = 0.01
	local function estimateMultiplier(state: any): number
		local level = tonumber(state.diamondTree and state.diamondTree.StreakStrength) or 0
		local b = math.max(0, level) * B_PER_LEVEL
		local streak = tonumber(state.streak) or 0
		if b <= 0 or streak <= 0 then
			return 1
		end
		local m = (1 + b) ^ math.min(streak, 500)
		return if ForgeMath.isFinite(m) then m else 1
	end

	-- Held so the RollResult handler below can redraw risk without waiting for
	-- the next snapshot. `RollResult` fires before the post-roll StateSync in
	-- practice, and the die's mass distribution does not change from a roll, so
	-- the last known risk is still correct at that instant.
	local lastVoidRiskPct: number? = nil

	NetClient.onStateSync(function(state: any)
		if type(state) ~= "table" then
			return
		end
		hudCtrl:updateBalances(state.cash or 0, state.gems or 0, state.diamonds or 0)
		lastVoidRiskPct = computeVoidRiskPct(state)
		hudCtrl:updateStreak(estimateMultiplier(state), tonumber(state.streak) or 0,
			lastVoidRiskPct)

		-- THE SEAM THAT WAS MISSING. `updateBalances` was the ONLY thing any
		-- snapshot reached: the forge never learned what dice existed, and every
		-- menu overlay opened onto content nothing had filled in. The panels were
		-- complete, and completely disconnected.
		if menuController ~= nil then
			menuController:applyState(state)
		end
		if forgeController ~= nil then
			forgeController:applyState(state)
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
		hudCtrl:updateStreak(mult, streak, lastVoidRiskPct)
		local payout = tonumber(result.payout)
		if payout ~= nil then
			hudCtrl:flashPayout(payout, result.voidHit == true)
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
