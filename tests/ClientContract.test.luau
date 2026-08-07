--!strict
-- UT-13 — Client contract (TEST_PLAN.md §4, added 2026-08-07)
--
-- WHY THIS SUITE EXISTS. `ForgeService` shipped a call to a function that has
-- never existed, and UT-12's own header records the reason it survived: *a
-- service module that no suite requires is a module whose symbols are never
-- resolved.* `NetClient` and `ClientBootstrap` were then built with EXACTLY that
-- property -- audited, statically clean, hand-tested over the wire, and required
-- by no suite at all. Requiring the module here is most of the value: it proves
-- the module loads and that every symbol the client depends on actually exists.
--
-- WHAT LIVES HERE vs IN P-3. A first draft of this suite read `NetClient.Source`
-- to assert structural rules. That FAILS at runtime -- `Source` needs
-- PluginOrOpenCloud capability, which a game script does not have. The rules
-- were not wrong, they were in the wrong place: anything that must be proven
-- about the TEXT belongs in procedure P-3, which greps the repository from disk.
-- What belongs here is everything provable from the loaded module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local RemoteGateway = require(ServerScriptService:WaitForChild("Server"):WaitForChild("RemoteGateway"))

local n = 0
local function check(cond: boolean, msg: string): string?
	n += 1
	if not cond then
		return msg
	end
	return nil
end

-- "Roll" -> "roll", "SetAutoRoll" -> "setAutoRoll"
local function wrapperName(remote: string): string
	return string.lower(string.sub(remote, 1, 1)) .. string.sub(remote, 2)
end

