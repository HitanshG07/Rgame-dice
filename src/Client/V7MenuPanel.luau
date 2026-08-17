--!strict
-- V7MenuPanel.luau
-- Dedicated Full-Screen Overlay Manager for Shapes, Slots, Ascension, Shop, Boards, Quests, Vault, and Settings.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- The folder of generated dice solids, named the same way `DiceRenderer` names
-- it. Both read the same replicated models: the SHAPES previews show the actual
-- die a player would receive, never a stand-in.
local DICE_SOURCE = "dice_faces"

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetisationCatalog = require(Shared:WaitForChild("MonetisationCatalog"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
local SettingsCatalog = require(Shared:WaitForChild("SettingsCatalog"))
local VaultCatalog = require(Shared:WaitForChild("VaultCatalog"))
local Format = require(Shared:WaitForChild("Format"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local NetClient = require(script.Parent:WaitForChild("NetClient"))

local V7MenuPanel = {}
V7MenuPanel.__index = V7MenuPanel

export type V7MenuController = {
	overlays: { [string]: Frame },
	openOverlay: (self: V7MenuController, name: string) -> (),
	closeAll: (self: V7MenuController) -> (),
	-- THE DATA PATH. Every overlay that shows server state gets it through here.
	-- Its absence was the whole reason the menus were empty: the panels could be
	-- opened but had no method by which state could ever reach them.
	applyState: (self: V7MenuController, state: any) -> (),
	shopRefresh: ((any) -> ())?,
	-- Boards are fetched on open rather than pushed, so this takes a BOARD ID
	-- rather than a snapshot.
	boardsRefresh: ((string) -> ())?,
	activeBoard: string?,
	ascendRefresh: ((any) -> ())?,
	shapeRefresh: ((any) -> ())?,
	questRefresh: ((any) -> ())?,
	vaultRefresh: ((any) -> ())?,
	slotsRefresh: ((any) -> ())?,
	settingsRefresh: ((any) -> ())?,
	setCapability: (self: V7MenuController, name: string, present: boolean) -> (),
	_capabilities: { [string]: boolean },
	lastState: any,
}

function V7MenuPanel.new(): V7MenuController
	local player = Players.LocalPlayer
	assert(player ~= nil, "[V7MenuPanel] LocalPlayer must exist")
	local playerGui = player:WaitForChild("PlayerGui")

	local overlays: { [string]: Frame } = {}

	-- Forward-declared so closures built during construction can reach the
	-- finished controller. Assigned at the end of `new`.
	local controller: any = nil

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "V7MenuGui"
	screenGui.ResetOnSpawn = false
	-- THE INSET IS RESPECTED, and that is what centres these panels.
	--
	-- With `IgnoreGuiInset = true` the canvas starts ABOVE the Roblox topbar --
	-- measured, y = -58 on a 780px screen -- so a panel at 0.5/0.5 centres on a
	-- rectangle the player cannot fully see. It rendered with 25px above and
	-- 84px below, reading as shoved up into the corner, and no amount of
	-- arithmetic correction fixed it cleanly: four attempts each produced a
	-- different constant bias.
	--
	-- The menu is a modal DIALOG, not a full-bleed HUD. It has no reason to draw
	-- under the topbar, and respecting the inset makes the canvas equal to the
	-- visible screen -- at which point a plain 0.5/0.5 is exactly centred with
	-- no offset to compute and nothing to keep in sync on resize.
	--
	-- The HUD keeps `IgnoreGuiInset = true` deliberately: its currency bar is
	-- meant to sit flush at the very top edge.
	screenGui.IgnoreGuiInset = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = UITheme.Layer.Overlay

	-- FORWARD-DECLARED AT FUNCTION SCOPE, and this is load-bearing.
	--
	-- `refreshShop` is defined with `local function` inside a nested block that
	-- closes long before the controller table is built, so the assignment
	-- `shopRefresh = refreshShop` several hundred lines later read a DIFFERENT,
	-- undeclared name and silently stored nil. Lua does not warn about that --
	-- it is a valid read of an unassigned global-ish local -- so the shop simply
	-- never received a snapshot: measured live, `applyState` reported
	-- `shopRefresh=nil` while its siblings were functions, and none of the
	-- fourteen cards ever showed its OWNED chip.
	--
	-- Declaring the name out here makes the inner `function refreshShop(...)`
	-- assign to THIS local rather than create a new one scoped to the block.
	local refreshShop: ((any) -> ())? = nil

	-- 1. SHOP OVERLAY (Replicated from Finalized Mock Preview)
	local shopOverlay, shopBody = UITheme.overlay("Shop & Exchange")
	shopOverlay.Parent = screenGui
	overlays["shop"] = shopOverlay

	local panelContainer = shopOverlay:FindFirstChild("Panel") :: Frame?
	if panelContainer then
		-- Style panel container with dark mocha fill & gold border
		panelContainer.BackgroundColor3 = Color3.fromRGB(26, 22, 20)
		local existingStroke = panelContainer:FindFirstChildOfClass("UIStroke")
		if existingStroke then
			existingStroke.Color = Color3.fromRGB(234, 179, 8)
			existingStroke.Thickness = 2
		else
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(234, 179, 8)
			stroke.Thickness = 2
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = panelContainer
		end

		-- Style Header to match Mock Preview (~ Shop & Exchange ~)
		local header = panelContainer:FindFirstChild("Header") :: Frame?
		if header then
			header.Size = UDim2.new(1, -28, 0, 56)
			header.Position = UDim2.new(0, 14, 0, 10)
			header.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
			header.BackgroundTransparency = 0

			local hCorner = header:FindFirstChildOfClass("UICorner")
			if not hCorner then
				hCorner = Instance.new("UICorner")
				hCorner.CornerRadius = UDim.new(0, 8)
				hCorner.Parent = header
			end

			local hStroke = header:FindFirstChildOfClass("UIStroke")
			if not hStroke then
				hStroke = Instance.new("UIStroke")
				hStroke.Color = Color3.fromRGB(234, 179, 8)
				hStroke.Thickness = 1
				hStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				hStroke.Parent = header
			end

			local titleLbl = header:FindFirstChild("Title") :: TextLabel?
			if titleLbl then
				titleLbl.Text = "~ Shop & Exchange ~"
				titleLbl.TextColor3 = Color3.fromRGB(234, 179, 8)
				titleLbl.Font = Enum.Font.GothamBold
				titleLbl.TextSize = 22
			end

			local closeBtn = header:FindFirstChild("Close") :: TextButton?
			if closeBtn then
				closeBtn.Size = UDim2.new(0, 42, 0, 42)
				closeBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
				closeBtn.TextColor3 = Color3.fromRGB(234, 179, 8)
				closeBtn.TextSize = 26
				local cCorner = closeBtn:FindFirstChildOfClass("UICorner")
				if not cCorner then
					cCorner = Instance.new("UICorner")
					cCorner.CornerRadius = UDim.new(0, 6)
					cCorner.Parent = closeBtn
				end
				local cStroke = closeBtn:FindFirstChildOfClass("UIStroke")
				if not cStroke then
					cStroke = Instance.new("UIStroke")
					cStroke.Color = Color3.fromRGB(234, 179, 8)
					cStroke.Thickness = 1
					cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					cStroke.Parent = closeBtn
				end
			end
		end

		-- Category Selector Tabs Bar (Fixed on Panel, above scrolling body)
		local categoryBar = Instance.new("Frame")
		categoryBar.Name = "CategoryBar"
		categoryBar.Size = UDim2.new(1, -28, 0, 44)
		categoryBar.Position = UDim2.new(0, 14, 0, 72)
		categoryBar.BackgroundTransparency = 1
		categoryBar.Parent = panelContainer

		local categoryList = Instance.new("UIListLayout")
		categoryList.Padding = UDim.new(0, 10)
		categoryList.SortOrder = Enum.SortOrder.LayoutOrder
		categoryList.FillDirection = Enum.FillDirection.Horizontal
		categoryList.Parent = categoryBar

		-- FOUR TABS, BECAUSE THERE ARE THREE KINDS OF THING FOR SALE.
		--
		-- It was ALL / GAMEPASSES / CURRENCY, and everything that was not a pass
		-- fell into CURRENCY -- so a 24-hour Time Skip, a Luck Boost and the
		-- Starter Bundle all sat under a heading that describes none of them.
		-- Six of fourteen items were mislabelled.
		--
		-- The catalog already knows the difference: `entry.kind` is "Currency"
		-- for the gem and diamond packs and "Boost", "Bundle" or "TimeSkip" for
		-- the consumables. Reading it beats re-deriving the category from
		-- whether the key happens to live in `Passes`.
		local categories = {
			{ id = "ALL", label = "ALL ITEMS" },
			{ id = "GAMEPASS", label = "GAMEPASSES" },
			{ id = "CURRENCY", label = "CURRENCY & GEMS" },
			{ id = "BOOST", label = "BOOSTS & BUNDLES" },
		}

		local categoryButtons: { [string]: TextButton } = {}
		local itemFrames: { [string]: Frame } = {}

		local function updateCategoryFilter(catId: string)
			for id, btn in pairs(categoryButtons) do
				if id == catId then
					btn.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
					btn.TextColor3 = Color3.fromRGB(26, 22, 20)
				else
					btn.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
					btn.TextColor3 = Color3.fromRGB(212, 175, 55)
				end
			end

			for _, itemFrame in pairs(itemFrames) do
				local catTag = itemFrame:GetAttribute("Category")
				if catId == "ALL" or catTag == catId then
					itemFrame.Visible = true
				else
					itemFrame.Visible = false
				end
			end
		end

		-- WIDTH DERIVED FROM THE COUNT, not a literal tuned for three tabs.
		--
		-- It was a flat `0.32` each, which fits three across with a gutter and
		-- nothing else -- adding the fourth pushed BOOSTS & BUNDLES 260px past
		-- the panel's right edge, measured. Sharing the row means the tabs stay
		-- inside whatever the panel is, at any count, so the next category added
		-- cannot reintroduce this.
		local tabCount = #categories
		local tabGutter = 10
		local tabWidth = (1 / tabCount)

		for i, cat in ipairs(categories) do
			local tabBtn = Instance.new("TextButton")
			tabBtn.Name = "Tab_" .. cat.id
			-- The offset term reclaims this tab's share of the gutters the
			-- layout inserts between them, so the row totals exactly 100%.
			tabBtn.Size = UDim2.new(tabWidth, -(tabGutter * (tabCount - 1)) / tabCount, 1, 0)
			tabBtn.BackgroundColor3 = if cat.id == "ALL" then Color3.fromRGB(212, 175, 55) else Color3.fromRGB(36, 30, 26)
			tabBtn.BorderSizePixel = 0
			tabBtn.Font = Enum.Font.GothamBold
			tabBtn.Text = cat.label
			tabBtn.TextColor3 = if cat.id == "ALL" then Color3.fromRGB(26, 22, 20) else Color3.fromRGB(212, 175, 55)
			tabBtn.TextSize = 13
			tabBtn.TextStrokeTransparency = 1
			tabBtn.LayoutOrder = i
			tabBtn.Parent = categoryBar

			local tabCorner = Instance.new("UICorner")
			tabCorner.CornerRadius = UDim.new(0, 6)
			tabCorner.Parent = tabBtn

			local tabStroke = Instance.new("UIStroke")
			tabStroke.Color = Color3.fromRGB(212, 175, 55)
			tabStroke.Thickness = 1
			tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			tabStroke.Parent = tabBtn

			categoryButtons[cat.id] = tabBtn

			UITheme.onPressed(tabBtn, function()
				updateCategoryFilter(cat.id)
			end)
		end

		-- FULL WIDTH. The horizontal inset belongs to the padding below and to
		-- nothing else: insetting here as WELL applied it twice, so cards sat
		-- 30px from the panel edge where SHAPES sits at 16. Only the vertical
		-- offset is real, and it exists to clear the fixed category bar.
		shopBody.Position = UDim2.new(0, 0, 0, 122)
		shopBody.Size = UDim2.new(1, 0, 1, -128)

		-- SYMMETRIC, matching SHAPES. It was `PaddingLeft = 0` against
		-- `PaddingRight = 20`, so the whole grid sat 20px left of centre inside
		-- its own body -- the same asymmetry the settings panel had, and the
		-- reason both read as shifted while SHAPES did not.
		local shopPadding = Instance.new("UIPadding")
		shopPadding.PaddingTop = UDim.new(0, UITheme.Scale.SM)
		shopPadding.PaddingBottom = UDim.new(0, UITheme.Scale.LG)
		shopPadding.PaddingLeft = UDim.new(0, UITheme.Scale.LG)
		shopPadding.PaddingRight = UDim.new(0, UITheme.Scale.LG)
		shopPadding.Parent = shopBody

		-- TWO COLUMNS THAT ACTUALLY SUM TO THE ROW.
		--
		-- The cells were `0.485 scale - 8px` with a `0.03 scale` gutter, which
		-- mixes two coordinate systems in one budget: two cells plus one gutter
		-- came to 1.0 of the width MINUS 16px, so the pair drifted left of the
		-- space they were given and the right-hand column never reached the
		-- right margin.
		--
		-- Expressed as one system instead: each cell is half the row less half
		-- the gutter, so `2 * cell + gutter` is exactly the row, at any width.
		local shopGutter = UITheme.Scale.LG
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.new(0.5, -shopGutter / 2, 0, 168)
		gridLayout.CellPadding = UDim2.new(0, shopGutter, 0, shopGutter)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = shopBody

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

		local passCards: { [string]: any } = {}

		local SHOP_TIER_DETAIL: { [string]: string } = {
			VipVault = string.format(
				"Vault: +%d%% of your earning rate, capacity raised to %dh.\n"
				.. "Standard is %d%% and %dh. Stacks with Roblox Premium.",
				math.floor(VaultCatalog.VIP_EFFICIENCY_BONUS * 100 + 0.5),
				math.floor(VaultCatalog.VIP_CAPACITY_SEC / 3600),
				math.floor(VaultCatalog.BASE_EFFICIENCY * 100 + 0.5),
				math.floor(VaultCatalog.BASE_CAPACITY_SEC / 3600)),
			AutoRoll = "Rolls for you. Manual rolling is capped lower than auto.",
			UltraAutoRoll = "Raises the auto-roll speed ceiling above the standard pass.",

			-- THE OTHER FIVE, so every card carries the same three text rows.
			--
			-- Three of eight passes had small print and five did not, which is
			-- what made the shop look uneven: the cards were identical in
			-- geometry -- measured, all 405x168 -- but two of them had a third
			-- line of text and the rest had a gap where it would go.
			--
			-- EVERY FIGURE IS READ FROM THE CATALOG, never typed here. A card
			-- must not be able to advertise a multiplier or a count the server
			-- does not actually grant, and a second copy of the number would
			-- drift the first time it is tuned (L-025).
			CashX2 = string.format(
				"Multiplies Cash from every roll by %sx. Applies to the roll "
				.. "payout only, not to Gems or Diamonds.",
				tostring(MonetisationCatalog.Passes.CashX2.amount or 2)),
			DieSlots2 = string.format(
				"Adds %d slots on top of whatever your ascension count allows, "
				.. "up to the cap of %d.",
				MonetisationCatalog.Passes.DieSlots2.amount or 2,
				DiceCatalog.MAX_DIE_SLOTS),
			VipForge = string.format(
				"Re-forging costs %d%% of the standard price. Moving mass stays "
				.. "zero-sum -- this changes the fee, never the mass.",
				math.floor((MonetisationCatalog.Passes.VipForge.amount or 0.6) * 100 + 0.5)),
			StreakShield = "A Void face pays nothing but no longer resets your "
				.. "streak, so a bad roll costs you the payout and not the run.",
			StarterBundle = (function(): string
				-- Built from the bundle's actual contents so the card lists what
				-- the handler grants, in the handler's own order, rather than a
				-- prose summary that can quietly fall out of date.
				local parts: { string } = {}
				local bundle = MonetisationCatalog.Products.StarterBundle.bundle
				if type(bundle) == "table" then
					for _, grant in ipairs(bundle) do
						table.insert(parts, string.format("%d %s",
							grant.amount, tostring(grant.currency)))
					end
				end
				table.insert(parts, "1 die slot")
				return "Grants " .. table.concat(parts, ", ") .. ". One purchase only."
			end)(),
		}
		
		local function createCorner(parent: Instance, radius: number): UICorner
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, radius)
			corner.Parent = parent
			return corner
		end

		for order, entry in ipairs(sellableItems) do
			local detail = SHOP_TIER_DETAIL[entry.key]
			local isPass = MonetisationCatalog.Passes[entry.key] ~= nil
			-- CATEGORY READ FROM THE CATALOG, not inferred. A product is
			-- CURRENCY only when it actually grants currency; the boosts,
			-- bundles and time skips are consumables and say so.
			local categoryType: string
			if isPass then
				categoryType = "GAMEPASS"
			elseif entry.kind == "Currency" then
				categoryType = "CURRENCY"
			else
				categoryType = "BOOST"
			end

			local card = Instance.new("Frame")
			card.Name = "Item_" .. entry.key
			card.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
			card.BorderSizePixel = 0
			card.LayoutOrder = order
			card.Parent = shopBody
			card:SetAttribute("Category", categoryType)

			itemFrames[entry.key] = card

			createCorner(card, 10)

			local cardStroke = Instance.new("UIStroke")
			cardStroke.Name = "RowStroke"
			cardStroke.Color = if entry.owned then Color3.fromRGB(212, 175, 55) else Color3.fromRGB(70, 58, 48)
			cardStroke.Thickness = 1
			cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			cardStroke.Parent = card

			local cardPadding = Instance.new("UIPadding")
			cardPadding.PaddingTop = UDim.new(0, 12)
			cardPadding.PaddingBottom = UDim.new(0, 12)
			cardPadding.PaddingLeft = UDim.new(0, 14)
			cardPadding.PaddingRight = UDim.new(0, 14)
			cardPadding.Parent = card

			local cardList = Instance.new("UIListLayout")
			cardList.Padding = UDim.new(0, 6)
			cardList.SortOrder = Enum.SortOrder.LayoutOrder
			cardList.Parent = card

			-- Row 1: Tag Badge Frame (Border stroke, no text glow) + Title
			local tagRow = Instance.new("Frame")
			tagRow.Name = "TagRow"
			tagRow.Size = UDim2.new(1, 0, 0, 24)
			tagRow.BackgroundTransparency = 1
			tagRow.LayoutOrder = 1
			tagRow.Parent = card

			local categoryBadgeFrame = Instance.new("Frame")
			categoryBadgeFrame.Name = "CategoryBadge"
			categoryBadgeFrame.Size = UDim2.new(0, 92, 1, 0)
			categoryBadgeFrame.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
			categoryBadgeFrame.BorderSizePixel = 0
			categoryBadgeFrame.Parent = tagRow
			createCorner(categoryBadgeFrame, 4)

			local catStroke = Instance.new("UIStroke")
			catStroke.Color = Color3.fromRGB(212, 175, 55)
			catStroke.Thickness = 1
			catStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			catStroke.Parent = categoryBadgeFrame

			local categoryLabel = Instance.new("TextLabel")
			categoryLabel.Name = "Label"
			categoryLabel.Size = UDim2.fromScale(1, 1)
			categoryLabel.BackgroundTransparency = 1
			categoryLabel.Font = Enum.Font.Code
			categoryLabel.Text = categoryType
			categoryLabel.TextColor3 = Color3.fromRGB(212, 175, 55)
			categoryLabel.TextSize = 11
			categoryLabel.TextStrokeTransparency = 1
			categoryLabel.Parent = categoryBadgeFrame

			local titleLbl = Instance.new("TextLabel")
			titleLbl.Name = "Title"
			titleLbl.Size = UDim2.new(1, -100, 1, 0)
			titleLbl.Position = UDim2.new(0, 100, 0, 0)
			titleLbl.BackgroundTransparency = 1
			titleLbl.Font = Enum.Font.GothamBold
			titleLbl.Text = entry.name
			titleLbl.TextColor3 = Color3.fromRGB(245, 239, 230)
			titleLbl.TextSize = 17
			titleLbl.TextStrokeTransparency = 1
			titleLbl.TextXAlignment = Enum.TextXAlignment.Left
			titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
			titleLbl.Parent = tagRow

			-- Row 2: Blurb (Matte Cream, NO glow)
			local blurbLbl = Instance.new("TextLabel")
			blurbLbl.Name = "Blurb"
			blurbLbl.Size = UDim2.new(1, 0, 0, 34)
			blurbLbl.BackgroundTransparency = 1
			blurbLbl.Font = Enum.Font.Gotham
			blurbLbl.Text = entry.blurb
			blurbLbl.TextColor3 = Color3.fromRGB(245, 239, 230)
			blurbLbl.TextSize = 15
			blurbLbl.TextStrokeTransparency = 1
			blurbLbl.TextWrapped = true
			blurbLbl.TextXAlignment = Enum.TextXAlignment.Left
			blurbLbl.TextYAlignment = Enum.TextYAlignment.Top
			blurbLbl.LayoutOrder = 2
			blurbLbl.Parent = card

			-- Row 3: Detail (Matte Brass Gold, NO glow)
			if detail ~= nil then
				local fine = Instance.new("TextLabel")
				fine.Name = "TierDetail"
				fine.Size = UDim2.new(1, 0, 0, 24)
				fine.BackgroundTransparency = 1
				fine.Font = Enum.Font.Code
				fine.Text = detail
				fine.TextColor3 = Color3.fromRGB(212, 175, 55)
				fine.TextSize = 11
				fine.TextStrokeTransparency = 1
				fine.TextWrapped = true
				fine.TextXAlignment = Enum.TextXAlignment.Left
				fine.TextYAlignment = Enum.TextYAlignment.Top
				fine.LayoutOrder = 3
				fine.Parent = card
			end

			-- Row 4: Action Control
			local actionRow = Instance.new("Frame")
			actionRow.Name = "ActionRow"
			actionRow.Size = UDim2.new(1, 0, 0, 38)
			actionRow.BackgroundTransparency = 1
			actionRow.LayoutOrder = 4
			actionRow.Parent = card

			local ownedPill = Instance.new("TextLabel")
			ownedPill.Name = "OwnedPill"
			ownedPill.Size = UDim2.fromScale(1, 1)
			ownedPill.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
			ownedPill.BorderSizePixel = 0
			ownedPill.Font = Enum.Font.GothamBold
			ownedPill.Text = "OWNED"
			ownedPill.TextColor3 = Color3.fromRGB(160, 148, 140)
			ownedPill.TextSize = 14
			ownedPill.TextStrokeTransparency = 1
			ownedPill.Visible = false
			ownedPill.Parent = actionRow

			createCorner(ownedPill, 6)

			local pillStroke = Instance.new("UIStroke")
			pillStroke.Color = Color3.fromRGB(48, 40, 36)
			pillStroke.Thickness = 1
			pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			pillStroke.Parent = ownedPill

			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "BuyButton"
			buyBtn.Size = UDim2.fromScale(1, 1)
			buyBtn.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
			buyBtn.BorderSizePixel = 0
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.Text = "BUY"
			buyBtn.TextColor3 = Color3.fromRGB(26, 22, 20)
			buyBtn.TextSize = 14
			buyBtn.TextStrokeTransparency = 1
			buyBtn.Parent = actionRow

			createCorner(buyBtn, 6)

			local btnStroke = Instance.new("UIStroke")
			btnStroke.Color = Color3.fromRGB(212, 175, 55)
			btnStroke.Thickness = 1
			btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			btnStroke.Parent = buyBtn

			local assetId = entry.assetId

			local function promptPurchase()
				if assetId == nil then
					blurbLbl.Text = "Not available yet."
					return
				end
				local ok, err
				if isPass then
					ok, err = pcall(MarketplaceService.PromptGamePassPurchase,
						MarketplaceService, player, assetId)
				else
					ok, err = pcall(MarketplaceService.PromptProductPurchase,
						MarketplaceService, player, assetId)
				end
				if not ok then
					warn(string.format("[V7MenuPanel] purchase prompt failed for %s: %s",
						entry.key, tostring(err)))
					blurbLbl.Text = "Could not open the purchase window."
					blurbLbl.TextColor3 = UITheme.Colors.Negative
				end
			end

			UITheme.onPressed(buyBtn, promptPurchase)

			if isPass then
				passCards[entry.key] = {
					button = buyBtn, blurb = blurbLbl, baseBlurb = entry.blurb,
					pill = ownedPill, stroke = cardStroke,
				}
			end
		end

		-- Assigns the FUNCTION-SCOPE local declared at the top of `new`, not a
		-- new block-scoped one. `local function` here would shadow it and the
		-- controller would receive nil again.
		refreshShop = function(state: any)
			local owned = if type(state) == "table" and type(state.ownedPasses) == "table"
				then state.ownedPasses else {}
			for key, ui in pairs(passCards) do
				if owned[key] == true then
					ui.pill.Visible = true
					ui.button.Visible = false
					ui.blurb.Text = ui.baseBlurb
					ui.blurb.TextColor3 = UITheme.Colors.TextDim
					ui.stroke.Color = Color3.fromRGB(234, 179, 8)
				else
					ui.pill.Visible = false
					ui.button.Visible = true
					ui.button.Text = "BUY"
					UITheme.setActionEnabled(ui.button, true)
					ui.blurb.Text = ui.baseBlurb
					ui.blurb.TextColor3 = Color3.fromRGB(245, 239, 230)
					ui.stroke.Color = Color3.fromRGB(70, 58, 48)
				end
			end
		end
	end

	-- 2. SHAPES OVERLAY
	local shapesOverlay, shapesBody = UITheme.overlay("Dice Shapes")
	shapesOverlay.Parent = screenGui
	overlays["shapes"] = shapesOverlay

	-- THE UNLOCK LADDER, drawn from DiceCatalog rather than hardcoded.
	--
	-- WHAT WAS HERE BEFORE: three cards -- D4, D6, D20 -- with hand-written
	-- descriptions carrying FABRICATED statistics ("~33% Void", "~16% Void",
	-- "~2.5% Void"). Five of the eight shapes were simply absent, there was no
	-- unlock button, no way to switch, and no connection to what the player
	-- actually owned. The numbers were also wrong: they described a per-shape
	-- budget that no longer exists after the FR-6.3 balance fix.
	--
	-- Everything below is computed from the shipping catalog and the live
	-- snapshot, so it cannot drift from the server (L-026).
	UITheme.verticalStack(shapesBody, UITheme.Scale.SM, UITheme.Scale.LG)

	local shapeCards: { [string]: any } = {}

	-- THE ROTATING PREVIEWS (operator-directed: "maybe can display the dice they
	-- will be buying with an animation which displays and rotates the dice").
	--
	-- Every card owns a ViewportFrame holding the REAL solid the board throws --
	-- the same `DiceMeshBuilder` output, read and cloned, never rebuilt. This
	-- code must not touch glyph geometry: the numerals are extruded parts and
	-- their construction is frozen pending the shearing investigation (L-051).
	--
	-- ONE DRIVER FOR ALL OF THEM, and it only runs while the panel is open. A
	-- RenderStepped connection per card would be a dozen connections spinning
	-- models nobody is looking at; the loop below allocates nothing per frame
	-- (roblox_luau skill S5) and disconnects when the overlay closes.
	local previews: { { model: Model, pivot: CFrame } } = {}
	local previewConn: RBXScriptConnection? = nil

	local function stopPreviews(): ()
		if previewConn ~= nil then
			previewConn:Disconnect()
			previewConn = nil
		end
	end

	local function startPreviews(): ()
		if previewConn ~= nil or #previews == 0 then
			return
		end
		previewConn = RunService.RenderStepped:Connect(function(dt: number)
			for _, entry in ipairs(previews) do
				entry.pivot = entry.pivot * CFrame.Angles(0, dt * 0.9, 0)
				entry.model:PivotTo(entry.pivot)
			end
		end)
	end

	-- THE DRIVER FOLLOWS THE PANEL'S VISIBILITY, not the code paths that change
	-- it. Binding start/stop to `openOverlay` and `closeAll` alone missed the
	-- header's own close button, which `UITheme.overlay` wires internally and
	-- which simply sets `Visible = false` -- so closing the panel with the X left
	-- eight invisible models being pivoted every frame for the rest of the
	-- session, and the `previewConn ~= nil` guard then made reopening a no-op, so
	-- the leak never healed.
	--
	-- Watching the property is what makes this correct for EVERY way the panel
	-- can be hidden, including ones added later. A visibility-driven resource
	-- should key off visibility, not off its callers.
	local function bindPreviewLifecycle(overlay: Frame): ()
		overlay:GetPropertyChangedSignal("Visible"):Connect(function()
			if overlay.Visible then
				startPreviews()
			else
				stopPreviews()
			end
		end)
	end

	-- Builds the little turntable for one shape. Returns nil when the shape has
	-- no source model, which is not an error -- a catalog shape whose builder is
	-- missing must show an empty frame rather than a stand-in die asserting a
	-- geometry the player would not actually receive (L-041).
	local function buildShapePreview(shapeId: string, parent: Instance): ViewportFrame?
		-- The SAME folder the board renders from, resolved the same way. The
		-- solids are generated server-side at boot and replicate asynchronously,
		-- so absent is a legitimate state and not an error.
		local folder = ReplicatedStorage:FindFirstChild(DICE_SOURCE)
		if folder == nil or not folder:IsA("Folder") then
			return nil
		end
		local source = folder:FindFirstChild(shapeId)
		if source == nil or not source:IsA("Model") then
			return nil
		end

		local vp = Instance.new("ViewportFrame")
		vp.Name = "Preview"
		vp.Size = UDim2.fromOffset(56, 56)
		vp.BackgroundColor3 = UITheme.Colors.PanelDeep
		vp.BackgroundTransparency = 0.35
		vp.BorderSizePixel = 0
		vp.LayoutOrder = 0
		vp.ZIndex = 6
		vp.Parent = parent

		local vpCorner = Instance.new("UICorner")
		vpCorner.CornerRadius = UDim.new(0, UITheme.Scale.RadiusControl)
		vpCorner.Parent = vp

		local model = source:Clone()

		-- WITHOUT A PRIMARYPART THE DIE ORBITS INSTEAD OF SPINNING. `PivotTo`
		-- turns a model about its pivot, and a clone can arrive with PrimaryPart
		-- unset -- in which case the pivot is the bounding-box centre and the
		-- turntable becomes a die swinging around an empty point. The builder
		-- leaves an invisible `Pivot` part at the centroid for this.
		if model.PrimaryPart == nil then
			local pivot = model:FindFirstChild("Pivot")
			if pivot ~= nil and pivot:IsA("BasePart") then
				model.PrimaryPart = pivot
			end
		end

		-- PIVOT BEFORE PARENT. A clone sits at its authored origin and renders on
		-- the frame it is parented, so parenting first shows it wherever it
		-- happens to be for one frame (L-052).
		model:PivotTo(CFrame.new(0, 0, 0))
		model.Parent = vp

		local cam = Instance.new("Camera")
		local _, size = model:GetBoundingBox()

		-- FRAMED FROM THE BOUNDING SPHERE, NOT THE AXIS-ALIGNED EXTENT.
		--
		-- Extent is the wrong measure for a spinning object, and the D6 proved
		-- it: the operator reported it "too huge compared to the rest".
		-- Measured across all twelve solids, every bounding SPHERE is exactly
		-- 3.00 -- the builder normalises them -- while the axis-aligned extents
		-- range from 2.76 to 5.01. A cube's widest axis is its EDGE; a
		-- polyhedron's is its long diagonal, so the same physical size reports
		-- very differently. Framing on extent pulled the D6's camera 44% closer
		-- than the D20's and made it apparent-size 1.21 against everything
		-- else's ~0.68.
		--
		-- The sphere is also what the eye actually reads, because a rotating die
		-- presents every orientation in turn -- so the silhouette the viewer
		-- integrates is the sphere, not whichever axis happens to face front.
		-- Same reasoning as `measureRadius` in DiceRenderer (L-029).
		local centre = model:GetPivot().Position
		local sphere = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Pivot" then
				local r = (d.Position - centre).Magnitude + d.Size.Magnitude * 0.5
				if r > sphere then
					sphere = r
				end
			end
		end
		-- Falls back to the extent if a model somehow has no measurable parts,
		-- so a preview is never framed at distance zero.
		if sphere <= 0 then
			sphere = math.max(size.X, size.Y, size.Z) * 0.5
		end
		-- 2.9x rather than 3.6x. The multiplier was tuned against extents that
		-- averaged ~4.8, and a sphere of 3.0 is a smaller number for the same
		-- physical die -- so keeping 3.6 would have made every preview uniformly
		-- correct and uniformly too small. This restores the framing the good
		-- tiles already had, now applied to all twelve equally.
		local distance = math.max(2.2, sphere * 2.9)

		-- THE ELEVATION FOLLOWS THE SHAPE'S FLATNESS.
		--
		-- One fixed angle suited the chunky solids and failed the flat ones: the
		-- D2 is a coin, and viewed from a low angle it presented its EDGE -- a
		-- gold sliver that reads as a bar, not a die. Its numbered face, the whole
		-- point of the preview, was pointing away from the camera.
		--
		-- `flatness` is the ratio of the thinnest axis to the widest: about 1.0
		-- for a D20 and near 0.2 for the coin. Flat shapes get a steeper, more
		-- top-down camera so their face is what the player sees; round ones keep
		-- the three-quarter view that shows a die's corners best.
		local thinnest = math.min(size.X, size.Y, size.Z)
		local widest = math.max(size.X, size.Y, size.Z)
		local flatness = if widest > 0 then thinnest / widest else 1
		-- 0.42 of the distance at flatness 1 (three-quarter), rising toward 1.35
		-- (steeply overhead) as the solid approaches a disc.
		local elevation = 0.42 + (1 - math.clamp(flatness, 0, 1)) * 0.93
		local ground = math.max(0.18, 1 - (1 - math.clamp(flatness, 0, 1)) * 0.72)

		cam.CFrame = CFrame.new(
			Vector3.new(distance * 0.55 * ground, distance * elevation, distance * 0.72 * ground),
			Vector3.new(0, 0, 0))
		cam.FieldOfView = 40
		cam.Parent = vp
		vp.CurrentCamera = cam

		table.insert(previews, { model = model, pivot = CFrame.new(0, 0, 0) })
		return vp
	end

	-- Server refusal codes rendered as sentences. The server sends an enumerated
	-- code and never prose (NFR-5, T-7), so the wording lives here.
	local SHAPE_REFUSAL: { [string]: string } = {
		insufficient_funds = string.format("Needs %d diamonds",
			DiceCatalog.SHAPE_CHANGE_DIAMOND_COST),
		not_unlocked = "Unlock the shape before it",
		invalid_request = "Cannot switch to that",
		profile_unavailable = "Still loading -- try again",
		rate_limited = "Slow down a moment",
		throttled = "Slow down a moment",
	}

	-- Refusals specific to buying ANOTHER die of a shape, which fails for
	-- different reasons than switching to one.
	local ADD_DIE_REFUSAL: { [string]: string } = {
		insufficient_funds = "Not enough Cash",
		invalid_request = "At your die limit -- ascend to raise it",
		not_unlocked = "Unlock this shape first",
		profile_unavailable = "Still loading -- try again",
		rate_limited = "Slow down a moment",
		throttled = "Slow down a moment",
	}

	for rung, shapeId in ipairs(DiceCatalog.getUnlockOrder()) do
		local def = DiceCatalog.getShape(shapeId)
		if def ~= nil then
			-- THE CARD IS NOW A LAID-OUT ROW, and that is the whole fix for this
			-- panel. Previously the status label spanned x 0.44-0.66 while the
			-- action button began at x 0.585 -- a hard 7.5% overlap, which is why
			-- the operator's screenshot shows "OWNED" printed straight through
			-- "USE 5<>". Two hand-picked fractions collided and nothing in the code
			-- could notice. Here the preview, the text and the actions are three
			-- tracks of one horizontal layout, so they cannot overlap whatever the
			-- text turns out to say.
			local card, content = UITheme.card(UITheme.Scale.RowHeight)
			card.Name = "Shape_" .. shapeId
			card.LayoutOrder = rung
			card.Parent = shapesBody

			local row, textCol, actions = UITheme.listRow(
				UITheme.Scale.RowHeight - UITheme.Scale.SM * 2)
			row.Parent = content

			-- The turntable leads the row, so the player sees the die before the
			-- words describing it.
			local preview = buildShapePreview(shapeId, row)
			if preview ~= nil then
				preview.LayoutOrder = 0
			end

			local title = UITheme.textLine(
				string.format("%s   %d faces", shapeId, def.faceCount),
				UITheme.Scale.TextHeading, UITheme.Colors.TextGold, UITheme.FontHeading)
			title.LayoutOrder = 1
			title.Parent = textCol

			-- The honest character line. Fewer faces means the same mass sits on
			-- fewer of them, so payouts spike and Voids are frequent; more faces
			-- means the reverse. This is a DESCRIPTION of the trade, never a
			-- ranking -- the balance sweep shows low face counts genuinely win at
			-- low Streak Strength.
			local character: string
			if def.faceCount <= 3 then
				character = "Sniper - huge spikes, frequent Voids"
			elseif def.faceCount <= 8 then
				character = "Balanced - moderate spikes and Voids"
			else
				character = "Grinder - steady income, rare Voids"
			end
			local sub = UITheme.textLine(character, UITheme.Scale.TextSmall,
				UITheme.Colors.TextDim)
			sub.LayoutOrder = 2
			sub.Parent = textCol

			-- STATE AS A CHIP, not as loose coloured text beside a button. The
			-- refusal messages land here too, which is why it is a pill rather
			-- than a bare word: a sentence in a chip still reads as status.
			local status = UITheme.statusPill("", UITheme.Colors.TextDim)
			status.Name = "Status"
			status.LayoutOrder = 1
			status.Parent = actions

			local btn = UITheme.actionButton("", "secondary", UITheme.Colors.Cash)
			btn.Name = "Use"
			btn.LayoutOrder = 2
			btn.Parent = actions

			-- BUY ANOTHER DIE OF THIS SHAPE (operator decision, 2026-08-13: "in
			-- shape we need to add options to buy multiple of the same dice - this
			-- helps progression").
			--
			-- Deliberately NOT a schema change. Ownership stays a boolean per
			-- shape; what a repeat purchase buys is another DIE on the board. The
			-- alternative -- turning `Diamond.Shapes` into counts -- would have
			-- meant migrating every live profile to represent something the player
			-- cannot see, since what they actually want is more dice.
			--
			-- Shares the SLOT price curve and the ascension cap rather than having
			-- its own: "buy a second D6" and "buy one more die" are the same
			-- transaction, and two price tables would drift (L-025).
			local addBtn = UITheme.actionButton("", "primary", UITheme.Colors.Positive)
			addBtn.Name = "AddDie"
			addBtn.Visible = false
			addBtn.LayoutOrder = 3
			addBtn.Parent = actions

			UITheme.onPressed(addBtn, function()
				local entry = shapeCards[shapeId]
				UITheme.setActionEnabled(addBtn, false)
				task.spawn(function()
					local result = NetClient.addDieSlot(shapeId)
					if not result.ok and entry ~= nil then
						UITheme.setPill(entry.status,
							ADD_DIE_REFUSAL[tostring(result.reason)]
								or "Cannot add a die right now.",
							UITheme.Colors.Negative)
					end
					UITheme.setActionEnabled(addBtn, true)
				end)
			end)

			UITheme.onPressed(btn, function()
				local entry = shapeCards[shapeId]
				local owned = entry and entry.owned
				UITheme.setActionEnabled(btn, false)
				task.spawn(function()
					local result
					if owned then
						-- Switching costs Diamonds and is freely reversible (FR-6.1).
						result = NetClient.setShape(1, shapeId)
					else
						-- Unlock. BuyDiamondNode carries shape ids too; the server
						-- prices them in Cash and enforces the ladder order.
						result = NetClient.buyDiamondNode(shapeId)
					end
					-- A REFUSAL HAS TO SHOW. Pressing USE with too few Diamonds used
					-- to do nothing at all: no movement, no message, no clue. The
					-- next snapshot repaints the row, so this note is transient by
					-- construction and cannot linger as a stale claim.
					if not result.ok and entry ~= nil then
						UITheme.setPill(entry.status,
							SHAPE_REFUSAL[tostring(result.reason)] or "Not right now.",
							UITheme.Colors.Negative)
					end
					UITheme.setActionEnabled(btn, true)
				end)
			end)

			shapeCards[shapeId] = {
				card = card, status = status, button = btn,
				addButton = addBtn,
				owned = false, rung = rung,
			}
		end
	end

	-- Bound AFTER the cards exist, so the first reveal has previews to drive.
	bindPreviewLifecycle(shapesOverlay)

	-- Redraws every rung from a snapshot. Called on each StateSync, so the panel
	-- is correct whether it is open or not.
	local function refreshShapes(state: any)
		if type(state) ~= "table" then
			return
		end
		local ownedMap = (state.diamondTree and state.diamondTree.Shapes) or {}
		local wornMap = (state.diamondTree and state.diamondTree.ShapesEquipped) or {}
		local currentShape = state.dice and state.dice[1] and state.dice[1].Shape
		local cash = tonumber(state.cash) or 0
		local diamonds = tonumber(state.diamonds) or 0
		local switchCost = DiceCatalog.SHAPE_CHANGE_DIAMOND_COST

		-- Buying another die of an owned shape uses the SLOT price and the SLOT
		-- cap, so the figures here are the same ones the SLOTS panel shows.
		local slots = tonumber(state.dieSlots) or 1
		local ascensions = tonumber(state.ascensions) or 0
		local addCost = DiceCatalog.dieSlotCost(slots, ascensions)

		for shapeId, entry in pairs(shapeCards) do
			local owned = ownedMap[shapeId] == true

			-- The +1 DIE button appears only on shapes the player OWNS, since the
			-- server refuses a shape they have not unlocked.
			if entry.addButton ~= nil then
				entry.addButton.Visible = owned
				if owned then
					if addCost == nil then
						-- At the die limit. Shown rather than hidden, so the ceiling
						-- is legible and the player knows ascending raises it.
						entry.addButton.Text = "MAX"
						UITheme.setActionEnabled(entry.addButton, false)
					else
						entry.addButton.Text = "+1 die   $" .. Format.formatNumber(addCost)
						UITheme.setActionEnabled(entry.addButton, cash >= addCost)
					end
				end
			end
			entry.owned = owned
			local cost = DiceCatalog.getUnlockCost(shapeId) or 0
			local allowed = DiceCatalog.canUnlock(shapeId, ownedMap)

			if shapeId == currentShape then
				UITheme.setPill(entry.status, "IN USE", UITheme.Colors.TextGold)
				entry.button.Text = "Equipped"
				UITheme.setActionEnabled(entry.button, false)
			elseif owned then
				-- THE SWITCH PRICE, ON THE BUTTON.
				--
				-- This read "OWNED" and "USE" with no mention of a cost. FR-6.1
				-- charges Diamonds to change shape, so a player who owned D3 and
				-- had no Diamonds pressed USE and watched nothing happen -- the
				-- server refused, correctly, and the panel had never said there was
				-- a price to refuse over.
				--
				-- FIRST EQUIP IS FREE, so the label has to distinguish the two
				-- cases. `ShapesEquipped` comes from the snapshot rather than being
				-- inferred from ownership, because "bought" and "has been worn" are
				-- genuinely different facts and only the server knows the second.
				local firstEquip = wornMap[shapeId] ~= true
				if firstEquip then
					UITheme.setPill(entry.status, "Owned", UITheme.Colors.Positive)
					entry.button.Text = "Equip - free"
					UITheme.setActionEnabled(entry.button, true)
				else
					local affordable = diamonds >= switchCost
					UITheme.setPill(entry.status, "Owned",
						if affordable then UITheme.Colors.Positive else UITheme.Colors.TextDim)
					entry.button.Text = string.format("Equip   %d\u{2666}", switchCost)
					UITheme.setActionEnabled(entry.button, affordable)
				end
			elseif allowed then
				-- The next rung. Affordability decides whether it is pressable,
				-- but the price is shown either way so the goal is visible.
				UITheme.setPill(entry.status, "$" .. Format.formatNumber(cost),
					if cash >= cost then UITheme.Colors.Positive else UITheme.Colors.TextDim)
				entry.button.Text = "Unlock"
				UITheme.setActionEnabled(entry.button, cash >= cost)
			else
				-- Locked behind an earlier rung. Naming the prerequisite is what
				-- turns a wall into a goal.
				local prereq = DiceCatalog.getPrerequisite(shapeId)
				UITheme.setPill(entry.status, "Needs " .. tostring(prereq),
					UITheme.Colors.TextDim)
				entry.button.Text = "Locked"
				UITheme.setActionEnabled(entry.button, false)
			end
		end
	end

	-- 3. LEADERBOARD OVERLAY
	local boardsOverlay, boardsBody = UITheme.overlay("Leaderboards")
	boardsOverlay.Parent = screenGui
	overlays["boards"] = boardsOverlay

	-- THE BOARD WAS ENTIRELY FABRICATED.
	--
	-- It read `RANK #1: @DiceKing_99 - $4.92E+28` and named the operator at rank
	-- #142, all hardcoded, all invented. `GetLeaderboard` existed server-side and
	-- returned real DataStore-backed entries; nothing on the client ever called
	-- it. Three fake usernames and four fake scores, permanently on screen.
	--
	-- THREE BOARDS, because the server keeps three (FR-11) and only one of them
	-- was ever hinted at. Tabs rather than one merged list: they measure
	-- different things and a combined ranking would be meaningless.
	local BOARD_TABS: { { id: string, label: string, prefix: string } } = {
		{ id = "NetWorth", label = "NET WORTH", prefix = "$" },
		{ id = "HighestRoll", label = "BEST ROLL", prefix = "$" },
		{ id = "Ascensions", label = "ASCENSIONS", prefix = "" },
	}
	local activeBoard = "NetWorth"

	local boardTabRow = Instance.new("Frame")
	boardTabRow.Name = "BoardTabs"
	boardTabRow.Size = UDim2.fromScale(0.96, 0.08)
	boardTabRow.Position = UDim2.fromScale(0.02, 0.01)
	boardTabRow.BackgroundTransparency = 1
	boardTabRow.Parent = boardsBody

	local boardTabLayout = Instance.new("UIListLayout")
	boardTabLayout.FillDirection = Enum.FillDirection.Horizontal
	boardTabLayout.Padding = UDim.new(0.02, 0)
	boardTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boardTabLayout.Parent = boardTabRow

	local boardRowsHolder = Instance.new("Frame")
	boardRowsHolder.Name = "Rows"
	boardRowsHolder.Size = UDim2.fromScale(0.96, 0.72)
	boardRowsHolder.Position = UDim2.fromScale(0.02, 0.11)
	boardRowsHolder.BackgroundTransparency = 1
	boardRowsHolder.Parent = boardsBody

	local boardRowsLayout = Instance.new("UIListLayout")
	boardRowsLayout.Padding = UDim.new(0, 4)
	boardRowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boardRowsLayout.Parent = boardRowsHolder

	local boardStatus = UITheme.label("Loading...", UDim2.fromScale(0.96, 0.06),
		UDim2.fromScale(0.02, 0.85), UITheme.Colors.TextDim)
	boardStatus.Name = "BoardStatus"
	boardStatus.TextScaled = true
	boardStatus.Parent = boardsBody

	-- A fixed pool of rows, refilled rather than rebuilt. The board holds at most
	-- 50 entries and rebuilding Instances on every refresh would churn the whole
	-- list every time a tab is pressed.
	local BOARD_ROW_COUNT = 12
	local boardRows: { any } = {}
	for i = 1, BOARD_ROW_COUNT do
		local row = UITheme.panel(UDim2.fromScale(1, 0), UDim2.fromScale(0, 0))
		row.Name = "BoardRow" .. tostring(i)
		row.Size = UDim2.new(1, 0, 0, 34)
		row.LayoutOrder = i
		row.Visible = false
		row.Parent = boardRowsHolder

		local rankLbl = UITheme.label("", UDim2.fromScale(0.12, 0.7), UDim2.fromScale(0.02, 0.15),
			UITheme.Colors.TextGold)
		rankLbl.Name = "Rank"
		rankLbl.TextScaled = true
		rankLbl.Parent = row

		local nameLbl = UITheme.label("", UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.16, 0.15),
			UITheme.Colors.TextPrimary)
		nameLbl.Name = "PlayerName"
		nameLbl.TextScaled = true
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Parent = row

		local scoreLbl = UITheme.label("", UDim2.fromScale(0.28, 0.7), UDim2.fromScale(0.68, 0.15),
			UITheme.Colors.Cash)
		scoreLbl.Name = "Score"
		scoreLbl.TextScaled = true
		scoreLbl.TextXAlignment = Enum.TextXAlignment.Right
		scoreLbl.Parent = row

		table.insert(boardRows, { row = row, rank = rankLbl, name = nameLbl, score = scoreLbl })
	end

	local refreshBoards: (string) -> ()

	local boardTabButtons: { [string]: TextButton } = {}
	for i, tab in ipairs(BOARD_TABS) do
		local tc, tb = UITheme.neumorphicButton(tab.label, UITheme.Colors.TextGold,
			UDim2.fromScale(0.31, 1), UDim2.fromScale(0, 0))
		tc.Name = "Tab_" .. tab.id
		tc.LayoutOrder = i
		tc.Parent = boardTabRow
		boardTabButtons[tab.id] = tb
		UITheme.onPressed(tb, function()
			-- `activeBoard` is the closure's copy, used below to discard a stale
			-- response. `controller` is assigned at the end of `new` and is what
			-- `openOverlay` reads to reopen on the tab the player last chose --
			-- nil-guarded because a click cannot happen before construction
			-- finishes, but the type checker cannot know that.
			activeBoard = tab.id
			if controller ~= nil then
				controller.activeBoard = tab.id
			end
			refreshBoards(tab.id)
		end)
	end

	-- THE FETCH. `GetLeaderboard` reads the server's CACHE and never triggers a
	-- DataStore call of its own (T-22), so pressing a tab repeatedly is cheap --
	-- but NetClient still throttles it to one call every two seconds.
	refreshBoards = function(boardId: string)
		for id, btn in pairs(boardTabButtons) do
			UITheme.setEnabled(btn, id ~= boardId)
		end

		local def
		for _, t in ipairs(BOARD_TABS) do
			if t.id == boardId then def = t end
		end
		if def == nil then
			return
		end

		boardStatus.Text = "Loading..."
		boardStatus.TextColor3 = UITheme.Colors.TextDim

		task.spawn(function()
			local entries, myRank = NetClient.getLeaderboard(boardId)
			-- Still the active tab? A player switching tabs quickly must not have
			-- an older response paint over a newer one.
			if activeBoard ~= boardId then
				return
			end

			if type(entries) ~= "table" then
				for _, ui in ipairs(boardRows) do
					ui.row.Visible = false
				end
				boardStatus.Text = "Could not load the board. Try again shortly."
				boardStatus.TextColor3 = UITheme.Colors.Negative
				return
			end

			local shown = 0
			for i, ui in ipairs(boardRows) do
				local e = entries[i]
				if type(e) ~= "table" then
					ui.row.Visible = false
				else
					shown += 1
					ui.row.Visible = true
					ui.rank.Text = "#" .. tostring(e.rank or i)
					ui.name.Text = tostring(e.name or "?")
					local raw = tonumber(e.rawVal) or 0
					ui.score.Text = def.prefix .. Format.formatNumber(raw)
					-- The player's own row, highlighted so they can find
					-- themselves without reading every line.
					local isMe = myRank ~= nil and (e.rank == myRank)
					ui.name.TextColor3 = if isMe
						then UITheme.Colors.TextGold else UITheme.Colors.TextPrimary
				end
			end

			if shown == 0 then
				-- AN EMPTY BOARD IS A REAL STATE, not an error. A fresh universe
				-- has nobody on it, and saying so is better than a spinner or a
				-- fabricated top three.
				boardStatus.Text = "No one is on this board yet -- be the first."
				boardStatus.TextColor3 = UITheme.Colors.TextDim
			elseif myRank ~= nil then
				boardStatus.Text = string.format("You are ranked #%d.", myRank)
				boardStatus.TextColor3 = UITheme.Colors.Positive
			else
				-- Honest about the limit rather than inventing a number: the
				-- server sends the top page only, so outside it the rank is
				-- genuinely unknown to us.
				boardStatus.Text = "You are not in the top " .. tostring(shown) .. " yet."
				boardStatus.TextColor3 = UITheme.Colors.TextDim
			end
		end)
	end

	-- 4. ASCENSION OVERLAY
	local ascendOverlay, ascendBody = UITheme.overlay("Ascension")
	ascendOverlay.Parent = screenGui
	overlays["ascend"] = ascendOverlay

	-- THIS PANEL LIED ABOUT THE MOST DESTRUCTIVE ACTION IN THE GAME.
	--
	-- It was a single static label reading "Current Gain: +450 Diamonds"
	-- regardless of the player's actual lifetime cash, with NO button, NO
	-- confirmation, and no statement of what ascending destroys. FR-9.4 is
	-- explicit: "The ascension screen states, before confirming, exactly what is
	-- lost and exactly what is gained." None of that existed.
	--
	-- The reward is now projected from the shared formula against the player's
	-- real LifetimeCash, and the reset is spelled out item by item behind a
	-- two-step confirm.
	local ascendReward = UITheme.label("--", UDim2.fromScale(0.94, 0.14), UDim2.fromScale(0.03, 0.03),
		UITheme.Colors.PurpleAscend)
	ascendReward.Name = "AscendReward"
	ascendReward.Font = UITheme.FontHeading
	ascendReward.TextScaled = true
	ascendReward.Parent = ascendBody

	local ascendProgress = UITheme.label("", UDim2.fromScale(0.94, 0.06), UDim2.fromScale(0.03, 0.18),
		UITheme.Colors.TextDim)
	ascendProgress.Name = "AscendProgress"
	ascendProgress.TextScaled = true
	ascendProgress.Parent = ascendBody

	-- FR-9.4: EXACTLY what is lost and EXACTLY what is gained, both stated before
	-- the player can confirm. Two columns so neither can be missed.
	local lostCard = UITheme.panel(UDim2.fromScale(0.46, 0.34), UDim2.fromScale(0.03, 0.26))
	lostCard.Name = "LostCard"
	lostCard.Parent = ascendBody

	local lostTitle = UITheme.label("YOU LOSE", UDim2.fromScale(0.9, 0.18), UDim2.fromScale(0.05, 0.05),
		UITheme.Colors.Negative)
	lostTitle.TextScaled = true
	lostTitle.Parent = lostCard

	local lostBody = UITheme.label("", UDim2.fromScale(0.9, 0.68), UDim2.fromScale(0.05, 0.26),
		UITheme.Colors.TextPrimary)
	lostBody.Name = "LostBody"
	lostBody.TextScaled = true
	lostBody.TextWrapped = true
	lostBody.TextYAlignment = Enum.TextYAlignment.Top
	lostBody.Parent = lostCard

	local keptCard = UITheme.panel(UDim2.fromScale(0.46, 0.34), UDim2.fromScale(0.51, 0.26))
	keptCard.Name = "KeptCard"
	keptCard.Parent = ascendBody

	local keptTitle = UITheme.label("YOU KEEP", UDim2.fromScale(0.9, 0.18), UDim2.fromScale(0.05, 0.05),
		UITheme.Colors.Positive)
	keptTitle.TextScaled = true
	keptTitle.Parent = keptCard

	local keptBody = UITheme.label("", UDim2.fromScale(0.9, 0.68), UDim2.fromScale(0.05, 0.26),
		UITheme.Colors.TextPrimary)
	keptBody.Name = "KeptBody"
	keptBody.TextScaled = true
	keptBody.TextWrapped = true
	keptBody.TextYAlignment = Enum.TextYAlignment.Top
	keptBody.Parent = keptCard

	-- Written from what AscensionService.ascend ACTUALLY does, not from memory.
	-- FR-9.1's list plus the three things the reset was corrected to preserve.
	lostBody.Text = "\u{2022} All Cash\n\u{2022} All Gems\n\u{2022} Cash upgrades\n"
		.. "\u{2022} Your dice, reset to one starting D2\n\u{2022} Extra die slots"
	keptBody.Text = "\u{2022} Every Diamond, plus the new ones\n\u{2022} Unlocked shapes and elements\n"
		.. "\u{2022} Diamond tree levels\n\u{2022} Gamepasses\n\u{2022} Promo codes and login streak"

	local ascendC, ascendBtn = UITheme.neumorphicButton("ASCEND", UITheme.Colors.PurpleAscend,
		UDim2.fromScale(0.44, 0.12), UDim2.fromScale(0.03, 0.64))
	ascendC.Name = "AscendButton"
	ascendC.Parent = ascendBody

	local ascendStatus = UITheme.label("", UDim2.fromScale(0.94, 0.08), UDim2.fromScale(0.03, 0.79),
		UITheme.Colors.TextDim)
	ascendStatus.Name = "AscendStatus"
	ascendStatus.TextScaled = true
	ascendStatus.TextWrapped = true
	ascendStatus.Parent = ascendBody

	local ASCEND_REFUSAL: { [string]: string } = {
		insufficient_lifetime_cash = "You have not earned enough this run yet.",
		ascension_failed = "Could not ascend. Try again.",
		profile_unavailable = "Still loading -- try again in a moment.",
		rate_limited = "Slow down a moment, then try again.",
		throttled = "Slow down a moment, then try again.",
	}

	-- TWO-STEP CONFIRM. Ascending wipes a run and cannot be undone, so a single
	-- press must not do it -- the first press arms, the second commits, and the
	-- armed state times out on its own so a stray click cannot leave the button
	-- primed for later.
	-- Forward-declared: the press handler below is built BEFORE `refreshAscend`
	-- exists and captures it as an upvalue. A `local function` declared after
	-- this point would be a DIFFERENT local and the closure would see nil.
	local refreshAscend: (any) -> ()
	-- Last ascension count seen in a snapshot, so the post-ascend repaint can
	-- state the new total without waiting for the server to tell it.
	local lastAscensions = 0

	local ascendArmed = false
	local ascendArmToken = 0

	local function disarmAscend()
		ascendArmed = false
		UITheme.setButtonText(ascendBtn, "ASCEND")
	end

	UITheme.onPressed(ascendBtn, function()
		if not ascendArmed then
			ascendArmed = true
			ascendArmToken += 1
			local token = ascendArmToken
			UITheme.setButtonText(ascendBtn, "CONFIRM?")
			ascendStatus.Text = "Press again to confirm. This cannot be undone."
			ascendStatus.TextColor3 = UITheme.Colors.Negative
			task.delay(4, function()
				if ascendArmed and ascendArmToken == token then
					disarmAscend()
					ascendStatus.Text = ""
				end
			end)
			return
		end

		disarmAscend()
		UITheme.setEnabled(ascendBtn, false)
		ascendStatus.Text = "Ascending..."
		ascendStatus.TextColor3 = UITheme.Colors.TextDim
		task.spawn(function()
			local result = NetClient.ascend()
			if result.ok then
				ascendStatus.Text = "Ascended. Your Diamonds have been granted."
				ascendStatus.TextColor3 = UITheme.Colors.Positive

				-- REPAINT IMMEDIATELY FROM THE CONFIRMED RESET.
				--
				-- OPERATOR-REPORTED: "the assencion worked but it didnt not update
				-- with real time". The server DOES push a snapshot (the handler is
				-- wrapped in `announcing`), but this panel kept showing the
				-- pre-reset projection -- "+1, earned $525K, 1 ascension" -- while
				-- the HUD already read $0. Between the profile write, the push, and
				-- an auto-roll snapshot arriving in the same window, the panel could
				-- repaint from a snapshot built before the mutation committed.
				--
				-- Rather than race it, the panel states what is now certainly true:
				-- the reset HAPPENED, so lifetime cash for the new run is zero and
				-- nothing is projected. The next genuine snapshot overwrites this
				-- with the authoritative figures; this only removes the window in
				-- which the screen contradicts itself.
				local ok, err = pcall(refreshAscend, {
					cash = 0,
					ascensions = (tonumber(lastAscensions) or 0) + 1,
				})
				if not ok then
					warn("[V7MenuPanel] post-ascend repaint failed: " .. tostring(err))
				end
			else
				local reason = tostring(result.reason or "ascension_failed")
				ascendStatus.Text = ASCEND_REFUSAL[reason] or "Could not ascend right now."
				ascendStatus.TextColor3 = UITheme.Colors.Negative
			end
			UITheme.setEnabled(ascendBtn, true)
		end)
	end)

	refreshAscend = function(state: any)
		-- CASH ON HAND -- the same figure the HUD's cash readout shows.
		--
		-- This read `lifetimeCash` first, which never resets, so the panel told a
		-- player "Earned $1.09M this run" when they had earned nothing of the sort
		-- and the projected reward only ever grew. It then read `runCash`, a
		-- separate per-run counter, which was correct but produced two internally
		-- valid figures a player could not reconcile: the HUD said $558K while this
		-- panel said $40K (operator-reported 2026-08-13).
		--
		-- Reading `cash` means the panel and the HUD are the SAME number by
		-- construction. Ascension sets cash to zero, so this reads $0 immediately
		-- afterwards, which is what the operator wanted and what makes the two
		-- impossible to contradict.
		local lifetime = if type(state) == "table" then tonumber(state.cash) or 0 else 0
		local ascensions = if type(state) == "table" then tonumber(state.ascensions) or 0 else 0
		lastAscensions = ascensions
		local projected = DiceCatalog.ascensionDiamonds(lifetime)
		local threshold = DiceCatalog.ASCEND_MIN_LIFETIME_CASH

		if projected > 0 then
			ascendReward.Text = string.format("+%s \u{2666}", Format.formatNumber(projected))
			ascendReward.TextColor3 = UITheme.Colors.PurpleAscend
			-- EARNED / TARGET (operator-requested). Showing the target even once it
			-- is met keeps the two numbers comparable across the whole run rather
			-- than the label changing shape at the threshold.
			ascendProgress.Text = string.format(
				"$%s / $%s this run  \u{00B7}  %d ascension%s so far",
				Format.formatNumber(lifetime), Format.formatNumber(threshold),
				ascensions, if ascensions == 1 then "" else "s")
			UITheme.setEnabled(ascendBtn, true)
		else
			-- Below the threshold: say how far off, rather than showing a reward
			-- that is not available or a button that silently refuses.
			ascendReward.Text = "+0 \u{2666}"
			ascendReward.TextColor3 = UITheme.Colors.TextDim
			-- Same earned / target shape as above, so the numbers do not move
			-- around when the threshold is crossed.
			ascendProgress.Text = string.format(
				"$%s / $%s this run  \u{00B7}  keep rolling to ascend",
				Format.formatNumber(lifetime), Format.formatNumber(threshold))
			UITheme.setEnabled(ascendBtn, false)
			-- Arming state must not survive the reward going away.
			if ascendArmed then
				disarmAscend()
			end
		end
	end

	-- 5. QUESTS OVERLAY
	local questsOverlay, questsBody = UITheme.overlay("Daily Quests")
	questsOverlay.Parent = screenGui
	overlays["quests"] = questsOverlay

	-- THIS OVERLAY WAS COMPLETELY EMPTY -- zero children. It opened onto nothing.
	local questsList = Instance.new("UIListLayout")
	questsList.Padding = UDim.new(0, 10)
	questsList.SortOrder = Enum.SortOrder.LayoutOrder
	questsList.Parent = questsBody

	local questRows: { any } = {}

	-- Three rows, matching the three quests the server rolls per UTC day. Built
	-- once and refilled on each snapshot rather than rebuilt, so opening the
	-- panel never rebuilds Instances mid-session.
	for i = 1, 3 do
		local row = UITheme.panel(UDim2.fromScale(1, 0), UDim2.fromScale(0, 0))
		-- Named by SLOT, not by quest id: the id changes daily but the row is a
		-- fixed position in the list, and a path that changes every UTC midnight
		-- is not an addressable path (L-037).
		row.Name = "QuestRow" .. tostring(i)
		row.Size = UDim2.new(1, 0, 0, 78)
		row.LayoutOrder = i
		row.Visible = false
		row.Parent = questsBody

		local name = UITheme.label("", UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.03, 0.1),
			UITheme.Colors.TextGold)
		name.TextScaled = true
		name.Parent = row

		local barBack = Instance.new("Frame")
		barBack.Size = UDim2.fromScale(0.5, 0.16)
		barBack.Position = UDim2.fromScale(0.03, 0.58)
		barBack.BackgroundColor3 = UITheme.Colors.ShadowDark
		barBack.BorderSizePixel = 0
		barBack.Parent = row
		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(1, 0)
		barCorner.Parent = barBack

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.fromScale(0, 1)
		barFill.BackgroundColor3 = UITheme.Colors.Cash
		barFill.BorderSizePixel = 0
		barFill.Parent = barBack
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = barFill

		local counter = UITheme.label("", UDim2.fromScale(0.14, 0.36), UDim2.fromScale(0.55, 0.32),
			UITheme.Colors.TextDim)
		counter.TextScaled = true
		counter.Parent = row

		local claimContainer, claimBtn = UITheme.neumorphicButton("CLAIM", UITheme.Colors.Positive,
			UDim2.fromScale(0.24, 0.5), UDim2.fromScale(0.72, 0.25))
		claimContainer.Name = "ClaimButton"
		claimContainer.Parent = row

		local rowState = { id = nil :: string? }
		UITheme.onPressed(claimBtn, function()
			local id = rowState.id
			if id == nil then
				return
			end
			UITheme.setEnabled(claimBtn, false)
			task.spawn(function()
				local result = NetClient.claimQuest(id)
				if result.ok then
					-- The snapshot that follows repaints this row as DONE, so the
					-- button text here is only the acknowledgement in between.
					UITheme.setButtonText(claimBtn, "PAID")
				else
					-- A refusal used to be completely silent: the reward is credited
					-- server-side and the button simply never changed, so a failed
					-- claim and a successful one looked identical.
					UITheme.setButtonText(claimBtn, "FAILED")
					task.wait(1.2)
					UITheme.setButtonText(claimBtn, "CLAIM")
					UITheme.setEnabled(claimBtn, true)
				end
			end)
		end)

		table.insert(questRows, {
			row = row, name = name, fill = barFill, counter = counter,
			button = claimBtn, state = rowState,
		})
	end

	local function refreshQuests(state: any)
		local quests = if type(state) == "table" then state.quests else nil
		for i, ui in ipairs(questRows) do
			local q = if type(quests) == "table" then quests[i] else nil
			if q == nil then
				ui.row.Visible = false
			else
				ui.row.Visible = true
				ui.state.id = q.id
				-- Human-readable from the id, so the client never carries a second
				-- copy of the quest table.
				local verb, target = string.match(tostring(q.id), "^(%a+)(%d+)$")
				ui.name.Text = if verb ~= nil
					then string.format("%s %s", string.upper(verb), target)
					else tostring(q.id)

				local prog = tonumber(q.progress) or 0
				local goal = tonumber(q.target) or 1
				ui.counter.Text = string.format("%d / %d", math.floor(prog), math.floor(goal))
				ui.fill.Size = UDim2.fromScale(math.clamp(prog / math.max(goal, 1), 0, 1), 1)

				if q.claimed then
					UITheme.setButtonText(ui.button, "DONE")
					UITheme.setEnabled(ui.button, false)
				elseif q.ready then
					UITheme.setButtonText(ui.button, "CLAIM")
					UITheme.setEnabled(ui.button, true)
				else
					UITheme.setButtonText(ui.button, "LOCKED")
					UITheme.setEnabled(ui.button, false)
				end
			end
		end
	end

	local vaultOverlay, vaultBody = UITheme.overlay("Offline Vault")
	vaultOverlay.Parent = screenGui
	overlays["vault"] = vaultOverlay

	-- THE ACCRUED AMOUNT, in the size it deserves. This is the number the player
	-- opened the panel to see.
	local vaultAmount = UITheme.label("--", UDim2.fromScale(0.94, 0.16), UDim2.fromScale(0.03, 0.04),
		UITheme.Colors.Cash)
	vaultAmount.Name = "VaultAmount"
	vaultAmount.Font = UITheme.FontHeading
	vaultAmount.TextScaled = true
	vaultAmount.Parent = vaultBody

	-- A fill bar for how much of the vault's capacity is used. Time is easier to
	-- read as a bar than as two numbers the player has to divide.
	local vaultBarBack = Instance.new("Frame")
	vaultBarBack.Name = "CapacityBar"
	vaultBarBack.Size = UDim2.fromScale(0.94, 0.035)
	vaultBarBack.Position = UDim2.fromScale(0.03, 0.22)
	vaultBarBack.BackgroundColor3 = UITheme.Colors.ShadowDark
	vaultBarBack.BorderSizePixel = 0
	vaultBarBack.Parent = vaultBody
	local vbCorner = Instance.new("UICorner")
	vbCorner.CornerRadius = UDim.new(1, 0)
	vbCorner.Parent = vaultBarBack

	local vaultBarFill = Instance.new("Frame")
	vaultBarFill.Name = "Fill"
	vaultBarFill.Size = UDim2.fromScale(0, 1)
	vaultBarFill.BackgroundColor3 = UITheme.Colors.Cash
	vaultBarFill.BorderSizePixel = 0
	vaultBarFill.Parent = vaultBarBack
	local vfCorner = Instance.new("UICorner")
	vfCorner.CornerRadius = UDim.new(1, 0)
	vfCorner.Parent = vaultBarFill

	local vaultInfo = UITheme.label("", UDim2.fromScale(0.94, 0.22), UDim2.fromScale(0.03, 0.28),
		UITheme.Colors.TextPrimary)
	vaultInfo.Name = "VaultInfo"
	vaultInfo.TextScaled = true
	vaultInfo.TextWrapped = true
	vaultInfo.Parent = vaultBody

	local claimVaultContainer, claimVaultBtn = UITheme.neumorphicButton("CLAIM",
		UITheme.Colors.Cash, UDim2.fromScale(0.44, 0.16), UDim2.fromScale(0.03, 0.54))
	claimVaultContainer.Name = "ClaimButton"
	claimVaultContainer.Parent = vaultBody

	-- BUY CAPACITY WITH GEMS -- the game's only Gems sink (FR-8; operator
	-- decision 2026-08-13, "5 gems means 1 hour of storage", +8h cap approved).
	--
	-- Sits beside CLAIM because the two are the vault's only actions and a player
	-- who has just collected is exactly the one thinking about holding more.
	-- Coloured with the Gems accent so the currency is legible before reading.
	local buyHoursContainer, buyHoursBtn = UITheme.neumorphicButton("+1 HOUR",
		UITheme.Colors.Gems, UDim2.fromScale(0.44, 0.16), UDim2.fromScale(0.53, 0.54))
	buyHoursContainer.Name = "BuyHoursButton"
	buyHoursContainer.Parent = vaultBody

	local vaultStatus = UITheme.label("", UDim2.fromScale(0.94, 0.1), UDim2.fromScale(0.03, 0.73),
		UITheme.Colors.TextDim)
	vaultStatus.Name = "ClaimStatus"
	vaultStatus.TextScaled = true
	vaultStatus.Parent = vaultBody

	-- TIER SMALL PRINT (operator-directed 2026-08-13). The panel stated capacity
	-- in hours and NOTHING about efficiency or tier -- so a player banking 50% of
	-- their rate and one banking 100% saw identical screens, with no way to learn
	-- that the difference existed. Rendered from the server's own computed
	-- efficiency and verified entitlement flags, via the shared catalog, so it
	-- cannot claim a rate the player does not have.
	local vaultTier = UITheme.smallPrint("", UDim2.fromScale(0.94, 0.12),
		UDim2.fromScale(0.03, 0.855))
	vaultTier.Name = "TierNote"
	vaultTier.Parent = vaultBody

	-- Server refusal codes as sentences. The server sends a code, never prose.
	local VAULT_REFUSAL: { [string]: string } = {
		vault_empty = "Nothing has built up yet -- come back later.",
		no_profile = "Still loading -- try again in a moment.",
		profile_unavailable = "Still loading -- try again in a moment.",
		mutate_failed = "Could not save that. Try again.",
		rate_limited = "Slow down a moment, then try again.",
		throttled = "Slow down a moment, then try again.",
		insufficient_gems = "Not enough Gems for another hour.",
		insufficient_funds = "Not enough Gems for another hour.",
		at_cap = "Your vault is already at its maximum size.",
		no_benefit = "Your VIP floor already covers more than this would add.",
		invalid_hours = "Could not buy that amount.",
		invalid_request = "Could not buy that amount.",
	}

	UITheme.onPressed(claimVaultBtn, function()
		UITheme.setEnabled(claimVaultBtn, false)
		task.spawn(function()
			local result = NetClient.claimVault(false)
			if result.ok then
				vaultStatus.Text = "Collected. Added to your Cash."
				vaultStatus.TextColor3 = UITheme.Colors.Positive
			else
				local reason = tostring(result.reason or "vault_empty")
				vaultStatus.Text = VAULT_REFUSAL[reason] or "Could not collect right now."
				vaultStatus.TextColor3 = UITheme.Colors.Negative
			end
			-- Re-enabled by the next snapshot's refresh, which also decides whether
			-- there is anything left to claim.
			UITheme.setEnabled(claimVaultBtn, true)
		end)
	end)

	UITheme.onPressed(buyHoursBtn, function()
		UITheme.setEnabled(buyHoursBtn, false)
		task.spawn(function()
			local result = NetClient.buyVaultHours(1)
			if result.ok then
				vaultStatus.Text = "Vault capacity increased by 1 hour."
				vaultStatus.TextColor3 = UITheme.Colors.Positive
			else
				local reason = tostring(result.reason or "insufficient_gems")
				vaultStatus.Text = VAULT_REFUSAL[reason] or "Could not buy capacity right now."
				vaultStatus.TextColor3 = UITheme.Colors.Negative
			end
			-- RE-ENABLED BY THE NEXT SNAPSHOT, not here. The button's caption and
			-- enabled state both depend on figures only the server knows (Gems held,
			-- hours owned, whether the cap is reached), so `refreshVault` owns them
			-- -- painting an optimistic state here is the L-042 defect.
			UITheme.setEnabled(buyHoursBtn, true)
		end)
	end)

	-- Seconds -> "3h 20m", because a vault measured in seconds is unreadable.
	local function formatDuration(seconds: number): string
		local s = math.max(0, math.floor(seconds))
		local h = math.floor(s / 3600)
		local m = math.floor((s % 3600) / 60)
		if h > 0 then
			return string.format("%dh %dm", h, m)
		end
		if m > 0 then
			return string.format("%dm", m)
		end
		return string.format("%ds", s)
	end

	local function refreshVault(state: any)
		-- THE REAL FIGURES, from the snapshot's `vault` block.
		--
		-- This used to recompute capacity on the client as `4 + level * 0.8` --
		-- a second copy of a server formula, which is precisely the drift L-025
		-- exists to prevent -- and it could not show the accrued amount AT ALL,
		-- because the snapshot did not carry one. The player learned what their
		-- vault held by claiming it.
		--
		-- `vault` is ABSENT rather than zeroed when the server has not reported,
		-- so "unknown" and "empty" stay distinguishable.
		local v = if type(state) == "table" then state.vault else nil
		if type(v) ~= "table" then
			vaultAmount.Text = "--"
			vaultAmount.TextColor3 = UITheme.Colors.TextDim
			vaultBarFill.Size = UDim2.fromScale(0, 1)
			vaultInfo.Text = "Waiting for your vault figures..."
			vaultTier.Text = ""
			UITheme.setEnabled(claimVaultBtn, false)
			UITheme.setEnabled(buyHoursBtn, false)
			return
		end

		-- THE GEMS CONTROL, painted from server figures only.
		--
		-- Three states, and each says something different: at the cap there is
		-- nothing to sell, short of Gems the price is still worth showing so the
		-- player knows what to save for, and otherwise the button carries its own
		-- cost. The cap and the owned hours both come from the snapshot -- the
		-- client never decides either (L-042).
		local ownedHours = tonumber(v.purchasedHours) or 0
		local maxHours = tonumber(v.maxPurchasedHours) or 0
		local gems = if type(state) == "table" then tonumber(state.gems) or 0 else 0
		local hourCost = VaultCatalog.gemCostForHours(1) or 0

		-- `buyableHours` is how many more hours would ACTUALLY raise capacity, not
		-- how many are left under the cap. They differ for a VIP player, whose 24h
		-- floor already exceeds every other source combined -- see
		-- OfflineService.effectiveBuyableHours.
		local buyable = tonumber(v.buyableHours) or 0

		if maxHours > 0 and ownedHours >= maxHours then
			UITheme.setButtonText(buyHoursBtn, string.format("MAX (+%dh)", math.floor(maxHours)))
			UITheme.setEnabled(buyHoursBtn, false)
		elseif buyable <= 0 then
			-- Nothing to sell. Saying "INCLUDED" rather than greying out an
			-- unexplained button is the difference between a player thinking the
			-- game is broken and understanding they already have the benefit.
			UITheme.setButtonText(buyHoursBtn, "INCLUDED")
			UITheme.setEnabled(buyHoursBtn, false)
		else
			UITheme.setButtonText(buyHoursBtn, string.format("+1 HOUR  %d\u{25C6}", hourCost))
			UITheme.setEnabled(buyHoursBtn, gems >= hourCost)
		end

		-- The tier line, from the server's computed efficiency and the
		-- entitlements it verified.
		vaultTier.Text = VaultCatalog.describeTier(
			tonumber(v.efficiency) or VaultCatalog.BASE_EFFICIENCY,
			v.hasVip == true, v.hasPremium == true)

		local unclaimed = tonumber(v.unclaimed) or 0
		local claimable = tonumber(v.claimableSeconds) or 0
		local capacity = tonumber(v.capacitySeconds) or 0
		local rate = tonumber(v.ratePerSec) or 0

		vaultAmount.Text = "$" .. Format.formatNumber(unclaimed)
		vaultAmount.TextColor3 = if unclaimed > 0
			then UITheme.Colors.Cash else UITheme.Colors.TextDim

		local frac = if capacity > 0 then math.clamp(claimable / capacity, 0, 1) else 0
		vaultBarFill.Size = UDim2.fromScale(frac, 1)
		vaultBarFill.BackgroundColor3 = if v.atCapacity == true
			then UITheme.Colors.Negative else UITheme.Colors.Cash

		if rate <= 0 then
			-- An honest empty state. The vault pays at the player's RECENT
			-- average rate, so a player who has not rolled yet has no rate and
			-- would otherwise stare at $0 with no explanation.
			vaultInfo.Text = string.format(
				"Roll a few times to set an earning rate -- your vault fills at your"
				.. " recent average.\n\nHolds up to %s.", formatDuration(capacity))
		elseif v.atCapacity == true then
			vaultInfo.Text = string.format(
				"FULL -- %s of %s stored, and it has stopped earning.\n\n"
				.. "Collect it to start filling again.",
				formatDuration(claimable), formatDuration(capacity))
		else
			vaultInfo.Text = string.format(
				"%s of %s stored, still filling.",
				formatDuration(claimable), formatDuration(capacity))
		end

		-- WHAT THE GEMS ACTUALLY BOUGHT -- which is not always what was paid for.
		--
		-- This line used to read "+8h of that is Gem-bought" unconditionally, and
		-- for a VIP player that was FALSE: their 24h floor already exceeds every
		-- other source combined, so the Gem hours contributed nothing to the
		-- capacity shown directly above. The operator spotted the contradiction
		-- immediately -- "how does this work if its still 24hrs".
		--
		-- A readout that credits a purchase with an effect it did not have is
		-- worse than saying nothing, so the two cases now read differently.
		-- `buyable <= 0` has TWO causes and they mean opposite things: the player is
		-- at the purchase cap (their Gems worked, there is simply no more to buy),
		-- or a floor is absorbing the purchase (their Gems did nothing). Reading it
		-- as only the second told a player with a working +8h that it "is not
		-- adding to it" -- the exact false claim this line was written to remove.
		-- The cap case is checked first because it is the one that means success.
		local atPurchaseCap = maxHours > 0 and ownedHours >= maxHours

		if ownedHours > 0 then
			if not atPurchaseCap and buyable <= 0 and v.hasVip == true then
				vaultInfo.Text ..= string.format(
					"\n\nYour VIP floor of %s already covers more than every other"
					.. " source combined, so your %dh of Gem-bought capacity is not"
					.. " adding to it.",
					formatDuration(VaultCatalog.VIP_CAPACITY_SEC), math.floor(ownedHours))
			else
				vaultInfo.Text ..= string.format(
					"\n\n+%dh of that is Gem-bought, out of a possible +%dh.",
					math.floor(ownedHours), math.floor(maxHours))
			end
		elseif buyable <= 0 and v.hasVip == true then
			vaultInfo.Text ..= string.format(
				"\n\nYour VIP floor of %s already covers more than every other"
				.. " source combined, so extra capacity is not worth buying.",
				formatDuration(VaultCatalog.VIP_CAPACITY_SEC))
		end

		UITheme.setEnabled(claimVaultBtn, unclaimed > 0)
		UITheme.setButtonText(claimVaultBtn, if unclaimed > 0 then "CLAIM" else "EMPTY")
	end

	-- 7. SETTINGS OVERLAY (Casino Ledger - Cozy Mocha & Gold Redesign)
	local settingsOverlay, settingsBody = UITheme.overlay("Settings")
	settingsOverlay.Parent = screenGui
	overlays["settings"] = settingsOverlay

	local settingsPanel = settingsOverlay:FindFirstChild("Panel") :: Frame?
	if settingsPanel then
		settingsPanel.BackgroundColor3 = Color3.fromRGB(26, 22, 20)
		
		local panelCorner = settingsPanel:FindFirstChildOfClass("UICorner")
		if panelCorner then
			panelCorner.CornerRadius = UDim.new(0, 14)
		end
		
		local panelStroke = settingsPanel:FindFirstChildOfClass("UIStroke")
		if panelStroke then
			panelStroke.Color = Color3.fromRGB(212, 175, 55)
			panelStroke.Thickness = 2
			panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		end

		local headerFrame = settingsPanel:FindFirstChild("Header") :: Frame?
		if headerFrame then
			headerFrame.Size = UDim2.new(1, -28, 0, 56)
			headerFrame.Position = UDim2.new(0, 14, 0, 10)
			headerFrame.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
			headerFrame.BackgroundTransparency = 0

			local headCorner = Instance.new("UICorner")
			headCorner.CornerRadius = UDim.new(0, 8)
			headCorner.Parent = headerFrame

			local headStroke = Instance.new("UIStroke")
			headStroke.Color = Color3.fromRGB(212, 175, 55)
			headStroke.Thickness = 1
			headStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			headStroke.Parent = headerFrame

			local headPadding = Instance.new("UIPadding")
			headPadding.PaddingLeft = UDim.new(0, 18)
			headPadding.PaddingRight = UDim.new(0, 18)
			headPadding.Parent = headerFrame

			local titleLabel = headerFrame:FindFirstChild("Title") :: TextLabel?
			if titleLabel then
				titleLabel.Text = "~ Settings & Options ~"
				titleLabel.TextColor3 = Color3.fromRGB(212, 175, 55)
				titleLabel.Font = Enum.Font.GothamBold
				titleLabel.TextSize = 22
				titleLabel.TextStrokeTransparency = 1
			end

			local closeBtn = headerFrame:FindFirstChild("Close") :: TextButton?
			if closeBtn then
				closeBtn.Size = UDim2.new(0, 42, 0, 42)
				closeBtn.Position = UDim2.new(1, -42, 0.5, -21)
				closeBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
				closeBtn.BackgroundTransparency = 0
				closeBtn.TextColor3 = Color3.fromRGB(212, 175, 55)
				closeBtn.Font = Enum.Font.GothamBold
				closeBtn.Text = "\u{00D7}"
				closeBtn.TextSize = 26
				closeBtn.TextStrokeTransparency = 1

				local closeCorner = Instance.new("UICorner")
				closeCorner.CornerRadius = UDim.new(0, 6)
				closeCorner.Parent = closeBtn

				local closeStroke = Instance.new("UIStroke")
				closeStroke.Color = Color3.fromRGB(212, 175, 55)
				closeStroke.Thickness = 1
				closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				closeStroke.Parent = closeBtn
			end
		end

		-- Full width for the same reason as the shop body: the horizontal inset
		-- is the padding's job, and doing it here too applied it twice.
		settingsBody.Position = UDim2.new(0, 0, 0, 74)
		settingsBody.Size = UDim2.new(1, 0, 1, -84)
	end

	-- SYMMETRIC, matching the SHAPES panel the operator holds up as correct.
	--
	-- It was `PaddingLeft = 0` against `PaddingRight = 16`, so every row sat
	-- 16px further left than it should and the scroll bar ate the difference on
	-- the right. Measured against SHAPES, whose rows inset 16/16: settings came
	-- out 14/30. Unequal padding is exactly what "too much on the left" looks
	-- like, and the asymmetry was invisible in the code because the two values
	-- are written on separate lines.
	--
	-- Read from the shared scale rather than typed, so the three panels cannot
	-- drift apart again the next time one is restyled.
	local settingsPadding = Instance.new("UIPadding")
	settingsPadding.PaddingTop = UDim.new(0, UITheme.Scale.SM)
	settingsPadding.PaddingBottom = UDim.new(0, UITheme.Scale.LG)
	settingsPadding.PaddingLeft = UDim.new(0, UITheme.Scale.LG)
	settingsPadding.PaddingRight = UDim.new(0, UITheme.Scale.LG)
	settingsPadding.Parent = settingsBody

	local settingsList = Instance.new("UIListLayout")
	settingsList.Padding = UDim.new(0, 12)
	settingsList.SortOrder = Enum.SortOrder.LayoutOrder
	settingsList.Parent = settingsBody

	local settingRows: { [string]: any } = {}

	local capabilities: { [string]: boolean } = {}

	for order, def in ipairs(SettingsCatalog.ordered()) do
		local row = Instance.new("Frame")
		row.Name = "Setting_" .. def.key
		row.Size = UDim2.new(1, 0, 0, 76)
		row.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = settingsBody

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 10)
		rowCorner.Parent = row

		local rowStroke = Instance.new("UIStroke")
		rowStroke.Name = "RowStroke"
		rowStroke.Color = Color3.fromRGB(212, 175, 55)
		rowStroke.Thickness = 1
		rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rowStroke.Parent = row

		local rowPadding = Instance.new("UIPadding")
		rowPadding.PaddingTop = UDim.new(0, 12)
		rowPadding.PaddingBottom = UDim.new(0, 12)
		rowPadding.PaddingLeft = UDim.new(0, 16)
		rowPadding.PaddingRight = UDim.new(0, 16)
		rowPadding.Parent = row

		local infoFrame = Instance.new("Frame")
		infoFrame.Name = "InfoFrame"
		infoFrame.Size = UDim2.new(1, -145, 1, 0)
		infoFrame.BackgroundTransparency = 1
		infoFrame.Parent = row

		local infoList = Instance.new("UIListLayout")
		infoList.Padding = UDim.new(0, 3)
		infoList.SortOrder = Enum.SortOrder.LayoutOrder
		infoList.Parent = infoFrame

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, 0, 0, 24)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = def.label
		label.TextColor3 = Color3.fromRGB(212, 175, 55)
		label.TextSize = 17
		label.TextStrokeTransparency = 1
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = 1
		label.Parent = infoFrame

		local blurb = Instance.new("TextLabel")
		blurb.Name = "Blurb"
		blurb.Size = UDim2.new(1, 0, 0, 26)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.Gotham
		blurb.Text = def.blurb
		blurb.TextColor3 = Color3.fromRGB(245, 239, 230)
		blurb.TextSize = 14
		blurb.TextStrokeTransparency = 1
		blurb.TextWrapped = true
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.LayoutOrder = 2
		blurb.Parent = infoFrame

		local toggleBtn = Instance.new("TextButton")
		toggleBtn.Name = "ToggleButton"
		toggleBtn.Size = UDim2.new(0, 130, 0, 40)
		toggleBtn.Position = UDim2.new(1, -130, 0.5, -20)
		toggleBtn.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
		toggleBtn.BorderSizePixel = 0
		toggleBtn.Font = Enum.Font.GothamBold
		toggleBtn.Text = "ACTIVE"
		toggleBtn.TextColor3 = Color3.fromRGB(26, 22, 20)
		toggleBtn.TextSize = 14
		toggleBtn.TextStrokeTransparency = 1
		toggleBtn.AutoButtonColor = true
		toggleBtn.Parent = row

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = toggleBtn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Name = "BtnStroke"
		btnStroke.Color = Color3.fromRGB(212, 175, 55)
		btnStroke.Thickness = 1
		btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		btnStroke.Parent = toggleBtn

		local key = def.key
		UITheme.onPressed(toggleBtn, function()
			local entry = settingRows[key]
			local current = entry ~= nil and entry.value == true
			NetClient.setSetting(key, not current)
		end)

		-- THREE STATES, NOT TWO. A setting is ON, OFF, or UNAVAILABLE, and the
		-- third is not a shade of the other two: Music and SFX control audio that
		-- does not exist yet -- every asset id is still a `DUMMY_ID_*` placeholder
		-- -- so their switches must read as locked rather than as merely off.
		--
		-- WHY THIS EXISTS AT ALL. `refreshSettings` calls
		-- `UITheme.setEnabled(entry.button, available)` to express the third
		-- state, and that helper is written for `UITheme.toggle` -- it looks for a
		-- `Knob` child, finds none on this button, and falls through to
		-- recolouring `TextColor3`. So it silently overwrote the ACTIVE colour and
		-- painted nothing legible in its place: measured live, all four rows read
		-- ACTIVE and all four were interactable, including the two that are
		-- supposed to be locked.
		--
		-- Owning the disabled paint here rather than in the shared helper keeps
		-- the new design's colours intact and stops the two fighting over the
		-- same properties.
		local function setDisplayState(active: boolean, available: boolean?)
			local usable = available ~= false
			if not usable then
				-- Locked: desaturated, and it says WHY in a word rather than
				-- relying on colour alone (ui_ux_design S3).
				toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 35, 31)
				toggleBtn.TextColor3 = Color3.fromRGB(120, 110, 100)
				toggleBtn.Text = "LOCKED"
				btnStroke.Color = Color3.fromRGB(70, 58, 48)
				toggleBtn.AutoButtonColor = false
				toggleBtn.Active = false
				toggleBtn.Interactable = false
				return
			end

			toggleBtn.AutoButtonColor = true
			toggleBtn.Active = true
			toggleBtn.Interactable = true
			if active then
				toggleBtn.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
				toggleBtn.TextColor3 = Color3.fromRGB(26, 22, 20)
				toggleBtn.Text = "ACTIVE"
				btnStroke.Color = Color3.fromRGB(212, 175, 55)
			else
				toggleBtn.BackgroundColor3 = Color3.fromRGB(48, 24, 24)
				toggleBtn.TextColor3 = Color3.fromRGB(240, 180, 180)
				toggleBtn.Text = "INACTIVE"
				btnStroke.Color = Color3.fromRGB(180, 60, 60)
			end
		end

		settingRows[key] = {
			set = setDisplayState,
			value = def.default,
			button = toggleBtn,
			blurb = blurb,
			requires = def.requires,
			baseBlurb = def.blurb,
			stroke = rowStroke,
		}
	end

	-- PROMO CODES (Casino Ledger Style)
	local codeCard = Instance.new("Frame")
	codeCard.Name = "PromoCard"
	codeCard.Size = UDim2.new(1, 0, 0, 120)
	codeCard.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	codeCard.BorderSizePixel = 0
	codeCard.LayoutOrder = 90
	codeCard.Parent = settingsBody

	local promoCorner = Instance.new("UICorner")
	promoCorner.CornerRadius = UDim.new(0, 10)
	promoCorner.Parent = codeCard

	local promoStroke = Instance.new("UIStroke")
	promoStroke.Color = Color3.fromRGB(212, 175, 55)
	promoStroke.Thickness = 1
	promoStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	promoStroke.Parent = codeCard

	local promoPad = Instance.new("UIPadding")
	promoPad.PaddingTop = UDim.new(0, 14)
	promoPad.PaddingBottom = UDim.new(0, 14)
	promoPad.PaddingLeft = UDim.new(0, 16)
	promoPad.PaddingRight = UDim.new(0, 16)
	promoPad.Parent = codeCard

	local promoList = Instance.new("UIListLayout")
	promoList.Padding = UDim.new(0, 8)
	promoList.SortOrder = Enum.SortOrder.LayoutOrder
	promoList.Parent = codeCard

	local codeTitle = Instance.new("TextLabel")
	codeTitle.Name = "PromoTitle"
	codeTitle.Size = UDim2.new(1, 0, 0, 20)
	codeTitle.BackgroundTransparency = 1
	codeTitle.Font = Enum.Font.GothamBold
	codeTitle.Text = "PROMO CODE REDEMPTION"
	codeTitle.TextColor3 = Color3.fromRGB(212, 175, 55)
	codeTitle.TextSize = 14
	codeTitle.TextStrokeTransparency = 1
	codeTitle.TextXAlignment = Enum.TextXAlignment.Left
	codeTitle.LayoutOrder = 1
	codeTitle.Parent = codeCard

	local inputRow = Instance.new("Frame")
	inputRow.Name = "InputRow"
	inputRow.Size = UDim2.new(1, 0, 0, 38)
	inputRow.BackgroundTransparency = 1
	inputRow.LayoutOrder = 2
	inputRow.Parent = codeCard

	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.Size = UDim2.new(1, -140, 1, 0)
	codeBox.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
	codeBox.BorderSizePixel = 0
	codeBox.Font = Enum.Font.Code
	codeBox.PlaceholderText = "ENTER CODE"
	codeBox.PlaceholderColor3 = Color3.fromRGB(140, 130, 120)
	codeBox.Text = ""
	codeBox.TextColor3 = Color3.fromRGB(245, 239, 230)
	codeBox.TextSize = 14
	codeBox.TextStrokeTransparency = 1
	codeBox.TextXAlignment = Enum.TextXAlignment.Left
	codeBox.ClearTextOnFocus = false
	codeBox.Parent = inputRow

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 6)
	boxCorner.Parent = codeBox

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = Color3.fromRGB(212, 175, 55)
	boxStroke.Thickness = 1
	boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	boxStroke.Parent = codeBox

	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingLeft = UDim.new(0, 12)
	boxPad.PaddingRight = UDim.new(0, 12)
	boxPad.Parent = codeBox

	local redeemBtn = Instance.new("TextButton")
	redeemBtn.Name = "RedeemButton"
	redeemBtn.Size = UDim2.new(0, 130, 1, 0)
	redeemBtn.Position = UDim2.new(1, -130, 0, 0)
	redeemBtn.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
	redeemBtn.BorderSizePixel = 0
	redeemBtn.Font = Enum.Font.GothamBold
	redeemBtn.Text = "REDEEM"
	redeemBtn.TextColor3 = Color3.fromRGB(26, 22, 20)
	redeemBtn.TextSize = 14
	redeemBtn.TextStrokeTransparency = 1
	redeemBtn.Parent = inputRow

	local redeemCorner = Instance.new("UICorner")
	redeemCorner.CornerRadius = UDim.new(0, 6)
	redeemCorner.Parent = redeemBtn

	local redeemStroke = Instance.new("UIStroke")
	redeemStroke.Color = Color3.fromRGB(212, 175, 55)
	redeemStroke.Thickness = 1
	redeemStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	redeemStroke.Parent = redeemBtn

	local codeStatus = Instance.new("TextLabel")
	codeStatus.Name = "CodeStatus"
	codeStatus.Size = UDim2.new(1, 0, 0, 20)
	codeStatus.BackgroundTransparency = 1
	codeStatus.Font = Enum.Font.Gotham
	codeStatus.Text = ""
	codeStatus.TextColor3 = Color3.fromRGB(140, 130, 120)
	codeStatus.TextSize = 13
	codeStatus.TextStrokeTransparency = 1
	codeStatus.TextXAlignment = Enum.TextXAlignment.Left
	codeStatus.LayoutOrder = 3
	codeStatus.Parent = codeCard

	local REDEEM_MESSAGE: { [string]: string } = {
		invalid_code = "That code is not recognised.",
		already_redeemed = "You have already used that code.",
		no_profile = "Your profile is still loading -- try again in a moment.",
		rate_limited = "Slow down a moment, then try again.",
		throttled = "Slow down a moment, then try again.",
	}

	local function submitCode()
		local raw = codeBox.Text
		if raw == nil or #raw == 0 then
			codeStatus.Text = "Type a code first."
			codeStatus.TextColor3 = Color3.fromRGB(140, 130, 120)
			return
		end
		UITheme.setEnabled(redeemBtn, false)
		codeStatus.Text = "Checking..."
		codeStatus.TextColor3 = Color3.fromRGB(140, 130, 120)
		task.spawn(function()
			local result = NetClient.redeemCode(raw)
			if result.ok then
				codeStatus.Text = "Redeemed. Your balance is updated."
				codeStatus.TextColor3 = UITheme.Colors.Positive
				codeBox.Text = ""
			else
				local reason = tostring(result.reason or "invalid_code")
				codeStatus.Text = REDEEM_MESSAGE[reason] or "That code could not be used."
				codeStatus.TextColor3 = UITheme.Colors.Negative
			end
			UITheme.setEnabled(redeemBtn, true)
		end)
	end

	UITheme.onPressed(redeemBtn, submitCode)
	codeBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submitCode()
		end
	end)

	local function refreshSettings(state: any)
		local settings = if type(state) == "table" then state.settings else nil
		for key, entry in pairs(settingRows) do
			local value = SettingsCatalog.read(settings, key)
			entry.value = value

			local available = entry.requires == nil
				or capabilities[entry.requires] == true

			-- AVAILABILITY IS PASSED TO THE ROW'S OWN PAINTER, not applied with
			-- `UITheme.setEnabled`. That helper is built for `UITheme.toggle`:
			-- it looks for a `Knob` child, does not find one on this button, and
			-- falls through to recolouring `TextColor3` -- which overwrote the
			-- design's ACTIVE colour and left every row reading ACTIVE and
			-- clickable, including the two gated on audio that does not exist.
			--
			-- One painter owning all three states means the state and its
			-- appearance cannot disagree.
			entry.set(value, available)

			if available then
				entry.blurb.Text = entry.baseBlurb
				entry.blurb.TextColor3 = Color3.fromRGB(245, 239, 230)
				if entry.stroke then
					entry.stroke.Color = Color3.fromRGB(212, 175, 55)
				end
			else
				entry.blurb.Text = string.format("%s - %s", entry.baseBlurb,
					SettingsCatalog.missingReason(entry.requires))
				entry.blurb.TextColor3 = Color3.fromRGB(140, 130, 120)
				if entry.stroke then
					entry.stroke.Color = Color3.fromRGB(70, 58, 48)
				end
			end
		end
	end

	-- 8. SLOTS OVERLAY
	local slotsOverlay, slotsBody = UITheme.overlay("Die Slots")
	slotsOverlay.Parent = screenGui
	overlays["slots"] = slotsOverlay

	-- Also completely empty before this. FR-1.1 allows 1 to 7 dice.
	--
	-- REBUILT AS A COMPOSED PANEL. It was three scale-positioned labels with a
	-- huge dead region below them, and the count sentence was `TextScaled` at 30%
	-- of the panel -- so on a monitor "You roll 1 die per throw" rendered at
	-- headline size while meaning nothing more than it does at body size. The
	-- count is now the headline BECAUSE IT IS THE POINT OF THE PANEL, stated as a
	-- figure rather than as a large sentence.
	UITheme.verticalStack(slotsBody, UITheme.Scale.MD, UITheme.Scale.LG)

	local slotsHeadline = UITheme.textLine("", 34, UITheme.Colors.TextGold,
		UITheme.FontHeading)
	slotsHeadline.Name = "SlotsHeadline"
	slotsHeadline.LayoutOrder = 1
	slotsHeadline.Parent = slotsBody

	local slotsInfo = UITheme.paragraph(
		"More dice means more faces resolving at once, and elements that read "
		.. "across dice have more to work with.",
		UITheme.Scale.TextBody, UITheme.Colors.TextDim)
	slotsInfo.Name = "SlotsInfo"
	slotsInfo.LayoutOrder = 2
	slotsInfo.Parent = slotsBody

	-- The action sits in its own row so the button is measured to its caption
	-- rather than stretched to 44% of the panel width.
	local slotsActionRow, slotsActionText, slotsActions =
		UITheme.listRow(UITheme.Scale.TouchTarget + UITheme.Scale.SM)
	slotsActionRow.Name = "SlotsAction"
	slotsActionRow.LayoutOrder = 3
	slotsActionRow.Parent = slotsBody

	local slotsStatus = UITheme.textLine("", UITheme.Scale.TextSmall,
		UITheme.Colors.TextDim)
	slotsStatus.Name = "SlotsStatus"
	slotsStatus.LayoutOrder = 1
	slotsStatus.Parent = slotsActionText

	local addSlotBtn = UITheme.actionButton("Add slot", "primary", UITheme.Colors.Cash)
	addSlotBtn.Name = "AddSlotButton"
	addSlotBtn.LayoutOrder = 1
	addSlotBtn.Parent = slotsActions

	local SLOT_REFUSAL: { [string]: string } = {
		insufficient_funds = "Not enough Cash for the next slot.",
		invalid_request = "You already have the maximum number of dice.",
		profile_unavailable = "Still loading -- try again in a moment.",
		rate_limited = "Slow down a moment, then try again.",
		throttled = "Slow down a moment, then try again.",
	}

	UITheme.onPressed(addSlotBtn, function()
		UITheme.setActionEnabled(addSlotBtn, false)
		task.spawn(function()
			local result = NetClient.addDieSlot()
			if result.ok then
				slotsStatus.Text = "Slot added -- a new die is on the board."
				slotsStatus.TextColor3 = UITheme.Colors.Positive
			else
				local reason = tostring(result.reason or "invalid_request")
				slotsStatus.Text = SLOT_REFUSAL[reason] or "Could not add a slot right now."
				slotsStatus.TextColor3 = UITheme.Colors.Negative
			end
			-- The next snapshot re-enables it if another slot is actually buyable.
			UITheme.setActionEnabled(addSlotBtn, true)
		end)
	end)

	local function refreshSlots(state: any)
		local slots = if type(state) == "table" then tonumber(state.dieSlots) or 1 else 1
		local cash = if type(state) == "table" then tonumber(state.cash) or 0 else 0
		local ascensions = if type(state) == "table" then tonumber(state.ascensions) or 0 else 0
		local cap = DiceCatalog.dieSlotCapFor(ascensions)
		-- THE FIGURE IS THE HEADLINE. "1 of 7 dice" states the same fact as the
		-- old sentence and states it as a quantity, which is what a player opening
		-- this panel actually came to read.
		slotsHeadline.Text = string.format("%d of %d dice", slots, cap)

		-- THE PRICE, ON THE BUTTON.
		--
		-- This read a bare "ADD SLOT" with no cost anywhere on the panel. The
		-- server charges 1000 * 2^(owned-1) and refuses when the player cannot
		-- pay -- correctly -- but the panel had never mentioned a price, so the
		-- refusal looked like a dead button. Same defect the SHAPE panel had.
		--
		-- The cost comes from the shared catalog, the same call the server makes.
		local cost = DiceCatalog.dieSlotCost(slots, ascensions)
		if cost == nil then
			-- AT THE CAP -- but WHICH cap? "MAX (7)" was shown even to a player
			-- stopped at 3 by their ascension count, which is simply untrue and
			-- hides the fact that ascending would raise it. The two cases now read
			-- differently because they are different situations: one is finished,
			-- the other has a clear next step.
			addSlotBtn.Text = string.format("At the limit (%d)", cap)
			UITheme.setActionEnabled(addSlotBtn, false)
			if cap < DiceCatalog.MAX_DIE_SLOTS then
				slotsStatus.Text = string.format(
					"Limit reached. Ascend to raise it to %d.", cap + 1)
				slotsStatus.TextColor3 = UITheme.Colors.PurpleAscend
			else
				slotsStatus.Text = "You have every die slot."
				slotsStatus.TextColor3 = UITheme.Colors.TextDim
			end
		else
			addSlotBtn.Text = "Add slot   $" .. Format.formatNumber(cost)
			UITheme.setActionEnabled(addSlotBtn, cash >= cost)
			if cash < cost then
				slotsStatus.Text = string.format("Next slot costs $%s.",
					Format.formatNumber(cost))
				slotsStatus.TextColor3 = UITheme.Colors.TextDim
			end
		end
	end

	-- NAME EVERY OVERLAY BY ITS KEY.
	--
	-- `UITheme.overlay` returns an anonymous Frame, so all eight overlays sat
	-- under one ScreenGui as siblings called "Frame" -- `V7MenuGui.Frame`
	-- resolved whichever happened to be first (the shop), and no path could name
	-- any of the other seven. Naming them here rather than at each call site
	-- keeps it impossible to add an overlay and forget.
	for key, frame in pairs(overlays) do
		frame.Name = "Overlay_" .. key
	end

	screenGui.Parent = playerGui

	local self: V7MenuController = setmetatable({
		overlays = overlays,
		-- The refresh functions are stored on the controller so `applyState` can
		-- fan a single snapshot out to every panel that needs it.
		shopRefresh = refreshShop,
		boardsRefresh = refreshBoards,
		activeBoard = "NetWorth",
		ascendRefresh = refreshAscend,
		shapeRefresh = refreshShapes,
		questRefresh = refreshQuests,
		vaultRefresh = refreshVault,
		slotsRefresh = refreshSlots,
		settingsRefresh = refreshSettings,
		_capabilities = capabilities,
		lastState = nil,
	}, V7MenuPanel) :: any

	-- Hands the finished controller to the closures built above (board tabs).
	controller = self

	return self
