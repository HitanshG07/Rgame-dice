--!strict
-- UT-16 — Settings (FR-13.6)
--
-- WHY THIS SUITE EXISTS. Player settings are declared in three places that must
-- agree and have no mechanical reason to: `SettingsCatalog` (what the client
-- draws and what the server allowlists), the `PlayerProfile` template (what a
-- new profile contains and what `_reconcile` backfills), and `StateSyncService`
-- (what reaches the client).
--
-- A key present in one and absent from another does not error anywhere. It
-- presents as a switch that will not stay flipped: the client offers it, the
-- server refuses the write, the snapshot comes back with the old value, and the
-- knob slides back. Nothing logs, nothing throws, and the player is left
-- thinking the game is broken -- which it is, quietly.
--
-- So the agreement is asserted in BOTH DIRECTIONS. A one-directional check
-- ("every catalog key is in the template") passes happily while the template
-- carries a key nothing can ever set.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsCatalog = require(Shared:WaitForChild("SettingsCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Server = ServerScriptService:WaitForChild("Server")
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local RemoteGateway = require(Server:WaitForChild("RemoteGateway"))
local RateLimiter = require(Server:WaitForChild("RateLimiter"))

local n = 0
local function check(cond: boolean, msg: string): string?
	n += 1
	if not cond then
		return msg
	end
	return nil
end

local function run(): (boolean, string?, number)
	n = 0
	local e: any = nil

	----------------------------------------------------------------------------
	-- The catalog itself
	----------------------------------------------------------------------------

	local order = SettingsCatalog.getOrder()
	e = e or check(#order > 0, "SettingsCatalog declares no settings at all")

	local defaults = SettingsCatalog.defaults()

	-- ORDER COVERS THE CATALOG, both ways. A key missing from ORDER is a row the
	-- panel never draws -- present in the profile, settable by a crafted call,
	-- and invisible to the player.
	local inOrder: { [string]: boolean } = {}
	for _, key in ipairs(order) do
		inOrder[key] = true
		e = e or check(SettingsCatalog.get(key) ~= nil, string.format(
			"ORDER names '%s', which is not a declared setting", key))
	end
	for key in pairs(defaults) do
		e = e or check(inOrder[key] == true, string.format(
			"setting '%s' is declared but absent from ORDER -- the panel will never"
			.. " draw a row for it", key))
	end

	-- Every entry carries what the panel needs to render an honest row.
	for _, def in ipairs(SettingsCatalog.ordered()) do
		e = e or check(type(def.label) == "string" and #def.label > 0,
			string.format("setting '%s' has no label", def.key))
		e = e or check(type(def.blurb) == "string" and #def.blurb > 0,
			string.format("setting '%s' has no blurb -- a bare toggle does not say"
				.. " what it does", def.key))
		e = e or check(type(def.default) == "boolean",
			string.format("setting '%s' has a non-boolean default", def.key))
	end

	-- `defaults()` must hand back a COPY. Returning the internal table would let
	-- any caller rewrite the defaults for every player on the server.
	local firstKey = order[1]
	if firstKey ~= nil then
		local a = SettingsCatalog.defaults()
		a[firstKey] = not a[firstKey]
		local b = SettingsCatalog.defaults()
		e = e or check(b[firstKey] == (SettingsCatalog.get(firstKey) :: any).default,
			"SettingsCatalog.defaults() must return a fresh table -- a caller"
			.. " mutated the shared one")
	end
	local orderA = SettingsCatalog.getOrder()
	table.insert(orderA, "INJECTED")
	e = e or check(#SettingsCatalog.getOrder() == #order,
		"SettingsCatalog.getOrder() must return a fresh table")

	----------------------------------------------------------------------------
	-- THE ALLOWLIST. This is what stands between a client string and a profile
	-- write, so it is exercised with the shapes an exploiting client sends.
	----------------------------------------------------------------------------

	for _, key in ipairs(order) do
		e = e or check(SettingsCatalog.isSetting(key) == true, string.format(
			"isSetting must accept the declared key '%s'", key))
	end

	e = e or check(SettingsCatalog.isSetting("Cash") == false,
		"isSetting must reject an undeclared key")
	e = e or check(SettingsCatalog.isSetting("__index") == false,
		"isSetting must reject a metatable key -- rawget is what makes this hold")
	e = e or check(SettingsCatalog.isSetting("") == false,
		"isSetting must reject an empty string")
	e = e or check(SettingsCatalog.isSetting(nil) == false,
		"isSetting must reject nil without throwing")
	e = e or check(SettingsCatalog.isSetting(42) == false,
		"isSetting must reject a number without throwing")
	e = e or check(SettingsCatalog.isSetting({}) == false,
		"isSetting must reject a table without throwing")
	e = e or check(SettingsCatalog.isSetting(true) == false,
		"isSetting must reject a boolean without throwing")

	----------------------------------------------------------------------------
	-- Snapshot reading falls back to the default, never to nil
	----------------------------------------------------------------------------

	if firstKey ~= nil then
		local def = (SettingsCatalog.get(firstKey) :: any).default
		e = e or check(SettingsCatalog.read(nil, firstKey) == def,
			"read() must fall back to the default when the snapshot is absent")
		e = e or check(SettingsCatalog.read({}, firstKey) == def,
			"read() must fall back to the default when the key is absent")
		e = e or check(SettingsCatalog.read({ [firstKey] = "true" }, firstKey) == def,
			"read() must ignore a non-boolean and fall back -- a string must never"
			.. " render as an enabled toggle")
		e = e or check(SettingsCatalog.read({ [firstKey] = false }, firstKey) == false,
			"read() must return a real stored false")
		e = e or check(SettingsCatalog.read({ [firstKey] = true }, firstKey) == true,
			"read() must return a real stored true")
	end

	----------------------------------------------------------------------------
	-- THE PROFILE TEMPLATE AGREES, IN BOTH DIRECTIONS
	----------------------------------------------------------------------------

	local template = PlayerProfile.getTemplate()
	local stored = (template :: any).Settings
	e = e or check(type(stored) == "table",
		"PlayerProfile template has no Settings table")

	if type(stored) == "table" then
		for key, default in pairs(defaults) do
			e = e or check(stored[key] ~= nil, string.format(
				"SettingsCatalog declares '%s' and the profile template does not --"
				.. " a returning player reads nil for it", key))
			if stored[key] ~= nil then
				e = e or check(stored[key] == default, string.format(
					"setting '%s' defaults to %s in the catalog and %s in the profile"
					.. " template -- the panel and a fresh profile disagree",
					key, tostring(default), tostring(stored[key])))
			end
		end
		for key in pairs(stored) do
			e = e or check(defaults[key] ~= nil, string.format(
				"the profile template stores '%s' and SettingsCatalog does not"
				.. " declare it -- nothing can ever set it and no panel shows it", key))
		end
	end

	----------------------------------------------------------------------------
	-- THE REMOTE IS REACHABLE END TO END
	----------------------------------------------------------------------------
	--
	-- Registration is not enough on its own -- eight handlers were registered and
	-- dead for a whole build (UT-15). What is checked here is everything the call
	-- has to pass through before the handler is even entered.

	e = e or check(Remotes.Fn.SetSetting == "SetSetting",
		"SetSetting must be declared in the remote registry, or the client's"
		.. " WaitForChild never resolves")

	-- ARITY, and the exact value. `bind()` refuses to wire an undeclared remote at
	-- startup, which fails closed -- but a WRONG arity fails at the first press
	-- with a generic refusal, which is much harder to trace.
	e = e or check(RemoteGateway.arityFor("SetSetting") == 2, string.format(
		"SetSetting must declare arity 2 (key, enabled), got %s",
		tostring(RemoteGateway.arityFor("SetSetting"))))

	-- A DEDICATED BUCKET. Without one the remote silently inherits DEFAULT_LIMIT
	-- (2/sec sustained), and a player flicking four switches in a row would be
	-- rate-limited mid-way through -- two saving and two appearing to fail.
	local limit = RateLimiter.limitFor("SetSetting")
	e = e or check(limit.burst >= #order, string.format(
		"SetSetting's burst (%d) must cover flipping every switch (%d) in one go",
		limit.burst, #order))

	if e ~= nil then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-16 Settings", run = run }
