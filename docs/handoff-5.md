# HANDOFF 5 — Dice geometry, the Gems sink, and the payout flash

**Date:** 2026-08-15
**Head:** `8bf09d4` · 21 suites, 3,547 assertions, 0 failing, 0 server errors
**Tree:** clean apart from `.mcp.json` and `tools/roblox_studio_mcp_proxy.js`,
which are the operator's MCP tooling and deliberately untouched.

**Status:** the queue from handoff-4 is DONE — payout flash, ascension
threshold, and the Gems vault sink all landed. The dice set is down to one
known visual defect plus one unsolved regression. **Nothing is in progress; the
next item is awaiting the operator's go.**

---

## 1. WHAT LANDED SINCE HANDOFF 4

### `e6bb771` — payout flash alive, ascension on Cash, `RunCash` deleted

**The payout flash had been a no-op since L-044** — dead for the whole V7 build.
It is now implemented on the label parented to the cash readout: rises out of the
figure it just changed, fades over 0.62s, tweened rather than stepped so it needs
no `RenderStepped` connection.

Single-flight, not queued: a new payout cancels the one in the air. At the
auto-roll ceiling of 1.6/sec a queue would drift behind the real balance and
start reporting stale figures.

**Wiring it exposed a defect.** The previous commit claimed the board-anchored
text was gone; it was not — the label had been moved but its subscription never
removed. With the flash working, BOTH fired, and a screenshot showed `+37.90K`
and `+33.00K` sprawled across thirty dice. `FeedbackFX.init` no longer routes
`onRollResult` anywhere. Verified: 0 visible board labels across sustained
auto-roll while the HUD flash still fires.

**Ascension now prices on Cash on hand**, per the operator's decision. `RunCash`
is deleted from six places. The panel reads `state.cash`, which the HUD already
displays — so the two can never disagree again, which was the whole point.
IT-5 gained an assertion that the field does NOT exist, so it cannot reappear as
a third cash figure.

> **The tradeoff, recorded:** spending Cash on upgrades now pushes ascension
> further away, because the threshold measures holdings rather than earnings.
> Upgrade-vs-prestige becomes a real decision. Worth revisiting if it feels
> punishing in play.

### `2ffc292` — Gems buy vault capacity (the game's first Gems sink)

`5 Gems = 1 hour`, capped at `+8h`. Treated as an economic surface:

- **The cap is enforced twice** — on write in `buyVaultHours`, on read in
  `getCapacity`. A write-only clamp is one bug away from unbounded; clamping the
  read means no stored value can exceed the ceiling whatever wrote it.
- **Order of operations is the safety property.** Every refusal is checked before
  any Gems move; capacity is written only after the debit succeeds; a failed
  mutation refunds. The failure mode is "nothing happened".
- **Range validated at the boundary**, so no absurd figure reaches the cost
  arithmetic.
- **The panel renders server truth only** (L-042).

**The project's own guard caught a mistake.** The handler was registered without
declaring its arity, and rather than binding a remote with no shape contract the
bootstrap REFUSED TO BOOT with three suites failing by name. That is F-4A-1
working exactly as designed.

Verified adversarially: `0`, `-5`, `2.5`, `1e9`, `NaN`, a string, `nil` and an
extra argument are all refused. Then eight purchases succeeded and five refused,
stopping exactly at the ceiling.

### `846ab76` + `8bf09d4` — VIP made the Gems sink worthless

Operator, looking at `24h 0m stored` beside `+8h of that is Gem-bought`:
*"how does this work if its still 24hrs"*. It did not. The Gems bought nothing.

| Source | Max |
|---|---|
| Base | 4h |
| Cash upgrades (5 × 0.8h) | 4h |
| Gem purchases | 8h |
| Roblox Premium | 4h |
| **Everything combined** | **20h** |
| **VIP floor (was)** | **24h** |

VIP's floor exceeded every other source combined, so it swallowed the entire
purchase — 40 Gems for zero capacity, and the panel credited them anyway.

**Operator chose option 1: lower the floor.** The threshold is arithmetic, and
the first attempt at it (16h) was still wrong — the floor must sit below what a
VIP player reaches WITHOUT Gems, which is base 4h + Gems 8h = 12h:

