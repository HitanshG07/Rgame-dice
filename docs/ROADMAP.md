# Dice Forge — the road to launch

**Written:** 2026-08-23. **Against HEAD `0f7a3c7`.**
Supersedes the scattered "still open" lists in `docs/handoff-1.md` through
`docs/handoff-7.md`, which are consolidated here.

This document is written in plain English on purpose. Every technical term gets
explained where it first appears, and every item has a worked example of what the
player actually experiences. If you are reading this in six months and cannot
tell what an item means, that is a defect in this document — fix it.

---

## 0. READ §12 FIRST

**A full-repository bug sweep on 2026-08-27 found defects more urgent than
anything in the phases below.** Five are CRITICAL — two destroy things players
paid Robux for, one permanently kills a progression path, one mints currency, and
one poisons a balance beyond in-game recovery. Three whole shipped features turn
out to be inert.

**The two worst are on the forge — the game's core screen.** It reports
“CALIBRATED” on *every* refusal (the result table is read as a tuple, so the
success branch is unconditional), and forging is **permanently impossible on D7
and D14** because their stored budget is 59.997 / 59.990 while the client always
submits 60. Together: a D14 owner can forge all day, be told it worked every
time, and never change a thing.

**Phase 1 should not start until §12.2 and §12.8 are triaged.** §12.9 gives the
ordered fix list. The phases in this document
were planned against a picture of the codebase that the sweep has since
corrected.

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

**The Status column is the live record.** It is updated only at a G5 DELIVERED
verdict — see §10b for exactly what that means and what else to update with it.

| # | Item | Kind | Verdict | Status |
|---|---|---|---|---|
| 1 | REDEEM code button does nothing | No button (inverse) | Fix — one line | **DONE** — see §4/0c (P-1 outstanding) |
| 2 | Element unlocks impossible | No button | Build | OPEN |
| 3 | MassCeiling / SlotNodes charge Diamonds, do nothing | Takes money | Fix first | **DONE** — see §4/0b |
| 4 | Luck Boost / Offline 2x charge **real Robux**, do nothing | Takes money | Fix first | **DONE** — `6cb6aa1`, plus a free-2x vault exploit found in the same seam |
| 5 | Group Rewards inert (`GROUP_ID = 0`) | Blocked on operator | Set the ID | BLOCKED — operator |
| 6 | Like Goal event never built | Decoration | **Dropped** | CLOSED — dropped, see §9 |
| 7 | Daily Spin has no UI | No button | Build | OPEN |
| 8 | Audio — 9 placeholder asset IDs | Blocked on operator | Upload sounds | BLOCKED — operator |
| 9 | Trait Forge — pure decoration | Decoration | Build | OPEN |
| 10 | 3,662 lines of dead legacy files | Housekeeping | Delete | OPEN |

---

## 1b. ONE SPEC ROW HAS DRIFTED FROM THE CODE

Found on 2026-08-26 by sweeping handoffs 1–7 against live code. It is not one of
the ten items and it is not a feature — it is a **contradiction between the
binding spec and what ships**, which this project treats as a defect rather than
a document to quietly correct.

**`docs/blueprint/SRS.md:15` (FR-1.1)** says the arena holds *"between 1 and 7
dice"*. The code ships `DiceCatalog.MAX_DIE_SLOTS = 12` (`:386`) with a nine-rung
ascension ladder up to it. The row was never amended, and no test pins the 7.

**Operator decision (2026-08-26): amend the spec to 1–12.** The 12 was a
deliberate balance decision recorded in handoffs 5 and 7, and the game has been
played at 12 — the code is right and the document is stale. Amend FR-1.1 citing
that as the triggering fact, per the SRS's own `STATUS: LIVING` rule.

**Do this before any other work.** Every later phase is audited against the spec,
and an auditor reading FR-1.1 as it stands today would correctly reject work that
assumes twelve slots.

*Related, and not a blocker:* handoff-4 records that die counts other than 1, 6
and 7 have never been checked by eye on a live board, and **FR-1.4 — no die may
come to rest outside the tray — is the one hard invariant** the arena must hold.
Worth one look at a full twelve-die board during the next play session.

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

**Execution order (operator decision, 2026-08-26): `0c` → `0a` → `0b`**, which is
not the order they are written in below. The sub-items keep their labels so
existing references stay valid.

The reason: `0c` is a single click handler against a backend that already works
end to end. It is the smallest change that can walk all seven gates, so it proves
the pipeline on something low-risk **before** anything touches the payout formula.
`0a` follows because it is the only defect involving real money. `0b` is last
because it is the only one of the three that moves a balance number, and it needs
a proposed curve brought to the operator before it is built.

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

- `src/Server/RollService.luau:303` reads `cfg.coinBonus` into the payout line.
- `src/Server/RollService.luau:473` — the call site — **now feeds the real
  multiplier** (was a hardcoded `1` at `:458` before the line numbers moved).

Feed the real boost multiplier in at `:458` instead of `1`. Offline 2x hooks the
equivalent point in `OfflineService`'s claim path.

*Worked example:* buy Luck Boost → today your rolls pay exactly the same as
before → after this, they genuinely pay more until the timer runs out.

**DONE 2026-08-27 (`6cb6aa1`).** Both boosts now reach a number. Three things
were wrong, not one:

1. **Nothing called `getMultiplier`.** The seam was already there and already
   guarded; the call site just passed `1`.
2. **A live exploit sat in the same seam.** `ClaimVault` took a boolean from the
   client, checked only that it *was* a boolean, and doubled the payout — so
   anyone sending `true` took 2× their vault cash, free, every claim. What was
   being given away is exactly what `OfflineX2` sells for Robux. One fix closed
   both: the flag is now a *request*, and the server prices it from the player's
   actual boost.
3. **`OfflineX2` could never have paid out.** It had no `durationSeconds`, so it
   fell back to 900 seconds — buy it, go offline for eight hours, come back to a
   boost that expired fifteen minutes after purchase. It is one-shot by its own
   wording, so it now has a seven-day window and is spent by the claim.

