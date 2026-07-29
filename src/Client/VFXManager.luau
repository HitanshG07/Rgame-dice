--!strict
-- VFXManager.luau
-- Client Visual Effects Engine: Bounce Ripple Effects, Gap Exit Particles & Floating Cash Text Popups.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local VFXManager = {}
VFXManager.__index = VFXManager

function VFXManager.new(parentGui: GuiObject)
	local self = setmetatable({}, VFXManager)
	self.ParentGui = parentGui
	return self
end

function VFXManager:CreateBounceRipple(position: Vector2, color: Color3)
	local ripple = Instance.new("Frame")
	ripple.Name = "BounceRipple"
	ripple.Size = UDim2.fromOffset(10, 10)
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	ripple.Position = UDim2.fromOffset(position.X, position.Y)
	ripple.BackgroundColor3 = color
	ripple.BackgroundTransparency = 0.2
	ripple.BorderSizePixel = 0
	ripple.Parent = self.ParentGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ripple

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = ripple

	-- Tween expansion and fade out
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenProps = {
		Size = UDim2.fromOffset(45, 45),
		BackgroundTransparency = 1,
	}

	local tween = TweenService:Create(ripple, tweenInfo, tweenProps)
	tween:Play()
	tween.Completed:Connect(function()
		ripple:Destroy()
	end)
end

function VFXManager:CreateFloatingText(position: Vector2, text: string, color: Color3)
	local label = Instance.new("TextLabel")
	label.Name = "FloatingCashText"
	label.Size = UDim2.fromOffset(120, 30)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextSize = 20
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = self.ParentGui

	-- Float upwards and fade out
	local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local tweenProps = {
		Position = UDim2.fromOffset(position.X, position.Y - 40),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}

	local tween = TweenService:Create(label, tweenInfo, tweenProps)
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

return VFXManager
