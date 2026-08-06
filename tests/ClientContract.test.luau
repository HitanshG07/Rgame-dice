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
