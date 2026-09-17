# CRITICAL BUG FIX PLAN — Dice Forge Incremental

**Written:** 2026-09-17 · **Against HEAD `0d0110a`** · Branch `finalized-ui-revamp-whole-repo`

Every defect from the 2026-08-27 sweep, with **where it stands** and **the actual
fix**. The register in `docs/ROADMAP.md` §12 says *what is wrong*; this document
says *what to type*.

**Nothing here is applied.** One item (`OFF-1`) was fixed during the sweep and is
kept for the lesson.

---

## HOW TO USE THIS

Each entry carries the same six fields. **Read `THE FIX` and `WHY THIS AND NOT
THAT` together** — several of these have an obvious wrong fix that a later audit
would reject.

| Field | Means |
|---|---|
| **Stands** | Verified how, and by whom |
| **Costs** | What a player actually loses |
| **Root cause** | The one sentence that explains it |
| **The fix** | Concrete code |
| **Pin it** | The test that must fail before the fix and pass after |
| **Prove it** | How to confirm in a running game |

### Status legend

| | |
|---|---|
| **FIXED** | Landed and verified |
| **READY** | Fix is written below, verified against live code, not applied |
| **NEEDS A DECISION** | Operator must choose before code can be written |
| **NEEDS DESIGN** | Bigger than a patch |

### The rule that governs all of it

Every fix walks `.brain/PIPELINE.md`. **The author never audits their own work.**
Two of the defects below (`OFF-1`, `SLOT-2`) were introduced *by fixes made
earlier the same day* — which is the entire argument for the gate.

---

## FIX ORDER

Ordered by what a player loses, and by dependency. **Do not reorder casually:**
batch 1 is first because `FORGE-1` is actively *hiding* `FORGE-2`, and batch 6
must land before any Phase 2 work or it turns into data loss.

| Batch | What | Items | Rough size |
|---|---|---|---|
| **1** | The forge lies and cannot be used on two shapes | `FORGE-1`, `FORGE-2` | 2 lines |
| **2** | Real money is being destroyed | `ASC-1`, `PASS-1`, `SLOT-2` | Small |
| **3** | Permanent, unrecoverable player loss | `ASC-2`, `LOGIN-1`, `NAN-1` | Small–medium |
| **4** | Whole features are inert | `BOARD-1`, `LUCK-1`, `SHAPE-1`, `QUEST-1` | Medium |
| **5** | Numbers on screen are simply wrong | `RISK-1`, `MULT-1`, `CONST-1` | Small |
| **6** | Safety nets — **before Phase 2** | `CURR-1`, `DIE-1`, `SAVE-1`, `VAULT-1`, `RECON-1`, `FANOUT-1` | Medium–large |
| **7** | Everything else | See §7 | Varies |

**Batch 1 alone is two lines and removes the worst defect in the game.**

---

# BATCH 1 — THE FORGE

The forge is the core screen. Both defects are on it, and they compound: the
first makes the second invisible.

## FORGE-1 — The forge reports success on every refusal

| | |
|---|---|
| **Severity** | **CRITICAL** |
| **Status** | **FIXED** |
| **Stands** | CONFIRMED. Client sweep; I re-read both sites myself |
| **Where** | `src/Client/V7ForgePanel.luau:1325` and `:1239` |
| **Costs** | A false economic receipt on the game's core screen |

**Root cause.** `NetClient.forge` returns a **single `Result` table**
(`{ok=..., reason=...}`), not `(ok, reason)`. The panel destructures it as a
tuple, so `ok` is the table — always truthy — and `reason` is always `nil`. **The
success branch is unconditional.**

A player who cannot afford the forge, is throttled, or submits a distribution the
server rejects watches the button turn green and read **"CALIBRATED"**, and
`dirty` is cleared. They believe they paid and reforged.

### The fix

`:1325` —

```lua
-- BEFORE
local ok, reason = NetClient.forge(activeDie, out)
if ok then

-- AFTER
local result = NetClient.forge(activeDie, out)
if result.ok then
```

…and `result.reason` in the `else` branch. Identical change at `:1239` for
`NetClient.buyUpgrade("MassBudget")`.

**Why this and not that.** Do not "fix" `NetClient.forge` to return a tuple —
**every other call site in the client already reads it correctly** as
`local result = ...; if result.ok` (`V7MenuPanel:1690, 3071, 4595`,
`V7VaultOverlay:671, 686`). Changing the wrapper would break five correct callers
to accommodate two wrong ones.

**Pin it.** `ClientContract.test.luau`: assert every `NetClient` wrapper returns
a **table with an `ok` field**, and that the field is a boolean. That is provable
from the loaded module and catches the whole class.

**Prove it.** Open the forge with insufficient Cash, submit, and confirm the
button reads the refusal reason in red instead of "CALIBRATED" in green.

---

## FORGE-2 — Forging is permanently impossible on D7 and D14