end

-- THE DATA PATH THAT DID NOT EXIST.
--
-- Every overlay showing server state is refreshed from one snapshot here. Called
-- on every StateSync, whether or not a panel is open: a panel that only refreshed
-- on open would show stale figures for the frame before its first update, and
-- would silently keep them if a snapshot arrived while it was already visible.
--
-- Each refresh is pcall-wrapped. One malformed field must not stop the others
-- updating -- a shop that fails to draw should not also freeze the quest list.
function V7MenuPanel:applyState(state: any)
	if type(state) ~= "table" then
		return
	end
	self.lastState = state

	-- ITERATED BY NAME, NOT BY `ipairs` OVER A LIST THAT MAY HOLD nil.
	--
	-- THIS IS THE BUG THAT UNHOOKED THE WHOLE UI. `ipairs` stops at the first
	-- nil, and `shopRefresh` was both nil -- a scoping mistake, fixed above --
	-- and FIRST in this list. So the loop terminated on element one and the
	-- other six refreshers never ran at all: shapes, quests, vault, slots,
	-- settings and ascend were every bit as dead as the shop, from a single
	-- missing assignment several hundred lines away.
	--
	-- A named list cannot fail that way. A nil entry is skipped and REPORTED
	-- rather than silently ending the sweep, so the next time a refresher is
	-- lost the console says which one instead of the UI just going quiet.
	local refreshers = {
		{ name = "shop", fn = self.shopRefresh },
		{ name = "shapes", fn = self.shapeRefresh },
		{ name = "quests", fn = self.questRefresh },
		{ name = "vault", fn = self.vaultRefresh },
		{ name = "slots", fn = self.slotsRefresh },
		{ name = "settings", fn = self.settingsRefresh },
		{ name = "ascend", fn = self.ascendRefresh },
	}
	for _, entry in ipairs(refreshers) do
		if type(entry.fn) == "function" then
			local ok, err = pcall(entry.fn, state)
			if not ok then
				warn(string.format("[V7MenuPanel] %s refresh failed: %s",
					entry.name, tostring(err)))
			end
		else
			warn(string.format("[V7MenuPanel] %s refresh is missing -- that panel "
				.. "will never receive a snapshot", entry.name))
		end
	end
