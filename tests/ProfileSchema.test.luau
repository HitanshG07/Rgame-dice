--!strict
-- UT-7 — ProfileSchema (TEST_PLAN.md §4)
--
-- Template reconciliation, the versioned migration chain, missing-field
-- recovery, and quarantine of an unmigratable profile (threat T-12).
--
-- `_reconcile` is exercised here BECAUSE IT RUNS ON THE LIVE LOAD PATH -- it is
-- called from PlayerProfile.load() immediately after the library's own
-- Reconcile(), as a second defensive layer over the sub-tables the roll loop
-- dereferences unguarded. An earlier draft of this suite tested it while
-- production never called it, which proves nothing about production.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))
local DiceCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DiceCatalog"))

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
	-- Typed `any` rather than `string?` for one specific Luau reason: the
	-- accumulator idiom `e = e or check(...)` produces a refinement union the
	-- checker cannot collapse back to `string?`, which warns at every call site.
	-- Semantics are unchanged (check still runs only while e is nil) and nothing
	-- is hidden: `e` is a local failure message whose only use is the return below.
	local e: any = nil

	local TEMPLATE = PlayerProfile.getTemplate()

	----------------------------------------------------------------------------
	-- An empty table reconciles to the FULL template
	----------------------------------------------------------------------------

	local reconciled = PlayerProfile._reconcile({})
	e = e or check(reconciled.SchemaVersion == 2, "reconciled profile should be SchemaVersion 2")
	e = e or check(reconciled.Cash == 0, "default Cash should be 0")
	e = e or check(reconciled.Gems == 0, "default Gems should be 0")
	e = e or check(reconciled.Diamonds == 0, "default Diamonds should be 0")
	e = e or check(reconciled.DieSlots == 1, "default DieSlots should be 1")
	e = e or check(reconciled.BundleOffered == false, "BundleOffered should default false")

	-- EVERY template key must be present. Enumerated rather than spot-checked:
	-- a missing key is a nil-index at first join, and spot-checks miss exactly
	-- the key nobody thought about (threat T-12).
	local missing: { string } = {}
	-- Cast to a dynamic map: Profile is a sealed type, so a runtime key sweep
	-- cannot be expressed against it directly under --!strict.
	local templateMap = TEMPLATE :: { [string]: any }
	local reconciledMap = reconciled :: { [string]: any }
	for key in pairs(templateMap) do
		if reconciledMap[key] == nil then
			table.insert(missing, key)
		end
	end
	e = e or check(#missing == 0,
		string.format("reconcile left template keys unset: %s", table.concat(missing, ", ")))

	----------------------------------------------------------------------------
	-- The starting die
	----------------------------------------------------------------------------

	e = e or check(type(reconciled.Dice) == "table" and #reconciled.Dice == 1,
		"a default profile should have exactly 1 starting die")
	-- THE STARTING SHAPE IS THE FIRST RUNG OF THE LADDER, asked of DiceCatalog
	-- rather than restated. A literal here would be a second copy of a product
	-- decision, and the copy nobody executes is the one that drifts (L-026).
	local startShape = DiceCatalog.STARTING_SHAPE
	local startDef = DiceCatalog.getShape(startShape)
	e = e or check(startDef ~= nil, "the starting shape must exist in the catalog")
	e = e or check(reconciled.Dice[1].Shape == startShape,
		string.format("the starting die should be a %s, got %s", startShape,
			tostring(reconciled.Dice[1].Shape)))
	e = e or check(#reconciled.Dice[1].Faces == (startDef :: any).faceCount,
		"the starting die's face count must match its shape definition")
	e = e or check(reconciled.Dice[1].MassBudget == (startDef :: any).defaultBudget,
		"the starting die's budget must match its shape's default")
	e = e or check(reconciled.Dice[1].PurchasedBudget == (startDef :: any).defaultBudget,
		"the starting die must declare PurchasedBudget, or a shape change reads nil")

	local faceSum = 0
	for _, face in ipairs(reconciled.Dice[1].Faces) do
		faceSum += face.Mass
	end
	e = e or check(faceSum == reconciled.Dice[1].MassBudget, string.format(
		"the starting die's faces must sum to its budget: %d vs %d",
		faceSum, reconciled.Dice[1].MassBudget))

	----------------------------------------------------------------------------
	-- Sub-tables the roll loop dereferences without guarding
	----------------------------------------------------------------------------

	e = e or check(reconciled.Upgrades.BadRollShield == 0, "BadRollShield should default to 0")
	e = e or check(reconciled.Upgrades.AutoRollSpeed == 0, "AutoRollSpeed should default to 0")
	e = e or check(reconciled.Diamond.StreakStrength == 0, "StreakStrength should default to 0")
	e = e or check(reconciled.Diamond.Elements.None == true, "the None element should be unlocked by default")
	e = e or check(reconciled.Diamond.Shapes[DiceCatalog.STARTING_SHAPE] == true,
		"the starting shape should be unlocked by default")

	-- THE LADDER IS CLOSED AT THE BOTTOM. Exactly one shape may be owned at the
	-- start, and it must be the first rung -- otherwise a new player either has
	-- nothing to roll or skips the progression entirely.
	local unlockedCount = 0
	for _, owned in pairs(reconciled.Diamond.Shapes) do
		if owned then
			unlockedCount += 1
		end
	end
	e = e or check(unlockedCount == 1,
		string.format("exactly one shape unlocked at start, found %d", unlockedCount))
	e = e or check(DiceCatalog.getUnlockOrder()[1] == DiceCatalog.STARTING_SHAPE,
		"the starting shape must be the first rung of the unlock ladder")
	e = e or check(DiceCatalog.getPrerequisite(DiceCatalog.STARTING_SHAPE) == nil,
		"the first rung must have no prerequisite, or it can never be unlocked")

	-- Every later rung must be REACHABLE: a prerequisite that names a shape not
	-- on the ladder would strand everything above it.
	local order = DiceCatalog.getUnlockOrder()
	local ladderOk = true
	for i = 2, #order do
		local prereq = DiceCatalog.getPrerequisite(order[i])
		if prereq ~= order[i - 1] then
			ladderOk = false
		end
		if DiceCatalog.getUnlockCost(order[i]) == nil then
			ladderOk = false
		end
	end
	e = e or check(ladderOk, "every rung must name the previous rung and carry a cost")
	e = e or check(reconciled.Vault.AvgIncomePerSec == 0, "AvgIncomePerSec should default to 0")

	-- A profile that has the key but a WRONG type is repaired, not trusted.
	local corrupt: any = { Dice = "not a table", Upgrades = 42, Diamond = false }
	local repaired = PlayerProfile._reconcile(corrupt)
	e = e or check(type(repaired.Dice) == "table" and #repaired.Dice == 1,
		"a non-table Dice field must be repaired to the starting die")
	e = e or check(type(repaired.Upgrades) == "table", "a non-table Upgrades field must be repaired")
	e = e or check(type(repaired.Diamond) == "table", "a non-table Diamond field must be repaired")
	e = e or check(type(repaired.Diamond.Elements) == "table", "Diamond.Elements must be repaired")
	e = e or check(type(repaired.Diamond.Shapes) == "table", "Diamond.Shapes must be repaired")

	-- An emptied Dice array is repaired too -- zero dice would make every roll
	-- return invalid_request forever with no way for the player to recover.
	local emptied: any = { Dice = {} }
	local refilled = PlayerProfile._reconcile(emptied)
	e = e or check(#refilled.Dice == 1, "an emptied Dice array must be repaired to the starting die")

	----------------------------------------------------------------------------
	-- Existing data is PRESERVED, never overwritten by defaults
	----------------------------------------------------------------------------

	local existing: any = { Cash = 12345, Gems = 7, LifetimeCash = 99999 }
	local kept = PlayerProfile._reconcile(existing)
	e = e or check(kept.Cash == 12345, "reconcile must not overwrite an existing Cash value")
	e = e or check(kept.Gems == 7, "reconcile must not overwrite an existing Gems value")
	e = e or check(kept.LifetimeCash == 99999, "reconcile must not overwrite existing LifetimeCash")
	e = e or check(kept.Diamonds == 0, "reconcile must still fill the fields that were absent")

	----------------------------------------------------------------------------
	-- F-AD-3: reconciliation must reach NESTED keys, and per-die fields
	----------------------------------------------------------------------------

	-- A shallow sweep fills `Upgrades` only when the whole table is missing. It
	-- never notices a new key INSIDE an existing table, so the day a field is
	-- added every returning player reads nil for it.
	local partialNested: any = {
		Upgrades = { AutoRollSpeed = 3 },
		Vault = { LastSeen = 111 },
		Settings = { Music = false },
		LoginStreak = { Count = 4 },
	}
	local nested = PlayerProfile._reconcile(partialNested)
	e = e or check(nested.Upgrades.AutoRollSpeed == 3, "an existing nested value must be preserved")
	e = e or check(nested.Upgrades.BadRollShield == 0, "a MISSING nested key must be filled (F-AD-3)")
	e = e or check(nested.Upgrades.VaultCapacity == 0, "every missing nested key must be filled")
	e = e or check(nested.Vault.LastSeen == 111, "an existing Vault value must be preserved")
	e = e or check(nested.Vault.AccrualId == 0, "a missing Vault key must be filled")
	e = e or check(nested.Vault.AvgIncomePerSec == 0, "a missing Vault key must be filled")
	e = e or check(nested.Settings.Music == false, "an existing Settings value must be preserved")
	e = e or check(nested.Settings.Particles == true, "a missing Settings key must be filled")
	e = e or check(nested.LoginStreak.Count == 4, "an existing LoginStreak value must be preserved")
	e = e or check(nested.LoginStreak.ForgivenessLeft == 1, "a missing LoginStreak key must be filled")

	-- Per-die fields live inside an ARRAY. ProfileStore's own Reconcile walks
	-- string keys only and never descends into Dice, so nothing but this layer
	-- can fill them.
	local preV2: any = { Dice = { { Shape = "D6", MassBudget = 120, Faces = {
		{ Mass = 20, Element = "None" }, { Mass = 20, Element = "None" },
		{ Mass = 20, Element = "None" }, { Mass = 20, Element = "None" },
		{ Mass = 20, Element = "None" }, { Mass = 20, Element = "None" },
	} } } }
	local dieFixed = PlayerProfile._reconcile(preV2)
	e = e or check(dieFixed.Dice[1].PurchasedBudget == 120, string.format(
		"a pre-v2 die must get PurchasedBudget seeded from MassBudget, got %s",
		tostring(dieFixed.Dice[1].PurchasedBudget)))
	e = e or check(dieFixed.Dice[1].MassBudget == 120, "reconcile must not alter an existing MassBudget")

	----------------------------------------------------------------------------
	-- Migration v1 -> v2: PurchasedBudget split out of MassBudget
	----------------------------------------------------------------------------

	local v1Die: any = { SchemaVersion = 1, Dice = { { Shape = "D6", MassBudget = 240, Faces = {} } } }
	local v2Ok, v2Err = PlayerProfile._migrate(v1Die)
	e = e or check(v2Ok, string.format("v1 -> v2 migration should succeed: %s", tostring(v2Err)))
	e = e or check(v1Die.SchemaVersion == 2, "a migrated profile should report version 2")
	e = e or check(v1Die.Dice[1].PurchasedBudget == 240, string.format(
		"v1 -> v2 must seed PurchasedBudget from MassBudget losslessly, got %s",
		tostring(v1Die.Dice[1].PurchasedBudget)))
	e = e or check(v1Die.Dice[1].MassBudget == 240, "v1 -> v2 must not change MassBudget")

	----------------------------------------------------------------------------
	-- Migration chain v0 -> v1
	----------------------------------------------------------------------------

	local v0Profile: any = { SchemaVersion = 0, Cash = 1000 }
	local migOk, migErr = PlayerProfile._migrate(v0Profile)
	e = e or check(migOk, string.format("v0 -> v1 migration should succeed: %s", tostring(migErr)))
	e = e or check(v0Profile.SchemaVersion == 2, "a v0 profile must migrate all the way to the current version")
	e = e or check(v0Profile.Cash == 1000, "Cash must be preserved across migration")
	e = e or check(type(v0Profile.Dice) == "table" and #v0Profile.Dice == 1,
		"a migrated profile should acquire the starting die")

	-- Migration must not hand the migrated profile a reference INTO the template.
	v0Profile.Dice[1].Faces[1].Mass = 4321
	local afterMigrate = PlayerProfile._reconcile({})
	-- Read from the template, not hardcoded: see the matching note in UT-8.
	local templateMass = PlayerProfile.getTemplate().Dice[1].Faces[1].Mass
	e = e or check(afterMigrate.Dice[1].Faces[1].Mass == templateMass, string.format(
		"migration shared the TEMPLATE die by reference -- a migrated player's forge "
		.. "would rewrite the starting die for everyone else (fresh mass is %s)",
		tostring(afterMigrate.Dice[1].Faces[1].Mass)))

	-- A current-version profile migrates as a no-op.
	local currentProfile: any = { SchemaVersion = 2, Cash = 55 }
	local currentOk = PlayerProfile._migrate(currentProfile)
	e = e or check(currentOk, "a current-version profile should migrate successfully as a no-op")
	e = e or check(currentProfile.Cash == 55, "a no-op migration must not alter data")

	----------------------------------------------------------------------------
	-- Quarantine: unmigratable profiles FAIL CLOSED, never overwritten
	----------------------------------------------------------------------------

	local futureProfile: any = { SchemaVersion = 999, Cash = 424242 }
	local futureOk, futureErr = PlayerProfile._migrate(futureProfile)
	e = e or check(not futureOk, "a future SchemaVersion must fail migration and quarantine")
	e = e or check(futureErr == "profile_from_future_version",
		string.format("expected 'profile_from_future_version', got '%s'", tostring(futureErr)))
	e = e or check(futureProfile.Cash == 424242,
		"a quarantined profile must be left INTACT, not reset -- it stays recoverable by hand")

	local unversioned: any = { Cash = 10 }
	local unversionedOk, unversionedErr = PlayerProfile._migrate(unversioned)
	e = e or check(not unversionedOk, "a profile with no SchemaVersion must fail closed")
	e = e or check(unversionedErr == "missing_schema_version",
		string.format("expected 'missing_schema_version', got '%s'", tostring(unversionedErr)))

	local badTypeVersion: any = { SchemaVersion = "one", Cash = 10 }
	local badTypeOk = PlayerProfile._migrate(badTypeVersion)
	e = e or check(not badTypeOk, "a non-numeric SchemaVersion must fail closed")

	if e then
		return false, e, n
	end
	return true, nil, n
end

return { name = "UT-7 ProfileSchema", run = run }