local function run(): (boolean, string?, number)
	n = 0
	local e: any = nil

	----------------------------------------------------------------------------
	-- The client tree is where the Rojo project says it is
	----------------------------------------------------------------------------

	local scripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local clientRoot = scripts and scripts:FindFirstChild("Client")
	e = e or check(clientRoot ~= nil,
		"StarterPlayerScripts.Client is missing -- the Rojo mapping is broken and NOTHING client-side runs")
	if not clientRoot then
		return false, e, n
	end

	local netModule = clientRoot:FindFirstChild("NetClient")
	local bootModule = clientRoot:FindFirstChild("ClientBootstrap")
	e = e or check(netModule ~= nil and netModule:IsA("ModuleScript"),
		"NetClient must exist as a ModuleScript")
	e = e or check(bootModule ~= nil and bootModule:IsA("LocalScript"),
		"ClientBootstrap must be a LocalScript, or it never executes")
	if not netModule then
		return false, e, n
	end

	----------------------------------------------------------------------------
	-- EVERY VIEW MODULE LOADS AND HONOURS THE BOOTSTRAP CONTRACT
	----------------------------------------------------------------------------

	-- THIS BLOCK EXISTS BECAUSE THE SAME GAP HAS NOW BITTEN THREE TIMES.
	--   1. ForgeService shipped calling a function that has never existed. No
	--      suite required the module, so no symbol in it was ever resolved.
	--   2. UT-13 was written to close that -- and covered NetClient and
	--      ClientBootstrap only.
	--   3. Seven view modules then landed with no suite requiring any of them.
	--      Six were rejected on audit; two of the defects (a nil-index on an
	--      absent settings source, a call into a shared function whose signature
	--      had changed) are exactly what a require would have surfaced.
	--
	-- The rule, stated so the fourth instance does not happen: A MODULE THAT NO
	-- SUITE REQUIRES IS A MODULE WHOSE SYMBOLS ARE NEVER RESOLVED. Requiring it
	-- is most of the value; asserting its shape is the rest.
	--
	-- These are CLIENT modules being required from a SERVER-side suite. That is
	-- deliberate and it is a real check: anything a view module does at MODULE
	-- SCOPE must be safe without a LocalPlayer, because module scope runs before
	-- init. Work needing a player belongs in init(), which this suite never calls.
	local VIEW_MODULES: { string } = {
		"UITheme",
		"ArenaView",
		"DiceRenderer",
		"FeedbackFX",
		"HUD",
		"ForgePanel",
		"MenuPanel",
		"AudioDirector",
	}

	local failedToLoad: { string } = {}
	local missingInit: { string } = {}
	local notATable: { string } = {}
	local loadedModules: { [string]: any } = {}

	for _, name in ipairs(VIEW_MODULES) do
		local instance = clientRoot:FindFirstChild(name)
		if instance == nil then
			table.insert(failedToLoad, name .. " (absent from the client tree)")
			continue
		end
		local ok, result = pcall(require, instance)
		if not ok then
			table.insert(failedToLoad, string.format("%s (%s)", name, tostring(result)))
			continue
		end
		loadedModules[name] = result
		if type(result) ~= "table" then
			table.insert(notATable, name)
			continue
		end
		-- UITheme is data plus builders, not a lifecycle module; every other view
		-- module is constructed by ClientBootstrap and must expose init.
		if name ~= "UITheme" and type(result.init) ~= "function" then
			table.insert(missingInit, name)
		end
	end

	e = e or check(#failedToLoad == 0, string.format(
		"view modules that FAILED TO LOAD: %s", table.concat(failedToLoad, " | ")))
	e = e or check(#notATable == 0, string.format(
		"view modules not returning a table: %s", table.concat(notATable, ", ")))
	e = e or check(#missingInit == 0, string.format(
		"view modules with no init(): ClientBootstrap would skip them silently -- %s",
		table.concat(missingInit, ", ")))

	----------------------------------------------------------------------------
	-- Teardown symmetry
	----------------------------------------------------------------------------

	-- A module that acquires a connection, a ScreenGui or a pool and offers no
	-- release path cannot be unloaded or re-hosted. Three of the seven shipped
	-- without one. Not every module needs shutdown -- but one that connects to a
	-- signal does, and the audit found the asymmetry only by reading each file.
	local noShutdown: { string } = {}
	for _, name in ipairs({ "ArenaView", "DiceRenderer", "FeedbackFX", "HUD", "ForgePanel", "MenuPanel", "AudioDirector" }) do
		local m = loadedModules[name]
		if type(m) == "table" and type((m :: any).shutdown) ~= "function" then
			table.insert(noShutdown, name)
		end
	end
	e = e or check(#noShutdown == 0, string.format(
		"view modules with no shutdown(): every acquisition needs a release path -- %s",
		table.concat(noShutdown, ", ")))

	----------------------------------------------------------------------------
	-- The theme is the single source of visual truth
	----------------------------------------------------------------------------

	local theme = loadedModules["UITheme"]
	if type(theme) == "table" then
		local t = theme :: any
		e = e or check(type(t.Colors) == "table", "UITheme must expose a Colors table")
		e = e or check(type(t.panel) == "function", "UITheme must expose the panel builder")
		e = e or check(type(t.label) == "function", "UITheme must expose the label builder")
		e = e or check(type(t.button) == "function", "UITheme must expose the button builder")
		e = e or check(t.BorderThickness == 1, "FR-13.1 specifies a 1-pixel border")

		-- Every element in the catalog needs a tint, or a face renders untinted
		-- with no error to notice. This is the check that keeps the palette and
		-- the catalog from drifting apart.
		local ElementCatalog = require(Shared:WaitForChild("ElementCatalog"))
		local untinted: { string } = {}
		for id in pairs(ElementCatalog.all()) do
			if t.ElementColors[id] == nil then
				table.insert(untinted, id)
			end
		end
		e = e or check(#untinted == 0, string.format(
			"elements with no UITheme tint: %s", table.concat(untinted, ", ")))
	end

	----------------------------------------------------------------------------
	-- IT LOADS. The single most valuable assertion in this file.
	----------------------------------------------------------------------------

	local loaded, NetClient = pcall(require, netModule)
	e = e or check(loaded, string.format("NetClient failed to LOAD: %s", tostring(NetClient)))
	if not loaded then
		return false, e, n
	end
	e = e or check(type(NetClient) == "table", "NetClient must return a table")

	----------------------------------------------------------------------------
	-- One wrapper per inbound remote, one subscription per outbound event
	----------------------------------------------------------------------------

	-- A remote with no wrapper is a feature the client cannot reach. A wrapper
	-- naming a remote that does not exist is a call that fails at runtime. Both
	-- are silent until someone presses the button.
	local missingWrapper: { string } = {}
	for _, remote in pairs(Remotes.Fn) do
		if type((NetClient :: any)[wrapperName(remote)]) ~= "function" then
			table.insert(missingWrapper, remote)
		end
	end
	e = e or check(#missingWrapper == 0, string.format(
		"remotes with no NetClient wrapper: %s", table.concat(missingWrapper, ", ")))

	local missingSub: { string } = {}
	for _, event in pairs(Remotes.Ev) do
		if type((NetClient :: any)["on" .. event]) ~= "function" then
			table.insert(missingSub, event)
		end
	end
	e = e or check(#missingSub == 0, string.format(
		"server->client events with no NetClient subscription: %s", table.concat(missingSub, ", ")))

	----------------------------------------------------------------------------
	-- No generic escape hatch
	----------------------------------------------------------------------------

	-- A generic sender is how a price reaches the wire six months from now: the
	-- narrow wrappers stop being the only way through, and NFR-5 becomes a
	-- convention rather than a shape.
	for _, banned in ipairs({ "invoke", "fire", "send", "call", "request" }) do
		e = e or check((NetClient :: any)[banned] == nil, string.format(
			"NetClient exposes a generic '%s' -- the narrow wrappers are the boundary", banned))
	end

	----------------------------------------------------------------------------
	-- Arity agreement between the two ends of the wire
	----------------------------------------------------------------------------

	-- The server refuses a call whose argument count differs from ARITY. If the
	-- client and that table ever disagree, every call of that kind is rejected
	-- and nothing says why. Every remote must be declared on both sides.
	local undeclared: { string } = {}
	for _, remote in pairs(Remotes.Fn) do
		if RemoteGateway.arityFor(remote) == nil then
			table.insert(undeclared, remote)
		end
	end
	e = e or check(#undeclared == 0, string.format(
		"remotes the server has no declared arity for: %s", table.concat(undeclared, ", ")))

	----------------------------------------------------------------------------
	-- The throttle is a courtesy, and says so through its API
	----------------------------------------------------------------------------

	e = e or check(type((NetClient :: any).readyIn) == "function",
		"NetClient must expose readyIn so the UI can grey a button rather than fire and be refused")
	local ready = (NetClient :: any).readyIn("Roll")
	e = e or check(type(ready) == "number" and ready >= 0,
		"readyIn must return a non-negative number of seconds")
	e = e or check((NetClient :: any).readyIn("NotARealRemote") == 0,
		"readyIn on an unknown remote must report ready, not error")

	-- The real enforcement is server-side and must still be wired.
	e = e or check(RemoteGateway.arityFor("Roll") == 0,
		"the server arity gate is the actual control and must remain in place")

	----------------------------------------------------------------------------
	-- awaitReady is client-only and fails closed off-client
	----------------------------------------------------------------------------

	-- Called from the server it must ERROR rather than silently report ready --
	-- a false ready would let a bootstrap build surfaces over remotes that were
	-- never resolved.
	local okAwait = pcall((NetClient :: any).awaitReady)
	e = e or check(not okAwait,
		"NetClient.awaitReady must refuse to run off-client rather than returning a false ready")

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-13 ClientContract", run = run }
