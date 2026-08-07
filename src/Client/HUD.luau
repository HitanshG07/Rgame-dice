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
-- and SetShape (verified against RemoteGateway.register call sites, 2026-08-08)
-- -- and none of those four systems is among them. Each therefore renders in an
-- explicit unavailable state that says so when pressed. It is not a button that
-- looks live and does nothing.
--
-- AUTO-ROLL IS ONE OF THEM, and it is the one that looked otherwise. `SetAutoRoll`
-- is declared in `Remotes` and carries a RemoteGateway rate-limit entry, which is
-- the whole of its existence server-side: nothing calls `RemoteGateway.register`
-- for it, so there is no `OnServerInvoke` behind the RemoteFunction. An earlier
-- revision of this file shipped AUTO as a live, enabled button that invoked it,
-- so the press failed inside NetClient's pcall and the player was shown "SERVER
-- DID NOT ANSWER" -- the server blamed for declining a feature it was never asked
-- to have, and, on the Roblox behaviour where an unhandled invocation yields
-- rather than raising, one client thread parked per press. AUTO now takes the
-- same pending treatment as CHEST, SPIN, GROUP and SHOP: nothing is sent, so
-- nothing can be blamed and nothing can be parked. It becomes a live control in
-- the same change that registers its handler and gives its state a field in the
-- StateSync snapshot -- not before, because a toggle the server cannot confirm is
-- a toggle this HUD may not claim to have set (FR-7.2).
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
-- exactly which calls it is allowed to make. Widening it is a visible diff.
-- NOTE THE ABSENCE of anything that takes a number: nothing this module sends
-- can carry a price, balance, reward, level, duration or multiplier (NFR-5).
--
-- `setAutoRoll` is deliberately NOT listed. NetClient still offers it, and the
-- type is structural, so re-adding the line is all it takes once a server
-- handler exists -- and until then the omission is what makes "the HUD cannot
-- send this" a fact about the code rather than a promise in a comment.
type NetResult = { ok: boolean, reason: string? }

