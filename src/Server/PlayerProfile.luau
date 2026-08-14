--!strict
-- PlayerProfile.luau
-- The SOLE wrapper over the persistence library. No other module in the game
-- touches ProfileStore directly, so replacing it is a one-module change (HLD §5.1).
--
-- Named PlayerProfile rather than ProfileStore deliberately, to avoid colliding
-- with loleris's library of that exact name.
--
-- Three rules from HLD §5.2, all enforced here and all testable:
--   1. A profile that fails to load, or whose lock is held elsewhere, FAILS CLOSED.
--      It is never replaced by a default profile -- that would silently overwrite
--      real saved data (threat T-10).
--   2. A RELEASED profile is immutable, and the active check must be SYNCHRONOUS
--      with the mutation. No yield may sit between check and write (threat T-26).
--   3. The in-memory profile is the single source of truth during play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Required for ONE constant: the die-slot ceiling. `_reconcile` used to hardcode
-- it, which is the mirror-drift defect L-041 records -- and here it was worse
-- than drift, because the hardcoded value also inverted a `math.clamp` range and
-- would throw. See the clamp itself for the full account.
local DiceCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DiceCatalog"))

local PlayerProfile = {}

local STORE_NAME = "DiceForge_Profiles_v1"
local KEY_PREFIX = "Profile_"

-- Threat T-13: purchase-id retention is bounded so a profile cannot grow until
-- every save fails. Eviction is TIME-AWARE, not count-only -- the original
-- count-only bound was justified on a time basis, which was wrong: a player
-- past the ceiling can have a still-replayable receipt evicted and be
-- double-granted. Entries older than the retry window are evictable; if the
-- ceiling is hit while all entries are still inside it, the oldest are archived
-- rather than dropped.
local PURCHASE_ID_CEILING = 200
local RECEIPT_RETRY_WINDOW = 60 * 60 * 24 * 3

-- Threat T-13: refuse to write a profile that would exceed the DataStore
-- per-key limit. Roblox's documented ceiling is ~4 MB; this leaves headroom.
local PAYLOAD_CEILING_BYTES = 3_500_000

export type Face = { Mass: number, Element: string }

-- `MassBudget` is what this die may distribute RIGHT NOW, clamped into the
-- current shape's legal range. `PurchasedBudget` is what the player actually
-- bought (SRS FR-3.6) and is shape-independent.
--
-- They are separate because a shape change must be freely reversible (FR-6.1)
-- WITHOUT being a way to gain budget. Deriving MassBudget from a per-shape
-- clamp of PurchasedBudget gives both: switching to a smaller-capped shape
-- caps the usable budget but does not destroy what was bought, and switching
-- to a larger-capped shape restores it but never manufactures more.
export type Die = { Shape: string, MassBudget: number, PurchasedBudget: number, Faces: { Face } }

export type Profile = {
	SchemaVersion: number,
	Cash: number, Gems: number, Diamonds: number,
	LifetimeCash: number, HighestRoll: number, Ascensions: number, TotalRolls: number,
	Dice: { Die },
	DieSlots: number,
	-- How much of the +2 Die Slots pass entitlement has already been turned into
	-- real stored slots. Lets the grant run on every join without stacking.
	PassSlotsGranted: number,
	Diamond: {
		StreakStrength: number, MassCeiling: number, SlotNodes: number,
		Elements: { [string]: boolean }, Shapes: { [string]: boolean },
		ShapesEquipped: { [string]: boolean },
	},
	Upgrades: { [string]: number },
	Vault: { LastSeen: number, AccrualId: number, AvgIncomePerSec: number },
	PurchaseIds: { [string]: number },
	PurchaseOrder: { string },
	BundleOffered: boolean,
	-- FR-12.5. Absolute server timestamp when the starter offer closes, stamped
	-- ONCE on the player's first session. Zero means "not yet stamped"; there is
	-- no code path that raises it after the fact.
	BundleExpiry: number,
	CodesRedeemed: { [string]: boolean },
	Quests: { Slots: { any }, RolledOn: number },
	LoginStreak: { Count: number, LastDay: number, ForgivenessLeft: number },
	LastSpin: number,
	GroupClaimed: boolean,
	Settings: { [string]: boolean },
}

