# Dice Forge — the road to launch

**Written:** 2026-08-23. **Against HEAD `0f7a3c7`.**
Supersedes the scattered "still open" lists in `docs/handoff-1.md` through
`docs/handoff-7.md`, which are consolidated here.

This document is written in plain English on purpose. Every technical term gets
explained where it first appears, and every item has a worked example of what the
player actually experiences. If you are reading this in six months and cannot
tell what an item means, that is a defect in this document — fix it.

---

## 1. WHERE THE GAME ACTUALLY IS

The UI revamp is finished. All eight menu panels are redesigned, connected to
live data, and verified in a running game. The dice, the forge, the roll loop,
the economy, persistence, leaderboards, quests and the vault all work.

What stands between this and a launch is a list of **ten things that were started
and never finished**, found by a full-repository audit on 2026-08-23. They fall
into three kinds, and the difference matters:

1. **Things that take money and give nothing back.** Not "missing" — actively
   wrong, in the live game, right now.
2. **Things that are fully built but have no button.** The code works; nothing
   calls it.
3. **Things that are decoration.** They look like features and have nothing
   behind them at all.

### The ten items

| # | Item | Kind | Verdict |
|---|---|---|---|
| 1 | REDEEM code button does nothing | No button (inverse) | Fix — one line |
| 2 | Element unlocks impossible | No button | Build |
| 3 | MassCeiling / SlotNodes charge Diamonds, do nothing | Takes money | Fix first |
| 4 | Luck Boost / Offline 2x charge **real Robux**, do nothing | Takes money | Fix first |
| 5 | Group Rewards inert (`GROUP_ID = 0`) | Blocked on operator | Set the ID |
| 6 | Like Goal event never built | Decoration | **Dropped** |
| 7 | Daily Spin has no UI | No button | Build |
| 8 | Audio — 9 placeholder asset IDs | Blocked on operator | Upload sounds |
| 9 | Trait Forge — pure decoration | Decoration | Build |
| 10 | ~3,500 lines of dead legacy files | Housekeeping | Delete |

---

## 2. THE GOVERNING RULE: BUILD THE UI ONCE, THEN NEVER DISTURB IT

**All screens get finished and frozen first. Then backend work only.**

This is the operator's decision and it is the correct one. It is worth writing
down *why*, because the reasoning is the most valuable thing in this document.

The alternative — port a screen now, come back for another feature later, reopen
the same panel a third time — is precisely how this codebase broke. The project's
own failure log records the cause in one sentence:

> *"The visual layer was rebuilt and the wiring behind it was not re-checked."*

That single pattern accounts for the worst incident in this project's history: a
UI pass left four data-refresh functions as empty stubs and every menu panel
silently stopped receiving data. Nobody noticed, because a panel that renders
perfectly and shows stale numbers looks exactly like a panel that works.

Touching each panel exactly once eliminates that entire class of failure. Not
reduces — eliminates, because the failure requires a second visit to exist.

### The freeze rule

Once a screen is signed off:

- **Allowed:** connecting a button to a real function; replacing a placeholder
  value (`"--"`, `"◆ -- SHARDS"`) with a real one.
- **Not allowed:** moving, resizing, restyling, or re-laying-out anything.
- **If wiring genuinely cannot be done without a visual change: stop and ask the
  operator.** Do not decide unilaterally.

---

## 3. WHO DOES WHAT

Two AI workers, split along their demonstrated strengths.

### Antigravity — visuals only

Strong at visual design. Weak at wiring. This is not a guess; it is the git
history. Its past runs produced good-looking panels and broke the game by
rebuilding a panel's appearance without re-checking the code behind it — six
separate documented ways, recorded in `docs/antigravity_ui_redesign_prompt.md`.

So it gets **mock previews only, never live files, one panel per run.** The
one-panel rule exists specifically because it broke things by over-reaching.

### Claude — everything that touches logic

Server code, remotes, profile schema, currency, wiring buttons to real functions,
and porting Antigravity's approved mocks into the live panels.

### Only two new screens exist in this entire roadmap

Everything else is already drawn. This is worth internalising before planning any
work — the instinct that "a new feature needs a new screen" is wrong here three
times out of four.

| Feature | Needs a new screen? |
|---|---|
| Element unlocks | **Yes** — a place to buy them |
| Daily Spin | **Yes** — one control |
| Trait Forge | No — panel is fully drawn already |
| All of Phase 0 | No — pure backend |

---

## 4. PHASE 0 — STOP CHARGING FOR NOTHING

