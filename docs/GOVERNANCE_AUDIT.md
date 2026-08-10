CONSUMED-BY: Operator / project governance
STATUS: LIVING — amend on every audit pass

# DICE FORGE — GOVERNANCE AUDIT
## Everything built right, half-right, and wrong

**Audit date:** 2026-08-11
**Head at audit:** `327826f` (+ V7HUD formatting fix)
**Method:** every requirement checked against running code. Nothing in this
document is taken from a prior report. Where a claim is marked VERIFIED, it was
measured on the live game or proven by a suite that runs on every pass.

---

## 0. THE HEADLINE

**19 test suites, 3,457 assertions, 0 failing.** The game is playable end to end:
roll → server samples → payout → 3D die tumbles to the credited face → balances
update. The core mechanic has been observed working.

**This audit found 11 defects, 4 of them serious enough to cost a player money
or make a purchase worthless.** All 11 are fixed. Three items remain open and
every one of them is listed in §5 with what it needs.

The single most important finding is §2.1 — **the game's central balance
requirement was violated outright**, and no test could have caught it because no
test existed for it. One does now.

---

## 1. WHAT WAS BUILT RIGHT

Recorded because an audit that lists only faults gives a false picture of the
work. These were checked, not assumed.

| Area | Status | Evidence |
|---|---|---|
| **Server authority** | Correct | Client sends intent with no payload; server samples, credits, then emits. No client value participates in any outcome. |
| **Inverted-mass mechanic (FR-2.3)** | Correct, and observed | Operator confirmed by hand: max mass on face 6, it never lands. |
| **Payout superlinearity (FR-2.4)** | Correct | α = 2.0; UT-4, 77 assertions. |
| **Zero-sum forging (FR-3.1/3.2)** | Correct | `assertDieInvariant` is one executable contract, gated on every write *and* every read, with load-path repair. |
| **Persistence (FR-14.x)** | Correct | ProfileStore behind one wrapper; session locking; fail-closed load; synchronous active-check; deep copy; recursive reconcile. |
| **Receipt handling (FR-12.3/12.4)** | Correct | Exactly one `ProcessReceipt` (T-17, grep-verified). `PurchaseGranted` only after a confirmed disk write. Idempotent replays. |
| **Rate limiting** | Correct | Per-player, per-remote token buckets; UT-6, 56 assertions. |
| **Leaderboard overflow (FR-11.4)** | Correct | Log-scaled monotonic integer transform; raw values would overflow int64 in an idle economy. |
| **Offline vault (FR-8.x)** | Correct | Server-clocked, capacity tiers 4h/12h/24h, negative-elapsed clamped and logged. |
| **Streak shield cooldown (FR-5.6)** | Correct | 30 s, server-clocked. |
| **Dice geometry** | Correct | All five catalog shapes render as true solids, verified visually off-axis. |
| **NFR-5 (no figures on the wire)** | Correct | Client outbound is one module, two call sites. |

---

## 2. WHAT WAS WRONG

### 2.1 — CRITICAL: the balance requirement at the centre of the game was violated

**FR-6.3:** *"No shape dominates at all Streak Strength values… A build where one
shape wins at every `b` is a balance defect."*

**Measured result before the fix — the D20 won at all eight values of `b`:**

```
b     best  bestEV        voidP   runner-up
0.00  D20   476.0         0.052   D12
0.05  D20   1,476.3       0.052   D12
0.15  D20   55,191.8      0.052   D12
0.50  D20   85,551,031.8  0.052   D12
DISTINCT WINNERS: 1
```

**Cause — structural, not a tuning slip.** `defaultBudget` scaled with face count
(D2 = 20 … D20 = 200, a tidy 10 per face). Payout is superlinear in mass, so more
budget is *strictly* better: the D20 simply had ten times the mass of the D2 and
face count stopped mattering at all. Every row looked reasonable in isolation,
which is exactly why five audit rounds never saw it.

**Fix:** the mass budget is now shape-independent. Shapes differ only in how many
faces the same 60 mass is spread across.

```
b <= 0.05   D3 wins    Void 0.492   the volatile sniper
b >= 0.10   D20 wins   Void 0.052   the steady grinder
DISTINCT WINNERS: 2 — the crossover exists
```

The measured Void range 0.49 → 0.05 brackets the SRS's predicted 0.33 → 0.05.

**Guarded:** `UT-14 Balance` runs the sweep on every test pass, against the
shipping catalog rather than a fixture. It also asserts the *cause* directly
(budget uniform across shapes), so a future failure reports why.

### 2.2 — SERIOUS: a money defect that would short-change paying players

`PurchaseService.applyGrant`, TimeSkip branch:

```lua
local payout = seconds * rate
if payout <= 0 then
    payout = 1000 -- baseline floor so time skip never credits zero
end
```

