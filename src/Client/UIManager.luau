--!strict
-- UIManager.luau
-- Complete 2D Idle Bouncy Ball Tycoon User Interface Controller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Physics2DEngine = require(script.Parent:WaitForChild("Physics2DEngine"))
local VFXManager = require(script.Parent:WaitForChild("VFXManager"))
local SFXManager = require(script.Parent:WaitForChild("SFXManager"))
local UpgradeDefinitions = require(ReplicatedStorage:WaitForChild("Source"):WaitForChild("Shared"):WaitForChild("UpgradeDefinitions"))
local BallDefinitions = require(ReplicatedStorage:WaitForChild("Source"):WaitForChild("Shared"):WaitForChild("BallDefinitions"))

local UIManager = {}
UIManager.__index = UIManager

function UIManager.new()
	local self = setmetatable({}, UIManager)
	self.Player = Players.LocalPlayer
	self.PlayerGui = self.Player:WaitForChild("PlayerGui")
	
	self.Cash = 92.0
	self.Prestige = 0
	self.UpgradeLevels = {
		AddBall = 1,
		RingSpin = 0,
		WidenGap = 0,
		CoinBonus = 0,
		IncreaseLuck = 0,
		RingSpikes = 0,
	}

	self.ScreenGui = nil :: ScreenGui?
	self.PhysicsEngine = nil :: any
	self.VFX = nil :: any
	self.SFX = nil :: any
	self.UpgradeButtons = {} :: { [string]: Frame }

	return self
end

function UIManager:BuildInterface()
	-- Create Master ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BouncyBallTycoonGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = self.PlayerGui
	self.ScreenGui = screenGui

	-- Background Container Frame
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	background.BorderSizePixel = 0
	background.Parent = screenGui

	-- 1. TOP STATUS HEADER
	self:BuildTopHeader(background)

	-- 2. CENTER PHYSICS CANVAS & RING
	local centerCanvas = Instance.new("Frame")
	centerCanvas.Name = "CenterCanvas"
	centerCanvas.Size = UDim2.fromOffset(600, 600)
	centerCanvas.AnchorPoint = Vector2.new(0.5, 0.5)
	centerCanvas.Position = UDim2.fromScale(0.5, 0.48)
	centerCanvas.BackgroundTransparency = 1
	centerCanvas.Parent = background

	-- Visual Pink Ring Container
	local ringFrame = Instance.new("Frame")
	ringFrame.Name = "PinkRing"
	ringFrame.Size = UDim2.fromOffset(450, 450)
	ringFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	ringFrame.Position = UDim2.fromScale(0.5, 0.5)
	ringFrame.BackgroundTransparency = 1
	ringFrame.Parent = centerCanvas

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Name = "RingStroke"
	ringStroke.Color = Color3.fromRGB(235, 30, 180)
	ringStroke.Thickness = 14
	ringStroke.Parent = ringFrame

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ringFrame

	-- Inner Ball Canvas
	local ballCanvas = Instance.new("Frame")
	ballCanvas.Name = "BallCanvas"
	ballCanvas.Size = UDim2.fromScale(1, 1)
	ballCanvas.BackgroundTransparency = 1
	ballCanvas.Parent = centerCanvas

	-- Initialize Visual & Audio Effects Managers
	self.VFX = VFXManager.new(centerCanvas)
	self.SFX = SFXManager.new()

	-- Initialize Physics Engine
	self.PhysicsEngine = Physics2DEngine.new({
		RingCenter = Vector2.new(300, 300),
		RingRadius = 210,
		RingRPM = 5,
		GapAngleWidth = math.rad(40),
	})

	-- Physics Signals
	self.PhysicsEngine.OnBounceSignal = function(ball, hitSpike)
		local multiplier = ball.CashMultiplier * (1 + (self.UpgradeLevels.CoinBonus * 0.25))
		if hitSpike then multiplier = multiplier * 2 end
		self.Cash = self.Cash + multiplier
		self:UpdateCashDisplay()

		-- Effects
		local canvasPos = Vector2.new(300 + ball.Position.X, 300 + ball.Position.Y)
		self.VFX:CreateBounceRipple(canvasPos, ball.Color)
		self.VFX:CreateFloatingText(canvasPos, "+$" .. string.format("%.0f", multiplier), Color3.fromRGB(40, 230, 80))
		self.SFX:PlayBounceSound(multiplier)
	end

	self.PhysicsEngine.OnEscapeSignal = function(ball)
		local bonus = ball.CashMultiplier * 5 * (1 + (self.UpgradeLevels.CoinBonus * 0.25))
		self.Cash = self.Cash + bonus
		self:UpdateCashDisplay()

		-- Effects
		local canvasPos = Vector2.new(300 + ball.Position.X, 300 + ball.Position.Y)
		self.VFX:CreateFloatingText(canvasPos, "GAP ESCAPE! +$" .. string.format("%.0f", bonus), Color3.fromRGB(245, 220, 20))
		self.SFX:PlayEscapeSound()
	end

	-- Spawn initial balls
	for i = 1, self.UpgradeLevels.AddBall do
		local ballData = BallDefinitions.GetRandomBall(self.UpgradeLevels.IncreaseLuck)
		self.PhysicsEngine:AddBall(ballData, ballCanvas)
	end

	-- 3. LEFT UPGRADE DRAWER
	self:BuildLeftUpgradeDrawer(background)

	-- 4. RIGHT MENU DRAWER
	self:BuildRightMenuDrawer(background)

	-- 5. BOTTOM ACTION BAR
	self:BuildBottomActionBar(background)

	-- Step Physics Engine on RenderStepped
	RunService.RenderStepped:Connect(function(dt)
		if self.PhysicsEngine then
			self.PhysicsEngine:Step(dt)
			-- Rotate visual ring frame
			ringFrame.Rotation = math.deg(self.PhysicsEngine.RingRotation)
		end
	end)
