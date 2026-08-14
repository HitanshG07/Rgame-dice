--!strict
-- V7MenuPanel.luau
-- Dedicated Full-Screen Overlay Manager for Shapes, Slots, Ascension, Shop, Boards, Quests, Vault, and Settings.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

	-- Cards that represent a PASS, keyed so a snapshot can mark them owned. A
	-- developer product is consumable and is deliberately absent from this map:
	-- buying gems twice is a legitimate repeat purchase, owning Auto-Roll twice
	-- is not.
	local passCards: { [string]: any } = {}

	-- Exact figures for the passes whose worth is a RATE. Built from the shared
	-- catalogs, never typed as prose, so a card cannot promise something the
	-- server does not deliver (L-025). Entries absent here simply show no small
	-- print -- a pass that grants a concrete thing ("+2 die slots") is already
	-- self-explanatory in its blurb.
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
	}

	for _, entry in ipairs(sellableItems) do
		local card = UITheme.panel(UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
		card.Name = "Item_" .. entry.key
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

		-- EXACT NUMBERS IN SMALL PRINT for the passes whose value is a rate rather
		-- than a thing (operator-directed 2026-08-13). "A far higher ceiling on
		-- offline earnings" is not something a player can evaluate against a
		-- Robux price; "+25% rate, 24h capacity" is. Read from the shared catalog
		-- so the card cannot advertise a number the server does not grant.
		local detail = SHOP_TIER_DETAIL[entry.key]
		if detail ~= nil then
			local fine = UITheme.smallPrint(detail, UDim2.fromScale(0.9, 0.16),
				UDim2.fromScale(0.05, 0.545))
			fine.Name = "TierDetail"
			fine.Parent = card
		end

		local buyContainer, buyBtn = UITheme.neumorphicButton("BUY", UITheme.Colors.Gems, UDim2.fromScale(0.8, 0.25), UDim2.fromScale(0.1, 0.7))
		buyContainer.Name = "BuyButton"
		buyContainer.Parent = card

		local assetId = entry.assetId
		local isPass = MonetisationCatalog.Passes[entry.key] ~= nil

		-- THE PROMPT CAN FAIL, and silently. `PromptGamePassPurchase` throws if
		-- the id does not exist or the place is not configured for it, and an
		-- unhandled throw inside a click handler leaves the player pressing a
		-- button that does nothing with no clue why. pcall + an on-card message.
		local function promptPurchase()
			if assetId == nil then
				-- FR-12.6 fail-closed: an unresolved entry is not purchasable.
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
			passCards[entry.key] = { button = buyBtn, blurb = blurbLbl, baseBlurb = entry.blurb }
		end
	end

	-- Marks owned passes so the shop stops offering what the player already has.
	--
	-- Without this every card showed an identical BUY regardless of ownership,
	-- and the only way to find out you already owned a pass was to press BUY and
	-- have Roblox tell you. Products are intentionally untouched -- they are
	-- consumable and repeat purchases are legitimate.
	local function refreshShop(state: any)
		local owned = if type(state) == "table" and type(state.ownedPasses) == "table"
			then state.ownedPasses else {}
		for key, ui in pairs(passCards) do
			if owned[key] == true then
				UITheme.setButtonText(ui.button, "OWNED")
				UITheme.setEnabled(ui.button, false)
				ui.blurb.Text = ui.baseBlurb .. "  (active)"
				ui.blurb.TextColor3 = UITheme.Colors.Positive
			else
				UITheme.setButtonText(ui.button, "BUY")
				UITheme.setEnabled(ui.button, true)
				ui.blurb.Text = ui.baseBlurb
				ui.blurb.TextColor3 = UITheme.Colors.TextPrimary
			end
		end
	end

	-- 2. SHAPES OVERLAY
	local shapesOverlay, shapesBody = UITheme.overlay("🎲 DICE SHAPES & BUILD CHOICE")
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
	local shapesList = Instance.new("UIListLayout")
	shapesList.Padding = UDim.new(0, 10)
	shapesList.SortOrder = Enum.SortOrder.LayoutOrder
	shapesList.Parent = shapesBody

	local shapeCards: { [string]: any } = {}

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
			local card = UITheme.panel(UDim2.fromScale(1, 0), UDim2.fromScale(0, 0))
			card.Name = "Shape_" .. shapeId
			card.Size = UDim2.new(1, 0, 0, 86)
			card.LayoutOrder = rung
			card.Parent = shapesBody

			local title = UITheme.label(
				string.format("%s  -  %d faces", shapeId, def.faceCount),
				UDim2.fromScale(0.34, 0.42), UDim2.fromScale(0.03, 0.08),
				UITheme.Colors.TextGold)
			title.TextScaled = true
			title.Parent = card

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
			local sub = UITheme.label(character,
				UDim2.fromScale(0.42, 0.34), UDim2.fromScale(0.03, 0.52),
				UITheme.Colors.TextDim)
			sub.TextScaled = true
			sub.Parent = card

			local status = UITheme.label("", UDim2.fromScale(0.22, 0.4),
				UDim2.fromScale(0.44, 0.3), UITheme.Colors.TextDim)
			status.TextScaled = true
			status.TextXAlignment = Enum.TextXAlignment.Right
			status.Parent = card

			local btnContainer, btn = UITheme.neumorphicButton("", UITheme.Colors.Cash,
				UDim2.fromScale(0.20, 0.56), UDim2.fromScale(0.585, 0.22))
			btnContainer.Name = "Action"
			btnContainer.Parent = card

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
			local addC, addBtn = UITheme.neumorphicButton("", UITheme.Colors.Positive,
				UDim2.fromScale(0.185, 0.56), UDim2.fromScale(0.80, 0.22))
			addC.Name = "AddDie"
			addC.Visible = false
			addC.Parent = card

			UITheme.onPressed(addBtn, function()
				local entry = shapeCards[shapeId]
				UITheme.setEnabled(addBtn, false)
				task.spawn(function()
					local result = NetClient.addDieSlot(shapeId)
					if not result.ok and entry ~= nil then
						entry.status.Text = ADD_DIE_REFUSAL[tostring(result.reason)]
							or "Cannot add a die right now."
						entry.status.TextColor3 = UITheme.Colors.Negative
					end
					UITheme.setEnabled(addBtn, true)
				end)
			end)

			UITheme.onPressed(btn, function()
				local entry = shapeCards[shapeId]
				local owned = entry and entry.owned
				UITheme.setEnabled(btn, false)
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
						entry.status.Text = SHAPE_REFUSAL[tostring(result.reason)]
							or "Not right now."
						entry.status.TextColor3 = UITheme.Colors.Negative
					end
					UITheme.setEnabled(btn, true)
				end)
			end)

			shapeCards[shapeId] = {
				card = card, status = status, button = btn,
				addContainer = addC, addButton = addBtn,
				owned = false, rung = rung,
			}
		end
	end

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
			if entry.addContainer ~= nil then
				entry.addContainer.Visible = owned
				if owned then
					if addCost == nil then
						-- At the die limit. Shown rather than hidden, so the ceiling
						-- is legible and the player knows ascending raises it.
						UITheme.setButtonText(entry.addButton, "MAX")
						UITheme.setEnabled(entry.addButton, false)
					else
						UITheme.setButtonText(entry.addButton,
							"+1  $" .. Format.formatNumber(addCost))
						UITheme.setEnabled(entry.addButton, cash >= addCost)
					end
				end
			end
			entry.owned = owned
			local cost = DiceCatalog.getUnlockCost(shapeId) or 0
			local allowed = DiceCatalog.canUnlock(shapeId, ownedMap)

			if shapeId == currentShape then
				entry.status.Text = "IN USE"
				entry.status.TextColor3 = UITheme.Colors.TextGold
				UITheme.setButtonText(entry.button, "ACTIVE")
				UITheme.setEnabled(entry.button, false)
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
					entry.status.Text = "OWNED - free to equip"
					entry.status.TextColor3 = UITheme.Colors.Positive
					UITheme.setButtonText(entry.button, "USE")
					UITheme.setEnabled(entry.button, true)
				else
					local affordable = diamonds >= switchCost
					entry.status.Text = if affordable
						then "OWNED"
						else string.format("OWNED - needs %d\u{2666}", switchCost)
					entry.status.TextColor3 = if affordable
						then UITheme.Colors.Positive else UITheme.Colors.TextDim
					UITheme.setButtonText(entry.button,
						string.format("USE %d\u{2666}", switchCost))
					UITheme.setEnabled(entry.button, affordable)
				end
			elseif allowed then
				-- The next rung. Affordability decides whether it is pressable,
				-- but the price is shown either way so the goal is visible.
				entry.status.Text = "$" .. Format.formatNumber(cost)
				entry.status.TextColor3 = if cash >= cost
					then UITheme.Colors.Positive else UITheme.Colors.TextDim
				UITheme.setButtonText(entry.button, "UNLOCK")
				UITheme.setEnabled(entry.button, cash >= cost)
			else
				-- Locked behind an earlier rung. Naming the prerequisite is what
				-- turns a wall into a goal.
				local prereq = DiceCatalog.getPrerequisite(shapeId)
				entry.status.Text = "needs " .. tostring(prereq)
				entry.status.TextColor3 = UITheme.Colors.TextDim
				UITheme.setButtonText(entry.button, "LOCKED")
				UITheme.setEnabled(entry.button, false)
			end
		end
	end

	-- 3. LEADERBOARD OVERLAY
	local boardsOverlay, boardsBody = UITheme.overlay("🏆 GLOBAL LEADERBOARDS")
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
	local ascendOverlay, ascendBody = UITheme.overlay("🌌 ASCENSION & DIAMOND TREE")
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
	local questsOverlay, questsBody = UITheme.overlay("📜 DAILY QUESTS & REWARDS")
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

	local vaultOverlay, vaultBody = UITheme.overlay("⏳ OFFLINE VAULT")
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

	-- 7. SETTINGS OVERLAY
	local settingsOverlay, settingsBody = UITheme.overlay("⚙️ SETTINGS & PROMO CODES")
	settingsOverlay.Parent = screenGui
	overlays["settings"] = settingsOverlay

	-- THIS OVERLAY HAD ZERO CHILDREN and no button anywhere opened it. It was a
	-- titled empty rectangle that nothing could reach.
	--
	-- Everything below is driven by `SettingsCatalog`, so the rows drawn here and
	-- the keys the server will accept are the same list by construction (L-025).
	local settingsList = Instance.new("UIListLayout")
	settingsList.Padding = UDim.new(0, 10)
	settingsList.SortOrder = Enum.SortOrder.LayoutOrder
	settingsList.Parent = settingsBody

	local settingRows: { [string]: any } = {}

	-- WHICH CLIENT CAPABILITIES ARE ACTUALLY PRESENT.
	--
	-- Filled by the composition root through `setCapability`, never by this module
	-- reaching sideways into AudioDirector. A view module that requires another
	-- view module turns the UI layer into a graph instead of a tree, and
	-- ClientBootstrap already holds both -- so it is the one place that can answer
	-- without adding an edge.
	--
	-- Absent means UNAVAILABLE, which is the right default: a capability that has
	-- not reported in has not proven it exists.
	local capabilities: { [string]: boolean } = {}

	for order, def in ipairs(SettingsCatalog.ordered()) do
		local row = UITheme.panel(UDim2.fromScale(1, 0), UDim2.fromScale(0, 0))
		-- NAMED PER SETTING. Every row is otherwise an anonymous "Frame", so all
		-- four resolved to the identical instance path and none of them could be
		-- addressed -- not by a click driver, not by an inspector, not by anything
		-- that needs to say WHICH switch it means.
		row.Name = "Setting_" .. def.key
		row.Size = UDim2.new(1, 0, 0, 76)
		row.LayoutOrder = order
		row.Parent = settingsBody

		local label = UITheme.label(def.label, UDim2.fromScale(0.5, 0.36),
			UDim2.fromScale(0.03, 0.12), UITheme.Colors.TextGold)
		label.TextScaled = true
		label.Parent = row

		local blurb = UITheme.label(def.blurb, UDim2.fromScale(0.66, 0.3),
			UDim2.fromScale(0.03, 0.52), UITheme.Colors.TextDim)
		blurb.TextScaled = true
		blurb.TextWrapped = true
		blurb.Parent = row

		local toggleC, toggleBtn, setToggle = UITheme.toggle(
			UDim2.fromScale(0.16, 0.34), UDim2.fromScale(0.78, 0.33))
		toggleC.Parent = row

		local key = def.key
		UITheme.onPressed(toggleBtn, function()
			-- Sends the OPPOSITE of what the server last told us, not the opposite
			-- of what the knob is showing. Those are the same thing while the panel
			-- is in sync, and when they are not, the server's value is the one worth
			-- inverting.
			local entry = settingRows[key]
			local current = entry ~= nil and entry.value == true
			-- The knob does not move here. It moves when the snapshot comes back
			-- confirming the write, so a refusal leaves the switch showing the
			-- truth instead of a value that never saved.
			NetClient.setSetting(key, not current)
		end)

		settingRows[key] = {
			set = setToggle, value = def.default, button = toggleBtn,
			blurb = blurb, requires = def.requires, baseBlurb = def.blurb,
		}
	end

	-- PROMO CODES (FR-10.6). The server already had `RedeemCode` wired to a real
	-- code table; there was no way for a player to type one in.
	local codeCard = UITheme.panel(UDim2.fromScale(1, 0), UDim2.fromScale(0, 0))
	codeCard.Name = "PromoCard"
	codeCard.Size = UDim2.new(1, 0, 0, 118)
	codeCard.LayoutOrder = 90
	codeCard.Parent = settingsBody

	local codeTitle = UITheme.label("PROMO CODE", UDim2.fromScale(0.5, 0.24),
		UDim2.fromScale(0.03, 0.06), UITheme.Colors.TextGold)
	codeTitle.TextScaled = true
	codeTitle.Parent = codeCard

	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.Size = UDim2.fromScale(0.58, 0.34)
	codeBox.Position = UDim2.fromScale(0.03, 0.36)
	codeBox.BackgroundColor3 = UITheme.Colors.BaseCream
	codeBox.BorderSizePixel = 0
	codeBox.Font = UITheme.FontMono
	codeBox.PlaceholderText = "ENTER CODE"
	codeBox.Text = ""
	codeBox.TextColor3 = UITheme.Colors.TextPrimary
	codeBox.TextScaled = true
	codeBox.ClearTextOnFocus = false
	codeBox.ZIndex = 4
	codeBox.Parent = codeCard

	local codeCorner = Instance.new("UICorner")
	codeCorner.CornerRadius = UDim.new(0, 8)
	codeCorner.Parent = codeBox

	local codeStroke = Instance.new("UIStroke")
	codeStroke.Color = UITheme.Colors.ShadowDark
	codeStroke.Thickness = 2
	codeStroke.Parent = codeBox

	local codeStatus = UITheme.label("", UDim2.fromScale(0.94, 0.2),
		UDim2.fromScale(0.03, 0.76), UITheme.Colors.TextDim)
	codeStatus.Name = "CodeStatus"
	codeStatus.TextScaled = true
	codeStatus.Parent = codeCard

	local redeemC, redeemBtn = UITheme.neumorphicButton("REDEEM", UITheme.Colors.Positive,
		UDim2.fromScale(0.28, 0.3), UDim2.fromScale(0.66, 0.38))
	redeemC.Name = "RedeemButton"
	redeemC.Parent = codeCard

	-- The reasons the server can give, rendered as sentences. The server sends a
	-- CODE, never prose (NFR-5 / T-7), and it never echoes the submitted text back
	-- -- so an unknown code is reported as unknown without repeating what was
	-- typed.
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
			codeStatus.TextColor3 = UITheme.Colors.TextDim
			return
		end
		UITheme.setEnabled(redeemBtn, false)
		codeStatus.Text = "Checking..."
		codeStatus.TextColor3 = UITheme.Colors.TextDim
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

	-- Redraws every switch from the snapshot. This is the ONLY thing that moves a
	-- knob, which is what makes the panel incapable of showing a value the server
	-- does not hold.
	local function refreshSettings(state: any)
		local settings = if type(state) == "table" then state.settings else nil
		for key, entry in pairs(settingRows) do
			local value = SettingsCatalog.read(settings, key)
			entry.value = value
			entry.set(value)

			-- A SETTING WHOSE FEATURE DOES NOT EXIST IS SHOWN AS UNAVAILABLE.
			--
			-- The preference is still stored and still honoured -- it is the
			-- CONTROL that is disabled, not the value -- so when the missing
			-- capability arrives the player's saved choice is already correct and
			-- the row simply becomes live. Nothing here is a placeholder; it is a
			-- true statement about the current build.
			local available = entry.requires == nil
				or capabilities[entry.requires] == true
			UITheme.setEnabled(entry.button, available)
			if available then
				entry.blurb.Text = entry.baseBlurb
				entry.blurb.TextColor3 = UITheme.Colors.TextDim
			else
				-- AN UNAVAILABLE TOGGLE IS FORCED TO READ "OFF", whatever the
				-- stored preference says.
				--
				-- OPERATOR-REPORTED: "the sound effects is turned on and greyed
				-- out i cant turn it off". Exactly right, and it was my design
				-- error. SFX defaults to `true`, so the row rendered a lit track
				-- with the knob to the right -- the universal picture of "this is
				-- ON" -- while being unpressable. That reads as a stuck control,
				-- not an unavailable one, and the natural conclusion is that the
				-- game is broken.
				--
				-- The stored VALUE is deliberately untouched: when audio ships,
				-- the player's real preference is still there and the row simply
				-- comes alive showing it. Only the DISPLAY is forced off, because
				-- a feature that produces no sound is off in every sense the
				-- player can observe.
				entry.set(false)
				entry.blurb.Text = string.format("%s - %s", entry.baseBlurb,
					SettingsCatalog.missingReason(entry.requires))
				entry.blurb.TextColor3 = UITheme.Colors.VoidFace
			end
		end
	end

	-- 8. SLOTS OVERLAY
	local slotsOverlay, slotsBody = UITheme.overlay("⚡ DIE SLOTS")
	slotsOverlay.Parent = screenGui
	overlays["slots"] = slotsOverlay

	-- Also completely empty before this. FR-1.1 allows 1 to 7 dice.
	local slotsInfo = UITheme.label("", UDim2.fromScale(0.94, 0.3), UDim2.fromScale(0.03, 0.06),
		UITheme.Colors.TextPrimary)
	slotsInfo.TextScaled = true
	slotsInfo.TextWrapped = true
	slotsInfo.Parent = slotsBody

	local addSlotContainer, addSlotBtn = UITheme.neumorphicButton("ADD SLOT",
		UITheme.Colors.Cash, UDim2.fromScale(0.44, 0.16), UDim2.fromScale(0.03, 0.42))
	addSlotContainer.Name = "AddSlotButton"
	addSlotContainer.Parent = slotsBody

	local slotsStatus = UITheme.label("", UDim2.fromScale(0.94, 0.1), UDim2.fromScale(0.03, 0.62),
		UITheme.Colors.TextDim)
	slotsStatus.Name = "SlotsStatus"
	slotsStatus.TextScaled = true
	slotsStatus.Parent = slotsBody

	local SLOT_REFUSAL: { [string]: string } = {
		insufficient_funds = "Not enough Cash for the next slot.",
		invalid_request = "You already have the maximum number of dice.",
		profile_unavailable = "Still loading -- try again in a moment.",
		rate_limited = "Slow down a moment, then try again.",
		throttled = "Slow down a moment, then try again.",
	}

	UITheme.onPressed(addSlotBtn, function()
		UITheme.setEnabled(addSlotBtn, false)
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
			UITheme.setEnabled(addSlotBtn, true)
		end)
	end)

	local function refreshSlots(state: any)
		local slots = if type(state) == "table" then tonumber(state.dieSlots) or 1 else 1
		local cash = if type(state) == "table" then tonumber(state.cash) or 0 else 0
		local ascensions = if type(state) == "table" then tonumber(state.ascensions) or 0 else 0
		local cap = DiceCatalog.dieSlotCapFor(ascensions)
		slotsInfo.Text = string.format(
			"You roll %d %s per throw.  Your limit is %d.\n\nMore dice means more "
			.. "faces resolving at once, and elements that read across dice have "
			.. "more to work with.",
			slots, if slots == 1 then "die" else "dice", cap)

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
			UITheme.setButtonText(addSlotBtn, string.format("MAX (%d)", cap))
			UITheme.setEnabled(addSlotBtn, false)
			if cap < DiceCatalog.MAX_DIE_SLOTS then
				slotsStatus.Text = string.format(
					"Limit reached. Ascend to raise it to %d.", cap + 1)
				slotsStatus.TextColor3 = UITheme.Colors.PurpleAscend
			else
				slotsStatus.Text = "You have every die slot."
				slotsStatus.TextColor3 = UITheme.Colors.TextDim
			end
		else
			UITheme.setButtonText(addSlotBtn, "ADD SLOT  $" .. Format.formatNumber(cost))
			UITheme.setEnabled(addSlotBtn, cash >= cost)
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
	for _, fn in ipairs({ self.shopRefresh, self.shapeRefresh, self.questRefresh,
		self.vaultRefresh, self.slotsRefresh, self.settingsRefresh,
		self.ascendRefresh }) do
		if type(fn) == "function" then
			local ok, err = pcall(fn, state)
			if not ok then
				warn("[V7MenuPanel] overlay refresh failed: " .. tostring(err))
			end
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
