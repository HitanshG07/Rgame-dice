--!strict
-- HUD.luau
-- The top bar, the streak strip and the bottom bar (SRS FR-13.2, FR-13.5).
--
-- THE ONE RULE THIS FILE EXISTS TO KEEP. Currency on screen comes from
-- StateSync and RollResult and from nothing else. Not from a local sum, not
-- from an optimistic add, not from "the payout I just saw". NFR-7 asks for
-- visible feedback within 100 ms of a ROLL press, and it is satisfied here by
-- animating the BUTTON, never by moving a number: an optimistic balance that a
-- refusal later revokes is a number the game told the player they had and then
-- took away, which is worse than a balance that updates 80 ms late.
--
-- WHAT IS DISPLAYED IS ALWAYS ALREADY TRUE. The server credits before it fires
-- RollResult (SRS FR-2.6), so every figure here is a fact by the time it
-- arrives. A dropped event costs a redraw and never a credit.
--
-- CONTINUOUS VISIBILITY (FR-5.5). Streak, streak multiplier and the loadout's
-- Void probability are not in a panel the player has to open. They sit in a
-- permanent strip under the top bar, because they are the three numbers the
-- forge decision is made against and a build screen that hides them is a build
-- screen nobody can reason about.
--
-- ENTRY POINTS WITH NO SYSTEM BEHIND THEM. FR-13.2 and FR-13.5 name Group
-- Rewards, the Robux shop, the playtime chest and the daily spin. As of this
-- writing the server registers exactly four handlers -- Roll, Forge, SetElement
-- and SetShape (verified against RemoteGateway.register call sites, 2026-08-07)
-- -- and none of those four systems is among them. Each therefore renders in an
-- explicit unavailable state that says so when pressed. It is not a button that
-- looks live and does nothing.
--
-- LAYOUT. Scale only (FR-13.7, NFR-3). The horizontal bands are 0.00-0.085 for
-- the top bar, 0.09-0.148 for the streak strip and 0.86-1.00 for the bottom bar,
-- leaving 0.16-0.84 clear for MenuPanel's sidebars and the arena beneath.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))

local ClientRoot = script.Parent

local UITheme = require(ClientRoot:WaitForChild("UITheme"))

-- AudioDirector ships in the same block as this file, so it is present in
-- practice. It is still resolved defensively: a sound layer that failed to
-- replicate must not be able to stop the HUD from being built, which is the
-- same "not built yet is not the same as broken" rule ClientBootstrap applies.
local AUDIO_WAIT = 5
local audioModule = ClientRoot:WaitForChild("AudioDirector", AUDIO_WAIT)
local Audio: any = nil
if audioModule ~= nil then
	local ok, loaded = pcall(require, audioModule)
	if ok then
		Audio = loaded
	else
		warn("[HUD] AudioDirector failed to load; running silent: " .. tostring(loaded))
	end
else
	warn("[HUD] AudioDirector not present; running silent")
end

local function cue(name: string): ()
	if Audio ~= nil then
		Audio.play(name)
	end
end

local HUD = {}

--------------------------------------------------------------------------------
-- The NetClient surface this module uses
--------------------------------------------------------------------------------

-- Structural rather than a require of NetClient's own type, so this file states
-- exactly which four calls it is allowed to make. Widening it is a visible diff.
-- NOTE THE ABSENCE of anything that takes a number: nothing this module sends
-- can carry a price, balance, reward, level, duration or multiplier (NFR-5).
type NetResult = { ok: boolean, reason: string? }

export type Net = {
	roll: () -> NetResult,
	setAutoRoll: (boolean) -> NetResult,
	readyIn: (string) -> number,
	onStateSync: ((any) -> ()) -> RBXScriptConnection,
	onRollResult: ((any) -> ()) -> RBXScriptConnection,
	onEventState: ((any) -> ()) -> RBXScriptConnection,
	onNotice: ((any) -> ()) -> RBXScriptConnection,
}