Luck Boost had to be a **payout** multiplier rather than a real luck one:
biasing the sampling would break FR-3.4, because the forge preview must show
exactly the maths that pays you. The shop blurb was corrected to match — a
real-money product must not be sold on a false claim.

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

**DONE 2026-08-27.** Both nodes now move the thing they charge for.

**MassCeiling: +80 per level, 300 → 1500** (operator decision). This is FR-3.6's
second half, which had never been built: *"purchased with Cash up to a per-shape
cap, and beyond that with Prestige Diamonds."* The Cash half worked and stopped
at 300; the Diamond half stored a level and did nothing. Fifteen levels × 80
spans exactly the gap to the existing 1500, so **no new numbers were invented —
the flat 1500 stops being everyone's default and becomes the reward for maxing
the tree.** Buying a level also *grants* the mass, mirroring the Cash handler,
because raising a ceiling nobody can reach is still nothing.

**SlotNodes: +1 slot per level** (operator decision, after seeing the real
numbers). The instinct was to slow it down — but the cost curve already does
that work: the four levels run 50 / 200 / 800 / 3,200 Diamonds, and a
*billion-dollar* ascension pays 31. The fourth slot is on the order of a hundred
ascensions away. `MAX_DIE_SLOTS` still hard-clamps the total, so this reaches the
same ceiling sooner and can never break FR-1.1.

**Nothing can be confiscated, by construction.** The per-player ceiling gates
*purchases* only; die validation still uses the absolute bound. A die bought
under the old flat 1500 with node level 0 keeps every gram — it simply cannot buy
more until the tree catches up. That is the rule `AddDieSlot` already followed:
refuse new purchases, never take back what was bought.

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

**DONE 2026-08-27.** A player can now type a promo code, click REDEEM, and
actually receive the reward — with an honest message on every outcome, including
the ones that previously showed nothing at all.

*It cost three audit rounds and eight defects, on the smallest item here.* Worth
recording why, because the lessons generalise:

- **The refusal map was built producer-outward twice and was wrong twice.**
  Walking out from the functions you already know about cannot see a producer you
  are not thinking of — first `PlayerProfile.mutate`, then the gateway's own
  dispatch wrapper. It is now built **consumer-inward** (enumerate everything that
  can arrive on this wire, then account for each), and `TEST_PLAN.md` P-3 enforces
  it from disk.
- **Sizing a child to fit its own contents is half a layout check.** The first fix
  made the card fit its contents and pushed the card 9px out of the panel.
- **A test whose assertions are its own literals cannot fail.** 11 such
  assertions inflated the count and covered nothing; deleting them moved the
  total DOWN, which is the correct direction.
- **An artifact certifies the code that existed when it was captured.** Two
  rounds failed on evidence captured mid-edit and then reasoned forward
  arithmetically — not on code quality.

**One thing is still outstanding and needs the operator:** P-1 static analysis
was never produced. No Luau analyzer exists on PATH and the Script Analysis pane
is not script-readable, so this is a standing blocker on every Gate 2 here.

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

### 1c — Active-boost timer (operator request, 2026-08-27)

**What the operator asked for:** a proper on-screen indicator showing **which
boost is running and how long is left**, as a real countdown, in the bottom-left
or bottom-right corner, with proper icons.

**To be built later. What matters now is that it is READY TO WIRE, and it is.**

*Worked example:* buy Luck Boost → a small icon appears in the corner reading
`2× PAYOUT — 14:32` → it ticks down every second → at zero it disappears on its
own.

**The backend is already done. No server work is needed for this.**

- `StateSyncService` already ships `state.boosts` on **every snapshot**, shaped
  `{ [kind] = expiryUnixTime }` — e.g. `{ LuckBoost = 1756300000 }`.
- **Only running boosts are listed.** An expired one is simply *absent* rather
  than sent as expired, because absent is the state the panel should draw. So
  the UI never has to decide whether something has lapsed.
- **Nothing on the client reads it yet.** The single mention in the repo is a
  stale comment in `ForgePanel.luau`, which is one of the dead legacy files
  Phase 3 deletes. This is a clean greenfield hookup.

**Two constraints the builder must respect:**

1. **Expiry TIMES cross the wire, never multipliers** — that is deliberate
   (NFR-5). The client must never be told what a boost is *worth*. If the icon
   needs to say "2×", it reads that from `MonetisationCatalog`, which is in
   `src/Shared/` precisely so the client can look up names and amounts locally
   without a figure being sent to it.
2. **Count down from the server's timestamp, not from a local timer.** Subtract
   `os.time()` from the expiry each frame. A client-side stopwatch started at
   purchase would drift, and would keep running through a rejoin.

**Icons:** draw them with `UITheme.createProgrammaticIcon` rather than using an
emoji — an emoji is a font fallback and renders differently per platform.

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

**This is L-027, and the code already says so.** The comment directly above the
branch you are copying (`src/Server/ServerBootstrap.server.luau:347`) reads: *"the
requirement was specified (FR-9.3), the READ was implemented, and the WRITE was
missing — ledger L-027 exactly."* Shapes had this identical defect and it was
fixed there; Elements is the same bug in the same shape, one field over.

L-027's lesson is that **a read with no writer is invisible** — there is no file
to open and nothing fails, because nothing is listening. The only check that can
see it is a sweep in the *producer* direction (see §10).

*Worked example:* unlock Fire → open the Forge → the Fire chip on a face is no
longer greyed out → apply it → your payouts change.

### 2b — Daily Spin wiring

Connect the control from 1b to the working backend. Small.

### 2c — Trait Forge

The largest single item, and it needs **no new UI at all** — the panel is fully
drawn in the Slots overlay, and one central switch
(`setTraitControlInert`, `src/Client/V7MenuPanel.luau:4133`) currently disables
every control in it. Un-inerting is therefore centralised in one place.

