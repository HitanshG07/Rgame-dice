CONSUMED-BY: Gate 3 / Matrix D
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# API CONTRACT & DATASTORE SCHEMA — 2D BOUNCY BALL TYCOON

## 1. DATASTORE SCHEMA (`PlayerData`)

All player state is stored in a single atomic JSON document per player key (`Player_[UserId]`).

```json
{
  "SchemaVersion": 1,
  "Currency": {
    "Cash": 100.0,
    "PrestigePoints": 0,
    "Gems": 0
  },
  "Stats": {
    "TotalBounces": 0,
    "TotalEscapes": 0,
    "TimePlayed": 0,
    "PrestigeCount": 0
  },
  "Upgrades": {
    "AddBall": 1,
    "RingSpin": 0,
    "WidenGap": 0,
    "CoinBonus": 0,
    "IncreaseLuck": 0,
    "RingSpikes": 0
  },
  "Customization": {
    "ActiveBallColor": "#FF007F",
    "ActiveRingColor": "#FF00CC",
    "UnlockedColors": ["#FF007F", "#FF00CC"]
  },
  "ClaimedRewards": {
    "DailySpinTimestamp": 0,
    "ClaimedCodes": []
  }
}
```

---

## 2. CLIENT-SERVER NETWORK CONTRACT (REMOTEEVENTS & REMOTEFUNCTIONS)

All network traffic flows through `ReplicatedStorage.Remotes`.

### R-1: `PurchaseUpgrade` (RemoteFunction)
- **Direction**: Client $\rightarrow$ Server $\rightarrow$ Client
- **Arguments**:
  - `upgradeId` (`string`): ID of upgrade (e.g. `"AddBall"`, `"RingSpin"`, `"WidenGap"`).
- **Return Payload**:
  - `success` (`boolean`): `true` if transaction succeeded.
  - `newLevel` (`number`): Updated level of the upgrade.
  - `newCash` (`number`): Player's updated cash balance.
  - `errorMessage` (`string|nil`): Failure reason if unsuccessful.
- **Validation**:
  - `upgradeId` must match a valid key in `UpgradeDefinitions`.
  - Player must have sufficient `Cash >= Price(newLevel)`.
  - Level must not exceed `MaxLevel`.

### R-2: `ClaimFreeCash` (RemoteFunction)
- **Direction**: Client $\rightarrow$ Server $\rightarrow$ Client
- **Arguments**: None
- **Return Payload**:
  - `success` (`boolean`)
  - `grantedCash` (`number`)
  - `cooldownRemaining` (`number`)
- **Validation**: Server tracks `LastClaimTimestamp` per player. Minimum 300 seconds between claims.

### R-3: `SyncPhysicsBounceBatch` (RemoteEvent)
- **Direction**: Client $\rightarrow$ Server
- **Arguments**:
  - `bounceCount` (`number`): Number of visual bounces in the last batch interval.
  - `escapeCount` (`number`): Number of gap exits in the last batch interval.
- **Validation**:
  - Server bounds check: `bounceCount` cannot exceed `(ActiveBalls * MaxPossibleBounceRate * DeltaTime) + SanityMargin`.
  - Grants validated income and updates player statistics.

### R-4: `PrestigeReset` (RemoteFunction)
- **Direction**: Client $\rightarrow$ Server $\rightarrow$ Client
- **Arguments**: None
- **Return Payload**:
  - `success` (`boolean`)
  - `newPrestigePoints` (`number`)
- **Validation**: Player must meet minimum cash threshold (e.g. `$1,000,000`). Resets cash and upgrade levels while granting Prestige Points.
