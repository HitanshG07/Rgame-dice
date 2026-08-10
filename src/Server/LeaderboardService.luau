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

local caches: { [string]: { lastFetch: number, entries: { Entry } } } = {
	NetWorth = { lastFetch = 0, entries = {} },
	HighestRoll = { lastFetch = 0, entries = {} },
	Ascensions = { lastFetch = 0, entries = {} },
}

local function getOrderedStore(boardId: string)
	local dsName = BOARDS[boardId]
	if not dsName then
		return nil
	end
	return DataStoreService:GetOrderedDataStore(dsName)
end

function LeaderboardService.submitScore(player: Player, boardId: string, rawValue: number): ()
	local store = getOrderedStore(boardId)
	if not store then
		return
	end
	local score = LeaderboardService.transform(rawValue)
	if score <= 0 then
		return
	end

	pcall(function()
		store:SetAsync(tostring(player.UserId), score)
	end)
end

function LeaderboardService.getBoard(boardId: string): { Entry }
	local cache = caches[boardId]
	if not cache then
		return {}
	end

	local now = os.clock()
	if (now - cache.lastFetch) < CACHE_TTL_SEC and #cache.entries > 0 then
		return cache.entries
	end

	local store = getOrderedStore(boardId)
	if not store then
		return cache.entries
	end

	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 50)
	end)

	if not ok or not pages then
		return cache.entries
	end

	local page = pages:GetCurrentPage()
	local newEntries: { Entry } = {}

	for rank, item in ipairs(page) do
		local uid = tonumber(item.key) or 0
		local score = tonumber(item.value) or 0
		local raw = LeaderboardService.inverseTransform(score)

		local name = "Player_" .. tostring(uid)
		local p = Players:GetPlayerByUserId(uid)
		if p then
			name = p.Name
		else
			task.spawn(function()
				local pcallOk, fetchedName = pcall(function()
					return Players:GetNameFromUserIdAsync(uid)
				end)
				if pcallOk and type(fetchedName) == "string" then
					name = fetchedName
				end
			end)
		end

		table.insert(newEntries, {
			userId = uid,
			name = name,
			score = score,
			rawVal = raw,
			rank = rank,
		})
	end

	cache.lastFetch = now
	cache.entries = newEntries
	return newEntries
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
