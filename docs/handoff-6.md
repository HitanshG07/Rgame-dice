# Handoff 6 — UI quality pass, mid-flight

> **This is a historical record. Do not action anything in it.**
> Superseded by **`docs/handoff-8.md`** (current state) and **`docs/ROADMAP.md`**
> (the plan and the live open-item list). Where this document and those two
> disagree, **they win** — they were verified against live code on 2026-08-26 and
> this one was not.
>
> **Specifically stale here:** the five uncommitted files it warns about were
> committed long ago, and its §174 instruction to expect *“zero errors and zero
> warnings”* is **false** — Script Analysis stands at **158 warnings**, which is
> the open NFR-8 blocker. The three ledger entries it drafted were appended; the
> ledger now runs to L-079. **Still valid:** do not skip the isolated `qa-auditor`
> pass, and when a number and a screenshot disagree, the screenshot wins.

**Written:** 2026-08-15, at operator request ("stop, make a handoff, we continue later").
**Supersedes nothing.** `docs/handoff-5.md` remains accurate for everything it covers;
this document covers only what happened after it.

**HEAD: `18f9573`.** Working tree has **five modified files, uncommitted, deliberately.**

---

## 1. WHAT IS COMMITTED

### `18f9573` — the weight bar spawn jump (handoff-5 §3, now closed)

`step` assigned `bar.Visible` from the projection test and only then assigned
`bar.Position`. A fresh bar has no position at all — a new `Frame` defaults to
`UDim2(0,0,0,0)`, the overlay's top-left — so the first time a die came to rest its
bar painted one frame in the corner of the board before snapping under the die.

Two lines reordered so position and reveal are one operation. Same class as the two
dice teleports in `8bf09d4` (L-052).

**Verified:** module loads in Studio, source confirmed synced. Not yet watched by eye
in a live roll — worth one glance next session, but the mechanism is understood and
the fix is two lines.

---

## 2. WHAT IS UNCOMMITTED — the UI quality pass

Five files, ~2,100 diff lines. **It is not finished and must not be committed as-is**
until the verification in §4 completes.

### Files touched

| File | What changed |
|---|---|
| `src/Client/UITheme.luau` | +`Scale` table; +9 layout primitives; overlay chrome rebuilt; 44px touch floor added to `neumorphicButton` |
| `src/Client/V7MenuPanel.luau` | SHOP, SHAPES, SLOTS rebuilt on the primitives; 8 titles de-emoji'd; rotating 3D dice previews added |
| `src/Client/V7ForgePanel.luau` | Face rows + action bar rebuilt; title de-emoji'd; face list made scrollable |
| `src/Client/V7HUD.luau` | Gear character replaced with drawn geometry |
| `tests/ClientContract.test.luau` | +emoji scanner, +layout-primitive assertions, +`arbitratesChildren` cases |

### The diagnosis that drove it

The panels did not look amateur because of colour. **They looked amateur because
hand-placed scale coordinates overlapped**, measured from source:

- **SHAPES card** — `status` spanned x 0.44→0.66, the action button began at x 0.585.
  A hard **7.5% overlap**. This is "OWNEDUSE 5♦" in the operator's screenshot: text
  drawn straight through a button.
- **SHOP card** — blurb at y 0.35→0.65 (TextScaled), tier small print at y 0.545→0.705.
  **10.5% vertical overlap** — "Rolls for you…" struck through the blurb.
- **SLOTS** — one TextScaled sentence at 30% panel height, then a void.

Nothing in the code could notice any of it. Two hand-picked fractions that happen to
intersect produce no error.

### The fix

`UITheme.Scale` (a 4px ladder) plus primitives that arrange children with
`UIListLayout`, so **siblings occupy disjoint tracks by construction**:
`verticalStack`, `card`, `listRow`, `textLine`, `paragraph`, `actionButton`,
`statusPill`, `setPill`, `setActionEnabled`, `arbitratesChildren`.

`card(nil)` / `listRow(nil)` self-measure for wrapped prose; passing a height fixes them.

### Emoji — all 10 gone

Titles are now Title Case noun phrases: Shop, Dice Shapes, Leaderboards, Ascension,
Daily Quests, Offline Vault, Settings, Die Slots, Forge. The HUD gear is **drawn from
frames**, because an emoji is a font-dependent glyph that renders as colour art, line
art, or tofu depending on platform.

---

## 3. TWO AUDIT ROUNDS — 11 defects, all addressed

Both run in isolated `qa-auditor` sub-agents that never saw the authoring reasoning.
**The audits earned their cost. Do not skip them next time.**

### Round 1 — 4 defects

1. **RenderStepped leak (HIGH).** Preview start/stop was driven from
   `openOverlay`/`closeAll`, which the header **×** bypasses — it just sets
   `Visible = false`. Closing with the X left 8+ invisible models pivoting every frame
   forever, and the `previewConn ~= nil` guard then made reopening a no-op, so it never
   healed. **Fixed at the root:** `bindPreviewLifecycle` watches the overlay's `Visible`
   property, so *every* hide path stops it, including ones added later.
2. **SHOP card overflow (MED).** Fixed 108/84px heights vs. wrapping paragraphs.
   Fixed via self-measuring `card(nil)`/`listRow(nil)`.
3. **AC-U2.1 falsely claimed as mechanically asserted (MED).** It was not, and could not
   be — construction needs a LocalPlayer, the suite is server-side (L-036). **The plan's
   criterion was rewritten rather than the claim defended.**
4. **Gear under 44px on narrow screens (MED).** 19px at 420px width.

### Round 2 — 7 more