| | |
|---|---|
| **Severity** | **CRITICAL** |
| **Status** | **FIXED** |
| **Stands** | CONFIRMED. I measured every shape in a running game |
| **Where** | `src/Client/V7ForgePanel.luau:1311` |
| **Costs** | Two shapes cannot be forged at all, ever |

**Root cause.** `DiceCatalog.newDie` snaps the per-face share **down** to 3dp, so
the budget is not an integer for shapes that do not divide 60 evenly. The submit
path forces the total to `math.floor(budget + 0.5)` = exactly 60. The server
validates `|total − budget| <= EPSILON`.

Measured live:

| Shape | Stored budget | Client sends | Drift | vs EPSILON `0.001` |
|---|---|---|---|---|
| D7 | **59.997** | 60 | 0.0030 | **rejected** |
| D14 | **59.990** | 60 | 0.0100 | **rejected** |

All ten other shapes produce exactly 60 and are unaffected.

### The fix

One line. The client invented an integer constraint **the server never had** —
`ForgeMath.validate` snaps to 4dp and checks the sum; it does not require
integers.

```lua
-- BEFORE  (:1311)
local drift = math.floor(budget + 0.5) - sum

-- AFTER
-- Target the die's REAL budget, not a rounded one. `newDie` snaps the per-face
-- share down to 3dp, so D7 is 59.997 and D14 is 59.990 -- rounding the target to
-- 60 put both past the server's 0.001 epsilon and made those two shapes
-- permanently unforgeable. The server never required integers.
local drift = budget - sum
```

**Why this and not that.** The tempting fix is to change `newDie` so every budget
is exactly 60. **Do not start there:** existing saved D7/D14 dice keep their
59.997 budget, so the client would still be wrong for every current owner, and
you would need a migration. Fix the client first — it repairs old and new dice at
once. Normalising `newDie` is worth doing afterwards as cleanup, not as the fix.

**Pin it.** A test that walks **every shape** in the catalog, builds the
distribution the client would submit, and asserts `ForgeMath.validate` accepts
it. A test that only checks D6 passes today.

**Prove it.** Equip a D14, move mass, forge. The bars must persist across the
next snapshot rather than reverting.

---

# BATCH 2 — REAL MONEY

## ASC-1 — Ascension deletes Gems, which are bought with Robux

| | |
|---|---|
| **Severity** | **CRITICAL** |
| **Status** | **NEEDS A DECISION** (recommended fix below) |
| **Stands** | CONFIRMED. `AscensionService.luau:66` reads `d.Gems = 0` |
| **Costs** | Up to 650 Robux-bought Gems, silently, on a button press |

**Root cause.** FR-9.1 enumerates what ascension resets — *"Cash, face layouts,
mass budgets, and Cash-purchased upgrades"*. **Gems are not on that list**, and
FR-9.2 protects Diamonds without mentioning Gems because Gems were never meant to
reset. The line is an exception nobody audited, and the confirm screen FR-9.4
requires does not warn about it.

### The fix (recommended)

```lua
-- DELETE this line from the ascension mutate block (AscensionService.luau:66)
d.Gems = 0
```

Replace with a comment recording *why* it is absent, so it is not "restored" by a
later reader:

```lua
-- GEMS DELIBERATELY SURVIVE ASCENSION. They are sold for Robux
-- (MonetisationCatalog GemsSmall / GemsLarge / StarterBundle) and are NOT in
-- FR-9.1's reset list. Zeroing them here destroyed a real-money purchase on a
-- button press, with no warning on the FR-9.4 confirm screen.
```

**Why this needs your sign-off.** It is a one-line deletion but an **economy
change**: Gems are the vault-capacity sink, and letting them persist across
prestige makes that sink cheaper over a long account. The alternative — keep the
reset and *warn* on the confirm screen — is defensible but still destroys
something a player paid Robux for, which is the worse outcome. **Recommendation:
delete the line.**

**Pin it.** `Integration_Ascension.test.luau` currently asserts only
`Upgrades.AutoRollSpeed == 0`. Add: seed Gems, ascend, assert Gems **unchanged**.

---

## PASS-1 — The `+2 Die Slots` gamepass grants 4 slots

| | |
|---|---|
| **Severity** | **CRITICAL** |
| **Status** | **READY** |
| **Stands** | CONFIRMED. I traced both grant paths |
| **Where** | `src/Server/PurchaseService.luau:504-509` |
| **Costs** | 2 extra permanent slots + 4 free dice per buyer; each slot is otherwise worth up to $1.02M |

**Root cause.** The mid-session purchase path calls `grantDieSlots(…, 2, …)` but
**never writes `data.PassSlotsGranted`** — and `applyPassSlotGrant`, which runs on
*every* join, is idempotent only through that counter. Buy in-session → +2.
Rejoin → the join-time grant sees `already = 0`, computes a shortfall of 2, and
grants +2 again.

### The fix

`applyPassSlotGrant` at `:404-424` already demonstrates the correct pattern —
including the subtlety that the counter must be credited by what was **actually
granted**, not what was owed. Mirror it:

```lua
if entry.key == "DieSlots2" and entry.amount ~= nil then
    PlayerProfile.mutate(player, function(data)
        -- CREDIT THE COUNTER. Without this, `applyPassSlotGrant` runs on the
        -- next join, sees PassSlotsGranted = 0, and grants the same two slots
        -- a second time -- so a 2-slot pass delivered 4.
        local already = tonumber(data.PassSlotsGranted) or 0
        local gained = PlayerProfile.grantDieSlots(data, entry.amount :: number,
            DiceCatalog.MAX_DIE_SLOTS, DiceCatalog.newStartingDie)
        data.PassSlotsGranted = already + gained
    end)
end
```

**Why by `gained` and not by `entry.amount`.** A player already at the 12-slot
ceiling gains nothing; recording the full entitlement anyway would permanently
forfeit slots they could claim later if the ceiling rose. That reasoning is
already written at `:419-421` — this path just never applied it.

**Pin it.** Grant the pass mid-session, run `applyPassSlotGrant` twice, assert
`DieSlots` increased by exactly 2 in total.

**Migration note.** Players who already bought the pass are sitting on the extra
slots. **Do not confiscate** — that is the rule `AddDieSlot` follows. Let them
keep it and fix it forward.

---

## SLOT-2 — The SLOTS panel quotes a price the server refuses *(mine)*

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Stands** | CONFIRMED. **Introduced by my own commit `daac879`** |
| **Where** | `src/Server/ServerBootstrap.server.luau:546` |
| **Costs** | A Diamond node costing up to 3,200 Diamonds buys a slot the store then declines to sell |

**Root cause.** `daac879` threaded `slotNodes` through the client's
`dieSlotCost` call and **missed the server's own**. The client prices against
`dieSlotCapFor(ascensions, slotNodes)`; the server prices against
`dieSlotCapFor(ascensions, 0)` and returns `nil` → `InvalidRequest`.

### The fix

```lua
-- BEFORE
local cost = DiceCatalog.dieSlotCost(data.DieSlots, data.Ascensions)

-- AFTER
local cost = DiceCatalog.dieSlotCost(data.DieSlots, data.Ascensions, data.Diamond.SlotNodes)
```

**The lesson, recorded because it is the same shape as `OFF-1`.** Making a
parameter *optional* so existing call sites keep compiling is exactly what let
one of two call sites go unupdated. **When a shared function grows an argument
that changes its answer, grep every call site in the same commit** — the
compiler will not help, because optional means silent.

**Pin it.** Assert client and server price the *same* slot identically for a
player with `SlotNodes > 0`.

---

# BATCH 3 — PERMANENT PLAYER LOSS

## ASC-2 — Ascension permanently kills the Cash mass-budget path

| | |
|---|---|
| **Severity** | **CRITICAL** |
| **Status** | **READY** |
| **Stands** | CONFIRMED |
| **Where** | `src/Server/AscensionService.luau:76-79` vs `:114-119` |
| **Costs** | The entire Cash half of FR-3.6, dead for the life of the account, after one ascension |

**Root cause.** Ascension resets four upgrades — `AutoRollSpeed`,
`VaultCapacity`, `VaultEfficiency`, `Luck` — but **not `MassBudget`**, while
`:114-119` resets the dice to a fresh 60-budget die. `MassBudget` is applied
**only at the moment of purchase**, so the level survives with nothing to show
for it, and `BuyUpgrade("MassBudget")` then refuses forever at
`currentLvl >= maxLevel`.

### The fix

```lua
-- Reset Cash upgrades only
d.Upgrades.AutoRollSpeed = 0
d.Upgrades.VaultCapacity = 0
d.Upgrades.VaultEfficiency = 0
d.Upgrades.Luck = 0
-- MassBudget MUST reset with them. The dice are reset to a 60 budget at the
-- bottom of this function, and MassBudget is applied only at purchase time --
-- so leaving the level standing meant the player kept a maxed counter, lost the
-- mass it bought, and could never re-buy it. FR-9.1 resets "Cash-purchased
-- upgrades"; this is one.
d.Upgrades.MassBudget = 0
```

**Second-order defect, same root, fix alongside.** Every die created *after* the
upgrade is bought is permanently under-budgeted — `AddDieSlot`, `grantDieSlots`
and `newStartingDie` all produce a 60-budget die and nothing re-applies the
account's level. The comment at `ServerBootstrap:292-294` claims `MassBudget` is
*"an account-level entitlement… applied to EVERY die the player owns"*, which is
true only for dice that existed at purchase time. **Make it true:** apply the
stored level whenever a die is created.

**Also fix `J`.** `UpgradeCatalog.luau:27` claims *"Keys match
PlayerProfile.Upgrades table exactly"* — `MassBudget` is **missing** from the
profile template at `PlayerProfile.luau:150`. Harmless today (`or 0` everywhere),
but it is the stated-but-false invariant that made this defect invisible. Add it.

