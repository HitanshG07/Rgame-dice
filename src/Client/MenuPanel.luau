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
-- WHY THE PENDING LIST IS AS LONG AS IT IS. Two censuses, not one, because a
-- live entry needs a handler for what it SENDS and a producer for what it
-- READS, and an audit that checks only the first will bless a surface that
-- renders nothing.
--
--   HANDLER CENSUS (RemoteGateway.register call sites, 2026-08-07): the server
--   registers exactly four handlers -- Roll, Forge, SetElement and SetShape.
--   AddDieSlot, BuyUpgrade, Ascend, ClaimQuest, GetLeaderboard and RedeemCode
--   have remote NAMES in the registry and NetClient wrappers, but no handler
--   behind them. A wrapper is not a system. Every entry depending on one of
--   those is Pending.
--
--   EMITTER CENSUS (FireClient call sites, re-run 2026-08-08): StateSync now
--   has a producer. `Server/StateSyncService.luau` fires it on join and after
--   every successful mutation, and `StateSyncService.buildSnapshot` is the
--   authority on the field names this file reads. STATS is Live on the strength
--   of that emitter, not on the strength of the event merely being declared --
--   which is precisely the mistake the first cut of this file made, marking
--   STATS live against an event nothing on the server had ever fired.
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
--
-- HISTORICAL NOTE, kept because it explains a decision. ForgePanel used to keep
-- a permanent FORGE tab in this module's own left-sidebar rectangle, one layer
-- above it, which covered a button and swallowed its taps. This file worked
-- around it by skipping a reserved band, and reported that the workaround was
-- fragile because it hard-coded another module's geometry. The resolution was
-- to DELETE the tab -- it was a duplicate entry point to a surface this sidebar
-- already opens -- so the band, the gap and the guard are all gone and the
-- pitch is even again. Nothing draws above this module in the sidebar rect.
-- Orchestrator-level decision about who owns x < 0.15. Reported, not assumed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))

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

-- The inbound counterpart to an opener. `setSurfaceOpener` lets this module get
-- OUT of another surface's way; this lets it ask the other surfaces to get out
-- of ITS way. See `setSurfaceCloser`.
export type SurfaceCloser = () -> ()

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
-- for these to persist per player. Persisting them needs BOTH a profile field
-- and a remote handler that writes it, and only the first half exists.
--
-- The 2026-08-08 census is specific about which half. `PlayerProfile` does have
-- a `Settings` table, and `StateSyncService.buildSnapshot` does ship it down as
-- `settings` -- so the READ path is complete. There is no matching handler: the
-- server registers Roll, Forge, SetElement and SetShape, and none of them writes
-- settings. A toggle therefore has nowhere to go, and the stored value can only
-- ever be the profile template's default.
--
-- This module consequently does NOT adopt the incoming `settings` field, and
-- that omission is deliberate rather than an unfinished read. Adopting it would
-- look like persistence while being incapable of it: every snapshot arrives
-- carrying the template defaults, so any snapshot pushed after any unrelated
-- mutation -- a roll, a forge -- would silently revert whatever the player had
-- just toggled. A switch that flips itself back is worse than one that is
-- honestly session-scoped. The toggles are fully functional for the session and
-- reset on rejoin; the settings surface says exactly that on screen.
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

	-- SNAPSHOT THE LISTENERS BEFORE CALLING ANY OF THEM. A listener is arbitrary
	-- foreign code and it is entitled to subscribe or unsubscribe while it runs
	-- -- the arena bridge this API exists to serve does exactly that, registering
	-- a child module's listener the first time it hears about a settings change.
	-- Adding or removing a key during a `pairs` traversal is undefined in Luau:
	-- the new listener may be visited in this same broadcast, may be skipped, or
	-- an existing one may be visited twice. Copying first makes the set of
	-- recipients exactly the set that existed when the broadcast began, which is
	-- the only definition that is stable to reason about. A listener that
	-- subscribes mid-broadcast hears the NEXT change, not this one.
	local recipients: { (Settings) -> () } = {}
	for _, listener in pairs(settingsListeners) do
		table.insert(recipients, listener)
	end

	for _, listener in ipairs(recipients) do
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
local surfaceCloser: SurfaceCloser? = nil

