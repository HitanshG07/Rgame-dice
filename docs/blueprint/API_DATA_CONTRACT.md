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
| `AddDieSlot` | `shapeId: string` | `ok, slots?, reason?` | Buys one more die. `shapeId` names its shape and **must be one the player already owns**; the **empty string** means the starting shape. Cap is `3 + ascensions`, hard maximum `7`, verified server-side. |
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
| `StateSync` | `{ cash, gems, diamonds, dice, upgrades, diamondTree, settings, streak, boosts, serverTime }` | Authoritative snapshot. Sent on join and after any state change. **`dice` carries the full per-die record including `PurchasedBudget`** (schema v2). **`diamondTree` carries `Elements` and `Shapes`** — the unlocked sets, without which the forge cannot honestly show what is available and defaults to showing everything locked. **`settings`** carries the FR-13.6 particle/motion-blur/audio toggles. |
| `ForgeResult` | `{ dieIndex, distribution, cost, ok, reason? }` | Confirms or rejects; client re-renders from this, never from its own optimism. |
| `VaultSummary` | `{ accrued, wouldHaveAccruedAtPeak, capacity, efficiency }` | The peak comparison is deliberate — it teaches that leaving well-tuned pays more (SRS FR-8.5). |
| `EventState` | `{ likeGoalProgress, likeGoalTarget, eventActive, eventEndsAt }` | **Per server instance in V1** — MessagingService is out of scope (risk R-8). |
| `Notice` | `{ severity: string, code: string }` | Enumerated codes only. **No stack traces, paths, or internal values** (threat T-7, Matrix E-8). |


**Amended 2026-08-07 — `StateSync` gains `diamondTree` and `settings`.** Triggering fact: **three swarm workers in isolated contexts independently reported that `StateSync` was specified here and emitted by nothing.** Each hit a different consequence — `DiceRenderer` could not learn shape or mass so every die rendered as a uniform dim D6 (FR-1.3 unverifiable); `HUD` showed Cash and Gems as `--` for want of any balance source; `ForgePanel` showed every element locked. Two further audits then found `FeedbackFX` reading toggles from a field the payload never declared, leaving FR-13.6 unmet end to end.

The convergence is the point: a contract row that no code implements reads exactly like one that does, and it stayed invisible through five audit rounds on the server because every one of those rounds audited what the server DID rather than what the contract PROMISED. **A specified-but-unimplemented event is a defect in the contract, not merely an absence in the code.**

---

## 2. VALIDATION CONTRACT

Every inbound handler runs, in this order: **rate limit → arity → type → finiteness → bounds → allowlist → affordability**. A failure at any step rejects the call, **mutates nothing**, logs server-side with the `UserId`, and returns a generic reason.

### 2.1 The forge proposal — the highest-risk validator in the game

`Forge(dieIndex, distribution)` is accepted only if **all** hold:

1. `dieIndex` is an integer within the player's owned slot count.
2. `distribution` is an array whose length **exactly equals** the die's face count.
3. Every element is a `number` and **explicitly finite** — checked with `n == n` (rejects `NaN`) plus finite upper/lower bounds (rejects `math.huge`, `-math.huge`).
4. Every element is `>= MASS_FLOOR` for that shape.
5. Every element is **snapped to a fixed decimal precision (4 dp)**, then `|sum(distribution) − serverHeldBudget| <= EPSILON`. Snapping precedes summation so IEEE 754 residuals cannot compound across repeated forges (threat T-27).
6. The player can afford the forge cost, which is computed **server-side** from the magnitude of mass moved (SRS FR-3.3).

**Step 3 must precede step 5.** `NaN` fails every comparison, so a sum check alone passes when `NaN` is present and the budget invariant breaks silently — this is threat **T-25** and it is the reason ordering is specified rather than left to the implementer.

### 2.2 Rate limits (per player, token bucket)

| Remote | Sustained | Burst |
|---|---|---|
| `Roll` (manual, via the remote) | 1/s | 3 |
| `Roll` (server-driven auto-roll) | server-known auto-roll tier, best 1.6/s | n/a |
| `Forge`, `SetElement`, `SetShape` | 4/s | 8 |
| `BuyUpgrade`, `BuyDiamondNode`, `AddDieSlot` | 4/s | 8 |
| `GetLeaderboard` | 0.5/s | 2 |
| `RedeemCode` | 0.2/s | 3 |
| all others | 2/s | 5 |