**Pin it.** Max `MassBudget`, ascend, assert the level is 0 **and** the upgrade
is purchasable again.

---

## LOGIN-1 — The login reward mints on repeat when writes fail

| | |
|---|---|
| **Severity** | **CRITICAL** |
| **Status** | **READY** |
| **Where** | `src/Server/ProgressionService.luau:471-482` |

**Root cause.** The streak write is unchecked **and** the credit runs
**unconditionally**. If the write is refused the reward is paid anyway and the
streak does not advance — so every subsequent join re-credits it. A player whose
profile writes are failing farms the ladder on a rejoin loop.

### The fix

```lua
local ok, reason = PlayerProfile.mutate(player, function(d)
    ...advance the streak...
end)
if not ok then
    -- NOT CREDITED. The streak write is what makes this reward once-only; if it
    -- did not land, paying anyway turns a rejoin into a mint.
    return false, reason or "mutate_failed"
end
EconomyService.credit(player, currency, amount, "login_streak")
```

**Three siblings, same file, same shape — fix together.** `:71-80` (daily spin,
burns 24h), `:111-120` (promo code, spent forever), `:323-346` (quest, marked
claimed). All write the "already claimed" flag inside `mutate`, then discard the
credit result. **These fail the opposite way to `LOGIN-1`** — they lose the
player's reward rather than minting one — but the cause is identical.

**The ordering rule, stated once for all four:** *the flag that makes a reward
once-only must be written **after** the payment is confirmed, or its failure must
roll the flag back.* `OfflineService.buyVaultHours:463-468` already does this
correctly and is the pattern to copy.

**Pin it.** Force `mutate` to fail, claim, assert nothing was credited and the
flag is unset.

---

## NAN-1 — NaN permanently poisons a balance

| | |
|---|---|
| **Severity** | **CRITICAL** |
| **Status** | **READY** |
| **Where** | `PlayerProfile._reconcile`, consumed at `EconomyService.luau:81-87` |

**Root cause.** No reconcile guard repairs a non-number or NaN `Cash` / `Gems` /
`Diamonds` / `LifetimeCash` / `HighestRoll`. `_reconcile`'s `fill` only writes
when the key is **absent**, so a key present with a poisoned value is left alone.
Then `current + amount` stays NaN, `next > MAX_CURRENCY` is **false** (every NaN
comparison is), and NaN is written back. **Unrecoverable in-game.**

`BundleExpiry` is the only scalar that has a NaN guard (`:346-348`) — which is
the proof the pattern was known and not generalised.

### The fix

In `_reconcile`, repair every numeric scalar the way `BundleExpiry` already is:

```lua
-- NaN AND WRONG-TYPE REPAIR FOR EVERY NUMERIC SCALAR. `fill` only writes absent
-- keys, so a field present with a poisoned value survives it. NaN then defeats
-- every downstream guard -- `next > MAX_CURRENCY` is FALSE for NaN -- and writes
-- straight back to the DataStore. One poisoned balance is unrecoverable in-game.
for _, key in ipairs({ "Cash", "Gems", "Diamonds", "LifetimeCash", "HighestRoll",
                       "Ascensions", "TotalRolls", "DieSlots" }) do
    local v = data[key]
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
        data[key] = TEMPLATE[key]
    end
end
```

**Belt and braces — also guard the writer.** `EconomyService.writeBalance` should
refuse a non-finite value outright, so a future path cannot reintroduce this
without reconcile's help.

**Pin it.** `ProfileSchema.test.luau`: reconcile a profile with `Cash = 0/0` and
assert it comes back finite. Extend the same test to the **seven unguarded
container fields** in `RECON-1`.

---

# BATCH 4 — INERT FEATURES

## BOARD-1 — All three leaderboards have never been written

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Where** | `src/Server/LeaderboardService.luau:245-254` |
| **Costs** | Every player's competitive record, since launch |

**Root cause.** `updatePlayer` is the only caller of `submitScore`, and
`updatePlayer` itself is called from **nowhere**. The HLD specifies writes *"on
player exit and on the periodic auto-save"* — **neither hook exists.** All three
OrderedDataStores are empty, so `getBoard` returns nothing and the BOARDS panel —
documented as done and live — renders empty to every player, forever.

### The fix

Two hooks. In `ServerBootstrap.server.luau`'s `onPlayerRemoving`, **before**
`PlayerProfile.release` (a released profile refuses reads):

```lua
-- MUST run before release, for the same reason OfflineService.onPlayerRemoving
-- does: it reads the profile, and a released profile is gone.
LeaderboardService.updatePlayer(player)

OfflineService.onPlayerRemoving(player)
...
PlayerProfile.release(player)
```

And a periodic publish on the existing server tick, so a crash or a `BindToClose`
race does not lose the session's progress.

