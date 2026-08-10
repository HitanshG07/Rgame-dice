--!strict
-- AudioDirector.luau
-- Every sound the client makes, behind one door.
--
-- WHY A DIRECTOR RATHER THAN Sound INSTANCES SCATTERED THROUGH THE VIEWS.
-- Three things have to be true at once: the settings toggles must actually
-- silence audio (SRS FR-13.6), no per-frame code may allocate a Sound (NFR-1),
-- and a missing or wrong asset id must never take a surface down. All three are
-- properties of the whole audio layer, not of any one call site, so they are
-- enforced in one file and the views only ever name a cue.
--
-- THE ASSET IDS DO NOT EXIST YET. Every entry in ASSET_IDS below is a
-- `DUMMY_ID_*` placeholder, mirroring SRS FR-12.6's rule for products: an
-- unresolved asset FAILS CLOSED. `isPlayable` accepts only a well-formed
-- `rbxassetid://<digits>` string, so a placeholder never reaches a Sound
-- instance, no Sound is created for it, and `play` for that cue is a silent
-- no-op. Nothing warns at runtime and nothing errors. Dropping the real ids in
-- later is a one-line-per-cue edit to ASSET_IDS and no other change anywhere:
-- the pooling, gating and volume mixing are already in place waiting for them.
--
-- POOLING (NFR-1). Every Sound this module will ever use is created once, at
-- init, and reused for the whole session; `play` allocates nothing and only
-- indexes tables it already holds. A cue owns a small fixed VOICE POOL rather
-- than a single instance, cycled round-robin, because the two kinds of cue in
-- this game want opposite retrigger behaviour:
--   * UI cues (clicks, refusals, panels) get ONE voice. Re-pressing a button
--     should cut the previous click off -- two overlapping clicks read as a
--     double-press that did not happen. Restart is the correct behaviour and
--     is what a one-voice pool does.
--   * Roll cues get two or three. An auto-roll at the FR-2.4 ceiling of five
--     per second retriggers RollLand every 200ms, and with one voice every
--     land sound longer than 200ms would be cut mid-attack -- a stuttering
--     200ms loop rather than a dice game. Three voices let a land tail of up
--     to ~600ms finish while the next roll starts over the top of it.
-- The pools are deliberately small. Overlapping copies of one sample sum, so
-- the ceiling on simultaneous voices is also the ceiling on how loud a cue can
-- get; three is enough to cover the tail and few enough that CUE_VOLUME below
-- still holds the mix under the player's own music.
--
-- CONTAINER (lazy). The `DiceForgeAudio` folder is created on first real Sound,
-- not at init. In today's all-placeholder state no Sound is built, so no folder
-- is published either and a session leaves nothing behind in SoundService.
--
-- WHAT THIS MODULE DOES NOT DO. It holds no game state, and CUES are pushed to
-- it by the surface that caused them -- never pulled from a remote -- so the
-- audio layer can never disagree with what is on screen about whether something
-- happened.
--
-- IT DOES SUBSCRIBE TO ONE THING (added 2026-08-11): StateSync, for the two
-- settings booleans, and nothing else off that snapshot is read.
--
-- WHY THAT CHANGED. This module used to ignore its NetClient argument entirely,
-- on the reasoning that MenuPanel would push settings in. MenuPanel was replaced
-- by V7MenuPanel, which never made that call, so `applySettings` had exactly one
-- caller left -- `init`, passing the module's own defaults back to itself. The
-- Music and SFX toggles were therefore INERT: the value saved to the profile and
-- replicated correctly and reached nothing that made a sound.
--
-- Subscribing directly is what removes the class of failure rather than the
-- instance: a bridge through a third module is a wire that can be forgotten
-- again the next time the panel layer is rewritten, and forgetting it is silent.
-- FeedbackFX already reads its own two settings off the snapshot for the same
-- reason; this makes the audio half symmetrical with it.

local SoundService = game:GetService("SoundService")

local AudioDirector = {}

--------------------------------------------------------------------------------
-- Public vocabulary
--------------------------------------------------------------------------------

-- A closed union rather than a free string, so a typo at a call site is a type
-- error instead of a cue that silently never plays.
export type Cue =
	"RollPress" | "RollLand" | "VoidHit" | "StreakUp"
	| "UiClick" | "UiRefused" | "PanelOpen" | "PanelClose"

-- Deliberately narrower than the full settings record owned by MenuPanel. This
-- module needs two booleans and has no business knowing about particles or
-- motion blur, so the structural type it accepts asks for exactly two booleans.
export type AudioSettings = {
	sfx: boolean,
	music: boolean,
}

--------------------------------------------------------------------------------
-- Asset table -- the single drop-in point for real ids
--------------------------------------------------------------------------------

local MUSIC_KEY = "Music"