--------------------------------------------------------------------------------
-- Honest readers for untyped payloads
--------------------------------------------------------------------------------

local EMPTY = "--"

-- Every payload arriving from the wire is `any`. These readers return nil for
-- anything that is not the expected shape, and every display site renders nil
-- as EMPTY. A malformed field shows a dash; it never shows a zero, because a
-- zero is a claim about the player's balance and a dash is not.
local function readNumber(source: any, key: string): number?
	if type(source) ~= "table" then
		return nil
	end
	local value = (source :: { [string]: any })[key]
	if type(value) ~= "number" or not ForgeMath.isFinite(value) then
		return nil
	end
	return value
end

local function readBoolean(source: any, key: string): boolean?
	if type(source) ~= "table" then
		return nil
	end
	local value = (source :: { [string]: any })[key]
	return if type(value) == "boolean" then value else nil
end

-- Returns `any` rather than a concrete table type on purpose. The wire shape is
-- not ours to assert, and a cast from `{[any]: any}` to an array type would be
-- exactly the kind of confident-but-unchecked claim these readers exist to
-- avoid. Callers narrow each leaf with readNumber/readBoolean instead.
local function readTable(source: any, key: string): any
	if type(source) ~= "table" then
		return nil
	end
	local value = (source :: { [string]: any })[key]
	return if type(value) == "table" then value else nil
end

-- P(at least one die lands Void this throw), which is exactly the event that
-- breaks the streak (FR-5.1): 1 - product(1 - p_i).
--
-- This is computed on the client from server-supplied masses, using the SAME
-- ForgeMath the server rolls against, so the figure cannot drift from the one
-- the outcome is actually drawn from. It is a restatement of server data, not a
-- client opinion about it -- the client still never decides an outcome.
--
-- Returns nil rather than a number if any die is unreadable, so a partially
-- malformed snapshot shows a dash instead of a confidently wrong percentage.
local function loadoutVoidProbability(dice: any): number?
	if type(dice) ~= "table" then
		return nil
	end

	local survive = 1.0
	local counted = 0

	for _, die in ipairs(dice :: { any }) do
		local faces = readTable(die, "Faces")
		if faces == nil then
			return nil
		end

		local mass: { number } = {}
		for _, face in ipairs(faces :: { any }) do
			local m = readNumber(face, "Mass")
			if m == nil then
				return nil
			end
			table.insert(mass, m)
		end

		if #mass < 2 then
			return nil
		end

		-- ForgeMath raises on degenerate input (zero total mass, for instance).
		-- A snapshot that trips it is a display problem, never a crash.
		-- The floor is per-shape and REQUIRED: without it voidProbability cannot
		-- apply the proximity gate and reports the lightest face's landing
		-- probability as if it were the streak-break chance.
		local shapeId = if type(die) == "table" and type(die.Shape) == "string" then die.Shape else nil
		if shapeId == nil then
			return nil
		end
		local ok, p = pcall(ForgeMath.voidProbability, mass, DiceCatalog.getMassFloor(shapeId))
		if not ok or type(p) ~= "number" or not ForgeMath.isFinite(p) then
			return nil
		end

		survive *= (1 - p)
		counted += 1
	end

	if counted == 0 then
		return nil
	end
	return 1 - survive
end

--------------------------------------------------------------------------------
-- Display state -- presentation only
--------------------------------------------------------------------------------