```
floor 16h -> Gems add +0h   (first guess, still broken)
floor 12h -> Gems add +0h
floor 10h -> Gems add +2h
```

**Now 10h.** Curve: free 4h → 12h with Gems; VIP 10h → 12h; everything maxed 20h.
VIP is still 2.5× base and beats a fully Cash-upgraded player without Premium.

Also fixed: `buyVaultHours` refuses with `no_benefit` when a purchase would not
raise capacity; the `"+25% and 24h"` upsell was a hardcoded second copy of the
floor and is now derived (L-025); and the panel was reading "at purchase cap" as
"VIP absorbed it", telling a player their working `+8h` was doing nothing.

### `8bf09d4` — dice fragmenting was two one-frame teleports

Operator-reported as dice *"breaking and deforming and then falling"*.
**Not the rasteriser.** Sampling the pivot every frame:

```
t=0.050  pos=(-2.44, 0.37,  7.08)   <- at rest
t=0.118  pos=( 0.00, 0.00,  0.00)   <- ONE FRAME AT THE ORIGIN
t=0.183  pos=( 4.72, 5.88,-10.87)   <- throw start
```

Two places made a die visible before positioning it: `applyModel` parented a
fresh clone (clones sit at the authored origin, and `Parent` shows them
immediately), and `measureSitHeight` posed the model with a rotation carrying no
translation. Both now park at `y = -1000` first. Re-measured across 5 rolls:
**0 visible jumps, 0 origin frames.**

**A worse bug found while chasing it.** `DiceRenderer.FACE_COUNTS` was a
hand-written mirror of EIGHT shapes; the catalog has twelve. An unlisted id draws
no model BY DESIGN — so a player on **D5, D7, D14 or D16 saw a completely empty
board**, with nothing logged. Found by setting the die count to 1 and getting a
D7. This is L-041 repeating in a second file; the list is now derived from
`DiceCatalog.getAllShapes()`.

---

## 2. THE DICE SET — STATE AND THE ONE REGRESSION

Twelve shapes, one file (`DiceMeshBuilder.luau`), all verified in Studio:
chamfer present, glyphs engraved and legible, radial extent 6.00, orthogonality
≤ 2e-07, every `FaceCount` and `PrimaryPart` correct, parts 29–210.

`f50d5a9` records why the Antigravity set was kept over the Codex one: both
passed every contract and face-by-face numbering was correct in both, so it came
down to the D6's round pips and a 4.5% lower part count.

### THE UNSOLVED REGRESSION — sub-pixel shearing at distance

**This is the one genuine open defect in the dice.** At the far edge of the felt
the thinnest geometry renders under one pixel and shears as the die tumbles.

**Do not simply re-apply the previous fix.** `fb0e96e` added a minimum thickness
floor in `normaliseScale`, and it was REVERTED in `8bf09d4` because it destroyed
the numerals: a facet plate is thin on ONE axis, but a numeral stroke is thin on
TWO — it is a bar — so the floor inflated every stroke into a cube. 75% of the
D20's glyphs, 57% of the D16's, eleven of twelve shapes. The operator: *"the
numbers on die are not visible at all."*

**Three further attempts all failed, each differently:**

1. Excluding glyphs from the floor — dice rendered completely blank, because the
   glyphs fell back to sub-pixel.
2. Lifting only the glyph's thinnest axis — blank again: thickening the plates
   had moved the face surface outward, leaving glyphs buried 0.147 studs inside
   it.
3. Pushing glyphs outward to follow — fixed 6 of 12.

`DiceMeshBuilder.luau` is restored to `70f3a42`, the last state with visibly
correct numerals, **confirmed by looking rather than by measuring**.

> **A pattern worth naming before the next attempt.** Four consecutive dice-
> geometry fixes had metrics reading "healthy" while the render was wrong. The
> measurements kept describing something ADJACENT to the real property — the
> "proud" check compared against furthest-corner reach, but glyphs sit on face
> CENTRES, which are always nearer, so it reported 12/12 buried on a build whose
> numerals were plainly visible. **The next attempt on this should be signed off
> from a screenshot, not from a number.**

**Constraint for whoever picks it up:** solve it without touching glyph geometry.
Thicken only chamfer strips and facet plates, identified by name, and check the
result by eye at the FURTHEST die on a full board — a threshold measured at the
nearest die passes while the far ones still tear (that was the `fb0e96e` error).