1. **`tests/ClientContract.test.luau` would not parse (CRITICAL).** A line ending in
   `decorated` followed by a line starting with `(` parses as a *call*. The whole test
   file would have failed to compile, **silently disabling every assertion in it —
   including the new ones this pass added.** Rewritten with named locals. A repo-wide
   scan for paren-initial statements now comes back clean.
2. **`MouseLeave` clobbered the disabled state (HIGH).** Press and disabled both wrote
   `TextTransparency`; the press handler restored a value captured at construction, so
   hovering a disabled button repainted it as enabled while it stayed unclickable.
   **Fixed by separating the channels** — press now paints a child veil.
3. **Circular measurement risk in the auto-size path (HIGH, unresolved by reading).**
   Settled empirically — see §4.
4. **Forge face list could not fit 20 rows (MED).** A plain Frame at 66% height holding
   up to 1150px of rows: a D20's later faces rendered *through* the cost label with no
   way to reach them. My row-height change made a pre-existing defect slightly worse,
   which is how it surfaced. **Now a ScrollingFrame** with an automatic canvas.
5. **9 of 10 HUD controls still under 44px (MED).** AUTO was 29px on a phone.
   **Fixed in the builder**, not per call site, so future scale-sized buttons inherit it.
6. **`overlay`'s container failed its own new rule (LOW).** Header/divider/body are
   pixel-anchored bands with no layout. Now carries an explicit `LayoutExempt`
   attribute — opting in by name, so a deliberate exception is auditable.
7. **False provenance in a comment (LOW).** I wrote that the scanner reports "8 + 1 + 1
   offenders"; it returns on first match, so it can only ever report **one line per
   file**. Re-measured: **3 files** at `a8faa6a`, **0** now. Corrected, and the
   correction verified against the code rather than re-asserted.

---

## 4. VERIFICATION STATUS — read this before continuing

Studio connected late in the session (`studio_id` changes per session; re-run
`list_roblox_studios`). What was established, in order:

| Check | Result |
|---|---|
| Source synced into Studio before any test | **All 5 files confirmed new** — markers found in live `Source` |
| All 6 client modules `require()` | **LOAD** — no syntax errors, no invalid Enum symbols |
| 10 layout primitives present on loaded theme | **All present**, `Scale.TouchTarget = 44` |
| Layout geometry at 1280 / 800 / 420px | **PASSED — this settles audit finding #3** |

The geometry probe built a real SHOP card in a rendered tree at three widths:

```
w=1280  card=85  textCol=1071x69   btn=76x44  H-overlap=-12  contentFits=true
w=800   card=85  textCol=591x69    btn=76x44  H-overlap=-12  contentFits=true
w=420   card=122 textCol=211x106   btn=76x44  H-overlap=-12  contentFits=true
```

**No collapse, no clipping.** `H-overlap = -12` is a 12px *gap* (the `Scale.MD` gutter)
at every width — negative means separated. At 420px the card **grows** 85→122px to fit
wrapped text, which is the auto-size path working. Buttons hold 44px throughout.

### STILL UNVERIFIED — the next thing to do

The **full-panel sweep was interrupted mid-run.** The script was written and ready: it
constructs the real `V7MenuPanel`, reveals every overlay, walks all descendants, and
reports (a) any intersecting sibling pair inside a container that does not arbitrate
its children, and (b) any `TextButton` under 44px. **That has not run.**

Also unverified:
- The test suite has **not been executed** this session. Baseline before this work:
  **21 suites / 3,547 assertions / 0 failing.** The new assertions should move the count
  — a green suite at an *unchanged* count means it ran over stale code (L-019/L-020).
- **Studio Script Analysis (P-1) has not been read.** A human must look at the panel;
  it is not exposed to MCP, and it catches what no test can.
- **Nobody has looked at the panels.** Per L-051: when a number and a screenshot
  disagree, the screenshot wins. The numbers above are encouraging, not sufficient.

---

## 5. RESUME HERE

1. Re-run `list_roblox_studios`, confirm source sync, then **run the interrupted
   full-panel sweep** (overlap + touch targets across all 9 overlays).
2. **Run `tests/RunAll.server.luau`.** Expect > 3,547 assertions. Investigate any
   count that has not moved.
3. **Read Script Analysis** — zero errors *and* zero warnings (NFR-8).
4. **Look at every panel.** Screenshot SHOP, SHAPES, SLOTS, FORGE.
5. Only then commit. Suggested split: UITheme + emoji sweep, then the panel rebuilds,
   then previews. **One commit per concern.**
6. Ledger entries to write at Gate 6 (drafted, not yet appended):
   - a paren-initial statement silently disabling an entire test file
   - two states sharing one visual channel, where the restore clobbers the other
   - a validation note describing what was fixed rather than what the check reports

---

## 6. STILL OPEN, UNCHANGED FROM HANDOFF 5

- **Sub-pixel shearing on distant dice** — untouched, and deliberately so. Four attempts
  have each passed their own numeric check and failed visually; the circuit breaker
  trips at three. **Do not attempt a fifth inside a UI commit**, and do not touch glyph
  geometry. Sign off from a screenshot.
- **Housekeeping before ship:** `ASCEND_MIN_LIFETIME_CASH` → `1e6`
  (`DiceCatalog.luau:338`); `PLAYTEST_DIE_COUNT` → `0`
  (`ServerBootstrap.server.luau:168`, currently `1` for dice testing).
- **Blocked on operator:** 9 audio asset IDs, `GROUP_ID`, element unlock decisions,
  `src/Client/LegacyUI/` deletion.
- **Open balance questions:** raise `MAX_DIE_SLOTS` past 7? Does the ascension spending
  tradeoff feel punishing?
