--!strict
-- V7MenuPanel.luau
-- Dedicated Full-Screen Overlay Manager for Shapes, Slots, Ascension, Shop, Boards, Quests, Vault, and Settings.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetisationCatalog = require(Shared:WaitForChild("MonetisationCatalog"))
local DiceCatalog = require(Shared:WaitForChild("DiceCatalog"))
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
	shapeRefresh: ((any) -> ())?,
	questRefresh: ((any) -> ())?,
	vaultRefresh: ((any) -> ())?,
	slotsRefresh: ((any) -> ())?,
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

	for rung, shapeId in ipairs(DiceCatalog.getUnlockOrder()) do
		local def = DiceCatalog.getShape(shapeId)
		if def ~= nil then
			local card = UITheme.panel(UDim2.fromScale(1, 0), UDim2.fromScale(0, 0))
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
			btnContainer.Parent = card

			btn.Activated:Connect(function()
				local owned = shapeCards[shapeId] and shapeCards[shapeId].owned
				if owned then
					-- Switching is free and reversible among owned shapes (FR-6.1).
					NetClient.setShape(1, shapeId)
				else
					-- Unlock. BuyDiamondNode carries shape ids too; the server
					-- prices them in Cash and enforces the ladder order.
					NetClient.buyDiamondNode(shapeId)
				end
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
		local currentShape = state.dice and state.dice[1] and state.dice[1].Shape
		local cash = tonumber(state.cash) or 0

		for shapeId, entry in pairs(shapeCards) do
			local owned = ownedMap[shapeId] == true
			entry.owned = owned
			local cost = DiceCatalog.getUnlockCost(shapeId) or 0
			local allowed = DiceCatalog.canUnlock(shapeId, ownedMap)

			if shapeId == currentShape then
				entry.status.Text = "IN USE"
				entry.status.TextColor3 = UITheme.Colors.TextGold
				entry.button.Text = "ACTIVE"
				UITheme.setEnabled(entry.button, false)
			elseif owned then
				entry.status.Text = "OWNED"
				entry.status.TextColor3 = UITheme.Colors.Positive
				entry.button.Text = "USE"
				UITheme.setEnabled(entry.button, true)
			elseif allowed then
				-- The next rung. Affordability decides whether it is pressable,
				-- but the price is shown either way so the goal is visible.
				entry.status.Text = "$" .. Format.formatNumber(cost)
				entry.status.TextColor3 = if cash >= cost
					then UITheme.Colors.Positive else UITheme.Colors.TextDim
				entry.button.Text = "UNLOCK"
				UITheme.setEnabled(entry.button, cash >= cost)
			else
				-- Locked behind an earlier rung. Naming the prerequisite is what
				-- turns a wall into a goal.
				local prereq = DiceCatalog.getPrerequisite(shapeId)
				entry.status.Text = "needs " .. tostring(prereq)
				entry.status.TextColor3 = UITheme.Colors.TextDim
				entry.button.Text = "LOCKED"
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
		claimContainer.Parent = row

		local rowState = { id = nil :: string? }
		claimBtn.Activated:Connect(function()
			local id = rowState.id
			if id ~= nil then
				NetClient.claimQuest(id)
			end
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
					ui.button.Text = "DONE"
					UITheme.setEnabled(ui.button, false)
				elseif q.ready then
					ui.button.Text = "CLAIM"
					UITheme.setEnabled(ui.button, true)
				else
					ui.button.Text = "LOCKED"
					UITheme.setEnabled(ui.button, false)
				end
			end
		end
	end

	local vaultOverlay, vaultBody = UITheme.overlay("⏳ OFFLINE VAULT")
	vaultOverlay.Parent = screenGui
	overlays["vault"] = vaultOverlay

	-- Was a single static label. The vault is a real server-clocked accrual
	-- (FR-8) and the player has to be able to see and claim it.
	local vaultInfo = UITheme.label("", UDim2.fromScale(0.94, 0.34), UDim2.fromScale(0.03, 0.06),
		UITheme.Colors.TextPrimary)
	vaultInfo.TextScaled = true
	vaultInfo.TextWrapped = true
	vaultInfo.Parent = vaultBody

	local claimVaultContainer, claimVaultBtn = UITheme.neumorphicButton("CLAIM",
		UITheme.Colors.Cash, UDim2.fromScale(0.44, 0.16), UDim2.fromScale(0.03, 0.46))
	claimVaultContainer.Parent = vaultBody
	claimVaultBtn.Activated:Connect(function()
		NetClient.claimVault(false)
	end)

	local function refreshVault(state: any)
		-- The snapshot does not carry vault earnings; the server owns that figure
		-- and reports it through the ClaimVault result. Until a claim happens the
		-- honest display is the capacity the player has EARNED, not a guess at
		-- what has accrued.
		local caps = if type(state) == "table" and type(state.upgrades) == "table"
			then state.upgrades else {}
		local lvl = tonumber(caps.VaultCapacity) or 0
		local hours = 4 + (lvl * 0.8)
		vaultInfo.Text = string.format(
			"Earnings accrue while you are away, at your recent average rate.\n\n"
			.. "Your capacity: %.1f hours.\n"
			.. "Press CLAIM to collect whatever has built up.", hours)
	end

	local settingsOverlay, settingsBody = UITheme.overlay("⚙️ SETTINGS & PROMO CODES")
	settingsOverlay.Parent = screenGui
	overlays["settings"] = settingsOverlay

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
	addSlotContainer.Parent = slotsBody
	addSlotBtn.Activated:Connect(function()
		NetClient.addDieSlot()
	end)

	local function refreshSlots(state: any)
		local slots = if type(state) == "table" then tonumber(state.dieSlots) or 1 else 1
		slotsInfo.Text = string.format(
			"You roll %d %s per throw.\n\nMore dice means more faces resolving at "
			.. "once, and elements that read across dice have more to work with.",
			slots, if slots == 1 then "die" else "dice")
		UITheme.setEnabled(addSlotBtn, slots < 7)
		addSlotBtn.Text = if slots < 7 then "ADD SLOT" else "MAX (7)"
	end

	screenGui.Parent = playerGui

	local self: V7MenuController = setmetatable({
		overlays = overlays,
		-- The refresh functions are stored on the controller so `applyState` can
		-- fan a single snapshot out to every panel that needs it.
		shapeRefresh = refreshShapes,
		questRefresh = refreshQuests,
		vaultRefresh = refreshVault,
		slotsRefresh = refreshSlots,
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
	for _, fn in ipairs({ self.shapeRefresh, self.questRefresh, self.vaultRefresh, self.slotsRefresh }) do
		if type(fn) == "function" then
			local ok, err = pcall(fn, state)
			if not ok then
				warn("[V7MenuPanel] overlay refresh failed: " .. tostring(err))
			end
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
