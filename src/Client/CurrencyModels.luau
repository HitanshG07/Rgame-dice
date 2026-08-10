--!strict
-- CurrencyModels.luau
-- Procedurally generates 3D models for UI icons (Cash, Gems, Diamonds)

local CurrencyModels = {}

function CurrencyModels.createCashModel(): Model
	local model = Instance.new("Model")
	model.Name = "CashIcon"
	
	-- Base stack
	local base = Instance.new("Part")
	base.Size = Vector3.new(2, 0.5, 1)
	base.Color = Color3.fromRGB(85, 170, 127)
	base.Material = Enum.Material.Plastic
	base.Anchored = true
	base.CFrame = CFrame.new(0, -0.25, 0)
	base.Parent = model
	
	-- Top bill
	local top = Instance.new("Part")
	top.Size = Vector3.new(1.9, 0.1, 0.9)
	top.Color = Color3.fromRGB(130, 200, 150)
	top.Material = Enum.Material.Plastic
	top.Anchored = true
	top.CFrame = CFrame.new(0, 0.05, 0)
	top.Parent = model
	
	-- Band
	local band = Instance.new("Part")
	band.Size = Vector3.new(0.4, 0.65, 1.05)
	band.Color = Color3.fromRGB(240, 230, 140)
	band.Material = Enum.Material.Plastic
	band.Anchored = true
	band.CFrame = CFrame.new(0, -0.25, 0)
	band.Parent = model
	
	model.PrimaryPart = base
	return model
end

function CurrencyModels.createGemModel(color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "GemIcon"
	
	-- A simple diamond shape made of two pyramids (WedgeParts)
	-- To make a true pyramid, we need 4 wedges for the top, 4 for the bottom.
	-- For a UI icon, a tilted block or a simple composition works best.
	
	-- Core
	local core = Instance.new("Part")
	core.Size = Vector3.new(1, 1, 1)
	core.Color = color
	core.Material = Enum.Material.Glass
	core.Anchored = true
	-- Rotate it so it looks like a diamond standing on its point
	core.CFrame = CFrame.Angles(math.rad(45), math.rad(45), 0)
	core.Parent = model
	
	-- Inner glow (slightly smaller, neon)
	local glow = Instance.new("Part")
	glow.Size = Vector3.new(0.6, 0.6, 0.6)
	glow.Color = color
	glow.Material = Enum.Material.Neon
	glow.Anchored = true
	glow.CFrame = CFrame.Angles(math.rad(45), math.rad(45), 0)
	glow.Parent = model
	
	model.PrimaryPart = core
	return model
end

function CurrencyModels.createDiamondModel(): Model
	return CurrencyModels.createGemModel(Color3.fromRGB(255, 105, 180)) -- Pink
end

function CurrencyModels.createBlueGemModel(): Model
	return CurrencyModels.createGemModel(Color3.fromRGB(0, 170, 255)) -- Blue
end

return CurrencyModels
