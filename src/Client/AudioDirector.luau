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
-- POOLING (NFR-1). Exactly one Sound instance exists per cue for the whole
-- session, created once at init and reused. Re-triggering a cue that is already
-- playing restarts it rather than layering a second voice -- for a dice game
-- whose loudest cue is a button press that is the correct behaviour anyway, and
-- it means a 5-per-second auto-roll allocates nothing at all.
--
-- WHAT THIS MODULE DOES NOT DO. It subscribes to no remote and holds no game
-- state. Cues are pushed to it by the surface that caused them, so the audio
-- layer can never disagree with what is on screen about whether something
-- happened. `init` therefore ignores its NetClient argument, deliberately.

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

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local initialised = false
local container: Folder? = nil
local sounds: { [string]: Sound } = {}
local musicSound: Sound? = nil

-- Audio is ON until MenuPanel tells us otherwise. MenuPanel pushes the real
-- values during its own init; because both toggles default true here and there,
-- the two cannot disagree during the window between the two inits.
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

-- Returns nil for an unresolved id. A nil here is the fail-closed path, not an
-- error path: the caller checks and does nothing.
local function buildSound(key: string, parent: Folder, looped: boolean): Sound?
	local id = ASSET_IDS[key]
	if not isPlayable(id) then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = id
	sound.Volume = volumeFor(key)
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = parent
	return sound
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Plays a one-shot cue. Safe to call before `init`, after a settings change, or
-- for a cue whose asset id has not been supplied yet -- all three do nothing.
function AudioDirector.play(cue: Cue): ()
	if not initialised or not settings.sfx then
		return
	end
	local sound = sounds[cue]
	if sound == nil or sound.Parent == nil then
		return
	end
	-- Restart rather than layer. See the pooling note in the header.
	sound.TimePosition = 0
	sound:Play()
end

-- Applies the player's settings. Called by MenuPanel on init and on every
-- toggle. Accepts anything shaped like AudioSettings, so MenuPanel can pass a
-- narrowed view of its own larger record without a shared type module.
function AudioDirector.applySettings(next: AudioSettings): ()
	settings = {
		sfx = next.sfx == true,
		music = next.music == true,
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
	return sounds[cue] ~= nil
end

-- `net` is unused on purpose -- see the header. The parameter exists to satisfy
-- the ClientBootstrap module contract, which calls every module as init(net).
function AudioDirector.init(_net: any): ()
	if initialised then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "DiceForgeAudio"
	folder.Parent = SoundService
	container = folder

	for key in pairs(ASSET_IDS) do
		if key ~= MUSIC_KEY then
			local sound = buildSound(key, folder, false)
			if sound ~= nil then
				sounds[key] = sound
			end
		end
	end

	musicSound = buildSound(MUSIC_KEY, folder, true)

	initialised = true

	-- Re-apply whatever settings are current. If MenuPanel already pushed a
	-- value before the sounds existed, this is what makes it take effect; if it
	-- has not, this starts the music under the default.
	AudioDirector.applySettings(settings)
end

-- Tears the audio layer down. Not used during normal play -- the client lives
-- for the session -- but a module that creates instances outside its own GUI
-- tree should be able to remove them again, or a Studio play-test leaves them
-- behind in SoundService.
function AudioDirector.shutdown(): ()
	local folder = container
	if folder ~= nil then
		folder:Destroy()
	end
	container = nil
	musicSound = nil
	sounds = {}
	initialised = false
end

return AudioDirector