-- API_DATA_CONTRACT.md §3. Every field has a default, so no load path can
-- dereference nil (threat T-12).
local TEMPLATE: Profile = {
	SchemaVersion = 2,
	Cash = 0, Gems = 0, Diamonds = 0,
	LifetimeCash = 0, HighestRoll = 0, Ascensions = 0, TotalRolls = 0,
	-- A NEW PLAYER STARTS ON THE D2 (operator-directed 2026-08-11). Shapes unlock
	-- along the ladder in `DiceCatalog.UNLOCK_ORDER`; see that file's header for
	-- why an ordered unlock does not make shapes a power tier.
	--
	-- Two faces at the SHARED budget of 60, split evenly. The budget is
	-- shape-independent by balance necessity -- see DiceCatalog, where making it
	-- scale with face count was measured handing the D20 an unconditional win at
	-- every Streak Strength.
	--
	-- Even is the honest starting distribution: it is the only one that expresses
	-- no opinion, and the first thing the game teaches is that moving mass OFF a
	-- face is what makes that face pay.
	Dice = {
		{
			Shape = "D2",
			MassBudget = 60,
			PurchasedBudget = 60,
			Faces = {
				{ Mass = 30, Element = "None" }, { Mass = 30, Element = "None" },
			},
		},
	},
	DieSlots = 1,
	PassSlotsGranted = 0,
	Diamond = {
		StreakStrength = 0, MassCeiling = 0, SlotNodes = 0,
		Elements = { None = true },
		-- The first rung, and the only one owned at the start.
		Shapes = { D2 = true },
		-- SHAPES THE PLAYER HAS EVER EQUIPPED (operator decision, 2026-08-11).
		--
		-- The FIRST time a shape goes onto a die it is free; every switch after
		-- that costs Diamonds per FR-6.1. Without this, a Cash-bought shape was
		-- unusable for a whole first run -- Diamonds only arrive at ascension, so
		-- a player could buy D3, D4 and D6 and still be rolling D2.
		--
		-- It lives beside `Shapes` in the Diamond tree because it is permanent in
		-- the same way ownership is: ascension must not make a shape free to
		-- equip again, or a cheap re-ascend becomes a way to dodge the cost.
		-- Seeded with the starting shape, which is already on the starting die.
		ShapesEquipped = { D2 = true },
	},
	-- BadRollShield is a GAMEPASS entitlement, not a Cash upgrade. It is
	-- declared here with a 0 default so no read path can hit nil, and so the
	-- field's existence is explicit rather than implied. MonetizationService
	-- (unbuilt) will be the only writer. Declared 2026-08-06 from Gate 3
	-- finding F-G3-2. Absent-means-off remains the fail-closed default.
	Upgrades = { AutoRollSpeed = 0, VaultCapacity = 0, VaultEfficiency = 0, Luck = 0, BadRollShield = 0 },
	Vault = { LastSeen = 0, AccrualId = 0, AvgIncomePerSec = 0 },
	PurchaseIds = {},
	PurchaseOrder = {},
	BundleOffered = false,
	BundleExpiry = 0,
	CodesRedeemed = {},
	Quests = { Slots = {}, RolledOn = 0 },
	LoginStreak = { Count = 0, LastDay = 0, ForgivenessLeft = 1 },
	LastSpin = 0,
	GroupClaimed = false,
	Settings = { Particles = true, MotionBlur = true, Music = true, SFX = true },
}

