# Handoff 8 — the panels work, and we now know what is left

**Written:** 2026-08-23, end of session. **HEAD: `0f7a3c7`.**
> **§8 WAS APPENDED 2026-08-27 and supersedes the state described below.**
> Phase 0 shipped, and a full-repository sweep found five CRITICAL defects
> that the rest of this document predates — two of them destroy things
> players paid Robux for. **Read §8 before acting on §1–§7.**

Tree clean. **Supersedes `docs/handoff-7.md`** — not only its open items; §4 below
voids two of its factual claims as well.

The forward-looking half of this document has been split into its own file:
**`docs/ROADMAP.md`** is the plan to launch. This handoff records what happened
and what is true right now.

---

## 1. STATE

**21 suites, 0 failed, 3,569 assertions.** Verified in a running Studio session,
not by reading code.

**Script Analysis: 158 warnings.** Unchanged this session — no new ones were
introduced, and none were fixed. Still the standing NFR-8 blocker.

Handoff-7's §5 said "nothing outstanding" while those 158 warnings were open. It
was wrong when written. Treat §5 of that document as void.

---

## 2. WHAT LANDED THIS SESSION

Three commits, all repairing damage the UI revamp left behind.

### The revamp had rebuilt five panels and dropped the code behind them

**Four refreshers were empty stubs.** `refreshShop`, `refreshAscend`,
`refreshVault` and `refreshBoards` each had a body consisting of a single
comment. They were called on every snapshot and did nothing — so no shop card
ever showed OWNED, no vault figure ever appeared, and the boards never fetched.

The panels rendered perfectly. That is what made it invisible.

**The actions were gone too, which was worse.**

- Every shop BUY button read **"BUY FOR R$ 0"**. It formatted
  `entry.priceRobux` — a field that does not exist on `MonetisationCatalog.Entry`
  — so `or 0` fired for all fourteen items. The catalog holds no price *on
  purpose*: Roblox owns pricing, and a figure asserted client-side is one the
  platform's own prompt will contradict.
- **No BUY button had a purchase handler at all**, on the only screen that earns
  money.
- **The ASCEND button had zero click handlers.** It was decorative, sitting under
  a label promising a two-step confirmation that did not exist.

**`applyState` had lost its defenses.** The named list with per-refresher `pcall`
and warn-on-missing had been replaced by a bare `if` chain. An unguarded throw in
the first refresher escapes into the StateSync handler and takes the other six
panels *and* the forge with it — this is L-057, the incident that killed seven
panels once already.

Restored, and verified by deliberately sabotaging the first refresher in a live
session: all seven still ran.

### Fixed at `205be1d`

- `applyState`: named list, per-refresher `pcall`, warn on a missing refresher.
- Boards is pull-not-push — called from `openOverlay` with a board id, never from
  the snapshot fan-out. `activeBoard` restored to `"NetWorth"` from `nil`.
- `setCapability` repaints from `lastState` again, so audio rows stop reading
  stale from boot.
- Shop: OWNED pill, real `MarketplaceService` purchase prompt, button reads
  `"BUY"`.
- Ascend: reads `state.cash`, **not** `lifetimeCash` — lifetime never resets and
  once told a player they had earned $1.09M this run when they had earned
  nothing. Two-step confirm that disarms on a timer, on panel close, and the
  moment the reward goes away.
- Vault and boards rebuilt: absent vault renders `"--"` not `"$0"`; the VIP-floor
  wording; the stale-response guard on rapid tab switches.
- **Slots and shapes both read `d.shape` / `d.mass`.** The wire carries `Shape`
  and `MassBudget`, so every die fell back to `"D6"` at mass 60 — that is the
  "SLOT 01: D6 / 02: D6 / 03: D6" the operator screenshotted. Two-line fix.
- `dieSlotCost` returns `number?` and was compared with `>`; it throws on any
  locked slot at the ascension cap, reachable just by paging right.
- The viewport prune tested `orbitRadius` as a type tag, but a one-die orrery has
  radius 0 and matched *both* the keep and the drop rule — every new player leaked
  a pivoted model per panel open. Now pruned by parentage, which cannot drift.
- Trait forge marked COMING SOON; its reroll button had faked a spend by
  decrementing a label from 145 to 135 forever.

### Fixed at `77c19ab`

- **Slots is dynamic.** The inventory grouped dice by *shape*, injected every
  shape the diamond tree had unlocked, fell back to a phantom D6, and stopped at
  six cards. It now renders one card per entry of `Profile.Dice`.
