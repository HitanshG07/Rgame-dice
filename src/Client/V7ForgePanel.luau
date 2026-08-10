--!strict
-- V7ForgePanel.luau
-- Full-Screen Dedicated Zero-Sum Mass Budget Forge Overlay (SRS FR-3).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local V7ForgePanel = {}
V7ForgePanel.__index = V7ForgePanel

export type V7ForgeController = {
	overlay: Frame,
	body: Frame,
	closeBtn: TextButton,
	evLabel: TextLabel,
	voidLabel: TextLabel,
	commitBtn: TextButton,
	show: (self: V7ForgeController) -> (),
	hide: (self: V7ForgeController) -> (),
	onCommitClicked: (self: V7ForgeController, callback: (dieIndex: number, distribution: { number }) -> ()) -> (),
}

function V7ForgePanel.new(): V7ForgeController
	local player = Players.LocalPlayer
	assert(player ~= nil, "[V7ForgePanel] LocalPlayer must exist")
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "V7ForgeGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = UITheme.Layer.Overlay

	local overlayFrame, bodyFrame, closeBtn = UITheme.overlay("🔨 THE FORGE ENGINE (ZERO-SUM MASS ALLOCATOR)")
	overlayFrame.Parent = screenGui
	screenGui.Parent = playerGui

	-- Die Selector Sidebar
	local dieSidebar = Instance.new("Frame")
	dieSidebar.Size = UDim2.fromScale(0.14, 0.96)
	dieSidebar.Position = UDim2.fromScale(0, 0.02)
	dieSidebar.BackgroundTransparency = 1
	dieSidebar.Parent = bodyFrame

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.Padding = UDim.new(0.02, 0)
	sidebarLayout.Parent = dieSidebar

	for i = 1, 5 do
		local dieCard = UITheme.panel(UDim2.fromScale(1, 0.15), UDim2.fromScale(0, 0))
		dieCard.Parent = dieSidebar

		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.fromScale(0.9, 0.8)
		txt.Position = UDim2.fromScale(0.05, 0.1)
		txt.BackgroundTransparency = 1
		txt.Font = UITheme.Font
		txt.Text = string.format("DIE %d (D6)", i)
		txt.TextColor3 = if i == 1 then UITheme.Colors.TextGold else UITheme.Colors.TextDim
		txt.TextScaled = true
		txt.Parent = dieCard
	end

	-- Center Face Editor
	local faceEditor = UITheme.panel(UDim2.fromScale(0.56, 0.96), UDim2.fromScale(0.16, 0.02))
	faceEditor.Parent = bodyFrame

	local faceTitle = Instance.new("TextLabel")
	faceTitle.Size = UDim2.fromScale(0.94, 0.06)
	faceTitle.Position = UDim2.fromScale(0.03, 0.02)
	faceTitle.BackgroundTransparency = 1
	faceTitle.Font = UITheme.FontHeading
	faceTitle.Text = "FACE MASS DISTRIBUTION (BUDGET: 60.00)"
	faceTitle.TextColor3 = UITheme.Colors.TextGold
	faceTitle.TextScaled = true
	faceTitle.TextXAlignment = Enum.TextXAlignment.Left
	faceTitle.Parent = faceEditor

	local faceList = Instance.new("Frame")
	faceList.Size = UDim2.fromScale(0.94, 0.88)
	faceList.Position = UDim2.fromScale(0.03, 0.1)
	faceList.BackgroundTransparency = 1
	faceList.Parent = faceEditor

	local faceLayout = Instance.new("UIListLayout")
	faceLayout.Padding = UDim.new(0.02, 0)
	faceLayout.Parent = faceList

	-- Generate 6 Face Rows
	local masses = { 10, 10, 10, 10, 10, 10 }
	local elements = { "Gold", "Fire", "Freeze", "None", "None", "None" }

	for idx = 1, 6 do
		local row = UITheme.panel(UDim2.fromScale(1, 0.13), UDim2.fromScale(0, 0), true)
		row.Parent = faceList

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(0.12, 0.8)
		lbl.Position = UDim2.fromScale(0.02, 0.1)
		lbl.BackgroundTransparency = 1
		lbl.Font = UITheme.FontHeading
		lbl.Text = string.format("F%d", idx)
		lbl.TextColor3 = UITheme.Colors.PrimaryCyan
		lbl.TextScaled = true
		lbl.Parent = row

		local elLbl = Instance.new("TextLabel")
		elLbl.Size = UDim2.fromScale(0.2, 0.8)
		elLbl.Position = UDim2.fromScale(0.16, 0.1)
		elLbl.BackgroundTransparency = 1
		elLbl.Font = UITheme.Font
		elLbl.Text = elements[idx]
		elLbl.TextColor3 = UITheme.ElementColors[elements[idx]] or UITheme.Colors.TextPrimary
		elLbl.TextScaled = true
		elLbl.Parent = row

		local massLbl = Instance.new("TextLabel")
		massLbl.Size = UDim2.fromScale(0.2, 0.8)
		massLbl.Position = UDim2.fromScale(0.38, 0.1)
		massLbl.BackgroundTransparency = 1
		massLbl.Font = UITheme.Font
		massLbl.Text = string.format("Mass: %d", masses[idx])
		massLbl.TextColor3 = UITheme.Colors.TextPrimary
		massLbl.TextScaled = true
		massLbl.Parent = row

		local minusBtn = Instance.new("TextButton")
		minusBtn.Size = UDim2.fromScale(0.1, 0.7)
		minusBtn.Position = UDim2.fromScale(0.65, 0.15)
		minusBtn.BackgroundColor3 = UITheme.Colors.PanelDeep
		minusBtn.Font = UITheme.Font
		minusBtn.Text = "-"
		minusBtn.TextColor3 = UITheme.Colors.TextGold
		minusBtn.TextScaled = true
		minusBtn.Parent = row

		local plusBtn = Instance.new("TextButton")
		plusBtn.Size = UDim2.fromScale(0.1, 0.7)
		plusBtn.Position = UDim2.fromScale(0.77, 0.15)
		plusBtn.BackgroundColor3 = UITheme.Colors.PanelDeep
		plusBtn.Font = UITheme.Font
		plusBtn.Text = "+"
		plusBtn.TextColor3 = UITheme.Colors.TextGold
		plusBtn.TextScaled = true
		plusBtn.Parent = row
	end

	-- Right Math & Actions Sidebar
	local mathSidebar = UITheme.panel(UDim2.fromScale(0.24, 0.96), UDim2.fromScale(0.74, 0.02))
	mathSidebar.Parent = bodyFrame

	local mathTitle = Instance.new("TextLabel")
	mathTitle.Size = UDim2.fromScale(0.9, 0.06)
	mathTitle.Position = UDim2.fromScale(0.05, 0.02)
	mathTitle.BackgroundTransparency = 1
	mathTitle.Font = UITheme.FontHeading
	mathTitle.Text = "📊 LIVE MATH"
	mathTitle.TextColor3 = UITheme.Colors.TextGold
	mathTitle.TextScaled = true
	mathTitle.Parent = mathSidebar

	local evCard = UITheme.panel(UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.1), true)
	evCard.Parent = mathSidebar
	local evLabel = Instance.new("TextLabel")
	evLabel.Size = UDim2.fromScale(0.9, 0.8)
	evLabel.Position = UDim2.fromScale(0.05, 0.1)
	evLabel.BackgroundTransparency = 1
	evLabel.Font = UITheme.Font
	evLabel.Text = "EV / Roll:\n$100.00"
	evLabel.TextColor3 = UITheme.Colors.Positive
	evLabel.TextScaled = true
	evLabel.Parent = evCard

	local voidCard = UITheme.panel(UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.33), true)
	voidCard.Parent = mathSidebar
	local voidLabel = Instance.new("TextLabel")
	voidLabel.Size = UDim2.fromScale(0.9, 0.8)
	voidLabel.Position = UDim2.fromScale(0.05, 0.1)
	voidLabel.BackgroundTransparency = 1
	voidLabel.Font = UITheme.Font
	voidLabel.Text = "Void Risk:\n0.00% (Safe)"
	voidLabel.TextColor3 = UITheme.Colors.PrimaryCyan
	voidLabel.TextScaled = true
	voidLabel.Parent = voidCard

	local commitBtnFrame = UITheme.panel(UDim2.fromScale(0.9, 0.18), UDim2.fromScale(0.05, 0.76))
	commitBtnFrame.Parent = mathSidebar
	local commitBtn = Instance.new("TextButton")
	commitBtn.Size = UDim2.fromScale(1, 1)
	commitBtn.BackgroundTransparency = 1
	commitBtn.Font = UITheme.FontHeading
	commitBtn.Text = "COMMIT FORGE"
	commitBtn.TextColor3 = UITheme.Colors.TextGold
	commitBtn.TextScaled = true
	commitBtn.Parent = commitBtnFrame

	local self: V7ForgeController = setmetatable({
		overlay = overlayFrame,
		body = bodyFrame,
		closeBtn = closeBtn,
		evLabel = evLabel,
		voidLabel = voidLabel,
		commitBtn = commitBtn,
	}, V7ForgePanel) :: any

	return self
end

function V7ForgePanel:show()
	self.overlay.Visible = true
end

function V7ForgePanel:hide()
	self.overlay.Visible = false
end

function V7ForgePanel:onCommitClicked(callback: (dieIndex: number, distribution: { number }) -> ())
	self.commitBtn.MouseButton1Click:Connect(function()
		callback(1, { 10, 10, 10, 10, 10, 10 })
	end)
end

return V7ForgePanel
