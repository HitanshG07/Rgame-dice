CONSUMED-BY: Gate 3 / Matrix D
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# API & DATA CONTRACT — DICE FORGE INCREMENTAL

Gate 3 audits the implemented remotes and the persisted schema against this document. Divergence is either a finding or an amendment citing its triggering fact.

**The rule that generates this whole document:** no inbound message may carry a price, balance, reward, score, level, duration, multiplier, or outcome. The client sends **intent**; the server sends **truth**. Every row below is checkable against that rule (SRS NFR-5).

---

## 1. REMOTE INVENTORY

All remotes live under `ReplicatedStorage.Remotes`, are created by the server, and are registered exclusively in `RemoteGateway`. **`RemoteFunction:InvokeClient()` appears nowhere in the codebase** — an exploiting client can hang the server thread forever (threat T-8).

### 1.1 Inbound — RemoteFunction (client calls, server returns)

| Remote | Args | Returns | Validation |
|---|---|---|---|
| `Roll` | *(none)* | `ok, reason?` | Rate-limit against the player's **server-known** auto-roll tier. Zero arity enforced — any argument rejects the call. |
| `Forge` | `dieIndex: number`, `distribution: {number}` | `ok, reason?` | See §2.1. The whole proposal is accepted or rejected atomically. |
| `SetElement` | `dieIndex: number`, `faceIndex: number`, `elementId: string` | `ok, reason?` | `elementId` resolved against the server catalog ∩ player's unlocked set. Never used as a table index. |
| `SetShape` | `dieIndex: number`, `shapeId: string` | `ok, reason?` | `shapeId` allowlisted; Diamond cost checked server-side. |
| `BuyUpgrade` | `upgradeId: string` | `ok, newLevel?, reason?` | `upgradeId` allowlisted. **Price is resolved server-side and never accepted from the client.** |
| `AddDieSlot` | *(none)* | `ok, slots?, reason?` | Cap is `5`, or `7` with the +2 Dice Slots gamepass, verified against server-held entitlements. |
| `Ascend` | *(none)* | `ok, diamondsGained?, reason?` | Minimum lifetime-earnings threshold enforced server-side (SRS FR-9.5). |
| `BuyDiamondNode` | `nodeId: string` | `ok, reason?` | `nodeId` allowlisted; Diamond cost server-resolved. Includes the Streak Strength tree. |
| `SetAutoRoll` | `enabled: boolean` | `ok, reason?` | Strict boolean. The **interval** is server-owned and is never a parameter. |
| `ClaimVault` | `doubled: boolean` | `ok, amount?, reason?` | `doubled=true` requires a validated receipt bound to this accrual id (threat T-24). Claim consumes the vault atomically. |
| `ClaimQuest` | `questId: string` | `ok, reward?, reason?` | Completion verified against server-tracked progress, never client assertion. |
| `ClaimChest` | `tierId: string` | `ok, reward?, reason?` | Server-clocked session time only. |
| `DailySpin` | *(none)* | `ok, outcomeId?, reason?` | Outcome drawn from a server-held weighted table. 24h cooldown on `os.time()`. |
| `RedeemCode` | `code: string` | `ok, reason` | Length ≤ 32, allowlist match. **Never echoes the submitted string** (threat T-21). Reasons limited to `valid` / `invalid` / `already`. |
| `ClaimGroupReward` | *(none)* | `ok, reason?` | Membership verified server-side via the Players/Groups API, re-verified each join. |
| `GetLeaderboard` | `boardId: string` | `entries, myRank` | `boardId` allowlisted. Reads the server cache; **never triggers a fetch** (threat T-22). |

### 1.2 Outbound — RemoteEvent (server → client, display only)

