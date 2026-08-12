--!strict
-- SettingsCatalog.luau
-- The one declaration of what a player setting IS (SRS FR-13.6).
--
-- WHY THIS MODULE EXISTS RATHER THAN TWO LISTS.
--
-- A settings panel needs the same set of keys in three places at once: the
-- client has to draw a row per setting, the server has to allowlist an incoming
-- key before writing it, and the profile template has to declare a default so no
-- read path hits nil. Written three times, they drift -- and the drift is
-- SILENT in the worst direction: a key the client offers but the server does not
-- allowlist looks to the player like a toggle that quietly refuses to save.
--
-- So the set is declared ONCE here and every side asks this module (ledger
-- L-025, the executable-contract pattern; L-026, both sides execute the same
-- code rather than agreeing to match).
--
-- `Settings.test.luau` asserts the PlayerProfile template and this catalog agree
-- in BOTH directions, so adding a key to one and forgetting the other fails the
-- suite instead of failing a player.
--
-- NOTHING ECONOMIC LIVES HERE. These are presentation preferences only; no
-- setting may gate a reward, a rate, or a price. A "setting" that changed income
-- would be an economic value the client could name, which NFR-5 forbids.

local SettingsCatalog = {}

export type Setting = {
	key: string,
	label: string,
	-- Shown under the label. Says what the toggle DOES, in the player's terms.
	blurb: string,
	default: boolean,
	-- WHAT THIS SETTING NEEDS IN ORDER TO DO ANYTHING, or nil if it is
	-- self-contained.
	--
	-- Music and Sound Effects control `AudioDirector`, whose nine asset ids are
	-- all `DUMMY_ID_*` placeholders -- no Sound instance is ever created, so both
	-- toggles saved a preference that reached nothing audible. A switch that
	-- controls nothing is mock UI, and the panel must not present one as live.
	--
	-- Declared here rather than hardcoded in the panel so that when the operator
	-- supplies real audio ids, the rows come alive on their own with no client
	-- change: the panel asks whether the capability is present and renders
	-- accordingly.
	requires: string?,
}

local SETTINGS: { [string]: Setting } = {
	-- BOTH VISUAL SETTINGS ARE LIVE TODAY and need no assets. They are built from
	-- TextLabels, not from ParticleEmitters or a BlurEffect: sparks are four "+"
	-- labels thrown outward, and the "motion blur" is a lagging translucent copy
	-- of the payout number -- a deliberate stand-in, because a real blur pass is
	-- not available to a ScreenGui. The blurbs below describe what the player
	-- actually sees, not what the names might suggest.
	Particles = {
		key = "Particles",
		label = "Particles",
		blurb = "Little sparks that burst from a payout when a die pays out.",
		default = true,
	},
	MotionBlur = {
		key = "MotionBlur",
		label = "Motion Trail",
		blurb = "A soft trailing copy behind the payout number as it rises.",
		default = true,
	},
	Music = {
		key = "Music",
		label = "Music",
		blurb = "Background ambience.",
		default = true,
		requires = "audio",
	},
	SFX = {
		key = "SFX",
		label = "Sound Effects",
		blurb = "Roll, land, streak and interface sounds.",
		default = true,
		requires = "audio",
	},
}

-- Player-facing explanation for a capability that is not present. Keyed by the
-- same string `requires` uses, so adding a capability means adding one line.
local MISSING: { [string]: string } = {
	audio = "No sounds are installed yet",
}

function SettingsCatalog.missingReason(capability: string): string
	return MISSING[capability] or "Not available yet"
end

-- Display order. Fixed rather than derived from `pairs`, because pairs order is
-- unspecified and a settings list that reshuffles between sessions is a bug the
-- player notices and nobody can reproduce.
local ORDER: { string } = { "Particles", "MotionBlur", "Music", "SFX" }

function SettingsCatalog.getOrder(): { string }
	return table.clone(ORDER)
end

function SettingsCatalog.get(key: string): Setting?
	return SETTINGS[key]
end

-- THE ALLOWLIST CHECK, as a function rather than as a table the caller indexes.
--
-- `rawget` and the explicit type guard together are what make this safe against
-- a client sending a non-string, a metatable key, or `__index` (threats T-5,
-- Matrix E-1/E-2). The server calls this; it never indexes a live table with a
-- client-supplied string.
function SettingsCatalog.isSetting(key: unknown): boolean
	if type(key) ~= "string" then
		return false
	end
	return rawget(SETTINGS, key :: string) ~= nil
end

-- A fresh table each call. Handing out the internal one would let any caller
-- mutate the defaults for the whole server.
function SettingsCatalog.defaults(): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for key, def in pairs(SETTINGS) do
		out[key] = def.default
	end
	return out
end

function SettingsCatalog.ordered(): { Setting }
	local out: { Setting } = {}
	for _, key in ipairs(ORDER) do
		local def = SETTINGS[key]
		if def ~= nil then
			table.insert(out, def)
		end
	end
	return out
end

-- Reads a setting out of an untrusted-shape snapshot table, falling back to the
-- catalog default. The client renders through this so a snapshot that is missing
-- a key shows the default rather than an unlit toggle that lies about state.
function SettingsCatalog.read(settings: any, key: string): boolean
	local def = SETTINGS[key]
	local fallback = if def ~= nil then def.default else true
	if type(settings) ~= "table" then
		return fallback
	end
	local value = settings[key]
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

return SettingsCatalog