**Today it is pure decoration.** There is no trait or shard concept anywhere in
`src/Server/` or `src/Shared/` — no schema field, no remote, no catalog, no test.

**The good news:** the hardest part is already prepared. The payout line has a
multiplier slot (`coinBonus`) that is declared, guarded, and currently hardcoded
to `1`.

**But it is one scalar, not two — and Phase 0a gets there first.** By the time
this phase runs, 0a has already fed the boost multiplier into that slot, so you
will find it occupied rather than free. This is fine: multipliers compose, so
combine the two into the value passed at `:458` rather than replacing what 0a
put there. Expect it, and do not read the occupied slot as a mistake.

**Build order:**

1. **`src/Shared/TraitCatalog.luau`** — copy `ElementCatalog`'s structure for the id union, definition table and
   accessors — but **NOT its cost model, because it has none.** `ElementCatalog`
   carries no cost, ladder, prerequisite or currency at all. The `math.huge`
   sentinel is in `UpgradeCatalog.luau:118`; copy it from there (§12.5).
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

- **Delete dead files, and remove the Like Goal leftovers in the same step.**
  `ForgePanel.luau`, `MenuPanel.luau`, `HUD.luau`, `CurrencyModels.luau` — **3,662
  lines** superseded by their `V7*` replacements. They actively mislead searches,
  which cost real time during this audit.

  **They are NOT "required by nothing" — that claim was wrong.** Three of the four
  are required by the test suite:

  - `tests/ClientContract.test.luau:104-106` names `HUD`, `ForgePanel` and
    `MenuPanel` in its `VIEW_MODULES` list.
  - `tests/ClientContract.test.luau:162` names the same three again in the
    `shutdown()` check.

  That suite **fails loudly when a named module is missing** — that is its stated
  purpose, not a bug. Deleting the files without editing the test turns a green
  suite red, against this document's own verification standard. Only
  `CurrencyModels.luau` (81 lines) is genuinely unreferenced.

  **Do the L-028 check before deleting anything.** L-028 is *"Deleting a Module
  Deletes Its Undocumented Duties Too"* — written when `ArenaView.luau` was
  removed after a dependency sweep found all six call sites, and the board then
  rendered with the baseplate, skybox and the player's own avatar in frame. The
  duty that broke had no export and therefore **no grep signature**. All three
  panels here contain references to `Workspace` / `Lighting` / `CurrentCamera` /
  `GetService`, which is exactly the signature L-028 says to check. For each file,
  enumerate what it touches outside itself and either reassign the duty or drop it
  consciously — recorded either way in the commit.

  **Order matters, because these two items overlap.** The Like Goal progress bar
  lives *inside* `HUD.luau`. Delete first, and it goes with the file; do it the
  other way round and you hunt leftovers that are already gone. After the
  deletion, the only surviving Like Goal residue is the `EventState` remote at
  `src/Shared/Remotes.luau:30` and `:68`, and its client subscriber at
  `src/Client/NetClient.luau:280-281`.
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

Added 2026-08-26, after sweeping handoffs 1–7 against live code:

| Decision | Choice |
|---|---|
| FR-1.1 says 7 dice, code ships 12 | **Amend the spec to 1–12** — the code is right, the document is stale (§1b) |
| Phase 0 execution order | **`0c` → `0a` → `0b`** — smallest change first to prove the pipeline (§4) |
| Marking work complete | **Only at a G5 DELIVERED verdict**, never when the code merely looks finished (§10b) |

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
- **The producer-direction sweep (L-027).** For every field or event the code
  *reads*, grep for what *writes* it. A read with no writer looks exactly like a
  working feature and fails silently — that is how Elements shipped unreachable,
  and `StateSync` before it went unemitted for three whole blocks through five
  audit rounds. Every gate asked *"is what the code does correct?"*; none asked
  *"is everything promised actually implemented?"* The sweep is mechanical and
  cheap, and it is the only check that can see the hole. Run it before launch on
  `Diamond.*`, every remote in `Remotes.luau`, and every field `StateSyncService`
  emits.
- **Proven in a running game, not by reading code.** This is not ceremony: the
  previous session found two real defects in a running session that a
  fresh-context code audit had already passed.
- Fresh-context audit before each commit. The author never verifies their own
  work.
- **Phase 2 onward:** confirm by screenshot that the frozen UI is unchanged.

---

## 10b. CLOSING AN ITEM OUT — MARK IT DONE, AND ONLY WHEN IT IS

**Every item in this document is updated to DONE the moment it lands, and never
before.** An item is not done when the code is written. It is done when it has
passed the full `.brain/PIPELINE.md` sequence and been delivered:

`G0 intake → G1 construct → G2 validate → G3 audit → G4 secure → G5 deliver → G6 evolve`

Until a **G5 DELIVERED** verdict exists, the item stays open in this document
regardless of how finished the code looks. A rejection at G2, G3 or G4 rewinds to
G1 and re-runs G2–G4 **in full** — so a rejected item does not get a partial mark,
it simply stays open.

### What to update, at G5, in the same commit as the work

1. **The item's row in §1** — change the Verdict cell to `DONE — <short-sha>`.
2. **The phase section** — mark the sub-item `**DONE (<short-sha>)**` with one
   line stating what a player can now actually do that they could not before.
3. **`.brain/SCOREBOARD.md`** — append the pipeline run: date, tier, lane,
   rejections (**including none**), and the outcome. Mandatory, and it is where
   the honesty lives; a whitewashed scoreboard voids the audit trail
   (Non-Negotiable 7).
4. **`.brain/LEDGER.md`** — only if the work produced a genuine lesson. At G6,
   *"no evolution required"* is a valid verdict, not an omission.
5. **A handoff** — when the session ends, not per item.

### The rule this exists to enforce

**Do not mark an item done and then keep working on it.** Two of this project's
recorded incidents are exactly that shape: a figure stated once and carried
forward by documents that never re-checked it (handoff-7's "23 audio IDs", and
its "nothing outstanding" while 158 warnings stood open). A roadmap that says
DONE next to something half-finished is the same defect with a bigger blast
radius, because the next session trusts it and builds on top.