**Watch for `M3` while you are here.** `getBoard` yields inside the remote
handler and sets `lastFetch` *after* the yield, so every request arriving during
it issues its own `GetSortedAsync` — 30 players refreshing at once produce 30
concurrent calls, Roblox throttles, and the boards freeze. Set the timestamp
**before** the yield.

**Pin it.** Assert `submitScore` is reached on player exit.

---

## LUCK-1 — `Upgrades.Luck` is sold for ~$23.7M and read by nothing

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **NEEDS A DECISION** |
| **Where** | `src/Shared/UpgradeCatalog.luau:71-77` |

**Root cause.** A fully wired, affordability-checked, rate-limited purchase whose
stored level is read by no gameplay code. Maxing it costs about **$23.7M Cash**
and changes zero bytes of behaviour. Note `RollService` reads
`BoostService.getMultiplier(player, "LuckBoost")` — a **different key**.

**The decision is yours:** make it do something, or remove it.

- **Remove** — honest, and smallest. But "Luck" is a genre-standard idle upgrade
  and the slot is a natural sink.
- **Implement** — it cannot bias the sampling (that breaks FR-3.4, exactly as
  `LuckBoost` could not). The only compliant reading is a **payout multiplier**,
  which makes it a duplicate of `CashX2` and `LuckBoost`.

**Recommendation: remove it**, and reuse the Cash sink for something that is not
already covered three ways. Whichever you pick, **do not leave it purchasable as
it is** — it takes $23.7M for nothing.

---

## SHAPE-1 — The SHAPES equip button is dead

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Where** | `src/Client/V7MenuPanel.luau:1073` and `:1157` |

**Root cause.** Both lines read `playerInventory`, but the only declaration is at
**`:3854`, inside `buildSlotsOverlay`** — a different closure. Inside
`buildShapesOverlay` the name resolves to a **global**, i.e. `nil`. So
`ownedTotal` is always 0: a player holding three D6 sees **"[ NO DICE OWNED ]"**,
and the click guard `ownedTotal > 0` can never pass.

`--!strict` flags this as an unknown global **at analysis time** — which is one
more reason P-1 is a blocker and not a formality.

### The fix

Give `buildShapesOverlay` its own inventory local, populated from the snapshot in
`refreshShapes` (the server already ships `state.inventory`):

```lua
-- Its own copy, deliberately. The SLOTS overlay has a `playerInventory` of the
-- same name in a DIFFERENT closure; these two lines used to resolve to a nil
-- global and report "NO DICE OWNED" to a player holding three.
local shapesInventory: { [string]: number } = {}
```

…assigned in `refreshShapes` from `state.inventory`, and read at `:1073` / `:1157`.

**Prove it.** Own two of a shape, open SHAPES, confirm the count is right and the
equip button works.

---

## QUEST-1 — The quests panel is permanent mock data with an invented reward

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Where** | `src/Client/V7MenuPanel.luau:1552-2252` |

**Root cause.** `questRows` is built at `:1705` and **read by nothing**.
`refreshQuests` only walks `playtimeRows` and `dayCardUIs`. `state.quests` —
which the server ships complete with `id / progress / target / claimed / ready`
*specifically* so the client can draw the bar — is read **nowhere**. So the cards
sit forever at construction values, `rowState.id` is never assigned, and CLAIM
returns immediately every time.

**The part that is not just dead but wrong:** the cards advertise
**`"REWARD: +$2,500 CASH"`**. The server deliberately omits quest reward amounts
from the snapshot under NFR-5. **The client invented a figure.**

### The fix

1. **Delete the fabricated reward string immediately** — that is a one-line
   change and it stops the game asserting a number nobody promised. Replace with
   the quest name only, or a non-numeric "REWARD ON COMPLETION".
2. Wire `refreshQuests` to walk `state.quests`, assign `rowState.id`, and drive
   progress / claimed / ready from the snapshot.

**Why not ship the amount.** It would need the server to send a reward figure,
which NFR-5 forbids. If the operator wants amounts shown, the reward table must
move to `src/Shared/` so the client can look it up locally — the same solution
`MonetisationCatalog` already uses. **That is a design decision, not a bug fix.**

---

# BATCH 5 — WRONG NUMBERS ON SCREEN

## RISK-1 — RISK reads one die and is the wrong formula

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Stands** | CONFIRMED. **Operator-reported**, then measured |
| **Where** | `src/Client/ClientBootstrap.client.luau:219` |

**Root cause.** Two defects in one line — `local die = state.dice[1]`. It never
looks past the first die, so forging any other die does not move the number. And
it is the **wrong quantity**: FR-5.1 breaks the streak when **any** die lands
Void, so the real figure is `1 − Π(1 − pᵢ)`.

| Dice | HUD shows | Real risk | Understated by |
|---|---|---|---|
| 3 | 33.0% | 69.9% | 36.9 pts |
| 7 | 33.0% | 93.9% | 60.9 pts |
| 12 | 33.0% | 99.2% | **66.2 pts** |

At the 12-slot cap the HUD says "33%" while the streak is **99.2% certain to
break**. Players build their entire mass strategy on it.