-- GRANTS DIE SLOTS AND THE DICE TO FILL THEM, together.
--
-- THE DEFECT THIS EXISTS TO PREVENT (operator-reported 2026-08-13, as
-- "the maximum number of slots shows 7 but in game its only 6" and dice
-- overlapping on the board).
--
-- `DieSlots` is an entitlement COUNTER and `Dice` is the actual array. They are
-- two representations of one fact, and three separate places wrote them:
-- `AddDieSlot` incremented both, but the `+2 Die Slots` GAMEPASS and the
-- Starter Bundle incremented only the counter. A player who bought the pass
-- ended up with `DieSlots = 4` and two real dice.
--
-- Nothing errored. `DiceRenderer` correctly draws one tile per entry in
-- `state.dice`, so the board showed fewer dice than the panel promised, and
-- `BoardView` laid out for a count that did not match what was drawn -- which
-- is the overlap. The player paid for dice they never received.
--
-- Callers must use this rather than touching `d.DieSlots` directly. Operates on
-- profile DATA inside an existing mutation, so it composes with the atomic
-- writes its callers already perform.
function PlayerProfile.grantDieSlots(d: any, count: number, maxSlots: number, makeDie: () -> any?): number
	if type(count) ~= "number" or count ~= count or count <= 0 then
		return 0
	end
	local want = math.floor(count)
	local before = d.DieSlots
	d.DieSlots = math.min(maxSlots, d.DieSlots + want)
	local gained = d.DieSlots - before

	-- The dice themselves. `#d.Dice` rather than `gained` is the loop bound on
	-- purpose: it repairs a profile that ALREADY drifted, so an existing player
	-- who bought the pass gets their missing dice on the next grant rather than
	-- staying permanently short.
	for _ = #d.Dice + 1, d.DieSlots do
		local die = makeDie()
		if die == nil then
			break
		end
		table.insert(d.Dice, die)
	end

	return gained
end

function PlayerProfile.getTemplate(): Profile
	return TEMPLATE
end

-- DEEP copy, not `table.clone`.
--
-- `table.clone` is SHALLOW: `table.clone(TEMPLATE.Dice)` produces a new ARRAY
-- whose element [1] is still THE SAME TABLE as `TEMPLATE.Dice[1]`. Every profile
-- built that way would share one die object with the template, so the first
-- player to forge would rewrite the starting die for every player who joined
-- afterwards on that server. Nothing at runtime reports this; it presents as
-- new players mysteriously starting with someone else's mass layout.
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out: { [any]: any } = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

PlayerProfile._deepCopy = deepCopy