-- Forward-declared. Wiring an opener has to re-render the sidebar, but the
-- renderer needs the entry table declared further down, so the two are split:
-- the name is reserved here and the body is assigned below the declarations.
local refreshEntries: () -> ()

-- Wiring point for the Orchestrator. Passing nil unwires, which returns the
-- entry to its unavailable rendering rather than leaving a live-looking button
-- with a dead callback.
function MenuPanel.setSurfaceOpener(key: SurfaceKey, opener: SurfaceOpener?): ()
	openers[key] = opener
	refreshEntries()
end

-- THE OTHER HALF OF THE Z-ORDER CONTRACT, and the reason it has to exist.
--
-- This module's overlay ScreenGui and ForgePanel's root both sit at
-- UITheme.Layer.Panel (30) with geometry that fully overlaps. Roblox does not
-- define which of two equal DisplayOrders draws on top, so a tie is not "the
-- later one wins" -- it is unspecified, and it may resolve differently between
-- sessions. Neither surface may unilaterally raise its own layer, because
-- UITheme.Layer exists precisely so that two panels cannot both decide they are
-- on top.
--
-- The only sound resolution is that exactly one Panel-layer surface is ever
-- enabled at a time, which means the tie is never evaluated. Outbound, this
-- module already yields: `activateEntry` calls `closeOverlay` before invoking a
-- foreign opener. Inbound was missing -- nothing told the other surface to
-- yield when THIS module took the screen, so opening STATS on top of an open
-- forge produced the undefined case.
--
-- `closer` is invoked from `showOverlay`, immediately before this module's
-- overlay is enabled. The Orchestrator wires it to `ForgePanel.setVisible(false)`.
-- It is deliberately NOT a direct call to ForgePanel: a view module that
-- imports a sibling view module is no longer disjoint from it, and the whole
-- point of the opener/closer pair is that the Orchestrator owns the sequencing
-- and the views stay ignorant of each other. Passing nil unwires.
function MenuPanel.setSurfaceCloser(closer: SurfaceCloser?): ()
	surfaceCloser = closer
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

--------------------------------------------------------------------------------
-- Sidebar slot geometry
--------------------------------------------------------------------------------

local SIDEBAR_TOP = 0.16
local SIDEBAR_HEIGHT = 0.68

-- Slot origins as a FRACTION OF THE SIDEBAR PANEL, top edge, with the button
-- height below. Even pitch, five slots per side, no reserved gap.
--
-- In absolute screen scale these resolve to:
--   slot 1  0.170 - 0.265      slot 4  0.605 - 0.700
--   slot 2  0.295 - 0.390      slot 5  0.730 - 0.825
--   slot 3  0.480 - 0.575
-- Slot 2 ends 0.005 above the band and slot 3 begins 0.005 below it. Both
-- sidebars use the same table: the right sidebar has no tab over it, but a
-- deliberate symmetry reads as a design and a one-sided shuffle reads as a bug.
-- Even pitch across the sidebar. This was previously a hand-derived table
-- that skipped a band reserved for ForgePanel's edge tab; that tab has been
-- REMOVED (it was a duplicate entry point to a surface this sidebar already
-- opens), so the band, the gap and the build-time occlusion guard all went
-- with it. Nothing above this module claims screen space in the sidebar's
-- rectangle any more.
local SLOT_Y: { number } = { 0.015, 0.185, 0.355, 0.525, 0.695 }
local SLOT_HEIGHT = 0.140

local SLOTS_PER_SIDE = #SLOT_Y

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------

local MAX_DIE_ROWS = 7   -- 5 base slots plus the +2 gamepass (FR-12.1)

-- cash, gems, diamonds, streak, die slots, lifetime cash, highest roll, total
-- rolls, ascensions. Every one of the nine is a named field of
-- StateSyncService.buildSnapshot -- see STAT_FIELDS.
local STAT_ROWS = 9

