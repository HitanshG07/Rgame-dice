# HANDOFF 4 — Economy corrections, tuning, and the Gems sink question

**Date:** 2026-08-13
**Head:** `f44af67` · 21 suites, 3,546 assertions, 0 failing · tree clean

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

### Tier differences are now visible — `f44af67`

> *"make sure to add that vault and every detail which differentiates standard
> vip and premium users is mentioned in a small font wherever its needed"*

**The vault panel said nothing about tier at all.** It stated capacity in hours
and never mentioned efficiency, so a player banking 50% of their earning rate
and one banking 100% saw *identical screens* — with no way to learn the
difference existed, or that a better tier was available.

New **`VaultCatalog`** (shared) now holds the tier values and the wording. They
had been server-side locals in `OfflineService`, which is precisely why the
client could not state them; `OfflineService` reads from the catalog now, so
there is one declaration instead of two that can drift (L-025).

| Surface | Small print |
|---|---|
| **VAULT panel** | `VIP — banks 75% of your earning rate` / `Roblox Premium +15% and +4h` |
| **SHOP, VIP Vault card** | `Vault: +25% of your earning rate, capacity raised to 24h. Standard is 50% and 4h. Stacks with Roblox Premium.` |

Two deliberate choices worth keeping:

- **States the player's ACTUAL rate first**, from the server's computed value —
  not a client re-derivation — and only mentions tiers they do **not** already
  have. Telling a VIP about the VIP bonus is noise, and noise is what makes
  small print go unread.
- **`UITheme.smallPrint` is not `TextScaled`.** Every other label in this UI
  scales to fill its box, which is right for a figure read at a glance and wrong
  for a footnote: scaled small print shouts on a large monitor and vanishes on a
  phone. Fixed size keeps it subordinate to the number it annotates.

The old VIP blurb was *"A far higher ceiling on offline earnings"* — not
something a player can weigh against a Robux price.

The snapshot now carries `efficiency`, `hasVip` and `hasPremium`. Those are
entitlement **facts the server has already verified**; the client renders them
and never asserts them.

### Slot cap — already answered
The operator asked whether the cap should auto-update per ascension. **It
already does**, as of `47a3535`: `3 + ascensions`, hard maximum 7. The hard 7 is
not a balance value — `BoardView` has layouts for exactly 1–7 and
`DiceRenderer` pools 7 visuals. Route A removes that constraint.

---

## 3. THE GEMS VAULT-STORAGE FEATURE — SPECIFIED, NOT BUILT

> *"the vault capacity is something users can buy through gems … 5 gems means 1m
> of storage or something — it should not be pay to win"*
> *"yeah sure it can be hour based for gems"*
> *"we will be making codes / quests - which give diamonds and gems aswell in
> future right"*

**RESOLVED: hour-based.** `5 Gems = 1 hour` of vault capacity.

### Gems have no sink — but they DO have earn paths

**Nothing anywhere debits Gems.** Grep confirms no spend path exists, so this
feature would be the currency's first real use. That is a good fit rather than a
bolt-on.

Correcting something stated loosely earlier: Gem **earning** is already
implemented and shipping, not future work. Every source below exists in code
today:

| Source | Gems | Notes |
|---|---|---|
| Quest `roll500` | 40 | daily rotation |
| Quest `streak15` | 30 | daily rotation |
| Quest `forge10` | 25 | daily rotation |
| Playtime chest, Tier 3 | 35 | 45 min of session time |
| Daily spin | 150 | one outcome on the wheel |
| Promo code `DICEFORGE` | 100 | once per player |

Three of the seven daily quests pay Gems, and the day's three are rolled from
that pool — so a typical active day yields roughly **25–105 Gems**, plus 35 from
the Tier-3 chest, plus the spin when it lands on Gems.

Diamonds are likewise already earnable outside ascension: the daily spin can pay
15, and `FORGE2026` pays 10.

So the answer to *"we will be making codes / quests which give diamonds and gems
as well in future, right?"* is **that already works** — `PROMO_CODES` and the
quest table both support `Cash | Gems | Diamonds` and already use all three.
Adding more is a one-line entry in either table, not a feature.

### The pay-to-win question, and why it is manageable here

Vault capacity **is** an economic advantage — more hours banked is more Cash —
and Gems are purchasable with Robux. A naive "Gems buy capacity" is therefore
pay-to-win by construction.

Two properties together defuse it, and both should ship at once:

1. **Cap the purchasable capacity at the same ceiling Cash reaches.** Paying
   buys *speed to the cap*, never a higher cap. This is the standard non-P2W
   shape and the single most important constraint.
2. **The earn rate above is already real.** At ~60 Gems on an average active day
   and `5 Gems = 1 hour`, a free player adds roughly **12 hours of capacity per
   day of play** — so the cap is reachable without spending, and buying Gems is
   a shortcut rather than an advantage.

### Proposed numbers (needs operator sign-off before building)

- **Rate:** `5 Gems = 1 hour` (3600s) of vault capacity. Operator-confirmed.
- **Cap:** purchased capacity stops at **+8h**, the same total a maxed
  `VaultCapacity` Cash upgrade reaches. Combined with base 4h that is 12h,
  matching a fully Cash-upgraded player exactly.
- **Stacking:** adds into the existing capacity sum alongside Cash upgrades,
  Premium and VIP — so it cannot push past the VIP 24h floor either.
