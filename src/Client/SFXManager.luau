--!strict
-- SFXManager.luau
-- Client Audio Controller with Dynamic Pitch Shifting Bounce Sound Generator.

local SoundService = game:GetService("SoundService")

local SFXManager = {}
SFXManager.__index = SFXManager

function SFXManager.new()
	local self = setmetatable({}, SFXManager)
	self.BounceSound = Instance.new("Sound")
	self.BounceSound.Name = "BounceSound"
	self.BounceSound.SoundId = "rbxassetid://9114223178" -- Standard pop sound asset ID
	self.BounceSound.Volume = 0.35
	self.BounceSound.Parent = SoundService

	self.EscapeSound = Instance.new("Sound")
	self.EscapeSound.Name = "EscapeSound"
	self.EscapeSound.SoundId = "rbxassetid://9114221589" -- High-frequency reward sound asset ID
	self.EscapeSound.Volume = 0.5
	self.EscapeSound.Parent = SoundService

	self.RecentBounceCount = 0
	return self
end

function SFXManager:PlayBounceSound(multiplier: number)
	self.RecentBounceCount = self.RecentBounceCount + 1
	-- Dynamic pitch shift based on multiplier and bounce speed
	local pitch = math.clamp(0.9 + (multiplier * 0.05) + ((self.RecentBounceCount % 8) * 0.04), 0.8, 2.0)
	self.BounceSound.PlaybackSpeed = pitch
	self.BounceSound:Play()

	task.delay(1.5, function()
		self.RecentBounceCount = math.max(0, self.RecentBounceCount - 1)
	end)
end

function SFXManager:PlayEscapeSound()
	self.EscapeSound.PlaybackSpeed = 1.2
	self.EscapeSound:Play()
end

return SFXManager
