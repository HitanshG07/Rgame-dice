--!strict
-- BoostService.luau
-- Authoritative server-clocked timed boost system (SRS FR-12.2; threat T-20).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))

local BoostService = {}

export type ActiveBoost = {
	kind: string,
	multiplier: number,
	expiresAt: number,
}

--------------------------------------------------------------------------------
-- Boost Management
--------------------------------------------------------------------------------

function BoostService.addBoost(player: Player, kind: string, multiplier: number, durationSec: number): boolean
	if type(kind) ~= "string" or not ForgeMath.isFinite(multiplier) or not ForgeMath.isFinite(durationSec) then
		return false
	end

	return PlayerProfile.mutate(player, function(d)
		local now = os.time()
		local existing = d.Upgrades["Boost_" .. kind .. "_Expiry"] or 0
		local startTime = if existing > now then existing else now
		d.Upgrades["Boost_" .. kind .. "_Expiry"] = startTime + math.floor(durationSec)
		d.Upgrades["Boost_" .. kind .. "_Mult"] = math.floor(multiplier * 100) -- stored as integer percentage
	end)
end

function BoostService.getMultiplier(player: Player, kind: string): number
	local data = PlayerProfile.get(player)
	if not data then
		return 1.0
	end

	local now = os.time()
	local expiry = data.Upgrades["Boost_" .. kind .. "_Expiry"] or 0
	if expiry <= now then
		return 1.0
	end

	local rawMult = data.Upgrades["Boost_" .. kind .. "_Mult"] or 100
	return math.max(1.0, rawMult / 100)
end

function BoostService.isBoostActive(player: Player, kind: string): boolean
	return BoostService.getMultiplier(player, kind) > 1.0
end

return BoostService
