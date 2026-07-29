--!strict
-- ServerMain.luau
-- Server-Authoritative Economy Manager & DataStore Saver for Bouncy Ball Tycoon.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeDefinitions = require(ReplicatedStorage:WaitForChild("Source"):WaitForChild("Shared"):WaitForChild("UpgradeDefinitions"))

local DATASTORE_KEY = "BouncyBallTycoon_v1"
local PlayerDataStore = nil

local dataStoreSuccess, dsInstance = pcall(function()
	return DataStoreService:GetDataStore(DATASTORE_KEY)
end)

if dataStoreSuccess and dsInstance then
	PlayerDataStore = dsInstance
else
	warn("[Server] DataStore access disabled or unpublished place — using local session memory mode.")
end

local SessionData = {} :: { [number]: any }

local DEFAULT_PROFILE = {
	Cash = 100.0,
	Prestige = 0,
	Upgrades = {
		AddBall = 1,
		RingSpin = 0,
		WidenGap = 0,
		CoinBonus = 0,
		IncreaseLuck = 0,
		RingSpikes = 0,
	},
}

local function DeepCopy(tbl: any): any
	local copy = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			copy[k] = DeepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

local function LoadPlayerData(player: Player)
	local userId = player.UserId
	local key = "Player_" .. tostring(userId)

	local success, result = false, nil
	if PlayerDataStore then
		success, result = pcall(function()
			return PlayerDataStore:GetAsync(key)
		end)
	end

	if success and result and type(result) == "table" then
		SessionData[userId] = result
		print("[Server] Successfully loaded DataStore profile for player: " .. player.Name)
	else
		SessionData[userId] = DeepCopy(DEFAULT_PROFILE)
		print("[Server] Initialized default profile for player: " .. player.Name)
	end
end

local function SavePlayerData(player: Player)
	if not PlayerDataStore then return end
	local userId = player.UserId
	local data = SessionData[userId]
	if not data then return end

	local key = "Player_" .. tostring(userId)
	local attempts = 0
	local maxAttempts = 3

	repeat
		attempts = attempts + 1
		local success, err = pcall(function()
			PlayerDataStore:SetAsync(key, data)
		end)

		if success then
			print("[Server] Saved DataStore profile for player: " .. player.Name)
			break
		else
			warn("[Server] DataStore save attempt " .. tostring(attempts) .. " failed: " .. tostring(err))
			task.wait(1.5)
		end
	until attempts >= maxAttempts
end

-- Network Remotes Initialization
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local purchaseRemote = remotesFolder:FindFirstChild("PurchaseUpgrade") :: RemoteFunction
if not purchaseRemote then
	purchaseRemote = Instance.new("RemoteFunction")
	purchaseRemote.Name = "PurchaseUpgrade"
	purchaseRemote.Parent = remotesFolder
end

purchaseRemote.OnServerInvoke = function(player: Player, upgradeId: string)
	local data = SessionData[player.UserId]
	if not data then
		return false, 0, 0, "Data not loaded"
	end

	local def = UpgradeDefinitions.Get(upgradeId)
	if not def then
		return false, 0, 0, "Invalid upgrade ID"
	end

	local currentLevel = data.Upgrades[upgradeId] or 0
	local cost = UpgradeDefinitions.CalculateCost(upgradeId, currentLevel)

	if data.Cash >= cost then
		data.Cash = data.Cash - cost
		data.Upgrades[upgradeId] = currentLevel + 1
		return true, data.Upgrades[upgradeId], data.Cash, nil
	else
		return false, currentLevel, data.Cash, "Insufficient cash"
	end
end

-- Player Session Lifecycle Connections
Players.PlayerAdded:Connect(LoadPlayerData)
Players.PlayerRemoving:Connect(function(player)
	SavePlayerData(player)
	SessionData[player.UserId] = nil
end)

-- Server Autosave Loop (Every 60 Seconds)
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			SavePlayerData(player)
		end
	end
end)

print("[Server] Bouncy Ball Tycoon Economy & DataStore Manager initialized successfully.")
