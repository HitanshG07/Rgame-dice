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

		buyBtn.MouseButton1Click:Connect(promptPurchase)
		buyBtn.Activated:Connect(promptPurchase)

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
				UDim2.fromScale(0.26, 0.56), UDim2.fromScale(0.70, 0.22))
			btnContainer.Name = "Action"
			btnContainer.Parent = card

			btn.Activated:Connect(function()
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

		for shapeId, entry in pairs(shapeCards) do
			local owned = ownedMap[shapeId] == true
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
		claimBtn.Activated:Connect(function()
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

	local vaultStatus = UITheme.label("", UDim2.fromScale(0.94, 0.1), UDim2.fromScale(0.03, 0.73),
		UITheme.Colors.TextDim)
	vaultStatus.Name = "ClaimStatus"
	vaultStatus.TextScaled = true
	vaultStatus.Parent = vaultBody

	-- Server refusal codes as sentences. The server sends a code, never prose.
	local VAULT_REFUSAL: { [string]: string } = {
		vault_empty = "Nothing has built up yet -- come back later.",
		no_profile = "Still loading -- try again in a moment.",
		profile_unavailable = "Still loading -- try again in a moment.",
		mutate_failed = "Could not save that. Try again.",
		rate_limited = "Slow down a moment, then try again.",
		throttled = "Slow down a moment, then try again.",
	}

	claimVaultBtn.Activated:Connect(function()
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
			UITheme.setEnabled(claimVaultBtn, false)
			return
		end

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
		toggleBtn.Activated:Connect(function()
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

	redeemBtn.Activated:Connect(submitCode)
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

	addSlotBtn.Activated:Connect(function()
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
		slotsInfo.Text = string.format(
			"You roll %d %s per throw.\n\nMore dice means more faces resolving at "
			.. "once, and elements that read across dice have more to work with.",
			slots, if slots == 1 then "die" else "dice")

		-- THE PRICE, ON THE BUTTON.
		--
		-- This read a bare "ADD SLOT" with no cost anywhere on the panel. The
		-- server charges 1000 * 2^(owned-1) and refuses when the player cannot
		-- pay -- correctly -- but the panel had never mentioned a price, so the
		-- refusal looked like a dead button. Same defect the SHAPE panel had.
		--
		-- The cost comes from the shared catalog, the same call the server makes.
		local cost = DiceCatalog.dieSlotCost(slots)
		if cost == nil then
			UITheme.setButtonText(addSlotBtn, "MAX (7)")
			UITheme.setEnabled(addSlotBtn, false)
			slotsStatus.Text = "You have every die slot."
			slotsStatus.TextColor3 = UITheme.Colors.TextDim
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
		shapeRefresh = refreshShapes,
		questRefresh = refreshQuests,
		vaultRefresh = refreshVault,
		slotsRefresh = refreshSlots,
		settingsRefresh = refreshSettings,
		_capabilities = capabilities,
		lastState = nil,
	}, V7MenuPanel) :: any

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
		self.vaultRefresh, self.slotsRefresh, self.settingsRefresh }) do
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
end

function V7MenuPanel:closeAll()
	for _, frame in pairs(self.overlays) do
		frame.Visible = false
	end
end

return V7MenuPanel