local sidebarGui: ScreenGui? = nil
local noticeGui: ScreenGui? = nil
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
--
-- WHERE IT LIVES, AND WHY THAT IS NOT COSMETIC. The notice is the entire
-- mechanism that makes a dead entry honest: a Pending or unwired button does
-- nothing except explain itself through this label. If the explanation is
-- covered, the button is indistinguishable from the silently-dead buttons this
-- whole file exists to avoid -- the refusal machinery would itself be the thing
-- that failed silently.
--
-- It used to sit on the sidebar ScreenGui at Layer.Sidebar (20), y 0.805-0.840,
-- underneath an opaque overlay panel that spans y 0.18-0.820 at Layer.Panel
-- (30). That covered the top 43% of it. Worse, the PROMO CODES refusal is
-- reachable ONLY from inside the settings surface, so the one message that can
-- only ever fire with the overlay open was the one guaranteed to be clipped.
--
-- The fix is a layer, not a nudge: the notice gets its own ScreenGui at
-- Layer.Toast (40), above every panel in the game. Moving it down the screen
-- instead would only have traded this collision for one with the HUD bottom
-- bar, and would still lose to any future full-height surface. A transient
-- message that must outrank whatever it is explaining is exactly what the Toast
-- layer is for.
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

	-- Make the other Panel-layer surfaces yield BEFORE enabling ours, so the two
	-- are never simultaneously enabled and the undefined equal-DisplayOrder tie
	-- is never evaluated. Foreign code, so a throw here must not leave this
	-- module half-open: the overlay comes up either way and the failure is
	-- reported rather than swallowed.
	local closer = surfaceCloser
	if closer ~= nil then
		local ok, err = pcall(closer)
		if not ok then
			warn("[MenuPanel] surface closer errored: " .. tostring(err))
		end
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

-- A COUNT, not a quantity. `readNumber` admits any finite number, because a
-- mass or a probability legitimately is one; a streak, a slot count, a roll
-- total and an ascension count are not, and formatting a non-integral value
-- with "%d" does not round it -- it RAISES. That throw used to happen inside
-- `renderStatistics`, which `activateEntry` calls BEFORE `showOverlay`, so a
-- fractional streak arriving over the wire turned the STATS button into a
-- button that consumed the tap, played its click, and opened nothing: the exact
-- silently-dead button this file was written to prevent, produced by the
-- rendering of the honesty surface itself.
--
-- So integrality is a read-time predicate, not a formatting concern. A value
-- that is not a whole number is not a valid count, and a field that fails this
-- renders as a dash -- the same treatment as a field the snapshot never sent,
-- because in both cases no authority has told us what the number is.
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
	local shapeId = readString(die, "Shape")
	if shapeId == nil then
		return EMPTY
	end
	local ok, p = pcall(ForgeMath.voidProbability, mass, DiceCatalog.getMassFloor(shapeId))
	if not ok or type(p) ~= "number" or not ForgeMath.isFinite(p) then
		return EMPTY
	end
	return string.format("%.1f%%", p * 100)
end

-- THE FIELD MAP, checked against StateSyncService.buildSnapshot on 2026-08-08.
-- Every `field` below is a key that function literally writes: cash, gems,
-- diamonds, streak, dieSlots, lifetimeCash, highestRoll, totalRolls,
-- ascensions. Kept as one table so the correspondence is a list somebody can
-- diff against the server, not nine string literals scattered through a
-- renderer. `counted` marks the fields that must be whole numbers.
type StatField = {
	label: string,
	field: string,
	counted: boolean,
}

local STAT_FIELDS: { StatField } = {
	{ label = "CASH",       field = "cash",         counted = false },
	{ label = "GEMS",       field = "gems",         counted = false },
	{ label = "DIAMONDS",   field = "diamonds",     counted = false },
	{ label = "STREAK",     field = "streak",       counted = true  },
	{ label = "DIE SLOTS",  field = "dieSlots",     counted = true  },
	{ label = "LIFETIME",   field = "lifetimeCash", counted = false },
	{ label = "BEST ROLL",  field = "highestRoll",  counted = false },
	{ label = "ROLLS",      field = "totalRolls",   counted = true  },
	{ label = "ASCENSIONS", field = "ascensions",   counted = true  },
}

-- Monospace type (UITheme.Font is Enum.Font.Code), so a fixed-width label
-- column actually lines the values up into one.
local function statLine(label: string, value: string): string
	return string.format("%-11s%s", label, value)
end

