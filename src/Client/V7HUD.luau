--!strict
-- V7HUD.luau (Neumorphic Ethereal Redesign - Bugfix & Scale Fix)
-- Fixed clipping issues and layout distortions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local V7HUD = {}
V7HUD.__index = V7HUD

export type V7HUDController = {
	gui: ScreenGui,
	cashLabel: TextLabel,
	gemsLabel: TextLabel,
	diamondsLabel: TextLabel,
	streakArcContainer: Frame,
	streakMultLabel: TextLabel,
	streakCountLabel: TextLabel,
	streakRiskLabel: TextLabel,
	payoutLabel: TextLabel,
	autoBtn: TextButton,
	rollBtn: TextButton,
	menuCallbacks: { (menuId: string) -> () },
	updateBalances: (self: V7HUDController, cash: number, gems: number, diamonds: number) -> (),
	onMenuClicked: (self: V7HUDController, callback: (menuId: string) -> ()) -> (),
	onRollClicked: (self: V7HUDController, callback: () -> ()) -> (),
	onAutoToggled: (self: V7HUDController, callback: (enabled: boolean) -> ()) -> (),
}

function V7HUD.new(): V7HUDController
	local player = Players.LocalPlayer
	assert(player ~= nil, "[V7HUD] LocalPlayer must exist")
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "V7HUDGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = UITheme.Layer.HUD
	
	-- Transparent HUD Background (BoardView owns the backdrop layer)
	local bgTint = Instance.new("Frame")
	bgTint.Size = UDim2.fromScale(1, 1)
	bgTint.Position = UDim2.fromScale(0, 0)
	bgTint.BackgroundColor3 = UITheme.Colors.BaseCream
	bgTint.BackgroundTransparency = 1
	bgTint.BorderSizePixel = 0
	bgTint.ZIndex = 0
	bgTint.Parent = gui

	local menuCallbacks: { (menuId: string) -> () } = {}

	-- ==========================================
	-- 1. TOP NEUMORPHIC BAR (Currencies)
	-- ==========================================
	local topBar, topBarBody = UITheme.neumorphicPod(UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.2, 0.02))
	topBar.Parent = gui

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	topLayout.Padding = UDim.new(0.05, 0)
	topLayout.Parent = topBarBody

	local function createCurrency(iconType: string, labelText: string, widthScale: number)
		local pod = Instance.new("Frame")
		pod.Size = UDim2.fromScale(widthScale, 1)
		pod.BackgroundTransparency = 1
		pod.ZIndex = 3
		pod.Parent = topBarBody
		
		-- 2D Vector Icon Container
		local iconContainer = Instance.new("Frame")
		iconContainer.Size = UDim2.fromScale(0.35, 0.8)
		iconContainer.Position = UDim2.fromScale(0.02, 0.1)
		iconContainer.BackgroundTransparency = 1
		iconContainer.ZIndex = 4
		iconContainer.Parent = pod
		
		-- Keep aspect ratio square
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = iconContainer
		
		if iconType == "cash" then
			-- Vector Cash Stack
			local cashBase = Instance.new("Frame")
			cashBase.Size = UDim2.fromScale(0.9, 0.5)
			cashBase.Position = UDim2.fromScale(0.05, 0.25)
			cashBase.BackgroundColor3 = Color3.fromRGB(85, 170, 127)
			cashBase.ZIndex = 4
			cashBase.Parent = iconContainer
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.15, 0)
			corner.Parent = cashBase
			
			local band = Instance.new("Frame")
			band.Size = UDim2.fromScale(0.2, 1)
			band.Position = UDim2.fromScale(0.4, 0)
			band.BackgroundColor3 = Color3.fromRGB(240, 230, 140)
			band.BorderSizePixel = 0
			band.ZIndex = 5
			band.Parent = cashBase
			
			local inner = Instance.new("Frame")
			inner.Size = UDim2.fromScale(0.8, 0.6)
			inner.Position = UDim2.fromScale(0.1, 0.2)
			inner.BackgroundColor3 = Color3.fromRGB(130, 200, 150)
			inner.ZIndex = 4
			inner.Parent = cashBase
			
			local innerCorner = Instance.new("UICorner")
			innerCorner.CornerRadius = UDim.new(0.1, 0)
			innerCorner.Parent = inner
			
			-- Subtle rotation
			cashBase.Rotation = -10
			
		elseif iconType == "gems" or iconType == "diamonds" then
			-- Vector Gem/Diamond
			local color = iconType == "gems" and Color3.fromRGB(0, 120, 220) or Color3.fromRGB(220, 40, 130)
			
			local gemBase = Instance.new("Frame")
			gemBase.Size = UDim2.fromScale(0.7, 0.7)
			gemBase.Position = UDim2.fromScale(0.15, 0.15)
			gemBase.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			gemBase.Rotation = 45
			gemBase.ZIndex = 4
			gemBase.Parent = iconContainer
			
			local grad = Instance.new("UIGradient")
			grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), color)
			grad.Rotation = 45
			grad.Parent = gemBase
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.1, 0)
			corner.Parent = gemBase
			
			local inner = Instance.new("Frame")
			inner.Size = UDim2.fromScale(0.5, 0.5)
			inner.Position = UDim2.fromScale(0.25, 0.25)
			inner.BackgroundColor3 = color
			inner.BorderSizePixel = 0
			inner.ZIndex = 5
			inner.Parent = gemBase
		end

		local titleLbl = UITheme.label(labelText, UDim2.fromScale(0.6, 0.4), UDim2.fromScale(0.35, 0.1), UITheme.Colors.TextDim)
		titleLbl.Font = UITheme.Font
		titleLbl.Parent = pod

		local valLbl = UITheme.label("0", UDim2.fromScale(0.6, 0.5), UDim2.fromScale(0.35, 0.5), UITheme.Colors.TextPrimary)
		valLbl.Font = UITheme.FontHeading
		valLbl.Parent = pod
		
		return pod, valLbl
	end

	local _, cashLabel = createCurrency("cash", "CASH", 0.3)
	local _, gemsLabel = createCurrency("gems", "GEMS", 0.25)
	local _, diamondsLabel = createCurrency("diamonds", "DIAMONDS", 0.25)

	-- ==========================================
	-- 2. CENTER ARC (Streak Data)
	-- ==========================================
	local centerArea, centerBody = UITheme.neumorphicPod(UDim2.fromScale(0.4, 0.12), UDim2.fromScale(0.3, 0.66))
	centerArea.Parent = gui

	local centerLayout = Instance.new("UIListLayout")
	centerLayout.FillDirection = Enum.FillDirection.Horizontal
	centerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	centerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	centerLayout.Padding = UDim.new(0.04, 0)
	centerLayout.Parent = centerBody

	local streakMultLabel = UITheme.label("x4.82", UDim2.fromScale(0.25, 0.8), UDim2.fromScale(0, 0), UITheme.Colors.Gems)
	streakMultLabel.Font = UITheme.FontHeading
	streakMultLabel.TextXAlignment = Enum.TextXAlignment.Center
	streakMultLabel.LayoutOrder = 1
	streakMultLabel.Parent = centerBody

	local infoContainer = Instance.new("Frame")
	infoContainer.Size = UDim2.fromScale(0.4, 0.9)
	infoContainer.BackgroundTransparency = 1
	infoContainer.LayoutOrder = 2
	infoContainer.Parent = centerBody
	
	local infoLayout = Instance.new("UIListLayout")
	infoLayout.FillDirection = Enum.FillDirection.Vertical
	infoLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	infoLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	infoLayout.Parent = infoContainer

	local streakCountLabel = UITheme.label("STREAK: 14", UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0), UITheme.Colors.TextPrimary)
	streakCountLabel.TextXAlignment = Enum.TextXAlignment.Center
	streakCountLabel.Font = UITheme.FontHeading
	streakCountLabel.Parent = infoContainer
	
	local streakRiskLabel = UITheme.label("SAFE (0.0% VOID RISK)", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0), UITheme.Colors.Positive)
	streakRiskLabel.TextXAlignment = Enum.TextXAlignment.Center
	streakRiskLabel.Parent = infoContainer

	local payoutLabel = UITheme.label("+$14.8M", UDim2.fromScale(0.25, 0.8), UDim2.fromScale(0, 0), UITheme.Colors.Cash)
	payoutLabel.Font = UITheme.FontHeading
	payoutLabel.TextXAlignment = Enum.TextXAlignment.Center
	payoutLabel.LayoutOrder = 3
	payoutLabel.Visible = false
	payoutLabel.Parent = centerBody

	-- ==========================================
	-- 3. LEFT & RIGHT NEUMORPHIC PANELS
	-- ==========================================
	local leftPanel, leftPanelBody = UITheme.neumorphicPod(UDim2.fromScale(0.12, 0.5), UDim2.fromScale(0.02, 0.25))
	leftPanel.Parent = gui
	
	local leftLayout = Instance.new("UIListLayout")
	leftLayout.FillDirection = Enum.FillDirection.Vertical
	leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	leftLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	leftLayout.Padding = UDim.new(0.05, 0)
	leftLayout.Parent = leftPanelBody

	local rightPanel, rightPanelBody = UITheme.neumorphicPod(UDim2.fromScale(0.12, 0.5), UDim2.fromScale(0.86, 0.25))
	rightPanel.Parent = gui
	
	local rightLayout = Instance.new("UIListLayout")
	rightLayout.FillDirection = Enum.FillDirection.Vertical
	rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rightLayout.Padding = UDim.new(0.05, 0)
	rightLayout.Parent = rightPanelBody

	local function addMenuBtn(parentBody: Instance, id: string, text: string, color: Color3?)
		local btnWrapper, btn = UITheme.neumorphicButton(text, color, UDim2.fromScale(0.8, 0.18), UDim2.fromScale(0, 0))
		btnWrapper.Parent = parentBody
		
		local lastTrigger = 0
		local function trigger()
			local now = os.clock()
			if now - lastTrigger < 0.15 then return end
			lastTrigger = now
			for _, cb in ipairs(menuCallbacks) do pcall(cb, id) end
		end
		
		btn.MouseButton1Click:Connect(trigger)
		btn.Activated:Connect(trigger)
	end

	addMenuBtn(leftPanelBody, "forge", "FORGE", UITheme.Colors.TextGold)
	addMenuBtn(leftPanelBody, "shapes", "SHAPE", UITheme.Colors.PrimaryCyan)
	addMenuBtn(leftPanelBody, "slots", "SLOTS", UITheme.Colors.TextPrimary)
	addMenuBtn(leftPanelBody, "ascend", "ASCEND", UITheme.Colors.PurpleAscend)

	addMenuBtn(rightPanelBody, "shop", "SHOP", UITheme.Colors.Gems)
	addMenuBtn(rightPanelBody, "boards", "BOARDS", UITheme.Colors.TextPrimary)
	addMenuBtn(rightPanelBody, "quests", "QUESTS", UITheme.Colors.Cash)
	addMenuBtn(rightPanelBody, "vault", "VAULT", UITheme.Colors.TextGold)

	-- ==========================================
	-- 4. BOTTOM CENTER ROLL STATION
	-- ==========================================
	local rollStation, rollStationBody = UITheme.neumorphicPod(UDim2.fromScale(0.35, 0.16), UDim2.fromScale(0.325, 0.8))
	rollStation.Parent = gui
	
	-- The Main Roll Button (Extruded deeply)
	local rollWrapper, rollBtn = UITheme.neumorphicButton(
		"ROLL", 
		UITheme.Colors.TextGold, 
		UDim2.fromScale(0.6, 0.7), 
		UDim2.fromScale(0.05, 0.15)
	)
	rollWrapper.Parent = rollStationBody

	-- The Auto Toggle
	local autoWrapper, autoBtn = UITheme.neumorphicButton(
		"AUTO",
		UITheme.Colors.TextDim,
		UDim2.fromScale(0.25, 0.5),
		UDim2.fromScale(0.7, 0.25)
	)
	autoWrapper.Parent = rollStationBody

	gui.Parent = playerGui

	local self: V7HUDController = setmetatable({
		gui = gui,
		cashLabel = cashLabel,
		gemsLabel = gemsLabel,
		diamondsLabel = diamondsLabel,
		streakArcContainer = centerArea,
		streakMultLabel = streakMultLabel,
		streakCountLabel = streakCountLabel,
		streakRiskLabel = streakRiskLabel,
		payoutLabel = payoutLabel,
		autoBtn = autoBtn,
		rollBtn = rollBtn,
		menuCallbacks = menuCallbacks,
	}, V7HUD) :: any

	return self