Equally: **do not leave a finished item unmarked.** The next reader has no way to
tell shipped work from unstarted work except this document, and re-deriving it
costs a full audit pass — which is how this session's ten-item list got built in
the first place.

### When an item turns out to be wrong

If a completed item is later found defective, **do not silently un-tick it.**
Leave the DONE mark, strike it through, and add a line naming what was wrong and
where it was corrected. The record of a mistake is worth more than a tidy list —
`docs/handoff-8.md` §4 is the precedent.

---

## 11. CRITICAL FILES

| File | Why it matters here |
|---|---|
| `src/Server/RollService.luau` | The payout seam — `coinBonus` read at `:303`, fed from `BoostService` at `:473` (**DONE**) |
| `src/Server/EconomyService.luau` | Currency branches; mind the Diamonds fallthrough |
| `src/Server/PlayerProfile.luau` | Schema and the per-die reconcile loop at `:325` |
| `src/Server/ServerBootstrap.server.luau` | Remote handlers; the shape-unlock branch to copy at `:348-379` |
| `src/Server/ForgeService.luau` | Element read side already waiting at `:506` |
| `src/Client/V7ForgePanel.luau` | Element chips already built; reads unlocks at `:1379` |
| `src/Client/V7MenuPanel.luau` | REDEEM at `:3372` (**DONE**); trait inert-switch at `:4133` |
| `src/Shared/TraitCatalog.luau` | New — model it on `ElementCatalog.luau` |
| `tests/RemoteContract.test.luau` | Fails by design on a half-added remote |
| `docs/antigravity_ui_redesign_prompt.md` | The prompt Antigravity runs; keep its status register current |

---

## 12. THE BUG REGISTER (swept 2026-08-27)

Two operator reports ("risk not working dynamically", "streak has no usecase")
turned out to be real, and a full-repository sweep behind them found a great deal
more. **Nothing in this section is fixed unless it says so.**

Method: three parallel sweeps (server + shared, client, persistence + future-work
hazards), each finding independently re-derived rather than taken on trust, plus
live stress testing in a running game that static reading cannot do. A second,
deeper round was started and **deferred by the operator** — see §12.6.

### 12.0 What is already fixed

| Item | Fix |
|---|---|
| **OfflineX2 consumed without being applied** | `67c8e84` — see below. This was a regression introduced by `6cb6aa1` earlier the same day |

**It is recorded here rather than quietly closed, because it is the most
instructive defect of the session.** The original `ClaimVault` bug gave 2× away
free to anyone who asked. My fix gated the *multiply* on the client's `doubled`
flag but gated the *consume* on `boostMult > 1.0` — and the only shipped caller
(`V7VaultOverlay.luau:671`) passes `false`. So the multiply never ran and the
consume always did: **a player bought a real-Robux product, collected 1×, and the
boost was destroyed.** Worse than the exploit it replaced, because that one gave
value away and this one took money and gave nothing.

The rule now written at the site: **apply and consume must share one condition.**
The tests missed it because they only ever claimed with `doubled = true` — the
one value no real caller uses. Testing the convenient case is what hid it.

---

### 12.1 The two operator reports — both confirmed

#### R-1 — RISK reads only die 1, and understates real risk by up to 66 points

`src/Client/ClientBootstrap.client.luau:219` — `local die = state.dice[1]`.

**Two defects in one line.** It never looks past the first die, so forging dice
2…N does not move the number — that is the "not dynamic" the operator saw. And it
is *mathematically the wrong quantity*: FR-5.1 breaks the streak when **any** die
lands Void, so the real figure is `1 − Π(1 − pᵢ)`, not `p₁`.

Measured with the game's own maths at a typical 33% per-die Void chance:

| Dice | HUD shows | Real risk | Understated by |
|---|---|---|---|
| 1 | 33.0% | 33.0% | — |
| 3 | 33.0% | 69.9% | **36.9 pts** |
| 7 | 33.0% | 93.9% | **60.9 pts** |
| 12 | 33.0% | 99.2% | **66.2 pts** |

At the 12-slot cap the HUD reports "33% risk" while the streak is **99.2% certain
to break**. Players build their entire mass strategy on this number.

*Fix:* compute across every die in `state.dice`. The per-die call is already
correct — only the aggregation is missing.

#### R-2 — The streak does nothing at all until a Diamond node is bought

Working **as specified** (FR-5.4 makes `b` a player investment), but the
consequence is worth stating plainly: `b = StreakStrength × 0.01`, and
`StreakStrength` defaults to **0**, so `(1+0)^streak = 1` forever.

The HUD is honest about it — it shows `--` and `LOCKED` rather than a fake
`×1.00` — but a counter still ticks upward next to it doing nothing.

| Level | `b` | Diamonds (cumulative) | ×at streak 10 | ×at streak 50 |
|---|---|---|---|---|
| 1 | 0.01 | 10 | 1.10 | 1.64 |
| 5 | 0.05 | 130 | 1.63 | 11.5 |
| 10 | 0.10 | 1,128 | 2.59 | 117 |
| **15** | **0.15** | **8,730** | 4.05 | 1,084 |
| 20 | 0.20 | 66,474 | 6.19 | 9,100 |

Diamonds come only from ascension: $1M → 1, $1B → 31, $1T → 1,000.

**Level 15 is the cliff the pre-code simulation found** — the point that splits
players into sniper and grinder builds, and the reason the mechanic exists at
all (L-016). It costs **8,730 Diamonds ≈ 9 trillion-dollar ascensions.** The
design's own centrepiece is effectively unreachable.

Streak is not *entirely* inert: two quests read it (`streak5` → $750,
`streak15` → 30 Gems). But its payout effect is locked for the whole first run.