-- Renders from the last StateSync and from nothing else. Every figure shown is
-- a server fact; a field the snapshot does not carry renders as a dash rather
-- than as a zero, because a zero here would be a claim about the player's
-- account that no authority made.
local function renderStatistics(): ()
	local state = latestState

	-- THE PRE-FIRST-PACKET WINDOW IS STILL REAL AND STILL NEEDS SAYING. The
	-- server pushes a snapshot on join, but "on join" is not "before this panel
	-- can be opened" -- the sidebar is built at init and the player can press
	-- STATS during the gap. With no snapshot every row is a dash, and nine
	-- dashes with no caption look like a broken panel rather than a waiting one.
	-- Once a snapshot has landed the caption goes away entirely: there is no
	-- longer a shortfall to disclose, because every field this surface shows is
	-- now carried by the payload.
	local note = statNote
	if note ~= nil then
		note.Text = if state == nil then "Waiting for the first server snapshot." else ""
	end

	local dice = readTable(state, "dice")

	for index, spec in ipairs(STAT_FIELDS) do
		local row = statRows[index]
		if row == nil then
			continue
		end
		local text: string
		if spec.counted then
			-- DIE SLOTS is here rather than derived, and that is the whole point
			-- of the field. It is a CAPACITY, granted by the profile and the +2
			-- gamepass (FR-12.1); the dice array is what the player has actually
			-- forged INTO that capacity. They are different quantities, and the
			-- earlier `#dice` fallback conflated them -- a player holding the
			-- gamepass with one die forged was shown "DIE SLOTS 1", understating
			-- their purchase. The fallback is deleted rather than repaired,
			-- because `#` on a table that arrived over a remote is undefined
			-- anyway: a sparse array has no defined length in Luau, and a
			-- serialised array with one hole can report any of several answers.
			-- If the server did not send the capacity, this surface does not
			-- know the capacity, and it says so with a dash.
			local value = readInteger(state, spec.field)
			text = if value == nil then EMPTY else string.format("%d", value)
		else
			text = money(readNumber(state, spec.field))
		end
		row.Text = statLine(spec.label, text)
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
function refreshEntries(): ()
	for _, entry in ipairs(ENTRIES) do
		local button = entryButtons[entry.id]
		if button ~= nil then
			local actionable = entryIsActionable(entry)
			UITheme.setEnabled(button, actionable)

			-- A MARKER FOR EVERY UNAVAILABLE ENTRY, NOT JUST THE PENDING ONES.
			-- Pending entries carried "(SOON)" while an unwired NeedsSurface
			-- entry was distinguished by nothing but TextDim instead of
			-- TextGold. Colour alone is too weak to carry that meaning: the two
			-- greys differ by a shade the player has no reference for, it is
			-- invisible to a colour-blind player and to anyone on a washed-out
			-- phone screen, and a dimmed button with no caption is exactly what
			-- a dead button looks like. FORGE and SHAPE were both in this state,
			-- and FR-13.8 calls the forge the core mechanic -- the single entry
			-- least able to afford being mistaken for broken.
			--
			-- The two markers say different things on purpose. "(SOON)" is a
			-- promise about the game: the system does not exist yet. "(UNWIRED)"
			-- is a report about this build: the surface exists but the
			-- Orchestrator has not connected it, which is a wiring defect and
			-- should look like one to whoever sees it.
			if entry.status == "Pending" then
				button.Text = entry.label .. "\n(SOON)"
			elseif not actionable then
				button.Text = entry.label .. "\n(UNWIRED)"
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

-- Converts a slot origin expressed as a fraction of the sidebar panel into
-- absolute screen scale. Retained because the layout comments quote absolute
-- figures and this is what derives them.
local function slotAbsoluteTop(slotFraction: number): number
	return SIDEBAR_TOP + SIDEBAR_HEIGHT * slotFraction
end