-- These mirror server facts for drawing. They are never read to decide
-- anything, never sent anywhere, and losing them costs one redraw
-- (FR-14.8's spirit on the client side: the server remains the only source).
local lastCash: number? = nil
local lastGems: number? = nil
local lastStreak: number? = nil
local lastMultiplier: number? = nil
local lastVoidProbability: number? = nil
local likeProgress: number? = nil
local likeTarget: number? = nil
local eventActive = false

local autoRollWanted = false
local rollPendingUntil = 0

--------------------------------------------------------------------------------
-- Instances -- all built once, all pooled (NFR-1)
--------------------------------------------------------------------------------

local screenGui: ScreenGui? = nil
local cashLabel: TextLabel? = nil
local gemsLabel: TextLabel? = nil
local likeLabel: TextLabel? = nil
local likeWell: Frame? = nil
local likeFill: Frame? = nil
local eventLabel: TextLabel? = nil
local streakLabel: TextLabel? = nil
local multiplierLabel: TextLabel? = nil
local voidLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local rollButton: TextButton? = nil
local autoButton: TextButton? = nil
local rollPulse: Frame? = nil

local connections: { RBXScriptConnection } = {}
local heartbeat: RBXScriptConnection? = nil

-- Cached rendered text. Every setter compares before assigning, so the steady
-- state -- an idle HUD, or an auto-roll at five per second where only the cash
-- figure moves -- performs no property writes it does not need and allocates
-- no strings it does not need.
local textCache: { [string]: string } = {}
local rollEnabledCache: boolean? = nil
local autoEnabledCache: boolean? = nil

local function setText(label: TextLabel?, key: string, text: string): ()
	if label == nil then
		return
	end
	if textCache[key] == text then
		return
	end
	textCache[key] = text
	label.Text = text
end

-- Same guard for a TextButton. A separate function rather than a union type or
-- a cast, because widening the parameter to `any` would silently accept an
-- instance with no Text property at all.
local function setButtonText(button: TextButton?, key: string, text: string): ()
	if button == nil then
		return
	end
	if textCache[key] == text then
		return
	end
	textCache[key] = text
	button.Text = text
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function money(value: number?): string
	return if value == nil then EMPTY else Format.formatNumber(value)
end

local function renderCurrencies(): ()
	setText(cashLabel, "cash", "CASH  " .. money(lastCash))
	setText(gemsLabel, "gems", "GEMS  " .. money(lastGems))
end

local function renderStreak(): ()
	local streak = lastStreak
	setText(streakLabel, "streak", "STREAK  " .. (if streak == nil then EMPTY else string.format("%d", streak)))

	-- The multiplier is a SERVER number. The one case where it is safe to state
	-- without the server having said it is streak zero, where (1+b)^0 = 1 by
	-- definition for every value of b (FR-5.3) and no player-specific data is
	-- being guessed at. Any other streak with no server multiplier in hand
	-- renders a dash rather than an arithmetic guess about b.
	local multiplierText: string
	if lastMultiplier ~= nil then
		multiplierText = string.format("x%.2f", lastMultiplier)
	elseif streak == 0 then
		multiplierText = "x1.00"
	else
		multiplierText = EMPTY
	end
	setText(multiplierLabel, "mult", "MULT  " .. multiplierText)

	local voidProbability = lastVoidProbability
	setText(voidLabel, "void", "VOID  "
		.. (if voidProbability == nil then EMPTY else string.format("%.1f%%", voidProbability * 100)))
end

local function renderLikeGoal(): ()
	-- FR-10.7 and the standing operator prohibition: this shows the REAL like
	-- count the server reported, or it shows nothing at all. There is no
	-- placeholder progress, no seeded starting value and no invented activity.
	local progress = likeProgress
	local target = likeTarget
	local fill = likeFill

	if progress == nil or target == nil or target <= 0 then
		setText(likeLabel, "like", "LIKE GOAL  " .. EMPTY)
		if fill ~= nil then
			fill.Size = UDim2.fromScale(0, 1)
		end
		return
	end

	setText(likeLabel, "like", string.format("LIKE GOAL  %s / %s",
		Format.formatNumber(progress), Format.formatNumber(target)))

	if fill ~= nil then
		local ratio = progress / target
		if ratio < 0 then
			ratio = 0
		elseif ratio > 1 then
			ratio = 1
		end
		fill.Size = UDim2.fromScale(ratio, 1)
	end
end

local function renderEvent(): ()
	-- No countdown is drawn even though EventState carries an end time. A timer
	-- on screen is the exact shape of the manufactured-urgency pattern the
	-- operator prohibited, and the state -- active or not -- is the part the
	-- player actually needs.
	--
	-- The banner takes the like goal's slot rather than being squeezed in beside
	-- it. That is not a space compromise: the event fires BECAUSE the like goal
	-- was reached (FR-10.7), so while it runs, the progress bar it replaced has
	-- nothing left to report.
	local label = eventLabel
	if label ~= nil then
		label.Visible = eventActive
		setText(label, "event", "3x CASH EVENT ACTIVE")
	end

	local well = likeWell
	if well ~= nil then
		well.Visible = not eventActive
	end
	local goal = likeLabel
	if goal ~= nil then
		goal.Visible = not eventActive
	end
end

local function renderAuto(): ()
	setButtonText(autoButton, "auto", if autoRollWanted then "AUTO  ON" else "AUTO")
end

-- The one place a refusal, a notice or an unavailable entry point becomes
-- words. A single pooled label; no toast instances are created or destroyed.
local function setStatus(text: string): ()
	setText(statusLabel, "status", text)
end

--------------------------------------------------------------------------------
-- Optimistic feedback (NFR-7) -- visual only
--------------------------------------------------------------------------------

local ROLL_PULSE_SECONDS = 0.18

-- Called synchronously on the press, before any network work is scheduled, so
-- the pulse is on screen in the same frame the player clicked. It moves colour
-- and nothing else: no figure on this HUD changes until the server says so.
local function pulseRoll(): ()
	local pulse = rollPulse
	if pulse == nil then
		return
	end
	pulse.Visible = true
	pulse.BackgroundTransparency = 0.45
	rollPendingUntil = os.clock() + ROLL_PULSE_SECONDS
end

local function fadeRollPulse(now: number): ()
	local pulse = rollPulse
	if pulse == nil or not pulse.Visible then
		return
	end
	local remaining = rollPendingUntil - now
	if remaining <= 0 then
		pulse.Visible = false
		return
	end
	-- Straight linear fade from the pulse transparency to fully clear. No table
	-- is built and no tween object is created, so this costs nothing per frame.
	pulse.BackgroundTransparency = 1 - (remaining / ROLL_PULSE_SECONDS) * 0.55
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local net: Net? = nil

local function reasonText(result: NetResult): string
	local reason = result.reason
	if reason == "throttled" then
		return "SLOW DOWN"
	elseif reason == "unavailable" then
		return "SERVER DID NOT ANSWER"
	elseif reason == "malformed_response" then
		return "UNEXPECTED REPLY"
	elseif reason ~= nil then
		return string.upper(reason)
	end
	return "REFUSED"
end

local function doRoll(): ()
	local client = net
	if client == nil then
		return
	end

	-- Asked before sending, not after being refused. The button is already
	-- greyed by the heartbeat at this point; this is what makes the grey
	-- MEAN something rather than being decoration over a call that still goes
	-- out and comes back rejected. readyIn is read-only and consumes nothing.
	if client.readyIn("Roll") > 0 then
		setStatus("SLOW DOWN")
		return
	end

	-- Feedback first, network second. The request is dispatched on its own
	-- thread so the InvokeServer yield cannot delay the pulse past 100 ms
	-- (NFR-7) -- the frame paints while the call is still in flight.
	pulseRoll()
	cue("RollPress")

	task.spawn(function()
		local result = client.roll()
		if not result.ok then
			setStatus(reasonText(result))
			cue("UiRefused")
		end
	end)
end

local function doToggleAuto(): ()
	local client = net
	if client == nil then
		return
	end

	if client.readyIn("SetAutoRoll") > 0 then
		setStatus("SLOW DOWN")
		return
	end

	local wanted = not autoRollWanted
	cue("UiClick")

	task.spawn(function()
		-- Only a boolean crosses the wire. The interval is server-owned
		-- (FR-7.2); asking for one would be asking for an income rate.
		local result = client.setAutoRoll(wanted)
		if result.ok then
			autoRollWanted = wanted
			setStatus(if wanted then "AUTO ON" else "AUTO OFF")
			renderAuto()
		else
			-- The local flag is only ever moved by a server confirmation, so a
			-- refusal needs no rollback: the button never claimed the new state.
			setStatus(reasonText(result))
			cue("UiRefused")
		end
	end)
end

-- Shared by every FR-13 entry point whose server system does not exist yet.
-- Pressing one says plainly what is going on rather than doing nothing.
local function announceUnavailable(what: string): ()
	setStatus(what .. " ARRIVES IN A LATER UPDATE")
	cue("UiRefused")
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function addLabel(parent: Instance, text: string, size: UDim2, position: UDim2,
	colour: Color3?, centred: boolean?): TextLabel

	local label = UITheme.label(text, size, position, colour)
	if centred then
		label.TextXAlignment = Enum.TextXAlignment.Center
	end
	label.Parent = parent
	return label
end

-- A button for a system that is not built. It is greyed, it is suffixed, and it
-- explains itself on press. The suffix is part of the label rather than a
-- separate badge so it survives every screen width down to 320 px.
local function addPendingButton(parent: Instance, label: string, size: UDim2, position: UDim2): TextButton
	local button = UITheme.button(label .. "  (SOON)", size, position)
	button.Parent = parent
	UITheme.setEnabled(button, false)
	button.Activated:Connect(function()
		announceUnavailable(label)
	end)
	return button
end

local function buildTopBar(root: Instance): ()
	local bar = UITheme.panel(UDim2.fromScale(1, 0.085), UDim2.fromScale(0, 0))
	bar.Name = "TopBar"
	bar.Parent = root

	cashLabel = addLabel(bar, "CASH  " .. EMPTY, UDim2.fromScale(0.20, 0.6),
		UDim2.fromScale(0.02, 0.2), UITheme.Colors.Cash)
	gemsLabel = addLabel(bar, "GEMS  " .. EMPTY, UDim2.fromScale(0.16, 0.6),
		UDim2.fromScale(0.24, 0.2), UITheme.Colors.Gems)

	-- Like goal: a recessed well with a fill bar, plus the literal numbers.
	local well = UITheme.panel(UDim2.fromScale(0.26, 0.30), UDim2.fromScale(0.42, 0.56))
	well.Name = "LikeGoalWell"
	well.BackgroundColor3 = UITheme.Colors.PanelDeep
	well.Parent = bar
	likeWell = well

	local fill = Instance.new("Frame")
	fill.Name = "LikeGoalFill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.Position = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = UITheme.Colors.TextGold
	fill.BorderSizePixel = 0
	fill.Parent = well
	likeFill = fill

	likeLabel = addLabel(bar, "LIKE GOAL  " .. EMPTY, UDim2.fromScale(0.26, 0.40),
		UDim2.fromScale(0.42, 0.12), UITheme.Colors.TextDim)

	local event = addLabel(bar, "3x CASH EVENT ACTIVE", UDim2.fromScale(0.26, 0.30),
		UDim2.fromScale(0.42, 0.56), UITheme.Colors.Positive, true)
	event.Visible = false
	eventLabel = event

	addPendingButton(bar, "GROUP", UDim2.fromScale(0.13, 0.62), UDim2.fromScale(0.70, 0.19))
	addPendingButton(bar, "SHOP", UDim2.fromScale(0.13, 0.62), UDim2.fromScale(0.85, 0.19))
end

local function buildStreakStrip(root: Instance): ()
	-- FR-5.5. Sits between the sidebars so it is never overlapped by them, and
	-- is a permanent fixture rather than a panel that has to be opened.
	local strip = UITheme.panel(UDim2.fromScale(0.70, 0.058), UDim2.fromScale(0.15, 0.09), true)
	strip.Name = "StreakStrip"
	strip.Parent = root

	streakLabel = addLabel(strip, "STREAK  " .. EMPTY, UDim2.fromScale(0.30, 0.68),
		UDim2.fromScale(0.02, 0.16), UITheme.Colors.TextPrimary)
	multiplierLabel = addLabel(strip, "MULT  " .. EMPTY, UDim2.fromScale(0.30, 0.68),
		UDim2.fromScale(0.35, 0.16), UITheme.Colors.TextGold)
	voidLabel = addLabel(strip, "VOID  " .. EMPTY, UDim2.fromScale(0.30, 0.68),
		UDim2.fromScale(0.68, 0.16), UITheme.Colors.VoidFace)
end

local function buildBottomBar(root: Instance): ()
	local bar = UITheme.panel(UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.86))
	bar.Name = "BottomBar"
	bar.Parent = root

	-- FR-13.5 names both entry points. FR-10.3 (server-clocked chests) and
	-- FR-10.4 (the weighted spin wheel) are unbuilt, so both are pending.
	addPendingButton(bar, "CHEST", UDim2.fromScale(0.15, 0.5), UDim2.fromScale(0.03, 0.25))
	addPendingButton(bar, "SPIN", UDim2.fromScale(0.15, 0.5), UDim2.fromScale(0.20, 0.25))

	statusLabel = addLabel(bar, "", UDim2.fromScale(0.24, 0.4), UDim2.fromScale(0.37, 0.3),
		UITheme.Colors.TextDim, true)

	local auto = UITheme.button("AUTO", UDim2.fromScale(0.16, 0.5), UDim2.fromScale(0.63, 0.25))
	auto.Name = "AutoButton"
	auto.Parent = bar
	auto.Activated:Connect(doToggleAuto)
	autoButton = auto

	local roll = UITheme.button("ROLL", UDim2.fromScale(0.16, 0.66), UDim2.fromScale(0.81, 0.17))
	roll.Name = "RollButton"
	roll.Parent = bar
	roll.Activated:Connect(doRoll)
	rollButton = roll

	-- The optimistic pulse. A child of the button rather than a new instance per
	-- press, so the 100 ms feedback path allocates nothing at all (NFR-1).
	local pulse = Instance.new("Frame")
	pulse.Name = "RollPulse"
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.Position = UDim2.fromScale(0, 0)
	pulse.BackgroundColor3 = UITheme.Colors.TextGold
	pulse.BackgroundTransparency = 1
	pulse.BorderSizePixel = 0
	pulse.Visible = false
	pulse.ZIndex = roll.ZIndex + 1
	pulse.Parent = roll
	rollPulse = pulse
