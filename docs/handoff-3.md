# HANDOFF 3 — Defect batch closed, animation rebuild specified

> **This is a historical record. Do not action anything in it.**
> Superseded by **`docs/handoff-8.md`** (current state) and **`docs/ROADMAP.md`**
> (the plan and the live open-item list). Where this document and those two
> disagree, **they win** — they were verified against live code on 2026-08-26 and
> this one was not.
>
> **Specifically stale here:** the animation rebuild it specifies was built and
> shipped. **Still valid:** the Void threshold of 0.35 was measured, not picked;
> manual rolling is deliberately slower than auto-roll so the gamepass confers a
> real advantage; and FR-1.4 — no die may come to rest outside the tray — remains
> the hard invariant any arena change must hold.

**Date:** 2026-08-13
**Head:** `1a43510` · 21 suites, 3,546 assertions, 0 failing · working tree clean

**Status:** the S1/S2 batch is DONE and verified. S3-a is done. The animation
rebuild is SPECIFIED BUT NOT STARTED — the operator asked for this document
first and will give the go-ahead.

---

## 1. WHAT LANDED THIS SESSION

Nine defects from the operator's play report, across two commits.

### `47a3535` — six defects

| Item | Sev | Evidence it works |
|---|---|---|
| Vault accrued while idle in-game | S1 | 12s idle held at `$28.20K / 51s` exactly; claim → `$0`, no refill |
| ROLL spammable | S1 | 20 rapid **remote** calls bypassing the client cooldown → 7 accepted, 13 refused |
| Void faces never appeared | S2 | Flat D2 `0%`; forged to 55/5 → **92%**, streak broke on nearly every roll |
| Slot cap not tied to ascensions | S3 | Showed "4 dice, limit 6" at 3 ascensions |
| Dice faces dark-shaded | S5 | Flat shadowless in screenshot |
| AUTO caption ambiguous | S5 | `AUTO OFF` grey ↔ `AUTO ON` cyan + glow |

Plus the **Sound Effects toggle** reading as on-and-stuck — my design error, an
unavailable row now forces its DISPLAY off while leaving the stored preference
intact for when audio ships.

### `1a43510` — the +2 Die Slots pass was never granted

**This was a real money bug.** `StateSyncService.buildSnapshot` computed
`dieSlots = data.DieSlots + bonusDieSlots(player)` — applying the gamepass at
**display time**. Nothing persisted it and no dice were created, so a pass owner
was told they had four slots while `d.Dice` held two.

Both of the operator's symptoms were this one defect: `DiceRenderer` draws one
tile per real die, so the board showed two while the panel promised four, and
`BoardView` positioned them for a population that did not exist — the overlap.

The entitlement is now materialised into the profile once at join, guarded by a
`PassSlotsGranted` counter so it cannot stack. Verified 4 slots / 4 dice / 4
tiles, idempotent across rejoin.

**Worth recording how it was found (L-043).** I assumed a bad *write*, built a
lockstep helper and a reconcile repair, and confirmed both worked in isolation
while the live profile stayed broken. One temporary log settled it —
`RECONCILE die-slots: in slots=2 dice=2 -> out slots=2 dice=2`. The stored
profile was *consistent*; the number was invented downstream of everything I was
auditing. **When every writer checks out, instrument the read.**

### Two decisions the operator made

- **Void threshold** raised, and the value was *measured* rather than picked. A
  first pass at `0.15` left `D2 55/5` safe and called a 20-mass face safe beside
  a 500-mass sibling. Cases separate cleanly — everything that should void sits
  at ≤0.333, everything that should not at ≥0.667 — so **0.35** sits in the empty
  band. A flat die is exactly 1.0 of its own average at every face count, so the
  clause that an un-forged die can never void still holds. **UT-14 Balance still
  passes**, so FR-6.3's crossover survived.
- **Manual rolling is slower than auto-roll** (2.5/s vs the 5/s auto ceiling), so
  the Auto-Roll gamepass confers a real advantage. `API_DATA_CONTRACT §2.2` was
  amended rather than the test simply flipped.

---

## 2. THE ANIMATION REBUILD — SPEC AND THE HONEST PROBLEM

The operator supplied a full specification and asked for it to be built. This
section records it, and states plainly why it is a **rebuild** rather than a
tuning pass.

### 2.1 What the operator asked for

1. **Natural 3D parabolic gravity throw.** Dice drop from above the felt on a
   real gravity curve with end-over-end tumbling (pitch/yaw/roll), then take
   **two dampened floor bounces** before settling.
2. **100% dynamic organic scatter.** No fixed slots, no grid, no cards. Landing
   coordinates and rest tilt **randomised on every throw** — no two rolls alike.
   Mixed shapes intermingle across the felt rather than clustering.
3. **Slim result summary bar** at the bottom edge of the board.
   Single die → `D2: 2`. Multiple → `4x D6 (SUM: 18)`.
4. **Maximised, unclipped framing.** Tray `0.670 × 0.660`, 16px buffer from all
   HUD edges, slim 1.5px warm-bronze border `RGB(56, 44, 36)`, camera distance
   `max(12, radius * 3.4)` so no die clips at any angle.
5. **It must not feel boxed in.** Smaller rendered dice are acceptable if the
   motion reads properly.

### 2.2 What already matches