-- Defensive template fill, layered UNDER ProfileStore's own Reconcile().
--
-- Reconcile() covers keys the library knows about; this covers a key that is
-- present but nil-valued, a Dice array emptied by a bad write, and the three
-- sub-tables the game dereferences on every roll. It runs on the live load path
-- (threat T-12) -- it is deliberately NOT a test-only helper, because a helper
-- that only tests exercise proves nothing about production.
function PlayerProfile._reconcile(raw: any): Profile
	-- Both sides are addressed as dynamic maps here BY NECESSITY: the whole job
	-- of this function is a runtime key sweep, and `Profile` is a sealed type
	-- that cannot be indexed by a computed key. The cast is confined to this
	-- function; every caller sees a `Profile` going in and coming out.
	local data: { [string]: any } = if type(raw) == "table" then raw else {}
	local template = (TEMPLATE :: any) :: { [string]: any }
	-- RECURSIVE, not top-level only. A shallow sweep fills `Upgrades` when the
	-- whole table is missing but never notices a NEW KEY INSIDE an existing
	-- one -- so the day a field is added to Upgrades, Vault, Settings or
	-- LoginStreak, every returning player reads nil for it. Found by the Block 3
	-- Gate 4 audit (F-AD-3). ProfileStore's own Reconcile does recurse and runs
	-- first, so this is defence in depth -- but a defensive layer that silently
	-- depends on the thing it is defending against is not a layer.
	--
	-- STRING KEYS ONLY, and this guard is load-bearing. Without it the recursion
	-- descends into ARRAYS -- `Dice` above all -- and merges the template's die
	-- into the player's die, overwriting per-die fields with starting values. A
	-- player with a 120-budget die would silently inherit the template's 60.
	-- ProfileStore's own ReconcileTable carries the identical guard for the
	-- identical reason. Array elements are the caller's data, never a shape to
	-- be filled; the explicit per-die loop below handles them by hand.
	local function fill(target: { [string]: any }, source: { [string]: any })
		for k, v in pairs(source) do
			if type(k) == "string" then
				if target[k] == nil then
					target[k] = deepCopy(v)
				elseif type(target[k]) == "table" and type(v) == "table" then
					fill(target[k], v)
				end
			end
		end
	end
	fill(data, template)
	if type(data.Dice) ~= "table" or #data.Dice == 0 then
		data.Dice = deepCopy(TEMPLATE.Dice)
	end

	-- SELF-REPAIR: `DieSlots` and `#Dice` must agree.
	--
	-- Two grant paths (the +2 Die Slots pass and the Starter Bundle) used to
	-- raise the counter without creating the dice, so profiles exist RIGHT NOW
	-- with `DieSlots = 4` and two dice. The writers are fixed, but a fix to the
	-- writer does nothing for data already on disk -- the player would stay short
	-- until they happened to buy another slot.
	--
	-- Repaired on the way IN, which is where every other schema drift in this
	-- function is handled. Missing dice are created from the template's starting
	-- die; the counter is never lowered to match a short array, because that
	-- would silently confiscate a slot the player paid for.
	if type(data.DieSlots) ~= "number" or data.DieSlots ~= data.DieSlots then
		data.DieSlots = #data.Dice
	end
	-- THE CEILING COMES FROM THE CATALOG, AND THE RANGE CANNOT INVERT.
	--
	-- This was `math.clamp(math.floor(data.DieSlots), #data.Dice, 7)`, and the
	-- literal 7 was two bugs wearing one coat.
	--
	-- FIRST, it mirrored `DiceCatalog.MAX_DIE_SLOTS` by hand, which is the drift
	-- L-041 records: raising the catalog's ceiling would have left this clamp
	-- quietly holding every profile at 7.
	--
	-- SECOND, AND MUCH WORSE: `math.clamp` THROWS when its minimum exceeds its
	-- maximum. The minimum here is `#data.Dice`. So any profile holding more than
	-- seven dice did not get trimmed -- it errored on load, on the profile path,
	-- for that player, every time. The operator's stated 20-dice progression
	-- ceiling was therefore unreachable no matter what the renderer could draw,
	-- and nothing would have reported why.
	--
	-- The ceiling now rises to admit whatever is genuinely stored. Trimming is
	-- deliberately NOT the behaviour: the counter is never lowered to match a
	-- short array (see above), and by the same reasoning a legitimately larger
	-- array must not be confiscated by a constant that has since moved.
	local slotCeiling = math.max(DiceCatalog.MAX_DIE_SLOTS, #data.Dice)
	data.DieSlots = math.clamp(math.floor(data.DieSlots), #data.Dice, slotCeiling)
	for _ = #data.Dice + 1, data.DieSlots do
		table.insert(data.Dice, deepCopy(TEMPLATE.Dice[1]))
	end

	-- Per-die defaults. NEITHER reconcile layer reaches here on its own:
	-- ProfileStore's ReconcileTable only walks STRING keys, so it never
	-- descends into an ARRAY like Dice, and the loop above only fills a
	-- top-level key that is entirely absent. A field added to the die record
	-- would therefore be nil forever on every existing profile.
	for _, die in ipairs(data.Dice) do
		if type(die) == "table" then
			if type(die.MassBudget) ~= "number" then
				die.MassBudget = TEMPLATE.Dice[1].MassBudget
			end
			if type(die.PurchasedBudget) ~= "number" then
				-- A pre-v2 die: what it holds IS what was purchased.
				die.PurchasedBudget = die.MassBudget
			end
		end
	end
	if type(data.Upgrades) ~= "table" then
		data.Upgrades = deepCopy(TEMPLATE.Upgrades)
	end
	if type(data.Diamond) ~= "table" then
		data.Diamond = deepCopy(TEMPLATE.Diamond)
	end
	-- Sub-tables inside Diamond are dereferenced unguarded by ForgeService.
	if type(data.Diamond.Elements) ~= "table" then
		data.Diamond.Elements = deepCopy(TEMPLATE.Diamond.Elements)
	end
	if type(data.BundleExpiry) ~= "number" or data.BundleExpiry ~= data.BundleExpiry then
		data.BundleExpiry = 0
	end
	if type(data.Diamond.Shapes) ~= "table" then
		data.Diamond.Shapes = deepCopy(TEMPLATE.Diamond.Shapes)
	end
	if type(data.Diamond.ShapesEquipped) ~= "table" then
		data.Diamond.ShapesEquipped = deepCopy(TEMPLATE.Diamond.ShapesEquipped)
	end

	-- `RunCash` WAS BACKFILLED HERE, and the field has been deleted.
	--
	-- It was a per-run earnings counter introduced 2026-08-13 to price ascension,
	-- and retired the same day in favour of reading cash on hand (operator
	-- decision -- `AscensionService.canAscend` carries the reasoning).
	--
	-- NO MIGRATION IS NEEDED ON REMOVAL, which is the whole reason this is safe to
	-- delete rather than deprecate: nothing reads the field, `fill` only ADDS keys
	-- the template has, and a stale `RunCash` sitting on an already-saved profile
	-- is inert. It costs a few bytes until that profile is next written and then
	-- stops existing.

	-- A SHAPE ON A DIE HAS, BY DEFINITION, BEEN EQUIPPED.
	--
	-- `ShapesEquipped` drives the first-equip-free rule, and the plain template
	-- backfill seeds it with the STARTING shape only. Every profile that predates
	-- the field is therefore wearing something the record says was never worn --
	-- so a player on a D6 could switch away and back for free once, and worse,
	-- the state is simply untrue.
	--
	-- Seeding from the dice themselves is both the correct migration and the
	-- honest one: it records what actually happened rather than guessing. It is
	-- also idempotent, so running it on every load costs nothing after the first.
	for _, die in ipairs(data.Dice) do
		if type(die) == "table" and type(die.Shape) == "string" then
			data.Diamond.ShapesEquipped[die.Shape] = true
		end
	end

	return (data :: any) :: Profile
end

--------------------------------------------------------------------------------
-- Library binding. Vendored under src/Server/Vendor/ and PINNED -- an unpinned
-- dependency on a moving target is prohibited at PRODUCTION tier.
--
-- The library is loaded through pcall so a missing vendor drop produces one
-- clear diagnostic instead of a cascade of nil-index errors at first join.
--------------------------------------------------------------------------------

local ProfileStoreLib: any = nil
local libLoadError: string? = nil

do
	local vendor = ServerScriptService:FindFirstChild("Server")
	vendor = vendor and vendor:FindFirstChild("Vendor")
	local mod = vendor and vendor:FindFirstChild("ProfileStore")
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			ProfileStoreLib = result
		else
			libLoadError = tostring(result)
		end
	else
		libLoadError = "ProfileStore ModuleScript not found at "
			.. "ServerScriptService.Server.Vendor.ProfileStore -- vendor the pinned "
			.. "release from https://github.com/MadStudioRoblox/ProfileStore"
	end
end

function PlayerProfile.isLibraryAvailable(): (boolean, string?)
	return ProfileStoreLib ~= nil, libLoadError
end

local store: any = nil
local active: { [Player]: any } = {}

function PlayerProfile.init(): ()
	if not RunService:IsServer() then
		error("[PlayerProfile] server-only", 2)
	end
	if store then
		return
	end
	if not ProfileStoreLib then
		error("[PlayerProfile] cannot init: " .. tostring(libLoadError), 2)
	end
	store = ProfileStoreLib.New(STORE_NAME, TEMPLATE)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- Rule 1: FAIL CLOSED. Returns ok, reason. On failure the caller must NOT
-- fabricate a profile -- it kicks the player with an honest message. Serving a
-- default over a live-locked or unreadable profile is how real saves get
-- silently destroyed.
function PlayerProfile.load(player: Player): (boolean, string?)
	if not store then
		if ProfileStoreLib then
			PlayerProfile.init()
		else
			return false, "store_not_initialised"
		end
	end
	if active[player] then
		return true, nil
	end

	local ok, profile = pcall(function()
		return store:StartSessionAsync(KEY_PREFIX .. tostring(player.UserId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
	end)

	if not ok then
		warn(string.format("[PlayerProfile] load errored for %d: %s",
			player.UserId, tostring(profile)))
		return false, "load_error"
	end
	if profile == nil then
		-- Session could not be claimed: another server holds it, or the player
		-- left mid-load. FAIL CLOSED.
		return false, "session_unavailable"
	end

	profile:AddUserId(player.UserId)      -- GDPR erasure support
	profile:Reconcile()                    -- fill any key added since last save
	-- Second, defensive layer under the library's own reconcile. Guarantees the
	-- sub-tables the roll loop dereferences unguarded are present (threat T-12).
	PlayerProfile._reconcile(profile.Data)

	profile.OnSessionEnd:Connect(function()
		active[player] = nil
		if player.Parent == Players then
			player:Kick("Your data session ended. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return false, "player_left"
	end

	local migrated, migrateErr = PlayerProfile._migrate(profile.Data)
	if not migrated then
		profile:EndSession()
		warn(string.format("[PlayerProfile] migration failed for %d: %s",
			player.UserId, tostring(migrateErr)))
		return false, "migration_failed"
	end

	active[player] = profile
	return true, nil
end

function PlayerProfile.release(player: Player): ()
	local profile = active[player]
	if profile then
		active[player] = nil
		profile:EndSession()
	end
end

function PlayerProfile.releaseAll(): ()
	for player in pairs(active) do
		PlayerProfile.release(player)
	end
end

-- Rule 2: a released profile is immutable. Callers use this immediately before
-- writing, with no yield in between.
function PlayerProfile.isActive(player: Player): boolean
	local profile = active[player]
	return profile ~= nil and profile:IsActive()
end

-- Read-only accessor. Returns nil rather than a fabricated default, so a caller
-- that forgets to check gets a loud nil-index rather than a silent phantom profile.
function PlayerProfile.get(player: Player): Profile?
	local profile = active[player]
	if not profile then
		return nil
	end
	return profile.Data :: Profile
end

-- Rule 2 enforced structurally: the ONLY sanctioned write path. `mutator` must
-- be synchronous -- it must not yield. The active check happens immediately
-- before it runs and the mutation happens immediately after, with nothing in
-- between that could let ListenToRelease fire (threat T-26).
function PlayerProfile.mutate(player: Player, mutator: (Profile) -> ()): (boolean, string?)
	local profile = active[player]
	if not profile then
		return false, "no_profile"
	end
	if not profile:IsActive() then
		warn(string.format("[PlayerProfile] write refused on released profile for %d",
			player.UserId))
		return false, "profile_released"
	end
	mutator(profile.Data :: Profile)
	return true, nil
end

--------------------------------------------------------------------------------
-- Purchase-id ledger (threats T-13, T-15)
--------------------------------------------------------------------------------

-- Records a granted receipt. Time-aware eviction: only entries older than the
-- platform retry window are droppable. If the ceiling is reached while every
-- entry is still replayable, the caller is told so it can archive rather than
-- silently discard a live receipt.
function PlayerProfile.recordPurchase(data: Profile, purchaseId: string, now: number): (boolean, string?)
	if data.PurchaseIds[purchaseId] ~= nil then
		return false, "already_recorded"
	end

	data.PurchaseIds[purchaseId] = now
	table.insert(data.PurchaseOrder, purchaseId)

	while #data.PurchaseOrder > PURCHASE_ID_CEILING do
		local oldest = data.PurchaseOrder[1]
		local stamped = data.PurchaseIds[oldest]
		if stamped and (now - stamped) < RECEIPT_RETRY_WINDOW then
			-- Still replayable. Do NOT evict.
			return true, "ceiling_reached_all_live"
		end
		table.remove(data.PurchaseOrder, 1)
		data.PurchaseIds[oldest] = nil
	end

	return true, nil
end

function PlayerProfile.hasPurchase(data: Profile, purchaseId: string): boolean
	return data.PurchaseIds[purchaseId] ~= nil
end

-- Forces the player's profile to disk NOW and yields until the write completes.
--
-- WHY THIS EXISTS, AND WHY ONLY FOR RECEIPTS. Normal play does not need it:
-- ProfileStore autosaves, and losing a few seconds of roll progress on a crash
-- costs the player almost nothing. A PURCHASE is different. FR-12.4 requires
-- `PurchaseGranted` to be returned only after the grant durably persists, because
-- returning it is what tells Roblox to stop retrying and keep the money. Grant
-- in memory, answer PurchaseGranted, crash before the autosave, and the player
-- has paid for something they no longer own and the platform will never re-send.
--
-- So this is the ONLY sanctioned way to make a grant durable, and the receipt
-- handler is the only caller that should need it. It YIELDS -- never call it
-- from inside `mutate`, whose mutator is required to be synchronous.
--
-- Returns false when there is no active session to save, which the caller must
-- treat as "not durable" and answer NotProcessedYet.
function PlayerProfile.saveNow(player: Player): (boolean, string?)
	local profile = active[player]
	if not profile then
		return false, "no_profile"
	end
	if not profile:IsActive() then
		return false, "profile_released"
	end

	local ok, err = pcall(function()
		profile:Save()
	end)
	if not ok then
		return false, "save_failed: " .. tostring(err)
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Migration and payload ceiling
--------------------------------------------------------------------------------

-- Reconcile() covers added keys. This chain covers shape changes it cannot.
-- Returns ok, reason -- an unmigratable profile fails closed rather than being
-- overwritten, so it stays recoverable by hand (DEVOPS_RECORD §8).
function PlayerProfile._migrate(data: Profile): (boolean, string?)
	if type(data.SchemaVersion) ~= "number" then
		return false, "missing_schema_version"
	end
	if data.SchemaVersion > TEMPLATE.SchemaVersion then
		return false, "profile_from_future_version"
	end
	if data.SchemaVersion < 1 then
		data.SchemaVersion = 1
		if type(data.Dice) ~= "table" or #data.Dice == 0 then
			data.Dice = deepCopy(TEMPLATE.Dice)
		end
	end
	-- v1 -> v2: PurchasedBudget split out of MassBudget (FR-3.6/FR-6.1). A v1
	-- die's MassBudget IS what the player paid for, so seeding one from the
	-- other is lossless and cannot inflate anyone.
	if data.SchemaVersion < 2 then
		if type(data.Dice) == "table" then
			for _, die in ipairs(data.Dice) do
				if type(die) == "table" and type(die.PurchasedBudget) ~= "number" then
					die.PurchasedBudget = die.MassBudget
				end
			end
		end
		data.SchemaVersion = 2
	end
	-- v1 is current; future steps append here, each bumping SchemaVersion.
	return true, nil
end

-- Threat T-13. Called before any explicit save so an oversized profile is
-- refused loudly rather than failing every future write silently.
function PlayerProfile.checkPayloadSize(data: Profile): (boolean, number)
	local ok, encoded = pcall(function()
		return game:GetService("HttpService"):JSONEncode(data)
	end)
	if not ok then
		return false, 0
	end
	local size = #(encoded :: string)
	return size <= PAYLOAD_CEILING_BYTES, size
end

-- STUDIO-ONLY test seam.
--
-- This writes straight into the `active` table, bypassing session locking
-- entirely -- exactly the thing this module exists to make impossible. It is
-- guarded so it errors in a live server: an unguarded version would be a
-- standing hole in the persistence boundary for the sake of a unit test
-- (threats T-10, T-26).
function PlayerProfile._injectProfileForTesting(player: Player, profile: any): ()
	if not RunService:IsStudio() then
		error("[PlayerProfile] the profile-injection seam is Studio-only", 2)
	end
	active[player] = profile
end

return PlayerProfile