**Starts immediately. Pure backend, touches no screen**, so it does not conflict
with the UI-first rule and runs in parallel while Antigravity designs.

This phase is first because everything in it is a live defect that costs players
money or currency today.

### 0a — Boosts do nothing

**What the player sees:** they buy "Luck Boost" or "Offline 2x" with real Robux.
A countdown timer appears and ticks down. It expires. Nothing was ever different.

**What is wrong:** `BoostService.getMultiplier` exists, is correct, and **is
never called by anything.** The purchase is granted, stored in the profile, and
displayed as a timer — the effect is simply never applied.

**Why this is the worst item on the list:** these are real-money purchases with
real Roblox asset IDs. Every other item on this list is an absence; this one is a
transaction that does not deliver.

**The fix is smaller than it sounds.** The hook already exists and is already
guarded against bad values:

- `src/Server/RollService.luau:302` reads `cfg.coinBonus` into the payout line.
- `src/Server/RollService.luau:458` — the call site — passes a hardcoded `1`.

Feed the real boost multiplier in at `:458` instead of `1`. Offline 2x hooks the
equivalent point in `OfflineService`'s claim path.

*Worked example:* buy Luck Boost → today your rolls pay exactly the same as
before → after this, they genuinely pay more until the timer runs out.

### 0b — MassCeiling and SlotNodes charge Diamonds and do nothing

**What the player sees:** they spend Diamonds on "Mass Budget Ceiling" or "Die
Slot Expansion". The level goes up. The number displays correctly. Nothing about
their dice or slots changes, ever.

**What is wrong:** verified by grep — `Diamond.MassCeiling` and
`Diamond.SlotNodes` each have **exactly one read in the entire codebase**, in
`StateSyncService`, purely to echo the number back to the client for display.

- The real mass ceiling is `SHARED_DIAMOND_CEILING`, a flat per-shape constant in
  `DiceCatalog.luau`.
- The real slot cap is `DiceCatalog.dieSlotCapFor(ascensions)` — a function of
  ascension count only.

Neither ever consults the node level the player paid for.

**The fix:** MassCeiling must raise the per-die budget cap; SlotNodes must add to
`dieSlotCapFor`. Both need the node level threaded into a calculation that
currently ignores it.

### 0c — The REDEEM button has no click handler

**What the player sees:** a normal-looking text box and a gold REDEEM button in
Settings. Typing a code and clicking does nothing at all. No error, no feedback.

**What is wrong:** `redeemBtn` is built, styled and parented at
`src/Client/V7MenuPanel.luau:3351` — and has no `MouseButton1Click` connection
anywhere in the file.

Everything behind it works: `NetClient.redeemCode`, the server `RedeemCode`
handler, a real promo-code catalog, duplicate-redemption tracking, and profile
persistence. Somebody built the whole feature and never connected the button.

**The fix:** one handler. This is the highest value-for-effort item in the
document.

### Verification for Phase 0

Buy each item in a running Studio session and confirm the number actually moves.
Full test suite green. Reuse the in-flight/disabled-during-request pattern the
vault buttons already use.

---

## 5. PHASE 1 — ALL UI, FINALISED AND FROZEN

Antigravity's phase. Runs in parallel with Phase 0.

### 1a — Element unlock section (goes in the Shapes panel)

**The situation:** the game has four elements — Fire, Freeze, Gold, Multiplier —
with fully built, fully tested payoff mathematics. Fire spills value onto other
dice; Gold pays when multiple dice land Gold; and so on.

**No player can ever use any of them.** `Diamond.Elements` is read to check
whether an element is unlocked, and **nothing anywhere ever sets one to
unlocked.** Every player is permanently stuck on plain faces.

**Critical scope note — this must be in the prompt.** *Applying* an element is
already fully built. `src/Client/V7ForgePanel.luau` already draws an element chip
on each face, cycles it on click, and already reads which elements are unlocked
from `diamondTree.Elements` (`:1379`). **Only the "buy the unlock" step is
missing.** The mock must not redesign the Forge panel's existing chips.

**Why the Shapes panel:** it already handles "unlock a thing with currency" for
dice shapes. Players learn one pattern instead of two, and Antigravity extends a
panel it has already redesigned and knows.

### 1b — Daily Spin

**The situation:** the remote, the server handler
(`ProgressionService.claimDailySpin`) and the client wrapper
(`NetClient.dailySpin`) all exist and work. There is no button anywhere in the
game that calls it. Not even a disabled placeholder.

Needs one control. Small.

### Sequencing hazard — read before starting