*Not a code defect — a balance decision for the operator.* Options: lower the
`StreakStrength` cost curve, raise `B_PER_LEVEL`, or grant level 1 at the first
ascension so the mechanic switches on when the player first meets it.

#### R-3 — `B_PER_LEVEL` is duplicated, client and server

`src/Client/ClientBootstrap.client.luau:267` hardcodes `0.01`; the server owns
`RollService.B_PER_LEVEL`. Retune one and the HUD silently lies about the
multiplier. The catalog pattern (L-025 — ask the shared module, never restate the
rule) exists precisely for this.

---

### 12.2 CRITICAL — real money or unrecoverable loss

| # | Defect | Where | Why it matters |
|---|---|---|---|
| **B-1** | **Ascension deletes Gems, which are bought with Robux** | `AscensionService.luau:66` (`d.Gems = 0`) | FR-9.1 lists what ascension resets — Gems are **not** on it, and FR-9.2 protects Diamonds without mentioning Gems because Gems were never meant to reset. `GemsLarge` sells 650 Gems for Robux. Press ASCEND and they vanish, with no warning on the confirm screen FR-9.4 requires |
| **B-2** | **`+2 Die Slots` gamepass grants 4 slots** | `PurchaseService.luau:504-509` | The mid-session grant never writes `PassSlotsGranted`, and `applyPassSlotGrant` (every join) is idempotent only through that counter. Buy in-session → +2; rejoin → +2 again, plus 4 free dice. Bypasses the ascension cap; each slot is otherwise worth up to $1.02M |
| **B-3** | **Ascension permanently kills the Cash mass-budget path** | `AscensionService.luau:76-79` vs `:114-119` | Ascension resets four upgrades but **not `MassBudget`**, while resetting dice to a 60 budget. `MassBudget` applies only at purchase time, so a maxed player ascends and `BuyUpgrade("MassBudget")` refuses forever at max level. **The entire Cash half of FR-3.6 is dead from the first ascension onward, for the life of the account** |
| **B-4** | **Login reward mints on repeat when writes fail** | `ProgressionService.luau:471-482` | The streak write is unchecked *and* the credit runs unconditionally. If the write is refused the reward is paid anyway and the streak does not advance — every rejoin re-credits it |
| **B-5** | **NaN permanently poisons a balance** | `EconomyService.luau:81-87`, `PlayerProfile._reconcile` | No `_reconcile` guard repairs a non-number `Cash`/`Gems`/`Diamonds`. `current + amount` stays NaN, `next > MAX_CURRENCY` is false, and NaN is written back. Unrecoverable in-game. `BundleExpiry` is the only scalar with a NaN guard |

### 12.3 HIGH — a shipped feature is inert, or a paid path can fail silently

> **STATUS ADDED 2026-10-14. The rows are kept as written: the history is the point, and this table was the 2026-08-27 sweep. Read the left three columns as what was true then; read the last column as where each stands now.** "CLOSED in code" means a fix is committed (`34f4777` or earlier) and read by hand; **nothing has been run in Studio since, Gate 2 has not passed, and P-1 static analysis has never been produced.** An independent audit rejected the seven batches that first claimed several of these closed; the closures above are the post-audit state.

| # | Defect | Where | Status as of 2026-10-14 |
|---|---|---|---|
| **H-1** | **All three leaderboards are permanently empty.** `updatePlayer`/`submitScore` have **zero** production callers. The HLD specifies writes "on player exit and on the periodic auto-save" — neither hook exists. Every player's competitive record is lost, and the BOARDS panel renders empty forever | `LeaderboardService.luau:245-254` | **CLOSED in code** by BOARD-1 (`7874a1c`): `updatePlayer` now runs on exit, on a periodic loop and in `BindToClose` (hooks present in `ServerBootstrap.server.luau`, read not run). Leaderboard cache then split into `inFlight`/`lastFetch`/`failedAt` on 2026-10-14. The exit-hook pin skips silently when `Source` is unreadable, so it may not be enforcing in Play Solo. Not Studio-verified. |
| **H-2** | **Currency fallthrough → Diamonds.** `readBalance` and `writeBalance` have no `else → refuse`; an unrecognised currency **reads and writes the Diamonds balance**. `PurchaseService:81-83` does guard this; the chokepoint module does not. Two live vectors already defeat the type checker (`DiceCatalog.UNLOCK_CURRENCY` is plain `string`; `ProgressionService:79` casts `:: any`) | `EconomyService.luau:80-97` | **CLOSED in code** 2026-10-14 (CURR-1 re-fixed): `isCurrency` guard at every public entry point, `readBalance`/`writeBalance` raise on an unknown currency, `PurchaseService` bundle loop made total. Batch 6's version of this fix was rejected by the independent audit. Not Studio-verified. |
| **H-3** | **`Upgrades.Luck` is sold for ~$23.7M and read by nothing** | `UpgradeCatalog.luau:71-77` | **WRONG TWICE; now CLOSED the other way.** Luck was *deleted* from `CASH_UPGRADES` in batch 4 (`7874a1c`, LUCK-1 as first decided), so the row's "sold for ~$23.7M" stopped being true then. On 2026-10-14 it was **restored and genuinely wired**: `(1 + level * LUCK_PER_LEVEL) * LuckBoost` is one `coinBonus` term, max level 1.40x, below the paid 2x. It is also now reachable from the new UPGRADES overlay. Not Studio-verified. |
| **H-4** | **Four paid handlers spend, then discard the write result and report success.** If the profile is released between the two, currency is gone and goods are not delivered. `ForgeService` does this correctly with refunds; `ServerBootstrap` does not | `ServerBootstrap.server.luau:280`, `:393`, `:467`, `:553` | **CLOSED in code** by batch 7: `mutate` result checked, refund on failure. **Caveat:** a refund is itself a `PlayerProfile.mutate` and cannot fire when the profile was released (see ledger L-081). Not re-audited for that. Not Studio-verified. |
| **H-5** | **Once-only rewards consumed by unchecked credits** — daily spin burns 24h, a promo code is spent forever, a quest is marked claimed, each without confirming payment landed | `ProgressionService.luau:71-80`, `:111-120`, `:323-346` | **PARTLY CLOSED.** `recordLogin` fixed properly 2026-10-14 (one mutation: streak and credit together). **`claimDailySpin`, `redeemCode` and `claimQuest` still roll back with a second `mutate`, which cannot fire when the profile has been released.** Recommended follow-up batch, deliberately not done. Open. |
| **H-6** | **Payload ceiling is documented, tested, and never called.** `checkPayloadSize` has zero production callers, so past ~4MB the profile silently stops persisting with no warn, no kick, no telemetry. `recordPurchase` also returns `ceiling_reached_all_live` **without evicting**, so `PurchaseOrder` grows unbounded | `PlayerProfile.luau:681`, `:590-599` | **First half CLOSED** by SAVE-1: `checkPayloadSize` is now called from `saveNow`. **Second half (`recordPurchase` returning `ceiling_reached_all_live` without evicting, so `PurchaseOrder` can grow) was not addressed by any batch I can find** and may be deliberate under T-13. Unresolved; not re-checked. |
| **H-7** | **Vault accrual is consumed before the credit lands.** Ordering is mutate → zero the window → credit → check. A failed credit loses the player's entire offline accrual, and `getMultiplier` has no finiteness guard on the stored multiplier to prevent one | `OfflineService.luau:354-375`, `BoostService.luau:58-59` | **CLOSED in code 2026-10-14.** Batch 6's fix credited first and bolted on a `debit` rollback that could not fire; the accrual then paid twice with the Robux boost still unspent (ledger L-081). Now one mutation (`creditWithin` plus window spend). Not Studio-verified. |
| **H-8** | **`_reconcile` can replace a whole dice collection with the template.** `if #data.Dice == 0 then data.Dice = deepCopy(TEMPLATE.Dice)` — and a DataStore round-trip turns a holed array into a *dictionary*, on which `#` is 0. Latent today (all writers use `table.remove`), but the repair is a total wipe | `PlayerProfile.luau:275-277` | **CLOSED in code** by RECON-1 (batch 6): holed arrays filtered before the empty-collection check. Rested on batch 6's audit; not individually re-audited. Not Studio-verified. |
| **H-9** | **Seven profile fields have no type guard in `_reconcile`.** A wrong-typed `Vault` throws inside `admitPlayer`, so the roll session, the bundle stamp and the **first snapshot** never run — the player sits in a live session with a blank UI, and the stranded-player sweep will not re-admit them | `PlayerProfile._reconcile` | **CLOSED in code** by RECON-1 (batch 6): container-type repair for ten profile sub-tables. Not individually re-audited. Not Studio-verified. |

