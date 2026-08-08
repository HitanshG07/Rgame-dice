# Block 4 — Consolidated close-out (Gate 4, Gate 5, Swarm Report)

**Head:** `d30b53a`
**Date:** 2026-08-09
**Block:** 4A (client spine) · 4B (board + renderer + FX) · 4C (HUD, forge, menu, audio)

---

## 1. What Block 4 delivered

The client. Before this block the game was a correct server with no way to see
it; the player-facing layer existed only as a specification.

| Module | Lines | Role |
|---|---:|---|
| `UITheme` | 151 | palette + sanctioned surface builders (orchestrator-owned) |
| `NetClient` | 277 | **sole** outbound wire boundary; no generic `invoke` |
| `ClientBootstrap` | 327 | MODULE_ORDER, fatal panel, teardown, **the seams** |
| `AudioDirector` | 351 | 9 cues, all `DUMMY_ID_*` |
| `BoardView` | 541 | 2D tray, slot geometry, FR-1.4 containment, backdrop |
| `FeedbackFX` | 598 | floating payout text, particles, screen feedback |
| `DiceRenderer` | 702 | flat tumble, weight bars, heavy-side drag |
| `HUD` | 894 | top/bottom bars, Void readout, like goal |
| `MenuPanel` | 1,131 | left/right sidebars, settings |
| `ForgePanel` | 1,556 | the primary surface (FR-13.8) |
| **Total** | **6,528** | |

Plus `UT-13 ClientContract` (28 assertions), which requires **every** client
module — the check that would have caught the very first defect of this block.

---

## 2. Gate 4 — Security

| Threat | Rule | Verdict |
|---|---|---|
| T-8 | no `RemoteFunction:InvokeClient()` | **PASS** — 0 code occurrences |
| T-11 | no `SetAsync` for profile data | **PASS** — 0 first-party |
| T-17 | exactly one `ProcessReceipt` | **VACUOUS** — no monetisation code exists (Block 5) |
| R-8 | no `MessagingService` in V1 | **PASS** — 0 first-party |
| NFR-5 | no price/balance/reward/score/multiplier/duration on a client message | **PASS** — one boundary module, two call sites |
| FR-12.6 | Robux ids are fail-closed placeholders | **PASS** — 9 ids, all `DUMMY_ID_*` |

Full method and the false-positive retraction: [`P3_CLIENT_BOUNDARY.md`](P3_CLIENT_BOUNDARY.md).

**T-17 is recorded as VACUOUS, not PASS.** Zero is not one. Marking it green
would be [[L-027]] committed knowingly, and it must be re-read the moment
`MarketplaceService` first appears.

**Structural note.** The client cannot leak what it never receives:
`StateSyncService` builds its snapshot field-by-field, so `PurchaseIds` and
`CodesRedeemed` have no path to the wire. That is a Gate 4 *reading*, not a grep
result, and it is why NFR-5 is defensible rather than merely un-matched.

---

## 3. Gate 5 — Verification

**Static.** P-1 Script Analysis: **0 errors, 0 warnings** — first-party *and*
vendor, read from the panel by the operator.

**Suite.** 10 suites, 0 failed, **3,370 assertions**, run on the live head.

**Runtime, measured rather than asserted** — sampled off the running Instance:

| Property | Measurement | Expected |
|---|---|---|
| Tumble travel (3D, before replacement) | 2,199° / 6.11 turns | 1,170–2,790° |
| Tumble travel (2D, current) | 3,993° / 11.09 turns | multi-turn |
| Direction reversals | 1 | 0–2 (settle lean, not rewind) |
| Deal-in travel | Y 0.050 → 0.521 | enters from above |
| Final rotation | 0.00° | lands square |
| Bootstrap | 7 modules, no FATAL | all declared |

**Operator-confirmed gameplay (P-4 row 6, the load-bearing row):** max mass onto
face 6 → *"it never lands."* This is the inverted-mass mechanic (FR-2) observed
end to end for the first time. It is the single most important behavioural
confirmation in the project and it now has a witness.

**VOID 19.7% investigated.** Not a regression: a default even D6 computes
0.0000, and the on-screen weight bar reads 0.05, so the die is the one the
operator forged during the row-6 test. Renderer and HUD agree.

---

## 4. Swarm Report (required by `.brain/modes/swarm.md` §8)

**Fan-out.** 7 workers built 7 elements; 7 verifiers audited them. Disjointness
on write sets was proven before dispatch and **held** — no two workers wrote the
same file. `UITheme` was orchestrator-owned precisely so it could be shared
without contention.

**Output.** ~5,236 lines in ~25 minutes of wall time, then **47 findings** across
the verifier pass.

**The honest number, recorded in `skills/roblox_luau.md` §9 and restated here:
parallel authoring is fast and does *not* reduce verification cost.** Seven
workers cut authoring from days to under half an hour and produced a 47-finding
queue that had to be worked serially. The speedup is real and it is confined to
one phase.

**What only the swarm could find.** Three workers in isolated contexts
independently reported the missing `StateSync` producer ([[L-027]]) — each having
hit a *different* consequence. Four verifiers found `voidProbability` disagreeing
with the server ([[L-026]]) after five Block 3 audit rounds had missed it. Both
were invisible to sequential review and became obvious under fan-out.

**Orchestrator failures, logged.** I committed during an active fan-out and
captured a half-written `MenuPanel`; a worker caught it, I did not.

---

## 5. Defects found by *running* what static checks had passed

Recorded because the pattern is the finding, not the individual bugs.

1. **The one-sweep fix shipped a crash.** Removing ForgePanel's edge tab left an
   orphaned `bind(tab, ...)` 170 lines below the deleted block. Type-checked,
   built, and aborted the bootstrap at `init`. I had reported the sweep as
   "statically verified" — accurate, and worth nothing here.
2. **The 2D board rendered with the Roblox world showing through** — baseplate,
   sky, avatar. `ArenaView`'s camera framing had been the only thing suppressing
   them, a duty with no export and therefore no grep signature. → **[[L-028]]**
3. **`ANCHOR_LIFT = 3.5` survived a coordinate-system change** — correct as
   studs, three and a half screen heights as scale. Valid number, valid type,
   passing suite. → **[[L-029]]**

All three are the same class: **the check that would have caught it could not
reach where the defect lived.**

---

## 6. Verdict

**Block 4: COMPLETE.** Gate 4 PASS (T-17 vacuous, tagged). Gate 5 PASS on
static, suite, and measured runtime. Swarm report filed.

The game is playable, the core mechanic has been observed working, and the
client renders honestly — every unbacked control reads `(SOON)` rather than
pretending.

## 7. Known-open, carried forward

- **`SetAutoRoll` has no server handler.** The control reads `(SOON)`, so the UI
  is honest, but the row is unimplemented.
- **FR-13.6 settings persistence** needs a remote and a profile write. Currently
  session-scoped, stated as such on screen, with a ClientBootstrap workaround
  re-asserting local toggles after every StateSync so a snapshot cannot silently
  revert a player's choice. **This is a workaround for a missing feature, not a
  design.**
- **Block 5 is blocked on the operator:** four gamepasses and four developer
  products must be created and their real asset ids supplied. Agents do not
  create monetized assets.
- **P-6B balance sweep will change `DiceCatalog` constants.**
- **2D trade-off accepted with cost stated:** the inverted-mass mechanic is no
  longer *watchable* the way a tumbling lopsided solid was. Weight bars and the
  heavy-side settle drag are compensation, not equivalence. If it reads as pure
  RNG to players, that is the cause.