---

## 3. THE NEXT ITEM — THE WEIGHT BAR SPAWN JUMP

**Operator-reported 2026-08-15, not yet fixed, awaiting the go.**

> *"why does the bar spawn away from dice first then get relocated to the dice"*

**Cause, confirmed by reading the code.** `showFace` sets `barShown = true`,
which makes the bar eligible to render — but its `Position` is assigned later, in
the frame step. For one frame it renders at its default `(0,0)`, the overlay's
top-left, before snapping to the die.

**It is the same bug class as the dice teleports** fixed in `8bf09d4`: something
becomes visible before it has been positioned. The dice version read as
fragmenting; this one reads as a bar sliding in from elsewhere.

**Proposed fix.** Do not let `Visible` be driven by intent alone — require that
the bar has been positioned at least once. One flag, set the first time `project`
succeeds for that die, cleared when the die is released. Contained; no change to
how the bar looks or what it reports.

---

## 4. THE QUEUE

### Immediately next
1. **The weight bar spawn jump** (§3) — small, contained, cause already found.
2. **Sub-pixel shearing at distance** (§2) — carried over. Read the constraint
   and the failure history in §2 before starting.

### The UI-quality pass (operator: the panels *"look as if made by an ai"*)
3. **Emoji removal and retitling across all nine overlays**, in one commit. The
   emoji is the smaller half — the titles were transcribed from the spec
   (`MONETIZATION SHOP (GAMEPASSES & PRODUCTS)` names an implementation category
   and then enumerates the SRS). A shipped game says `SHOP`.
4. **Layout rebuilds:** SHOP → FORGE → SHAPES.
5. **Rotating 3D die preview** on shape and shop cards — last, and now unblocked
   because the models are final. The renderer already provides a working
   ViewportFrame/camera/model path to reuse.

### Housekeeping before release — both carry test values
- **`ASCEND_MIN_LIFETIME_CASH` → `1e6`** (currently `100000`, `DiceCatalog:338`).
- **`PLAYTEST_DIE_COUNT` → `0`** (currently `1`, `ServerBootstrap:168`).
  Studio-gated so it cannot reach a live game, but it must not ship set.

### Still blocked on the operator
- **Audio** — 9 `DUMMY_ID_*` placeholders in `AudioDirector`. Fails closed and
  Settings says so honestly.
- **Roblox group id** — `ProgressionService.GROUP_ID = 0`; group rewards built
  and commented out.
- **Element unlocks** (Fire/Freeze/Gold/Multiplier) — built server-side, no
  unlock path. Belongs in ASCEND.
- **`src/Client/LegacyUI/`** — dead duplicate code awaiting deletion.

### Open balance questions, not defects
- **`MAX_DIE_SLOTS` is still 7** (`DiceCatalog:371`). The renderer, the forge tab
  strip and the scatter sampler all handle 20+ — verified at 30 dice — so raising
  it is now purely a balance decision with no rendering work attached.
- **Whether the ascension tradeoff feels punishing** now that spending delays
  prestige (§1).

---

## 5. NOTES FOR THE NEXT SESSION

**Rojo drops edits silently.** Several times this session a file was edited on
disk and Studio kept the old copy, with no error. Symptoms are confusing —
assertions failing against code that looks correct. Verify a specific string is
present in `Source` before trusting a Studio measurement, and reconnect the
plugin if not.

**`require()` caches, so a regenerated model can be stale.** Reading
`Workspace.dice_faces` after a source edit can measure the PREVIOUS build. Clone
the module and re-parent it to force a fresh require before regenerating.

**`Workspace:Raycast` is useless on the dice.** Every part sets
`CanQuery = false`, so rays pass straight through and report nothing. It returns
0% seated for all twelve and means nothing. Compare positions and radii directly.

**`execute_luau` does not share the running server's module cache.** A fresh
require gets an empty instance, so live profile state cannot be read that way.
Drive the real remotes instead.

**Studio's frame rate under MCP is ~15 fps regardless of scene contents** —
confirmed by hiding the entire viewport and measuring no change. Do not read it
as a performance signal.

Ledger entries now run to **L-053**.