### 12.4 MEDIUM and LOW

**Medium:** `buyVaultHours` charges for hours the VIP floor already covers
(`OfflineService.luau:428-434`) · `GetLeaderboard` yields inside the handler with
a thundering-herd window, contradicting the contract's "never triggers a fetch"
(`LeaderboardService.luau:163-221`) · `AddDieSlot` mints inventory that
`BuyDieInstance` charges up to $4.2M for, and `_reconcile` retroactively legitimises
it (`ServerBootstrap.server.luau:463` vs `:546`) · `PurchaseService.grantCurrency`
bypasses `EconomyService` entirely, so no `MAX_CURRENCY` clamp and no
`LifetimeCash` update (`:77-94`) · **boost multipliers ship to the client** in the
generic `upgrades` map, defeating the NFR-5 protection the curated `boosts` map
three lines earlier exists to provide (`StateSyncService.luau:134-137`) ·
`recordPurchase` writes the receipt idempotency ledger **without an `IsActive()`
check**, bypassing `mutate` (`PlayerProfile.luau:582-602`) · server shutdown races
`BindToClose` against `PlayerRemoving`, so `Vault.LastSeen` may not be stamped ·
`_reconcile` runs **before** `_migrate` and its return value is discarded, making
any "field absent" migration dead on arrival.

**Low:** `BuyDieInstance("D2")` is free and unbounded (a zero-cost debit returns
`true`) · `SetElement` charges 50 Cash for a no-op · `Vault.AccrualId` is written
and never read · `starterBundle` / `shapesEquipped` / `forgivenessLeft` are
emitted with no consumer — which means **FR-12.5's entire once-only Starter Bundle
offer is computed on every push and rendered nowhere** · roll credits, quest
progress and streak advance all commit *before* the credit check · a corrupt die
repairs to **D6, not the D2 starting shape**, and `_reconcile` then latches a free
first-equip · `BadRollShield` is simultaneously a 5,000-Cash upgrade and a Robux
gamepass, and two files state opposite intent.

---

### 12.5 LANDMINES IN THE PLANNED WORK

These are not bugs today. They are what will break when Phases 1–3 are built, and
they are the reason those phases need more than the roadmap's own estimates.

**A new currency (Shards, Phase 2c) touches 23 sites, not one.** The Diamond
fallthrough exists in **two** files (`EconomyService` *and*
`PurchaseService.luau:85-93`), plus a bundle loop with no `else` at all
(`:126-132`) that would silently skip a Shard part after the player paid. The
sharpest fact: **because reward tables are typed `EconomyService.Currency`,
widening the union makes the broken fallthroughs compile silently.** The type
system will hide this, not catch it. No test pins the union — add one first.

**A new per-die field (traits) must be added in six places, and three of them
*delete* it rather than fail to create it.** Beyond the reconcile loop the
roadmap names, `performSetShape` (`ForgeService.luau:716-733`) and `repairDie`
(`:213-250`) both rebuild the die as a fresh **four-field literal** — so every
shape change and every join-time repair silently strips traits. Detection is
asymmetric and that is what makes it dangerous: the reconcile gap fails on the
first reload and is obvious, while these two fail only *after* a shape change —
a player forges traits, uses them a week, switches D6 → D8, and they are gone.
`StateSyncService.luau:117-132` builds the dice payload field-by-field too, so
traits would never reach the client and the cause would look like a UI bug.