| Event | Payload | Notes |
|---|---|---|
| `RollResult` | `{ faces: {number}, payout: number, streak: number, multiplier: number, elementsFired: {string}, voidHit: boolean }` | `faces` drives the animation target. Arrives **after** Cash is already credited. |
| `StateSync` | `{ cash, gems, diamonds, dice, upgrades, streak, boosts, serverTime }` | Authoritative snapshot. Sent on join and after any state change. |
| `ForgeResult` | `{ dieIndex, distribution, cost, ok, reason? }` | Confirms or rejects; client re-renders from this, never from its own optimism. |
| `VaultSummary` | `{ accrued, wouldHaveAccruedAtPeak, capacity, efficiency }` | The peak comparison is deliberate — it teaches that leaving well-tuned pays more (SRS FR-8.5). |
| `EventState` | `{ likeGoalProgress, likeGoalTarget, eventActive, eventEndsAt }` | **Per server instance in V1** — MessagingService is out of scope (risk R-8). |
| `Notice` | `{ severity: string, code: string }` | Enumerated codes only. **No stack traces, paths, or internal values** (threat T-7, Matrix E-8). |

---

## 2. VALIDATION CONTRACT

Every inbound handler runs, in this order: **rate limit → arity → type → finiteness → bounds → allowlist → affordability**. A failure at any step rejects the call, **mutates nothing**, logs server-side with the `UserId`, and returns a generic reason.

### 2.1 The forge proposal — the highest-risk validator in the game

`Forge(dieIndex, distribution)` is accepted only if **all** hold:

1. `dieIndex` is an integer within the player's owned slot count.
2. `distribution` is an array whose length **exactly equals** the die's face count.
3. Every element is a `number` and **explicitly finite** — checked with `n == n` (rejects `NaN`) plus finite upper/lower bounds (rejects `math.huge`, `-math.huge`).
4. Every element is `>= MASS_FLOOR` for that shape.
5. `|sum(distribution) − serverHeldBudget| <= EPSILON`.
6. The player can afford the forge cost, which is computed **server-side** from the magnitude of mass moved (SRS FR-3.3).

**Step 3 must precede step 5.** `NaN` fails every comparison, so a sum check alone passes when `NaN` is present and the budget invariant breaks silently — this is threat **T-25** and it is the reason ordering is specified rather than left to the implementer.

### 2.2 Rate limits (per player, token bucket)

| Remote | Sustained | Burst |
|---|---|---|
| `Roll` | server-known auto-roll tier, max 5/s | 10 |
| `Forge`, `SetElement`, `SetShape` | 4/s | 8 |
| `BuyUpgrade`, `BuyDiamondNode`, `AddDieSlot` | 4/s | 8 |
| `GetLeaderboard` | 0.5/s | 2 |
| `RedeemCode` | 0.2/s | 3 |
| all others | 2/s | 5 |

Over-budget requests are dropped and counted. Sustained abuse is logged. **Never auto-kick** — lag produces false positives (threat T-4).

---

## 3. THE PROFILE BLUEPRINT (ProfileStore)

One ProfileStore *store object* keyed `Profile_{UserId}` (the library type, not our `PlayerProfile` wrapper). This table is the **complete** default template: every field has a default, so no load path can dereference `nil` (threat T-12). ProfileStore reconciles missing keys on load; the migration chain handles shape changes it cannot.

