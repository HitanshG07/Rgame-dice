--!strict
-- LeaderboardService.luau
-- Authoritative global leaderboards with log-scaled integer transforms (SRS FR-11; threats T-20, T-28).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))

local LeaderboardService = {}

--------------------------------------------------------------------------------
-- Constants & Transforms (SRS FR-11.4, Threat T-20)
--------------------------------------------------------------------------------

local CACHE_TTL_SEC = 60
local SCALE_FACTOR = 1e6
local MAX_STORED_INTEGER = 2e9 -- Well within 64-bit integer limits

export type Entry = {
	userId: number,
	name: string,
	score: number,
	rawVal: number,
	rank: number,
}

-- Logarithmic transform maps numbers up to 1e300 safely to [0, 3e8]
function LeaderboardService.transform(raw: number): number
	if not ForgeMath.isFinite(raw) or raw <= 0 then
		return 0
	end
	local val = math.floor(math.log10(raw + 1) * SCALE_FACTOR)
	if not ForgeMath.isFinite(val) or val < 0 then
		return 0
	end
	return math.min(val, MAX_STORED_INTEGER)
end

function LeaderboardService.inverseTransform(score: number): number
	if not ForgeMath.isFinite(score) or score <= 0 then
		return 0
	end
	local raw = (10 ^ (score / SCALE_FACTOR)) - 1
	if not ForgeMath.isFinite(raw) or raw < 0 then
		return 0
	end
	return raw
end

--------------------------------------------------------------------------------
-- DataStore Boards & Caching
--------------------------------------------------------------------------------

local BOARDS = {
	NetWorth = "Board_NetWorth_v1",
	HighestRoll = "Board_HighestRoll_v1",
	Ascensions = "Board_Ascensions_v1",
}

-- TWO FACTS, TWO FIELDS. `lastFetch` is when a fetch last SUCCEEDED (0 = never);
-- `inFlight` is whether one is running right now. They were one field, stamped
-- before the yield (M3) -- which stopped the 30-caller burst but also made a
-- THROTTLED first fetch look like a success, so every caller for a full TTL got
-- an empty board. `failedAt` only gates a short retry cooldown, so a failure
-- neither poisons the cache for the TTL nor lets callers hammer a throttled store.
export type BoardStatus = "ok" | "empty" | "throttled" | "loading"

type BoardCache = {
	lastFetch: number,
	failedAt: number,
	inFlight: boolean,
	status: BoardStatus,
	entries: { Entry },
}

local function newCache(): BoardCache
	return { lastFetch = 0, failedAt = 0, inFlight = false, status = "loading", entries = {} }
end

local caches: { [string]: BoardCache } = {
	NetWorth = newCache(),
	HighestRoll = newCache(),
	Ascensions = newCache(),
}

-- Minimum gap between retries after a FAILED fetch (not after a success).
local RETRY_COOLDOWN_SEC = 5

-- Test seams: a fake store and a fake clock. Calling with no arguments restores
-- the real ones and clears every cache.
local storeProvider: ((string) -> OrderedDataStore?)? = nil
local clock: () -> number = os.clock

function LeaderboardService._setTestHooks(provider: ((string) -> OrderedDataStore?)?, fakeClock: (() -> number)?): ()
	storeProvider = provider
	clock = fakeClock or os.clock
	for id in pairs(caches) do
		caches[id] = newCache()
	end
end

-- USERNAME CACHE. `GetNameFromUserIdAsync` is a web call; a 50-entry board would
-- make 50 of them on every refresh and stall the fetch. Names effectively never
-- change, so one lookup per user id per server lifetime is plenty.
local nameCache: { [number]: string } = {}
-- Ids with a lookup currently in flight. SEPARATE from `nameCache` so a pending
-- marker can never be mistaken for a resolved name and rendered on the board.
local namePending: { [number]: boolean } = {}

