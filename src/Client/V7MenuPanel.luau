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

local function buildQuestsOverlay(screenGui: ScreenGui, overlays: { [string]: Frame }): (any) -> ()
	local questsOverlay, oldQuestsBody = UITheme.overlay("Daily Quests")
	questsOverlay.Parent = screenGui
	overlays["quests"] = questsOverlay

	local questsPanelContainer = questsOverlay:FindFirstChild("Panel") :: Frame?
	if not questsPanelContainer then
		questsPanelContainer = questsOverlay:FindFirstChildOfClass("Frame")
	end

	local questResetLabel: TextLabel? = nil

	if questsPanelContainer then
		questsPanelContainer.BackgroundColor3 = Color3.fromRGB(26, 22, 20)
		questsPanelContainer.BackgroundTransparency = 0

		local panelCorner = questsPanelContainer:FindFirstChildOfClass("UICorner")
		if not panelCorner then
			panelCorner = Instance.new("UICorner")
			panelCorner.CornerRadius = UDim.new(0, 12)
			panelCorner.Parent = questsPanelContainer
		else
			panelCorner.CornerRadius = UDim.new(0, 12)
		end

		local panelStroke = questsPanelContainer:FindFirstChildOfClass("UIStroke")
		if not panelStroke then
			panelStroke = Instance.new("UIStroke")
			panelStroke.Color = Color3.fromRGB(212, 175, 55)
			panelStroke.Thickness = 2
			panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			panelStroke.Parent = questsPanelContainer
		else
			panelStroke.Color = Color3.fromRGB(212, 175, 55)
			panelStroke.Thickness = 2
			panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		end

		-- Header Bar (Exact 16px margins)
		local header = questsPanelContainer:FindFirstChild("Header") :: Frame?
		if header then
			local hList = header:FindFirstChildOfClass("UIListLayout")
			if hList then
				hList:Destroy()
			end

			header.Size = UDim2.new(1, -32, 0, 48)
			header.Position = UDim2.new(0, 16, 0, 16)
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
				hStroke.Color = Color3.fromRGB(212, 175, 55)
				hStroke.Thickness = 1
				hStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				hStroke.Parent = header
			end

			local hPad = header:FindFirstChildOfClass("UIPadding")
			if not hPad then
				hPad = Instance.new("UIPadding")
				hPad.PaddingLeft = UDim.new(0, 16)
				hPad.PaddingRight = UDim.new(0, 16)
				hPad.Parent = header
			end

			local titleLbl = header:FindFirstChild("Title") :: TextLabel?
			if titleLbl then
				local titleFlex = titleLbl:FindFirstChildOfClass("UIFlexItem")
				if titleFlex then
					titleFlex:Destroy()
				end
				titleLbl.Text = "QUESTS"
				titleLbl.TextColor3 = Color3.fromRGB(212, 175, 55)
				titleLbl.Font = Enum.Font.GothamBold
				titleLbl.TextSize = 20
				titleLbl.TextXAlignment = Enum.TextXAlignment.Left
				titleLbl.Position = UDim2.new(0, 0, 0, 0)
				titleLbl.Size = UDim2.new(0.5, 0, 1, 0)
			end

			-- Reset countdown label on the right
			local resetLbl = header:FindFirstChild("ResetTimer") :: TextLabel?
			if not resetLbl then
				resetLbl = Instance.new("TextLabel")
				resetLbl.Name = "ResetTimer"
				resetLbl.Size = UDim2.new(0.5, -45, 1, 0)
				resetLbl.Position = UDim2.new(0.5, 0, 0, 0)
				resetLbl.BackgroundTransparency = 1
				resetLbl.Font = Enum.Font.GothamBold
				resetLbl.Text = "Resets in: --"
				resetLbl.TextColor3 = Color3.fromRGB(160, 148, 140)
				resetLbl.TextSize = 13.5
				resetLbl.TextXAlignment = Enum.TextXAlignment.Right
				resetLbl.Parent = header
			end
			questResetLabel = resetLbl

			local closeBtn = header:FindFirstChild("Close") :: TextButton?
			if closeBtn then
				closeBtn.Size = UDim2.new(0, 32, 0, 32)
				closeBtn.Position = UDim2.new(1, -32, 0.5, -16)
				closeBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
				closeBtn.BackgroundTransparency = 0
				closeBtn.TextColor3 = Color3.fromRGB(212, 175, 55)
				closeBtn.Font = Enum.Font.GothamBold
				closeBtn.Text = "\u{00D7}"
				closeBtn.TextSize = 20
				closeBtn.TextStrokeTransparency = 1

				local cCorner = closeBtn:FindFirstChildOfClass("UICorner")
				if not cCorner then
					cCorner = Instance.new("UICorner")
					cCorner.CornerRadius = UDim.new(0, 6)
					cCorner.Parent = closeBtn
				end

				closeBtn.MouseButton1Click:Connect(function()
					questsOverlay.Visible = false
				end)
			end
		end

		local divider = questsPanelContainer:FindFirstChild("Divider") :: Frame?
		if divider then
			divider.Visible = false
		end

		if oldQuestsBody then
			oldQuestsBody.Visible = false
		end
	end

	-- Dedicated Non-Clipping Body Container (Exact 16px margins on all 4 sides)
	local questVaultBody = Instance.new("Frame")
	questVaultBody.Name = "QuestVaultBody"
	questVaultBody.Size = UDim2.new(1, -32, 1, -92)
	questVaultBody.Position = UDim2.new(0, 16, 0, 76)
	questVaultBody.BackgroundTransparency = 1
	questVaultBody.ClipsDescendants = false
	questVaultBody.Parent = questsPanelContainer or questsOverlay

	-- Main 58/42 Dual-Column Row Layout
	local mainRowLayout = Instance.new("UIListLayout")
	mainRowLayout.FillDirection = Enum.FillDirection.Horizontal
	mainRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainRowLayout.Padding = UDim.new(0, 14)
	mainRowLayout.Parent = questVaultBody

	-- Quest Definitions Lookup
	local QUEST_INFO: { [string]: { title: string, desc: string, rewardText: string, rewardColor: Color3 } } = {
		roll25 = {
			title = "MASS REVOLUTION I",
			desc = "Perform 25 physical dice rolls in the arena.",
			rewardText = "+$500 CASH",
			rewardColor = Color3.fromRGB(74, 222, 128),
		},
		roll100 = {
			title = "HIGH-FREQUENCY CALIBRATION",
			desc = "Perform 100 physical dice rolls in the arena.",
			rewardText = "+$2,500 CASH",
			rewardColor = Color3.fromRGB(74, 222, 128),
		},
		roll500 = {
			title = "OVERCLOCK HARVEST",
			desc = "Perform 500 physical dice rolls in the arena.",
			rewardText = "+40 GEMS",
			rewardColor = Color3.fromRGB(56, 189, 248),
		},
		streak5 = {
			title = "MOMENTUM VECTOR",
			desc = "Attain an unbroken consecutive roll streak of 5.",
			rewardText = "+$750 CASH",
			rewardColor = Color3.fromRGB(74, 222, 128),
		},
		streak15 = {
			title = "CRITICAL ALIGNMENT RUN",
			desc = "Attain an unbroken consecutive roll streak of 15.",
			rewardText = "+30 GEMS",
			rewardColor = Color3.fromRGB(56, 189, 248),
		},
		forge3 = {
			title = "CORE WEIGHTING",
			desc = "Modify and forge 3 die face mass distributions.",
			rewardText = "+$600 CASH",
			rewardColor = Color3.fromRGB(74, 222, 128),
		},
		forge10 = {
			title = "MASS EQUILIBRIUM SHIFT",
			desc = "Modify and forge 10 die face mass distributions.",
			rewardText = "+25 GEMS",
			rewardColor = Color3.fromRGB(56, 189, 248),
		},
	}

	-- Left Column (58%): 3 Heavy Quest Directives
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftQuestsCol"
	leftCol.Size = UDim2.new(0.58, -7, 1, 0)
	leftCol.BackgroundTransparency = 1
	leftCol.LayoutOrder = 1
	leftCol.Parent = questVaultBody

	local lList = Instance.new("UIListLayout")
	lList.Padding = UDim.new(0, 10)
	lList.SortOrder = Enum.SortOrder.LayoutOrder
	lList.Parent = leftCol

	local questRows: { any } = {}

	for i = 1, 3 do
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
		cStroke.Color = Color3.fromRGB(70, 58, 48)
		cStroke.Thickness = 1
		cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cStroke.Parent = card

		local cPad = Instance.new("UIPadding")
		cPad.PaddingTop = UDim.new(0, 8)
		cPad.PaddingBottom = UDim.new(0, 8)
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
		tagLbl.Text = string.format("[ QUEST 0%d ]", i)
		tagLbl.TextColor3 = Color3.fromRGB(212, 175, 55)
		tagLbl.TextSize = 12
		tagLbl.TextXAlignment = Enum.TextXAlignment.Left
		tagLbl.Parent = topRow

		local rewBadge = Instance.new("TextLabel")
		rewBadge.Size = UDim2.new(0.5, 0, 1, 0)
		rewBadge.Position = UDim2.new(0.5, 0, 0, 0)
		rewBadge.BackgroundTransparency = 1
		rewBadge.Font = Enum.Font.GothamBold
		rewBadge.Text = "REWARD: +$2,500 CASH"
		rewBadge.TextColor3 = Color3.fromRGB(74, 222, 128)
		rewBadge.TextSize = 13.5
		rewBadge.TextXAlignment = Enum.TextXAlignment.Right
		rewBadge.Parent = topRow

		-- Title
		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, 0, 0, 22)
		titleLbl.Position = UDim2.new(0, 0, 0, 20)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.Text = "HIGH-FREQUENCY CALIBRATION"
		titleLbl.TextColor3 = Color3.fromRGB(245, 239, 230)
		titleLbl.TextSize = 15
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.Parent = card

		-- Description
		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(1, 0, 0, 20)
		descLbl.Position = UDim2.new(0, 0, 0, 42)
		descLbl.BackgroundTransparency = 1
		descLbl.Font = Enum.Font.GothamMedium
		descLbl.Text = "Perform 100 physical dice rolls in the arena."
		descLbl.TextColor3 = Color3.fromRGB(170, 160, 150)
		descLbl.TextSize = 13
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.Parent = card

		-- Bottom row: Progress Track & Action Button
		local botRow = Instance.new("Frame")
		botRow.Size = UDim2.new(1, 0, 0, 36)
		botRow.Position = UDim2.new(0, 0, 1, -36)
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
		trFill.Size = UDim2.fromScale(0, 1)
		trFill.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
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
		countLbl.Text = "COMPLETION: 0 / 100"
		countLbl.TextColor3 = Color3.fromRGB(180, 170, 160)
		countLbl.TextSize = 11
		countLbl.TextXAlignment = Enum.TextXAlignment.Left
		countLbl.Parent = botRow

		local actionBtn = Instance.new("TextButton")
		actionBtn.Size = UDim2.new(0.37, 0, 1, 0)
		actionBtn.Position = UDim2.new(0.63, 0, 0, 0)
		actionBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
		actionBtn.BorderSizePixel = 0
		actionBtn.Font = Enum.Font.GothamBold
		actionBtn.Text = "IN PROGRESS"
		actionBtn.TextColor3 = Color3.fromRGB(160, 148, 140)
		actionBtn.TextSize = 13
		actionBtn.Parent = botRow

		local abCorner = Instance.new("UICorner")
		abCorner.CornerRadius = UDim.new(0, 6)
		abCorner.Parent = actionBtn

		local rowState = { id = nil :: string?, isReady = false, isClaimed = false }

		actionBtn.MouseButton1Click:Connect(function()
			local id = rowState.id
			if id == nil or not rowState.isReady or rowState.isClaimed then
				return
			end
			actionBtn.Text = "CLAIMING..."
			task.spawn(function()
				local result = NetClient.claimQuest(id)
				if result.ok then
					actionBtn.Text = "CLAIMED \u{2713}"
					actionBtn.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
					actionBtn.TextColor3 = Color3.fromRGB(160, 148, 140)
					rowState.isClaimed = true
					rowState.isReady = false
				else
					actionBtn.Text = "CLAIM REWARD"
					actionBtn.BackgroundColor3 = Color3.fromRGB(74, 222, 128)
					actionBtn.TextColor3 = Color3.fromRGB(20, 16, 14)
				end
			end)
		end)

		table.insert(questRows, {
			card = card,
			stroke = cStroke,
			tag = tagLbl,
			rew = rewBadge,
			title = titleLbl,
			desc = descLbl,
			count = countLbl,
			fill = trFill,
			button = actionBtn,
			state = rowState,
		})
	end

	-- Right Column (42%): Stacked Playtime Rewards & Daily Login
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightProgressionCol"
	rightCol.Size = UDim2.new(0.42, -7, 1, 0)
	rightCol.BackgroundTransparency = 1
	rightCol.LayoutOrder = 2
	rightCol.Parent = questVaultBody

	local rList = Instance.new("UIListLayout")
	rList.Padding = UDim.new(0, 10)
	rList.SortOrder = Enum.SortOrder.LayoutOrder
	rList.Parent = rightCol

	-- Top Pod: Playtime Rewards (60% height)
	local chestPod = Instance.new("Frame")
	chestPod.Name = "PlaytimeRewardsPod"
	chestPod.Size = UDim2.new(1, 0, 0.60, -5)
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
	cpPad.PaddingTop = UDim.new(0, 8)
	cpPad.PaddingBottom = UDim.new(0, 8)
	cpPad.PaddingLeft = UDim.new(0, 14)
	cpPad.PaddingRight = UDim.new(0, 14)
	cpPad.Parent = chestPod

	local cpHeader = Instance.new("TextLabel")
	cpHeader.Size = UDim2.new(1, 0, 0, 18)
	cpHeader.Position = UDim2.new(0, 0, 0, 0)
	cpHeader.BackgroundTransparency = 1
	cpHeader.Font = Enum.Font.GothamBold
	cpHeader.Text = "\u{25B6} PLAYTIME REWARDS"
	cpHeader.TextColor3 = Color3.fromRGB(212, 175, 55)
	cpHeader.TextSize = 13.5
	cpHeader.TextXAlignment = Enum.TextXAlignment.Left
	cpHeader.Parent = chestPod

	local chestScroll = Instance.new("ScrollingFrame")
	chestScroll.Name = "ChestScroll"
	chestScroll.Size = UDim2.new(1, 0, 1, -24)
	chestScroll.Position = UDim2.new(0, 0, 0, 22)
	chestScroll.BackgroundTransparency = 1
	chestScroll.BorderSizePixel = 0
	chestScroll.ScrollBarThickness = 3
	chestScroll.ScrollBarImageColor3 = Color3.fromRGB(212, 175, 55)
	chestScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	chestScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	chestScroll.Parent = chestPod

	local cpList = Instance.new("UIListLayout")
	cpList.Padding = UDim.new(0, 8)
	cpList.SortOrder = Enum.SortOrder.LayoutOrder
	cpList.Parent = chestScroll

	local PLAYTIME_CONFIG = {
		{ id = "Tier1", name = "Tier 1", timeSec = 5 * 60, timeStr = "5 Mins", rewardText = "+$500 CASH", rewardColor = Color3.fromRGB(74, 222, 128) },
		{ id = "Tier2", name = "Tier 2", timeSec = 15 * 60, timeStr = "15 Mins", rewardText = "+$1,500 CASH", rewardColor = Color3.fromRGB(74, 222, 128) },
		{ id = "Tier3", name = "Tier 3", timeSec = 30 * 60, timeStr = "30 Mins", rewardText = "+25 GEMS", rewardColor = Color3.fromRGB(56, 189, 248) },
		{ id = "Tier4", name = "Tier 4", timeSec = 45 * 60, timeStr = "45 Mins", rewardText = "+50 GEMS", rewardColor = Color3.fromRGB(56, 189, 248) },
		{ id = "Tier5", name = "Tier 5", timeSec = 60 * 60, timeStr = "60 Mins", rewardText = "+$10,000 CASH", rewardColor = Color3.fromRGB(74, 222, 128) },
		{ id = "Tier6", name = "Tier 6", timeSec = 90 * 60, timeStr = "90 Mins", rewardText = "+3 DIAMONDS", rewardColor = Color3.fromRGB(244, 114, 182) },
	}

	local sessionStartTime = os.clock()
	local playtimeRows: { any } = {}

	for i, tier in ipairs(PLAYTIME_CONFIG) do
		local tRow = Instance.new("Frame")
		tRow.Size = UDim2.new(1, -6, 0, 68)
		tRow.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
		tRow.BorderSizePixel = 0
		tRow.LayoutOrder = i
		tRow.Parent = chestScroll

		local trCorner2 = Instance.new("UICorner")
		trCorner2.CornerRadius = UDim.new(0, 8)
		trCorner2.Parent = tRow

		local tStroke = Instance.new("UIStroke")
		tStroke.Color = Color3.fromRGB(70, 58, 48)
		tStroke.Thickness = 1
		tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tStroke.Parent = tRow

		local tPad = Instance.new("UIPadding")
		tPad.PaddingLeft = UDim.new(0, 14)
		tPad.PaddingRight = UDim.new(0, 12)
		tPad.Parent = tRow

		local tTitle = Instance.new("TextLabel")
		tTitle.Size = UDim2.new(0.60, 0, 0, 20)
		tTitle.Position = UDim2.new(0, 0, 0, 6)
		tTitle.BackgroundTransparency = 1
		tTitle.Font = Enum.Font.GothamBold
		tTitle.Text = string.format("%s (%s)", tier.name, tier.timeStr)
		tTitle.TextColor3 = Color3.fromRGB(245, 239, 230)
		tTitle.TextSize = 14
		tTitle.TextXAlignment = Enum.TextXAlignment.Left
		tTitle.Parent = tRow

		local tReward = Instance.new("TextLabel")
		tReward.Size = UDim2.new(0.60, 0, 0, 18)
		tReward.Position = UDim2.new(0, 0, 0, 26)
		tReward.BackgroundTransparency = 1
		tReward.Font = Enum.Font.GothamBold
		tReward.Text = "REWARD: " .. tier.rewardText
		tReward.TextColor3 = tier.rewardColor
		tReward.TextSize = 13
		tReward.TextXAlignment = Enum.TextXAlignment.Left
		tReward.Parent = tRow

		local subProgress = Instance.new("TextLabel")
		subProgress.Size = UDim2.new(0.60, 0, 0, 16)
		subProgress.Position = UDim2.new(0, 0, 0, 46)
		subProgress.BackgroundTransparency = 1
		subProgress.Font = Enum.Font.Code
		subProgress.Text = "STATUS: IN PROGRESS"
		subProgress.TextColor3 = Color3.fromRGB(212, 175, 55)
		subProgress.TextSize = 11.5
		subProgress.TextXAlignment = Enum.TextXAlignment.Left
		subProgress.Parent = tRow

		local cBtn = Instance.new("TextButton")
		cBtn.Size = UDim2.new(0.35, 0, 0, 44)
		cBtn.Position = UDim2.new(0.65, 0, 0.5, -22)
		cBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
		cBtn.BorderSizePixel = 0
		cBtn.Font = Enum.Font.GothamBold
		cBtn.Text = "LOCKED"
		cBtn.TextColor3 = Color3.fromRGB(160, 148, 140)
		cBtn.TextSize = 13.5
		cBtn.Parent = tRow

		local cbCorner = Instance.new("UICorner")
		cbCorner.CornerRadius = UDim.new(0, 6)
		cbCorner.Parent = cBtn

		local tState = { id = tier.id, claimed = false, ready = false }

		cBtn.MouseButton1Click:Connect(function()
			if not tState.ready or tState.claimed then
				return
			end
			cBtn.Text = "CLAIMING..."
			task.spawn(function()
				local res = NetClient.claimChest(tier.id)
				if res.ok then
					tState.claimed = true
					tState.ready = false
					cBtn.Text = "CLAIMED \u{2713}"
					cBtn.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
					cBtn.TextColor3 = Color3.fromRGB(160, 148, 140)
					subProgress.Text = "STATUS: CLAIMED"
					subProgress.TextColor3 = Color3.fromRGB(160, 148, 140)
				else
					cBtn.Text = "CLAIM"
					cBtn.BackgroundColor3 = Color3.fromRGB(74, 222, 128)
					cBtn.TextColor3 = Color3.fromRGB(20, 16, 14)
				end
			end)
		end)

		table.insert(playtimeRows, {
			config = tier,
			title = tTitle,
			reward = tReward,
			status = subProgress,
			button = cBtn,
			state = tState,
		})
	end

	-- Bottom Pod: Daily Login Streak (40% height with 3x2 + Day 7 layout)
	local loginPod = Instance.new("Frame")
	loginPod.Name = "DailyLoginPod"
	loginPod.Size = UDim2.new(1, 0, 0.40, -5)
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
	lpPad.PaddingTop = UDim.new(0, 6)
	lpPad.PaddingBottom = UDim.new(0, 6)
	lpPad.PaddingLeft = UDim.new(0, 14)
	lpPad.PaddingRight = UDim.new(0, 14)
	lpPad.Parent = loginPod

	local lpHeader = Instance.new("TextLabel")
	lpHeader.Size = UDim2.new(1, 0, 0, 16)
	lpHeader.Position = UDim2.new(0, 0, 0, 0)
	lpHeader.BackgroundTransparency = 1
	lpHeader.Font = Enum.Font.GothamBold
	lpHeader.Text = "\u{25C8} DAILY LOGIN (DAY 1 / 7)"
	lpHeader.TextColor3 = Color3.fromRGB(212, 175, 55)
	lpHeader.TextSize = 13
	lpHeader.TextXAlignment = Enum.TextXAlignment.Left
	lpHeader.Parent = loginPod

	-- Main Layout Container (Left 3x2 + Right Day 7)
	local gridContainer = Instance.new("Frame")
	gridContainer.Name = "GridContainer"
	gridContainer.Size = UDim2.new(1, 0, 1, -20)
	gridContainer.Position = UDim2.new(0, 0, 0, 18)
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
	ldcList.Padding = UDim.new(0, 4)
	ldcList.SortOrder = Enum.SortOrder.LayoutOrder
	ldcList.Parent = leftDaysCol

	local dayCardUIs: { any } = {}

	local LOGIN_LADDER = {
		{ day = 1, amount = "$300", currency = "CASH", kind = "Cash", currColor = Color3.fromRGB(74, 222, 128) },
		{ day = 2, amount = "$700", currency = "CASH", kind = "Cash", currColor = Color3.fromRGB(74, 222, 128) },
		{ day = 3, amount = "+20", currency = "GEMS", kind = "Gems", currColor = Color3.fromRGB(56, 189, 248) },
		{ day = 4, amount = "$2.0K", currency = "CASH", kind = "Cash", currColor = Color3.fromRGB(74, 222, 128) },
		{ day = 5, amount = "+45", currency = "GEMS", kind = "Gems", currColor = Color3.fromRGB(56, 189, 248) },
		{ day = 6, amount = "$5.0K", currency = "CASH", kind = "Cash", currColor = Color3.fromRGB(74, 222, 128) },
		{ day = 7, amount = "+5", currency = "DIAMONDS", kind = "Diamonds", jackpot = true, currColor = Color3.fromRGB(244, 114, 182) },
	}

	local function createDayCard(d: any, parentRow: Frame)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0.333, -4, 1, 0)
		card.BackgroundColor3 = Color3.fromRGB(28, 24, 20)
		card.BorderSizePixel = 0
		card.LayoutOrder = d.day
		card.Parent = parentRow

		local cCorn = Instance.new("UICorner")
		cCorn.CornerRadius = UDim.new(0, 6)
		cCorn.Parent = card

		local cStk = Instance.new("UIStroke")
		cStk.Color = Color3.fromRGB(70, 58, 48)
		cStk.Thickness = 1
		cStk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cStk.Parent = card

		local dTitle = Instance.new("TextLabel")
		dTitle.Size = UDim2.new(1, 0, 0, 13)
		dTitle.Position = UDim2.new(0, 0, 0, 2)
		dTitle.BackgroundTransparency = 1
		dTitle.Font = Enum.Font.GothamBold
		dTitle.Text = "DAY " .. d.day
		dTitle.TextColor3 = Color3.fromRGB(160, 148, 140)
		dTitle.TextSize = 9.5
		dTitle.Parent = card

		local dVal = Instance.new("TextLabel")
		dVal.Size = UDim2.new(1, 0, 0, 16)
		dVal.Position = UDim2.new(0, 0, 0, 15)
		dVal.BackgroundTransparency = 1
		dVal.Font = Enum.Font.GothamBold
		dVal.Text = d.amount
		dVal.TextColor3 = Color3.fromRGB(245, 239, 230)
		dVal.TextSize = 12.5
		dVal.Parent = card

		local dCurr = Instance.new("TextLabel")
		dCurr.Size = UDim2.new(1, 0, 0, 12)
		dCurr.Position = UDim2.new(0, 0, 0, 31)
		dCurr.BackgroundTransparency = 1
		dCurr.Font = Enum.Font.GothamBold
		dCurr.Text = d.currency
		dCurr.TextColor3 = d.currColor
		dCurr.TextSize = 8.5
		dCurr.Parent = card

		local dStat = Instance.new("TextLabel")
		dStat.Size = UDim2.new(1, 0, 0, 13)
		dStat.Position = UDim2.new(0, 0, 1, -15)
		dStat.BackgroundTransparency = 1
		dStat.Font = Enum.Font.GothamBold
		dStat.Text = "LOCKED"
		dStat.TextColor3 = Color3.fromRGB(140, 130, 120)
		dStat.TextSize = 8.5
		dStat.Parent = card

		table.insert(dayCardUIs, {
			day = d.day,
			card = card,
			stroke = cStk,
			title = dTitle,
			val = dVal,
			curr = dCurr,
			currColor = d.currColor,
			stat = dStat,
		})
	end

	-- Row 1: Days 1, 2, 3
	local row1 = Instance.new("Frame")
	row1.Name = "Row_Days123"
	row1.Size = UDim2.new(1, 0, 0.5, -2)
	row1.BackgroundTransparency = 1
	row1.LayoutOrder = 1
	row1.Parent = leftDaysCol

	local r1List = Instance.new("UIListLayout")
	r1List.FillDirection = Enum.FillDirection.Horizontal
	r1List.Padding = UDim.new(0, 6)
	r1List.SortOrder = Enum.SortOrder.LayoutOrder
	r1List.Parent = row1

	createDayCard(LOGIN_LADDER[1], row1)
	createDayCard(LOGIN_LADDER[2], row1)
	createDayCard(LOGIN_LADDER[3], row1)

	-- Row 2: Days 4, 5, 6
	local row2 = Instance.new("Frame")
	row2.Name = "Row_Days456"
	row2.Size = UDim2.new(1, 0, 0.5, -2)
	row2.BackgroundTransparency = 1
	row2.LayoutOrder = 2
	row2.Parent = leftDaysCol

	local r2List = Instance.new("UIListLayout")
	r2List.FillDirection = Enum.FillDirection.Horizontal
	r2List.Padding = UDim.new(0, 6)
	r2List.SortOrder = Enum.SortOrder.LayoutOrder
	r2List.Parent = row2

	createDayCard(LOGIN_LADDER[4], row2)
	createDayCard(LOGIN_LADDER[5], row2)
	createDayCard(LOGIN_LADDER[6], row2)

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
	d7Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	d7Stroke.Parent = day7Card

	local d7Pad = Instance.new("UIPadding")
	d7Pad.PaddingTop = UDim.new(0, 6)
	d7Pad.PaddingBottom = UDim.new(0, 6)
	d7Pad.PaddingLeft = UDim.new(0, 6)
	d7Pad.PaddingRight = UDim.new(0, 6)
	d7Pad.Parent = day7Card

	local d7Badge = Instance.new("TextLabel")
	d7Badge.Size = UDim2.new(1, 0, 0, 12)
	d7Badge.Position = UDim2.new(0, 0, 0, 2)
	d7Badge.BackgroundTransparency = 1
	d7Badge.Font = Enum.Font.Code
	d7Badge.Text = "[ FINAL DAY ]"
	d7Badge.TextColor3 = Color3.fromRGB(244, 114, 182)
	d7Badge.TextSize = 9
	d7Badge.Parent = day7Card

	local d7Title = Instance.new("TextLabel")
	d7Title.Size = UDim2.new(1, 0, 0, 16)
	d7Title.Position = UDim2.new(0, 0, 0, 14)
	d7Title.BackgroundTransparency = 1
	d7Title.Font = Enum.Font.GothamBold
	d7Title.Text = "DAY 7"
	d7Title.TextColor3 = Color3.fromRGB(245, 239, 230)
	d7Title.TextSize = 12
	d7Title.Parent = day7Card

	local d7Amount = Instance.new("TextLabel")
	d7Amount.Size = UDim2.new(1, 0, 0, 26)
	d7Amount.Position = UDim2.new(0, 0, 0, 30)
	d7Amount.BackgroundTransparency = 1
	d7Amount.Font = Enum.Font.GothamBlack
	d7Amount.Text = "+5"
	d7Amount.TextColor3 = Color3.fromRGB(244, 114, 182)
	d7Amount.TextSize = 20
	d7Amount.Parent = day7Card

	local d7Sub = Instance.new("TextLabel")
	d7Sub.Size = UDim2.new(1, 0, 0, 14)
	d7Sub.Position = UDim2.new(0, 0, 0, 56)
	d7Sub.BackgroundTransparency = 1
	d7Sub.Font = Enum.Font.GothamBold
	d7Sub.Text = "DIAMONDS"
	d7Sub.TextColor3 = Color3.fromRGB(212, 175, 55)
	d7Sub.TextSize = 10
	d7Sub.Parent = day7Card

	local d7Btn = Instance.new("Frame")
	d7Btn.Size = UDim2.new(1, -4, 0, 20)
	d7Btn.Position = UDim2.new(0, 2, 1, -22)
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
	d7bText.TextSize = 9
	d7bText.Parent = d7Btn

	table.insert(dayCardUIs, {
		day = 7,
		card = day7Card,
		stroke = d7Stroke,
		title = d7Title,
		val = d7Amount,
		stat = d7bText,
		isGrand = true,
	})

	-- Live Periodic Timer
	task.spawn(function()
		while true do
			task.wait(1)
			if questsOverlay.Visible then
				local now = os.time()
				local secToday = now % 86400
				local secLeft = 86400 - secToday
				local hrs = math.floor(secLeft / 3600)
				local mins = math.floor((secLeft % 3600) / 60)
				if questResetLabel then
					questResetLabel.Text = string.format("Resets in: %dh %dm", hrs, mins)
				end

				-- Update playtime tiers
				local sessionSec = os.clock() - sessionStartTime
				for _, row in ipairs(playtimeRows) do
					if not row.state.claimed then
						if sessionSec >= row.config.timeSec then
							row.state.ready = true
							row.button.Text = "CLAIM"
							row.button.BackgroundColor3 = Color3.fromRGB(74, 222, 128)
							row.button.TextColor3 = Color3.fromRGB(20, 16, 14)
							row.status.Text = "STATUS: UNLOCKED"
							row.status.TextColor3 = Color3.fromRGB(74, 222, 128)
						else
							row.state.ready = false
							local rem = row.config.timeSec - sessionSec
							local rMin = math.ceil(rem / 60)
							row.button.Text = "LOCKED"
							row.button.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
							row.button.TextColor3 = Color3.fromRGB(160, 148, 140)
							row.status.Text = string.format("STATUS: %dm left", rMin)
							row.status.TextColor3 = Color3.fromRGB(212, 175, 55)
						end
					end
				end
			end
		end
	end)

	local function refreshQuests(state: any)
		local quests = if type(state) == "table" then state.quests else nil
		if type(quests) == "table" then
			for i, ui in ipairs(questRows) do
				local q = quests[i]
				if q == nil then
					ui.card.Visible = false
				else
					ui.card.Visible = true
					ui.state.id = q.id
					ui.state.isClaimed = q.claimed == true
					ui.state.isReady = q.ready == true

					local qInfo = QUEST_INFO[q.id]
					if qInfo then
						ui.title.Text = qInfo.title
						ui.desc.Text = qInfo.desc
						ui.rew.Text = "REWARD: " .. qInfo.rewardText
						ui.rew.TextColor3 = qInfo.rewardColor
					else
						local verb, target = string.match(tostring(q.id), "^(%a+)(%d+)$")
						ui.title.Text = if verb ~= nil then string.format("%s %s", string.upper(verb), target) else tostring(q.id)
						ui.desc.Text = "Complete the objective in the arena."
						ui.rew.Text = "REWARD: +$1,000 CASH"
						ui.rew.TextColor3 = Color3.fromRGB(74, 222, 128)
					end

					local prog = tonumber(q.progress) or 0
					local goal = tonumber(q.target) or 1
					ui.count.Text = string.format("COMPLETION: %d / %d", math.floor(prog), math.floor(goal))
					ui.fill.Size = UDim2.fromScale(math.clamp(prog / math.max(goal, 1), 0, 1), 1)

					if q.claimed then
						ui.fill.BackgroundColor3 = Color3.fromRGB(74, 222, 128)
						ui.stroke.Color = Color3.fromRGB(70, 58, 48)
						ui.stroke.Thickness = 1
						ui.button.Text = "CLAIMED \u{2713}"
						ui.button.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
						ui.button.TextColor3 = Color3.fromRGB(160, 148, 140)
					elseif q.ready then
						ui.fill.BackgroundColor3 = Color3.fromRGB(74, 222, 128)
						ui.stroke.Color = Color3.fromRGB(74, 222, 128)
						ui.stroke.Thickness = 1.5
						ui.button.Text = "CLAIM REWARD"
						ui.button.BackgroundColor3 = Color3.fromRGB(74, 222, 128)
						ui.button.TextColor3 = Color3.fromRGB(20, 16, 14)
					else
						ui.fill.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
						ui.stroke.Color = Color3.fromRGB(70, 58, 48)
						ui.stroke.Thickness = 1
						ui.button.Text = "IN PROGRESS"
						ui.button.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
						ui.button.TextColor3 = Color3.fromRGB(160, 148, 140)
					end
				end
			end
		end

		-- Refresh Daily Login Matrix
		local streakData = if type(state) == "table" then state.loginStreak else nil
		local currentDay = 1
		local claimedToday = false
		if type(streakData) == "table" then
			currentDay = math.clamp(((tonumber(streakData.count) or 1) - 1) % 7 + 1, 1, 7)
			claimedToday = streakData.claimedToday == true
		end

		lpHeader.Text = string.format("\u{25C8} DAILY LOGIN (DAY %d / 7)", currentDay)

		for _, item in ipairs(dayCardUIs) do
			if item.day < currentDay or (item.day == currentDay and claimedToday) then
				-- Claimed
				if item.isGrand then
					item.stat.Text = "CLAIMED \u{2713}"
					item.stat.TextColor3 = Color3.fromRGB(160, 148, 140)
					item.stroke.Color = Color3.fromRGB(70, 58, 48)
				else
					item.card.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
					item.stroke.Color = Color3.fromRGB(70, 58, 48)
					item.stroke.Thickness = 1
					item.title.TextColor3 = Color3.fromRGB(160, 148, 140)
					item.val.TextColor3 = Color3.fromRGB(160, 148, 140)
					if item.curr then
						item.curr.TextColor3 = Color3.fromRGB(120, 110, 100)
					end
					item.stat.Text = "\u{2713} DONE"
					item.stat.TextColor3 = Color3.fromRGB(140, 130, 120)
				end
			elseif item.day == currentDay and not claimedToday then
				-- Active / Ready
				if item.isGrand then
					item.stat.Text = "READY"
					item.stat.TextColor3 = Color3.fromRGB(244, 114, 182)
					item.stroke.Color = Color3.fromRGB(244, 114, 182)
					item.stroke.Thickness = 1.5
				else
					item.card.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
					item.stroke.Color = Color3.fromRGB(245, 239, 230)
					item.stroke.Thickness = 1.5
					item.title.TextColor3 = Color3.fromRGB(20, 16, 14)
					item.val.TextColor3 = Color3.fromRGB(20, 16, 14)
					if item.curr then
						item.curr.TextColor3 = Color3.fromRGB(30, 24, 20)
					end
					item.stat.Text = "READY"
					item.stat.TextColor3 = Color3.fromRGB(20, 16, 14)
				end
			else
				-- Locked future days
				if item.isGrand then
					item.stat.Text = "LOCKED"
					item.stat.TextColor3 = Color3.fromRGB(160, 148, 140)
					item.stroke.Color = Color3.fromRGB(244, 114, 182)
					item.stroke.Thickness = 1.5
				else
					item.card.BackgroundColor3 = Color3.fromRGB(28, 24, 20)
					item.stroke.Color = Color3.fromRGB(70, 58, 48)
					item.stroke.Thickness = 1
					item.title.TextColor3 = Color3.fromRGB(160, 148, 140)
					item.val.TextColor3 = Color3.fromRGB(245, 239, 230)
					if item.curr then
						item.curr.TextColor3 = item.currColor
					end
					item.stat.Text = "LOCKED"
					item.stat.TextColor3 = Color3.fromRGB(140, 130, 120)
				end
			end
		end
	end

	return refreshQuests
