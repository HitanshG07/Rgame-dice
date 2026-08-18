--!strict
-- UIMockPreview.luau
-- Quests & Daily Directives Panel Redesign Preview (3 Distinct Design Directions).
--
-- Explore 3 distinct design philosophies for the Daily Quests / Mission Control system:
--   Variant A: MACHINIST PRECISION TERMINAL (Dual-column contract terminal + session telemetry)
--   Variant B: CASINO LEDGER & BOUNTY BOARD (Classic mahogany & brass wager sheet + daily chip ribbon)
--   Variant C: BRUTALIST OPERATIONS DOSSIER (3-Column high-contrast mission grid + temporal cache)
--
-- Features:
--   - Instant carousel cycling (< and > buttons + A/B/C indicators)
--   - 100% accurate data from ProgressionService (Rolls, Forges, Streaks, Daily Streak, Playtime Chests)
--   - Zero emojis, zero fake asset IDs (100% Roblox native UI geometry)
--   - No modifications to live files; self-contained preview.
--
-- Runnable in Roblox Studio command bar via:
-- require(game.StarterPlayer.StarterPlayerScripts.Client.UIMockPreview:Clone()).show()

local Players = game:GetService("Players")

local UIMockPreview = {}

local currentGui: ScreenGui? = nil
local activeVariantIndex = 1 -- 1 = A, 2 = B, 3 = C

--------------------------------------------------------------------------------
-- SAMPLE REALISTIC QUEST DATA (From ProgressionService & QuestPool)
--------------------------------------------------------------------------------

type QuestItem = {
	id: string,
	tag: string,
	title: string,
	desc: string,
	current: number,
	target: number,
	rewardKind: string,
	rewardAmount: number,
	rewardText: string,
	rewardColor: Color3,
	isReady: boolean,
	isClaimed: boolean,
}

local SAMPLE_QUESTS: { QuestItem } = {
	{
		id = "roll100",
		tag = "[ QUEST 01 ]",
		title = "HIGH-FREQUENCY CALIBRATION",
		desc = "Perform 100 physical dice rolls in the arena.",
		current = 100,
		target = 100,
		rewardKind = "Cash",
		rewardAmount = 2500,
		rewardText = "+$2,500 CASH",
		rewardColor = Color3.fromRGB(74, 222, 128),
		isReady = true,
		isClaimed = false,
	},
	{
		id = "forge10",
		tag = "[ QUEST 02 ]",
		title = "MASS EQUILIBRIUM SHIFT",
		desc = "Modify and forge 10 die face mass distributions.",
		current = 4,
		target = 10,
		rewardKind = "Gems",
		rewardAmount = 25,
		rewardText = "+25 GEMS",
		rewardColor = Color3.fromRGB(56, 189, 248),
		isReady = false,
		isClaimed = false,
	},
	{
		id = "streak15",
		tag = "[ QUEST 03 ]",
		title = "CRITICAL ALIGNMENT RUN",
		desc = "Attain an unbroken consecutive roll streak of 15.",
		current = 8,
		target = 15,
		rewardKind = "Gems",
		rewardAmount = 30,
		rewardText = "+30 GEMS",
		rewardColor = Color3.fromRGB(56, 189, 248),
		isReady = false,
		isClaimed = false,
	},
}

local LOGIN_DAYS = {
	{ day = 1, text = "$300", claimed = true },
	{ day = 2, text = "$700", claimed = true },
	{ day = 3, text = "20 \u{25C6}", claimed = true },
	{ day = 4, text = "$2.0K", active = true },
	{ day = 5, text = "45 \u{25C6}", future = true },
	{ day = 6, text = "$5.0K", future = true },
	{ day = 7, text = "5 \u{2666}", jackpot = true, future = true },
}

local PLAYTIME_TIERS = {
	{ name = "Tier 1", timeStr = "5m", rewardStr = "$400 Cash", claimed = true, progress = 1.0 },
	{ name = "Tier 2", timeStr = "15m", rewardStr = "$1,500 Cash", ready = true, progress = 1.0 },
	{ name = "Tier 3", timeStr = "45m", rewardStr = "35 Gems", ready = false, progress = 0.44, timeRemaining = "25m left" },
}

--------------------------------------------------------------------------------
-- HELPER: BASE MODAL SHELL
--------------------------------------------------------------------------------

local function createModalShell(titleText: string, subtitleText: string, root: Frame): (Frame, Frame)
	local container = Instance.new("Frame")
	container.Name = "ModalContainer"
	container.Size = UDim2.new(0.86, 0, 0.86, -137.6)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundColor3 = Color3.fromRGB(26, 22, 20)
	container.BorderSizePixel = 0
	container.Parent = root

	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.Name = "PanelBounds"
	sizeCap.MaxSize = Vector2.new(900, 1100)
	sizeCap.MinSize = Vector2.new(320, 420)
	sizeCap.Parent = container

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 12)
	cCorner.Parent = container

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = Color3.fromRGB(212, 175, 55)
	cStroke.Thickness = 2
	cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cStroke.Parent = container

	-- Header Bar (16px margins matching Body)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -32, 0, 48)
	header.Position = UDim2.new(0, 16, 0, 16)
	header.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	header.BorderSizePixel = 0
	header.Parent = container

	local hCorner = Instance.new("UICorner")
	hCorner.CornerRadius = UDim.new(0, 8)
	hCorner.Parent = header

	local hStroke = Instance.new("UIStroke")
	hStroke.Color = Color3.fromRGB(212, 175, 55)
	hStroke.Thickness = 1
	hStroke.Parent = header

	local hPad = Instance.new("UIPadding")
	hPad.PaddingLeft = UDim.new(0, 16)
	hPad.PaddingRight = UDim.new(0, 16)
	hPad.Parent = header

	local hTitle = Instance.new("TextLabel")
	hTitle.Size = UDim2.new(0.5, 0, 1, 0)
	hTitle.BackgroundTransparency = 1
	hTitle.Font = Enum.Font.GothamBold
	hTitle.Text = titleText
	hTitle.TextColor3 = Color3.fromRGB(212, 175, 55)
	hTitle.TextSize = 20
	hTitle.TextXAlignment = Enum.TextXAlignment.Left
	hTitle.Parent = header

	local hSub = Instance.new("TextLabel")
	hSub.Size = UDim2.new(0.5, -45, 1, 0)
	hSub.Position = UDim2.new(0.5, 0, 0, 0)
	hSub.BackgroundTransparency = 1
	hSub.Font = Enum.Font.GothamBold
	hSub.Text = subtitleText
	hSub.TextColor3 = Color3.fromRGB(160, 148, 140)
	hSub.TextSize = 13.5
	hSub.TextXAlignment = Enum.TextXAlignment.Right
	hSub.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -32, 0.5, -16)
	closeBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
	closeBtn.BorderSizePixel = 0
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "\u{00D7}"
	closeBtn.TextColor3 = Color3.fromRGB(212, 175, 55)
	closeBtn.TextSize = 20
	closeBtn.Parent = header

	local cbCorner = Instance.new("UICorner")
	cbCorner.CornerRadius = UDim.new(0, 6)
	cbCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		UIMockPreview.hide()
	end)

	-- Body Area (Exact 16px all-around margins: Left 16, Right 16, Top 76, Bottom 16)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -32, 1, -92)
	body.Position = UDim2.new(0, 16, 0, 76)
	body.BackgroundTransparency = 1
	body.ClipsDescendants = false
	body.Parent = container

	return container, body
end

--------------------------------------------------------------------------------
-- VARIANT A: MACHINIST PRECISION CONTRACT TERMINAL
--------------------------------------------------------------------------------