end

function V7HUD:updateBalances(cash: number, gems: number, diamonds: number)
	-- NFR-4, THE SUFFIX LADDER. This was `string.format("$%.2e", cash)`, which
	-- showed players "$2.06e+04" instead of "$20.6K" -- scientific notation is a
	-- programmer's format, and an idle game whose central number is unreadable
	-- has broken its own core feedback loop.
	--
	-- `Format.formatNumber` is the shared implementation, already precision-safe
	-- to 1e300 and already handling NaN and infinity. It existed the whole time;
	-- this module simply never required it.
	self.cashLabel.Text = "$" .. Format.formatNumber(cash)
	self.gemsLabel.Text = Format.formatNumber(gems)
	self.diamondsLabel.Text = Format.formatNumber(diamonds)
end

function V7HUD:onMenuClicked(callback: (menuId: string) -> ())
	table.insert(self.menuCallbacks, callback)
end

function V7HUD:onRollClicked(callback: () -> ())
	local lastTrigger = 0
	local function trigger()
		local now = os.clock()
		if now - lastTrigger < 0.1 then return end
		lastTrigger = now
		pcall(callback)
	end
	self.rollBtn.MouseButton1Click:Connect(trigger)
	self.rollBtn.Activated:Connect(trigger)
end

function V7HUD:onAutoToggled(callback: (enabled: boolean) -> ())
	local active = false
	local function trigger()
		active = not active
		
		local wrapper = self.autoBtn.Parent :: Frame
		local body = wrapper:FindFirstChildOfClass("Frame")
		if body then
			local lbl = body:FindFirstChildOfClass("TextLabel")
			if lbl then
				lbl.TextColor3 = if active then UITheme.Colors.Positive else UITheme.Colors.TextDim
			end
		end

		pcall(callback, active)
	end
	
	self.autoBtn.MouseButton1Click:Connect(trigger)
	self.autoBtn.Activated:Connect(trigger)
end

return V7HUD