end

--------------------------------------------------------------------------------
-- Server payloads
--------------------------------------------------------------------------------

local function onStateSync(state: any): ()
	-- Absent fields leave the previous value alone rather than blanking it: a
	-- partial snapshot should not wipe a figure the server never retracted.
	local cash = readNumber(state, "cash")
	if cash ~= nil then
		lastCash = cash
	end

	local gems = readNumber(state, "gems")
	if gems ~= nil then
		lastGems = gems
	end

	local streak = readNumber(state, "streak")
	if streak ~= nil then
		lastStreak = streak
		if streak == 0 then
			-- A reset streak means the multiplier is definitionally 1; clearing
			-- the cached one stops a stale value from outliving its streak.
			lastMultiplier = nil
		end
	end

	local dice = readTable(state, "dice")
	if dice ~= nil then
		lastVoidProbability = loadoutVoidProbability(dice)
	end

	renderCurrencies()
	renderStreak()
end

local function onRollResult(result: any): ()
	local streak = readNumber(result, "streak")
	local previousStreak = lastStreak
	if streak ~= nil then
		lastStreak = streak
	end

	local multiplier = readNumber(result, "multiplier")
	if multiplier ~= nil then
		lastMultiplier = multiplier
	end

	local voidHit = readBoolean(result, "voidHit")

	renderStreak()

	-- Deliberately NOT done here: adding `payout` to lastCash. The payout is
	-- real, but the balance it produced is the server's to state, and it states
	-- it in the StateSync that follows. Adding it here would put a number on
	-- screen that no authority has confirmed.

	if voidHit == true then
		cue("VoidHit")
	else
		cue("RollLand")
		if streak ~= nil and previousStreak ~= nil and streak > previousStreak then
			cue("StreakUp")
		end
	end