- **Two-click swap** through the existing `SwapDice` remote — no new remote, no
  schema change. Verified end to end, including that the server refuses
  self-swaps (`invalid_request`) and out-of-range indices (`out_of_range`).
- **Typography by scaling.** The panels referenced `UITheme.Scale` **zero
  times** — 63 hardcoded text sizes, 48 of them ≤12px. A `UIScale` multiplies the
  whole design space so the ratio between an 11px label and its 16px box is
  identical at every scale; editing 63 literals individually would have broken
  the ~50 pixel reservations tuned against them. Derived from viewport, clamped
  to [1.0, 1.45].
- The shop's action row was anchored *outside* its `UIListLayout`, so the layout
  could not see it and the auto-sizing tier detail rendered through the BUY
  button. The reservation was 40px against a 42px need before any text grew.
  `TextFits` cannot catch this — an auto-sized label never truncates (L-058).
- `UITheme`: restored the viewport clamp on the panel floor. The revamp hardcoded
  680×420, and `V7ForgePanel` calls `UITheme.overlay` with no constraint of its
  own — so on a short window its close button went off-screen.

### Fixed at `c2dfdbc`

The inventory grid's cell height was `0.50` of its frame — a fraction that only
means "half" while there are exactly two rows. With seven dice the seventh card
rendered outside the panel. Fixed cell height, scrolling container.

### Two defects a fresh-context audit caught in my own work

Both were mine, both were caught before shipping, and both are worth recording:

1. **`slotPageCount` was declared above the two locals it reads.** Lua binds
   closure names at parse time, so both resolved to `nil` globals and `#nil`
   would have thrown on the first snapshot — killing the slots panel on every
   render. This is the L-057 shape, reintroduced *in the file that documents
   L-057*.
2. **The trait panel still asserted invented effects** — "+65% VELOCITY",
   "LEGENDARY" — rendering in live theme beside real dice. Removing the fake
   *spend* was not enough while the fabricated *figures* stayed.

The first would have been caught by nothing else; the build passes, and Rojo does
not type-check.

---

## 3. THE AUDIT — TEN UNFINISHED ITEMS