end

-- Declares whether a client capability is present, from the composition root.
-- Repaints immediately from the last snapshot so the answer takes effect without
-- waiting for the next StateSync.
function V7MenuPanel:setCapability(name: string, present: boolean)
	self._capabilities[name] = present
	local last = self.lastState
	if last ~= nil and type(self.settingsRefresh) == "function" then
		local ok, err = pcall(self.settingsRefresh, last)
		if not ok then
			warn("[V7MenuPanel] settings refresh failed: " .. tostring(err))
		end
	end
end

function V7MenuPanel:openOverlay(name: string)
	self:closeAll()
	local target = self.overlays[name]
	if target then
		target.Visible = true
	end

	-- BOARDS IS PULL, NOT PUSH. Every other panel rides the StateSync snapshot,
	-- but leaderboards are global rather than per-player, so they are fetched on
	-- demand -- and only when the panel is actually opened, so a player who never
	-- looks at them never costs the server a request.
	if name == "boards" and type(self.boardsRefresh) == "function" then
		local ok, err = pcall(self.boardsRefresh, self.activeBoard or "NetWorth")
		if not ok then
			warn("[V7MenuPanel] board refresh failed: " .. tostring(err))
		end
	end

end

function V7MenuPanel:closeAll()
	for _, frame in pairs(self.overlays) do
		frame.Visible = false
	end
end

return V7MenuPanel