-- Returns the best name known RIGHT NOW, and kicks off a lookup for next time if
-- the id is still unknown. Never yields -- callers are inside a board build that
-- must not block on the network.
function LeaderboardService._resolveName(uid: number): string
	local cached = nameCache[uid]
	if cached ~= nil then
		return cached
	end

	-- CAST AT THE BOUNDARY, and only here. Roblox now types these two parameters
	-- as a BRANDED `User` rather than a plain number, so passing a UserId read
	-- from a DataStore key warns "Expected this to be 'User', but got 'number'".
	-- Verified against the live API before casting: both calls accept a plain
	-- number and return correctly, so this is a type-declaration artefact and
	-- not a call-shape defect. The cast is scoped to the argument rather than
	-- applied to `uid` itself, so the value stays a number everywhere else and
	-- the arithmetic around it keeps its checking.
	local online = Players:GetPlayerByUserId(uid :: any)
	if online ~= nil then
		nameCache[uid] = online.Name
		return online.Name
	end

	-- Placeholder now; the cache is filled for the next refresh. Guarded so
	-- repeated refreshes do not spawn duplicate lookups for the same id.
	if not namePending[uid] then
		namePending[uid] = true
		task.spawn(function()
			local ok, fetched = pcall(function()
				return Players:GetNameFromUserIdAsync(uid :: any)
			end)
			if ok and type(fetched) == "string" and #fetched > 0 then
				nameCache[uid] = fetched
			end
			-- Cleared either way: a failed lookup should be retryable on a later
			-- refresh rather than cached as permanently unknown.
			namePending[uid] = nil
		end)
	end
	return "Player " .. tostring(uid)
end

-- RETURN TYPE STATED EXPLICITLY. Inferred, this returned
-- `OrderedDataStore | nil` with the nil arm unnamed, and every caller then
-- indexed it inside a `pcall` closure -- where Luau DISCARDS the narrowing an
-- enclosing `if not store then return end` performed, because a closure may
-- outlive the branch that narrowed it. That produced "Type 'nil' does not have
-- key 'SetAsync'" and the same for 'GetSortedAsync' on code that is actually
-- guarded and actually correct.
local function getOrderedStore(boardId: string): OrderedDataStore?
	if storeProvider ~= nil then
		return storeProvider(boardId)
	end
	local dsName = BOARDS[boardId]
	if not dsName then
		return nil
	end
	return DataStoreService:GetOrderedDataStore(dsName)
end

function LeaderboardService.submitScore(player: Player, boardId: string, rawValue: number): ()
	local store = getOrderedStore(boardId)
	if store == nil then
		return
	end
	local score = LeaderboardService.transform(rawValue)
	if score <= 0 then
		return
	end

	-- BOUND TO A NON-OPTIONAL LOCAL BEFORE THE CLOSURE CAPTURES IT. A closure
	-- can outlive the branch that narrowed `store`, so Luau re-widens it to
	-- `OrderedDataStore?` inside the pcall body and reports an index on nil.
	-- Re-binding after the guard gives the closure something already narrowed.
	local ds: OrderedDataStore = store
	pcall(function()
		ds:SetAsync(tostring(player.UserId), score)
	end)
end