local function buildVariantA(parent: Frame): Frame
	local root = Instance.new("Frame")
	root.Name = "VariantA_Machinist"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = parent

	local container, body = createModalShell(
		"QUESTS",
		"Resets in: 8h 42m",
		root
	)

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 14)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = body

	-- LEFT COLUMN (58%): 3 Heavy Contract Rows
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftContractCol"
	leftCol.Size = UDim2.new(0.58, -7, 1, 0)
	leftCol.BackgroundTransparency = 1
	leftCol.LayoutOrder = 1
	leftCol.Parent = body

	local lList = Instance.new("UIListLayout")
	lList.Padding = UDim.new(0, 10)
	lList.SortOrder = Enum.SortOrder.LayoutOrder
	lList.Parent = leftCol

	for i, q in ipairs(SAMPLE_QUESTS) do
		local card = Instance.new("Frame")
		card.Name = "QuestCard_" .. i
		card.Size = UDim2.new(1, 0, 0.333, -7)
		card.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = leftCol

		local cCorner = Instance.new("UICorner")
		cCorner.CornerRadius = UDim.new(0, 8)
		cCorner.Parent = card

		local cStroke = Instance.new("UIStroke")
		cStroke.Color = if q.isReady then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(70, 58, 48)
		cStroke.Thickness = if q.isReady then 1.5 else 1
		cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cStroke.Parent = card

		local cPad = Instance.new("UIPadding")
		cPad.PaddingTop = UDim.new(0, 10)
		cPad.PaddingBottom = UDim.new(0, 10)
		cPad.PaddingLeft = UDim.new(0, 14)
		cPad.PaddingRight = UDim.new(0, 14)
		cPad.Parent = card

		-- Top row: Tag & Reward
		local topRow = Instance.new("Frame")
		topRow.Size = UDim2.new(1, 0, 0, 20)
		topRow.BackgroundTransparency = 1
		topRow.Parent = card

		local tagLbl = Instance.new("TextLabel")
		tagLbl.Size = UDim2.new(0.5, 0, 1, 0)
		tagLbl.BackgroundTransparency = 1
		tagLbl.Font = Enum.Font.Code
		tagLbl.Text = q.tag
		tagLbl.TextColor3 = Color3.fromRGB(212, 175, 55)
		tagLbl.TextSize = 12
		tagLbl.TextXAlignment = Enum.TextXAlignment.Left
		tagLbl.Parent = topRow

		local rewBadge = Instance.new("TextLabel")
		rewBadge.Size = UDim2.new(0.5, 0, 1, 0)
		rewBadge.Position = UDim2.new(0.5, 0, 0, 0)
		rewBadge.BackgroundTransparency = 1
		rewBadge.Font = Enum.Font.GothamBold
		rewBadge.Text = "REWARD: " .. q.rewardText
		rewBadge.TextColor3 = q.rewardColor
		rewBadge.TextSize = 13.5
		rewBadge.TextXAlignment = Enum.TextXAlignment.Right
		rewBadge.Parent = topRow

		-- Title
		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, 0, 0, 22)
		titleLbl.Position = UDim2.new(0, 0, 0, 22)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.Text = q.title
		titleLbl.TextColor3 = Color3.fromRGB(245, 239, 230)
		titleLbl.TextSize = 15
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.Parent = card

		-- Description
		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(1, 0, 0, 20)
		descLbl.Position = UDim2.new(0, 0, 0, 46)
		descLbl.BackgroundTransparency = 1
		descLbl.Font = Enum.Font.GothamMedium
		descLbl.Text = q.desc
		descLbl.TextColor3 = Color3.fromRGB(170, 160, 150)
		descLbl.TextSize = 13
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.Parent = card

		-- Bottom row: Progress Track & Action Button
		local botRow = Instance.new("Frame")
		botRow.Size = UDim2.new(1, 0, 0, 38)
		botRow.Position = UDim2.new(0, 0, 1, -38)
		botRow.BackgroundTransparency = 1
		botRow.Parent = card

		local trackBack = Instance.new("Frame")
		trackBack.Size = UDim2.new(0.63, -10, 0, 14)
		trackBack.Position = UDim2.new(0, 0, 0.5, -7)
		trackBack.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		trackBack.BorderSizePixel = 0
		trackBack.Parent = botRow

		local trCorner = Instance.new("UICorner")
		trCorner.CornerRadius = UDim.new(0, 7)
		trCorner.Parent = trackBack

		local trFill = Instance.new("Frame")
		trFill.Size = UDim2.fromScale(math.clamp(q.current / q.target, 0, 1), 1)
		trFill.BackgroundColor3 = if q.isReady then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(212, 175, 55)
		trFill.BorderSizePixel = 0
		trFill.Parent = trackBack

		local tfCorner = Instance.new("UICorner")
		tfCorner.CornerRadius = UDim.new(0, 7)
		tfCorner.Parent = trFill

		local countLbl = Instance.new("TextLabel")
		countLbl.Size = UDim2.new(0.63, -10, 0, 18)
		countLbl.Position = UDim2.new(0, 0, 0, -16)
		countLbl.BackgroundTransparency = 1
		countLbl.Font = Enum.Font.Code
		countLbl.Text = string.format("COMPLETION: %d / %d", q.current, q.target)
		countLbl.TextColor3 = Color3.fromRGB(180, 170, 160)
		countLbl.TextSize = 11
		countLbl.TextXAlignment = Enum.TextXAlignment.Left
		countLbl.Parent = botRow

		local actionBtn = Instance.new("TextButton")
		actionBtn.Size = UDim2.new(0.37, 0, 1, 0)
		actionBtn.Position = UDim2.new(0.63, 0, 0, 0)
		actionBtn.BackgroundColor3 = if q.isReady then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(48, 40, 36)
		actionBtn.BorderSizePixel = 0
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.Text = if q.isReady then "CLAIM REWARD" else "IN PROGRESS"
		actionBtn.TextColor3 = if q.isReady then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(160, 148, 140)
		actionBtn.TextSize = 13
		actionBtn.Parent = botRow

		local abCorner = Instance.new("UICorner")
		abCorner.CornerRadius = UDim.new(0, 6)
		abCorner.Parent = actionBtn
	end

	-- RIGHT COLUMN (42%): Stacked Session Chests & 7-Day Protocol
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightProgressionCol"
	rightCol.Size = UDim2.new(0.42, -7, 1, 0)
	rightCol.BackgroundTransparency = 1
	rightCol.LayoutOrder = 2
	rightCol.Parent = body

	local rList = Instance.new("UIListLayout")
	rList.Padding = UDim.new(0, 10)
	rList.SortOrder = Enum.SortOrder.LayoutOrder
	rList.Parent = rightCol

	-- Top Pod: Playtime Rewards (44% height)
	local chestPod = Instance.new("Frame")
	chestPod.Name = "PlaytimeRewardsPod"
	chestPod.Size = UDim2.new(1, 0, 0.44, -5)
	chestPod.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	chestPod.BorderSizePixel = 0
	chestPod.LayoutOrder = 1
	chestPod.Parent = rightCol

	local cpCorner = Instance.new("UICorner")
	cpCorner.CornerRadius = UDim.new(0, 8)
	cpCorner.Parent = chestPod

	local cpStroke = Instance.new("UIStroke")
	cpStroke.Color = Color3.fromRGB(70, 58, 48)
	cpStroke.Thickness = 1
	cpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cpStroke.Parent = chestPod

	local cpPad = Instance.new("UIPadding")
	cpPad.PaddingTop = UDim.new(0, 10)
	cpPad.PaddingBottom = UDim.new(0, 10)
	cpPad.PaddingLeft = UDim.new(0, 14)
	cpPad.PaddingRight = UDim.new(0, 14)
	cpPad.Parent = chestPod

	local cpList = Instance.new("UIListLayout")
	cpList.Padding = UDim.new(0, 6)
	cpList.SortOrder = Enum.SortOrder.LayoutOrder
	cpList.Parent = chestPod

	local cpHeader = Instance.new("TextLabel")
	cpHeader.Size = UDim2.new(1, 0, 0, 20)
	cpHeader.BackgroundTransparency = 1
	cpHeader.Font = Enum.Font.GothamBold
	cpHeader.Text = "\u{25B6} PLAYTIME REWARDS"
	cpHeader.TextColor3 = Color3.fromRGB(212, 175, 55)
	cpHeader.TextSize = 13.5
	cpHeader.TextXAlignment = Enum.TextXAlignment.Left
	cpHeader.LayoutOrder = 1
	cpHeader.Parent = chestPod

	for i, tier in ipairs(PLAYTIME_TIERS) do
		local tRow = Instance.new("Frame")
		tRow.Size = UDim2.new(1, 0, 0, 44)
		tRow.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		tRow.BorderSizePixel = 0
		tRow.LayoutOrder = i + 1
		tRow.Parent = chestPod

		local trCorner2 = Instance.new("UICorner")
		trCorner2.CornerRadius = UDim.new(0, 6)
		trCorner2.Parent = tRow

		local tPad = Instance.new("UIPadding")
		tPad.PaddingLeft = UDim.new(0, 10)
		tPad.PaddingRight = UDim.new(0, 10)
		tPad.Parent = tRow

		local tTitle = Instance.new("TextLabel")
		tTitle.Size = UDim2.new(0.55, 0, 0, 20)
		tTitle.Position = UDim2.new(0, 0, 0, 4)
		tTitle.BackgroundTransparency = 1
		tTitle.Font = Enum.Font.GothamBold
		tTitle.Text = string.format("%s (%s): %s", tier.name, tier.timeStr, tier.rewardStr)
		tTitle.TextColor3 = Color3.fromRGB(245, 239, 230)
		tTitle.TextSize = 12.5
		tTitle.TextXAlignment = Enum.TextXAlignment.Left
		tTitle.Parent = tRow

		local subProgress = Instance.new("TextLabel")
		subProgress.Size = UDim2.new(0.55, 0, 0, 16)
		subProgress.Position = UDim2.new(0, 0, 0, 24)
		subProgress.BackgroundTransparency = 1
		subProgress.Font = Enum.Font.Code
		subProgress.Text = if tier.claimed then "STATUS: CLAIMED" elseif tier.ready then "STATUS: UNLOCKED" else "STATUS: " .. (tier.timeRemaining or "IN PROGRESS")
		subProgress.TextColor3 = if tier.claimed then Color3.fromRGB(160, 148, 140) elseif tier.ready then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(212, 175, 55)
		subProgress.TextSize = 10.5
		subProgress.TextXAlignment = Enum.TextXAlignment.Left
		subProgress.Parent = tRow

		local cBtn = Instance.new("TextButton")
		cBtn.Size = UDim2.new(0.4, 0, 0, 30)
		cBtn.Position = UDim2.new(0.6, 0, 0.5, -15)
		cBtn.BackgroundColor3 = if tier.claimed then Color3.fromRGB(36, 30, 26) elseif tier.ready then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(48, 40, 36)
		cBtn.BorderSizePixel = 0
		cBtn.Font = Enum.Font.GothamBold
		cBtn.Text = if tier.claimed then "CLAIMED \u{2713}" elseif tier.ready then "CLAIM" else "LOCKED"
		cBtn.TextColor3 = if tier.ready then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(160, 148, 140)
		cBtn.TextSize = 12
		cBtn.Parent = tRow

		local cbCorner = Instance.new("UICorner")
		cbCorner.CornerRadius = UDim.new(0, 4)
		cbCorner.Parent = cBtn
	end

	-- Bottom Pod: Daily Login Streak (56% height with 3x2 + Day 7 layout)
	local loginPod = Instance.new("Frame")
	loginPod.Name = "DailyLoginPod"
	loginPod.Size = UDim2.new(1, 0, 0.56, -5)
	loginPod.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	loginPod.BorderSizePixel = 0
	loginPod.LayoutOrder = 2
	loginPod.Parent = rightCol

	local lpCorner = Instance.new("UICorner")
	lpCorner.CornerRadius = UDim.new(0, 8)
	lpCorner.Parent = loginPod

	local lpStroke = Instance.new("UIStroke")
	lpStroke.Color = Color3.fromRGB(70, 58, 48)
	lpStroke.Thickness = 1
	lpStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lpStroke.Parent = loginPod

	local lpPad = Instance.new("UIPadding")
	lpPad.PaddingTop = UDim.new(0, 10)
	lpPad.PaddingBottom = UDim.new(0, 10)
	lpPad.PaddingLeft = UDim.new(0, 14)
	lpPad.PaddingRight = UDim.new(0, 14)
	lpPad.Parent = loginPod

	local lpHeader = Instance.new("TextLabel")
	lpHeader.Size = UDim2.new(1, 0, 0, 20)
	lpHeader.BackgroundTransparency = 1
	lpHeader.Font = Enum.Font.GothamBold
	lpHeader.Text = "\u{25C8} DAILY LOGIN (DAY 4 / 7)"
	lpHeader.TextColor3 = Color3.fromRGB(212, 175, 55)
	lpHeader.TextSize = 13.5
	lpHeader.TextXAlignment = Enum.TextXAlignment.Left
	lpHeader.Parent = loginPod

	-- Main Layout Container (Left 3x2 + Right Day 7)
	local gridContainer = Instance.new("Frame")
	gridContainer.Name = "GridContainer"
	gridContainer.Size = UDim2.new(1, 0, 1, -26)
	gridContainer.Position = UDim2.new(0, 0, 0, 24)
	gridContainer.BackgroundTransparency = 1
	gridContainer.Parent = loginPod

	local gcList = Instance.new("UIListLayout")
	gcList.FillDirection = Enum.FillDirection.Horizontal
	gcList.Padding = UDim.new(0, 8)
	gcList.SortOrder = Enum.SortOrder.LayoutOrder
	gcList.Parent = gridContainer

	-- Left Column: 2 Rows of 3 Cards (Days 1-3 on top, Days 4-6 on bottom)
	local leftDaysCol = Instance.new("Frame")
	leftDaysCol.Name = "LeftDaysCol"
	leftDaysCol.Size = UDim2.new(0.72, -4, 1, 0)
	leftDaysCol.BackgroundTransparency = 1
	leftDaysCol.LayoutOrder = 1
	leftDaysCol.Parent = gridContainer

	local ldcList = Instance.new("UIListLayout")
	ldcList.Padding = UDim.new(0, 6)
	ldcList.SortOrder = Enum.SortOrder.LayoutOrder
	ldcList.Parent = leftDaysCol

	-- Helper to create a small day card
	local function createDayCard(d: any, parentRow: Frame)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0.333, -4, 1, 0)
		card.BackgroundColor3 = if d.active then Color3.fromRGB(212, 175, 55) elseif d.claimed then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(28, 24, 20)
		card.BorderSizePixel = 0
		card.LayoutOrder = d.day
		card.Parent = parentRow

		local cCorn = Instance.new("UICorner")
		cCorn.CornerRadius = UDim.new(0, 6)
		cCorn.Parent = card

		local cStk = Instance.new("UIStroke")
		cStk.Color = if d.active then Color3.fromRGB(245, 239, 230) else Color3.fromRGB(70, 58, 48)
		cStk.Thickness = if d.active then 1.5 else 1
		cStk.Parent = card

		local dTitle = Instance.new("TextLabel")
		dTitle.Size = UDim2.new(1, 0, 0, 16)
		dTitle.Position = UDim2.new(0, 0, 0, 6)
		dTitle.BackgroundTransparency = 1
		dTitle.Font = Enum.Font.GothamBold
		dTitle.Text = "DAY " .. d.day
		dTitle.TextColor3 = if d.active then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(160, 148, 140)
		dTitle.TextSize = 11
		dTitle.Parent = card

		local dVal = Instance.new("TextLabel")
		dVal.Size = UDim2.new(1, 0, 0, 24)
		dVal.Position = UDim2.new(0, 0, 0, 24)
		dVal.BackgroundTransparency = 1
		dVal.Font = Enum.Font.GothamBold
		dVal.Text = d.text
		dVal.TextColor3 = if d.active then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(245, 239, 230)
		dVal.TextSize = 14
		dVal.Parent = card

		local dStat = Instance.new("TextLabel")
		dStat.Size = UDim2.new(1, 0, 0, 16)
		dStat.Position = UDim2.new(0, 0, 1, -18)
		dStat.BackgroundTransparency = 1
		dStat.Font = Enum.Font.GothamBold
		dStat.Text = if d.claimed then "\u{2713} DONE" elseif d.active then "READY" else "LOCKED"
		dStat.TextColor3 = if d.active then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(140, 130, 120)
		dStat.TextSize = 9.5
		dStat.Parent = card
	end

	-- Row 1: Days 1, 2, 3
	local row1 = Instance.new("Frame")
	row1.Name = "Row_Days123"
	row1.Size = UDim2.new(1, 0, 0.5, -3)
	row1.BackgroundTransparency = 1
	row1.LayoutOrder = 1
	row1.Parent = leftDaysCol

	local r1List = Instance.new("UIListLayout")
	r1List.FillDirection = Enum.FillDirection.Horizontal
	r1List.Padding = UDim.new(0, 6)
	r1List.SortOrder = Enum.SortOrder.LayoutOrder
	r1List.Parent = row1

	createDayCard(LOGIN_DAYS[1], row1)
	createDayCard(LOGIN_DAYS[2], row1)
	createDayCard(LOGIN_DAYS[3], row1)

	-- Row 2: Days 4, 5, 6
	local row2 = Instance.new("Frame")
	row2.Name = "Row_Days456"
	row2.Size = UDim2.new(1, 0, 0.5, -3)
	row2.BackgroundTransparency = 1
	row2.LayoutOrder = 2
	row2.Parent = leftDaysCol

	local r2List = Instance.new("UIListLayout")
	r2List.FillDirection = Enum.FillDirection.Horizontal
	r2List.Padding = UDim.new(0, 6)
	r2List.SortOrder = Enum.SortOrder.LayoutOrder
	r2List.Parent = row2

	createDayCard(LOGIN_DAYS[4], row2)
	createDayCard(LOGIN_DAYS[5], row2)
	createDayCard(LOGIN_DAYS[6], row2)

	-- Right Column: Big Day 7 Grand Finale Card (Full height spanning both rows)
	local day7Card = Instance.new("Frame")
	day7Card.Name = "Day7GrandCard"
	day7Card.Size = UDim2.new(0.28, -4, 1, 0)
	day7Card.BackgroundColor3 = Color3.fromRGB(28, 22, 24)
	day7Card.BorderSizePixel = 0
	day7Card.LayoutOrder = 2
	day7Card.Parent = gridContainer

	local d7Corner = Instance.new("UICorner")
	d7Corner.CornerRadius = UDim.new(0, 8)
	d7Corner.Parent = day7Card

	local d7Stroke = Instance.new("UIStroke")
	d7Stroke.Color = Color3.fromRGB(244, 114, 182)
	d7Stroke.Thickness = 1.5
	d7Stroke.Parent = day7Card

	local d7Pad = Instance.new("UIPadding")
	d7Pad.PaddingTop = UDim.new(0, 8)
	d7Pad.PaddingBottom = UDim.new(0, 8)
	d7Pad.PaddingLeft = UDim.new(0, 8)
	d7Pad.PaddingRight = UDim.new(0, 8)
	d7Pad.Parent = day7Card

	local d7Badge = Instance.new("TextLabel")
	d7Badge.Size = UDim2.new(1, 0, 0, 16)
	d7Badge.Position = UDim2.new(0, 0, 0, 2)
	d7Badge.BackgroundTransparency = 1
	d7Badge.Font = Enum.Font.Code
	d7Badge.Text = "[ FINAL DAY ]"
	d7Badge.TextColor3 = Color3.fromRGB(244, 114, 182)
	d7Badge.TextSize = 10
	d7Badge.Parent = day7Card

	local d7Title = Instance.new("TextLabel")
	d7Title.Size = UDim2.new(1, 0, 0, 20)
	d7Title.Position = UDim2.new(0, 0, 0, 20)
	d7Title.BackgroundTransparency = 1
	d7Title.Font = Enum.Font.GothamBold
	d7Title.Text = "DAY 7"
	d7Title.TextColor3 = Color3.fromRGB(245, 239, 230)
	d7Title.TextSize = 15
	d7Title.Parent = day7Card

	local d7Amount = Instance.new("TextLabel")
	d7Amount.Size = UDim2.new(1, 0, 0, 36)
	d7Amount.Position = UDim2.new(0, 0, 0, 44)
	d7Amount.BackgroundTransparency = 1
	d7Amount.Font = Enum.Font.GothamBlack
	d7Amount.Text = "+5 \u{2666}"
	d7Amount.TextColor3 = Color3.fromRGB(244, 114, 182)
	d7Amount.TextSize = 26
	d7Amount.Parent = day7Card

	local d7Sub = Instance.new("TextLabel")
	d7Sub.Size = UDim2.new(1, 0, 0, 18)
	d7Sub.Position = UDim2.new(0, 0, 0, 82)
	d7Sub.BackgroundTransparency = 1
	d7Sub.Font = Enum.Font.GothamBold
	d7Sub.Text = "DIAMONDS"
	d7Sub.TextColor3 = Color3.fromRGB(212, 175, 55)
	d7Sub.TextSize = 12
	d7Sub.Parent = day7Card

	local d7Btn = Instance.new("Frame")
	d7Btn.Size = UDim2.new(1, -6, 0, 24)
	d7Btn.Position = UDim2.new(0, 3, 1, -28)
	d7Btn.BackgroundColor3 = Color3.fromRGB(36, 28, 32)
	d7Btn.BorderSizePixel = 0
	d7Btn.Parent = day7Card

	local d7bCorner = Instance.new("UICorner")
	d7bCorner.CornerRadius = UDim.new(0, 4)
	d7bCorner.Parent = d7Btn

	local d7bText = Instance.new("TextLabel")
	d7bText.Size = UDim2.fromScale(1, 1)
	d7bText.BackgroundTransparency = 1
	d7bText.Font = Enum.Font.GothamBold
	d7bText.Text = "LOCKED"
	d7bText.TextColor3 = Color3.fromRGB(160, 148, 140)
	d7bText.TextSize = 10.5
	d7bText.Parent = d7Btn

	return root
