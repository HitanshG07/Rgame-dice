# Handoff 7 — the UI is connected, aligned and uniform

> **This is a historical record. Do not action anything in it.**
> Superseded by **`docs/handoff-8.md`** (current state) and **`docs/ROADMAP.md`**
> (the plan and the live open-item list). Where this document and those two
> disagree, **they win** — they were verified against live code on 2026-08-26 and
> this one was not.
>
> **Two claims in this document are known to be FALSE and are corrected in
> `docs/handoff-8.md` §4:**
>
> 1. **§3 says “23 audio asset IDs”. The real count is 9** — 8 SFX cues and one
>    music loop, verified by direct grep of `AudioDirector.luau`. Handoffs 1–6 all
>    correctly said 9; this document introduced the error.
> 2. **§5 says “nothing outstanding”** while 158 Script Analysis warnings were open
>    and recorded two sections above it in this same file. **Treat §5 as void.**
>
> **Still valid:** the `Vendor/ProfileStore.luau` warning-policy problem it raises
> is real and is still the first decision blocking NFR-8.

**Written:** 2026-08-18, end of session. **HEAD: `6b79a66`.**
Tree clean apart from `.mcp.json` and untracked operator tooling.
Supersedes the open items in `docs/handoff-6.md`; that document's §4 verification
list is now complete.

---

## 1. STATE

**21 suites, 0 failed, 3,565 assertions.**
Everything below was verified in a running Studio session, not by reading code.

**SCRIPT ANALYSIS IS NOT CLEAN — 158 WARNINGS. Earlier handoffs and commit
messages in this project claim zero; that claim is FALSE.** The operator
confirmed zero on 2026-08-16 for the code as it stood, and I repeated that
result for two days without re-reading the panel. A verification someone else
performed once is not a standing guarantee. Six were fixed at `73b1b82`
(163 -> 158); the rest are open and are the first task of the next session.

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

### Script Analysis: 158 warnings, spread over 20 files

Fixed at `73b1b82`, each confirmed by reading the code rather than trusting the
report:
- `ProgressionService:92` — `string.upper(string.gsub(...))` passes TWO
  arguments, because `gsub` returns the string AND a replacement count. A real
  defect, not a type nit.
- `ProgressionService:146` — `IsInGroup` deprecated, now `IsInGroupAsync`. It
  yields, which is why the surrounding `pcall` matters.
- Three currency mismatches — quest, chest and login reward kinds were typed
  `string` and passed to a function wanting the union. `EconomyService.Currency`
  is now **exported** and used at those declarations, fixing the class at source
  rather than casting per call site. A `:: any` at `ProgressionService:79` was
  masking the same thing.
- `PurchaseService` — `entry` re-bound to a non-optional local, because the nil
  check's narrowing did not survive to the `string.format` calls below it.

**Still open, and the first decision is yours:**
- **`Vendor.ProfileStore` is 2,242 lines of THIRD-PARTY code by loleris.** Do
  not edit it — an upstream upgrade would clobber the changes. It needs a policy
  instead: `--!nonstrict` at its head, or exclusion from analysis. Likely a large
  share of the 158, so decide this before counting anything else.
- The remainder spread across the client modules and the test suite. Work them
  file by file; several are the same classes fixed above (lost narrowing,
  loosely typed catalog fields), so exporting a type usually clears a group at
  once.

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

**Script Analysis must reach zero first (NFR-8) -- see §3.** Otherwise the
constants are ready: `ASCEND_MIN_LIFETIME_CASH` is at `1e6` and
`PLAYTEST_DIE_COUNT` at `0` — both already restored to shipping values.
`MAX_DIE_SLOTS` is 12, ladder 3 → 12 across nine ascensions.
