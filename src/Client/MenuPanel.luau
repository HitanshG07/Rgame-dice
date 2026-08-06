--!strict
-- MenuPanel.luau
-- The left and right sidebars (SRS FR-13.3, FR-13.4) and the two overlay
-- surfaces this module actually owns: Statistics and Settings.
--
-- THE RULE THIS FILE IS BUILT AROUND, stated before anything else because it
-- determined the whole design: A MENU ENTRY IS ADDED ONLY WHEN THE SYSTEM
-- BEHIND IT EXISTS. The predecessor project in this repository shipped fifteen
-- sidebar entries of which most were buttons that looked live and did nothing.
-- That is the specific failure this file must not reproduce.
--
-- So an entry here is not a button plus a hope. It is a record with a declared
-- STATUS, and the status decides how it renders:
--
--   Live         -- this module opens the surface itself, right now.
--   NeedsSurface -- the surface is owned by another module and is reached
--                   through an opener the Orchestrator wires in. Until that
--                   opener is set the entry renders unavailable, so a wiring
--                   omission is VISIBLE rather than silent.
--   Pending      -- the server system does not exist. Renders greyed, suffixed
--                   "(SOON)", and says which update it is waiting for when
--                   pressed.
--
-- The statuses are declared in ONE table (ENTRIES). Turning a Pending entry
-- live when Block 5 lands is a one-line status change with the note removed,
-- and the diff shows exactly which promise was just kept.
--
-- WHY THE PENDING LIST IS AS LONG AS IT IS. Verified against the RemoteGateway
-- register call sites on 2026-08-07: the server registers exactly four
-- handlers -- Roll, Forge, SetElement and SetShape. AddDieSlot, BuyUpgrade,
-- Ascend, ClaimQuest, GetLeaderboard and RedeemCode have remote NAMES in the
-- registry and NetClient wrappers, but no handler behind them. A wrapper is not
-- a system. Every entry that would depend on one of those is Pending.
--
-- THIS MODULE SENDS NOTHING. It makes no NetClient call at all: it reads
-- StateSync for the Statistics surface and otherwise operates entirely on local
-- presentation state. There is consequently no path by which it could put a
-- price, balance, reward, level, duration or multiplier on the wire (NFR-5).
--
-- SETTINGS OWNERSHIP. FR-13.6's particle and motion-blur toggles live here
-- because this is where the settings surface is. Consumers subscribe through
-- `onSettingsChanged`; AudioDirector is pushed the audio half directly. See the
-- note on persistence at the settings section -- it is honest about what it
-- cannot yet do.
--
-- LAYOUT. Scale only (FR-13.7, NFR-3). The sidebars occupy x 0.005-0.145 and
-- 0.855-0.995 across y 0.16-0.84, which is precisely the band HUD leaves clear
-- between its streak strip and its bottom bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local ClientRoot = script.Parent
local UITheme = require(ClientRoot:WaitForChild("UITheme"))

-- Resolved defensively for the same reason HUD does it: a missing sound layer
-- must not be able to stop a visual surface from being built.
local AUDIO_WAIT = 5
local audioModule = ClientRoot:WaitForChild("AudioDirector", AUDIO_WAIT)
local Audio: any = nil
if audioModule ~= nil then
	local ok, loaded = pcall(require, audioModule)
	if ok then
		Audio = loaded
	else
		warn("[MenuPanel] AudioDirector failed to load; running silent: " .. tostring(loaded))
	end
else
	warn("[MenuPanel] AudioDirector not present; running silent")
end

local function cue(name: string): ()
	if Audio ~= nil then
		Audio.play(name)
	end
end

local MenuPanel = {}

--------------------------------------------------------------------------------
-- Public contract
--------------------------------------------------------------------------------

export type Net = {
	onStateSync: ((any) -> ()) -> RBXScriptConnection,
}

-- Surfaces owned by OTHER modules that a sidebar entry points at.
-- `Forge` is ForgePanel's; `Shape` is the shape-selection surface, which lives
-- with the forge because a shape change re-derives every face (FR-6.1).
export type SurfaceKey = "Forge" | "Shape"

-- The opener signature. `dieIndex` is optional because the sidebar has no die
-- context to offer -- it always passes nil, meaning "open on whatever die you
-- consider current". The parameter exists so the same opener can be reused from
-- a call site that DOES have a die in hand (a die in the arena, say) without
-- ForgePanel needing a second entry point.
export type SurfaceOpener = (dieIndex: number?) -> ()

