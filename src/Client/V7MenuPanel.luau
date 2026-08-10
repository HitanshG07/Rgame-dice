--!strict
-- V7MenuPanel.luau
-- Dedicated Full-Screen Overlay Manager for Shapes, Slots, Ascension, Shop, Boards, Quests, Vault, and Settings.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetisationCatalog = require(Shared:WaitForChild("MonetisationCatalog"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local V7MenuPanel = {}
V7MenuPanel.__index = V7MenuPanel

export type V7MenuController = {
	overlays: { [string]: Frame },
	openOverlay: (self: V7MenuController, name: string) -> (),
	closeAll: (self: V7MenuController) -> (),
}

function V7MenuPanel.new(): V7MenuController
	local player = Players.LocalPlayer
	assert(player ~= nil, "[V7MenuPanel] LocalPlayer must exist")
	local playerGui = player:WaitForChild("PlayerGui")

	local overlays: { [string]: Frame } = {}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "V7MenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = UITheme.Layer.Overlay

	-- 1. SHOP OVERLAY
	local shopOverlay, shopBody = UITheme.overlay("🛒 MONETIZATION SHOP (GAMEPASSES & PRODUCTS)")
	shopOverlay.Parent = screenGui
	overlays["shop"] = shopOverlay

	local shopGrid = Instance.new("UIGridLayout")
	shopGrid.CellSize = UDim2.fromScale(0.48, 0.44)
	shopGrid.CellPadding = UDim2.fromScale(0.02, 0.04)
	shopGrid.Parent = shopBody

	-- Dynamically render sellable passes and products from MonetisationCatalog (P-5A3)
	local sellableItems: { MonetisationCatalog.Entry } = {}

	for _, entry in pairs(MonetisationCatalog.Passes) do
		if MonetisationCatalog.isSellable(entry) then
			table.insert(sellableItems, entry)
		end
	end
	for _, entry in pairs(MonetisationCatalog.Products) do
		if MonetisationCatalog.isSellable(entry) then
			table.insert(sellableItems, entry)
		end
	end

	table.sort(sellableItems, function(a, b)
		return a.key < b.key
	end)

	for _, entry in ipairs(sellableItems) do
		local card = UITheme.panel(UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
		card.Parent = shopBody

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.fromScale(0.9, 0.3)
		titleLbl.Position = UDim2.fromScale(0.05, 0.05)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = UITheme.FontHeading
		titleLbl.Text = entry.name
		titleLbl.TextColor3 = UITheme.Colors.TextGold
		titleLbl.TextScaled = true
		titleLbl.Parent = card

		local blurbLbl = Instance.new("TextLabel")
		blurbLbl.Size = UDim2.fromScale(0.9, 0.3)
		blurbLbl.Position = UDim2.fromScale(0.05, 0.35)
		blurbLbl.BackgroundTransparency = 1
		blurbLbl.Font = UITheme.Font
		blurbLbl.Text = entry.blurb
		blurbLbl.TextColor3 = UITheme.Colors.TextPrimary
		blurbLbl.TextScaled = true
		blurbLbl.Parent = card

		local buyContainer, buyBtn = UITheme.neumorphicButton("BUY", UITheme.Colors.Gems, UDim2.fromScale(0.8, 0.25), UDim2.fromScale(0.1, 0.7))
		buyContainer.Parent = card

		local assetId = entry.assetId
		local isPass = MonetisationCatalog.Passes[entry.key] ~= nil

		local function promptPurchase()
			if assetId ~= nil then
				if isPass then
					MarketplaceService:PromptGamePassPurchase(player, assetId)
				else
					MarketplaceService:PromptProductPurchase(player, assetId)
				end
			end
		end

		buyBtn.MouseButton1Click:Connect(promptPurchase)
		buyBtn.Activated:Connect(promptPurchase)
	end

	-- 2. SHAPES OVERLAY
	local shapesOverlay, shapesBody = UITheme.overlay("🎲 DICE SHAPES & BUILD CHOICE")
	shapesOverlay.Parent = screenGui
	overlays["shapes"] = shapesOverlay

	local shapesGrid = Instance.new("UIGridLayout")
	shapesGrid.CellSize = UDim2.fromScale(0.31, 0.44)
	shapesGrid.CellPadding = UDim2.fromScale(0.02, 0.04)
	shapesGrid.Parent = shapesBody

	local shapes = {
		{ name = "D4 Volatile Sniper", desc = "4 Faces (~33% Void). High payout spikes." },
		{ name = "D6 Standard Balanced", desc = "6 Faces (~16% Void). All-round baseline." },
		{ name = "D20 Steady Grinder", desc = "20 Faces (~2.5% Void). Dominates high streak b." },
	}

	for _, sh in ipairs(shapes) do
		local card = UITheme.panel(UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
		card.Parent = shapesBody
		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.fromScale(0.9, 0.8)
		txt.Position = UDim2.fromScale(0.05, 0.1)
		txt.BackgroundTransparency = 1
		txt.Font = UITheme.FontHeading
		txt.Text = string.format("%s\n\n%s", sh.name, sh.desc)
		txt.TextColor3 = UITheme.Colors.TextGold
		txt.TextScaled = true
		txt.Parent = card
	end

	-- 3. LEADERBOARD OVERLAY
	local boardsOverlay, boardsBody = UITheme.overlay("🏆 GLOBAL LEADERBOARDS")
	boardsOverlay.Parent = screenGui
	overlays["boards"] = boardsOverlay

	local lbCard = UITheme.panel(UDim2.fromScale(0.96, 0.9), UDim2.fromScale(0.02, 0.05))
	lbCard.Parent = boardsBody
	local lbTxt = Instance.new("TextLabel")
	lbTxt.Size = UDim2.fromScale(0.9, 0.8)
	lbTxt.Position = UDim2.fromScale(0.05, 0.1)
	lbTxt.BackgroundTransparency = 1
	lbTxt.Font = UITheme.FontHeading
	lbTxt.Text = "RANK #1: @DiceKing_99 — $4.92E+28\nRANK #2: @ArcaneRoller — $1.18E+26\nRANK #3: @MythicMaster — $8.45E+24\n\nYOUR RANK: #142 (HitanshG07) — $1.84E+12"
	lbTxt.TextColor3 = UITheme.Colors.TextGold
	lbTxt.TextScaled = true
	lbTxt.Parent = lbCard

	-- 4. ASCENSION OVERLAY
	local ascendOverlay, ascendBody = UITheme.overlay("🌌 ASCENSION & DIAMOND TREE")
	ascendOverlay.Parent = screenGui
	overlays["ascend"] = ascendOverlay

	local ascendCard = UITheme.panel(UDim2.fromScale(0.96, 0.4), UDim2.fromScale(0.02, 0.05))
	ascendCard.Parent = ascendBody
	local ascendTxt = Instance.new("TextLabel")
	ascendTxt.Size = UDim2.fromScale(0.9, 0.8)
	ascendTxt.Position = UDim2.fromScale(0.05, 0.1)
	ascendTxt.BackgroundTransparency = 1
	ascendTxt.Font = UITheme.FontHeading
	ascendTxt.Text = "RESET CASH FOR PRESTIGE DIAMONDS\n\nCurrent Gain: +450 Diamonds (♦️)"
	ascendTxt.TextColor3 = UITheme.Colors.PurpleAscend
	ascendTxt.TextScaled = true
	ascendTxt.Parent = ascendCard

	-- 5. QUESTS OVERLAY
	local questsOverlay, questsBody = UITheme.overlay("📜 DAILY QUESTS & REWARDS")
	questsOverlay.Parent = screenGui
	overlays["quests"] = questsOverlay

	-- 6. VAULT OVERLAY
	local vaultOverlay, vaultBody = UITheme.overlay("⏳ OFFLINE VAULT ACCRUAL")
	vaultOverlay.Parent = screenGui
	overlays["vault"] = vaultOverlay

	local vaultCard = UITheme.panel(UDim2.fromScale(0.96, 0.4), UDim2.fromScale(0.02, 0.05))
	vaultCard.Parent = vaultBody
	local vaultTxt = Instance.new("TextLabel")
	vaultTxt.Size = UDim2.fromScale(0.9, 0.8)
	vaultTxt.Position = UDim2.fromScale(0.05, 0.1)
	vaultTxt.BackgroundTransparency = 1
	vaultTxt.Font = UITheme.FontHeading
	vaultTxt.Text = "OFFLINE EARNINGS: +$8.42B CASH\n\nAccrued during 4h 12m away."
	vaultTxt.TextColor3 = UITheme.Colors.Positive
	vaultTxt.TextScaled = true
	vaultTxt.Parent = vaultCard

	-- 7. SETTINGS OVERLAY
	local settingsOverlay, settingsBody = UITheme.overlay("⚙️ SETTINGS & PROMO CODES")
	settingsOverlay.Parent = screenGui
	overlays["settings"] = settingsOverlay

	-- 8. SLOTS OVERLAY
	local slotsOverlay, slotsBody = UITheme.overlay("⚡ DIE SLOTS MANAGEMENT")
	slotsOverlay.Parent = screenGui
	overlays["slots"] = slotsOverlay

	screenGui.Parent = playerGui

	local self: V7MenuController = setmetatable({
		overlays = overlays,
	}, V7MenuPanel) :: any

	return self
end

function V7MenuPanel:openOverlay(name: string)
	self:closeAll()
	local target = self.overlays[name]
	if target then
		target.Visible = true
	end
end

function V7MenuPanel:closeAll()
	for _, frame in pairs(self.overlays) do
		frame.Visible = false
	end
end

return V7MenuPanel
