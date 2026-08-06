--!strict
-- RunAll.server.luau
-- Test harness. A Script (not a ModuleScript) so it executes on Play Solo.
-- Contract: TEST_PLAN.md §1.
--
-- The rule that matters most here: a module that FAILS TO LOAD is reported as a
-- FAILURE, never skipped. The previous project shipped a suite whose require
-- path was wrong; it silently ran zero tests and nobody noticed for weeks.

local ServerScriptService = game:GetService("ServerScriptService")

type Suite = { name: string, run: () -> (boolean, string?, number) }

local root = ServerScriptService:WaitForChild("Tests")

local passed, failed, totalAsserts = 0, 0, 0
local failures: { string } = {}

local function record(name: string, ok: boolean, message: string?, asserts: number)
	totalAsserts += asserts
	if ok then
		passed += 1
		print(string.format("[PASS] %s (%d assertions)", name, asserts))
	else
		failed += 1
		local line = string.format("[FAIL] %s: %s", name, message or "no message")
		print(line)
		table.insert(failures, line)
	end
end

print("=== DICE FORGE TEST SUITE ===")

local modules: { ModuleScript } = {}
for _, child in ipairs(root:GetDescendants()) do
	if child:IsA("ModuleScript") and string.match(child.Name, "%.test$") then
		table.insert(modules, child)
	end
end
table.sort(modules, function(a: ModuleScript, b: ModuleScript)
	return a.Name < b.Name
end)

if #modules == 0 then
	-- Zero discovered suites is itself a failure: it means the harness found
	-- nothing, which is indistinguishable from everything passing.
	print("[FAIL] discovery: no *.test ModuleScripts found under ServerScriptService.Tests")
	failed += 1
end

for _, module in ipairs(modules) do
	local loaded, result = pcall(require, module)
	if not loaded then
		-- A require error is a FAILURE, not a skip.
		record(module.Name, false, "module failed to load: " .. tostring(result), 0)
		continue
	end

	local suite = result :: Suite
	if type(suite) ~= "table" or type(suite.run) ~= "function" then
		record(module.Name, false, "module did not return { name, run }", 0)
		continue
	end

	local ranOk, a, b, c = pcall(suite.run)
	if not ranOk then
		record(suite.name or module.Name, false, "run() errored: " .. tostring(a), 0)
	else
		record(suite.name or module.Name, a :: boolean, b :: string?, (c :: number?) or 0)
	end
end

if failed > 0 then
	print("--- FAILURES ---")
	for _, line in ipairs(failures) do
		print("  " .. line)
	end
end

print(string.format("total assertions: %d", totalAsserts))
print(string.format("=== SUITE COMPLETE: %d passed, %d failed ===", passed, failed))
