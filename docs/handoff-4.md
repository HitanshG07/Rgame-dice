# HANDOFF 4 — Economy corrections, tuning, and the Gems sink question

**Date:** 2026-08-13
**Head:** `740d117` · 21 suites, 3,546 assertions, 0 failing · tree clean

**Status:** S3-a / S3-c / S3-d are DONE. The operator's latest defect list is
done except the Gems vault-storage feature, which needs a design decision.
**Animation not started** — deliberately, on the operator's instruction.

---

## 1. WHAT LANDED SINCE HANDOFF 3

### `72d135f` — S3-d, choose which die sits in which slot
New `SwapDice` remote; `<` / `>` arrows in the forge. Position in `d.Dice` IS
the board slot, so reordering the array is the whole feature — the data model
already supported it and nothing exposed it.

Refuses while there are unsaved edits: a pending draft belongs to a die INDEX,
so swapping underneath it would apply a half-finished layout to a different die.

*Verified:* a marked die walked across the array, self-swap and out-of-range
both refused, and the panel FOLLOWS the die to its new slot.

### `074b5cf` — S3-c, buy another die of a shape you own
**Asking which of three readings the operator meant avoided a saved-data
migration entirely.** Ownership stays a boolean set; the repeat purchase buys a
DIE. `AddDieSlot` now takes a shape id, sharing the slot price curve and
ascension cap rather than getting a parallel set that could drift.

*Verified:* buying D3 gave `[D2,D2,D2,D2,D3]`; an unowned D20 refused; the
summary bar grouped them as `5x D2 (SUM: 7)` · `D3: 3`.

### `740d117` — ascension was priced on all-time cash

**The operator was right: "it shows i earned 1m but i didnt".**

`LifetimeCash` never resets — the NetWorth leaderboard ranks on it — but the
ascension reward read it as though it were per-run. Two real consequences:
after one ascension a player **permanently** met the threshold, and each
prestige **paid out again for earnings already converted into Diamonds**.

New `RunCash`, credited alongside lifetime and zeroed on ascension. Existing
profiles backfill from **current cash**, not lifetime — lifetime includes
everything already spent and already cashed in, so seeding from it would hand
every returning player an enormous unearned reward. Current cash is the most
generous figure that is defensibly "this run" and can only under-credit.

Panel now shows `$0 / $100.00K this run` — the earned/target format requested,
and the same shape either side of the threshold so the numbers do not jump.

---

## 2. TUNING DECISIONS MADE THIS SESSION

### Roll speeds
The operator asked for "roll speed to 5 seconds and auto to 8". Taken literally
that made **auto slower than manual**, turning the Auto-Roll gamepass into a
downgrade — so it was worth confirming. Agreed as rolls-per-5-seconds:

| | Rate |
|---|---|
| Manual | 1.0/s (5 per 5s) |
| Auto-roll, best | 1.6/s (8 per 5s) |

**`AUTO_FLOOR` also had to move (1.0 → 0.625).** It was `1.0`, which after the
manual retune would have left the two IDENTICAL — a player tapping steadily
would have matched a fully-upgraded auto-roll and the pass would be worth
nothing. UT-6 now asserts the **relationship**, not the literals, so a future
retune of either cannot silently close the gap.

### Vault tiers
The operator proposed VIP `1.25x` and Premium `1.5x`. The problem: **anything
above 100% means offline out-earns playing**, which in an idle game makes
closing the game the optimal move. Agreed on additive-and-capped:

| Source | Efficiency | Capacity |
|---|---|---|
| Base | 50% | 4h |
| Cash upgrades | +5%/level (max +25%) | +0.8h/level (max +8h) |
| Roblox Premium | +15% | +4h |
| VIP Vault pass | +25% | floors at 24h |
| **Fully stacked** | **100% (cap)** | **24h** |

Everything adds, so all three purchases matter at once. VIP now sets a **floor**
rather than overriding — it returned 24h outright, so a player with maxed
upgrades plus Premium could have been entitled to more and been silently cut
back by buying the pass. Premium is read from `Player.MembershipType`,
server-side.

