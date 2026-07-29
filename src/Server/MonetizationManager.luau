--!strict
-- MonetizationManager.luau
-- Authoritative Robux Developer Product Receipt Processor & GamePass Validator.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PassDefinitions = require(ReplicatedStorage:WaitForChild("Source"):WaitForChild("Shared"):WaitForChild("PassDefinitions"))

local MonetizationManager = {}
MonetizationManager.__index = MonetizationManager

-- Set of processed receipt IDs to guarantee idempotency (prevent double-granting)
local ProcessedReceipts = {} :: { [string]: boolean }

function MonetizationManager.Init(grantCashCallback: (player: Player, amount: number) -> ())
	MarketplaceService.ProcessReceipt = function(receiptInfo: { PlayerId: number, ProductId: number, PurchaseId: string, CurrencySpent: number })
		local purchaseKey = tostring(receiptInfo.PlayerId) .. "_" .. receiptInfo.PurchaseId
		if ProcessedReceipts[purchaseKey] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			-- Player disconnected; defer granting receipt until return
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local productData = PassDefinitions.GetByAssetId(receiptInfo.ProductId)
		if not productData then
			warn("[Monetization] Unrecognized Product ID: " .. tostring(receiptInfo.ProductId))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- Grant Developer Product Rewards
		if productData.CashReward and productData.CashReward > 0 then
			grantCashCallback(player, productData.CashReward)
			print(string.format("[Monetization] Granted %s (+$%d Cash) to %s", productData.Name, productData.CashReward, player.Name))
		end

		-- Record receipt for idempotency
		ProcessedReceipts[purchaseKey] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	print("[Monetization] MarketplaceService ProcessReceipt handler registered successfully.")
end

function MonetizationManager.UserOwnsPass(player: Player, passAssetId: number): boolean
	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passAssetId)
	end)
	return success and owns
end

return MonetizationManager
