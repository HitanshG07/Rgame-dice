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

--------------------------------------------------------------------------------
-- THE CASH MULTIPLIER, INJECTED RATHER THAN REQUIRED.
--
-- `award` needs the 2x-Cash gamepass multiplier, which `PurchaseService` owns.
-- `PurchaseService` already requires this module's siblings, so requiring it
-- back forms a cycle: EconomyService -> PurchaseService -> OfflineService ->
-- EconomyService. That cycle was previously broken with a lazy `require` inside
-- the function body -- the L-035 workaround -- which WORKS at runtime and still
-- leaves the analyser reporting the cycle at four separate sites, because the
-- edge genuinely exists, merely deferred.
--
-- INVERTING THE EDGE REMOVES IT. `PurchaseService` registers its multiplier
-- here at boot; this module never names it. The dependency now points one way,
-- the analyser has nothing to report, and the runtime behaviour is unchanged.
--
-- FAIL-SAFE DEFAULT: 1.0, meaning "no multiplier". If registration has not
-- happened yet -- a payout during boot, or a test that never wires it -- the
-- player receives their base rate rather than an error or an inflated award.
-- The dangerous direction here is UP, so the default is the floor.
local cashMultiplierProvider: ((Player) -> number)? = nil

function EconomyService.setCashMultiplierProvider(fn: (Player) -> number): ()
	cashMultiplierProvider = fn
end

-- Reads the multiplier defensively. A provider that errors or returns nonsense
-- must not stop a payout, and must never silently scale it by a non-finite
-- value -- so anything unusable falls back to 1.0.
local function cashMultiplierFor(player: Player): number
	local provider = cashMultiplierProvider
	if provider == nil then
		return 1
	end
	local ok, value = pcall(provider, player)
	if not ok or type(value) ~= "number" or not ForgeMath.isFinite(value) or value <= 0 then
		return 1
	end
	return value
end

type Currency = "Cash" | "Gems" | "Diamonds"

-- Currency access is EXPLICIT, one branch per field, rather than a computed
-- `data[currency]` index.
--
-- Two reasons, and the type checker is only the second one. `Profile` is a
-- sealed type, so writing through a computed key raises "Cannot add indexer to
-- table 'Profile'" -- silenceable with a `:: any` cast, but that cast would also
-- silence a genuine typo writing to a field that does not exist. The first
-- reason is the audit surface: EconomyService is the SOLE writer of currency
-- (SRS FR-14.8, HLD §5.2 rule 3), and these two functions are the complete,
-- readable list of every profile field it can touch. A computed index makes
-- that list unbounded by inspection.
local function readBalance(data: PlayerProfile.Profile, currency: Currency): number
	if currency == "Cash" then
		return data.Cash
	elseif currency == "Gems" then
		return data.Gems
	end
	return data.Diamonds
end

local function writeBalance(data: PlayerProfile.Profile, currency: Currency, value: number): ()
	if currency == "Cash" then
		data.Cash = value
	elseif currency == "Gems" then
		data.Gems = value
	else
		data.Diamonds = value
	end
end

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

	local finalAmount = amount
	if currency == "Cash" and source == "roll" then
		finalAmount = amount * cashMultiplierFor(player)
	end

	return PlayerProfile.mutate(player, function(data)
		local current = readBalance(data, currency)
		local next_ = current + finalAmount
		if next_ > MAX_CURRENCY then
			next_ = MAX_CURRENCY
		end
		writeBalance(data, currency, next_)

		if currency == "Cash" then
			-- ALL-TIME, and it must NOT reset: the NetWorth leaderboard ranks on
			-- it. A second per-run counter used to be maintained alongside it here
			-- to price ascension; that counter has been deleted and ascension now
			-- reads cash on hand, which `writeBalance` above has already updated.
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
	if readBalance(data, currency) < amount then
		return false, "insufficient_funds"
	end

	return PlayerProfile.mutate(player, function(d)
		local current = readBalance(d, currency)
		-- re-check inside the mutation: the balance is read above, and although
		-- mutate does not yield, re-reading keeps this correct if that ever changes
		if current < amount then
			return
		end
		writeBalance(d, currency, current - amount)
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
	return readBalance(data, currency)
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
