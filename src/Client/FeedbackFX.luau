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
-- pool is fixed at construction and the per-frame loop allocates nothing
-- (NFR-1). If every slot is busy, the oldest is recycled rather than a new one
-- being made -- dropping the least relevant number beats dropping frames.
--
-- ON THE SETTINGS TOGGLES (FR-13.6). Particles and motion blur are player
-- choices about DECORATION, never about information. Turning both off removes
-- the sparks and the trailing ghost; the payout number itself always appears,
-- because a player who turned particles off to help their frame rate did not
-- ask to stop being told what they earned. Both default to ENABLED when the
-- state snapshot carries no Settings block.
--
-- Every colour and the font come from UITheme; sizing is Scale-only (FR-13.7).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local UITheme = require(Client:WaitForChild("UITheme"))
local ArenaView = require(Client:WaitForChild("ArenaView"))

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

-- Where the text is anchored in the world: above the middle of the pit.
local ANCHOR_LIFT = 3.5

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
	showGhost: boolean,
	showSparks: boolean,
}

local pool: { Item } = {}
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
	ghost.TextTransparency = 0.7
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
		local spark = UITheme.label("+", UDim2.fromScale(0.3, 0.6), UDim2.fromScale(0.35, 0.2), UITheme.Colors.TextGold)
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
		showGhost = true,
		showSparks = true,
	}
end

--------------------------------------------------------------------------------
-- Scaling to the payout
--------------------------------------------------------------------------------

-- One normalised "bigness" in [0, 1] drives width, duration and travel together,
-- so a big win is bigger on every axis at once rather than in one of them.
local function magnitude(payout: number): number
	if payout ~= payout or payout <= 0 or payout >= math.huge then
		return 0
	end
	return math.clamp(math.log10(payout + 1) / 6, 0, 1)
end

--------------------------------------------------------------------------------
-- Acquiring a slot
--------------------------------------------------------------------------------

local function acquire(): Item
	for i = 1, POOL_SIZE do
		local item = pool[i]
		if not item.active then
			return item
		end
	end
	-- Everything is busy: recycle the one that started earliest. Its number has
	-- already been on screen longest, so it is the least costly to cut short.
	local oldest = pool[1]
	for i = 2, POOL_SIZE do
		if pool[i].sequence < oldest.sequence then
			oldest = pool[i]
		end
	end
	return oldest
end

--------------------------------------------------------------------------------
-- The anchor point, projected from the world into screen scale.
--
-- Computed once per payout, not per frame: the camera is fixed while the text
-- is on screen, and projecting every frame would be per-frame work for an
-- answer that does not change.
--------------------------------------------------------------------------------

local function anchorInScreenScale(): (number, number)
	local camera = ArenaView.getCamera()
	if camera == nil then
		return 0.5, 0.45
	end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return 0.5, 0.45
	end
	local world = ArenaView.getCenter() + Vector3.new(0, ANCHOR_LIFT, 0)
	local screen = camera:WorldToViewportPoint(world)
	return math.clamp(screen.X / viewport.X, 0.1, 0.9), math.clamp(screen.Y / viewport.Y, 0.1, 0.9)
end

--------------------------------------------------------------------------------
-- Presenting a payout
--------------------------------------------------------------------------------

local function present(payout: number, voidHit: boolean): ()
	local item = acquire()
	local size = magnitude(payout)

	local paid = payout > 0
	local text: string
	local colour: Color3
	if paid then
		text = "+" .. Format.formatNumber(payout)
		colour = UITheme.Colors.Cash
	elseif voidHit then
		text = "VOID"
		colour = UITheme.Colors.VoidFace
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

	-- FR-13.6: decoration obeys the toggles; the number never does. Sparks are
	-- also suppressed for a zero payout, where celebrating would be a lie.
	item.showGhost = motionBlurEnabled
	item.showSparks = particlesEnabled and paid
	item.ghost.Visible = item.showGhost
	for s = 1, SPARKS_PER_ITEM do
		item.sparks[s].Visible = item.showSparks
	end

	item.frame.Position = UDim2.fromScale(item.baseX, item.baseY)
	item.frame.Visible = true
end

--------------------------------------------------------------------------------
-- The frame loop. One connection; no allocation inside it (NFR-1).
--------------------------------------------------------------------------------

local function step(deltaTime: number): ()
	for i = 1, POOL_SIZE do
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

-- Reads a boolean out of an untrusted-in-SHAPE settings table under either
-- casing. Absent or malformed means ENABLED, matching the server template's
-- defaults in PlayerProfile.
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

function FeedbackFX.init(net: any): ()
	if started then
		return
	end
	started = true

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

	for i = 1, POOL_SIZE do
		pool[i] = makeItem(gui)
	end

	net.onStateSync(function(state: any)
		if type(state) ~= "table" then
			return
		end
		local settings = state.settings
		if type(settings) ~= "table" then
			settings = state.Settings
		end
		particlesEnabled = readToggle(settings, "Particles", "particles")
		motionBlurEnabled = readToggle(settings, "MotionBlur", "motionBlur")
	end)

	-- Already credited by the time this arrives (FR-2.6). This is a receipt,
	-- not a transaction.
	net.onRollResult(function(result: any)
		if type(result) ~= "table" then
			return
		end
		local payout = result.payout
		if type(payout) ~= "number" then
			return
		end
		present(payout, result.voidHit == true)
	end)

	RunService.RenderStepped:Connect(step)
end

return FeedbackFX
