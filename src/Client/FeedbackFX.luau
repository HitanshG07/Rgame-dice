--!strict
-- FeedbackFX.luau
-- Floating payout text in the arena (SRS FR-2.8), scaled to the size of the win.
--
-- WHY THIS FIRES ON `RollResult` AND NOT WHEN THE DICE LAND. FR-2.8 says the
-- payout is displayed "at the moment of credit". The credit happens on the
-- server, before `RollResult` is sent (API_DATA_CONTRACT §1.2), so the earliest
-- honest moment on the client is the instant that message arrives -- which is
-- also the moment the tumble begins, not the moment it ends. Waiting for the
-- animation to finish would tie the display of a real transaction to an
-- animation that FR-2.6 explicitly permits to be interrupted. A player who
-- drops frames for two seconds still sees what they were paid.
--
-- WHY THE TEXT IS POOLED. Auto-roll can produce several payouts a second for a
-- whole session. Creating and destroying a TextLabel per roll is the classic
-- way a Roblox client's frame time quietly degrades over twenty minutes; the
-- pool is fixed at construction and no Instance is created after init (NFR-1 --
-- see ACCEPTED ALLOCATION below for the one thing that does still allocate per
-- frame). If every slot is busy, the oldest is recycled rather than a new one
-- being made -- dropping the least relevant number beats dropping frames.
--
-- ON THE SETTINGS TOGGLES (FR-13.6). Particles and motion blur are player
-- choices about DECORATION, never about information. Turning both off removes
-- the sparks and the trailing ghost; the payout number itself always appears,
-- because a player who turned particles off to help their frame rate did not
-- ask to stop being told what they earned. Both default to ENABLED when neither
-- source states otherwise -- the absence of a preference is not a preference.
--
-- THE TOGGLES HAVE ONE SOURCE (corrected 2026-08-11).
--
-- `StateSync.settings` (API_DATA_CONTRACT §1.2, emitted by StateSyncService from
-- the PlayerProfile `Settings` template, keys `Particles` / `MotionBlur`). It is
-- authoritative at join and it is what survives a rejoin.
--
-- WHAT THIS COMMENT USED TO SAY, and why the correction matters. It described a
-- SECOND source -- MenuPanel holding session-scoped toggles -- on the stated
-- grounds that "persisting a settings change needs a remote that does not
-- exist". The `SetSetting` remote now exists (FR-13.6), so a toggle writes to the
-- profile and comes back down this same snapshot path. There is no session-only
-- copy of a setting anywhere any more, and there should not be one: two sources
-- for one boolean is how a panel ends up showing a value the server does not
-- hold.
--
-- `applySettings` stays public as a PUSH entry point, mirroring
-- `AudioDirector.applySettings`, so a surface already holding a snapshot can
-- apply it without a second round trip. Nothing pushes through it today.
--
-- ACCEPTED ALLOCATION (NFR-1 says "no allocation inside per-frame loops").
-- `step` constructs UDim2 values: one per active item for the frame position,
-- one more if the ghost is on, and one per spark if sparks are on. With the
-- pool fully busy and every decoration enabled that is a worst case of
-- 10 * (1 + 1 + 4) = 60 UDim2 constructions per frame; the realistic case is
-- one or two active items, so six to twelve. This is ACCEPTED, not overlooked.
-- `UDim2` is a heap-allocated userdata and Roblox exposes no mutating setter
-- for a GUI object's Position -- assigning a position REQUIRES constructing the
-- value. The only ways to avoid it are to stop moving the text (which is the
-- feature) or to cache and reuse UDim2 instances (impossible: they are
-- immutable, and a distinct position per frame is a distinct value). Nothing
-- else in the loop allocates: no tables, no strings, no closures, and the spark
-- direction vectors are computed once at load. The remaining per-frame writes
-- are numbers assigned to existing properties.
--
-- Every colour and the font come from UITheme; sizing is Scale-only (FR-13.7).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local UITheme = require(Client:WaitForChild("UITheme"))
local BoardView = require(Client:WaitForChild("BoardView"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))

local FeedbackFX = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local POOL_SIZE = 10
local SPARKS_PER_ITEM = 4

local MIN_DURATION = 1.1
local MAX_DURATION = 2.0

-- Text box width, as a fraction of the screen. The floor is the smallest size
-- that stays legible on a 320px phone (NFR-3); the ceiling stops a jackpot from
-- covering the arena it is celebrating.
local WIDTH_MIN = 0.14
local WIDTH_MAX = 0.34
local ASPECT = 0.34          -- height as a fraction of width