```lua
local PROFILE_TEMPLATE = {
    SchemaVersion = 1,

    -- currencies (EconomyService is the ONLY writer)
    Cash            = 0,
    Gems            = 0,
    Diamonds        = 0,

    -- lifetime stats, also the leaderboard sources
    LifetimeCash    = 0,      -- Top Net Worth
    HighestRoll     = 0,      -- Highest Single Roll
    Ascensions      = 0,      -- Max Prestiges
    TotalRolls      = 0,

    -- dice: array of owned dice, index = slot
    Dice = {
        [1] = {
            Shape      = "D6",          -- D4 | D6 | D8 | D12 | D20
            MassBudget = 60,            -- server-held; the forge sum must equal this
            Faces = {
                -- one entry per face; Mass sums to MassBudget
                { Mass = 10, Element = "None" },
                { Mass = 10, Element = "None" },
                { Mass = 10, Element = "None" },
                { Mass = 10, Element = "None" },
                { Mass = 10, Element = "None" },
                { Mass = 10, Element = "None" },
            },
        },
    },
    DieSlots = 1,

    -- permanent trees (survive ascension)
    Diamond = {
        StreakStrength = 0,   -- b in (1+b)^streak - the build-defining axis (SRS FR-5.4)
        MassCeiling    = 0,
        SlotNodes      = 0,
        Elements       = { None = true },   -- unlocked element allowlist
        Shapes         = { D6 = true },     -- unlocked shape allowlist
    },

    -- cash upgrades (reset on ascension)
    Upgrades = { AutoRollSpeed = 0, VaultCapacity = 0, VaultEfficiency = 0, Luck = 0 },

    -- offline vault
    Vault = {
        LastSeen        = 0,   -- os.time() at release; server-written only
        AccrualId       = 0,   -- increments each claim; binds the 2x receipt (threat T-24)
        AvgIncomePerSec = 0,   -- rolling average from active play
    },

    -- monetization
    PurchaseIds   = {},   -- BOUNDED: 200 most recent, insertion-ordered (threat T-13)
    PurchaseOrder = {},   -- eviction order for the above
    BundleOffered = false,-- Starter Bundle is ONCE-ONLY; true forever after (SRS FR-12.5)

    -- progression
    CodesRedeemed = {},   -- bounded by the server-held catalog
    Quests        = { Slots = {}, RolledOn = 0 },
    LoginStreak   = { Count = 0, LastDay = 0, ForgivenessLeft = 1 },
    LastSpin      = 0,
    GroupClaimed  = false,

    Settings = { Particles = true, MotionBlur = true, Music = true, SFX = true },
}
```

### 3.1 Invariants enforced on every write
1. `sum(Dice[i].Faces[*].Mass) == Dice[i].MassBudget` within epsilon, for every die. This is the security boundary of the forge, not just a design rule (threat T-4).
2. `Cash`, `Gems`, `Diamonds` are finite and `>= 0`. Every mutation is checked, never assumed.
3. `PurchaseIds` never exceeds 200 entries; `PurchaseOrder` drives eviction.
4. `Vault.LastSeen` is server-written only and never populated from a client message (threat T-23).
5. `BundleOffered` is **write-once true**. No code path may reset it — that would manufacture urgency, which is prohibited (SRS FR-12.5).
6. The serialised profile is asserted under the payload ceiling **before** every save; an oversized write is refused and logged (threat T-13).

### 3.2 Lifecycle
`LoadProfileAsync` → on failure or foreign lock, **fail closed** (kick with an honest message; never serve a default) → `Reconcile()` → run migration chain if `SchemaVersion` is behind → bind `ListenToRelease` to kick and clear in-memory state → hold in memory for the session → release on leave and on `BindToClose()`. **A released profile is immutable**; every write path checks `profile:IsActive()` first and drops the write if not (HLD §5.2).

---

## 4. LEADERBOARD CONTRACT

Three `OrderedDataStore`s: `LB_NetWorth`, `LB_HighestRoll`, `LB_Prestiges`.

**Values must be bounded, log-scaled, monotonic integers** — raw currency overflows the signed 64-bit range in an idle economy (threat T-20):

```
key   = tostring(UserId)
value = math.clamp(math.floor(math.log10(math.max(raw, 1)) * 1e6), 0, 9e15)
```

Monotonic, so ordering is preserved exactly. Bounded, so overflow is impossible by construction — **verified against `raw = 1e300`** in the test plan. Display values come from the profile, not from the decoded key.

**Writes:** on player exit and on the periodic auto-save. **Reads:** one `GetSortedAsync` per server per interval, cached and shared by all players on that server. Display names come from the `Players` service, never from a client message (threat T-21).

---

## 5. UNKNOWNS
- **U-1 — Robux asset ids do not exist.** The product catalog ships empty; every product **fails closed** (threat T-19). Adding real ids later is a one-line change per product.
- **U-2 — Balance constants untuned.** The simulations established structure (α=2.0, `P ∝ (M−m)`, streak cliff near `b≈0.15`, mass-coupled elements), not shipping values. Tuning happens in construction against telemetry.