-- FR-13.6 plus the two audio switches AudioDirector needs. One record so a
-- consumer receives the whole picture rather than four separate notifications.
export type Settings = {
	particles: boolean,
	motionBlur: boolean,
	sfx: boolean,
	music: boolean,
}

--------------------------------------------------------------------------------
-- Settings state
--------------------------------------------------------------------------------

-- SESSION-SCOPED, AND THAT IS A KNOWN SHORTFALL, NOT AN OVERSIGHT. FR-13.6 asks
-- for these to persist per player. Persisting them needs a remote and a profile
-- field, and neither exists: the remote registry has no settings entry and
-- adding one is a server change outside this module's remit. The toggles are
-- therefore fully functional for the session and reset on rejoin. Nothing here
-- claims otherwise, and the settings surface says so on screen.
local settings: Settings = {
	particles = true,
	motionBlur = true,
	sfx = true,
	music = true,
}

local settingsListeners: { [number]: (Settings) -> () } = {}
local nextListenerId = 1

local function snapshotSettings(): Settings
	-- A copy, so a listener cannot mutate the authoritative record by holding
	-- onto the table it was handed.
	return {
		particles = settings.particles,
		motionBlur = settings.motionBlur,
		sfx = settings.sfx,
		music = settings.music,
	}
end

local function broadcastSettings(): ()
	if Audio ~= nil then
		Audio.applySettings({ sfx = settings.sfx, music = settings.music })
	end
	local payload = snapshotSettings()
	for _, listener in pairs(settingsListeners) do
		-- One faulty listener must not stop the rest from being told.
		local ok, err = pcall(listener, payload)
		if not ok then
			warn("[MenuPanel] settings listener errored: " .. tostring(err))
		end
	end
end

function MenuPanel.getSettings(): Settings
	return snapshotSettings()
end

-- Returns an unsubscribe function. Used by the Orchestrator to bridge the
-- particle and motion-blur toggles to the arena modules, which have no other
-- way to hear about them.
function MenuPanel.onSettingsChanged(listener: (Settings) -> ()): () -> ()
	local id = nextListenerId
	nextListenerId += 1
	settingsListeners[id] = listener
	return function()
		settingsListeners[id] = nil
	end
end

--------------------------------------------------------------------------------
-- Surface openers
--------------------------------------------------------------------------------

local openers: { [string]: SurfaceOpener } = {}

-- Wiring point for the Orchestrator. Passing nil unwires, which returns the
-- entry to its unavailable rendering rather than leaving a live-looking button
-- with a dead callback.
function MenuPanel.setSurfaceOpener(key: SurfaceKey, opener: SurfaceOpener?): ()
	openers[key] = opener
	MenuPanel.refresh()
end

--------------------------------------------------------------------------------
-- Entry declarations
--------------------------------------------------------------------------------

type EntryStatus = "Live" | "NeedsSurface" | "Pending"

type Entry = {
	id: string,
	label: string,
	side: string,       -- "Left" (FR-13.3) or "Right" (FR-13.4)
	status: EntryStatus,
	surface: SurfaceKey?,
	note: string,       -- what is said when the entry cannot act
}

local BLOCK5 = "arrives with the progression update"
local NO_SERVER = "the server side of this is not built yet"

local ENTRIES: { Entry } = {
	-- FR-13.3, left, in the order the requirement lists them.
	{
		id = "Forge", label = "FORGE", side = "Left",
		status = "NeedsSurface", surface = "Forge",
		note = "the forge surface is not attached",
	},
	{
		id = "AddSlot", label = "ADD DIE SLOT", side = "Left",
		status = "Pending", surface = nil,
		note = NO_SERVER,
	},
	{
		id = "Shape", label = "SHAPE", side = "Left",
		status = "NeedsSurface", surface = "Shape",
		note = "the shape surface is not attached",
	},
	{
		id = "AutoSpeed", label = "AUTO SPEED", side = "Left",
		status = "Pending", surface = nil,
		note = NO_SERVER,
	},
	{
		id = "Ascend", label = "ASCEND", side = "Left",
		status = "Pending", surface = nil,
		note = BLOCK5,
	},

	-- FR-13.4, right.
	{
		id = "Leaderboards", label = "BOARDS", side = "Right",
		status = "Pending", surface = nil,
		note = BLOCK5,
	},
	{
		id = "Statistics", label = "STATS", side = "Right",
		status = "Live", surface = nil,
		note = "",
	},
	{
		id = "Quests", label = "QUESTS", side = "Right",
		status = "Pending", surface = nil,
		note = BLOCK5,
	},
	{
		id = "Settings", label = "SETTINGS", side = "Right",
		status = "Live", surface = nil,
		note = "",
	},
}