local RISE = 0.16            -- how far the text floats up, in screen fractions
local SPARK_TRAVEL = 0.07
local GHOST_LAG = 0.10       -- the trail's share of the main label's travel

-- The resting values of every property `step` animates. `present` restores all
-- of them, because a pooled item arrives carrying whatever the previous run
-- left behind and would otherwise render one frame of the last payout's fade
-- and scattered sparks before the loop overwrites them.
local GHOST_TRANSPARENCY = 0.55
local SPARK_BASE_X = 0.35
local SPARK_BASE_Y = 0.2

-- How far ABOVE the board's centre payout text starts its rise, so it reads as
-- coming off the dice rather than out from behind them.
--
-- UNITS CHANGED WHEN THE BOARD WENT FLAT. This was 3.5 STUDS, lifted in world
-- space before being projected through the camera. The board is now a ScreenGui
-- and the anchor is composed in screen scale, where 3.5 means three and a half
-- SCREEN HEIGHTS -- the text would be clamped to the top edge on every payout
-- and never seen to move. A fifteenth of the screen is the flat equivalent.
local ANCHOR_LIFT = 0.065

--------------------------------------------------------------------------------
-- Types and state
--------------------------------------------------------------------------------

type Item = {
	frame: Frame,
	ghost: TextLabel,
	main: TextLabel,
	sparks: { TextLabel },
	active: boolean,
	elapsed: number,
	duration: number,
	baseX: number,
	baseY: number,
	sequence: number,
	paid: boolean,
	showGhost: boolean,
	showSparks: boolean,
}

-- The push shape. Fields are optional so that a caller who knows about only one
-- of the two toggles cannot accidentally assert `false` for the other; absent
-- means "no preference stated", which means enabled.
export type FXSettings = {
	particles: boolean?,
	motionBlur: boolean?,
}

local pool: { Item } = {}
local connections: { RBXScriptConnection } = {}
local screenGui: ScreenGui? = nil
local started = false
local sequence = 0

-- FR-13.6. Default ON: the absence of a preference is not a preference.
local particlesEnabled = true
local motionBlurEnabled = true

-- Fixed spark directions, computed once. Recomputing four unit vectors per roll
-- would be trivial waste; recomputing them per frame would not be.
local SPARK_DIRS: { Vector2 } = {}
for i = 1, SPARKS_PER_ITEM do
	local angle = ((i - 1) / SPARKS_PER_ITEM) * math.pi * 2 + math.pi / 4
	SPARK_DIRS[i] = Vector2.new(math.cos(angle), math.sin(angle))
end

--------------------------------------------------------------------------------
-- Construction (init only)
--------------------------------------------------------------------------------

local function makeItem(gui: ScreenGui): Item
	local frame = Instance.new("Frame")
	frame.Name = "Payout"
	frame.Size = UDim2.fromScale(WIDTH_MIN, WIDTH_MIN * ASPECT)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui

	-- The ghost is drawn first so it sits behind the main label. It is the
	-- motion-blur stand-in: a real blur pass is not available to a ScreenGui,
	-- and a lagging semi-transparent copy sells the same movement for nothing.
	local ghost = UITheme.label("", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), UITheme.Colors.TextGold)
	ghost.Name = "Ghost"
	ghost.TextXAlignment = Enum.TextXAlignment.Center
	ghost.TextTransparency = GHOST_TRANSPARENCY
	ghost.Parent = frame

	local main = UITheme.label("", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), UITheme.Colors.Cash)
	main.Name = "Main"
	main.TextXAlignment = Enum.TextXAlignment.Center
	main.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Colors.PanelDeep
	stroke.Thickness = UITheme.BorderThickness
	stroke.Parent = main

	local sparks: { TextLabel } = {}
	for s = 1, SPARKS_PER_ITEM do
		local spark = UITheme.label("+", UDim2.fromScale(0.3, 0.6), UDim2.fromScale(SPARK_BASE_X, SPARK_BASE_Y), UITheme.Colors.TextGold)
		spark.Name = "Spark" .. tostring(s)
		spark.TextXAlignment = Enum.TextXAlignment.Center
		spark.Parent = frame
		sparks[s] = spark
	end

	return {
		frame = frame,
		ghost = ghost,
		main = main,
		sparks = sparks,
		active = false,
		elapsed = 0,
		duration = MIN_DURATION,
		baseX = 0.5,
		baseY = 0.5,
		sequence = 0,
		paid = false,
		showGhost = true,
		showSparks = true,
	}