### The fix

Aggregate across every die. The per-die call is already correct — only the
combination is missing:

```lua
-- ACROSS EVERY DIE, not just the first. FR-5.1 resets the streak when ANY die
-- lands Void, so the risk is the complement of "no die voids" -- not die 1's own
-- probability. Reading only dice[1] also meant forging any other die never moved
-- the number, which is how this was spotted.
local survive = 1.0
for _, die in ipairs(state.dice) do
    local p = <existing per-die voidProbability>
    survive *= (1 - p)
end
return (1 - survive) * 100
```

**Keep the existing guards.** The `nil`-on-unknown behaviour and the face-shape
tolerance at `:232-253` are both load-bearing — the all-zero mass case is what
took the whole client down once. Wrap the loop, do not replace them.

**Pin it.** Assert 3 dice at 33% each produce ~69.9%, not 33%.

---

## MULT-1 — The MULT chip overstates by orders of magnitude

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Where** | `src/Client/ClientBootstrap.client.luau:290` |

**Root cause.** `math.min(streak, 500)` — the server caps the exponent at **50**
(`RollService.STREAK_CAP`) and additionally clamps to `1e6`. At StreakStrength 20
and streak 60 the HUD reads **×56,347** against a real **×9,100**.

### The fix — and fix `CONST-1` with it

Do **not** just change `500` to `50`. That is the third hardcoded copy of a
server-owned tuning constant in this one function — `B_PER_LEVEL = 0.01` two
lines above is the second (`CONST-1`). Patching the number leaves the
duplication.

**Move both constants into `src/Shared/`** and have both sides read them:

```lua
-- Shared/StreakMath.luau  (new, small, pure)
StreakMath.B_PER_LEVEL = 0.01
StreakMath.STREAK_CAP = 50
StreakMath.MAX_MULTIPLIER = 1e6
function StreakMath.multiplier(level: number, streak: number): number
```

Server: `RollService` reads them. Client: `estimateMultiplier` calls the same
function. **This is the `ForgeMath` pattern** — shared because pure, so the number
on screen cannot drift from the number that pays.

**Pin it.** Assert the client estimate equals `RollService.streakMultiplier` for a
grid of levels and streaks **including past the cap**.

---

# BATCH 6 — SAFETY NETS (before Phase 2)

These are not the most painful today. They are the ones that **turn into data
loss the moment Phase 2 ships**, so they must land first.

## CURR-1 — Currency fallthrough silently resolves to Diamonds

| | |
|---|---|
| **Severity** | HIGH — **blocks Shards work** |
| **Status** | **READY** |
| **Where** | `EconomyService.luau:80-97`, and a second copy at `PurchaseService.luau:85-93` |

**Root cause.** `readBalance` and `writeBalance` have no `else → refuse`. An
unrecognised, renamed or misspelled currency **reads and writes the Diamonds
balance** — the premium prestige currency — through `credit`, `debit`, `spend`,
`balance` and `canAfford` alike. Nothing warns.

**Why this is worse than it looks.** Because reward tables are typed
`EconomyService.Currency`, **widening the union for Shards makes the broken
fallthroughs compile silently.** The type system will hide this, not catch it.
There are **23 sites** in total (enumerated in `docs/ROADMAP.md` §12.5) and a
bundle loop at `PurchaseService:126-132` with **no `else` at all**, which would
skip a Shard part after the player paid.

### The fix

Make both functions **total**, and refuse rather than guess:

```lua
local function readBalance(data, currency: Currency): number
    if currency == "Cash" then return data.Cash
    elseif currency == "Gems" then return data.Gems
    elseif currency == "Diamonds" then return data.Diamonds end
    -- NOT a silent fallthrough. This used to `return data.Diamonds`, so any
    -- currency the branches did not name read and wrote the premium balance.
    error("unknown currency: " .. tostring(currency))
end
```

…and an `isCurrency` guard at the public boundary (`credit`/`debit`/`spend`/
`balance`/`canAfford`) that refuses cleanly instead of throwing, matching
`PurchaseService:81-83`, which **already does this correctly**.

**Pin it — this is the important half.** A test that **enumerates the currency
union** and asserts `readBalance`/`writeBalance` are total over it. No test pins
the list today; that absence is why the fallthrough survived.

---

## DIE-1 — A new per-die field must be added in six places; three *delete* it

| | |
|---|---|
| **Severity** | HIGH — **blocks Trait Forge** |
| **Status** | **READY** (as a checklist) |

The roadmap names one site. There are six:

| # | Site | Without the edit |
|---|---|---|
| 1 | `PlayerProfile.luau:325` per-die loop | `nil` forever on existing saves |
| 2 | `DiceCatalog.newDie` | every new die born without it |
| 3 | **`ForgeService.luau:716-733` `performSetShape`** | **every shape change silently deletes it** |
| 4 | **`ForgeService.luau:213-250` `repairDie`** | **a join-time repair strips it** |
| 5 | `ForgeService` `assertDieInvariant` | no validation; a hand-edited profile passes |
| 6 | `StateSyncService.luau:117-132` | never reaches the client; looks like a UI bug |

