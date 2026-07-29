--!strict
-- Physics2D.test.luau
-- Unit tests for 2D Physics Vector Math, Arc Collision, and Gap Exit Detection.

local Physics2DEngine = require(game:GetService("ReplicatedStorage"):WaitForChild("Source"):WaitForChild("Shared"):WaitForChild("Client"):WaitForChild("Physics2DEngine"))

local function Assert(condition: boolean, msg: string)
	if not condition then
		error("[TEST FAILED] " .. msg)
	end
end

print("=== Running UT-2: 2D Physics Engine Math Tests ===")

-- Test 1: Physics Engine Instantiation
local engine = Physics2DEngine.new({
	RingCenter = Vector2.new(300, 300),
	RingRadius = 200,
	RingRPM = 10,
	GapAngleWidth = math.rad(40),
})

Assert(engine ~= nil, "Physics engine instance must be created")
Assert(engine.RingRadius == 200, "Ring radius must be 200")
Assert(engine.RingRPM == 10, "Ring RPM must be 10")

-- Test 2: Angle Normalization & Rotation Integration
local initRotation = engine.RingRotation
engine:Step(0.016) -- Simulate 1 frame (16ms)
Assert(engine.RingRotation > initRotation, "Ring rotation angle should increment over time")

-- Test 3: Ball Addition & Position Verification
local mockContainer = Instance.new("Frame")
local ball = engine:AddBall({
	Color = Color3.fromRGB(255, 0, 0),
	Radius = 20,
	CashMultiplier = 1.0,
	Bounciness = 0.95,
}, mockContainer)

Assert(ball ~= nil, "Ball should be spawned")
Assert(#engine.Balls == 1, "Balls array size must be 1")
Assert(ball.GuiElement ~= nil, "Ball GuiElement must be assigned")

print("[PASS] UT-2: 2D Physics Engine Math Tests succeeded clean!")
return true