**Amended 2026-08-13 — `AddDieSlot` takes a shape.** It was zero-arity and always
created the starting shape. SHAPE can now sell another die of a shape the player
already owns (operator: *"in shape we need to add options to buy multiple of the
same dice - this helps progression"*), which is the same transaction with a
different starting shape — so it shares the slot price curve and the ascension
cap rather than getting a parallel set that could drift. The **empty string** is
the sentinel for "starting shape" rather than `nil`, because §2's arity check is
deliberately EXACT and loosening it to a maximum for one optional argument would
weaken that check for every remote. Ownership is unchanged: `Diamond.Shapes`
remains a boolean set, and a repeat purchase buys a **die**, not a count.

**Amended 2026-08-13 — manual rolling is slower than auto-roll.** The `Roll`
bucket was a flat 5/s, identical to the FR-2.4 auto-roll ceiling. Two
consequences, both reported from play: holding the button spammed the server as
fast as the input could fire, and the Auto-Roll **gamepass bought nothing** —
a paying player got the same rate as someone tapping. Manual invocation is now
capped at **1/s** (5 rolls per 5 seconds, operator-set) against auto-roll's best
of **1.6/s** (8 per 5 seconds), so auto-roll retains a real advantage.
`RollService.AUTO_FLOOR` was lowered to `0.625` in the same change: it had been
`1.0`, which after the manual retune would have left the two IDENTICAL and made
the gamepass worth nothing. UT-6 asserts the *relationship* rather than the
literals, so a future retune of either cannot silently close the gap. The auto-roll loop is
server-driven and does not pass through the remote, so its own ceiling is
unchanged. The client shows a cooldown sweep on the ROLL button; that is
**presentation only** and an exploiter's client will not run it — the bucket
above is the enforcement.

Over-budget requests are dropped and counted. Sustained abuse is logged. **Never auto-kick** — lag produces false positives (threat T-4).

---

## 3. THE PROFILE BLUEPRINT (ProfileStore)

One ProfileStore *store object* keyed `Profile_{UserId}` (the library type, not our `PlayerProfile` wrapper). This table is the **complete** default template: every field has a default, so no load path can dereference `nil` (threat T-12). ProfileStore reconciles missing keys on load; the migration chain handles shape changes it cannot.

**Amended 2026-08-07 — schema v2.** `PurchasedBudget` was split out of `MassBudget` (Block 3 Gate 3 finding F-AD-1). `PurchasedBudget` is what the player OWNS and is shape-independent; `MassBudget` is what the current shape may USE, derived as `clamp(PurchasedBudget, faceCount * massFloor, shape.diamondCeiling)`. They are separate because a shape change must be freely reversible (FR-6.1) without being a way to gain budget: a narrower shape caps what is usable, and returning to a wider one restores it, but neither ever mints more. The v1 -> v2 migration seeds `PurchasedBudget` from `MassBudget`, which is lossless because a v1 die's budget IS what was paid for.

**The die contract is executable, not prose.** `ForgeService.assertDieInvariant(die, shape)` is the single definition of a valid die -- seven clauses covering argument shape, face count, entitlement bounds, usable-budget bounds, per-face floor and element validity, and zero-sum. Every mutating handler checks a CANDIDATE against it before persisting, `ForgeService.validateStoredDice` checks and repairs on join, and UT-12 checks the stored die after every mutation. **A new rule about dice is added to that function, never restated inline.** This exists because the rules previously lived as prose spread across FR-3.6, FR-6.1 and comments, and `performSetShape` was consequently wrong three times in three different directions.

```lua
local PROFILE_TEMPLATE = {
    SchemaVersion = 2,   -- v2 (2026-08-07): PurchasedBudget split out of MassBudget

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
            Shape           = "D6",     -- D4 | D6 | D8 | D12 | D20
            MassBudget      = 60,       -- USABLE now; the forge sum must equal this
            PurchasedBudget = 60,       -- OWNED; shape-independent (FR-3.6)
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

**`raw` must be asserted finite (`raw == raw`, plus finite bounds) BEFORE the transform.** `NaN` propagates through `math.max`, `math.log10`, `math.floor` and `math.clamp` untouched, and `SetAsync` then throws, permanently breaking publication for that player. A non-finite value is refused, logged, and the previous published value retained (threat T-28). *(Amended 2026-08-04, triggering fact: Gate 4 audit TM-5.4 — the identical hazard was closed for the forge validator at T-25 and left open here.)*

Monotonic, so ordering is preserved exactly. Bounded, so overflow is impossible by construction — **verified against `raw = 1e300`** in the test plan. Display values come from the profile, not from the decoded key.

**Writes:** on player exit and on the periodic auto-save. **Reads:** one `GetSortedAsync` per server per interval, cached and shared by all players on that server. Display names come from the `Players` service, never from a client message (threat T-21).

---

## 5. UNKNOWNS
- **U-1 — Robux asset ids do not exist.** The product catalog ships empty; every product **fails closed** (threat T-19). Adding real ids later is a one-line change per product.
- **U-2 — Balance constants untuned.** The simulations established structure (α=2.0, `P ∝ (M−m)`, streak cliff near `b≈0.15`, mass-coupled elements), not shipping values. Tuning happens in construction against telemetry.