end

--------------------------------------------------------------------------------
-- Scaling to the payout
--------------------------------------------------------------------------------

-- One normalised "bigness" in [0, 1] drives width, duration and travel together,
-- so a big win is bigger on every axis at once rather than in one of them.
-- Magnitude is taken of the ABSOLUTE value: a large debit is as significant an
-- event as a large credit and deserves the same amount of the player's screen.
local function magnitude(payout: number): number
	if payout ~= payout then
		return 0
	end
	local size = math.abs(payout)
	if size <= 0 or size >= math.huge then
		return 0
	end
	return math.clamp(math.log10(size + 1) / 6, 0, 1)
end

--------------------------------------------------------------------------------
-- Acquiring a slot
--------------------------------------------------------------------------------

-- Only ever called with a non-empty pool -- `present` guards that -- so the
-- `pool[1]` fallback below always resolves.
local function acquire(): Item
	for i = 1, #pool do
		local item = pool[i]
		if not item.active then
			return item
		end
	end
	-- Everything is busy: recycle the one that started earliest. Its number has
	-- already been on screen longest, so it is the least costly to cut short.
	local oldest = pool[1]
	for i = 2, #pool do
		if pool[i].sequence < oldest.sequence then
			oldest = pool[i]
		end
	end
	return oldest
end

--------------------------------------------------------------------------------
-- The anchor point: where payout text floats up from.
--
-- THIS USED TO BE A WORLD-TO-SCREEN PROJECTION. The 3D pit had a camera, so the
-- anchor was the pit's centre lifted a few studs and projected through the
-- camera's viewport, with fallbacks for a missing camera and for a zero-sized
-- viewport during startup or a resize.
--
-- The board is now a ScreenGui and its centre is ALREADY screen scale, so the
-- camera, the projection, the viewport division and both failure modes are gone
-- rather than ported. There is nothing left that can fail here.
--------------------------------------------------------------------------------

local function anchorInScreenScale(): (number, number)
	-- BoardView reports the board's centre in its own interior scale; the tray
	-- occupies a known rectangle of the screen, so the two compose into absolute
	-- screen scale. Lifted slightly so text rises from ABOVE the dice rather
	-- than out from behind them.
	local bx, by, bw, bh = BoardView.getRect()
	local centre = BoardView.getCenter()
	local x = bx + centre.X.Scale * bw
	local y = by + centre.Y.Scale * bh - ANCHOR_LIFT
	return math.clamp(x, 0.1, 0.9), math.clamp(y, 0.1, 0.9)
end

--------------------------------------------------------------------------------
-- Presenting a payout
--------------------------------------------------------------------------------

local function present(payout: number, voidHit: boolean): ()
	if #pool == 0 then
		return
	end

	local item = acquire()
	local size = magnitude(payout)

	-- The sign chooses the rendering, and a negative payout is a DEBIT that must
	-- read as one. `Format.formatNumber` already carries the minus sign, so the
	-- only thing needed is to stop routing it into the neutral zero branch --
	-- telling a player "0" while their balance went down is a false receipt.
	local credited = payout > 0
	local debited = payout < 0
	local text: string
	local colour: Color3
	if credited then
		text = "+" .. Format.formatNumber(payout)
		colour = UITheme.Colors.Cash
	elseif debited then
		text = Format.formatNumber(payout)
		colour = UITheme.Colors.Negative
	elseif voidHit then
		text = "VOID"
		colour = UITheme.Colors.VoidFace
	elseif payout ~= payout then
		-- Not a number at all, which is a contract violation upstream. Whatever
		-- it is, it is not zero, and `formatNumber` renders it as "NaN" -- the
		-- truth. Inventing a "0" here would hide a server bug behind a plausible
		-- looking receipt.
		text = Format.formatNumber(payout)
		colour = UITheme.Colors.Negative
	else
		text = "0"
		colour = UITheme.Colors.TextDim
	end

	item.main.Text = text
	item.main.TextColor3 = colour
	item.ghost.Text = text
	item.ghost.TextColor3 = colour

	local width = WIDTH_MIN + (WIDTH_MAX - WIDTH_MIN) * size
	item.frame.Size = UDim2.fromScale(width, width * ASPECT)

	local baseX, baseY = anchorInScreenScale()
	-- A small deterministic fan across the pool keeps two payouts in the same
	-- second from printing exactly on top of each other.
	sequence += 1
	item.baseX = math.clamp(baseX + ((sequence % 3) - 1) * 0.05, 0.06, 0.94)
	item.baseY = baseY
	item.sequence = sequence

	item.duration = MIN_DURATION + (MAX_DURATION - MIN_DURATION) * size
	item.elapsed = 0
	item.active = true
	item.paid = credited

	-- FR-13.6: decoration obeys the toggles; the number never does. Sparks are
	-- also suppressed for anything that is not a credit -- celebrating a zero or
	-- a debit would be a lie.
	item.showGhost = motionBlurEnabled
	item.showSparks = particlesEnabled and credited
	item.ghost.Visible = item.showGhost
	for s = 1, SPARKS_PER_ITEM do
		item.sparks[s].Visible = item.showSparks
	end

	-- Restore every property `step` animates to its t=0 value. This item may be
	-- a recycled one still holding the previous payout's fade and spark spread,
	-- and it becomes visible on this frame -- before `step` next runs.
	item.main.TextTransparency = 0
	item.ghost.TextTransparency = GHOST_TRANSPARENCY
	item.ghost.Position = UDim2.fromScale(0, GHOST_LAG)
	for s = 1, SPARKS_PER_ITEM do
		local spark = item.sparks[s]
		spark.Position = UDim2.fromScale(SPARK_BASE_X, SPARK_BASE_Y)
		spark.TextTransparency = 0
	end

	item.frame.Position = UDim2.fromScale(item.baseX, item.baseY)
	item.frame.Visible = true