local ASSET_IDS: { [string]: string } = {
	RollPress  = "DUMMY_ID_SFX_ROLL_PRESS",
	RollLand   = "DUMMY_ID_SFX_ROLL_LAND",
	VoidHit    = "DUMMY_ID_SFX_VOID_HIT",
	StreakUp   = "DUMMY_ID_SFX_STREAK_UP",
	UiClick    = "DUMMY_ID_SFX_UI_CLICK",
	UiRefused  = "DUMMY_ID_SFX_UI_REFUSED",
	PanelOpen  = "DUMMY_ID_SFX_PANEL_OPEN",
	PanelClose = "DUMMY_ID_SFX_PANEL_CLOSE",
	[MUSIC_KEY] = "DUMMY_ID_MUSIC_ARENA_LOOP",
}

-- Relative mix, set here rather than at the call sites so the balance between
-- cues is readable in one place. Kept conservative: a game that auto-rolls five
-- times a second must not be louder than the player's own music.
local CUE_VOLUME: { [string]: number } = {
	RollPress  = 0.35,
	RollLand   = 0.45,
	VoidHit    = 0.40,
	StreakUp   = 0.40,
	UiClick    = 0.25,
	UiRefused  = 0.30,
	PanelOpen  = 0.25,
	PanelClose = 0.25,
	[MUSIC_KEY] = 0.18,
}

local DEFAULT_VOLUME = 0.3

-- Voices per cue. See the POOLING note in the header for why UI cues get one
-- and roll cues get more. A cue absent from this table gets DEFAULT_VOICES.
local CUE_VOICES: { [string]: number } = {
	RollPress  = 2,
	RollLand   = 3,
	VoidHit    = 2,
	StreakUp   = 2,
	UiClick    = 1,
	UiRefused  = 1,
	PanelOpen  = 1,
	PanelClose = 1,
}

local DEFAULT_VOICES = 1
local MAX_VOICES = 4

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local initialised = false
local container: Folder? = nil
-- One entry per cue that resolved to at least one real Sound. A cue whose id is
-- still a placeholder is simply absent -- that absence IS the fail-closed path.
local voices: { [string]: { Sound } } = {}
-- Round-robin cursor per cue, always a valid index into that cue's pool.
local cursor: { [string]: number } = {}
local musicSound: Sound? = nil
-- Held so `shutdown` can release it. A Studio play-test that re-inits without
-- disconnecting would stack a second handler on every replay.
local settingsConnection: RBXScriptConnection? = nil

-- Audio is ON until the first snapshot says otherwise. These defaults match
-- SettingsCatalog's, so the window before the first StateSync cannot disagree
-- with what the server holds for a new player.
local settings: AudioSettings = {
	sfx = true,
	music = true,
}

--------------------------------------------------------------------------------
-- Fail-closed id resolution
--------------------------------------------------------------------------------

-- The whole safety property of this file. Only a literal, well-formed asset
-- reference is accepted; a placeholder, an empty string, a bare number, or a
-- URL to somewhere else all resolve to "not playable" and are dropped.
local function isPlayable(id: string?): boolean
	if type(id) ~= "string" then
		return false
	end
	return string.match(id, "^rbxassetid://%d+$") ~= nil
end

local function volumeFor(key: string): number
	local v = CUE_VOLUME[key]
	return if type(v) == "number" then v else DEFAULT_VOLUME
end

-- Bounded on both sides deliberately. A hand-edit to CUE_VOICES that reads 0,
-- a fraction, or something absurd must not be able to produce an empty pool or
-- a hundred Sound instances; it lands in a sane range instead. Written as plain
-- comparisons rather than math.clamp, which ERRORS when min > max, and ordered
-- so that a value no comparison accepts -- NaN included -- falls to the default
-- rather than out of the bottom of the function.
local function voicesFor(key: string): number
	local v = CUE_VOICES[key]
	if type(v) ~= "number" then
		return DEFAULT_VOICES
	end
	local n = math.floor(v)
	if n >= MAX_VOICES then
		return MAX_VOICES
	end
	if n >= 1 then
		return n
	end
	return DEFAULT_VOICES
end

-- Created on first real Sound rather than at init, so an all-placeholder
-- session publishes nothing to SoundService at all.
local function ensureContainer(): Folder
	local existing = container
	if existing ~= nil then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "DiceForgeAudio"
	folder.Parent = SoundService
	container = folder
	return folder
end

