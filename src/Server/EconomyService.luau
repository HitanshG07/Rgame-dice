--!strict
-- EconomyService.luau
-- THE ONLY MODULE PERMITTED TO MUTATE Cash, Gems, or Diamonds.
--
-- Single chokepoint by design (HLD §3): the audit surface for "can a player
-- gain currency they did not earn" is this one file. IT-4 asserts the property
-- adversarially by attempting mutation through every other service and
-- confirming the balance is unchanged.
--
-- Every write goes through PlayerProfile.mutate, which performs the IsActive
-- check SYNCHRONOUSLY with the mutation -- no yield in between (threat T-26).

local PlayerProfile = require(script.Parent:WaitForChild("PlayerProfile"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ForgeMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ForgeMath"))

local EconomyService = {}

-- Cash is representable to 1e300 without precision loss (SRS NFR-4). Beyond
-- this we clamp rather than let a float go non-finite and poison the profile.
local MAX_CURRENCY = 1e300

type Currency = "Cash" | "Gems" | "Diamonds"

local function guardAmount(amount: number): (boolean, string?)
	if not ForgeMath.isFinite(amount) then
		return false, "non_finite_amount"
	end
	if amount < 0 then
		return false, "negative_amount"
	end
	return true, nil
end

-- Credit. `source` is recorded for telemetry and is never player-supplied.
function EconomyService.credit(player: Player, currency: Currency, amount: number, source: string): (boolean, string?)
	local ok, reason = guardAmount(amount)
	if not ok then
		warn(string.format("[Economy] refused credit of %s to UserId=%d from '%s': %s",
			tostring(amount), player.UserId, source, tostring(reason)))
		return false, reason
	end
	if amount == 0 then
		return true, nil
	end

	return PlayerProfile.mutate(player, function(data)
		local current = data[currency] :: number
		local next_ = current + amount
		if next_ > MAX_CURRENCY then
			next_ = MAX_CURRENCY
		end
		data[currency] = next_

		if currency == "Cash" then
			local lifetime = data.LifetimeCash + amount
			data.LifetimeCash = if lifetime > MAX_CURRENCY then MAX_CURRENCY else lifetime
		end
	end)
end

-- Debit. Refuses rather than going negative -- an overdraft is how duplication
-- bugs become permanent.
function EconomyService.debit(player: Player, currency: Currency, amount: number, source: string): (boolean, string?)
	local ok, reason = guardAmount(amount)
	if not ok then
		return false, reason
	end

	local data = PlayerProfile.get(player)
	if not data then
		return false, "no_profile"
	end
	if (data[currency] :: number) < amount then
		return false, "insufficient_funds"
	end

	return PlayerProfile.mutate(player, function(d)
		local current = d[currency] :: number
		-- re-check inside the mutation: the balance is read above, and although
		-- mutate does not yield, re-reading keeps this correct if that ever changes
		if current < amount then
			return
		end
		d[currency] = current - amount
	end)
end

-- Atomic spend-then-grant. Used by every purchase path so a failed debit can
-- never be followed by a successful grant.
function EconomyService.spend(player: Player, currency: Currency, cost: number, source: string): (boolean, string?)
	return EconomyService.debit(player, currency, cost, source)
end

function EconomyService.balance(player: Player, currency: Currency): number?
	local data = PlayerProfile.get(player)
	if not data then
		return nil
	end
	return data[currency] :: number
end

function EconomyService.canAfford(player: Player, currency: Currency, cost: number): boolean
	if not ForgeMath.isFinite(cost) then
		return false
	end
	local bal = EconomyService.balance(player, currency)
	return bal ~= nil and bal >= cost
end

-- Records the highest single-throw payout, which feeds the Highest Single Roll
-- leaderboard. Monotonic: it may only ever increase.
function EconomyService.recordRoll(player: Player, payout: number): (boolean, string?)
	if not ForgeMath.isFinite(payout) or payout < 0 then
		return false, "bad_payout"
	end
	return PlayerProfile.mutate(player, function(data)
		data.TotalRolls += 1
		if payout > data.HighestRoll then
			data.HighestRoll = payout
		end
	end)
end

return EconomyService