-- Entries plus WHY they look the way they do. "throttled" (fetch failed, retry
-- shortly) must not be painted as an empty board or as "STREAM OFFLINE" -- they
-- are different facts. A bare discriminant: NFR-5 forbids any figure here, so
-- there is deliberately no retry-after duration.
function LeaderboardService.getBoardStatus(boardId: string): ({ Entry }, BoardStatus)
	local cache = caches[boardId]
	if not cache then
		return {}, "empty"
	end

	local now = clock()
	if cache.lastFetch > 0 and (now - cache.lastFetch) < CACHE_TTL_SEC then
		return cache.entries, cache.status
	end

	-- M3 (BOARD-1): ONE fetch at a time. 30 simultaneous callers must not issue 30
	-- GetSortedAsync calls. Guarded by `inFlight`, NOT by stamping `lastFetch`.
	if cache.inFlight then
		return cache.entries, cache.status
	end
	if cache.failedAt > 0 and (now - cache.failedAt) < RETRY_COOLDOWN_SEC then
		return cache.entries, cache.status
	end

	local store = getOrderedStore(boardId)
	if store == nil then
		return cache.entries, cache.status
	end

	cache.inFlight = true

	-- Same re-bind as `submitScore`: narrowing does not survive into a closure.
	local ds: OrderedDataStore = store
	local ok, pages = pcall(function()
		return ds:GetSortedAsync(false, 50)
	end)
	-- Cleared right after the only yield; nothing below yields, so it cannot
	-- be left set.
	cache.inFlight = false

	if not ok or not pages then
		cache.failedAt = clock()
		cache.status = "throttled"
		return cache.entries, cache.status
	end

	-- `GetCurrentPage` is typed loosely, so `item.key` and `item.value` arrive as
	-- `unknown` and indexing them warns. Naming the row shape states what the
	-- DataStore contract actually returns, and the `tonumber` guards below stay
	-- exactly as they were -- this annotates the boundary, it does not trust it.
	type OrderedRow = { key: string, value: number }
	local page = pages:GetCurrentPage() :: { OrderedRow }
	local newEntries: { Entry } = {}

	for rank, item in ipairs(page) do
		local uid = tonumber(item.key) or 0
		local score = tonumber(item.value) or 0
		local raw = LeaderboardService.inverseTransform(score)

		-- THE NAME, RESOLVED INTO THE ENTRY THAT SHIPS.
		--
		-- This used to `task.spawn` a `GetNameFromUserIdAsync` and assign the
		-- result to the local `name` -- AFTER that local's value had already been
		-- copied into the entry table below. The spawned thread therefore updated
		-- a variable nobody read again, and every offline player on the board
		-- rendered permanently as "Player_1234567". A closure writing to a
		-- captured local does not reach back into a table built from it.
		--
		-- Resolved through a persistent cache instead, and the entry is written
		-- with whatever is known NOW. A name that arrives late lands in the cache
		-- and is picked up on the next refresh, which is the correct trade: the
		-- board is cached for CACHE_TTL_SEC anyway, and blocking the whole fetch
		-- on 50 sequential web calls would be far worse than one stale label.
		local entry: Entry = {
			userId = uid,
			name = LeaderboardService._resolveName(uid),
			score = score,
			rawVal = raw,
			rank = rank,
		}
		table.insert(newEntries, entry)
	end

	cache.entries = newEntries
	cache.lastFetch = clock()
	cache.failedAt = 0
	cache.status = if #newEntries > 0 then "ok" else "empty"
	return newEntries, cache.status
end

function LeaderboardService.getBoard(boardId: string): { Entry }
	local entries = LeaderboardService.getBoardStatus(boardId)
	return entries
end

-- THE PLAYER'S OWN RANK on a board, or nil if they are not on it.
--
-- The `GetLeaderboard` handler returned a HARDCODED 1 for every caller, so the
-- panel would have told every player they were first in the world. A rank the
-- server invents is worse than no rank at all.
--
-- Read from the cached page, so this costs nothing and cannot disagree with the
-- list rendered beside it. A player outside the top 50 gets nil, which the panel
-- renders as "unranked" -- honest, and the alternative (a second sorted query
-- per request) is a DataStore call on a remote an exploiter can spam (T-22).
function LeaderboardService.getPlayerRank(player: Player, boardId: string): number?
	local entries = LeaderboardService.getBoard(boardId)
	for _, entry in ipairs(entries) do
		if entry.userId == player.UserId then
			return entry.rank
		end
	end
	return nil
end

function LeaderboardService.updatePlayer(player: Player): ()
	local data = PlayerProfile.get(player)
	if not data then
		return
	end

	LeaderboardService.submitScore(player, "NetWorth", data.LifetimeCash)
	LeaderboardService.submitScore(player, "HighestRoll", data.HighestRoll)
	LeaderboardService.submitScore(player, "Ascensions", data.Ascensions)
end

return LeaderboardService
