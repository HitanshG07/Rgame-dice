--!strict
-- Physics2DEngine.luau
-- High-performance 2D Vector Physics Simulator for Bouncy Ball Tycoon.

export type PhysicsBall = {
	Id: number,
	Position: Vector2,
	Velocity: Vector2,
	Radius: number,
	Color: Color3,
	CashMultiplier: number,
	Bounciness: number,
	GuiElement: Frame,
}

export type PhysicsEngineConfig = {
	RingCenter: Vector2,
	RingRadius: number,
	RingRPM: number,
	GapAngleWidth: number, -- Radians
	Gravity: Vector2,
}

local Physics2DEngine = {}
Physics2DEngine.__index = Physics2DEngine

function Physics2DEngine.new(config: PhysicsEngineConfig)
	local self = setmetatable({}, Physics2DEngine)
	self.RingCenter = config.RingCenter or Vector2.new(300, 300)
	self.RingRadius = config.RingRadius or 200
	self.RingRotation = 0 -- Radians
	self.RingRPM = config.RingRPM or 10
	self.GapAngleWidth = config.GapAngleWidth or math.rad(45)
	self.Gravity = config.Gravity or Vector2.new(0, 350)
	self.Balls = {} :: { PhysicsBall }
	self.NextBallId = 1

	self.OnBounceSignal = nil :: ((ball: PhysicsBall, hitSpike: boolean) -> ())?
	self.OnEscapeSignal = nil :: ((ball: PhysicsBall) -> ())?

	return self
end

function Physics2DEngine:AddBall(ballData: { Color: Color3, Radius: number, CashMultiplier: number, Bounciness: number }, containerGui: GuiObject): PhysicsBall
	local ballFrame = Instance.new("Frame")
	ballFrame.Name = "Ball_" .. tostring(self.NextBallId)
	ballFrame.Size = UDim2.fromOffset(ballData.Radius * 2, ballData.Radius * 2)
	ballFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	ballFrame.BackgroundColor3 = ballData.Color
	ballFrame.BorderSizePixel = 0
	ballFrame.Parent = containerGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ballFrame

	-- Initial random launch velocity
	local angle = math.random() * math.pi * 2
	local speed = math.random(100, 200)
	local initVel = Vector2.new(math.cos(angle) * speed, math.sin(angle) * speed)

	local ball: PhysicsBall = {
		Id = self.NextBallId,
		Position = Vector2.new(0, -20), -- Offset slightly from center
		Velocity = initVel,
		Radius = ballData.Radius,
		Color = ballData.Color,
		CashMultiplier = ballData.CashMultiplier,
		Bounciness = ballData.Bounciness,
		GuiElement = ballFrame,
	}

	self.NextBallId = self.NextBallId + 1
	table.insert(self.Balls, ball)
	return ball
end

function Physics2DEngine:UpdateConfig(rpm: number, gapDegrees: number)
	self.RingRPM = rpm
	self.GapAngleWidth = math.rad(math.clamp(gapDegrees, 10, 120))
end

local function NormalizeAngle(angle: number): number
	angle = angle % (2 * math.pi)
	if angle < 0 then
		angle = angle + (2 * math.pi)
	end
	return angle
end

function Physics2DEngine:Step(dt: number)
	dt = math.clamp(dt, 0.001, 0.05)

	-- Update Ring Rotation
	local rotSpeed = (self.RingRPM * 2 * math.pi) / 60
	self.RingRotation = NormalizeAngle(self.RingRotation + (rotSpeed * dt))

	local gapHalf = self.GapAngleWidth / 2
	local gapStart = NormalizeAngle(self.RingRotation - gapHalf)
	local gapEnd = NormalizeAngle(self.RingRotation + gapHalf)

	for _, ball in ipairs(self.Balls) do
		-- Apply Gravity
		ball.Velocity = ball.Velocity + (self.Gravity * dt)

		-- Update Position
		ball.Position = ball.Position + (ball.Velocity * dt)

		-- Distance from Ring Center (Relative coords: 0,0 is center)
		local dist = ball.Position.Magnitude
		local maxDist = self.RingRadius - ball.Radius

		if dist >= maxDist then
			-- Calculate polar angle of ball relative to center
			local ballAngle = NormalizeAngle(math.atan2(ball.Position.Y, ball.Position.X))

			-- Check if ball angle falls within opening gap
			local isInsideGap = false
			if gapStart < gapEnd then
				isInsideGap = (ballAngle >= gapStart and ballAngle <= gapEnd)
			else
				-- Gap wraps around 0/2pi
				isInsideGap = (ballAngle >= gapStart or ballAngle <= gapEnd)
			end

			if isInsideGap then
				-- Ball Escapes through the gap!
				if self.OnEscapeSignal then
					self.OnEscapeSignal(ball)
				end

				-- Respawn ball at center with fresh launch velocity
				ball.Position = Vector2.new(0, 0)
				local launchAngle = (self.RingRotation + math.pi + (math.random() * 0.5 - 0.25)) % (2 * math.pi)
				local launchSpeed = math.random(150, 250)
				ball.Velocity = Vector2.new(math.cos(launchAngle) * launchSpeed, math.sin(launchAngle) * launchSpeed)
			else
				-- Bounce off inner ring wall
				local normal = -ball.Position.Unit -- Inward normal vector toward center
				local dot = ball.Velocity:Dot(normal)

				if dot < 0 then
					-- Calculate reflected velocity vector
					local impulse = -(1 + ball.Bounciness) * dot
					ball.Velocity = ball.Velocity + (normal * impulse)

					-- Tangential velocity boost from ring spin
					local tangent = Vector2.new(-normal.Y, normal.X)
					local tangentialSpeed = rotSpeed * self.RingRadius * 0.15
					ball.Velocity = ball.Velocity + (tangent * tangentialSpeed)

					-- Position correction to prevent clipping through wall
					ball.Position = -normal * (maxDist - 1)

					-- Trigger bounce callback
					if self.OnBounceSignal then
						self.OnBounceSignal(ball, false)
					end
				end
			end
		end

		-- Render position to UI Frame
		ball.GuiElement.Position = UDim2.fromOffset(
			self.RingCenter.X + ball.Position.X,
			self.RingCenter.Y + ball.Position.Y
		)
	end
end

function Physics2DEngine:Destroy()
	for _, ball in ipairs(self.Balls) do
		if ball.GuiElement then
			ball.GuiElement:Destroy()
		end
	end
	self.Balls = {}
end

return Physics2DEngine