end

local function onEventState(state: any): ()
	likeProgress = readNumber(state, "likeGoalProgress")
	likeTarget = readNumber(state, "likeGoalTarget")
	eventActive = readBoolean(state, "eventActive") == true
	renderLikeGoal()
	renderEvent()
end

local function onNotice(notice: any): ()
	if type(notice) ~= "table" then
		return
	end
	local code = (notice :: { [string]: any }).code
	if type(code) ~= "string" then
		return
	end
	-- Enumerated codes only; nothing internal crosses the boundary (threat T-7).
	-- Rendered as the code itself, upper-cased -- the client does not invent a
	-- friendlier story about a server condition it cannot see.
	-- Bound to a local first: string.gsub returns two values, and passing it
	-- straight into string.upper would hand it a second argument.
	local spaced = string.gsub(code, "_", " ")
	setStatus(string.upper(spaced))
	cue("UiRefused")
end

--------------------------------------------------------------------------------
-- Throttle-aware button state
--------------------------------------------------------------------------------

local THROTTLE_POLL = 0.05
local throttleAccumulator = 0

-- Greys ROLL and AUTO while NetClient's cooperative throttle would refuse them,
-- so the player sees an unavailable button instead of pressing one and being
-- told off (the button is still connected; UITheme.setEnabled only changes how
-- it looks, so the press still produces an honest explanation).
local function onHeartbeat(deltaTime: number): ()
	local now = os.clock()
	fadeRollPulse(now)

	throttleAccumulator += deltaTime
	if throttleAccumulator < THROTTLE_POLL then
		return
	end
	throttleAccumulator = 0

	local client = net
	if client == nil then
		return
	end

	local canRoll = client.readyIn("Roll") <= 0
	if canRoll ~= rollEnabledCache then
		rollEnabledCache = canRoll
		local button = rollButton
		if button ~= nil then
			UITheme.setEnabled(button, canRoll)
		end
	end

	local canAuto = client.readyIn("SetAutoRoll") <= 0
	if canAuto ~= autoEnabledCache then
		autoEnabledCache = canAuto
		local button = autoButton
		if button ~= nil then
			UITheme.setEnabled(button, canAuto)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HUD.init(client: Net): ()
	if screenGui ~= nil then
		return
	end
	net = client

	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		error("[HUD] no LocalPlayer", 2)
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "DiceForgeHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = UITheme.Layer.HUD
	-- Left false on purpose: the top bar must sit BELOW Roblox's own inset, or
	-- the cash figure hides behind the platform chrome on a 320 px phone
	-- (NFR-3).
	gui.IgnoreGuiInset = false
	gui.Parent = playerGui
	screenGui = gui

	buildTopBar(gui)
	buildStreakStrip(gui)
	buildBottomBar(gui)

	renderCurrencies()
	renderStreak()
	renderLikeGoal()
	renderEvent()
	renderAuto()
	setStatus("")

	table.insert(connections, client.onStateSync(onStateSync))
	table.insert(connections, client.onRollResult(onRollResult))
	table.insert(connections, client.onEventState(onEventState))
	table.insert(connections, client.onNotice(onNotice))

	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
end

function HUD.shutdown(): ()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}

	local beat = heartbeat
	if beat ~= nil then
		beat:Disconnect()
	end
	heartbeat = nil

	local gui = screenGui
	if gui ~= nil then
		gui:Destroy()
	end
	screenGui = nil
	textCache = {}
	rollEnabledCache = nil
	autoEnabledCache = nil
	autoRollWanted = false
	net = nil
end

return HUD