-- Checked at build time rather than trusted. SLOT_Y was derived by hand against
-- constants declared a hundred lines apart; if anyone edits either end of that
-- derivation -- retunes the slot pitch, or updates RESERVED_BAND after
-- ForgePanel moves its tab -- the numbers stop agreeing and nothing on screen
-- announces it, because an occluded button looks precisely like a button. The
-- symptom this guards against was permanent and silent from init, so the guard
-- runs at init too.
-- The occlusion guard that lived here checked sidebar slots against
-- ForgePanel's edge tab. The tab is gone, so there is nothing above this
-- module in the sidebar's rectangle and the check has no subject. Deleted
-- rather than left passing vacuously -- a guard that can never fire reads
-- like protection and provides none.
local function warnIfSlotIsOccluded(_entryId: string, _slot: number): ()
end

local function buildSidebar(root: Instance, side: string, x: number): ()
	local bar = UITheme.panel(UDim2.fromScale(0.14, SIDEBAR_HEIGHT), UDim2.fromScale(x, SIDEBAR_TOP))
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

		warnIfSlotIsOccluded(side, slot, entry.id)

		local button = UITheme.button(entry.label, UDim2.fromScale(0.90, SLOT_HEIGHT),
			UDim2.fromScale(0.05, SLOT_Y[slot]))
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

	addLabel(body, "These apply for this session; saving them needs a server update.",
		UDim2.fromScale(1, rowHeight * 0.8), UDim2.fromScale(0, rowHeight * (#TOGGLES + 1)),
		UITheme.Colors.TextDim)

	return body
end

local function buildOverlay(root: Instance): ()
	local panel = UITheme.panel(UDim2.fromScale(0.70, 0.64), UDim2.fromScale(0.15, 0.18), true)
	panel.Name = "OverlayPanel"
	panel.Parent = root

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

	-- A THIRD ScreenGui, for the reason given at `notify`: the refusal notice has
	-- to outrank every panel, including this module's own overlay, and a
	-- DisplayOrder belongs to a ScreenGui rather than to a frame inside one.
	local notices = Instance.new("ScreenGui")
	notices.Name = "DiceForgeMenuNotice"
	notices.ResetOnSpawn = false
	notices.DisplayOrder = UITheme.Layer.Toast
	notices.IgnoreGuiInset = false
	notices.Parent = playerGui
	noticeGui = notices

	noticeLabel = addLabel(notices, "", UDim2.fromScale(0.60, 0.035), UDim2.fromScale(0.20, 0.805),
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
	overlay.DisplayOrder = UITheme.Layer.Overlay
	overlay.IgnoreGuiInset = false
	overlay.Enabled = false
	overlay.Parent = playerGui
	overlayGui = overlay

	buildOverlay(overlay)

	refreshEntries()
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

	local notices = noticeGui
	if notices ~= nil then
		notices:Destroy()
	end
	noticeGui = nil

	local overlay = overlayGui
	if overlay ~= nil then
		overlay:Destroy()
	end
	overlayGui = nil

	overlayTitle = nil
	noticeLabel = nil
	statsBody = nil
	settingsBody = nil
	statNote = nil
	entryButtons = {}
	settingsButtons = {}
	statRows = {}
	dieRows = {}
	latestState = nil
	openSurfaceId = nil

	-- THE REGISTRY IS PART OF THE TEARDOWN, and leaving it out was a leak with
	-- teeth. `settingsListeners` survived shutdown holding closures over
	-- destroyed instances; the next `init` ends with `broadcastSettings`, which
	-- would call every one of them. Each stale closure then either errors into
	-- the pcall -- a warn per listener per broadcast, forever -- or, worse,
	-- succeeds against an instance detached from the DataModel, keeping the
	-- whole destroyed GUI tree alive and applying settings to a surface no one
	-- can see. The id counter resets with it: nothing outside this module holds
	-- an id, and the only reference to one is the unsubscribe closure returned
	-- by `onSettingsChanged`, which is itself dead once shutdown has run. An
	-- unsubscribe called after shutdown clears a key that no longer exists,
	-- which is a no-op, not a collision.
	settingsListeners = {}
	nextListenerId = 1

	-- `openers` and `surfaceCloser` are deliberately NOT cleared. They hold
	-- functions belonging to other modules, which shutting this one down does
	-- not destroy, and the Orchestrator wires them once at startup rather than
	-- per init. Clearing them would silently un-wire FORGE and SHAPE across an
	-- init/shutdown cycle. This asymmetry with `settingsListeners` is the point:
	-- that registry holds closures over instances THIS module just destroyed.
end

return MenuPanel