A full-repository sweep (three parallel research passes: server systems, client
UI, and the project's own docs/ledger) found ten things started and never
finished. Every row below was independently verified against live code.

| # | Item | State today | Verdict |
|---|---|---|---|
| 1 | **REDEEM code button** | Built, styled, **no click handler**. Backend fully works. | Fix — one line |
| 2 | **Element unlocks** | `Diamond.Elements` is read to gate elements and **never written**. Every player stuck on plain faces forever. | Build |
| 3 | **MassCeiling / SlotNodes** | Charge Diamonds, store the level, display it. **One read each in the whole codebase**, for display only. Real caps come from a flat constant and from ascension count. | Fix first |
| 4 | **Luck Boost / Offline 2x** | Cost **real Robux**. `BoostService.getMultiplier` is never called by anything. Player gets a countdown that does nothing. | Fix first |
| 5 | **Group Rewards** | Fully built, correct, deliberately unplugged (`GROUP_ID = 0`, registration commented out). | Operator: set ID |
| 6 | **Like Goal (FR-10.7)** | `EventState` remote declared, never fired. Client renders a bar reading fields no snapshot contains. | **Dropped** |
| 7 | **Daily Spin** | Remote, handler and client wrapper all work. **No button anywhere.** | Build |
| 8 | **Audio** | 9 `DUMMY_ID_*` placeholders. Fails closed correctly; Settings shows Music/SFX as LOCKED. | Operator: upload |
| 9 | **Trait Forge** | Pure decoration. No trait or shard concept exists in `src/Server/` or `src/Shared/` at all. | Build |
| 10 | **Dead legacy files** | `ForgePanel`, `MenuPanel`, `HUD`, `CurrencyModels` — 3,662 lines, superseded by the `V7*` set. **Not "required by nothing"** — see the correction below. | Delete |

**Items 3 and 4 are not "unfinished" — they are transactions that do not
deliver.** Item 4 involves real money.

---

## 4. FOUR CORRECTIONS TO THE RECORD

**Audio placeholder count.** `docs/handoff-7.md` §3 states *"23 audio asset
IDs"*. The real count is **9** — 8 SFX cues plus one music loop, verified by
direct grep of `AudioDirector.luau`. Handoffs 1 through 6 all correctly said 9.
Handoff-7 introduced the error and no later document caught it.

**"Nothing outstanding".** Handoff-7's §5 claimed the constants were ready and
nothing was outstanding, while 158 Script Analysis warnings were open and
recorded two sections above it in the same document. Void that section.

**"Required by nothing".** The audit table above originally described the four
dead client files as required by nothing and loaded by nothing. That was **wrong,
and acting on it would have broken the suite.**
`tests/ClientContract.test.luau` requires three of the four — `HUD`, `ForgePanel`
and `MenuPanel` — at `:104-106` in its `VIEW_MODULES` list and again at `:162` in
its `shutdown()` check. That suite fails loudly when a named module is missing,
which is its stated purpose. Only `CurrencyModels.luau` (81 lines) is genuinely
unreferenced. The line total is **3,662**, not ~3,500.

Caught on a re-verification pass, before any deletion was attempted.
`docs/ROADMAP.md` §7 now carries the corrected instruction, including the L-028
pre-deletion check for duties these files perform outside themselves.

**The assertion count.** §1 of this document originally said **3,565**. The live suite reports **3,569**, confirmed on 2026-08-26 in a running Studio session, and the scoreboard's last two entries independently say 3,569 and 3,570. Corrected throughout this file and in `HANDOFF.md`.

This one matters more than its size suggests. **The assertion count is this project's staleness canary** — L-019 and L-020 both turned on noticing that a green suite had run over stale code, and the tell was a count that did not move. A baseline recorded four low disarms that check: real work could remove four assertions and still look like it had added none.

All four corrections follow the same pattern the zero-warnings incident did: a
figure stated once, then carried forward by documents that did not re-check it.
The third adds a wrinkle worth naming — **"nothing references this" is a claim
about absence, and absence is the one thing a grep for a name cannot confirm.**
It has to be checked in the producer direction (L-027) or by deleting and running
the suite.

---

## 5. WHAT IS STILL OPEN

**Everything in `docs/ROADMAP.md`.** That document is the plan and supersedes the
scattered open-item lists in handoffs 1–7. In brief:

- **Phase 0** — stop charging for nothing (items 3, 4, 1 above). Pure backend.
- **Phase 1** — the only two new screens: Element unlocks (into the Shapes
  panel) and Daily Spin. Antigravity, one panel per run.
- **Phase 2** — backend against frozen UI: Elements, Daily Spin, Trait Forge.
- **Phase 3** — cleanup, Script Analysis to zero, and the operator-blocked items.

**The governing rule** the operator set: build the UI once, freeze it, then do
backend only. Never reopen a panel for a second feature.

**Blocked on the operator, cannot be done in code:** 9 audio asset IDs, and a
real `GROUP_ID`.

---

## 6. NOTES FOR THE NEXT SESSION

- **The build passing means nothing about types.** Rojo does not type-check, and
  there is no CLI type-checker in this repo. The declaration-order defect above
  built cleanly and would have thrown at runtime on every snapshot. Studio's
  analysis pane is the only mechanical check that exists.
- **`AbsoluteSize` reports post-`UIScale` values.** The shop shell measures
  992×627 on a 1240×774 viewport; dividing by the scale returns exactly the
  940×580 design size. The constraint is holding — the larger number is the
  rendered size, not a violation.
- **A stub is a present function.** `applyState`'s missing-refresher warning
  cannot catch an empty refresher body, only a lost assignment. A silent console
  is not proof a panel is live.
- **Verify in a running game.** Two real defects this session survived a
  fresh-context code audit and were caught only by running it.
- **When a number and a screenshot disagree, the screenshot wins.**

---

## 7. BEFORE SHIP

1. **Phase 0 of the roadmap** — nothing should ship while two purchase paths take
   currency and deliver nothing. Item 4 involves real money.
2. **Script Analysis to zero** (NFR-8). Decide the `Vendor/ProfileStore.luau`
   policy first — 2,242 lines of third-party code that must not be edited.
3. **Audio asset IDs and `GROUP_ID`** — operator-supplied, no code work.

Constants are already at shipping values: `ASCEND_MIN_LIFETIME_CASH` at `1e6`,
`PLAYTEST_DIE_COUNT` at `0`, `MAX_DIE_SLOTS` at 12.

---

## 8. SESSION 2026-08-26/27 — PHASE 0 SHIPPED, AND A SWEEP THAT CHANGED THE PICTURE

Appended after the original document. HEAD at writing: `67c8e84`.

### 8.1 What shipped

| Commit | What |
|---|---|
| `aec44c0` | Spec amendment: FR-1.1 said 1–7 dice, the game ships 12. Two more rows carried the same stale 7 |
| `a31dda3` | **Phase 0c** — REDEEM button works |
| `6cb6aa1` | **Phase 0a** — boosts reach a number; a free-2× vault exploit closed |
| `daac879` | **Phase 0b** — Diamond nodes do something. **Phase 0 complete** |
| `67c8e84` | Fix for a real-money regression `6cb6aa1` introduced |

**23 suites, 0 failed, 3,642 assertions** (from 3,569).

### 8.2 The REDEEM button cost three audit rounds and tripped the breaker

The smallest item in the roadmap — one click handler — took **three Gate 2/3
rejections and eight defects**, and tripped the circuit breaker at
`AI_WORKSPACE_RULES.md:24`. The operator authorised completion.

**Two of the three rounds failed on evidence currency, not code quality.** That
is the part worth carrying forward:

- **I validated a reason map producer-outward, twice, and it was wrong twice.**
  Round 1 missed `profile_released`; round 2 missed the gateway's own dispatch
  wrapper. Walking outward from functions you already know about structurally
  cannot see a producer you are not thinking of. It is now built
  **consumer-inward** — enumerate everything that can arrive on the wire, then
  account for each — and `TEST_PLAN.md` P-3 enforces it from disk.
- **I captured gate artifacts mid-edit and reasoned forward arithmetically.** An
  artifact certifies the code that existed when it was captured and nothing
  later. The 3,574 figure in round 3 was derived (46+5), never observed.
- **A test whose assertions are its own literals cannot fail.** Eleven such
  assertions inflated the count while covering nothing. Deleting them moved the
  total *down*, which was the correct direction.
- **Sizing a child to fit its own contents is half a layout check.** The card fix
  made the card fit its contents and pushed it 9px outside the panel.

### 8.3 A free-2× vault exploit, and then a worse regression

`ClaimVault` took a boolean from the client, validated only that it *was* a
boolean, and doubled the payout. **Anyone sending `true` took 2× their vault
cash, free, every claim** — and what was being given away is exactly what
`OfflineX2` sells for Robux.

**My fix for it introduced something worse.** It gated the multiply on the
client's flag but the consume on the boost, and the only shipped caller passes
`false`. So a player bought the product, collected 1×, and **the boost was
destroyed**. The exploit gave value away; the regression took money and gave
nothing. Caught by the sweep the same day, fixed at `67c8e84`.

The rule now written at the site: **apply and consume must share one condition.**
The tests missed it because they only claimed with `doubled = true` — the one
value no real caller uses.

`OfflineX2` also had no `durationSeconds`, so it fell back to 900 seconds: buy
"double your next offline collection", go offline eight hours, return to a boost
that expired fifteen minutes after purchase. **It could not have paid out once.**

### 8.4 THE SWEEP — the picture the roadmap was planned against was wrong

Two operator reports ("risk not working dynamically", "streak has no usecase")
were both correct, and the sweep behind them found far more. **Full register with
file:line and failure scenarios is `docs/ROADMAP.md` §12.** Headlines:

**The two worst are on the forge, and they compound.** `V7ForgePanel` reads
`NetClient.forge`'s **`Result` table as a tuple**, so `ok` is always truthy and
the panel prints **“CALIBRATED” on every refusal** — a false economic receipt on
the game's core screen. And **forging is permanently impossible on D7 and D14**:
their stored budget is 59.997 / 59.990 (the per-face share is snapped to 3dp)
while the client always submits exactly 60, which exceeds the 0.001 epsilon. So
a D14 owner forges, is told it worked, and nothing ever changes. Measured in a
running game; the other ten shapes are exact and unaffected.

**Five more CRITICAL on the server:**

1. **Ascension deletes Gems**, which are sold for Robux. Not on FR-9.1's reset
   list, not mentioned on the confirm screen FR-9.4 requires.
2. **The `+2 Die Slots` gamepass grants 4** — the mid-session path never writes
   the idempotency counter the join-time grant relies on.
3. **Ascension permanently kills the Cash mass-budget path.** `MassBudget` is not
   reset while the dice are, so after one ascension the upgrade refuses forever
   at max level. The entire Cash half of FR-3.6 is dead for the life of the
   account.
4. **The login reward mints on repeat** when profile writes fail — the credit runs
   unconditionally after an unchecked write.
5. **NaN permanently poisons a balance.** No reconcile guard repairs a
   non-number currency field, and NaN passes every downstream check.

**Three shipped features are inert:**

- **All three leaderboards are permanently empty.** `updatePlayer` has zero
  production callers. The BOARDS panel — documented as done and live — renders
  empty to every player, forever, and every competitive record is lost.
- **`Upgrades.Luck`** is sold for ~$23.7M and read by nothing.
- **The Starter Bundle** is computed on every snapshot and rendered nowhere.

**The two operator reports, quantified:**

- **RISK** reads `state.dice[1]` only — so forging any other die never moves it,
  *and* it is the wrong quantity. The streak breaks if **any** die voids, so at
  the 12-slot cap the HUD says "33%" while the real risk is **99.2%**.
- **The streak** is inert until `StreakStrength` is bought, and the design's own
  cliff (`b ≈ 0.15`, the point the pre-code simulation was built around) costs
  **8,730 Diamonds ≈ 9 trillion-dollar ascensions.** Not a code defect — a
  balance decision.

**Landmines for the planned phases**, which change the estimates:

- A **new currency** touches **23 sites**, and because reward tables are typed
  `EconomyService.Currency`, widening the union makes the broken Diamond
  fallthroughs **compile silently**. The type system will hide this.
- A **new per-die field** must be added in six places, and **three of them delete
  it** — `performSetShape` and `repairDie` rebuild the die as a four-field
  literal, so traits would survive until a player's first shape change.
- **Element unlocks cannot copy what the roadmap says to copy** —
  `ElementCatalog` has no cost, ladder, prerequisite or currency at all.
- **Daily Spin needs server work** the roadmap does not budget: the snapshot
  carries no spin state and the handler discards the outcome.

### 8.5 Corrections to this document's own earlier sections

- **§1 said 3,565 assertions.** The live figure was **3,569** and the scoreboard
  independently said so. Corrected. This matters because the assertion count is
  the project's staleness canary — a baseline four low disarms it.
- **§3 item 10 said the dead files are "required by nothing."** False:
  `tests/ClientContract.test.luau` requires three of the four in two places, and
  deleting them without editing it turns the suite red.

### 8.6 What is still open

**Everything in `docs/ROADMAP.md` §12**, none of which is fixed except the
`67c8e84` regression.

**Round 1 is now complete** — all three sweeps in, client findings included above
and in full at `docs/ROADMAP.md` §12.8. The client sweep also found the SHAPES
equip button is dead (a cross-closure nil global), the quests panel is permanent
mock data advertising an invented “+$2,500 CASH” reward, the MULT chip overstates
by orders of magnitude past streak 50, and **nothing in the client subscribes to
`onNotice`**, so every enumerated server refusal is fired into nothing.

**A deeper round 2 was started and deferred by the operator.** Round 2 was to
independently re-verify every claim and dig into element resolution across dice,
forge mass validation, auto-roll lifecycle, and rate-limiter token maths.

**Still blocked on the operator, unchanged:**

- **P-1 static analysis** — never produced for any change this session. No Luau
  analyzer on PATH, pane not script-readable. `TEST_PLAN.md:45` makes a missing
  P-1 a rejected gate, so **Gate 2 is not clean on any Phase 0 item** — recorded
  on the scoreboard rather than waived.
- The `Vendor/ProfileStore.luau` warning policy, 9 audio IDs, a real `GROUP_ID`.

### 8.7 Notes for whoever is next

- **`execute_luau` holds its own module cache (L-022).** A Server-context script
  cannot see the live player's profile. Several things this session could only be
  proven by unit test plus a source check of the running server, not by watching
  the game — and that limit was stated rather than papered over.
- **Rojo detached silently for the whole first half of the session** and
  reconnected later. Every file was hashed on both sides before every run. It
  also **cannot inject a *new* file while Play is running** — the first run of a
  new suite reported nothing at all, because an absent suite is silent rather
  than failing.
- **A green suite is not proof.** Two of this session's worst defects — the
  `doubled=false` regression and the tautological test — passed a green suite.
- **When a number and a screenshot disagree, the screenshot wins.** Still true;
  the layout overflow was found by measuring the live game, not by arithmetic.