**The "six files must agree" rule for a new remote currently holds for five.**
`SwapDice`, `UnequipDie` and `BuyDieInstance` are all fully wired and **absent
from `API_DATA_CONTRACT.md` §1.1**. `RemoteContract.test.luau` cannot read files
from disk, so the doc is unenforced by construction. Also: `RateLimiter` silently
falls back to a permissive default for an unlisted remote — fine for most, wrong
for a value-bearing random action like `RerollTraits`.

**Element unlocks (Phase 2a) cannot copy what the roadmap says to copy.**
`ElementCatalog` has **no cost table, no ladder, no prerequisite and no
currency** — all three must be authored. The roadmap's instruction to copy
`ElementCatalog`'s `math.huge` cost sentinel is wrong; that sentinel is in
`UpgradeCatalog.luau:118`. And **ordering in `BuyDiamondNode` is load-bearing**:
placed after the generic node path, an element id writes `Diamond.Fire = 1` — a
number at the top level instead of into `Diamond.Elements` — invisibly, while the
player is charged. That is L-027 reproduced one field over.

**Daily Spin (Phase 1b/2b) is not "connect a button to a working backend".** The
snapshot carries **no spin state at all**, so the button cannot be greyed or show
a cooldown; and the handler discards the outcome (`ok, reason, _, _`), so a wheel
cannot be told what it landed on. Both need server work the roadmap does not
budget. Shipping the *amount* would violate NFR-5; an `outcomeId` would not —
that decision is unmade.

**Phase 3 deletions are safer than feared.** The L-028 sweep was run: none of the
four files touches `Workspace`, `Lighting`, `CurrentCamera`, `Terrain` or
`Atmosphere`, and no other module looks up their GUIs. The `ArenaView` failure
does not repeat. The only real coupling is `tests/ClientContract.test.luau`
(already recorded in §7).

**Stale line references in this document**, found while verifying:
`setTraitControlInert` is at `V7MenuPanel.luau:4133`, not `:3938` (195 lines off);
`coinBonus` is at `RollService.luau:303`/`:473`, not `:302`/`:458`. Most other
citations verified exact.

**`API_DATA_CONTRACT.md` is a seventh place** a new profile or snapshot field must
be recorded, and it is already stale in eight ways (starting shape listed as D6
when the code uses D2, plus seven omitted fields).

---

### 12.6 What is NOT yet covered

- ~~The client sweep was still running.~~ **Complete — see §12.8.** It found the
  two worst defects of the exercise.
- **Round 2 was started and deferred by the operator.** It was to independently
  re-verify every claim above and dig into four areas the first pass
  under-covered: element resolution across dice, forge mass validation under
  legal-operation sequences, auto-roll lifecycle, and rate-limiter token maths.
- **P-1 static analysis has never been run** on any of this. Still the standing
  operator blocker.

### 12.7 What the sweep found CLEAN

Worth recording so it is not re-swept: every `RemoteGateway.register` handler was
walked for client-influenced economic arguments and — apart from the `ClaimVault`
flag, now fixed — **none reaches a payout, cost or grant unverified.** No
division-by-zero or `nil` arithmetic reaches a stored value. Fan-out loops are
`pcall`-guarded. And live stress testing held completely: 45 junk inputs across
five remotes produced **zero throws and zero false successes**, every economic
boundary refused correctly, and repeat vault claims correctly report
`vault_empty`.

---

### 12.8 CLIENT SWEEP — round 1 complete (appended 2026-08-27)

The third sweep landed after §12 was first written. It found the two worst
defects of the whole exercise, and they compound each other.

#### CRITICAL

**CL-1 — The forge reports success on every single refusal.**
`V7ForgePanel.luau:1325` (and `:1239`) do:

```lua
local ok, reason = NetClient.forge(activeDie, out)
if ok then ... bForge.Text = "CALIBRATED" ...
```

`NetClient.forge` returns a **single `Result` table**, not `(ok, reason)`. So
`ok` is always a truthy table and `reason` is always `nil` — **the success branch
is unconditional.** Verified: every other call site in the client correctly does
`local result = ...; if result.ok`.

A player who cannot afford the forge, is throttled, or submits a distribution the
server rejects sees the button turn green and read **"CALIBRATED"**, and `dirty`
is cleared. They believe they paid and reforged. Nothing happened. Same at
`:1239`, where a refused `MassBudget` purchase never shows its reason.

This is a **false economic receipt on the game's core screen.**

**CL-2 — Forging is permanently impossible on D7 and D14.**
`newDie` snaps the per-face share down to 3dp, so the budget is not an integer for
shapes that do not divide 60 evenly. The submit path forces the total to
`math.floor(budget + 0.5)` = exactly 60. Measured in a running game:

| Shape | Stored budget | Client sends | Drift | vs EPSILON 0.001 |
|---|---|---|---|---|
| D7 | **59.997** | 60 | 0.0030 | **rejected** |
| D14 | **59.990** | 60 | 0.0100 | **rejected** |

All ten other shapes produce an exact 60 and are unaffected.

**Every forge on a D7 or D14 fails with `sum_mismatch`, forever — and CL-1 tells
the player it worked.** The two together are why this pair is listed first: a
player can own a D14, forge it repeatedly, be told "CALIBRATED" each time, and
never once change anything.

**CL-3 — The MULT readout overstates by orders of magnitude past streak 50.**
`ClientBootstrap.client.luau:290` uses `math.min(streak, 500)`; the server caps
the exponent at **50** (`RollService.STREAK_CAP`) and clamps to `1e6`. At
StreakStrength 20 and streak 60 the HUD reads **×56,347** against a real **×9,100**.
This is a third hardcoded copy of a server-owned constant, two lines below the
`B_PER_LEVEL` duplication in R-3.

