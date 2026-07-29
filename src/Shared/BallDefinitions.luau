--!strict
-- BallDefinitions.luau
-- Authoritative catalog for ball types, colors, radii, and income multipliers.

export type BallData = {
	Id: string,
	Name: string,
	Color: Color3,
	Radius: number,
	Bounciness: number,
	CashMultiplier: number,
	SpawnWeight: number,
}

local BallDefinitions = {}

local BALL_TYPES: { BallData } = {
	{
		Id = "MagentaBall",
		Name = "Magenta Ball",
		Color = Color3.fromRGB(235, 30, 180),
		Radius = 24,
		Bounciness = 0.95,
		CashMultiplier = 1.0,
		SpawnWeight = 40,
	},
	{
		Id = "YellowBall",
		Name = "Yellow Ball",
		Color = Color3.fromRGB(245, 220, 20),
		Radius = 22,
		Bounciness = 0.96,
		CashMultiplier = 1.5,
		SpawnWeight = 25,
	},
	{
		Id = "GreenBall",
		Name = "Green Ball",
		Color = Color3.fromRGB(30, 215, 60),
		Radius = 20,
		Bounciness = 0.97,
		CashMultiplier = 2.0,
		SpawnWeight = 15,
	},
	{
		Id = "CyanBall",
		Name = "Cyan Ball",
		Color = Color3.fromRGB(20, 200, 220),
		Radius = 20,
		Bounciness = 0.98,
		CashMultiplier = 3.0,
		SpawnWeight = 10,
	},
	{
		Id = "OrangeBall",
		Name = "Orange Ball",
		Color = Color3.fromRGB(245, 140, 20),
		Radius = 22,
		Bounciness = 0.96,
		CashMultiplier = 4.0,
		SpawnWeight = 6,
	},
	{
		Id = "BlueBall",
		Name = "Blue Ball",
		Color = Color3.fromRGB(30, 120, 230),
		Radius = 24,
		Bounciness = 0.95,
		CashMultiplier = 5.0,
		SpawnWeight = 3,
	},
	{
		Id = "PurpleBall",
		Name = "Purple Ball",
		Color = Color3.fromRGB(150, 40, 210),
		Radius = 26,
		Bounciness = 0.94,
		CashMultiplier = 10.0,
		SpawnWeight = 1,
	},
}

function BallDefinitions.GetAll(): { BallData }
	return BALL_TYPES
end

function BallDefinitions.GetRandomBall(luckLevel: number): BallData
	local totalWeight = 0
	local weightedList = {}

	for _, ball in ipairs(BALL_TYPES) do
		local weight = ball.SpawnWeight
		if ball.CashMultiplier > 2.0 then
			weight = weight * (1 + (luckLevel * 0.2))
		end
		totalWeight = totalWeight + weight
		table.insert(weightedList, { Ball = ball, CumWeight = totalWeight })
	end

	local roll = math.random() * totalWeight
	for _, entry in ipairs(weightedList) do
		if roll <= entry.CumWeight then
			return entry.Ball
		end
	end

	return BALL_TYPES[1]
end

return BallDefinitions