`rate` is `Vault.AvgIncomePerSec`, **zero until a player has earned anything**,
and `getStatus` returns nil outright with no profile. Both fell through to a flat
1,000 — then returned `PurchaseGranted`, which tells Roblox to keep the money and
stop retrying. A player earning 50k/sec buys "24 hours of offline earnings" and
receives 1,000, irreversibly.

**Fix:** no fallback figure. When the rate cannot be established the grant
returns false → `NotProcessedYet` → the receipt stays alive and the platform's
own retry grants correctly once the player has played.

**The general rule:** a fallback constant in a grant path is never a safety net.
It is a wrong answer delivered confidently.

### 2.3 — SERIOUS: four handlers reported success without doing anything

```lua
RemoteGateway.register("ClaimQuest", announcing(function(player, questId)
    return true, nil      -- granted nothing
end))
RemoteGateway.register("ClaimChest", announcing(function(player, tierId)
    return true, nil      -- granted nothing
end))
```

Worse than missing. `announcing` then pushed a snapshot of unchanged state, so
the client showed a claimed quest and the player received nothing — **the game
told them their reward had been taken.**

`SetAutoRoll` validated the boolean, checked pass ownership, then **discarded the
value**. The toggle was inert; the server never rolled for anyone. FR-7.1/7.2/7.3
had no implementation at all while the Auto-Roll gamepass was sellable against it.

`claimGroupReward` carried the comment `-- Verified server-side` above code that
verified **nothing**. `GroupService` was required at the top of the file and never
called. Any player could claim 250 Gems + 15 Diamonds by invoking the remote once.

**All four now do what their names claim.** Group membership is really checked,
with an unset group id failing closed.

### 2.4 — SERIOUS: shapes could never be unlocked

`SetShape` has always checked `data.Diamond.Shapes[shapeId]`. **Nothing anywhere
ever set it true** beyond the one shape in the profile template.
`BuyDiamondNode` only increments numeric levels — pointing it at `Shapes` would
have written `Shapes = 1` and destroyed the table.

Every shape past the starting one was permanently unreachable. FR-9.3 specified
it, the *read* was implemented, the *write* was absent. **Ledger L-027 again**,
and it survived every audit because a missing write has nothing to read.

### 2.5 — Boosts were invisible to the player

`StateSync` carried `boosts = {}` hardcoded, with the comment *"Block 5 populates
this."* Block 5 built `BoostService` and never came back. A purchased boost ticked
down server-side while the client was told there were none.

### 2.6 — The Starter Bundle timer did not exist

`BundleOffered` sat in the schema with a default, read and written by nothing.
FR-12.5 requires a genuinely once-only offer.

**Now:** `BundleExpiry` is stamped once at first admission and never rewritten;
purchase latches `BundleOffered`. **No code path anywhere extends, resets, or
reopens it** — verified by grep. If that ever needs changing, changing it is the
violation.

### 2.7 — Scientific notation shown to players

`V7HUD` rendered `string.format("$%.2e", cash)` → **`$2.06e+04`**. `Format.luau`
existed the whole time, precision-safe to 1e300; the module simply never required
it. Now `$20.58K`.

### 2.8 — Three retention systems were schema-only

`Quests`, `LoginStreak` and playtime chests all had profile fields with defaults
and **no implementation**. Built: deterministic daily quests (same three per
player per UTC day, so a rejoin cannot reroll for an easier set), a login streak
with exactly one non-renewing forgiveness token, and server-clocked chests.

### 2.9 — The quest trap I nearly walked into myself

Having just built the quest system, **nothing called `advanceQuests`**. Quests
would have rolled daily, displayed correctly, and never moved — L-027 committed
by the person who wrote the ledger entry.

Wired through *observers* rather than requires: `RollService` and `ForgeService`
expose hooks the composition root fills, so neither knows `ProgressionService`
exists. Avoids the module cycle L-035 records, and reflects the real relationship
— quests observe play; play does not serve quests.

### 2.10 — Tests coupled to a product decision

Three suites hardcoded a D6 starting die and broke when it became a D2. Two now
declare an explicit D6 **fixture** (they test forge maths and should own the shape
they test); IT-2's loop reads `#initialDie.Faces` instead of a literal 6. Two
deep-copy sentinels hardcoded the template's face mass and now read it from the
template.

**None were weakened.** UT-7 gained five assertions proving the ladder is closed
at the bottom and every rung reachable.

### 2.11 — Ledger ID collision

Antigravity appended an entry reusing `L-029`, violating Ledger Law 4. Renumbered
to `L-030` and **amended rather than rewritten**: its stated fix described the
first build, which shipped the star-geometry defect, and its Gate 3 evidence was
*"8 models verified present"* — a count, which cannot see a shape.

---

## 3. THE DESIGN CHANGE: D2 START WITH A PROGRESSION LADDER

**Operator-directed 2026-08-11.** A new player starts on the D2 and works up:

```
D2 → D3 → D4 → D6 → D8 → D10 → D12 → D20
0     5    15   40   90   180   320   600   (Diamonds)
```

Each rung requires the one below it. Verified live: D20 refused with
`prerequisite_locked`, D3 allowed, D2 `already_owned`, bogus id `unknown_shape`.

**This conflicts with FR-6.1 on its face** — *"shapes are a build choice, never a
tier ladder"* — and the reconciliation is load-bearing:

- **The unlock is a ladder.** Ordered progression, which gives a new player one
  comprehensible goal instead of eight options they cannot evaluate.
- **The choice stays free.** Once owned, a shape is never taken away, and
  switching among owned shapes is free and reversible. A player who owns the D20
  may roll a D2 forever — and below `b = 0.10` that is *correct play*.

**The honest caveat, recorded in the code:** a ladder implies "later is better",
and §2.1's sweep shows that is **false** for this game. **The UI must present
later shapes as *different*, not *stronger*,** or the ladder will teach players a
wrong model of their own build. This is a design obligation, not a code one.

---

## 4. MONETISATION — FULL LEDGER

All 14 items have real asset IDs. Every entitlement now has a caller.

| Item | Type | ID | Effect wired to |
|---|---|---|---|
| Auto-Roll | Pass | 1941930874 | `RollService.stepAutoRoll`, re-checked every tick |
| 2x Cash | Pass | 1941816910 | `EconomyService` credit path |
| +2 Die Slots | Pass | 1942770917 | `StateSyncService`, clamped to 7 |
| VIP Forge | Pass | 1941768890 | `ForgeService.computeForgeCost` |
| Bad Roll Shield | Pass | 1941036910 | `RollService`, 30 s cooldown |
| VIP Vault | Pass | 1940358891 | `OfflineService` capacity |
| Ultra Auto-Roll | Pass | 1940634905 | `RollService.autoInterval` floor |
| Small Gem Pack | Product | 3655134862 | Currency grant |
| Large Gem Pack | Product | 3655091493 | Currency grant |
| Diamond Cache | Product | 3655106265 | Currency grant |
| Starter Bundle | Product | 3654933328 | Bundle + die slot + closes offer |
| 2x Luck Boost | Product | 3655545836 | `BoostService`, timed |
| 2x Offline Payout | Product | 3655618937 | `BoostService`, timed |
| Time Skip 24h | Product | 3655695933 | Real rate × 24 h, **no fallback** |

**Design integrity (FR-12.7):** no purchase grants an economic capability
unreachable through play. VIP Forge reduces re-forge *cost* and never adds mass —
forging stays zero-sum.

---

## 5. WHAT IS STILL OPEN

Stated plainly rather than buried. Nothing here is blocking play; all of it is
blocking "finished".

| # | Item | Why it is open | What it needs |
|---|---|---|---|
| **1** | **`GROUP_ID = 0`** | Fails closed — nobody can claim the group reward | **Operator:** supply the real Roblox group id |
| **2** | **Audio is `DUMMY_ID_*`** | 9 sound cues have no assets | **Operator:** upload sounds, supply ids |
| **3** | **FR-10.7 Like Goal** | No server implementation. Must show the *real* platform like count or nothing — fabricated activity is prohibited | Build against `MarketplaceService` real counts |
| 4 | `src/Client/LegacyUI/` | Dead duplicate of every pre-V7 client module | Delete once V7 is confirmed stable |
| 5 | Balance *tuning* | UT-14 proves a crossover EXISTS, not that it sits at a good `b` | Operator judgement + playtesting |
| 6 | Shape ladder costs | 5→600 Diamonds is a first pass, unvalidated against real earn rates | Playtest |

---

## 6. THE RULES THIS AUDIT PAID FOR

Each is now a ledger entry with a real defect behind it.

1. **A fallback constant in a grant path is a wrong answer delivered
   confidently.** (§2.2)
2. **A handler that reports success it did not deliver is worse than a missing
   one.** (§2.3)
3. **A comment asserting a control that does not exist is the most dangerous
   line in a codebase.** (§2.3 — `-- Verified server-side`)
4. **A specified row with a READ but no WRITE is invisible to every audit,**
   because a missing write has nothing to read. (§2.4, L-027 — third occurrence)
5. **A balance requirement is a property of the numbers, and no code test can
   see it.** It needs its own sweep, run every time. (§2.1)
6. **Verify by running it.** Every defect above passed static analysis. (L-031)

---

## 7. VERDICT

**The game is mechanically sound and honestly built.** The core loop, the
economy, persistence, and monetisation are correct and now genuinely tested.

**Before publish, three things need you** — the group id, the audio ids, and a
decision on the Like Goal. Everything else on the open list is polish or
judgement.

The thing I would not skip: **play it for an hour at the new D2 start.** The
balance sweep proves a crossover exists mathematically; it cannot tell you
whether climbing the ladder *feels* like progress. That is the one question no
test in this repository can answer.