- **Capacity only, not efficiency.** Efficiency is the dial that decides whether
  offline can rival live play; leaving it purely Cash/Premium/VIP keeps the
  100% ceiling meaningful and avoids a second P2W surface.

### What is still needed

- Sign-off on the **+8h cap** specifically. It is the whole anti-P2W property,
  so it should be a deliberate choice rather than my default.
- A new `PurchasedVaultHours` profile field, a Gems spend path (the first one in
  the game), and a VAULT panel control. **None of this is built.**

`VaultCatalog.GEMS_PER_CAPACITY_HOUR = 5` and
`MAX_PURCHASED_CAPACITY_SEC = 8h` are already declared in the shared catalog
ready for this, but **nothing reads them yet** — they are the spec, not an
implementation.

---

## 3b. TO DO — ASCENSION THRESHOLD: SWITCH TO CASH ON HAND

**Operator-reported 2026-08-13. DECIDED, NOT IMPLEMENTED** — the operator asked
for it to be recorded rather than fixed in the moment.

> *"here it shows 40/1m but i have 500k in cash with me it should show the actual
> cash i have in the ascension as well"*

### Measured

```
cash          = $568,717
runCash       = $55,267
lifetimeCash  = $1,147,945
ascensions    = 3
```

The HUD shows **$558K**; the ASCEND panel shows **$40K / $100K**. Both figures
are internally correct, which is precisely what makes this bad: a player has no
way to reconcile them.

### Why they differ — two separate causes

**1. A one-off migration artifact.** `RunCash` was only introduced in `740d117`
(earlier today). The operator's last ascension predates the field, so it was
seeded by the `_reconcile` backfill rather than by a real reset. The $568K on
hand accumulated *before* the counter existed. **Every ascension from here
resets `Cash` and `RunCash` together, so this specific mismatch is self-healing
for new runs and for every new player.**

To confirm the operator's question directly: **yes, ascending does set Cash to
0** — `AscensionService` sets both `d.Cash = 0` and `d.RunCash = 0`. Nothing is
broken about the reset.

**2. A real design question that survives the artifact.** Even with a clean
reset, `Cash` and `RunCash` diverge the moment a player *spends*:

- `Cash` is what you are holding — it drops when you buy an upgrade or a slot.
- `RunCash` is what you have earned — spending does not reduce it.

So a player who earns $900K and spends $400K on upgrades holds $500K but has
earned $900K. Which one gates ascension is a genuine choice:

| Basis | Pro | Con |
|---|---|---|
| **Current Cash** | Always matches the HUD exactly. No hidden state. | Spending on upgrades pushes ascension further away — a real tradeoff, possibly a punishing one. |
| **Earned this run** (current) | Spending never delays prestige. | HUD and panel legitimately differ after any purchase, which is exactly the confusion reported. |
| **Show both, labelled** | Nothing hidden. | Two figures on a screen whose job is one yes/no decision. |

### DECIDED — use current Cash on hand

> *"holding — because after ascension I'm holding 0 so it would anyways be
> showing 0 in the ascension tab as well"*

**Operator decision, 2026-08-13. Not yet implemented.**

The reasoning is sound and is the whole argument for this option: ascension sets
`Cash = 0`, so the panel reads `$0 / $1.00M` immediately afterwards — the same
thing the HUD shows. **The two can never disagree again**, which removes the
entire class of confusion rather than papering over this instance of it.

### The work, when it is picked up

1. `AscensionService.ascend` reads `data.Cash` instead of `data.RunCash`.
2. The snapshot's `runCash` field is replaced by the existing `cash` field —
   the ASCEND panel already has `state.cash` available and needs no new data.
3. **DELETE `RunCash` entirely**: the profile field, the template default, the
   `_reconcile` backfill, the credit in `EconomyService`, the reset in
   `AscensionService`, and the two assertions in `Integration_Ascension`. This
   removal is the point — it is a field that existed for one day and caused one
   confusion, and keeping it "just in case" is how a schema accumulates ghosts.
4. UT-5's ascension assertions move to asserting against `Cash`.

**The tradeoff being accepted, stated plainly:** spending Cash on upgrades now
pushes ascension further away, because the threshold measures what you hold
rather than what you earned. That is a real gameplay consequence — upgrade-vs-
prestige becomes a genuine decision — and it is the cost of the two numbers
always agreeing. Worth revisiting if it turns out to feel punishing in play.

**Whichever way this lands, it must NOT go back to `LifetimeCash`** — see the
note below.

**Note this is separate from the bug fixed in `740d117`.** That one was real and
is fixed: the reward used to be priced on `LifetimeCash`, which never resets, so
a player permanently qualified after their first ascension and was paid again
for earnings already converted into Diamonds. Whichever basis is chosen here,
it must not go back to all-time cash.

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

1. **Ascension threshold → Cash on hand** (§3b) — decided, not built. Small and
   subtractive: it DELETES `RunCash` rather than adding anything. Do it before
   the Gems work so nothing new is built on a field that is being removed.
2. **Gems vault storage** — rate and shape are settled; needs sign-off on the
   +8h cap in §3, then it is a contained build (profile field, Gems spend path,
   VAULT panel control)
3. **Animation rebuild (Route A)** — approved, self-contained, wants its own
   verification pass per L-031 (screenshots mid-tumble, several consecutive
   rolls compared, 1/2/4/7 dice, and FR-1.4 containment must hold)
4. Restore the ascension threshold to `1e6` before any real playtest

Ledger entries this session: **L-039** … **L-043**.