export type Net = {
	roll: () -> NetResult,
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

-- A count that is not a whole number is malformed, not something to round.
-- `readNumber` admits any finite number, and Luau's `%d` RAISES on 2.5 rather
-- than truncating it -- a throw that NetClient's per-handler pcall swallows, so
-- the streak strip would freeze silently while cash carried on updating.
-- Rejecting integrality at the boundary makes the worst case a dash.
local function readInteger(source: any, key: string): number?
	local value = readNumber(source, key)
	if value == nil or value % 1 ~= 0 then
		return nil
	end
	return value
end

local function readString(source: any, key: string): string?
	if type(source) ~= "table" then
		return nil
	end
	local value = (source :: { [string]: any })[key]
	return if type(value) == "string" then value else nil
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

		-- The floor is per-shape and REQUIRED. Without it `voidProbability`
		-- cannot apply the proximity gate (a face counts as Void only when it is
		-- the lightest AND sits at or under floor * VOID_FLOOR_FACTOR) and
		-- reports the lightest face's landing probability as though it were the
		-- streak-break chance: 16.7% on a starting D6 whose true Void chance is
		-- zero. `massFloor` is now a required parameter precisely so no caller
		-- can ask this question without answering that one first.
		--
		-- An unrecognised shape id renders a dash rather than borrowing
		-- DiceCatalog's default floor. `getMassFloor` answers 1 for an id it does
		-- not know, and a guessed floor produces a confident percentage measured
		-- against a gate the server would never have applied.
		local shapeId = readString(die, "Shape")
		if shapeId == nil or DiceCatalog.getShape(shapeId) == nil then
			return nil
		end

		-- ForgeMath raises on degenerate input (zero total mass, for instance).
		-- A snapshot that trips it is a display problem, never a crash.
		local ok, p = pcall(ForgeMath.voidProbability, mass, DiceCatalog.getMassFloor(shapeId))
		if not ok or type(p) ~= "number" or not ForgeMath.isFinite(p) then
			return nil
		end

		-- A flat, un-forged die fails the proximity gate and contributes exactly
		-- 0, multiplying `survive` by 1 and leaving 1 - product(1 - p_i) exactly
		-- as it was. That is the correct reading and not a special case: a die
		-- that cannot land a Void cannot break the streak, so a loadout of only
		-- such dice reports 0.0% and a mixed loadout reports the forged dice's
		-- combined chance alone.
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
-- The streak `lastMultiplier` was reported against. The multiplier arrives on
-- RollResult and has NO field in the StateSync snapshot, so nothing in a later
-- snapshot can correct it; binding it to its streak is what lets renderStreak
-- refuse to draw a figure whose streak has since moved on.
local lastMultiplierStreak: number? = nil
local lastVoidProbability: number? = nil
local likeProgress: number? = nil
local likeTarget: number? = nil
local eventActive = false

local rollPendingUntil = 0
-- Taken synchronously on the press, released when the reply lands. See doRoll.
local rollInFlight = false

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
local rollPulse: Frame? = nil

local connections: { RBXScriptConnection } = {}
local heartbeat: RBXScriptConnection? = nil

-- Cached rendered text. Every setter compares before assigning, so the steady
-- state -- an idle HUD, or an auto-roll at five per second where only the cash
-- figure moves -- performs no property writes it does not need and allocates
-- no strings it does not need.
local textCache: { [string]: string } = {}
local rollEnabledCache: boolean? = nil

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
	-- Format, not `%d`. The integrality that `%d` demands is enforced at the
	-- reader instead, so an unrepresentable streak is already nil by the time it
	-- reaches here and this line cannot raise.
	local streak = lastStreak
	setText(streakLabel, "streak", "STREAK  " .. (if streak == nil then EMPTY else Format.formatNumber(streak)))

	-- The multiplier is a SERVER number, and it is drawn only for the streak the
	-- server quoted it against -- a multiplier held over a streak that has since
	-- changed describes a state the player is no longer in. The one case where it
	-- is safe to state without the server having said it is streak zero, where
	-- (1+b)^0 = 1 by definition for every value of b (FR-5.3) and no
	-- player-specific data is being guessed at. Anything else renders a dash
	-- rather than an arithmetic guess about b.
	local multiplierText: string
	if lastMultiplier ~= nil and streak ~= nil and lastMultiplierStreak == streak then
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

-- The one place a refusal, a notice or an unavailable entry point becomes
-- words. A single pooled label; no toast instances are created or destroyed.
--
-- Every message EXPIRES. A "SLOW DOWN" left on screen stops describing what just
-- happened and starts describing the interface as permanently unhappy, and the
-- player has no way to tell a message about this press from one about a press
-- two minutes ago. The clear runs on the heartbeat that is already ticking, so
-- no timer thread is spawned per message.
local STATUS_SECONDS = 4
local statusUntil = 0

local function setStatus(text: string): ()
	setText(statusLabel, "status", text)
	statusUntil = if text == "" then 0 else os.clock() + STATUS_SECONDS
end

local function expireStatus(now: number): ()
	if statusUntil > 0 and now >= statusUntil then
		setStatus("")
	end
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

	-- The latch is taken and tested SYNCHRONOUSLY, before the thread hop. The
	-- readyIn pre-check below and NetClient's own throttle stamp sit on opposite
	-- sides of that hop, so two presses inside one frame could both pass the
	-- check and both pulse while only one of them ever reached the wire -- a
	-- pulse promising a roll that was silently dropped. Held until the reply
	-- lands, it also guarantees at most one request in flight, so a press cannot
	-- park a thread behind an earlier one.
	if rollInFlight then
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
	rollInFlight = true
	pulseRoll()
	cue("RollPress")

	task.spawn(function()
		-- NetClient wraps the invocation in a pcall and always answers with a
		-- Result, so this cannot throw past the release below and strand the
		-- latch set.
		local result = client.roll()
		rollInFlight = false
		if not result.ok then
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

	-- FR-7.2's auto-roll. `SetAutoRoll` has a Remotes entry and a rate-limit
	-- entry and no handler, so this is an entry point with no system behind it
	-- exactly like CHEST and SPIN, and it is drawn as one. Nothing is invoked.
	local auto = addPendingButton(bar, "AUTO", UDim2.fromScale(0.16, 0.5), UDim2.fromScale(0.63, 0.25))
	auto.Name = "AutoButton"

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
	-- EVERY FIELD IS OVERWRITTEN, INCLUDING WITH NIL. StateSync is a FULL
	-- snapshot (API_DATA_CONTRACT §1.2), never a patch, so a field this reader
	-- cannot make sense of is not "unchanged" -- it is unknown, and there is no
	-- contract under which the previous figure still describes it.
	--
	-- The earlier keep-previous form was the same mistake this file exists to
	-- prevent, arrived at from the other direction: a snapshot with a malformed
	-- `cash` taken straight after a spend would leave the PRE-SPEND balance on
	-- screen, indefinitely, presented as a present fact with no dash to admit
	-- otherwise. A stale confirmed-once number is a claim about the player's
	-- money exactly as a zero is. `onEventState` has always taken this form.
	lastCash = readNumber(state, "cash")
	lastGems = readNumber(state, "gems")
	lastStreak = readInteger(state, "streak")
	lastVoidProbability = loadoutVoidProbability(readTable(state, "dice"))

	-- No multiplier is read: the snapshot has no such field (verified against
	-- StateSyncService.buildSnapshot, 2026-08-08). It is left where RollResult
	-- put it, and renderStreak draws it only while its bound streak still
	-- matches the one just read -- so a streak the snapshot moved retires the
	-- multiplier with it, without this handler having to guess a replacement.

	renderCurrencies()
	renderStreak()
end

local function onRollResult(result: any): ()
	local streak = readInteger(result, "streak")
	local previousStreak = lastStreak
	if streak ~= nil then
		lastStreak = streak
	end

	-- Stored together or not at all. A multiplier with no streak to pin it to
	-- cannot be checked for staleness later, and an unpinnable figure is one
	-- this HUD declines to draw.
	local multiplier = readNumber(result, "multiplier")
	if multiplier ~= nil and streak ~= nil then
		lastMultiplier = multiplier
		lastMultiplierStreak = streak
	else
		lastMultiplier = nil
		lastMultiplierStreak = nil
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
	-- Whole numbers or nothing. A fractional like count is malformed, and
	-- rendering "1.50 / 100" would dress a broken payload up as real activity.
	likeProgress = readInteger(state, "likeGoalProgress")
	likeTarget = readInteger(state, "likeGoalTarget")
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

-- Greys ROLL while NetClient's cooperative throttle would refuse it, so the
-- player sees an unavailable button instead of pressing one and being told off
-- (the button is still connected; UITheme.setEnabled only changes how it looks,
-- so the press still produces an honest explanation). Also runs the two
-- time-based clears -- the roll pulse and the status message -- on the tick that
-- is already scheduled, rather than spawning a thread per press.
local function onHeartbeat(deltaTime: number): ()
	local now = os.clock()
	fadeRollPulse(now)
	expireStatus(now)

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

	-- AUTO is not polled. It is a pending button held permanently grey by
	-- addPendingButton, and a throttle it never consumes has nothing to say
	-- about it.
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

	-- THE DISPLAY STATE GOES TOO, not just the caches. Clearing textCache alone
	-- left every figure -- cash, gems, streak, multiplier, Void, the like goal,
	-- the event flag -- alive in module scope, so a re-init repainted the
	-- PREVIOUS session's numbers before a single packet of the new one arrived.
	-- Those figures were true of a player who may not be this player, and are in
	-- any case unconfirmed now. A HUD that has heard nothing yet shows dashes.
	textCache = {}
	rollEnabledCache = nil

	lastCash = nil
	lastGems = nil
	lastStreak = nil
	lastMultiplier = nil
	lastMultiplierStreak = nil
	lastVoidProbability = nil
	likeProgress = nil
	likeTarget = nil
	eventActive = false

	statusUntil = 0
	throttleAccumulator = 0
	rollPendingUntil = 0
	rollInFlight = false

	net = nil
end

return HUD
