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
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

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
export type Die = { Shape: string, MassBudget: number, Faces: { Face } }

export type Profile = {
	SchemaVersion: number,
	Cash: number, Gems: number, Diamonds: number,
	LifetimeCash: number, HighestRoll: number, Ascensions: number, TotalRolls: number,
	Dice: { Die },
	DieSlots: number,
	Diamond: {
		StreakStrength: number, MassCeiling: number, SlotNodes: number,
		Elements: { [string]: boolean }, Shapes: { [string]: boolean },
	},
	Upgrades: { [string]: number },
	Vault: { LastSeen: number, AccrualId: number, AvgIncomePerSec: number },
	PurchaseIds: { [string]: number },
	PurchaseOrder: { string },
	BundleOffered: boolean,
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
	SchemaVersion = 1,
	Cash = 0, Gems = 0, Diamonds = 0,
	LifetimeCash = 0, HighestRoll = 0, Ascensions = 0, TotalRolls = 0,
	Dice = {
		{
			Shape = "D6",
			MassBudget = 60,
			Faces = {
				{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
				{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
				{ Mass = 10, Element = "None" }, { Mass = 10, Element = "None" },
			},
		},
	},
	DieSlots = 1,
	Diamond = {
		StreakStrength = 0, MassCeiling = 0, SlotNodes = 0,
		Elements = { None = true },
		Shapes = { D6 = true },
	},
	Upgrades = { AutoRollSpeed = 0, VaultCapacity = 0, VaultEfficiency = 0, Luck = 0 },
	Vault = { LastSeen = 0, AccrualId = 0, AvgIncomePerSec = 0 },
	PurchaseIds = {},
	PurchaseOrder = {},
	BundleOffered = false,
	CodesRedeemed = {},
	Quests = { Slots = {}, RolledOn = 0 },
	LoginStreak = { Count = 0, LastDay = 0, ForgivenessLeft = 1 },
	LastSpin = 0,
	GroupClaimed = false,
	Settings = { Particles = true, MotionBlur = true, Music = true, SFX = true },
}

function PlayerProfile.getTemplate(): Profile
	return TEMPLATE
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
		return false, "store_not_initialised"
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

return PlayerProfile
