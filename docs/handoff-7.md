# Handoff 7 — the UI is connected, aligned and uniform

**Written:** 2026-08-18, end of session. **HEAD: `6b79a66`.**
Tree clean apart from `.mcp.json` and untracked operator tooling.
Supersedes the open items in `docs/handoff-6.md`; that document's §4 verification
list is now complete.

---

## 1. STATE

**21 suites, 0 failed, 3,565 assertions. Zero Script Analysis warnings.**
Everything below was verified in a running Studio session, not by reading code.

---

## 2. WHAT LANDED THIS SESSION

### The big one: every menu panel was dead, not just settings

Reported as "settings completely unhooked". It was all seven panels — the slots
headline was empty, no shop card showed its OWNED chip, and all four settings
toggles read ACTIVE including the two gated on audio that does not exist.

**Cause:** `refreshShop` was re-declared with `local function` inside a nested
block, so `shopRefresh = refreshShop` several hundred lines later read an
undeclared name and stored `nil`. The fan-out used `ipairs`, **which stops at the
first nil** — and shop was first. Six unrelated panels died from one scoping
mistake in a seventh. Both halves are silent: Lua does not warn on the nil read,
and the truncated loop raises nothing.

**Second, independent break in the same path:** the void-risk helper read
`face.Mass` and scored anything else 0, so a snapshot with plain numeric faces
produced an all-zero mass list, `ForgeMath` raised, and **that error escaped the
whole StateSync handler**.

Fixed at `c8c7482`. The fan-out now iterates a named list, skips a nil rather
than terminating, and warns which refresher is missing.

### Everything else

| | commit |
|---|---|
| 3D gear replaces the decal, spins on hover | `a1ddc0c` |
| Gear plate, framing, hub hole restored; 45 → 20 parts | `4fab4e1` |
| Overlays centred by respecting the inset | `cbee343` |
| Shop/settings aligned to shapes (16/16), scrim lightened | `bd25813` |
| Buy buttons on one line; scrim covers the topbar strip | `6d15602` |
| Shop type raised; short cards fill their space | `42208bc` |
| Last six shop cards given their description row | `8e3252a` |
| Brain: 3 ledger entries, 5 Luau traps, UI collections section | `6b79a66` |

---

## 3. WHAT IS STILL OPEN

### Blocked on you — cannot be done in code
- **23 audio asset IDs** (`DUMMY_ID_*` in `AudioDirector.luau`). The game is
  silent, and Music/SFX correctly render **LOCKED** until these exist.
- **`GROUP_ID = 0`** in `ProgressionService.luau:126` — group reward inert.

### Untracked, your call
- `src/Client/UIMockPreview.luau` — Antigravity's mock, never wired in.
- `src/Client/settings_gear.jpg`, `gp_images/settings_gear.jpg` — superseded by
  the procedural gear. Rojo does not sync images, so they reach nothing.

### Not attempted, deliberately
- **Sub-pixel dice shearing is CLOSED** — it was the D10/D14 chamfer wedges at
  0.0097 studs, not the numerals. Fixed at `cbfb2a8`. Zero sub-pixel parts across
  all twelve dice.
- No other deferred work. The handoff-6 queue is empty.

---

## 4. NOTES FOR THE NEXT SESSION

- **`TextFits` is not a containment check.** It reports truncation, and
  `AutomaticSize` makes it permanently true. It reported clean while text
  rendered straight through a button. Test rectangles instead (L-058).
- **A `UIListLayout` owns every child and overrides `Position`.** Pinning one
  child to an edge only changes its sort order.
- **Identical output from two different formulas means stale code**, not
  stubborn arithmetic. One `Source` read distinguishes them (L-041, L-059).
- **`execute_luau` has its own module cache**, so it cannot inspect live service
  state. Use a temporary probe in the real script and read the console.
- Snapshots are **event-driven**; an idle client receives none. Trigger a real
  roll before concluding the data path is broken.

---

## 5. BEFORE SHIP

Nothing outstanding. `ASCEND_MIN_LIFETIME_CASH` is at `1e6` and
`PLAYTEST_DIE_COUNT` at `0` — both already restored to shipping values.
`MAX_DIE_SLOTS` is 12, ladder 3 → 12 across nine ascensions.