end

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
		-- 192, NOT 168. At the raised type sizes the longest tier small print
		-- wraps to three lines, and a 168px card could not hold title + blurb +
		-- three lines + a 38px action row -- the small print rendered straight
		-- through the button beneath it. Sized for the WORST case rather than
		-- the average, because every card in a grid shares one height and the
		-- tallest content is what has to fit.
		gridLayout.CellSize = UDim2.new(0.5, -shopGutter / 2, 0, 192)
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

			-- THE LAST SIX, so every card carries the same three rows.
			--
			-- These were the cards that read as empty: eight items had small
			-- print and six did not, and the gap where the third row would go is
			-- what the eye picked up. Filling it beats stretching the layout to
			-- disguise it -- the row was missing CONTENT, not height.
			--
			-- Each says what the blurb cannot: the blurb states WHAT you get,
			-- this states what it is FOR. A gem count means nothing to a player
			-- who does not know that gems buy vault hours. Every figure is read
			-- from the shared catalogs, so a card cannot advertise a rate the
			-- server does not honour (L-025).
			DiamondCache = string.format(
				"Diamonds re-roll a die's shape -- %d per change -- and unlock "
				.. "nodes on the ascension tree.",
				DiceCatalog.SHAPE_CHANGE_DIAMOND_COST),
			GemsLarge = string.format(
				"Gems buy vault capacity at %d per hour, up to a cap of %dh.",
				VaultCatalog.GEMS_PER_CAPACITY_HOUR,
				math.floor(VaultCatalog.MAX_PURCHASED_CAPACITY_SEC / 3600)),
			GemsSmall = string.format(
				"Gems buy vault capacity at %d per hour, up to a cap of %dh.",
				VaultCatalog.GEMS_PER_CAPACITY_HOUR,
				math.floor(VaultCatalog.MAX_PURCHASED_CAPACITY_SEC / 3600)),
			LuckBoost = (function(): string
				local e = MonetisationCatalog.Products.LuckBoost
				return string.format(
					"For %d minutes, heavy faces land closer to even odds. Your "
					.. "mass and payouts are unchanged.",
					math.floor((e.durationSeconds or 900) / 60))
			end)(),
			OfflineX2 = string.format(
				"Multiplies the NEXT vault claim by %sx. Applies once, to that "
				.. "claim only.",
				tostring(MonetisationCatalog.Products.OfflineX2.amount or 2)),
			TimeSkip24 = (function(): string
				local e = MonetisationCatalog.Products.TimeSkip24
				return string.format(
					"Pays %d hours at YOUR OWN earning rate, not a fixed sum. Roll "
					.. "a few times first so that rate is established.",
					math.floor((e.durationSeconds or 24 * 3600) / 3600))
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

			-- Even padding all round. The action row's space is reserved by the
			-- text stack's own height, not by padding here.
			local cardPadding = Instance.new("UIPadding")
			cardPadding.PaddingTop = UDim.new(0, UITheme.Scale.MD)
			cardPadding.PaddingBottom = UDim.new(0, UITheme.Scale.MD)
			cardPadding.PaddingLeft = UDim.new(0, UITheme.Scale.MD)
			cardPadding.PaddingRight = UDim.new(0, UITheme.Scale.MD)
			cardPadding.Parent = card

			-- THE TEXT STACK IS ITS OWN CONTAINER, so the action row can escape it.
			--
			-- A `UIListLayout` owns EVERY child of the frame it sits on and
			-- overrides their `Position` outright -- so pinning the action row to
			-- the card's bottom edge did nothing except make the layout sort it
			-- first, which put every button at the TOP of its card. Measured:
			-- perfectly aligned at 12px from the top, and completely wrong.
			--
			-- Giving the flowing content its own frame leaves the card itself
			-- with exactly two children -- this stack and the pinned action row --
			-- neither of which is under a layout, so both keep the positions they
			-- are given.
			local textStack = Instance.new("Frame")
			textStack.Name = "TextStack"
			-- Reserves the action row plus a gap ABOVE it, so the last line of
			-- small print does not sit flush against the button.
			textStack.Size = UDim2.new(1, 0, 1, -(38 + UITheme.Scale.MD * 2))
			textStack.BackgroundTransparency = 1
			textStack.Parent = card

			local cardList = Instance.new("UIListLayout")
			cardList.Padding = UDim.new(0, 6)
			cardList.SortOrder = Enum.SortOrder.LayoutOrder
			-- Stated explicitly because the blurb below is a `UIFlexItem`, and
			-- flex only distributes along a declared fill direction.
			cardList.FillDirection = Enum.FillDirection.Vertical
			cardList.Parent = textStack

			-- Row 1: Tag Badge Frame (Border stroke, no text glow) + Title
			local tagRow = Instance.new("Frame")
			tagRow.Name = "TagRow"
			-- Taller to carry the raised title size without clipping its
			-- descenders. 24 was sized for a 17px title; this holds 20px.
			tagRow.Size = UDim2.new(1, 0, 0, 28)
			tagRow.BackgroundTransparency = 1
			tagRow.LayoutOrder = 1
			tagRow.Parent = textStack

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
			categoryLabel.TextSize = UITheme.Scale.TextSmall
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
			titleLbl.TextSize = 20
			titleLbl.TextStrokeTransparency = 1
			titleLbl.TextXAlignment = Enum.TextXAlignment.Left
			titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
			titleLbl.Parent = tagRow

			-- Row 2: Blurb (Matte Cream, NO glow)
			-- THE BLURB ABSORBS WHATEVER IS LEFT, which is what evens the cards out.
			--
			-- Every card is a fixed 168 tall, but only the ones with tier small
			-- print filled it: measured, a three-row card used 82 of its 94px
			-- text area while a two-row card used 58, leaving 36px of dead space.
			-- That gap is what read as some cards looking empty.
			--
			-- A flex item takes the remainder rather than a fixed 34, so a card
			-- with no small print gives its blurb the room instead of leaving a
			-- hole, and a card with small print is unchanged.
			local blurbLbl = Instance.new("TextLabel")
			blurbLbl.Name = "Blurb"
			blurbLbl.Size = UDim2.new(1, 0, 0, 34)
			blurbLbl.BackgroundTransparency = 1
			blurbLbl.Font = Enum.Font.Gotham
			blurbLbl.Text = entry.blurb
			blurbLbl.TextColor3 = Color3.fromRGB(245, 239, 230)
			blurbLbl.TextSize = UITheme.Scale.TextHeading
			blurbLbl.TextStrokeTransparency = 1
			blurbLbl.TextWrapped = true
			blurbLbl.TextXAlignment = Enum.TextXAlignment.Left
			blurbLbl.TextYAlignment = Enum.TextYAlignment.Top
			blurbLbl.LayoutOrder = 2
			blurbLbl.Parent = textStack

			local blurbFlex = Instance.new("UIFlexItem")
			blurbFlex.FlexMode = Enum.UIFlexMode.Fill
			blurbFlex.Parent = blurbLbl

			-- A FLOOR, because flex distributes what is LEFT and that can be
			-- nothing. On the two cards whose small print wraps to three lines
			-- the blurb was squeezed to a 13px box for 17px text and clipped its
			-- own single line. Fill is the right behaviour when there is room to
			-- spare; it must not be allowed to take the row below legibility.
			local blurbFloor = Instance.new("UISizeConstraint")
			blurbFloor.MinSize = Vector2.new(0, 22)
			blurbFloor.Parent = blurbLbl

			-- Row 3: Detail (Matte Brass Gold, NO glow)
			if detail ~= nil then
				local fine = Instance.new("TextLabel")
				fine.Name = "TierDetail"
				-- MEASURES ITSELF. At the raised type size these lines wrap to
				-- two rows and a fixed 24px box truncated five of them mid-word.
				-- `AutomaticSize.Y` lets the row take the height its text needs,
				-- and the blurb's flex above gives back whatever is left over.
				fine.Size = UDim2.new(1, 0, 0, 0)
				fine.AutomaticSize = Enum.AutomaticSize.Y
				fine.BackgroundTransparency = 1
				fine.Font = Enum.Font.Code
				fine.Text = detail
				fine.TextColor3 = Color3.fromRGB(212, 175, 55)
				fine.TextSize = UITheme.Scale.TextBody
				fine.TextStrokeTransparency = 1
				fine.TextWrapped = true
				fine.TextXAlignment = Enum.TextXAlignment.Left
				fine.TextYAlignment = Enum.TextYAlignment.Top
				fine.LayoutOrder = 3
				fine.Parent = textStack
			end

			-- Row 4: Action Control
			-- ANCHORED TO THE CARD'S BOTTOM, NOT PLACED BY THE TEXT ABOVE IT.
			--
			-- As `LayoutOrder = 4` in the card's vertical list, the button sat
			-- wherever the text happened to end -- so a card with tier small
			-- print pushed it to y=112 while one without left it at y=82.
			-- Measured across the shop: a 30px difference between neighbours in
			-- the same row, which is why the buttons did not line up.
			--
			-- Every card is a fixed 168 tall, so pinning the action row to the
			-- bottom edge puts every button on one line regardless of how much
			-- text sits above it. It leaves the list layout, which is why the
			-- padding below reserves its height so the text cannot run underneath.
			local actionRow = Instance.new("Frame")
			actionRow.Name = "ActionRow"
			actionRow.Size = UDim2.new(1, -UITheme.Scale.MD * 2, 0, 38)
			actionRow.AnchorPoint = Vector2.new(0.5, 1)
			actionRow.Position = UDim2.new(0.5, 0, 1, -UITheme.Scale.MD)
			actionRow.BackgroundTransparency = 1
			actionRow.ZIndex = 3
			actionRow.Parent = card

			local ownedPill = Instance.new("TextLabel")
			ownedPill.Name = "OwnedPill"
			ownedPill.Size = UDim2.fromScale(1, 1)
			ownedPill.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
			ownedPill.BorderSizePixel = 0
			ownedPill.Font = Enum.Font.GothamBold
			ownedPill.Text = "OWNED"
			ownedPill.TextColor3 = Color3.fromRGB(160, 148, 140)
			ownedPill.TextSize = UITheme.Scale.TextBody
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
			buyBtn.TextSize = UITheme.Scale.TextHeading
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

	-- 4. ASCENSION OVERLAY (The Sovereign Ascension Vault - Master Responsive Edition)
	local ascendOverlay, ascendBody = UITheme.overlay("The Sovereign Ascension Vault")
	ascendOverlay.Parent = screenGui
	overlays["ascend"] = ascendOverlay

	local ascendPanelContainer = ascendOverlay:FindFirstChild("Panel") :: Frame?
	if ascendPanelContainer then
		-- Style panel container with dark mocha fill & gold border
		ascendPanelContainer.BackgroundColor3 = Color3.fromRGB(26, 22, 20)
		
		local panelCorner = ascendPanelContainer:FindFirstChildOfClass("UICorner")
		if panelCorner then
			panelCorner.CornerRadius = UDim.new(0, 14)
		end

		local existingStroke = ascendPanelContainer:FindFirstChildOfClass("UIStroke")
		if existingStroke then
			existingStroke.Color = Color3.fromRGB(212, 175, 55)
			existingStroke.Thickness = 2
			existingStroke.Transparency = 0
		else
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(212, 175, 55)
			stroke.Thickness = 2
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = ascendPanelContainer
		end

		-- Style Header (~ The Sovereign Ascension Vault ~)
		local header = ascendPanelContainer:FindFirstChild("Header") :: Frame?
		if header then
			header.Size = UDim2.new(1, -24, 0, 52)
			header.Position = UDim2.new(0, 12, 0, 10)
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
				hStroke.Color = Color3.fromRGB(212, 175, 55)
				hStroke.Thickness = 1
				hStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				hStroke.Parent = header
			end

			local hPad = header:FindFirstChildOfClass("UIPadding")
			if not hPad then
				hPad = Instance.new("UIPadding")
				hPad.PaddingLeft = UDim.new(0, 16)
				hPad.PaddingRight = UDim.new(0, 16)
				hPad.Parent = header
			end

			local titleLbl = header:FindFirstChild("Title") :: TextLabel?
			if titleLbl then
				titleLbl.Text = "~ The Sovereign Ascension Vault ~"
				titleLbl.TextColor3 = Color3.fromRGB(212, 175, 55)
				titleLbl.Font = Enum.Font.GothamBold
				titleLbl.TextSize = 21
				titleLbl.TextStrokeTransparency = 1
			end

			local closeBtn = header:FindFirstChild("Close") :: TextButton?
			if closeBtn then
				closeBtn.Size = UDim2.new(0, 38, 0, 38)
				closeBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
				closeBtn.BackgroundTransparency = 0
				closeBtn.TextColor3 = Color3.fromRGB(212, 175, 55)
				closeBtn.Font = Enum.Font.GothamBold
				closeBtn.Text = "\u{00D7}"
				closeBtn.TextSize = 24
				closeBtn.TextStrokeTransparency = 1

				local cCorner = closeBtn:FindFirstChildOfClass("UICorner")
				if not cCorner then
					cCorner = Instance.new("UICorner")
					cCorner.CornerRadius = UDim.new(0, 6)
					cCorner.Parent = closeBtn
				end

				local cStroke = closeBtn:FindFirstChildOfClass("UIStroke")
				if not cStroke then
					cStroke = Instance.new("UIStroke")
					cStroke.Color = Color3.fromRGB(212, 175, 55)
					cStroke.Thickness = 1
					cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					cStroke.Parent = closeBtn
				end
			end
		end

		local divider = ascendPanelContainer:FindFirstChild("Divider") :: Frame?
		if divider then
			divider.Visible = false
		end

		ascendBody.Visible = false
	end

	-- Dedicated Non-Clipping Body Container (Eliminates all edge stroke clipping)
	local vaultBody = Instance.new("Frame")
	vaultBody.Name = "VaultBody"
	vaultBody.Size = UDim2.new(1, -32, 1, -88)
	vaultBody.Position = UDim2.new(0, 16, 0, 70)
	vaultBody.BackgroundTransparency = 1
	vaultBody.ClipsDescendants = false
	vaultBody.Parent = ascendPanelContainer or ascendOverlay

	-- Main 48/52 Two-Column Row Container (Fills 100% height)
	local bodyRow = Instance.new("Frame")
	bodyRow.Name = "BodyRow"
	bodyRow.Size = UDim2.fromScale(1, 1)
	bodyRow.BackgroundTransparency = 1
	bodyRow.ClipsDescendants = false
	bodyRow.Parent = vaultBody

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.FillDirection = Enum.FillDirection.Horizontal
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 14)
	bodyLayout.Parent = bodyRow

	-- =========================================================================
	-- LEFT COLUMN (48%): Expanded Prestige Extraction Command Pod
	-- =========================================================================
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftCommandCol"
	leftCol.Size = UDim2.new(0.48, -7, 1, 0)
	leftCol.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	leftCol.BorderSizePixel = 0
	leftCol.LayoutOrder = 1
	leftCol.Parent = bodyRow

	local lCorner = Instance.new("UICorner")
	lCorner.CornerRadius = UDim.new(0, 10)
	lCorner.Parent = leftCol

	local lStroke = Instance.new("UIStroke")
	lStroke.Color = Color3.fromRGB(212, 175, 55)
	lStroke.Thickness = 1
	lStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lStroke.Parent = leftCol

	local lPad = Instance.new("UIPadding")
	lPad.PaddingTop = UDim.new(0, 14)
	lPad.PaddingBottom = UDim.new(0, 14)
	lPad.PaddingLeft = UDim.new(0, 16)
	lPad.PaddingRight = UDim.new(0, 16)
	lPad.Parent = leftCol

	local leftList = Instance.new("UIListLayout")
	leftList.Padding = UDim.new(0, 9)
	leftList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	leftList.SortOrder = Enum.SortOrder.LayoutOrder
	leftList.Parent = leftCol

	-- Section Badge
	local leftTagFrame = Instance.new("Frame")
	leftTagFrame.Name = "TagFrame"
	leftTagFrame.Size = UDim2.new(1, 0, 0, 28)
	leftTagFrame.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
	leftTagFrame.BorderSizePixel = 0
	leftTagFrame.LayoutOrder = 1
	leftTagFrame.Parent = leftCol

	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 4)
	tCorner.Parent = leftTagFrame

	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(70, 58, 48)
	tStroke.Thickness = 1
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tStroke.Parent = leftTagFrame

	local leftTag = Instance.new("TextLabel")
	leftTag.Size = UDim2.fromScale(1, 1)
	leftTag.BackgroundTransparency = 1
	leftTag.Font = Enum.Font.Code
	leftTag.Text = "[ 01 // PRESTIGE EXTRACTION ]"
	leftTag.TextColor3 = Color3.fromRGB(212, 175, 55)
	leftTag.TextSize = 11
	leftTag.TextStrokeTransparency = 1
	leftTag.Parent = leftTagFrame

	-- Primary Yield Readout
	local ascendReward = Instance.new("TextLabel")
	ascendReward.Name = "AscendReward"
	ascendReward.Size = UDim2.new(1, 0, 0, 52)
	ascendReward.BackgroundTransparency = 1
	ascendReward.Font = Enum.Font.GothamBlack
	ascendReward.Text = "+0 \u{2666} DIAMONDS"
	ascendReward.TextColor3 = Color3.fromRGB(244, 114, 182)
	ascendReward.TextSize = 36
	ascendReward.TextStrokeTransparency = 1
	ascendReward.LayoutOrder = 2
	ascendReward.Parent = leftCol

	local rewardSub = Instance.new("TextLabel")
	rewardSub.Name = "RewardSub"
	rewardSub.Size = UDim2.new(1, 0, 0, 20)
	rewardSub.BackgroundTransparency = 1
	rewardSub.Font = Enum.Font.GothamMedium
	rewardSub.Text = "Guaranteed Permanent Vault Asset"
	rewardSub.TextColor3 = Color3.fromRGB(160, 148, 140)
	rewardSub.TextSize = 13
	rewardSub.TextStrokeTransparency = 1
	rewardSub.LayoutOrder = 3
	rewardSub.Parent = leftCol

	-- Progress Bar Meter
	local meterTrack = Instance.new("Frame")
	meterTrack.Name = "MeterTrack"
	meterTrack.Size = UDim2.new(1, 0, 0, 14)
	meterTrack.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
	meterTrack.BorderSizePixel = 0
	meterTrack.LayoutOrder = 4
	meterTrack.Parent = leftCol

	local mtCorner = Instance.new("UICorner")
	mtCorner.CornerRadius = UDim.new(0, 7)
	mtCorner.Parent = meterTrack

	local mtStroke = Instance.new("UIStroke")
	mtStroke.Color = Color3.fromRGB(70, 58, 48)
	mtStroke.Thickness = 1
	mtStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mtStroke.Parent = meterTrack

	local meterFill = Instance.new("Frame")
	meterFill.Name = "MeterFill"
	meterFill.Size = UDim2.fromScale(0, 1)
	meterFill.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
	meterFill.BorderSizePixel = 0
	meterFill.Parent = meterTrack

	local mfCorner = Instance.new("UICorner")
	mfCorner.CornerRadius = UDim.new(0, 7)
	mfCorner.Parent = meterFill

	-- Basis & Progress Text
	local ascendProgress = Instance.new("TextLabel")
	ascendProgress.Name = "AscendProgress"
	ascendProgress.Size = UDim2.new(1, 0, 0, 24)
	ascendProgress.BackgroundTransparency = 1
	ascendProgress.Font = Enum.Font.GothamBold
	ascendProgress.Text = "Run Basis: $0 / $1.00M"
	ascendProgress.TextColor3 = Color3.fromRGB(245, 239, 230)
	ascendProgress.TextSize = 14
	ascendProgress.TextStrokeTransparency = 1
	ascendProgress.LayoutOrder = 5
	ascendProgress.Parent = leftCol

	-- Lifetime Metrics Pod (176px - High-Density Sovereign Readout)
	local metricsCard = Instance.new("Frame")
	metricsCard.Name = "LifetimeMetricsPod"
	metricsCard.Size = UDim2.new(1, 0, 0, 176)
	metricsCard.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
	metricsCard.BorderSizePixel = 0
	metricsCard.LayoutOrder = 6
	metricsCard.Parent = leftCol

	local mcCorner = Instance.new("UICorner")
	mcCorner.CornerRadius = UDim.new(0, 8)
	mcCorner.Parent = metricsCard

	local mcStroke = Instance.new("UIStroke")
	mcStroke.Color = Color3.fromRGB(70, 58, 48)
	mcStroke.Thickness = 1
	mcStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mcStroke.Parent = metricsCard

	local mcPad = Instance.new("UIPadding")
	mcPad.PaddingTop = UDim.new(0, 10)
	mcPad.PaddingBottom = UDim.new(0, 10)
	mcPad.PaddingLeft = UDim.new(0, 14)
	mcPad.PaddingRight = UDim.new(0, 14)
	mcPad.Parent = metricsCard

	local mcList = Instance.new("UIListLayout")
	mcList.Padding = UDim.new(0, 8)
	mcList.SortOrder = Enum.SortOrder.LayoutOrder
	mcList.Parent = metricsCard

	local mHeader = Instance.new("TextLabel")
	mHeader.Size = UDim2.new(1, 0, 0, 22)
	mHeader.BackgroundTransparency = 1
	mHeader.Font = Enum.Font.GothamBold
	mHeader.Text = "VAULT YIELD & PROJECTIONS"
	mHeader.TextColor3 = Color3.fromRGB(212, 175, 55)
	mHeader.TextSize = 12
	mHeader.TextStrokeTransparency = 1
	mHeader.TextXAlignment = Enum.TextXAlignment.Left
	mHeader.LayoutOrder = 1
	mHeader.Parent = metricsCard

	-- Row 1: Post-Reset Vault Total
	local row1 = Instance.new("Frame")
	row1.Size = UDim2.new(1, 0, 0, 32)
	row1.BackgroundTransparency = 1
	row1.LayoutOrder = 2
	row1.Parent = metricsCard

	local r1Label = Instance.new("TextLabel")
	r1Label.Size = UDim2.new(0.6, 0, 1, 0)
	r1Label.BackgroundTransparency = 1
	r1Label.Font = Enum.Font.GothamMedium
	r1Label.Text = "Post-Reset Vault Total:"
	r1Label.TextColor3 = Color3.fromRGB(160, 148, 140)
	r1Label.TextSize = 13
	r1Label.TextStrokeTransparency = 1
	r1Label.TextXAlignment = Enum.TextXAlignment.Left
	r1Label.Parent = row1

	local postVaultVal = Instance.new("TextLabel")
	postVaultVal.Name = "PostVaultVal"
	postVaultVal.Size = UDim2.new(0.4, 0, 1, 0)
	postVaultVal.Position = UDim2.new(0.6, 0, 0, 0)
	postVaultVal.BackgroundTransparency = 1
	postVaultVal.Font = Enum.Font.GothamBold
	postVaultVal.Text = "0 \u{2666} (+0)"
	postVaultVal.TextColor3 = Color3.fromRGB(244, 114, 182)
	postVaultVal.TextSize = 14
	postVaultVal.TextStrokeTransparency = 1
	postVaultVal.TextXAlignment = Enum.TextXAlignment.Right
	postVaultVal.Parent = row1

	-- Row 2: Next Yield Milestone
	local row2 = Instance.new("Frame")
	row2.Size = UDim2.new(1, 0, 0, 32)
	row2.BackgroundTransparency = 1
	row2.LayoutOrder = 3
	row2.Parent = metricsCard

	local r2Label = Instance.new("TextLabel")
	r2Label.Size = UDim2.new(0.55, 0, 1, 0)
	r2Label.BackgroundTransparency = 1
	r2Label.Font = Enum.Font.GothamMedium
	r2Label.Text = "Next Diamond Tier:"
	r2Label.TextColor3 = Color3.fromRGB(160, 148, 140)
	r2Label.TextSize = 13
	r2Label.TextStrokeTransparency = 1
	r2Label.TextXAlignment = Enum.TextXAlignment.Left
	r2Label.Parent = row2

	local nextTierVal = Instance.new("TextLabel")
	nextTierVal.Name = "NextTierVal"
	nextTierVal.Size = UDim2.new(0.45, 0, 1, 0)
	nextTierVal.Position = UDim2.new(0.55, 0, 0, 0)
	nextTierVal.BackgroundTransparency = 1
	nextTierVal.Font = Enum.Font.GothamBold
	nextTierVal.Text = "at $1.00M"
	nextTierVal.TextColor3 = Color3.fromRGB(212, 175, 55)
	nextTierVal.TextSize = 14
	nextTierVal.TextStrokeTransparency = 1
	nextTierVal.TextXAlignment = Enum.TextXAlignment.Right
	nextTierVal.Parent = row2

	-- Row 3: Career Resets
	local row3 = Instance.new("Frame")
	row3.Size = UDim2.new(1, 0, 0, 32)
	row3.BackgroundTransparency = 1
	row3.LayoutOrder = 4
	row3.Parent = metricsCard

	local r3Label = Instance.new("TextLabel")
	r3Label.Size = UDim2.new(0.6, 0, 1, 0)
	r3Label.BackgroundTransparency = 1
	r3Label.Font = Enum.Font.GothamMedium
	r3Label.Text = "Career Ascensions:"
	r3Label.TextColor3 = Color3.fromRGB(160, 148, 140)
	r3Label.TextSize = 13
	r3Label.TextStrokeTransparency = 1
	r3Label.TextXAlignment = Enum.TextXAlignment.Left
	r3Label.Parent = row3

	local careerAscendVal = Instance.new("TextLabel")
	careerAscendVal.Name = "CareerAscendVal"
	careerAscendVal.Size = UDim2.new(0.4, 0, 1, 0)
	careerAscendVal.Position = UDim2.new(0.6, 0, 0, 0)
	careerAscendVal.BackgroundTransparency = 1
	careerAscendVal.Font = Enum.Font.GothamBold
	careerAscendVal.Text = "0 Completed"
	careerAscendVal.TextColor3 = Color3.fromRGB(74, 222, 128)
	careerAscendVal.TextSize = 14
	careerAscendVal.TextStrokeTransparency = 1
	careerAscendVal.TextXAlignment = Enum.TextXAlignment.Right
	careerAscendVal.Parent = row3

	-- Large Action Button (56px)
	local ascendBtn = Instance.new("TextButton")
	ascendBtn.Name = "AscendButton"
	ascendBtn.Size = UDim2.new(1, 0, 0, 56)
	ascendBtn.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
	ascendBtn.BorderSizePixel = 0
	ascendBtn.Font = Enum.Font.GothamBold
	ascendBtn.Text = "SEAL THE VAULT & ASCEND"
	ascendBtn.TextColor3 = Color3.fromRGB(26, 22, 20)
	ascendBtn.TextSize = 16
	ascendBtn.TextStrokeTransparency = 1
	ascendBtn.LayoutOrder = 7
	ascendBtn.Parent = leftCol

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(0, 8)
	bCorner.Parent = ascendBtn

	local bStroke = Instance.new("UIStroke")
	bStroke.Color = Color3.fromRGB(212, 175, 55)
	bStroke.Thickness = 1
	bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bStroke.Parent = ascendBtn

	local ascendStatus = Instance.new("TextLabel")
	ascendStatus.Name = "AscendStatus"
	ascendStatus.Size = UDim2.new(1, 0, 0, 40)
	ascendStatus.BackgroundTransparency = 1
	ascendStatus.Font = Enum.Font.GothamMedium
	ascendStatus.Text = "Ready to ascend. Press button to begin two-step confirmation."
	ascendStatus.TextColor3 = Color3.fromRGB(212, 175, 55)
	ascendStatus.TextSize = 12
	ascendStatus.TextStrokeTransparency = 1
	ascendStatus.TextWrapped = true
	ascendStatus.LayoutOrder = 8
	ascendStatus.Parent = leftCol

	-- =========================================================================
	-- RIGHT COLUMN (52%): Stacked Retention Ledger (Fills 100% height)
	-- =========================================================================
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightLedgerCol"
	rightCol.Size = UDim2.new(0.52, -7, 1, 0)
	rightCol.BackgroundTransparency = 1
	rightCol.LayoutOrder = 2
	rightCol.Parent = bodyRow

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.Padding = UDim.new(0, 12)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Parent = rightCol

	-- TOP CARD: Preserved Wealth (50% minus half gap)
	local keptCard = Instance.new("Frame")
	keptCard.Name = "KeptCard"
	keptCard.Size = UDim2.new(1, 0, 0.5, -6)
	keptCard.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	keptCard.BorderSizePixel = 0
	keptCard.LayoutOrder = 1
	keptCard.Parent = rightCol

	local kCorner = Instance.new("UICorner")
	kCorner.CornerRadius = UDim.new(0, 10)
	kCorner.Parent = keptCard

	local kStroke = Instance.new("UIStroke")
	kStroke.Color = Color3.fromRGB(65, 160, 90)
	kStroke.Thickness = 1
	kStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	kStroke.Parent = keptCard

	local kPad = Instance.new("UIPadding")
	kPad.PaddingTop = UDim.new(0, 12)
	kPad.PaddingBottom = UDim.new(0, 12)
	kPad.PaddingLeft = UDim.new(0, 16)
	kPad.PaddingRight = UDim.new(0, 16)
	kPad.Parent = keptCard

	local kList = Instance.new("UIListLayout")
	kList.Padding = UDim.new(0, 6)
	kList.SortOrder = Enum.SortOrder.LayoutOrder
	kList.Parent = keptCard

	local keptTitle = Instance.new("TextLabel")
	keptTitle.Name = "KeptTitle"
	keptTitle.Size = UDim2.new(1, 0, 0, 28)
	keptTitle.BackgroundTransparency = 1
	keptTitle.Font = Enum.Font.GothamBold
	keptTitle.Text = "\u{25B2} IMMUTABLE ASSETS (YOU KEEP)"
	keptTitle.TextColor3 = Color3.fromRGB(74, 222, 128)
	keptTitle.TextSize = 15
	keptTitle.TextStrokeTransparency = 1
	keptTitle.TextXAlignment = Enum.TextXAlignment.Left
	keptTitle.LayoutOrder = 1
	keptTitle.Parent = keptCard

	local keptItems = {
		"+ Every Diamond, plus newly extracted yield",
		"+ Unlocked Dice Shapes & Elemental Masteries",
		"+ Diamond Tree Progression Perks & Multipliers",
		"+ All Purchased Gamepass Privileges",
		"+ Redeemed Promo Codes & Daily Login Streak",
	}
	for i, itemText in ipairs(keptItems) do
		local row = Instance.new("TextLabel")
		row.Name = "Credit_" .. i
		row.Size = UDim2.new(1, 0, 0, 32)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.Text = itemText
		row.TextColor3 = Color3.fromRGB(245, 239, 230)
		row.TextSize = 13
		row.TextStrokeTransparency = 1
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i + 1
		row.Parent = keptCard
	end

	-- BOTTOM CARD: Forfeit on Reset (50% minus half gap)
	local lostCard = Instance.new("Frame")
	lostCard.Name = "LostCard"
	lostCard.Size = UDim2.new(1, 0, 0.5, -6)
	lostCard.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	lostCard.BorderSizePixel = 0
	lostCard.LayoutOrder = 2
	lostCard.Parent = rightCol

	local lostC = Instance.new("UICorner")
	lostC.CornerRadius = UDim.new(0, 10)
	lostC.Parent = lostCard

	local lostS = Instance.new("UIStroke")
	lostS.Color = Color3.fromRGB(160, 65, 65)
	lostS.Thickness = 1
	lostS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lostS.Parent = lostCard

	local lostP = Instance.new("UIPadding")
	lostP.PaddingTop = UDim.new(0, 12)
	lostP.PaddingBottom = UDim.new(0, 12)
	lostP.PaddingLeft = UDim.new(0, 16)
	lostP.PaddingRight = UDim.new(0, 16)
	lostP.Parent = lostCard

	local lostL = Instance.new("UIListLayout")
	lostL.Padding = UDim.new(0, 6)
	lostL.SortOrder = Enum.SortOrder.LayoutOrder
	lostL.Parent = lostCard

	local lostTitle = Instance.new("TextLabel")
	lostTitle.Name = "LostTitle"
	lostTitle.Size = UDim2.new(1, 0, 0, 28)
	lostTitle.BackgroundTransparency = 1
	lostTitle.Font = Enum.Font.GothamBold
	lostTitle.Text = "\u{25BC} FORFEIT ON RESET (YOU LOSE)"
	lostTitle.TextColor3 = Color3.fromRGB(248, 113, 113)
	lostTitle.TextSize = 15
	lostTitle.TextStrokeTransparency = 1
	lostTitle.TextXAlignment = Enum.TextXAlignment.Left
	lostTitle.LayoutOrder = 1
	lostTitle.Parent = lostCard

	local lostItems = {
		"\u{2014} All Current Cash Balance (Reset to $0)",
		"\u{2014} All Gem Holdings (Expended on Reset)",
		"\u{2014} All Purchased Cash Multiplier Upgrades",
		"\u{2014} Active Dice Collection (Reset to 1x D2)",
		"\u{2014} Unlocked Extra Die Slots",
	}
	for i, itemText in ipairs(lostItems) do
		local row = Instance.new("TextLabel")
		row.Name = "Debit_" .. i
		row.Size = UDim2.new(1, 0, 0, 32)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamMedium
		row.Text = itemText
		row.TextColor3 = Color3.fromRGB(245, 239, 230)
		row.TextSize = 13
		row.TextStrokeTransparency = 1
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i + 1
		row.Parent = lostCard
	end

	local ASCEND_REFUSAL: { [string]: string } = {
		insufficient_lifetime_cash = "You have not earned enough this run yet.",
		ascension_failed = "Could not ascend. Try again.",
		profile_unavailable = "Still loading -- try again in a moment.",
		rate_limited = "Slow down a moment, then try again.",
		throttled = "Slow down a moment, then try again.",
	}

	-- TWO-STEP CONFIRM. Ascending wipes a run and cannot be undone.
	local refreshAscend: (any) -> ()
	local lastAscensions = 0
	local ascendArmed = false
	local ascendArmToken = 0

	local function disarmAscend()
		ascendArmed = false
		ascendBtn.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
		ascendBtn.TextColor3 = Color3.fromRGB(26, 22, 20)
		ascendBtn.Text = "SEAL THE VAULT & ASCEND"
		bStroke.Color = Color3.fromRGB(212, 175, 55)
		bStroke.Thickness = 1
	end

	UITheme.onPressed(ascendBtn, function()
		if not ascendArmed then
			ascendArmed = true
			ascendArmToken += 1
			local token = ascendArmToken
			ascendBtn.BackgroundColor3 = Color3.fromRGB(220, 38, 38)
			ascendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			ascendBtn.Text = "CONFIRM SETTLEMENT? (NO UNDO)"
			bStroke.Color = Color3.fromRGB(255, 215, 0)
			bStroke.Thickness = 2
			ascendStatus.Text = "WARNING: Press again to confirm. Cash, dice & slots will be wiped permanently."
			ascendStatus.TextColor3 = Color3.fromRGB(248, 113, 113)
			task.delay(4, function()
				if ascendArmed and ascendArmToken == token then
					disarmAscend()
					ascendStatus.Text = "Ready to ascend. Press button to begin two-step confirmation."
					ascendStatus.TextColor3 = Color3.fromRGB(212, 175, 55)
				end
			end)
			return
		end

		disarmAscend()
		UITheme.setEnabled(ascendBtn, false)
		ascendStatus.Text = "Ascending and settling ledger..."
		ascendStatus.TextColor3 = Color3.fromRGB(160, 148, 140)
		task.spawn(function()
			local result = NetClient.ascend()
			if result.ok then
				ascendStatus.Text = "Ascended. Your Diamonds have been granted."
				ascendStatus.TextColor3 = Color3.fromRGB(74, 222, 128)

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
				ascendStatus.TextColor3 = Color3.fromRGB(248, 113, 113)
			end
			UITheme.setEnabled(ascendBtn, true)
		end)
	end)

	refreshAscend = function(state: any)
		local lifetime = if type(state) == "table" then tonumber(state.cash) or 0 else 0
		local ascensions = if type(state) == "table" then tonumber(state.ascensions) or 0 else 0
		local diamonds = if type(state) == "table" then tonumber(state.diamonds) or 0 else 0
		lastAscensions = ascensions
		local projected = DiceCatalog.ascensionDiamonds(lifetime)
		local threshold = DiceCatalog.ASCEND_MIN_LIFETIME_CASH
		local nextMilestone = if projected > 0 then (projected + 1) * 10000000 else threshold

		if projected > 0 then
			ascendReward.Text = string.format("+%s \u{2666} DIAMONDS", Format.formatNumber(projected))
			ascendReward.TextColor3 = Color3.fromRGB(244, 114, 182)
			ascendProgress.Text = string.format("Run Basis: $%s / $%s", Format.formatNumber(lifetime), Format.formatNumber(threshold))
			
			meterFill.Size = UDim2.fromScale(math.min(1, lifetime / threshold), 1)
			meterFill.BackgroundColor3 = Color3.fromRGB(212, 175, 55)

			postVaultVal.Text = string.format("%d \u{2666} (+%d)", diamonds + projected, projected)
			nextTierVal.Text = string.format("at $%s", Format.formatNumber(nextMilestone))
			careerAscendVal.Text = string.format("%d Completed", ascensions)

			UITheme.setEnabled(ascendBtn, true)
			if not ascendArmed then
				ascendBtn.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
				ascendBtn.TextColor3 = Color3.fromRGB(26, 22, 20)
				ascendBtn.Text = "SEAL THE VAULT & ASCEND"
				bStroke.Color = Color3.fromRGB(212, 175, 55)
				bStroke.Thickness = 1
				ascendStatus.Text = "Ready to ascend. Press button to begin two-step confirmation."
				ascendStatus.TextColor3 = Color3.fromRGB(212, 175, 55)
			end
		else
			ascendReward.Text = "+0 \u{2666} DIAMONDS"
			ascendReward.TextColor3 = Color3.fromRGB(140, 130, 120)
			ascendProgress.Text = string.format("Run Basis: $%s / $%s", Format.formatNumber(lifetime), Format.formatNumber(threshold))
			
			meterFill.Size = UDim2.fromScale(math.min(1, lifetime / threshold), 1)
			meterFill.BackgroundColor3 = Color3.fromRGB(220, 38, 38)

			postVaultVal.Text = string.format("%d \u{2666} (+0)", diamonds)
			nextTierVal.Text = string.format("at $%s", Format.formatNumber(threshold))
			careerAscendVal.Text = string.format("%d Completed", ascensions)

			UITheme.setEnabled(ascendBtn, false)
			ascendBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 36)
			ascendBtn.TextColor3 = Color3.fromRGB(140, 130, 120)
			ascendBtn.Text = "UNAVAILABLE // INSUFFICIENT CASH"
			bStroke.Color = Color3.fromRGB(70, 58, 48)
			bStroke.Thickness = 1

			ascendStatus.Text = string.format("Threshold not met: Earn $%s more cash this run to unlock.", Format.formatNumber(math.max(0, threshold - lifetime)))
			ascendStatus.TextColor3 = Color3.fromRGB(248, 113, 113)

			if ascendArmed then
				disarmAscend()
			end
		end
	end

	-- 5. QUESTS OVERLAY (Approved Master Design: Dual-Column Quests & Progression)
	local refreshQuests = buildQuestsOverlay(screenGui, overlays)

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