end

function UIManager:BuildTopHeader(parent: GuiObject)
	local topHeader = Instance.new("Frame")
	topHeader.Name = "TopHeader"
	topHeader.Size = UDim2.new(1, 0, 0, 70)
	topHeader.BackgroundTransparency = 1
	topHeader.Parent = parent

	-- Cash Pill Display
	local cashPill = Instance.new("Frame")
	cashPill.Name = "CashPill"
	cashPill.Size = UDim2.fromOffset(220, 50)
	cashPill.AnchorPoint = Vector2.new(0.5, 0)
	cashPill.Position = UDim2.fromScale(0.5, 0.15)
	cashPill.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	cashPill.BorderSizePixel = 0
	cashPill.Parent = topHeader

	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0.5, 0)
	pillCorner.Parent = cashPill

	local pillStroke = Instance.new("UIStroke")
	pillStroke.Color = Color3.fromRGB(40, 210, 80)
	pillStroke.Thickness = 3
	pillStroke.Parent = cashPill

	local cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "CashLabel"
	cashLabel.Size = UDim2.fromScale(1, 1)
	cashLabel.BackgroundTransparency = 1
	cashLabel.Font = Enum.Font.FredokaOne
	cashLabel.Text = "$" .. string.format("%.0f", self.Cash)
	cashLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	cashLabel.TextSize = 28
	cashLabel.Parent = cashPill
	self.CashLabel = cashLabel
end

function UIManager:BuildLeftUpgradeDrawer(parent: GuiObject)
	local leftDrawer = Instance.new("ScrollingFrame")
	leftDrawer.Name = "LeftUpgradeDrawer"
	leftDrawer.Size = UDim2.new(0, 240, 0.7, 0)
	leftDrawer.Position = UDim2.fromScale(0.02, 0.12)
	leftDrawer.BackgroundTransparency = 1
	leftDrawer.ScrollBarThickness = 4
	leftDrawer.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = leftDrawer

	local upgradesList = {
		{ Id = "AddBall", Name = "Add Ring / Ball", Color = Color3.fromRGB(220, 150, 20) },
		{ Id = "RingSpin", Name = "Ring Spin", Color = Color3.fromRGB(230, 160, 0) },
		{ Id = "WidenGap", Name = "Widen Gap", Color = Color3.fromRGB(180, 100, 20) },
		{ Id = "CoinBonus", Name = "Coin Bonus", Color = Color3.fromRGB(30, 180, 80) },
		{ Id = "IncreaseLuck", Name = "Increase Luck", Color = Color3.fromRGB(30, 200, 90) },
		{ Id = "RingSpikes", Name = "Ring Spikes", Color = Color3.fromRGB(200, 30, 50) },
	}

	for idx, item in ipairs(upgradesList) do
		local btn = Instance.new("TextButton")
		btn.Name = "Upgrade_" .. item.Id
		btn.Size = UDim2.new(1, -10, 0, 55)
		btn.BackgroundColor3 = item.Color
		btn.Font = Enum.Font.FredokaOne
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.TextSize = 16
		btn.Text = item.Name .. "\n$" .. tostring(UpgradeDefinitions.CalculateCost(item.Id, self.UpgradeLevels[item.Id]))
		btn.LayoutOrder = idx
		btn.Parent = leftDrawer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			self:PurchaseUpgrade(item.Id)
		end)
		
		self.UpgradeButtons[item.Id] = btn
	end