end

--------------------------------------------------------------------------------
-- The frame loop. One connection. The only allocation inside it is the UDim2
-- construction that a GUI reposition unavoidably requires -- accepted and
-- quantified in the header under ACCEPTED ALLOCATION (NFR-1).
--------------------------------------------------------------------------------

local function step(deltaTime: number): ()
	-- `#pool` and not POOL_SIZE: after `shutdown` the pool is empty, and this
	-- must read as "nothing to animate" rather than indexing destroyed labels.
	for i = 1, #pool do
		local item = pool[i]
		if not item.active then
			continue
		end

		item.elapsed += deltaTime
		local a = item.elapsed / item.duration
		if a >= 1 then
			item.active = false
			item.frame.Visible = false
			continue
		end

		-- Rise fast, then drift: the number arrives with the roll and lingers
		-- long enough to be read.
		local eased = 1 - (1 - a) * (1 - a)
		local y = item.baseY - RISE * eased
		item.frame.Position = UDim2.fromScale(item.baseX, y)

		-- Hold fully opaque for the first third, then fade out.
		local fade = if a < 0.34 then 0 else (a - 0.34) / 0.66
		item.main.TextTransparency = fade

		if item.showGhost then
			-- The trail lags behind the main label by a fixed share of its
			-- travel, which is what reads as motion.
			item.ghost.Position = UDim2.fromScale(0, GHOST_LAG * (1 - a))
			item.ghost.TextTransparency = 0.55 + 0.45 * fade
		end

		if item.showSparks then
			local spread = SPARK_TRAVEL * eased
			for s = 1, SPARKS_PER_ITEM do
				local dir = SPARK_DIRS[s]
				local spark = item.sparks[s]
				spark.Position = UDim2.fromScale(0.35 + dir.X * spread * 3, 0.2 + dir.Y * spread * 3)
				spark.TextTransparency = fade
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function FeedbackFX.particlesOn(): boolean
	return particlesEnabled
end

function FeedbackFX.motionBlurOn(): boolean
	return motionBlurEnabled
end

-- Pushes a settings record in. This is the entry point the Orchestrator uses to
-- bridge `MenuPanel.onSettingsChanged` to this module, mirroring
-- `AudioDirector.applySettings` for the audio half of the same record. It is
-- also what the StateSync handler funnels the join snapshot through, so there
-- is exactly one place where these two booleans change.
--
-- `~= false` rather than `== true`: an omitted field is not a stated
-- preference, and the default for an unstated preference is ON.
--
-- The change applies to payouts already in flight as well as future ones. A
-- player who turns particles off is asking for them to stop, not to stop in two
-- seconds' time. Sparks stay bound to `paid` -- re-enabling particles must not
-- make a zero payout start celebrating.
--
-- The parameter is `nextSettings` and not `next` because `next` is a Luau
-- global and shadowing it is a lint warning.
function FeedbackFX.applySettings(nextSettings: FXSettings): ()
	particlesEnabled = nextSettings.particles ~= false
	motionBlurEnabled = nextSettings.motionBlur ~= false

	for i = 1, #pool do
		local item = pool[i]
		item.showGhost = motionBlurEnabled
		item.showSparks = particlesEnabled and item.paid
		item.ghost.Visible = item.showGhost
		for s = 1, SPARKS_PER_ITEM do
			item.sparks[s].Visible = item.showSparks
		end
	end
