# Handoff 8 — the panels work, and we now know what is left

**Written:** 2026-08-23, end of session. **HEAD: `0f7a3c7`.**
Tree clean. Supersedes the open items in `docs/handoff-7.md`.

The forward-looking half of this document has been split into its own file:
**`docs/ROADMAP.md`** is the plan to launch. This handoff records what happened
and what is true right now.

---

## 1. STATE

**21 suites, 0 failed, 3,565 assertions.** Verified in a running Studio session,
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
| 10 | **Dead legacy files** | `ForgePanel`, `MenuPanel`, `HUD`, `CurrencyModels` — ~3,500 lines, required by nothing. | Delete |

**Items 3 and 4 are not "unfinished" — they are transactions that do not
deliver.** Item 4 involves real money.

---

## 4. TWO CORRECTIONS TO THE RECORD

**Audio placeholder count.** `docs/handoff-7.md` §3 states *"23 audio asset
IDs"*. The real count is **9** — 8 SFX cues plus one music loop, verified by
direct grep of `AudioDirector.luau`. Handoffs 1 through 6 all correctly said 9.
Handoff-7 introduced the error and no later document caught it.

**"Nothing outstanding".** Handoff-7's §5 claimed the constants were ready and
nothing was outstanding, while 158 Script Analysis warnings were open and
recorded two sections above it in the same document. Void that section.

Both corrections follow the same pattern the zero-warnings incident did: a figure
stated once, then carried forward by documents that did not re-check it.

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
