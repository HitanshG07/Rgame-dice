--!strict
-- ClientMain.luau
-- Client Entry Point for 2D Bouncy Ball Tycoon.

local UIManager = require(script.Parent:WaitForChild("UIManager"))

task.spawn(function()
	local uiInstance = UIManager.new()
	uiInstance:BuildInterface()
	print("[Client] 2D Bouncy Ball Tycoon Interface initialized successfully.")
end)