end

function UIManager:BuildRightMenuDrawer(parent: GuiObject)
	local rightDrawer = Instance.new("Frame")
	rightDrawer.Name = "RightMenuDrawer"
	rightDrawer.Size = UDim2.new(0, 180, 0.7, 0)
	rightDrawer.Position = UDim2.fromScale(0.85, 0.12)
	rightDrawer.BackgroundTransparency = 1
	rightDrawer.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rightDrawer

	local menus = { "Balls", "Prestige", "Shop", "Limited Event", "Leaderboard", "Settings", "Rewards", "Quests", "Codes" }
	for idx, menuName in ipairs(menus) do
		local btn = Instance.new("TextButton")
		btn.Name = "Menu_" .. menuName
		btn.Size = UDim2.new(1, 0, 0, 36)
		btn.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
		btn.Font = Enum.Font.FredokaOne
		btn.Text = "  " .. menuName
		btn.TextColor3 = Color3.fromRGB(220, 220, 240)
		btn.TextSize = 15
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.LayoutOrder = idx
		btn.Parent = rightDrawer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = btn
	end
end

function UIManager:BuildBottomActionBar(parent: GuiObject)
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, 0, 80)
	bottomBar.Position = UDim2.fromScale(0, 0.88)
	bottomBar.BackgroundTransparency = 1
	bottomBar.Parent = parent

	-- Buy Ball Main Action Button
	local buyBallBtn = Instance.new("TextButton")
	buyBallBtn.Name = "BuyBallButton"
	buyBallBtn.Size = UDim2.fromOffset(240, 50)
	buyBallBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	buyBallBtn.Position = UDim2.fromScale(0.5, 0.4)
	buyBallBtn.BackgroundColor3 = Color3.fromRGB(30, 200, 80)
	buyBallBtn.Font = Enum.Font.FredokaOne
	buyBallBtn.Text = "Buy Ball ($23)"
	buyBallBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyBallBtn.TextSize = 22
	buyBallBtn.Parent = bottomBar

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = buyBallBtn

	buyBallBtn.MouseButton1Click:Connect(function()
		self:PurchaseUpgrade("AddBall")
	end)
end

function UIManager:PurchaseUpgrade(upgradeId: string)
	local cost = UpgradeDefinitions.CalculateCost(upgradeId, self.UpgradeLevels[upgradeId])
	if self.Cash >= cost then
		self.Cash = self.Cash - cost
		self.UpgradeLevels[upgradeId] = self.UpgradeLevels[upgradeId] + 1

		-- Apply immediate client physics effects
		if upgradeId == "AddBall" then
			local ballData = BallDefinitions.GetRandomBall(self.UpgradeLevels.IncreaseLuck)
			self.PhysicsEngine:AddBall(ballData, self.ScreenGui.Background.CenterCanvas.BallCanvas)
		elseif upgradeId == "RingSpin" then
			self.PhysicsEngine:UpdateConfig(5 + (self.UpgradeLevels.RingSpin * 2), 40 + (self.UpgradeLevels.WidenGap * 5))
		elseif upgradeId == "WidenGap" then
			self.PhysicsEngine:UpdateConfig(5 + (self.UpgradeLevels.RingSpin * 2), 40 + (self.UpgradeLevels.WidenGap * 5))
		end

		self:UpdateCashDisplay()
	end
end

function UIManager:UpdateCashDisplay()
	if self.CashLabel then
		self.CashLabel.Text = "$" .. string.format("%.0f", self.Cash)
	end
end

return UIManager