-- Returns nil for an unresolved id. A nil here is the fail-closed path, not an
-- error path: the caller checks and does nothing. Note the id test happens
-- BEFORE ensureContainer, so an unplayable id creates no folder either.
local function buildSound(key: string, index: number, total: number, looped: boolean): Sound?
	local id = ASSET_IDS[key]
	if not isPlayable(id) then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = if total > 1 then string.format("%s_%d", key, index) else key
	sound.SoundId = id
	sound.Volume = volumeFor(key)
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = ensureContainer()
	return sound
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Plays a one-shot cue. Safe to call before `init`, after a settings change, or
-- for a cue whose asset id has not been supplied yet -- all three do nothing.
-- Also safe for a name that is not a Cue at all: the callers reach this through
-- an erased `any` boundary, and an unknown key simply misses the pool table.
function AudioDirector.play(cue: Cue): ()
	if not initialised or not settings.sfx then
		return
	end
	local pool = voices[cue]
	if pool == nil then
		return
	end
	local count = #pool
	if count == 0 then
		return
	end

	-- Advance the cursor whether or not the chosen voice turns out to be
	-- usable, so one destroyed instance cannot pin every later play onto it.
	local index = cursor[cue] or 1
	if index < 1 or index > count then
		index = 1
	end
	cursor[cue] = if index >= count then 1 else index + 1

	local sound = pool[index]
	if sound == nil or sound.Parent == nil then
		return
	end
	-- Restart THIS voice; the other voices in the pool keep ringing. See the
	-- pooling note in the header for why the pool sizes differ per cue.
	sound.TimePosition = 0
	sound:Play()
end

-- Applies the player's settings. The live caller is this module's own StateSync
-- subscription; it stays public because a surface that already holds a snapshot
-- can push one in without a second round trip. Accepts anything shaped like
-- AudioSettings, so a caller can pass a narrowed view of a larger record.
--
-- The parameter is GUARDED rather than trusted. The only caller reaches this
-- across an erased-type boundary (`local Audio: any`) and does not pcall, so a
-- future caller passing nil would raise here, abort MenuPanel's init, and be
-- converted by ClientBootstrap into a fatal boot abort -- the audio layer
-- taking down every visual surface, which is the exact outcome that loading
-- this module LAST exists to prevent. Throw-freedom has to be a property of
-- this module, not of its callers, so a non-table is ignored, never indexed.
function AudioDirector.applySettings(incoming: AudioSettings?): ()
	if type(incoming) ~= "table" then
		return
	end

	settings = {
		sfx = incoming.sfx == true,
		music = incoming.music == true,
	}

	local music = musicSound
	if music == nil or music.Parent == nil then
		return
	end

	if settings.music then
		if not music.IsPlaying then
			music:Play()
		end
	elseif music.IsPlaying then
		-- Stop, not pause. A looping ambience resumed mid-phrase sounds like a
		-- glitch, and there is nothing to preserve a position for.
		music:Stop()
	end
end

-- Exposed so a caller can render an honest state rather than guessing why a cue
-- produced no sound. Nothing in the shipped surfaces depends on it; it exists
-- because "silent because muted" and "silent because unresolved" are different
-- facts and the difference should be answerable.
function AudioDirector.isCueAvailable(cue: Cue): boolean
	local pool = voices[cue]
	return pool ~= nil and #pool > 0
end

function AudioDirector.init(net: any): ()
	if initialised then
		return
	end

	for key in pairs(ASSET_IDS) do
		if key ~= MUSIC_KEY then
			local total = voicesFor(key)
			local pool: { Sound } = {}
			for index = 1, total do
				local sound = buildSound(key, index, total, false)
				if sound ~= nil then
					pool[#pool + 1] = sound
				end
			end
			if #pool > 0 then
				voices[key] = pool
				cursor[key] = 1
			end
		end
	end

	musicSound = buildSound(MUSIC_KEY, 1, 1, true)

	initialised = true

	-- Re-apply whatever settings are current. If a snapshot already arrived
	-- before the sounds existed, this is what makes it take effect; if it has
	-- not, this starts the music under the default.
	AudioDirector.applySettings(settings)

	-- THE SETTINGS SUBSCRIPTION. Two booleans off the snapshot and nothing else.
	--
	-- Guarded rather than assumed: `init` is called with whatever ClientBootstrap
	-- holds, and a module that hard-required a live NetClient here would turn a
	-- missing subscription into a fatal boot abort -- the audio layer taking down
	-- every visual surface, which is the exact outcome loading this module LAST
	-- exists to prevent.
	if type(net) == "table" and type(net.onStateSync) == "function" then
		settingsConnection = net.onStateSync(function(state: any)
			if type(state) ~= "table" then
				return
			end
			local incoming = state.settings
			if type(incoming) ~= "table" then
				return
			end
			-- ABSENT MEANS ON for audio, which is the opposite default from a
			-- security check and correct here: a snapshot that omits the key must
			-- not silence a player who never turned anything off.
			AudioDirector.applySettings({
				music = incoming.Music ~= false,
				sfx = incoming.SFX ~= false,
			})
		end)
	end
end

-- Tears the audio layer down. Not used during normal play -- the client lives
-- for the session -- but a module that creates instances outside its own GUI
-- tree should be able to remove them again, or a Studio play-test leaves them
-- behind in SoundService.
function AudioDirector.shutdown(): ()
	local conn = settingsConnection
	if conn ~= nil then
		conn:Disconnect()
	end
	settingsConnection = nil

	local folder = container
	if folder ~= nil then
		folder:Destroy()
	end
	container = nil
	musicSound = nil
	voices = {}
	cursor = {}
	initialised = false
end

return AudioDirector