end

-- Reads a boolean out of an untrusted-in-SHAPE settings table under either
-- casing. StateSyncService copies the PlayerProfile `Settings` template
-- verbatim, so the live keys are `Particles` and `MotionBlur`; the lower-case
-- fallback costs one comparison and survives a future rename in either
-- direction. Absent or malformed means ENABLED, matching that template's
-- defaults.
local function readToggle(settings: any, upper: string, lower: string): boolean
	if type(settings) ~= "table" then
		return true
	end
	local v = settings[upper]
	if type(v) == "boolean" then
		return v
	end
	v = settings[lower]
	if type(v) == "boolean" then
		return v
	end
	return true
end

-- The single release path, shared by `shutdown` and by `init`'s retry guard.
local function release(): ()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}

	local gui = screenGui
	if gui ~= nil then
		gui:Destroy()
	end
	screenGui = nil

	-- The Items hold references to instances that no longer exist; clearing the
	-- pool is what stops `step` -- were it somehow still bound -- from writing to
	-- destroyed labels, and releases them for collection.
	table.clear(pool)
	sequence = 0
	started = false
end

function FeedbackFX.init(net: any): ()
	if started then
		return
	end

	-- `started` is now latched at the END of init, so reaching here after a
	-- failed attempt is a legitimate retry -- but that attempt may have got as
	-- far as parenting a ScreenGui or opening a subscription. Drop whatever it
	-- acquired first, or the retry leaks a second gui and a duplicate handler.
	release()

	local player = Players.LocalPlayer
	if player == nil then
		error("[FeedbackFX] no LocalPlayer", 0)
	end
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "DiceForgeFeedback"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = UITheme.Layer.Toast
	-- Every element in this layer is a transparent Frame or a TextLabel, and
	-- neither consumes input, so floating text can never swallow a tap aimed at
	-- the ROLL button underneath it. Do not add a TextButton here.
	gui.Parent = playerGui
	screenGui = gui

	for i = 1, POOL_SIZE do
		pool[i] = makeItem(gui)
	end

	-- The authoritative value, and the only one that survives a rejoin. It is
	-- routed through `applySettings` rather than assigning the two locals here,
	-- so the snapshot path and the MenuPanel path cannot drift apart.
	table.insert(connections, net.onStateSync(function(state: any)
		if type(state) ~= "table" then
			return
		end
		local settings = state.settings
		if type(settings) ~= "table" then
			settings = state.Settings
		end
		FeedbackFX.applySettings({
			particles = readToggle(settings, "Particles", "particles"),
			motionBlur = readToggle(settings, "MotionBlur", "motionBlur"),
		})
	end))

	-- Already credited by the time this arrives (FR-2.6). This is a receipt,
	-- not a transaction.
	table.insert(connections, net.onRollResult(function(result: any)
		if type(result) ~= "table" then
			return
		end
		local payout = result.payout
		if type(payout) ~= "number" then
			return
		end
		present(payout, result.voidHit == true)
	end))

	table.insert(connections, RunService.RenderStepped:Connect(step))

	-- Latched LAST, and only here. Latching it on entry would make a failed init
	-- -- a missing LocalPlayer, a subscription that threw -- permanent and
	-- silent, because the retry would return early having done nothing.
	started = true
end

-- Releases everything `init` acquired: the three connections (StateSync,
-- RollResult, RenderStepped), the ScreenGui, and with it the ten pooled frames
-- and their sixty labels, which are parented to it. Matches `HUD.shutdown`.
-- `started` is cleared so a subsequent `init` rebuilds rather than returning
-- early into a torn-down module. Idempotent: calling it twice, or before
-- `init`, does nothing the second time.
--
-- The settings state is deliberately NOT reset. It is the player's preference,
-- not an acquired resource, and a teardown/rebuild cycle that silently turned
-- their particles back on would be a bug.
function FeedbackFX.shutdown(): ()
	release()
end

return FeedbackFX