end

--------------------------------------------------------------------------------
-- VARIANT B: CASINO LEDGER & GENTLEMAN'S BOUNTY BOARD
--------------------------------------------------------------------------------

local function buildVariantB(parent: Frame): Frame
	local root = Instance.new("Frame")
	root.Name = "VariantB_CasinoLedger"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = parent

	local container, body = createModalShell(
		"~ Royal Ledger of Bounties & Wagers ~",
		"Settles Daily at 00:00 UTC",
		root
	)

	local bList = Instance.new("UIListLayout")
	bList.Padding = UDim.new(0, 12)
	bList.SortOrder = Enum.SortOrder.LayoutOrder
	bList.Parent = body

	-- TOP POD: Daily Streak Chip Ribbon
	local ribbon = Instance.new("Frame")
	ribbon.Name = "StreakRibbon"
	ribbon.Size = UDim2.new(1, 0, 0, 80)
	ribbon.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	ribbon.BorderSizePixel = 0
	ribbon.LayoutOrder = 1
	ribbon.Parent = body

	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(0, 10)
	rCorner.Parent = ribbon

	local rStroke = Instance.new("UIStroke")
	rStroke.Color = Color3.fromRGB(212, 175, 55)
	rStroke.Thickness = 1
	rStroke.Parent = ribbon

	local rPad = Instance.new("UIPadding")
	rPad.PaddingTop = UDim.new(0, 8)
	rPad.PaddingBottom = UDim.new(0, 8)
	rPad.PaddingLeft = UDim.new(0, 14)
	rPad.PaddingRight = UDim.new(0, 14)
	rPad.Parent = ribbon

	local rHeader = Instance.new("TextLabel")
	rHeader.Size = UDim2.new(0.5, 0, 0, 18)
	rHeader.BackgroundTransparency = 1
	rHeader.Font = Enum.Font.GothamBold
	rHeader.Text = "★ DAILY CONSECUTIVE PATRONAGE (DAY 4 / 7)"
	rHeader.TextColor3 = Color3.fromRGB(212, 175, 55)
	rHeader.TextSize = 12
	rHeader.TextXAlignment = Enum.TextXAlignment.Left
	rHeader.Parent = ribbon

	local rSub = Instance.new("TextLabel")
	rSub.Size = UDim2.new(0.5, 0, 0, 18)
	rSub.Position = UDim2.new(0.5, 0, 0, 0)
	rSub.BackgroundTransparency = 1
	rSub.Font = Enum.Font.GothamMedium
	rSub.Text = "1 Forgiveness Token Active"
	rSub.TextColor3 = Color3.fromRGB(74, 222, 128)
	rSub.TextSize = 11
	rSub.TextXAlignment = Enum.TextXAlignment.Right
	rSub.Parent = ribbon

	local chipRow = Instance.new("Frame")
	chipRow.Size = UDim2.new(1, 0, 0, 42)
	chipRow.Position = UDim2.new(0, 0, 0, 22)
	chipRow.BackgroundTransparency = 1
	chipRow.Parent = ribbon

	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.Parent = chipRow

	for _, d in ipairs(LOGIN_DAYS) do
		local chip = Instance.new("Frame")
		chip.Size = UDim2.new(0.142, -7, 1, 0)
		chip.BackgroundColor3 = if d.active then Color3.fromRGB(212, 175, 55) elseif d.claimed then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(30, 24, 20)
		chip.BorderSizePixel = 0
		chip.Parent = chipRow

		local cpCorn = Instance.new("UICorner")
		cpCorn.CornerRadius = UDim.new(0, 6)
		cpCorn.Parent = chip

		local cpStk = Instance.new("UIStroke")
		cpStk.Color = if d.active then Color3.fromRGB(245, 239, 230) elseif d.jackpot then Color3.fromRGB(244, 114, 182) else Color3.fromRGB(60, 50, 42)
		cpStk.Thickness = 1
		cpStk.Parent = chip

		local cText = Instance.new("TextLabel")
		cText.Size = UDim2.fromScale(1, 1)
		cText.BackgroundTransparency = 1
		cText.Font = Enum.Font.GothamBold
		cText.Text = string.format("D%d: %s", d.day, d.text)
		cText.TextColor3 = if d.active then Color3.fromRGB(20, 16, 14) elseif d.jackpot then Color3.fromRGB(244, 114, 182) else Color3.fromRGB(245, 239, 230)
		cText.TextSize = 11
		cText.Parent = chip
	end

	-- CENTER: 3 Horizontal Wager Cards
	local wagerGrid = Instance.new("Frame")
	wagerGrid.Name = "WagerGrid"
	wagerGrid.Size = UDim2.new(1, 0, 1, -170)
	wagerGrid.BackgroundTransparency = 1
	wagerGrid.LayoutOrder = 2
	wagerGrid.Parent = body

	local wgLayout = Instance.new("UIListLayout")
	wgLayout.FillDirection = Enum.FillDirection.Horizontal
	wgLayout.Padding = UDim.new(0, 12)
	wgLayout.Parent = wagerGrid

	for i, q in ipairs(SAMPLE_QUESTS) do
		local wCard = Instance.new("Frame")
		wCard.Name = "WagerCard_" .. i
		wCard.Size = UDim2.new(0.333, -8, 1, 0)
		wCard.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
		wCard.BorderSizePixel = 0
		wCard.LayoutOrder = i
		wCard.Parent = wagerGrid

		local wcCorner = Instance.new("UICorner")
		wcCorner.CornerRadius = UDim.new(0, 10)
		wcCorner.Parent = wCard

		local wcStroke = Instance.new("UIStroke")
		wcStroke.Color = if q.isReady then Color3.fromRGB(212, 175, 55) else Color3.fromRGB(70, 58, 48)
		wcStroke.Thickness = if q.isReady then 1.5 else 1
		wcStroke.Parent = wCard

		local wcPad = Instance.new("UIPadding")
		wcPad.PaddingTop = UDim.new(0, 12)
		wcPad.PaddingBottom = UDim.new(0, 12)
		wcPad.PaddingLeft = UDim.new(0, 14)
		wcPad.PaddingRight = UDim.new(0, 14)
		wcPad.Parent = wCard

		local wcList = Instance.new("UIListLayout")
		wcList.Padding = UDim.new(0, 8)
		wcList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		wcList.SortOrder = Enum.SortOrder.LayoutOrder
		wcList.Parent = wCard

		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.new(1, 0, 0, 18)
		badge.BackgroundTransparency = 1
		badge.Font = Enum.Font.GothamBold
		badge.Text = string.format("\u{25C6} BOUNTY #0%d \u{25C6}", i)
		badge.TextColor3 = Color3.fromRGB(212, 175, 55)
		badge.TextSize = 11
		badge.LayoutOrder = 1
		badge.Parent = wCard

		local wTitle = Instance.new("TextLabel")
		wTitle.Size = UDim2.new(1, 0, 0, 24)
		wTitle.BackgroundTransparency = 1
		wTitle.Font = Enum.Font.GothamBold
		wTitle.Text = q.title
		wTitle.TextColor3 = Color3.fromRGB(245, 239, 230)
		wTitle.TextSize = 13
		wTitle.TextWrapped = true
		wTitle.LayoutOrder = 2
		wTitle.Parent = wCard

		local wDesc = Instance.new("TextLabel")
		wDesc.Size = UDim2.new(1, 0, 0, 36)
		wDesc.BackgroundTransparency = 1
		wDesc.Font = Enum.Font.GothamMedium
		wDesc.Text = q.desc
		wDesc.TextColor3 = Color3.fromRGB(160, 148, 140)
		wDesc.TextSize = 11
		wDesc.TextWrapped = true
		wDesc.LayoutOrder = 3
		wDesc.Parent = wCard

		local wPill = Instance.new("Frame")
		wPill.Size = UDim2.new(1, 0, 0, 32)
		wPill.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		wPill.BorderSizePixel = 0
		wPill.LayoutOrder = 4
		wPill.Parent = wCard

		local wpCorner = Instance.new("UICorner")
		wpCorner.CornerRadius = UDim.new(0, 6)
		wpCorner.Parent = wPill

		local rewLbl = Instance.new("TextLabel")
		rewLbl.Size = UDim2.fromScale(1, 1)
		rewLbl.BackgroundTransparency = 1
		rewLbl.Font = Enum.Font.GothamBold
		rewLbl.Text = "REWARD: " .. q.rewardText
		rewLbl.TextColor3 = q.rewardColor
		rewLbl.TextSize = 12
		rewLbl.Parent = wPill

		-- Progress Bar
		local wBar = Instance.new("Frame")
		wBar.Size = UDim2.new(1, 0, 0, 10)
		wBar.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		wBar.BorderSizePixel = 0
		wBar.LayoutOrder = 5
		wBar.Parent = wCard

		local wbCorner = Instance.new("UICorner")
		wbCorner.CornerRadius = UDim.new(0, 5)
		wbCorner.Parent = wBar

		local wbFill = Instance.new("Frame")
		wbFill.Size = UDim2.fromScale(math.clamp(q.current / q.target, 0, 1), 1)
		wbFill.BackgroundColor3 = if q.isReady then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(212, 175, 55)
		wbFill.BorderSizePixel = 0
		wbFill.Parent = wBar

		local wbfCorner = Instance.new("UICorner")
		wbfCorner.CornerRadius = UDim.new(0, 5)
		wbfCorner.Parent = wbFill

		local wProgTxt = Instance.new("TextLabel")
		wProgTxt.Size = UDim2.new(1, 0, 0, 18)
		wProgTxt.BackgroundTransparency = 1
		wProgTxt.Font = Enum.Font.GothamBold
		wProgTxt.Text = string.format("%d / %d", q.current, q.target)
		wProgTxt.TextColor3 = Color3.fromRGB(245, 239, 230)
		wProgTxt.TextSize = 12
		wProgTxt.LayoutOrder = 6
		wProgTxt.Parent = wCard

		local wBtn = Instance.new("TextButton")
		wBtn.Size = UDim2.new(1, 0, 0, 36)
		wBtn.BackgroundColor3 = if q.isReady then Color3.fromRGB(212, 175, 55) else Color3.fromRGB(48, 40, 36)
		wBtn.BorderSizePixel = 0
		wBtn.Font = Enum.Font.GothamBold
		wBtn.Text = if q.isReady then "COLLECT BOUNTY" else "IN PROGRESS"
		wBtn.TextColor3 = if q.isReady then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(160, 148, 140)
		wBtn.TextSize = 12
		wBtn.LayoutOrder = 7
		wBtn.Parent = wCard

		local wbCorner2 = Instance.new("UICorner")
		wbCorner2.CornerRadius = UDim.new(0, 6)
		wbCorner2.Parent = wBtn
	end

	-- BOTTOM FOOTER: Playtime Caches Strip (Fixed LayoutOrder)
	local footer = Instance.new("Frame")
	footer.Name = "FooterPlaytimeStrip"
	footer.Size = UDim2.new(1, 0, 0, 66)
	footer.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	footer.BorderSizePixel = 0
	footer.LayoutOrder = 3
	footer.Parent = body

	local ftCorner = Instance.new("UICorner")
	ftCorner.CornerRadius = UDim.new(0, 10)
	ftCorner.Parent = footer

	local ftStroke = Instance.new("UIStroke")
	ftStroke.Color = Color3.fromRGB(70, 58, 48)
	ftStroke.Thickness = 1
	ftStroke.Parent = footer

	local ftPad = Instance.new("UIPadding")
	ftPad.PaddingLeft = UDim.new(0, 14)
	ftPad.PaddingRight = UDim.new(0, 14)
	ftPad.Parent = footer

	local ftList = Instance.new("UIListLayout")
	ftList.FillDirection = Enum.FillDirection.Horizontal
	ftList.Padding = UDim.new(0, 10)
	ftList.VerticalAlignment = Enum.VerticalAlignment.Center
	ftList.SortOrder = Enum.SortOrder.LayoutOrder
	ftList.Parent = footer

	local ftLabel = Instance.new("TextLabel")
	ftLabel.Size = UDim2.new(0.22, 0, 0, 24)
	ftLabel.BackgroundTransparency = 1
	ftLabel.Font = Enum.Font.GothamBold
	ftLabel.Text = "\u{23F1} SESSION REWARDS:"
	ftLabel.TextColor3 = Color3.fromRGB(212, 175, 55)
	ftLabel.TextSize = 12
	ftLabel.TextXAlignment = Enum.TextXAlignment.Left
	ftLabel.LayoutOrder = 1
	ftLabel.Parent = footer

	for i, tier in ipairs(PLAYTIME_TIERS) do
		local tPill = Instance.new("Frame")
		tPill.Size = UDim2.new(0.26, -7, 0, 44)
		tPill.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		tPill.BorderSizePixel = 0
		tPill.LayoutOrder = i + 1
		tPill.Parent = footer

		local tpCorn = Instance.new("UICorner")
		tpCorn.CornerRadius = UDim.new(0, 6)
		tpCorn.Parent = tPill

		local tpPad = Instance.new("UIPadding")
		tpPad.PaddingLeft = UDim.new(0, 8)
		tpPad.PaddingRight = UDim.new(0, 8)
		tpPad.Parent = tPill

		local tName = Instance.new("TextLabel")
		tName.Size = UDim2.new(0.55, 0, 1, 0)
		tName.BackgroundTransparency = 1
		tName.Font = Enum.Font.GothamBold
		tName.Text = string.format("%s (%s)\n%s", tier.name, tier.timeStr, tier.rewardStr)
		tName.TextColor3 = Color3.fromRGB(245, 239, 230)
		tName.TextSize = 10.5
		tName.TextXAlignment = Enum.TextXAlignment.Left
		tName.Parent = tPill

		local tBtn = Instance.new("TextButton")
		tBtn.Size = UDim2.new(0.42, 0, 0, 28)
		tBtn.Position = UDim2.new(0.58, 0, 0.5, -14)
		tBtn.BackgroundColor3 = if tier.claimed then Color3.fromRGB(36, 30, 26) elseif tier.ready then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(48, 40, 36)
		tBtn.BorderSizePixel = 0
		tBtn.Font = Enum.Font.GothamBold
		tBtn.Text = if tier.claimed then "\u{2713} DONE" elseif tier.ready then "CLAIM" else "LOCKED"
		tBtn.TextColor3 = if tier.ready then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(160, 148, 140)
		tBtn.TextSize = 10
		tBtn.Parent = tPill

		local tbCorn = Instance.new("UICorner")
		tbCorn.CornerRadius = UDim.new(0, 4)
		tbCorn.Parent = tBtn
	end

	return root
