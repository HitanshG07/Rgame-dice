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
	--   4. AND AGAIN, found 2026-08-11. This list named HUD, ForgePanel and
	--      MenuPanel -- the LEGACY surfaces. ClientBootstrap has been constructing
	--      V7HUD, V7ForgePanel and V7MenuPanel for the whole of the V7 work, so
	--      the three modules the player actually touches were required by nothing,
	--      while the suite reported client coverage from three files that no
	--      longer render. A list of module names is exactly the kind of thing that
	--      keeps passing after the thing it names has been replaced.
	--
	-- The V7 modules are CONSTRUCTED (`.new`) rather than initialised (`.init`),
	-- so the lifecycle check below accepts either.
	local VIEW_MODULES: { string } = {
		"UITheme",
		"BoardView",
		"DiceRenderer",
		"FeedbackFX",
		"AudioDirector",
		"V7HUD",
		"V7ForgePanel",
		"V7MenuPanel",
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
		-- UITheme is data plus builders, not a lifecycle module. Every other view
		-- module must give ClientBootstrap a way in: `init(net)` for the modules
		-- it initialises, `new()` for the V7 surfaces it constructs. A module with
		-- neither is loaded and then never touched, silently.
		if name ~= "UITheme"
			and type(result.init) ~= "function"
			and type(result.new) ~= "function" then
			table.insert(missingInit, name)
		end
	end

	e = e or check(#failedToLoad == 0, string.format(
		"view modules that FAILED TO LOAD: %s", table.concat(failedToLoad, " | ")))
	e = e or check(#notATable == 0, string.format(
		"view modules not returning a table: %s", table.concat(notATable, ", ")))
	e = e or check(#missingInit == 0, string.format(
		"view modules with no init() or new(): ClientBootstrap would skip them "
		.. "silently -- %s", table.concat(missingInit, ", ")))

	-- ClientBootstrap.computeVoidRiskPct is local to a .client script and cannot be
	-- required here, so this pins the PREMISE of its unknown-shape guard: an
	-- unrecognised id must be detectable via getShape (the guard returns nil on it)
	-- even though getMassFloor would silently answer a default.
	local DiceCatalog = require(Shared:WaitForChild("DiceCatalog")) :: any
	e = e or check(DiceCatalog.getShape("NoSuchShape") == nil,
		"getShape must return nil for an unknown id -- the HUD void-risk guard relies on it")

	----------------------------------------------------------------------------
	-- Teardown symmetry
	----------------------------------------------------------------------------

	-- A module that acquires a connection, a ScreenGui or a pool and offers no
	-- release path cannot be unloaded or re-hosted. Three of the seven shipped
	-- without one. Not every module needs shutdown -- but one that connects to a
	-- signal does, and the audit found the asymmetry only by reading each file.
	local noShutdown: { string } = {}
	-- KNOWN GAP: V7HUD, V7ForgePanel and V7MenuPanel are NOT listed. They return
	-- controllers from `.new()` and expose no module-level shutdown(), so the V7
	-- surfaces have no teardown assertion here. The legacy HUD, ForgePanel and
	-- MenuPanel were removed from this list when those files were deleted (Phase 3);
	-- they asserted teardown on modules the player no longer sees.
	for _, name in ipairs({ "BoardView", "DiceRenderer", "FeedbackFX", "AudioDirector" }) do
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

		------------------------------------------------------------------------
		-- THE LAYOUT PRIMITIVES.
		--
		-- These exist because hand-placed scale coordinates were overlapping:
		-- the SHAPES card drew its status label from x 0.44 to 0.66 while its
		-- action button began at x 0.585, so "OWNED" printed through "USE".
		-- Panels are now built from layout containers instead, which cannot
		-- overlap by construction.
		--
		-- ASSERTED HERE BECAUSE NOTHING ELSE CAN SEE THEM. `new()` needs a
		-- LocalPlayer and this suite runs server-side, so the entire
		-- CONSTRUCTION phase of every panel is out of reach (L-036). What is
		-- reachable is whether the symbols the panels call actually exist --
		-- which is exactly the failure mode where a renamed builder takes out
		-- every overlay at once and the suite stays green.
		------------------------------------------------------------------------

		for _, fn in ipairs({ "verticalStack", "card", "listRow", "textLine",
			"paragraph", "actionButton", "statusPill", "setPill",
			"setActionEnabled", "arbitratesChildren" }) do
			e = e or check(type((t :: any)[fn]) == "function",
				string.format("UITheme must expose the %s layout primitive", fn))
		end

		------------------------------------------------------------------------
		-- THE OVERLAP RULE, exercised on synthetic containers.
		--
		-- The property that matters is "no two siblings in a card intersect",
		-- and it CANNOT be measured here: constructing a panel needs a
		-- LocalPlayer and this suite runs server-side, so there is no
		-- AbsoluteSize to compare (L-036). Asserting it anyway would be a green
		-- check for a property nobody tested, which is the trap L-051 was
		-- written about.
		--
		-- What IS checkable is the rule the panels were rebuilt to satisfy:
		-- overlap is impossible when a container arbitrates its children with a
		-- layout, and possible exactly when siblings are hand-placed. These
		-- cases pin `arbitratesChildren` against known-good and known-bad
		-- shapes, so the helper the panels rely on cannot silently invert.
		------------------------------------------------------------------------

		if type((t :: any).arbitratesChildren) == "function" then
			local arbitrates = (t :: any).arbitratesChildren

			-- KNOWN-BAD: two hand-placed siblings. This is the exact shape the
			-- shapes card had, with a status label and a button whose
			-- rectangles overlapped by 7.5% of the panel width.
			local bad = Instance.new("Frame")
			local badA = Instance.new("TextLabel")
			badA.Parent = bad
			local badB = Instance.new("TextButton")
			badB.Parent = bad
			e = e or check(arbitrates(bad) == false,
				"arbitratesChildren must REJECT two hand-placed siblings")

			-- KNOWN-GOOD: the same two children under a layout.
			local good = Instance.new("Frame")
			local layout = Instance.new("UIListLayout")
			layout.Parent = good
			local goodA = Instance.new("TextLabel")
			goodA.Parent = good
			local goodB = Instance.new("TextButton")
			goodB.Parent = good
			e = e or check(arbitrates(good) == true,
				"arbitratesChildren must ACCEPT siblings under a UIListLayout")

			-- KNOWN-GOOD: a single child needs no layout to be unambiguous.
			local single = Instance.new("Frame")
			local only = Instance.new("Frame")
			only.Parent = single
			e = e or check(arbitrates(single) == true,
				"arbitratesChildren must ACCEPT a container with one child")

			-- KNOWN-GOOD: decorations are not positioned content. A card carries
			-- a UICorner, a UIStroke and a UIPadding beside its one content
			-- frame, and counting those as siblings would flag every card.
			-- Written as named locals rather than parenthesised expressions. A
			-- statement beginning with `(` after a line ending in an identifier
			-- parses as a CALL on that identifier -- `decorated(...)` here -- and
			-- the whole file then fails to compile, taking every assertion in it
			-- with it, silently. A leading `;` prevents that, which is why two of
			-- these lines had one; the first did not, and one missing semicolon
			-- would have disabled this entire suite.
			local decorated = Instance.new("Frame")
			local body = Instance.new("Frame")
			body.Parent = decorated
			local deco1 = Instance.new("UICorner")
			deco1.Parent = decorated
			local deco2 = Instance.new("UIStroke")
			deco2.Parent = decorated
			local deco3 = Instance.new("UIPadding")
			deco3.Parent = decorated
			e = e or check(arbitrates(decorated) == true,
				"arbitratesChildren must not count UICorner/UIStroke/UIPadding as content")

			bad:Destroy()
			good:Destroy()
			single:Destroy()
			decorated:Destroy()
		else
			e = e or check(false, "UITheme must expose arbitratesChildren")
		end

		-- THE SCALE IS THE ANTI-MAGIC-NUMBER CONTROL. Every gap, radius and type
		-- size comes from here, so a panel inventing its own 0.545 has somewhere
		-- to be corrected TO.
		e = e or check(type(t.Scale) == "table", "UITheme must expose a Scale table")
		if type(t.Scale) == "table" then
			local s = t.Scale :: any
			-- 44px is the platform touch-target floor and does not scale with
			-- build tier (ui_ux_design skill S3). Asserted as a NUMBER and a
			-- MINIMUM rather than an equality, so raising it stays legal and
			-- lowering it below the accessibility floor does not.
			e = e or check(type(s.TouchTarget) == "number" and s.TouchTarget >= 44,
				"UITheme.Scale.TouchTarget must be at least the 44px touch floor")

			-- The spacing ladder must be ASCENDING, which is the property that
			-- makes it a scale rather than six unrelated numbers.
			local ladder = { s.XS, s.SM, s.MD, s.LG, s.XL, s.XXL }
			local ascending = true
			for i = 2, #ladder do
				if type(ladder[i]) ~= "number" or ladder[i] <= ladder[i - 1] then
					ascending = false
					break
				end
			end
			e = e or check(ascending,
				"UITheme.Scale spacing steps must ascend strictly (XS < SM < ... < XXL)")

			-- Likewise the type ladder, descending from title to small print. A
			-- body size at or above the heading size is a hierarchy inversion.
			e = e or check(
				type(s.TextTitle) == "number" and type(s.TextSmall) == "number"
				and s.TextTitle > s.TextHeading and s.TextHeading > s.TextBody
				and s.TextBody > s.TextSmall,
				"UITheme.Scale type sizes must descend: Title > Heading > Body > Small")
		end

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
	-- NO EMOJI IN THE INTERFACE.
	--
	-- Nine of the nine overlay titles opened with one -- a shopping trolley, a
	-- die, a trophy, an hourglass -- and the operator's verdict on the result
	-- was that it looked "as if it was made by an ai, and not a proper
	-- developer". They are also a RENDERING hazard independent of taste: an
	-- emoji is a font-dependent glyph, so it renders as colour art on one
	-- platform, monochrome line art on another, and a tofu box wherever the
	-- font lacks it. Every icon in this game is drawn geometry for that reason.
	--
	-- CHECKED ON THE SOURCE rather than on constructed instances, because the
	-- panels cannot be constructed here (no LocalPlayer). Scanning bytes catches
	-- it wherever it appears -- a title, a button caption, a status string --
	-- rather than only in the places a test thought to look.
	--
	-- READING `Source` NEEDS A CAPABILITY THIS THREAD MAY NOT HAVE. Under Play
	-- Solo the suite runs in the GAME context, where `LuaSourceContainer.Source`
	-- raises "cannot read 'Source' (lacking capability PluginOrOpenCloud)". The
	-- first version of this check read it unguarded and took the WHOLE suite from
	-- 21 passed to 20 passed / 1 errored -- a check meant to protect the UI
	-- instead destroyed the evidence for everything else in this file.
	--
	-- So the read is pcall'd and the check SKIPS where it cannot run, rather than
	-- failing. A skip is honest; an error is not, and neither is silently
	-- dropping the check. It still runs under a plugin or Open Cloud context,
	-- which is where the pre-commit sweep happens, and the same scan is
	-- reproducible from the shell against any commit.
	--
	-- TWO RANGES, because the offenders spanned both. Five were 4-byte sequences
	-- in the emoji planes (trolley, die, trophy, scroll, galaxy) and five were
	-- 3-byte symbols (gear, hourglass, high voltage) -- so a check for only the
	-- 4-byte lead would have passed a panel still headed by a gear.
	--
	-- Deliberately NOT flagged: the multiplication sign, the minus sign and the
	-- diamond suit, all used on purpose as typography. They fall outside both
	-- ranges, which is the property that makes this a usable rule rather than a
	-- ban on every non-ASCII character.
	--
	-- VALIDATED BOTH WAYS BEFORE BEING TRUSTED (L-051): run against commit
	-- a8faa6a it reports THREE offending files -- V7MenuPanel:64, V7ForgePanel:67
	-- and V7HUD:223 -- and against the current tree it reports none.
	--
	-- THREE FILES, NOT TEN SITES, and the difference is the point: `findPictograph`
	-- returns on the FIRST match, so it names one line per file however many that
	-- file contains. The count is a file count. An earlier version of this comment
	-- claimed ten offenders, which is the number of emoji that were in the tree
	-- and not a number this code can ever print -- a validation note describing
	-- what was fixed rather than what the check reports. That is the same shape of
	-- error as the metric it guards against, so it is corrected rather than
	-- quietly dropped. A metric that cannot tell
	-- a known-bad build from a known-good one is not evidence.
	----------------------------------------------------------------------------

	local function findPictograph(src: string): number?
		local i = 1
		local len = #src
		while i <= len do
			local c = string.byte(src, i)
			if c == nil then
				break
			end
			if c >= 240 and c <= 244 then
				-- 4-byte: the supplementary planes, where the emoji live.
				return i
			elseif c == 226 and i + 2 <= len then
				-- 3-byte starting E2: misc symbols, dingbats, arrows.
				local b1 = string.byte(src, i + 1) or 0
				local b2 = string.byte(src, i + 2) or 0
				local cp = 0x2000 + (b1 % 64) * 64 + (b2 % 64)

				-- THE CARD SUITS ARE TYPOGRAPHY AND ARE ALLOWED. U+2666 BLACK
				-- DIAMOND SUIT is the Diamonds currency mark and sits INSIDE the
				-- misc-symbols block below, so it has to be excused explicitly
				-- rather than by relying on where it falls.
				--
				-- It is currently written as a `\u{2666}` escape, whose bytes are
				-- plain ASCII and would never reach this scan at all -- which is
				-- exactly why the exclusion is stated here. A rule that passes
				-- only because of how a character happened to be typed is a trap
				-- for whoever next writes the glyph literally.
				local isSuit = cp >= 0x2660 and cp <= 0x2667

				if not isSuit and ((cp >= 0x2600 and cp <= 0x27BF)
					or (cp >= 0x2B00 and cp <= 0x2BFF)
					or (cp >= 0x23E9 and cp <= 0x23FA)) then
					return i
				end
				i += 2
			end
			i += 1
		end
		return nil
	end

	local emojiOffenders: { string } = {}
	local sourceReadable = true

	for _, name in ipairs(VIEW_MODULES) do
		local instance = clientRoot:FindFirstChild(name)
		if instance ~= nil and instance:IsA("LuaSourceContainer") then
			-- The capability check is per-thread, not per-instance, so one
			-- failure means none of them are readable. Stop rather than pcall
			-- eleven times for the same answer.
			local ok, src = pcall(function()
				return instance.Source
			end)
			if not ok then
				sourceReadable = false
				break
			end
			local at = findPictograph(src)
			if at ~= nil then
				-- Report the LINE, so the offender is addressable rather than
				-- merely reported as present (L-037).
				local _, line = string.gsub(string.sub(src, 1, at), "\n", "")
				table.insert(emojiOffenders,
					string.format("%s:%d", name, line + 1))
			end
		end
	end

	if sourceReadable then
		e = e or check(#emojiOffenders == 0, string.format(
			"emoji in client UI source (icons must be drawn geometry, not font glyphs): %s",
			table.concat(emojiOffenders, ", ")))
	else
		-- SAID OUT LOUD, because a check that quietly does nothing is worse than
		-- no check: it leaves a green suite implying a property nobody tested.
		print("[UT-13] emoji scan SKIPPED -- this thread cannot read Source "
			.. "(needs PluginOrOpenCloud). Runs under a plugin context; also "
			.. "reproducible from the shell.")
	end

	----------------------------------------------------------------------------
	-- MULT-1: THE CLIENT MUST NOT CARRY ITS OWN STREAK CAP.
	--
	-- The shipped defect was a hardcoded `math.min(streak, 500)` in
	-- ClientBootstrap's `estimateMultiplier`, so the HUD advertised a multiplier the
	-- server (cap 50) never paid. `estimateMultiplier` is a local inside a .client
	-- script and cannot be required, so this is a SOURCE SCAN -- the same instrument
	-- as the emoji scan above, with the same skip-when-unreadable behaviour.
	--
	-- WHAT THIS PROVES, AND WHAT IT DOES NOT. It proves the file contains a call to
	-- `StreakMath.multiplier` and no line that clamps something streak-named against
	-- a numeric literal. It does NOT prove the call is on the live path, that its
	-- arguments are right, or that a cap spelled some other way (a named local, a
	-- lookup table) is absent. A behavioural test would; extracting the function
	-- to Shared was ruled out as a logic refactor. Treat a green here as "the known
	-- defect shape is gone", not "the HUD multiplier is correct".
	--
	-- Comments are stripped first: the explanatory comment above `estimateMultiplier`
	-- legitimately mentions "500".
	--
	-- VALIDATED BOTH WAYS (L-051): the detector is run on a synthetic copy of the
	-- shipped defect below and must flag it, so it cannot pass by matching nothing.
	----------------------------------------------------------------------------

	local function literalStreakClamp(src: string): string?
		for line in string.gmatch(src, "[^\n]+") do
			local code = string.gsub(line, "%-%-.*$", "")
			local lower = string.lower(code)
			if string.find(lower, "streak", 1, true) ~= nil
				and (string.find(lower, "math.min(", 1, true) ~= nil
					or string.find(lower, "math.clamp(", 1, true) ~= nil)
				and string.find(lower, "[%(,]%s*%d+%.?%d*%s*[,%)]") ~= nil then
				return code
			end
		end
		return nil
	end

	e = e or check(literalStreakClamp("local c = math.min(streak, 500)") ~= nil
		and literalStreakClamp("local c = math.min(500, state.streak)") ~= nil
		and literalStreakClamp("local c = math.min(streak, StreakMath.STREAK_CAP) -- 500") == nil,
		"literalStreakClamp must flag the shipped MULT-1 shape and ignore comments and named caps")

	if bootModule ~= nil and bootModule:IsA("LuaSourceContainer") then
		local okBoot, bootSrc = pcall(function()
			return (bootModule :: any).Source :: string
		end)
		if okBoot then
			e = e or check(literalStreakClamp(bootSrc) == nil, string.format(
				"ClientBootstrap clamps a streak against a numeric literal (MULT-1: derive the cap "
				.. "from StreakMath.STREAK_CAP): %s", tostring(literalStreakClamp(bootSrc))))
			e = e or check(string.find(bootSrc, "StreakMath.multiplier(", 1, true) ~= nil,
				"ClientBootstrap must compute the HUD multiplier through StreakMath.multiplier (MULT-1)")
		else
			print("[UT-13] MULT-1 streak-cap scan SKIPPED -- this thread cannot read Source "
				.. "(needs PluginOrOpenCloud).")
		end
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

	----------------------------------------------------------------------------
	-- NetClient wrappers return a single Result table { ok: boolean, reason: string? }
	-- NOT a tuple (FORGE-1 regression pin)
	----------------------------------------------------------------------------
	-- Calling a wrapper returns a table with `ok: boolean`, never a boolean directly.
	-- If a caller destructures as `local ok, reason = NetClient.forge(...)`, `ok`
	-- becomes the table reference (always truthy!) and reason is nil.
	local resForge = (NetClient :: any).forge(1, { 10, 10, 10, 10, 10, 10 })
	e = e or check(type(resForge) == "table",
		"NetClient.forge must return a single Result table, not a tuple or primitive")
	e = e or check(type(resForge.ok) == "boolean",
		"NetClient.forge result.ok must be a boolean")
	e = e or check(resForge.reason == nil or type(resForge.reason) == "string",
		"NetClient.forge result.reason must be nil or string")

	local resUpgrade = (NetClient :: any).buyUpgrade("MassBudget")
	e = e or check(type(resUpgrade) == "table",
		"NetClient.buyUpgrade must return a single Result table, not a tuple or primitive")
	e = e or check(type(resUpgrade.ok) == "boolean",
		"NetClient.buyUpgrade result.ok must be a boolean")
	e = e or check(resUpgrade.reason == nil or type(resUpgrade.reason) == "string",
		"NetClient.buyUpgrade result.reason must be nil or string")

	----------------------------------------------------------------------------
	-- The promo-code refusal surface is CLOSED (added 2026-08-26)
	----------------------------------------------------------------------------

	-- WHY THIS EXISTS. The REDEEM handler shipped a reason->message table under a
	-- comment claiming every reason was mapped. Two audit rounds found two
	-- different producers outside that claim -- `PlayerProfile.mutate`, then the
	-- gateway's own dispatch wrapper. Nothing mechanical could catch either: a
	-- missing table key is not a syntax error, and the fallback rendered it as a
	-- plausible message.
	--
	-- A FIRST ATTEMPT AT THIS TEST WAS A TAUTOLOGY and is recorded here so it is
	-- not rebuilt. It declared the reason strings in the test and then asserted
	-- they were non-empty strings -- checking the test's own literals against
	-- themselves. It could not fail, it pinned nothing, and it inflated the
	-- assertion count while covering zero behaviour (the L-018 / F-G3-3 shape,
	-- and the count moving is exactly what made it look like coverage).
	--
	-- The client's message table CANNOT be reached from here: it is a local
	-- inside a closure, and reading `Source` needs PluginOrOpenCloud which a game
	-- script does not have. Per TEST_PLAN.md:136 that check belongs in **P-3**,
	-- which greps the repository from disk -- not in a runtime suite pretending
	-- it can see the text.
	--
	-- What IS provable here is the PRODUCER side: the reasons really are what the
	-- client must handle. These drive the real functions and fail on real drift.

	-- `boundedString` is the validator the RedeemCode path runs through, and its
	-- three refusals must stay exactly these three. Proven by driving it, not by
	-- reading it.
	local okStr, whyStr = (RemoteGateway :: any).V.boundedString(42, 32)
	e = e or check(okStr == false and whyStr == "not_string",
		"boundedString must refuse a non-string as not_string")
	okStr, whyStr = (RemoteGateway :: any).V.boundedString("", 32)
	e = e or check(okStr == false and whyStr == "empty_string",
		"boundedString must refuse an empty string as empty_string")
	okStr, whyStr = (RemoteGateway :: any).V.boundedString(string.rep("A", 33), 32)
	e = e or check(okStr == false and whyStr == "too_long",
		"boundedString must refuse an over-length code as too_long")
	okStr, whyStr = (RemoteGateway :: any).V.boundedString("FORGE2026", 32)
	e = e or check(okStr == true and whyStr == nil,
		"boundedString must accept a well-formed code")

	-- RedeemCode takes exactly one argument. If this changes, the client wrapper
	-- and the handler have to change together.
	e = e or check(RemoteGateway.arityFor("RedeemCode") == 1,
		"RedeemCode must take exactly one argument")

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-13 ClientContract", run = run }