**#3 and #4 are the dangerous ones**, and the reason is the **detection
asymmetry**: #1 fails on the first reload and is obvious. #3 and #4 fail only
*after* a shape change — a player forges traits, uses them for a week, switches
D6 → D8, and they are gone. **That is the one that reaches production.**

### The fix

Both rebuild the die as a fresh **four-field literal**. Make them **carry
forward** every field they do not deliberately reset — the same way
`performSetShape` already carries elements forward at `:665`.

**Do this before writing any trait code, not during.**

---

## SAVE-1 — The payload ceiling is documented, tested, and never called

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Where** | `PlayerProfile.luau:681` (zero production callers) |

`API_DATA_CONTRACT.md` §3.1 invariant 6: *"The serialised profile is asserted
under the payload ceiling **before** every save."* It is not. Past ~4MB the
profile **silently stops persisting** — no warn, no kick, no telemetry. The
player keeps playing on a profile that is no longer saving.

Compounding: `recordPurchase:590-599` returns `ceiling_reached_all_live`
**without evicting**, so `PurchaseOrder` grows unbounded, and the comment
promising the oldest are *"archived rather than dropped"* describes **archive
code that does not exist**.

**Fix:** call `checkPayloadSize` before every save, refuse loudly and log on
failure, and either implement the archive or correct the comment to say entries
are retained and the ceiling is a hard stop.

---

## VAULT-1 — The vault accrual is consumed before the payout lands

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Where** | `OfflineService.luau:354-375` |

Order is: consume the vault → zero the frozen window → **then** credit → check.
A failed credit loses the player's **entire offline accrual**.

This inverts the rule stated two paragraphs later in the same file at `:377-380`
("SPENT ONLY NOW, after the money is safely in") — which I wrote for the boost
consume in `OFF-1` and did not apply to the accrual six lines above it.

**Fix:** credit first, then consume; or refund on a failed credit, as
`buyVaultHours:463-468` does. **Also add the missing finiteness guard** on
`BoostService.getMultiplier`'s stored value — `RollService:303-306` guards the
identical read and this does not.

---

## RECON-1 — Seven profile fields have no type guard

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |

`fill` only writes when a key is **absent**; a key present with the **wrong type**
is left alone. Guards exist for six fields. **Missing:** `Vault`, `Settings`,
`Quests`, `LoginStreak`, `CodesRedeemed`, `PurchaseIds`/`PurchaseOrder`.

**Worst blast radius:** a wrong-typed `Vault` throws inside `admitPlayer`, so the
roll session, the bundle stamp and the **first snapshot** never run. The player
sits in a live session with a blank UI, and the stranded-player sweep sees
`isActive() == true` and will not re-admit them.

`ProfileSchema.test.luau:192-199` tests exactly the three fields that **do** have
guards — which is why the gap reads as covered.

**Fix:** extend the type-repair block to every container field, and extend the
test to the ones it does not cover.

**Related, same file:** `H-8` — `if #data.Dice == 0 then data.Dice = TEMPLATE`
is the one place reconcile **destroys** rather than fills, and a DataStore
round-trip turns a holed array into a dictionary where `#` is 0. Latent today;
repair it to fill gaps rather than wipe.

---

## FANOUT-1 — Two unguarded lines sit upstream of the panel fan-out

| | |
|---|---|
| **Severity** | HIGH |
| **Status** | **READY** |
| **Where** | `ClientBootstrap.client.luau:310`, `:326-329` |

`V7MenuPanel:applyState` and `V7ForgePanel:applyState` are both correctly
isolated. But `:310` and `:326-329` run **before** `menuController:applyState` at
`:336`. Only the risk calculation — **the one that already caused the L-057
incident** — was wrapped.

`estimateMultiplier` throws on any non-table `state.diamondTree`. A throw there
aborts the snapshot before any panel is fed, while the HUD keeps updating. **That
is the L-057 symptom exactly.**

**Fix:** wrap both in `pcall`, matching the risk calculation directly above them.

**Second, same file:** the three `.new()` panel constructions at `:152/:155/:159`
are **not** `pcall`'d, unlike `require` and `init` which both route failure
through `fatal()`. A throw inside ~6,000 lines of `V7MenuPanel.new` leaves the
ROLL button unwired **with no error panel**, because that path was skipped.

---

# BATCH 7 — EVERYTHING ELSE

Grouped, with the fix in one line each. Full detail in `docs/ROADMAP.md` §12.4
and §12.8.

### Money and economy (MEDIUM)