- Tray is **already** `TRAY_W = 0.670`, `TRAY_H = 0.660` — spec-compliant.
- The result summary bar exists and already formats `4x D2 (SUM: 5)`.
- All 8 catalog shapes now generate models (fixed earlier, L-041).

### 2.3 THE ARCHITECTURAL BLOCKER — read this before starting

**Every die lives in its own `ViewportFrame`, anchored to a precomputed grid
slot.** That is the "restricted box" feel, and it is structural, not cosmetic:

- `BoardView.buildLayouts()` precomputes fixed row plans for 1–7 dice
  (`{1}, {2}, {3}, {2,2}, {3,2}, {3,3}, {4,3}`).
- `BoardView.getAnchor(index, count, extent)` returns a **deterministic**
  position from that table. Same index and count → same pixel, every time.
- `DiceRenderer` gives each die a **separate** ViewportFrame with its **own**
  camera, then tweens that frame's `Position` across the screen.

**Consequences that block the spec directly:**

- **Requirement 2 is impossible as built.** There is no randomisation anywhere
  in the landing path. Dice cannot scatter organically because their positions
  are looked up from a table, not simulated.
- **Dice cannot intermingle or interact.** They are in separate viewports —
  separate 3D scenes. They cannot occupy a shared floor, cannot be near each
  other in 3D, and could never collide.
- **A "floor" does not exist.** Bounces would have to be faked per-viewport
  against an imaginary plane, and each die's felt would be its own.
- **The 20-dice case is not reachable.** `MAX_DICE = 7` in both `BoardView` and
  `DiceRenderer`, and FR-1.1 specifies 1–7. The spec mentions up to 20 — **this
  needs an operator decision**, and note that raising the ceiling was already
  identified as needing new layouts and re-tuned scaling.

### 2.4 The two honest routes

**Route A — one shared ViewportFrame for the whole tray.**
Replace the seven per-die viewports with a single one covering the board, one
camera, and all dice as models inside that one 3D scene at real 3D coordinates.
Animate in **3D space** (a genuine parabola plus damped bounces) rather than
tweening 2D frame positions.

*This is what the spec actually describes.* It makes organic scatter, shared
floor, intermingling and real bounces all natural rather than faked. It is a
substantial rewrite of `DiceRenderer`'s layout and animation core and touches
`BoardView`'s anchor contract — the FR-1.4 containment guarantee would move from
`clampToBoard` on a 2D point to a 3D bounds check.

**Route B — keep per-die viewports, randomise within them.**
Add jitter to each die's anchor, randomise rest tilt, and fake two bounces on the
2D tween. Much smaller change, no architectural risk.

*It will not deliver the spec.* Dice still cannot intermingle or share a floor,
and with each die confined to its own frame the "boxed in" feeling largely
remains — which was the operator's actual complaint.

**Recommendation: Route A.** It is the only one that answers the complaint. It
should be done as its own change with its own verification, not folded into a
defect batch — the containment guarantee and the whole roll-feedback path run
through this code.

### 2.5 Verification this will need

Per L-031, geometry and motion are verified by LOOKING, not by counting:

- Screenshots mid-tumble, not only at rest.
- Several consecutive rolls compared — the spec's core claim is that **no two
  land alike**, which a single frame cannot show.
- 1, 2, 4 and 7 dice, since layout behaviour changes with count.
- FR-1.4 still holds: **no die may come to rest outside the tray.** This is the
  one hard invariant the rewrite must not break.

---

## 3. STILL OUTSTANDING

### Requested, not started
- **S3-c — buy duplicates of the same shape.** Schema change:
  `Diamond.Shapes` is a boolean set and cannot represent owning two D6s. Every
  reader (`SetShape`, `canUnlock`, the panel, migration) must handle both the old
  boolean form and the new counted one. Touches saved data — do it deliberately.
- **S3-d — choose which die sits in which slot (forge).** The data model already
  supports it (`d.Dice` is an ordered array); this is mostly UI plus a reorder
  remote.

### Deferred by the operator
- **Tiered vault rates** — standard / in-game VIP / Roblox Premium. Note the rate
  is currently derived from the player's own recent average income, so this is a
  change of *model*, not a multiplier. `OfflineService.getEfficiency` is the
  seam; `Player.MembershipType` gives Premium server-side.
- **Audio** — 9 `DUMMY_ID_*` placeholders. Fails closed; Settings says so
  honestly. Dropping real ids into `ASSET_IDS` is the only change needed.

### Blocked on the operator
- Roblox group id (`GROUP_ID = 0`); group rewards built and commented out.
- Balance tuning unvalidated against real play.
- **Does the 20-dice figure in the animation spec supersede FR-1.1's max of 7?**

### Housekeeping
- **`ASCEND_MIN_LIFETIME_CASH` is `100000` for testing — SHIP `1e6`.**
  One clearly-marked line in `DiceCatalog`.
- Element unlocks (Fire/Freeze/Gold/Multiplier) built server-side, no unlock
  path; belongs in ASCEND.
- `src/Client/LegacyUI/` is dead duplicate code awaiting deletion.

---

## 4. SUGGESTED ORDER FROM HERE

The operator asked for **S3-a, S3-d, S3-c first**, then the animation.
S3-a is already done, so:

1. **S3-d** forge slot assignment — self-contained, data model already supports it
2. **S3-c** duplicate shapes — schema change, migrate carefully
3. **Animation rebuild** — Route A, its own change, its own verification

Ledger entries added this session: **L-039** … **L-043**.