### Slot cap — already answered
The operator asked whether the cap should auto-update per ascension. **It
already does**, as of `47a3535`: `3 + ascensions`, hard maximum 7. The hard 7 is
not a balance value — `BoardView` has layouts for exactly 1–7 and
`DiceRenderer` pools 7 visuals. Route A removes that constraint.

---

## 3. THE GEMS VAULT-STORAGE IDEA — NEEDS A DECISION

> *"the vault capacity is something users can buy through gems … 5 gems means 1m
> of storage or something — it should not be pay to win"*

### The finding that makes this attractive

**Gems currently have NO sink.** They can be earned (promo codes, daily spin,
quests) and bought (two Robux products), and there is **nowhere to spend them**.
Grep confirms: no handler anywhere debits Gems. So a vault-storage exchange
would be the currency's first real use, which is a good fit rather than a bolt-on.

### The "not pay to win" tension, stated honestly

Vault capacity **is** an economic advantage — more hours banked is more Cash.
Gems are purchasable with Robux. So a naive "Gems buy capacity" is pay-to-win by
construction. Three ways to keep it fair, and this is the decision needed:

1. **Cap the purchasable capacity.** Gems buy hours up to the same ceiling a
   Cash player reaches (12h), so paying only buys *speed*, never a higher
   ceiling. This is the standard non-P2W shape.
2. **Make Gems generously earnable.** If quests and the daily spin pay enough
   Gems that a regular player reaches the cap in reasonable time, buying them is
   a shortcut rather than an advantage.
3. **Both** — a cap plus a real earn rate. Strongest position.

### What I would need from the operator

- Which of the three above.
- **The exchange rate.** "5 gems = 1m of storage" is ambiguous — 1 million what?
  Capacity is measured in *seconds of offline time*, not currency. Likely
  readings: 5 Gems = 1 hour of capacity, or 5 Gems = enough capacity to bank
  $1M at the player's current rate (which would vary per player and is probably
  not what is wanted).
- Whether Gems should also buy **efficiency**, or capacity only.

**Nothing has been built for this.** It is specified here and waiting.

---

## 4. STILL OUTSTANDING

### The animation rebuild — Route A, approved, not started
Full spec and the architectural analysis are in **handoff-3 §2**. Summary:
every die is currently in its OWN ViewportFrame at a deterministic grid anchor,
which is both the "restricted box" feeling and the reason organic scatter is
unreachable. Route A puts all dice in one shared 3D scene.

The operator confirmed the **20-dice figure is a progression ceiling to design
toward**, not a current requirement — so the new renderer must not cap die count
architecturally, even though `MAX_DIE_SLOTS` stays 7 until the balance decision
is made.

**The overlap in the latest screenshots is this same issue** — six dice cannot
fit the fixed grid without collisions. Not a new defect.

### Deferred / blocked
- **Audio** — 9 `DUMMY_ID_*` placeholders; fails closed, Settings says so.
- **Roblox group id** — `GROUP_ID = 0`; group rewards built and commented out.
- **Balance tuning** unvalidated against real play.
- **Element unlocks** (Fire/Freeze/Gold/Multiplier) built server-side, no unlock
  path; belongs in ASCEND.
- `src/Client/LegacyUI/` — dead duplicate code awaiting deletion.

### Housekeeping
- **`ASCEND_MIN_LIFETIME_CASH` is `100000` for testing — SHIP `1e6`.** One
  clearly-marked line in `DiceCatalog`. Still outstanding from handoff 3.

---

## 5. SUGGESTED ORDER

1. **Gems vault storage** — needs the three answers in §3 first
2. **Animation rebuild (Route A)** — approved, self-contained, wants its own
   verification pass per L-031 (screenshots mid-tumble, several consecutive
   rolls compared, 1/2/4/7 dice, and FR-1.4 containment must hold)
3. Restore the ascension threshold before any real playtest

Ledger entries this session: **L-039** … **L-043**.