Antigravity's prompt instructs it to **overwrite `UIMockPreview.luau` wholesale**
on each run. The Elements mock will therefore be destroyed the moment the Daily
Spin run begins.

**Port and commit Elements before releasing the second prompt.**

### Exit condition

Both mocks approved by the operator, ported into the live panels, screenshotted,
committed. **From this point the UI is frozen** and section 2's freeze rule
applies to everything after.

---

## 6. PHASE 2 — BACKEND ONLY, AGAINST FROZEN UI

No visual work from here. Every item fills an already-existing screen with real
behaviour.

### 2a — Element unlocks

Copy the shape-unlock path that already works. `BuyDiamondNode` has a branch
(`src/Server/ServerBootstrap.server.luau:348-379`) that checks an unlock ladder,
spends currency, and writes `Diamond.Shapes[id] = true`.

Elements need the identical branch writing `Diamond.Elements[id] = true`. The
read side (`src/Server/ForgeService.luau:506`) already exists and is waiting.

*Worked example:* unlock Fire → open the Forge → the Fire chip on a face is no
longer greyed out → apply it → your payouts change.

### 2b — Daily Spin wiring

Connect the control from 1b to the working backend. Small.

### 2c — Trait Forge

The largest single item, and it needs **no new UI at all** — the panel is fully
drawn in the Slots overlay, and one central switch
(`setTraitControlInert`, `src/Client/V7MenuPanel.luau:3938`) currently disables
every control in it. Un-inerting is therefore centralised in one place.

**Today it is pure decoration.** There is no trait or shard concept anywhere in
`src/Server/` or `src/Shared/` — no schema field, no remote, no catalog, no test.

**The good news:** the hardest part is already prepared. The payout line has a
spare multiplier slot (`coinBonus`) that is declared, guarded, and currently
hardcoded to `1` — the same seam Phase 0a uses.

**Build order:**

1. **`src/Shared/TraitCatalog.luau`** — copy `ElementCatalog`'s structure exactly
   (id union, definition table, accessors, `math.huge` cost sentinel).
   **Must be in `src/Shared/`, not server-only.** The client reads trait names,
   rarities and costs from it directly, because sending those over the wire would
   break the no-figures-on-the-wire rule (NFR-5).
2. **Shards currency** — see the trap in section 8.
3. **Per-die trait storage** — see the trap in section 8.
4. **Shard earning** — a trickle on rolls, a lump sum on ascension.
5. **`RerollTraits` remote** — six files must agree; see the trap in section 8.
   A reroll is a random, value-bearing action, so it must be decided by the
   server: reuse the per-session server-seeded `Random` and
   `ForgeMath.sampleFace`'s weighted-sampling shape. Never let the client pick.
6. **Un-inert the controls** via the single existing seam.

---

## 7. PHASE 3 — CLEANUP AND LAUNCH READINESS

### Housekeeping (no UI impact)

- **Delete dead files.** `ForgePanel.luau`, `MenuPanel.luau`, `HUD.luau`,
  `CurrencyModels.luau` — roughly 3,500 lines superseded by their `V7*`
  replacements, required by nothing, loaded by nothing. They actively mislead
  searches, which cost real time during this audit.
- **Remove the dropped Like Goal's leftovers** — the dead `EventState` remote and
  the client's progress bar that reads fields no snapshot ever contains.
- **Script Analysis to zero** (NFR-8). 158 pre-existing warnings. Decide the
  `Vendor/ProfileStore.luau` policy *first* — it is 2,242 lines of third-party
  code and editing it would be clobbered by any upstream update. It needs a
  policy (`--!nonstrict`, or exclusion from analysis), not edits.

### Blocked on the operator — cannot be done in code

- **Audio — 9 placeholder asset IDs** (`DUMMY_ID_*` in `AudioDirector.luau`).
  The game is completely silent. This is handled *correctly*: it fails closed, no
  Sound instance is ever created, and the Settings panel already shows Music and
  SFX as **LOCKED** rather than pretending they work. It needs real uploaded
  Roblox asset IDs and nothing else.
  *(Correction to the record: `docs/handoff-7.md` states 23. The real count is 9,
  verified by direct grep. Handoffs 1–6 all correctly said 9.)*
- **Group Rewards — `GROUP_ID = 0`.** Fully built and correct
  (`ProgressionService.isInGroup` / `claimGroupReward`, real `IsInGroupAsync`
  check). Deliberately inert: zero fails closed by design, and the remote
  registration is commented out in `ServerBootstrap` with a note reading
  "UNPLUGGED... not deleted". Set a real group ID and uncomment two lines.

---

## 8. THE THREE TRAPS