local SLOTS_PER_SIDE = 5

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------

local MAX_DIE_ROWS = 7   -- 5 base slots plus the +2 gamepass (FR-12.1)
local STAT_ROWS = 5      -- cash, gems, diamonds, streak, slots

local sidebarGui: ScreenGui? = nil
local overlayGui: ScreenGui? = nil
local overlayTitle: TextLabel? = nil
local noticeLabel: TextLabel? = nil

local entryButtons: { [string]: TextButton } = {}

local statRows: { TextLabel } = {}
local dieRows: { TextLabel } = {}
local statNote: TextLabel? = nil
local statsBody: Frame? = nil

local settingsBody: Frame? = nil
local settingsButtons: { [string]: TextButton } = {}
local settingsNote: TextLabel? = nil
local codesRow: TextButton? = nil

local connections: { RBXScriptConnection } = {}
local latestState: any = nil
local noticeToken = 0
local openSurfaceId: string? = nil

--------------------------------------------------------------------------------
-- Notice line
--------------------------------------------------------------------------------

local NOTICE_SECONDS = 4

-- One pooled label. Nothing is created or destroyed to show a notice, and the
-- token guards against an earlier timer clearing a later message.
local function notify(text: string): ()
	local label = noticeLabel
	if label == nil then
		return
	end
	label.Text = text
	label.Visible = true

	noticeToken += 1
	local token = noticeToken
	task.delay(NOTICE_SECONDS, function()
		if token == noticeToken and label.Parent ~= nil then
			label.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- Overlay surfaces
--------------------------------------------------------------------------------

local function closeOverlay(): ()
	local gui = overlayGui
	if gui == nil or not gui.Enabled then
		return
	end
	gui.Enabled = false
	openSurfaceId = nil
	cue("PanelClose")
end

-- Exposed so the Orchestrator can make this module yield the screen before
-- ForgePanel takes it. Both surfaces sit at UITheme.Layer.Panel and neither
-- knows about the other, so somebody has to sequence them and it is not a view.
function MenuPanel.closeAll(): ()
	closeOverlay()
end

local function showOverlay(id: string, title: string, body: Frame): ()
	local gui = overlayGui
	local titleLabel = overlayTitle
	if gui == nil or titleLabel == nil then
		return
	end

	local stats = statsBody
	if stats ~= nil then
		stats.Visible = (stats == body)
	end
	local prefs = settingsBody
	if prefs ~= nil then
		prefs.Visible = (prefs == body)
	end

	titleLabel.Text = title
	gui.Enabled = true
	openSurfaceId = id
	cue("PanelOpen")
end

--------------------------------------------------------------------------------
-- Statistics
--------------------------------------------------------------------------------

local EMPTY = "--"

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

local function readString(source: any, key: string): string?
	if type(source) ~= "table" then
		return nil
	end
	local value = (source :: { [string]: any })[key]
	return if type(value) == "string" then value else nil
end

local function readTable(source: any, key: string): any
	if type(source) ~= "table" then
		return nil
	end
	local value = (source :: { [string]: any })[key]
	return if type(value) == "table" then value else nil
end

local function money(value: number?): string
	return if value == nil then EMPTY else Format.formatNumber(value)
end

local function dieVoidText(die: any): string
	local faces = readTable(die, "Faces")
	if faces == nil then
		return EMPTY
	end
	local mass: { number } = {}
	for _, face in ipairs(faces :: { any }) do
		local m = readNumber(face, "Mass")
		if m == nil then
			return EMPTY
		end
		table.insert(mass, m)
	end
	if #mass < 2 then
		return EMPTY
	end
	local ok, p = pcall(ForgeMath.voidProbability, mass)
	if not ok or type(p) ~= "number" or not ForgeMath.isFinite(p) then
		return EMPTY
	end
	return string.format("%.1f%%", p * 100)
end

-- Renders from the last StateSync and from nothing else. Every figure shown is
-- a server fact; a field the snapshot does not carry renders as a dash rather
-- than as a zero, because a zero here would be a claim about the player's
-- account that no authority made.
local function renderStatistics(): ()
	local state = latestState

	local note = statNote
	if note ~= nil then
		if state == nil then
			note.Text = "Waiting for the first server snapshot."
		else
			-- Said plainly rather than left as a suspicious gap: lifetime rolls,
			-- highest single roll and ascension count are real profile fields,
			-- but the StateSync contract does not carry them, so this surface
			-- genuinely cannot show them yet.
			note.Text = "Lifetime totals are not in the state snapshot yet."
		end
	end

	local slots = readNumber(state, "dieSlots")
	local dice = readTable(state, "dice")
	if slots == nil and type(dice) == "table" then
		slots = #(dice :: { any })
	end

	local values = {
		"CASH      " .. money(readNumber(state, "cash")),
		"GEMS      " .. money(readNumber(state, "gems")),
		"DIAMONDS  " .. money(readNumber(state, "diamonds")),
		"STREAK    " .. (if readNumber(state, "streak") == nil
			then EMPTY else string.format("%d", readNumber(state, "streak") :: number)),
		"DIE SLOTS " .. (if slots == nil then EMPTY else string.format("%d", slots)),
	}

	for index, row in ipairs(statRows) do
		row.Text = values[index] or ""
	end

	-- Die rows are pooled to MAX_DIE_ROWS and toggled, never created per render.
	for index, row in ipairs(dieRows) do
		local die = if type(dice) == "table" then (dice :: { any })[index] else nil
		if die == nil then
			row.Visible = false
		else
			row.Visible = true
			row.Text = string.format("DIE %d  %s  MASS %s  VOID %s",
				index,
				readString(die, "Shape") or EMPTY,
				money(readNumber(die, "MassBudget")),
				dieVoidText(die))
		end
	end
end

--------------------------------------------------------------------------------
-- Settings surface
--------------------------------------------------------------------------------

type ToggleDef = {
	key: string,
	label: string,
	get: () -> boolean,
	set: (boolean) -> (),
}

local TOGGLES: { ToggleDef } = {
	{
		key = "particles", label = "PARTICLES",
		get = function() return settings.particles end,
		set = function(v) settings.particles = v end,
	},
	{
		key = "motionBlur", label = "MOTION BLUR",
		get = function() return settings.motionBlur end,
		set = function(v) settings.motionBlur = v end,
	},
	{
		key = "sfx", label = "SOUND FX",
		get = function() return settings.sfx end,
		set = function(v) settings.sfx = v end,
	},
	{
		key = "music", label = "MUSIC",
		get = function() return settings.music end,
		set = function(v) settings.music = v end,
	},
}

local function renderSettings(): ()
	for _, def in ipairs(TOGGLES) do
		local button = settingsButtons[def.key]
		if button ~= nil then
			local on = def.get()
			button.Text = def.label .. "   " .. (if on then "ON" else "OFF")
			button.TextColor3 = if on then UITheme.Colors.Positive else UITheme.Colors.TextDim
		end
	end
end

--------------------------------------------------------------------------------
-- Entry behaviour
--------------------------------------------------------------------------------

local function entryIsActionable(entry: Entry): boolean
	if entry.status == "Live" then
		return true
	end
	if entry.status == "NeedsSurface" then
		local key = entry.surface
		return key ~= nil and openers[key] ~= nil
	end
	return false
end

local function activateEntry(entry: Entry): ()
	if entry.status == "Pending" then
		notify(entry.label .. " -- " .. entry.note)
		cue("UiRefused")
		return
	end

	if entry.status == "NeedsSurface" then
		local key = entry.surface
		local opener = if key ~= nil then openers[key] else nil
		if opener == nil then
			notify(entry.label .. " -- " .. entry.note)
			cue("UiRefused")
			return
		end
		-- Yield the screen first. This module does not know what the opener
		-- puts up, only that it will be at the same layer.
		closeOverlay()
		cue("UiClick")
		opener(nil)
		return
	end

	-- Live: owned here.
	cue("UiClick")
	if openSurfaceId == entry.id then
		closeOverlay()
		return
	end

	if entry.id == "Statistics" then
		local body = statsBody
		if body ~= nil then
			renderStatistics()
			showOverlay(entry.id, "STATISTICS", body)
		end
	elseif entry.id == "Settings" then
		local body = settingsBody
		if body ~= nil then
			renderSettings()
			showOverlay(entry.id, "SETTINGS", body)
		end
	end
end

-- Re-evaluates every entry's appearance against its current status. Cheap, and
-- called only on wiring changes -- there is no per-frame work in this module.
function MenuPanel.refresh(): ()
	for _, entry in ipairs(ENTRIES) do
		local button = entryButtons[entry.id]
		if button ~= nil then
			local actionable = entryIsActionable(entry)
			UITheme.setEnabled(button, actionable)
			if entry.status == "Pending" then
				button.Text = entry.label .. "\n(SOON)"
			else
				button.Text = entry.label
			end
		end
	end
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

local function buildSidebar(root: Instance, side: string, x: number): ()
	local bar = UITheme.panel(UDim2.fromScale(0.14, 0.68), UDim2.fromScale(x, 0.16))
	bar.Name = side .. "Sidebar"
	bar.Parent = root

	local slot = 0
	for _, entry in ipairs(ENTRIES) do
		if entry.side ~= side then
			continue
		end
		slot += 1
		if slot > SLOTS_PER_SIDE then
			-- A hard stop rather than an overflow that renders off the panel.
			-- Reaching this means an entry was added without a slot for it, and
			-- silently clipping it would be the dead-button failure in reverse.
			warn(string.format("[MenuPanel] '%s' has no slot on the %s sidebar", entry.id, side))
			break
		end

		local y = 0.02 + (slot - 1) * 0.19
		local button = UITheme.button(entry.label, UDim2.fromScale(0.90, 0.17), UDim2.fromScale(0.05, y))
		button.Name = entry.id
		button.TextWrapped = true
		button.Parent = bar
		button.Activated:Connect(function()
			activateEntry(entry)
		end)
		entryButtons[entry.id] = button
	end
end

local function buildStatsBody(parent: Instance): Frame
	local body = Instance.new("Frame")
	body.Name = "StatisticsBody"
	body.Size = UDim2.fromScale(0.92, 0.78)
	body.Position = UDim2.fromScale(0.04, 0.14)
	body.BackgroundTransparency = 1
	body.Visible = false
	body.Parent = parent

	local rowHeight = 1 / (STAT_ROWS + MAX_DIE_ROWS + 1)

	for index = 1, STAT_ROWS do
		local row = addLabel(body, "", UDim2.fromScale(1, rowHeight * 0.9),
			UDim2.fromScale(0, rowHeight * (index - 1)), UITheme.Colors.TextPrimary)
		table.insert(statRows, row)
	end

	for index = 1, MAX_DIE_ROWS do
		local row = addLabel(body, "", UDim2.fromScale(1, rowHeight * 0.9),
			UDim2.fromScale(0, rowHeight * (STAT_ROWS + index - 1)), UITheme.Colors.TextGold)
		row.Visible = false
		table.insert(dieRows, row)
	end

	statNote = addLabel(body, "", UDim2.fromScale(1, rowHeight * 0.9),
		UDim2.fromScale(0, rowHeight * (STAT_ROWS + MAX_DIE_ROWS)), UITheme.Colors.TextDim)

	return body
end

local function buildSettingsBody(parent: Instance): Frame
	local body = Instance.new("Frame")
	body.Name = "SettingsBody"
	body.Size = UDim2.fromScale(0.92, 0.78)
	body.Position = UDim2.fromScale(0.04, 0.14)
	body.BackgroundTransparency = 1
	body.Visible = false
	body.Parent = parent

	local rowCount = #TOGGLES + 2
	local rowHeight = 1 / rowCount

	for index, def in ipairs(TOGGLES) do
		local button = UITheme.button(def.label, UDim2.fromScale(1, rowHeight * 0.82),
			UDim2.fromScale(0, rowHeight * (index - 1)))
		button.Name = def.key
		button.Parent = body
		button.Activated:Connect(function()
			def.set(not def.get())
			renderSettings()
			-- The click cue is played AFTER the toggle is applied, so turning
			-- sound effects off does not play one on its way out.
			cue("UiClick")
			broadcastSettings()
		end)
		settingsButtons[def.key] = button
	end

	-- FR-13.4 pairs Codes with Settings. RedeemCode has a remote name and a
	-- NetClient wrapper but no server handler and no code catalog, so it is a
	-- row that states its own absence rather than a text box that swallows
	-- whatever the player types.
	local codes = UITheme.button("PROMO CODES\n(SOON)", UDim2.fromScale(1, rowHeight * 0.82),
		UDim2.fromScale(0, rowHeight * #TOGGLES))
	codes.Name = "PromoCodes"
	codes.TextWrapped = true
	codes.Parent = body
	UITheme.setEnabled(codes, false)
	codes.Activated:Connect(function()
		notify("PROMO CODES -- " .. BLOCK5)
		cue("UiRefused")
	end)
	codesRow = codes

	settingsNote = addLabel(body, "These apply for this session; saving them needs a server update.",
		UDim2.fromScale(1, rowHeight * 0.8), UDim2.fromScale(0, rowHeight * (#TOGGLES + 1)),
		UITheme.Colors.TextDim)

	return body
end

local function buildOverlay(root: Instance): ()
	local panel = UITheme.panel(UDim2.fromScale(0.70, 0.64), UDim2.fromScale(0.15, 0.18), true)
	panel.Name = "OverlayPanel"
	panel.Parent = root
	overlayPanel = panel

	overlayTitle = addLabel(panel, "", UDim2.fromScale(0.7, 0.09), UDim2.fromScale(0.04, 0.025),
		UITheme.Colors.TextGold)

	local close = UITheme.button("X", UDim2.fromScale(0.10, 0.09), UDim2.fromScale(0.86, 0.025))
	close.Name = "Close"
	close.Parent = panel
	close.Activated:Connect(closeOverlay)

	statsBody = buildStatsBody(panel)
	settingsBody = buildSettingsBody(panel)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MenuPanel.init(client: Net): ()
	if sidebarGui ~= nil then
		return
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		error("[MenuPanel] no LocalPlayer", 2)
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local bars = Instance.new("ScreenGui")
	bars.Name = "DiceForgeMenu"
	bars.ResetOnSpawn = false
	bars.DisplayOrder = UITheme.Layer.Sidebar
	bars.IgnoreGuiInset = false
	bars.Parent = playerGui
	sidebarGui = bars

	buildSidebar(bars, "Left", 0.005)
	buildSidebar(bars, "Right", 0.855)

	noticeLabel = addLabel(bars, "", UDim2.fromScale(0.60, 0.035), UDim2.fromScale(0.20, 0.805),
		UITheme.Colors.TextDim, true)
	local notice = noticeLabel
	if notice ~= nil then
		notice.Visible = false
	end

	-- A SECOND ScreenGui, not a child frame. The overlay must sit at
	-- UITheme.Layer.Panel alongside ForgePanel while the sidebars stay at
	-- Layer.Sidebar beneath it; one ScreenGui can hold only one DisplayOrder.
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "DiceForgeMenuOverlay"
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = UITheme.Layer.Panel
	overlay.IgnoreGuiInset = false
	overlay.Enabled = false
	overlay.Parent = playerGui
	overlayGui = overlay

	buildOverlay(overlay)

	MenuPanel.refresh()
	renderSettings()
	renderStatistics()

	table.insert(connections, client.onStateSync(function(state: any)
		latestState = state
		if openSurfaceId == "Statistics" then
			renderStatistics()
		end
	end))

	-- Pushes the starting settings so AudioDirector and any early subscriber
	-- begin in agreement with what the settings surface shows.
	broadcastSettings()
end

function MenuPanel.shutdown(): ()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}

	local bars = sidebarGui
	if bars ~= nil then
		bars:Destroy()
	end
	sidebarGui = nil

	local overlay = overlayGui
	if overlay ~= nil then
		overlay:Destroy()
	end
	overlayGui = nil

	overlayPanel = nil
	overlayTitle = nil
	noticeLabel = nil
	statsBody = nil
	settingsBody = nil
	statNote = nil
	settingsNote = nil
	codesRow = nil
	entryButtons = {}
	settingsButtons = {}
	statRows = {}
	dieRows = {}
	latestState = nil
	openSurfaceId = nil
end

return MenuPanel
