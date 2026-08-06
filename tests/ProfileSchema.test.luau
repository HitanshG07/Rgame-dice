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

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local PlayerProfile = require(Server:WaitForChild("PlayerProfile"))

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
	local e: string?

	local TEMPLATE = PlayerProfile.getTemplate()

	----------------------------------------------------------------------------
	-- An empty table reconciles to the FULL template
	----------------------------------------------------------------------------

	local reconciled = PlayerProfile._reconcile({})
	e = e or check(reconciled.SchemaVersion == 1, "reconciled profile should be SchemaVersion 1")
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
	e = e or check(reconciled.Dice[1].Shape == "D6", "the starting die should be a D6")
	e = e or check(#reconciled.Dice[1].Faces == 6, "the starting D6 should have 6 faces")
	e = e or check(reconciled.Dice[1].MassBudget == 60, "the starting D6 budget should be 60")

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
	e = e or check(reconciled.Diamond.Shapes.D6 == true, "the D6 shape should be unlocked by default")
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
	-- Migration chain v0 -> v1
	----------------------------------------------------------------------------

	local v0Profile: any = { SchemaVersion = 0, Cash = 1000 }
	local migOk, migErr = PlayerProfile._migrate(v0Profile)
	e = e or check(migOk, string.format("v0 -> v1 migration should succeed: %s", tostring(migErr)))
	e = e or check(v0Profile.SchemaVersion == 1, "a migrated profile should report version 1")
	e = e or check(v0Profile.Cash == 1000, "Cash must be preserved across migration")
	e = e or check(type(v0Profile.Dice) == "table" and #v0Profile.Dice == 1,
		"a migrated profile should acquire the starting die")

	-- Migration must not hand the migrated profile a reference INTO the template.
	v0Profile.Dice[1].Faces[1].Mass = 4321
	local afterMigrate = PlayerProfile._reconcile({})
	e = e or check(afterMigrate.Dice[1].Faces[1].Mass == 10, string.format(
		"migration shared the TEMPLATE die by reference -- a migrated player's forge "
		.. "would rewrite the starting die for everyone else (fresh mass is %s)",
		tostring(afterMigrate.Dice[1].Faces[1].Mass)))

	-- A current-version profile migrates as a no-op.
	local v1Profile: any = { SchemaVersion = 1, Cash = 55 }
	local v1Ok = PlayerProfile._migrate(v1Profile)
	e = e or check(v1Ok, "a current-version profile should migrate successfully as a no-op")
	e = e or check(v1Profile.Cash == 55, "a no-op migration must not alter data")

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