These are recorded because each one fails **silently**. None produces an error at
the point of the mistake.

### Trap 1 — the currency fallthrough

`EconomyService` deliberately uses one explicit branch per currency rather than a
computed lookup, and the file explains why at length: it is the sole writer of
currency, and the explicit branches are the complete auditable list of every
field it can touch.

**The trap:** the final `else` in both `readBalance` and `writeBalance` returns
**Diamonds**. Add `Shards` to the type union but forget a branch, and Shards will
silently read and write the player's *Diamond* balance.

**Also:** no test currently pins the currency list. Nothing fails when a currency
is added incorrectly. **Add that test as part of the work.**

### Trap 2 — per-die data and the reconcile loop

Traits attach to individual dice (operator's decision). `Profile.Dice` is an
**array**, and the profile reconcile logic deliberately never descends into
arrays — the guard is load-bearing, because descending would overwrite each
player's dice with the starting template.

**Consequence:** a new field added to a die record would be `nil` forever on every
existing save. It needs an explicit entry in the per-die loop at
`src/Server/PlayerProfile.luau:325`, following the `PurchasedBudget` precedent
directly above it.

**No `SchemaVersion` bump is needed** — that mechanism is only for shape changes
reconcile cannot handle. Additive keys are handled by reconcile itself.

### Trap 3 — the remote contract

Adding a remote requires **six files to agree**: the name registry, the arity
table, the rate limiter, the server handler, the client wrapper, and the docs.

`tests/RemoteContract.test.luau` fails loudly if any is missed. **This is
intended behaviour, not an obstacle** — it was written after a real incident
where three files had to agree and nothing pinned the middle one.

---

## 9. DECISIONS ON RECORD

Made by the operator during planning on 2026-08-23:

| Decision | Choice |
|---|---|
| Broken purchases | **Fix them properly**, not hide or disable them |
| Features to build | Element unlocks, Daily Spin, Trait Forge |
| Like Goal | **Dropped** — cut, not deferred |
| Trait scope | **Per-die** (each die carries its own traits) |
| Shard source | **Both** rolling and ascending |
| Element unlock location | **Shapes panel** |
| Work split | Antigravity visuals only; Claude all logic |
| Antigravity batching | **One panel per run** |
| Sequencing | **UI first, freeze, then backend** |
| UI freeze strictness | Wiring only; **ask before any visual change** |

### Why Like Goal was dropped

A 3× Cash event triggered when the experience hits a real like-count milestone
(SRS FR-10.7). It needs live Roblox like-count integration, and **fabricating the
number is barred by project rule** — a governance audit flagged it explicitly as
"must show the real platform like count or nothing."

It was specified, flagged as unbuilt, tracked for one handoff, then silently
dropped from every subsequent one. This document ends that ambiguity: it is
**cut**, and its leftovers are removed in Phase 3.

---

## 10. VERIFICATION STANDARD FOR EVERY PHASE

- Full `tests/*.test.luau` suite green in Studio. **Watch the assertion count**
  — a count that drops means assertions stopped running, which looks identical to
  a pass in the summary line.
- Script Analysis: **zero new** warnings against the 158 baseline.
- **Proven in a running game, not by reading code.** This is not ceremony: the
  previous session found two real defects in a running session that a
  fresh-context code audit had already passed.
- Fresh-context audit before each commit. The author never verifies their own
  work.
- **Phase 2 onward:** confirm by screenshot that the frozen UI is unchanged.

---

## 11. CRITICAL FILES

| File | Why it matters here |
|---|---|
| `src/Server/RollService.luau` | The payout seam — `coinBonus` at `:302`, hardcoded `1` at `:458` |
| `src/Server/EconomyService.luau` | Currency branches; mind the Diamonds fallthrough |
| `src/Server/PlayerProfile.luau` | Schema and the per-die reconcile loop at `:325` |
| `src/Server/ServerBootstrap.server.luau` | Remote handlers; the shape-unlock branch to copy at `:348-379` |
| `src/Server/ForgeService.luau` | Element read side already waiting at `:506` |
| `src/Client/V7ForgePanel.luau` | Element chips already built; reads unlocks at `:1379` |
| `src/Client/V7MenuPanel.luau` | REDEEM at `:3351`; trait inert-switch at `:3938` |
| `src/Shared/TraitCatalog.luau` | New — model it on `ElementCatalog.luau` |
| `tests/RemoteContract.test.luau` | Fails by design on a half-added remote |
| `docs/antigravity_ui_redesign_prompt.md` | The prompt Antigravity runs; keep its status register current |
