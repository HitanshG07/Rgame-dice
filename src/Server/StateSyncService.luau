--!strict
-- StateSyncService.luau
-- The authoritative snapshot pushed to a client (API_DATA_CONTRACT §1.2).
--
-- WHY THIS MODULE EXISTS, AND WHY LATE. `StateSync` was specified in the data
-- contract from the blueprint onward and implemented by NOTHING for three
-- blocks. It went unnoticed through five audit rounds because every one of them
-- audited what the server DID rather than what the contract PROMISED — a row
-- describing an event nobody emits reads exactly like a row describing one that
-- works.
--
-- It surfaced only when the client was built: THREE swarm workers, in isolated
-- contexts and given different slices, independently reported it. Each hit a
-- different consequence — dice with no shape or mass, a HUD with no balances, a
-- forge showing every element locked.
--
-- THE RULE THIS MODULE ENFORCES. Everything the client displays comes from here
-- or from `RollResult`. No client may derive a balance, and no client may assume
-- a default for something the server owns. That is why the payload is built by
-- explicit field, never by handing over the profile: `PurchaseIds`,
-- `CodesRedeemed` and the receipt ledger are the player's data but they are not
-- the player's business, and a snapshot that ships the whole profile leaks the
-- purchase history to anyone with a network inspector.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local PurchaseService = require(script.Parent:WaitForChild("PurchaseService"))
local RollService = require(script.Parent:WaitForChild("RollService"))

local StateSyncService = {}

--------------------------------------------------------------------------------
-- Emission seam. Same rationale as RollService's and ForgeService's: the suite
-- drives this with a fake player, and the alternative is typeof-guards and a
-- swallowing pcall in the production path. STUDIO-ONLY.
--------------------------------------------------------------------------------

local RunService = game:GetService("RunService")

local function defaultEmit(player: Player, payload: any): ()
	Remotes.getEvent("StateSync"):FireClient(player, payload)
end

local emitState: (Player, any) -> () = defaultEmit

function StateSyncService._setEmitterForTesting(fn: ((Player, any) -> ())?): ()
	if not RunService:IsStudio() then
		error("[StateSyncService] the emitter seam is Studio-only", 2)
	end
	emitState = fn or defaultEmit
end

--------------------------------------------------------------------------------
-- Snapshot construction
--------------------------------------------------------------------------------

-- Copies only what the contract names. Explicit field-by-field BY DESIGN: a
-- snapshot built by handing over `profile.Data` would ship PurchaseIds,
-- PurchaseOrder and CodesRedeemed to the client, and would silently start
-- shipping every future field the moment someone added one to the template.
-- The client cannot be trusted with what it does not need to know.
function StateSyncService.buildSnapshot(data: PlayerProfile.Profile, streak: number, player: Player?): any
	local dice = {}
	for i, die in ipairs(data.Dice) do
		local faces = {}
		for j, face in ipairs(die.Faces) do
			faces[j] = { Mass = face.Mass, Element = face.Element }
		end
		dice[i] = {
			Shape = die.Shape,
			MassBudget = die.MassBudget,
			-- Schema v2. The forge needs the owned figure as well as the usable
			-- one, or it cannot show why a narrower shape is capping the player.
			PurchasedBudget = die.PurchasedBudget,
			Faces = faces,
		}
	end

	local upgrades = {}
	for id, level in pairs(data.Upgrades) do
		upgrades[id] = level
	end

	-- The unlocked sets. Without these the forge defaults to showing EVERYTHING
	-- locked, which is the safe direction to fail but is not the truth.
	local elements = {}
	for id, unlocked in pairs(data.Diamond.Elements) do
		elements[id] = unlocked
	end
	local shapes = {}
	for id, unlocked in pairs(data.Diamond.Shapes) do
		shapes[id] = unlocked
	end

	local settings = {}
	for key, enabled in pairs(data.Settings) do
		settings[key] = enabled
	end

	local extraSlots = if player ~= nil then PurchaseService.bonusDieSlots(player) else 0

	return {
		cash = data.Cash,
		gems = data.Gems,
		diamonds = data.Diamonds,
		dice = dice,
		upgrades = upgrades,
		diamondTree = {
			StreakStrength = data.Diamond.StreakStrength,
			MassCeiling = data.Diamond.MassCeiling,
			SlotNodes = data.Diamond.SlotNodes,
			Elements = elements,
			Shapes = shapes,
		},
		settings = settings,
		streak = streak,
		boosts = {},          -- Block 5 populates this; an empty table, never nil
		serverTime = os.time(),
		-- Stats the HUD and the Statistics panel read. Present here rather than
		-- in a second event because they change on the same cadence.
		lifetimeCash = data.LifetimeCash,
		highestRoll = data.HighestRoll,
		ascensions = data.Ascensions,
		totalRolls = data.TotalRolls,
		dieSlots = math.min(7, data.DieSlots + extraSlots),
	}
end

--------------------------------------------------------------------------------
-- Push
--------------------------------------------------------------------------------

-- Fails CLOSED and silently: a player mid-teardown has no profile, and firing at
-- them would either error or deliver a snapshot of nothing. Returns whether a
-- push happened so callers and tests can assert it rather than assume it.
function StateSyncService.push(player: Player): boolean
	if player.Parent ~= Players then
		return false
	end
	local data = PlayerProfile.get(player)
	if not data then
		return false
	end
	emitState(player, StateSyncService.buildSnapshot(data, RollService.getStreak(player), player))
	return true
end

-- Convenience for the call sites that mutate state and must announce it. Named
-- for the reason it exists rather than for what it does, so the next author sees
-- the obligation: EVERY state change owes the client a snapshot, or the display
-- silently drifts from the truth.
function StateSyncService.announceChange(player: Player): ()
	StateSyncService.push(player)
end

return StateSyncService