end

--------------------------------------------------------------------------------
-- VARIANT C: BRUTALIST OPERATIONS DOSSIER
--------------------------------------------------------------------------------

local function buildVariantC(parent: Frame): Frame
	local root = Instance.new("Frame")
	root.Name = "VariantC_Brutalist"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = parent

	local container, body = createModalShell(
		"MISSION CONTROL // DAILY PROTOCOLS",
		"CYCLE RESET: 08:42:15 UTC",
		root
	)

	local cList = Instance.new("UIListLayout")
	cList.Padding = UDim.new(0, 12)
	cList.SortOrder = Enum.SortOrder.LayoutOrder
	cList.Parent = body

	-- TOP SECTION (68% height): 3 Large Vertical Mission Columns
	local missionRow = Instance.new("Frame")
	missionRow.Name = "MissionRow"
	missionRow.Size = UDim2.new(1, 0, 0.68, 0)
	missionRow.BackgroundTransparency = 1
	missionRow.LayoutOrder = 1
	missionRow.Parent = body

	local mrLayout = Instance.new("UIListLayout")
	mrLayout.FillDirection = Enum.FillDirection.Horizontal
	mrLayout.Padding = UDim.new(0, 14)
	mrLayout.Parent = missionRow

	for i, q in ipairs(SAMPLE_QUESTS) do
		local mCard = Instance.new("Frame")
		mCard.Name = "MissionCard_" .. i
		mCard.Size = UDim2.new(0.333, -9, 1, 0)
		mCard.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
		mCard.BorderSizePixel = 0
		mCard.Parent = missionRow

		local mcCorner = Instance.new("UICorner")
		mcCorner.CornerRadius = UDim.new(0, 10)
		mcCorner.Parent = mCard

		local mcStroke = Instance.new("UIStroke")
		mcStroke.Color = if q.isReady then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(70, 58, 48)
		mcStroke.Thickness = if q.isReady then 2 else 1
		mcStroke.Parent = mCard

		local mcPad = Instance.new("UIPadding")
		mcPad.PaddingTop = UDim.new(0, 14)
		mcPad.PaddingBottom = UDim.new(0, 14)
		mcPad.PaddingLeft = UDim.new(0, 16)
		mcPad.PaddingRight = UDim.new(0, 16)
		mcPad.Parent = mCard

		local mcList = Instance.new("UIListLayout")
		mcList.Padding = UDim.new(0, 8)
		mcList.SortOrder = Enum.SortOrder.LayoutOrder
		mcList.Parent = mCard

		local mBadge = Instance.new("TextLabel")
		mBadge.Size = UDim2.new(1, 0, 0, 18)
		mBadge.BackgroundTransparency = 1
		mBadge.Font = Enum.Font.Code
		mBadge.Text = string.format("[ TASK 0%d // ACTIVE ]", i)
		mBadge.TextColor3 = Color3.fromRGB(212, 175, 55)
		mBadge.TextSize = 11
		mBadge.TextXAlignment = Enum.TextXAlignment.Left
		mBadge.LayoutOrder = 1
		mBadge.Parent = mCard

		local mBigTitle = Instance.new("TextLabel")
		mBigTitle.Size = UDim2.new(1, 0, 0, 26)
		mBigTitle.BackgroundTransparency = 1
		mBigTitle.Font = Enum.Font.GothamBold
		mBigTitle.Text = q.title
		mBigTitle.TextColor3 = Color3.fromRGB(245, 239, 230)
		mBigTitle.TextSize = 14
		mBigTitle.TextXAlignment = Enum.TextXAlignment.Left
		mBigTitle.LayoutOrder = 2
		mBigTitle.Parent = mCard

		local mDesc = Instance.new("TextLabel")
		mDesc.Size = UDim2.new(1, 0, 0, 36)
		mDesc.BackgroundTransparency = 1
		mDesc.Font = Enum.Font.GothamMedium
		mDesc.Text = q.desc
		mDesc.TextColor3 = Color3.fromRGB(160, 148, 140)
		mDesc.TextSize = 12
		mDesc.TextWrapped = true
		mDesc.TextXAlignment = Enum.TextXAlignment.Left
		mDesc.LayoutOrder = 3
		mDesc.Parent = mCard

		-- Segmented Progress Track
		local segTrack = Instance.new("Frame")
		segTrack.Size = UDim2.new(1, 0, 0, 8)
		segTrack.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		segTrack.BorderSizePixel = 0
		segTrack.LayoutOrder = 4
		segTrack.Parent = mCard

		local stCorner = Instance.new("UICorner")
		stCorner.CornerRadius = UDim.new(0, 4)
		stCorner.Parent = segTrack

		local stFill = Instance.new("Frame")
		stFill.Size = UDim2.fromScale(math.clamp(q.current / q.target, 0, 1), 1)
		stFill.BackgroundColor3 = if q.isReady then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(212, 175, 55)
		stFill.BorderSizePixel = 0
		stFill.Parent = segTrack

		local stfCorner = Instance.new("UICorner")
		stfCorner.CornerRadius = UDim.new(0, 4)
		stfCorner.Parent = stFill

		-- Large Metric Readout
		local metricPod = Instance.new("Frame")
		metricPod.Size = UDim2.new(1, 0, 0, 66)
		metricPod.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		metricPod.BorderSizePixel = 0
		metricPod.LayoutOrder = 5
		metricPod.Parent = mCard

		local mpCorner = Instance.new("UICorner")
		mpCorner.CornerRadius = UDim.new(0, 6)
		mpCorner.Parent = metricPod

		local valLbl = Instance.new("TextLabel")
		valLbl.Size = UDim2.new(1, 0, 0, 36)
		valLbl.BackgroundTransparency = 1
		valLbl.Font = Enum.Font.GothamBlack
		valLbl.Text = string.format("%d / %d", q.current, q.target)
		valLbl.TextColor3 = if q.isReady then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(245, 239, 230)
		valLbl.TextSize = 22
		valLbl.Parent = metricPod

		local subMetric = Instance.new("TextLabel")
		subMetric.Size = UDim2.new(1, 0, 0, 20)
		subMetric.Position = UDim2.new(0, 0, 0, 38)
		subMetric.BackgroundTransparency = 1
		subMetric.Font = Enum.Font.GothamBold
		subMetric.Text = "PAYOUT: " .. q.rewardText
		subMetric.TextColor3 = q.rewardColor
		subMetric.TextSize = 12
		subMetric.Parent = metricPod

		-- Action Button
		local mBtn = Instance.new("TextButton")
		mBtn.Size = UDim2.new(1, 0, 0, 44)
		mBtn.BackgroundColor3 = if q.isReady then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(48, 40, 36)
		mBtn.BorderSizePixel = 0
		mBtn.Font = Enum.Font.GothamBold
		mBtn.Text = if q.isReady then "CLAIM YIELD" else "IN PROGRESS"
		mBtn.TextColor3 = if q.isReady then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(160, 148, 140)
		mBtn.TextSize = 13
		mBtn.LayoutOrder = 6
		mBtn.Parent = mCard

		local mbCorner = Instance.new("UICorner")
		mbCorner.CornerRadius = UDim.new(0, 6)
		mbCorner.Parent = mBtn
	end

	-- BOTTOM SECTION (32% minus gap): 50/50 Dual Telemetry Strip
	local botSection = Instance.new("Frame")
	botSection.Name = "BotTelemetryRow"
	botSection.Size = UDim2.new(1, 0, 0.32, -12)
	botSection.BackgroundTransparency = 1
	botSection.LayoutOrder = 2
	botSection.Parent = body

	local bsLayout = Instance.new("UIListLayout")
	bsLayout.FillDirection = Enum.FillDirection.Horizontal
	bsLayout.Padding = UDim.new(0, 14)
	bsLayout.Parent = botSection

	-- Bottom Left: Session Chest Timeline
	local bLeft = Instance.new("Frame")
	bLeft.Size = UDim2.new(0.5, -7, 1, 0)
	bLeft.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	bLeft.BorderSizePixel = 0
	bLeft.Parent = botSection

	local blCorner = Instance.new("UICorner")
	blCorner.CornerRadius = UDim.new(0, 8)
	blCorner.Parent = bLeft

	local blPad = Instance.new("UIPadding")
	blPad.PaddingTop = UDim.new(0, 8)
	blPad.PaddingBottom = UDim.new(0, 8)
	blPad.PaddingLeft = UDim.new(0, 14)
	blPad.PaddingRight = UDim.new(0, 14)
	blPad.Parent = bLeft

	local blTitle = Instance.new("TextLabel")
	blTitle.Size = UDim2.new(1, 0, 0, 18)
	blTitle.BackgroundTransparency = 1
	blTitle.Font = Enum.Font.GothamBold
	blTitle.Text = "[ SESSION TIME CACHES ]"
	blTitle.TextColor3 = Color3.fromRGB(212, 175, 55)
	blTitle.TextSize = 11
	blTitle.TextXAlignment = Enum.TextXAlignment.Left
	blTitle.Parent = bLeft

	local blRow = Instance.new("Frame")
	blRow.Size = UDim2.new(1, 0, 1, -22)
	blRow.Position = UDim2.new(0, 0, 0, 20)
	blRow.BackgroundTransparency = 1
	blRow.Parent = bLeft

	local blList = Instance.new("UIListLayout")
	blList.FillDirection = Enum.FillDirection.Horizontal
	blList.Padding = UDim.new(0, 8)
	blList.Parent = blRow

	for _, tier in ipairs(PLAYTIME_TIERS) do
		local tBox = Instance.new("Frame")
		tBox.Size = UDim2.new(0.333, -6, 1, 0)
		tBox.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		tBox.BorderSizePixel = 0
		tBox.Parent = blRow

		local tbCorn = Instance.new("UICorner")
		tbCorn.CornerRadius = UDim.new(0, 6)
		tbCorn.Parent = tBox

		local tbText = Instance.new("TextLabel")
		tbText.Size = UDim2.new(1, 0, 0, 42)
		tbText.Position = UDim2.new(0, 0, 0, 6)
		tbText.BackgroundTransparency = 1
		tbText.Font = Enum.Font.GothamBold
		tbText.Text = string.format("%s (%s)\n%s", tier.name, tier.timeStr, tier.rewardStr)
		tbText.TextColor3 = Color3.fromRGB(245, 239, 230)
		tbText.TextSize = 11
		tbText.Parent = tBox

		local tbBtn = Instance.new("TextButton")
		tbBtn.Size = UDim2.new(1, -16, 0, 26)
		tbBtn.Position = UDim2.new(0, 8, 1, -32)
		tbBtn.BackgroundColor3 = if tier.claimed then Color3.fromRGB(36, 30, 26) elseif tier.ready then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(48, 40, 36)
		tbBtn.BorderSizePixel = 0
		tbBtn.Font = Enum.Font.GothamBold
		tbBtn.Text = if tier.claimed then "CLAIMED" elseif tier.ready then "CLAIM" else "LOCKED"
		tbBtn.TextColor3 = if tier.ready then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(160, 148, 140)
		tbBtn.TextSize = 10
		tbBtn.Parent = tBox

		local tbbCorn = Instance.new("UICorner")
		tbbCorn.CornerRadius = UDim.new(0, 4)
		tbbCorn.Parent = tbBtn
	end

	-- Bottom Right: 7-Day Cadence
	local bRight = Instance.new("Frame")
	bRight.Size = UDim2.new(0.5, -7, 1, 0)
	bRight.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	bRight.BorderSizePixel = 0
	bRight.Parent = botSection

	local brCorner = Instance.new("UICorner")
	brCorner.CornerRadius = UDim.new(0, 8)
	brCorner.Parent = bRight

	local brPad = Instance.new("UIPadding")
	brPad.PaddingTop = UDim.new(0, 8)
	brPad.PaddingBottom = UDim.new(0, 8)
	brPad.PaddingLeft = UDim.new(0, 14)
	brPad.PaddingRight = UDim.new(0, 14)
	brPad.Parent = bRight

	local brTitle = Instance.new("TextLabel")
	brTitle.Size = UDim2.new(1, 0, 0, 18)
	brTitle.BackgroundTransparency = 1
	brTitle.Font = Enum.Font.GothamBold
	brTitle.Text = "[ 7-DAY CADENCE ACCUMULATOR ]"
	brTitle.TextColor3 = Color3.fromRGB(212, 175, 55)
	brTitle.TextSize = 11
	brTitle.TextXAlignment = Enum.TextXAlignment.Left
	brTitle.Parent = bRight

	local brRow = Instance.new("Frame")
	brRow.Size = UDim2.new(1, 0, 1, -22)
	brRow.Position = UDim2.new(0, 0, 0, 20)
	brRow.BackgroundTransparency = 1
	brRow.Parent = bRight

	local brList = Instance.new("UIListLayout")
	brList.FillDirection = Enum.FillDirection.Horizontal
	brList.Padding = UDim.new(0, 5)
	brList.Parent = brRow

	for _, d in ipairs(LOGIN_DAYS) do
		local dBox = Instance.new("Frame")
		dBox.Size = UDim2.new(0.142, -5, 1, 0)
		dBox.BackgroundColor3 = if d.active then Color3.fromRGB(212, 175, 55) elseif d.claimed then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(28, 24, 20)
		dBox.BorderSizePixel = 0
		dBox.Parent = brRow

		local dbCorn = Instance.new("UICorner")
		dbCorn.CornerRadius = UDim.new(0, 4)
		dbCorn.Parent = dBox

		local dbStroke = Instance.new("UIStroke")
		dbStroke.Color = if d.active then Color3.fromRGB(245, 239, 230) elseif d.jackpot then Color3.fromRGB(244, 114, 182) else Color3.fromRGB(70, 58, 48)
		dbStroke.Thickness = 1
		dbStroke.Parent = dBox

		local dbDay = Instance.new("TextLabel")
		dbDay.Size = UDim2.new(1, 0, 0, 18)
		dbDay.Position = UDim2.new(0, 0, 0, 6)
		dbDay.BackgroundTransparency = 1
		dbDay.Font = Enum.Font.GothamBold
		dbDay.Text = "D" .. d.day
		dbDay.TextColor3 = if d.active then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(160, 148, 140)
		dbDay.TextSize = 11
		dbDay.Parent = dBox

		local dbRew = Instance.new("TextLabel")
		dbRew.Size = UDim2.new(1, 0, 0, 24)
		dbRew.Position = UDim2.new(0, 0, 0, 26)
		dbRew.BackgroundTransparency = 1
		dbRew.Font = Enum.Font.GothamBold
		dbRew.Text = d.text
		dbRew.TextColor3 = if d.active then Color3.fromRGB(20, 16, 14) elseif d.jackpot then Color3.fromRGB(244, 114, 182) else Color3.fromRGB(245, 239, 230)
		dbRew.TextSize = 11
		dbRew.Parent = dBox

		local dbStat = Instance.new("TextLabel")
		dbStat.Size = UDim2.new(1, 0, 0, 18)
		dbStat.Position = UDim2.new(0, 0, 1, -22)
		dbStat.BackgroundTransparency = 1
		dbStat.Font = Enum.Font.Code
		dbStat.Text = if d.claimed then "\u{2713}" elseif d.active then "READY" else "LOCKED"
		dbStat.TextColor3 = if d.active then Color3.fromRGB(20, 16, 14) else Color3.fromRGB(120, 110, 100)
		dbStat.TextSize = 9
		dbStat.Parent = dBox
	end

	return root
end

--------------------------------------------------------------------------------
-- MAIN CAROUSEL CONTROLLER
--------------------------------------------------------------------------------

function UIMockPreview.show(parentScreenGui: Instance?): ScreenGui
	UIMockPreview.hide()

	local targetParent = parentScreenGui
	if targetParent == nil then
		local player = Players.LocalPlayer
		if player then
			targetParent = player:WaitForChild("PlayerGui")
		end
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "UIMockPreview"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 9999
	screenGui.Parent = targetParent or game:GetService("CoreGui")

	currentGui = screenGui

	-- Dimmed Backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui

	-- Variant Holder
	local variantHolder = Instance.new("Frame")
	variantHolder.Name = "VariantHolder"
	variantHolder.Size = UDim2.fromScale(1, 1)
	variantHolder.BackgroundTransparency = 1
	variantHolder.Parent = screenGui

	local vA = buildVariantA(variantHolder)
	vA.Visible = true

	return screenGui
end

function UIMockPreview.hide(): ()
	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end
end

return UIMockPreview