| Item | Fix |
|---|---|
| `buyVaultHours` charges for hours the VIP floor already covers | Clamp the request to `effectiveBuyableHours`, not just refuse at zero |
| Four handlers spend then discard the write result | Check `mutate`, refund on failure — copy `ForgeService:454-459` |
| `AddDieSlot` mints inventory `BuyDieInstance` charges $4.2M for | Write `Inventory` in `AddDieSlot`, or price both the same |
| `grantCurrency` bypasses `EconomyService` | Route through `credit` — restores the clamp and `LifetimeCash` |
| `BuyDieInstance("D2")` free and unbounded | Refuse a zero-cost purchase, or cap inventory |
| `SetElement` charges 50 Cash for a no-op | Refuse same-element, as `performSetShape:611-613` does |
| `recordPurchase` bypasses `mutate` (no `IsActive` check) | Route through `mutate` |
| Shutdown races `BindToClose` vs `PlayerRemoving` for `Vault.LastSeen` | Stamp it in `BindToClose` too |

### Wrong or invented figures on screen (MEDIUM)

| Item | Fix |
|---|---|
| `★ TOTAL` sums face **indices**, which have no economic meaning | Sum payout, or relabel it as face numbers |
| Boost multipliers leak in the generic `upgrades` map | Filter `Boost_*_Mult` out of the snapshot |
| Vault invents defaults, hardcodes "1.50x VIP", labels Premium "Standard" | Render `--` for missing; call `VaultCatalog.tierName()` |
| Shop shows both the true **and** the false Luck Boost description | Delete the stale fine print at `V7MenuPanel:2412` |
| Payout flash shows the pre-multiplier figure | Emit the credited amount, or apply the multiplier before emitting |
| Throttled leaderboard read painted as "STREAM OFFLINE" | Distinguish `throttled` from failure; retry |
| Client duplicates of playtime/login reward tables | Move to `src/Shared/` |
| Forge re-implements `ForgeMath` (third L-025 instance) | Call `ForgeMath` |
| `+` on the starting D2 returns 2 mass where `−` removed 5 | Remove the per-donor cap of 1 |

### Dead and misleading (LOW)

`_reconcile` runs before `_migrate` and discards its return · settings toggles
control nothing · **nothing subscribes to `onNotice`, so every server refusal is
fired into nothing** · SAFE and EVEN presets are identical · the SHAPES priced
button has no handler (an overlay intercepts it) · `Vault.AccrualId` write-only ·
`starterBundle` computed and never rendered · corrupt die repairs to D6 not D2 ·
`BadRollShield` sold as both a $5,000 upgrade and a gamepass · per-snapshot model
churn.

---

# ALREADY FIXED — kept for the lesson

## OFF-1 — `OfflineX2` was consumed without being applied

| | |
|---|---|
| **Status** | **FIXED** — `67c8e84` |
| **Stands** | **A regression I introduced in `6cb6aa1` the same day** |

The original `ClaimVault` bug gave 2× away free to anyone who asked. My fix gated
the **multiply** on the client's `doubled` flag but the **consume** on
`boostMult > 1.0` — and the only shipped caller passes `false`. So a player bought
a real-Robux product, collected **1×**, and the boost was destroyed.

**Worse than the exploit it replaced.** That one gave value away; this took money
and gave nothing.

**The rule, now written at the site:** *apply and consume must share one
condition.* Both are `boostMult > 1.0`, so they cannot disagree about whether the
boost was used, whatever any caller passes.

**Why the tests missed it:** they only ever claimed with `doubled = true` — the
one value **no real caller uses**. Testing the convenient case is what hid it.
Seven assertions were added pinning both flag values.

---

# STANDING BLOCKERS — not code

| Blocker | Who |
|---|---|
| **P-1 static analysis has never been produced** for any change. No Luau analyzer on PATH; the Script Analysis pane is not script-readable. `TEST_PLAN.md:45` makes a missing P-1 a **rejected gate, never a pass with a caveat** — so Gate 2 is not clean on anything shipped | **Operator.** Would have caught `SHAPE-1` (unknown global) outright |
| `Vendor/ProfileStore.luau` warning policy — `--!nonstrict` or exclude | **Operator.** Blocks the 158-warning cleanup |
| 9 audio asset IDs; a real `GROUP_ID` | **Operator.** Pure config |
| **Round 2 of the sweep** — deferred. Was to re-verify every claim independently and cover element resolution across dice, forge mass validation, auto-roll lifecycle, and rate-limiter token maths | **Operator's call when to run** |

---

# TWO THINGS I GOT WRONG, STATED PLAINLY

Both are in this document as defects, and both came from fixes made earlier the
same day:

1. **`OFF-1`** — my exploit fix destroyed a paid product. Fixed.
2. **`SLOT-2`** — my `slotNodes` threading updated the client and missed the
   server. Open, in batch 2.

They share a cause worth naming: **I changed a shared function's behaviour and
did not grep every call site in the same commit.** Making the new parameter
optional is precisely what made the omission silent. That is now the stated rule
in `SLOT-2`.

It is also the argument for the pipeline. Neither was caught by a green suite;
both were caught by a fresh context reading the diff with no memory of having
written it.