**CL-4 — The SHAPES panel's equip button is dead.** `V7MenuPanel.luau:1073` and
`:1157` read `playerInventory`, but the only declaration is at `:3854` inside a
*different closure*. It resolves to a nil global, so `ownedTotal` is always 0: a
player holding three D6 sees **"[ NO DICE OWNED ]"** and the click guard can never
pass. A scope scan found this is the only cross-closure leak in the live set.

**CL-5 — The DAILY QUESTS panel is permanent mock data with a dead CLAIM
button.** `questRows` is built and read by nothing; `state.quests` — which the
server ships complete with progress and target *specifically* so the client can
draw the bar — is read nowhere. The cards sit forever at their construction
values, including a fabricated **"REWARD: +$2,500 CASH"**. The server
deliberately omits quest reward amounts under NFR-5; the client invented one.
`rowState.id` is never assigned, so CLAIM returns immediately every time.

**CL-6 — Two unguarded lines sit upstream of the panel fan-out.**
`V7MenuPanel:applyState` and `V7ForgePanel:applyState` are both correctly
isolated — but in `ClientBootstrap`, lines `:310` and `:326-329` run *before*
`menuController:applyState` at `:336`. Only the risk calculation (the one that
already caused the L-057 incident) was wrapped. A throw in `estimateMultiplier` —
which happens on any non-table `state.diamondTree` — aborts the snapshot before
any panel is fed, while the HUD keeps working. **That is the exact L-057
symptom.** Separately, the three `.new()` panel constructions at `:152/:155/:159`
are not `pcall`'d, unlike `require` and `init`; a throw inside ~6,000 lines of
`V7MenuPanel.new` would leave the ROLL button unwired with no `fatal()` panel.

#### HIGH

- **Shape-change cost is invisible and its refusal is discarded.** The server
  charges 5 Diamonds for a non-first equip; `SHAPE_CHANGE_DIAMOND_COST` exists so
  the client can show it, and `ShapesEquipped` is shipped so it can tell free from
  paid. Neither is read. The catalog comment says this defect was already fixed —
  it has returned, in both SHAPES and SLOTS.
- **`★ TOTAL` on the board sums face *indices*, which have no economic meaning.**
  Payout is `mass^ALPHA`, and under the inverse-mass rule a high index is usually
  a *light, low-paying* face. The board's most prominent number moves opposite to
  earnings.
- **The SLOTS panel quotes a slot price the server will refuse.** Client passes
  `slotNodes` to `dieSlotCost`; `ServerBootstrap.server.luau:546` omits it. A
  Diamond node the player paid up to 3,200 Diamonds for buys a slot the store then
  declines to sell. *(This one is mine — introduced in `daac879` when I threaded
  `slotNodes` through the client and missed the server's own pricing call.)*
- **All four settings toggles control nothing.** `refreshSettings` hardcodes
  `available = true` and never reads `_capabilities`, which is written and read by
  nothing. Music and SFX render as live switches over a subsystem where
  `AudioDirector.play` has zero call sites outside the dead files.
- **The shop shows the false Luck Boost claim the catalog was corrected to
  remove.** `V7MenuPanel.luau:2412` still says *"heavy faces land closer to even
  odds"*, rendering directly beneath the corrected blurb — so the card now shows
  both the true and the false description of the same Robux product.

#### MEDIUM / LOW

Vault panel invents plausible defaults for missing fields and hardcodes "1.50x
VIP" (the bonus is additive, so the real figure varies) and labels Premium players
"Standard" · the forge re-implements `landingProbabilities` / `expectedValue` /
`voidProbability` instead of calling `ForgeMath`, the third recorded instance of
L-025 · `+` on the starting D2 returns only 2 mass where `−` removed 5 · the
payout flash shows the pre-multiplier figure, so a CashX2 owner sees `+$100` while
the balance jumps `+$200` · a throttled leaderboard read is painted as
"STREAM OFFLINE" · client-side duplicates of the playtime and login reward tables
· per-snapshot `Model:Clone()` churn rebuilding ~20 rigged dice per second for
panels nobody is looking at · SAFE and EVEN presets are byte-identical · the
SHAPES card's priced button has no click handler (an overlay intercepts it) ·
**nothing subscribes to `onNotice`, so every enumerated server refusal is fired
into nothing** · `state.boosts` is read by no client module, so a purchased
15-minute Luck Boost has no countdown anywhere — which is exactly what §5's item
**1c** must fix.

#### Verified clean by this sweep

`applyState` isolation in both panels · board tab ids match the server ·
`BuyDieInstance` and shape-unlock pricing match · `refreshAscend` correctly reads
`state.cash`, not `LifetimeCash` · `DiceRenderer` and `BoardView` have symmetric
`shutdown` · every `NetClient` throttle is looser than its server bucket · no
unbounded connection or instance leak anywhere in the live set.

---

### 12.9 REVISED PRIORITY after all three sweeps

**Fix before Phase 1 starts.** Ordered by what a player loses:

1. **CL-1** — the forge lies about every failure. One-line fix, and it is masking
   at least CL-2.
2. **CL-2** — D7 and D14 cannot be forged at all.
3. **B-1 / B-2** — ascension deletes Robux-bought Gems; the slot pass grants
   double.
4. **B-3** — ascension permanently kills the Cash mass-budget path.
5. **B-4 / B-5** — the login mint, and NaN poisoning a balance forever.
6. **H-1** — leaderboards have never been written.
7. **CL-4 / CL-5** — the equip button and the quest panel are dead; the quest
   panel additionally displays an invented reward figure.
8. **R-1 / CL-3** — RISK and MULT both report numbers that are simply wrong.

**Then:** H-2 (currency fallthrough) *before* any Shards work, and the six per-die
sites *before* any traits work — both are in §12.5.

**Two of the findings above are mine, from today**, and are called out as such
rather than folded in anonymously: the `OfflineX2` consume-without-apply
regression (fixed, `67c8e84`) and the SLOTS price mismatch (open).
