CONSUMED-BY: Operator / session-start directive
STATUS: LIVING — amend when a block lands or scope changes

# EXECUTION ROADMAP — DICE FORGE INCREMENTAL
## Every remaining step, as a runnable prompt

This file is the operator's control panel for the rest of the build. Each section
is a **copy-pasteable prompt**. Paste one, wait for its EXIT ARTIFACT, then move to
the next. Nothing here requires you to remember project context — each prompt
re-anchors the assistant itself.

**Read §1 first.** It tells you which prompt to run when. Everything after §1 is
the prompt text.

---

## 0. HOW TO USE THIS FILE

1. Find your position in the **§1 master sequence**.
2. Copy the prompt body verbatim (the fenced block only — not the WHEN/EXIT notes).
3. Paste it into a fresh or continuing Claude Code session in `c:\RGame`.
4. Do not run the next prompt until the current one's **EXIT ARTIFACT** exists.
5. If something breaks mid-block, jump to the matching **§8 contingency prompt**,
   then resume where you left off.

**Three rules that hold for every prompt below:**

- **No prompt authorises skipping a gate.** If an assistant reports a block
  complete without the exit artifact, it has not completed the block.
- **A green test suite at an unchanged assertion count is not a pass** (ledger
  L-020). Every construction prompt below demands the new count explicitly.
- **Asset IDs are now REAL** (all 14 supplied 2026-08-09 and wired into
  `MonetisationCatalog`). Audio cues remain `DUMMY_ID_*` and must stay that way
  until the operator supplies sound ids. An item's id existing does **not** mean
  the game can honour it — gate on `isSellable`, never `isResolved`.

---

## 1. MASTER SEQUENCE — WHICH PROMPT, WHEN

**Last reconciled against the repository: 2026-08-09, head `14fe582`.** Every
DONE row below was verified by running the game, not by reading a report.

| Order | Prompt | Status | Blocking on you? |
|---|---|---|---|
| 1 | **P-3A** Block 3 construction | ✅ DONE | — |
| 2 | **P-3B** Block 3 Gate 2 verification | ✅ DONE | — |
| 3 | **P-3C** Block 3 Gate 3+4 audit | ✅ DONE — 5 rounds, 12 findings | — |
| 4 | **P-3D** Audit remediation | ✅ DONE | — |
| 5 | **P-4A** Client foundation | ✅ DONE | — |
| 6 | **P-4B** Board + dice renderer | ✅ DONE — 2D board, 3D dice in ViewportFrames | — |
| 7 | **P-4C** Forge panel + HUD + menus | ✅ DONE — 6,528 lines, 10 modules | — |
| 8 | **P-4D** Block 4 Gate 2 + P-4 smoke | ✅ DONE — row 6 confirmed by operator | — |
| 9 | **P-4E** Block 4 Gate 3+4 audit | ✅ DONE — `BLOCK4_CLOSEOUT.md` | — |
| 10 | **P-5.0** Robux asset creation | ✅ DONE — all 14 ids supplied | — |
| 11 | **P-5A** Monetisation backend | ✅ DONE — receipts, entitlements, catalog | — |
| **12** | **P-5A2** Apply the pass effects | **⬅ NEXT. Passes are sellable and do nothing.** | No |
| 13 | **P-5A3** Shop UI | After P-5A2 | No |
| 14 | **P-5B** Offline vault + Leaderboards | After P-5A3. Unblocks 3 dead products. | No |
| 15 | **P-5B2** Timed boosts | With or after P-5B | No |
| 16 | **P-5C** Progression + Ascension | After P-5B | No |
| 17 | **P-5C2** The 12 unhandled remotes | After P-5C | No |
| 18 | **P-5D** Block 5 Gate 2 | After P-5C2 | Yes |
| 19 | **P-5E** Block 5 Gate 3+4 audit | P-5D clean | Yes |
| 20 | **P-6A** Integration suites IT-1…IT-5 | Block 5 signed off | No |
| 21 | **P-6B** Balance tuning pass | P-6A clean | No |
| 22 | **P-6C** Performance pass (NFR-1/2) | P-6B lands | Yes — MicroProfiler |
| 23 | **P-6D** Full P-1…P-4 pre-launch sweep | P-6C lands | Yes |
| 24 | **P-6E** Final cross-vendor security audit | P-6D clean | Yes |
| 25 | **P-7A** Launch readiness + publish | P-6E returns SECURE | **Yes — you publish** |
| 26 | **P-7B** Post-launch monitoring setup | Published | No |

**Run any time, out of band:** §7 standing prompts (handoff refresh, commit,
ledger harvest) and §8 contingencies (Rojo desync, MCP loss, red-flag recovery).

---

### ⚠ TWO LIVE HAZARDS — read before running anything

**1. Four gamepasses are sellable right now and have no effect.**
`PurchaseService` implements `cashMultiplier`, `bonusDieSlots`,
`forgeCostMultiplier`, `hasStreakShield` and `hasAutoRoll` correctly — and
**nothing calls any of them** (verified: zero callers outside their own module).
A player who buys 2x Cash today gets 1x. **P-5A2 closes this and should be run
before anyone can reach the store page.**

**2. Three developer products cannot be delivered.**
2x Luck Boost, 2x Offline Payout and Time Skip (24h) need timed boosts and
offline accrual — neither system exists. `applyGrant` refuses them, so the
receipt answers `NotProcessedYet` and Roblox retries forever while the player has
paid. They are marked `unavailable` so no shop UI will offer them, **but they
remain purchasable through Roblox's own experience store page.** Either disable
those three on the dashboard until P-5B/P-5B2 land, or accept the exposure
knowingly.

---

## 1B. WHERE THE GAME ACTUALLY STANDS — and what "finished" requires

*Written 2026-08-09 against head `19efd31`. Every claim here was checked by
running the game or grepping the source, never by trusting an earlier report.*

### What is real and working

The **core loop is complete and proven**: roll → server samples from the mass
distribution → payout credits → StateSync → the board animates a real 3D die
onto the face the server chose. Forging, shape changes, elements, streaks, Void
faces, persistence and rate limiting all work. 10 suites, 3,370 assertions.

The **inverted-mass mechanic** — the whole reason this game exists — has been
observed working end to end by the operator. That is the single most important
fact in this file.

### The shape of what is left

Almost everything remaining is **breadth, not depth**. The hard, novel,
easy-to-get-wrong parts are done. What remains is largely: *systems that were
specified, have UI already saying `(SOON)`, and need building.*

Four groups, in the order they should be built:

**GROUP 1 — make what is already SOLD actually work.** (P-5A2, P-5A3)
This is not new scope; it is closing a gap between what the platform will sell
and what the game will deliver. Highest priority by a distance, because it is
the only remaining work where the failure mode is *a real person loses money*.

**GROUP 2 — the systems three products depend on.** (P-5B, P-5B2)
Offline earnings and timed boosts. Until these exist, three developer products
cannot be honoured. Building them converts three dead SKUs into live ones and
unlocks the vault UI the HUD already gestures at.

**GROUP 3 — the rest of the specified game.** (P-5C, P-5C2)
Progression, Ascension, and the twelve declared-but-unhandled remotes. This is
where most of the `(SOON)` labels get replaced by working buttons.

**GROUP 4 — hardening and launch.** (P-6A … P-7B)
Integration suites, balance, performance, the pre-launch sweep, a final
cross-vendor security audit, then publish.

### How the pieces connect

```
   P-5A2 ── passes take money and DO something
     │
   P-5A3 ── a shop exists, gated on isSellable
     │
   P-5B ─── offline earnings accrue        ┐
     │                                     ├─ together, the 3 dead products
   P-5B2 ── boosts tick and expire         ┘  become deliverable
     │
   P-5C ─── progression + ascension
     │
   P-5C2 ── every declared remote has a handler (or is deleted)
     │
   P-5D / P-5E ── Block 5 gates
     │
   P-6A…P-6E ── integration, balance, performance, sweep, security
     │
   P-7A ── publish
```

### The rules that carry forward

These have each been paid for with a real defect. They are not style notes.

- **Verify by running it, not by reading a report.** Blocks 3 and 4 both shipped
  defects that every static check passed. The dice passed *every numeric check*
  while rendering as six-pointed stars (L-031).
- **A green suite at an unchanged assertion count is not a pass** (L-020).
- **Match the evidence to the artifact.** Visual work needs a screenshot from an
  angle where the expected failure would show (L-031).
- **Audit the contract in the producer direction.** For every declared event or
  endpoint, find the code that emits it. A row with no producer is a finding
  (L-027) — this is exactly how the twelve unhandled remotes were found.
- **Before deleting a module, list what it touches outside itself** (L-028).
- **When a coordinate system or unit changes, re-state every constant** (L-029).
- **Fail closed, and never let "the asset exists" mean "we can deliver it."**

### What only the operator can do

| Task | Why it cannot be automated |
|---|---|
| Disable the 3 undeliverable products on the dashboard | Roblox's own store page is outside anything the code controls |
| Supply audio asset ids | Agents do not create monetised or uploaded assets |
| P-1 Script Analysis readings | Not exposed through the MCP surface |
| Balance judgement (P-6B) | The numbers are a design opinion, not a correctness property |
| Publishing (P-7A) | The operator's account, the operator's decision |

---

# 2. BLOCK 3 — SERVICE LAYER COMPLETION

## P-3A — Block 3 construction  ✅ DONE

> **COMPLETE — do not re-run.** Landed after 5 audit rounds and 12 findings. The die contract is now a single executable function (`ForgeService.assertDieInvariant`).

**WHEN:** Now.
**PRECONDITION:** Blocks 1–2 complete through Gate 4; `master` clean.
**EXIT ARTIFACT:** 6 new files on disk, committed, with a stated expected assertion delta.

```
Boot per CLAUDE.md — this session MODIFIES FILES, so parse the full bootloader,
.brain/PERSONAS.md, .brain/PIPELINE.md, and consult .brain/LEDGER.md before
constructing. Read docs/blueprint/HLD.md §3, docs/blueprint/SRS.md FR-3/FR-4/FR-6,
and docs/blueprint/TEST_PLAN.md §4 UT-5 through UT-8.

Execute BLOCK 3 — the service layer. Sequenced construction, no swarm, no
sub-agents unless I ask.

BUILD, in this order:

1. src/Shared/DiceCatalog.luau
   - Shape definitions for D4, D6, D8, D12, D20: face count, per-shape mass floor,
     per-shape Cash budget cap and Diamond budget ceiling (SRS FR-6.1, FR-3.6).
   - RollService.MASS_FLOOR MUST MOVE HERE. It is currently a single constant in
     RollService; it is per-shape data. Update every call site and say which ones
     you changed.
   - Shapes are a build choice, never a tier ladder (FR-6.1). If your numbers make
     one shape dominant at every Streak Strength b, that is a balance defect —
     state it rather than shipping it.

2. src/Shared/UpgradeCatalog.luau
   - Cash upgrades: AutoRollSpeed, VaultCapacity, VaultEfficiency, Luck.
   - Diamond tree: StreakStrength, MassCeiling, SlotNodes, Elements, Shapes.
   - Cost curves as pure functions of level. Must match the PlayerProfile template
     keys exactly — a mismatch here is a silent no-op at runtime.

3. src/Shared/Format.luau
   - Suffix-ladder number formatting, precision-safe to 1e300 (NFR-4).
   - Must handle NaN, inf, and negative input without producing garbage text.

4. src/Server/RateLimiter.luau
   - Extract the token-bucket logic currently inline in RemoteGateway into this
     module (HLD §3 C-1 lists it as its own module and UT-6 tests it directly).
   - Per-player, per-remote buckets. Sustained + burst per API_DATA_CONTRACT §2.2.
   - One player's exhaustion must not affect another's.
   - Rewire RemoteGateway to consume it. Behaviour must not change.

5. src/Server/ForgeService.luau
   - Applies validated mass redistribution as a CLOSED SYSTEM (FR-3.2). Reuses
     ForgeMath.validate — do not reimplement validation.
   - Forge cost scales with magnitude of mass moved and is non-trivial (FR-3.3).
     This is a CORRECTNESS requirement from ledger L-016, not a monetisation
     lever: free re-forging collapses the cross-die puzzle.
   - Element assignment and shape change live here too.
   - Any violation rejects the WHOLE proposal and mutates NOTHING.

6. src/Server/ServerBootstrap.server.luau
   - Constructs services in dependency order, wires PlayerAdded/PlayerRemoving,
     registers BindToClose with PlayerProfile.releaseAll().
   - A failed profile load KICKS with an honest message. It must never fall back
     to a default profile (FR-14.3, threat T-10).

7. tests/Fakes.luau
   - Injectable fakes for DataStoreService, MarketplaceService, Players, and
     ProfileStore. No unit test may touch a live Roblox service.
   - This unblocks performRoll, which is currently untested.

8. Test suites, per TEST_PLAN §4:
   - tests/Elements.test.luau      (UT-5) — Gold pays only at >=2 Gold dice AND
     its payoff SCALES WITH COMBINED INVESTED MASS. Assert the scaling explicitly:
     a flat conditional bonus is a defect (FR-4.3, L-016). Fire spill, Freeze
     re-roll-keep-better, Multiplier multiplies rather than adds.
   - tests/RateLimit.test.luau     (UT-6)
   - tests/ProfileSchema.test.luau (UT-7)
   - tests/ProfileLifecycle.test.luau (UT-8)
   - Plus: add performRoll coverage to the existing UT-3/UT-4 now that Fakes exists.

CONSTRAINTS (all standing, all binding):
- --!strict everywhere; zero Script Analysis warnings.
- `T.field: Type = value` is INVALID LUAU (ledger, block-1 syntax error). Annotate
  a local, then bind it to the table field.
- No client message may carry a price, balance, reward, score, level, duration,
  multiplier, or outcome (NFR-5).
- No InvokeClient. No SetAsync on profile data. No MessagingService in our code.
- No TODO / FIXME / TBD in src/.
- Asset IDs remain DUMMY_ID_* placeholders that fail closed.

BEFORE YOU FINISH, report:
- Every file written, with line count.
- The exact expected new total assertion count and the delta from 2,779. I will
  use that number as the sync canary (ledger L-020) — a suite that reports green
  at 2,779 has run over stale code.
- Anything you could not do and why. Do not report the block complete if any
  part is missing.

Do not run the tests yourself. Do not press Play. Stop when the code is written
and committed.
```

---

## P-3B — Block 3 Gate 2 verification  ✅ DONE

> **COMPLETE — do not re-run.** Suite green; assertion count now 3,370.

**WHEN:** P-3A reports code written and committed.
**YOU DO:** Confirm the Rojo plugin is Connected, then press Play.
**EXIT ARTIFACT:** `deliveries/evidence/<date>-block3-unit-suite.txt` with 8/8 passing.

```
Gate 2 mechanical verification for Block 3. Follow docs/blueprint/TEST_PLAN.md
procedures P-1, P-2 and P-3 exactly. Enumerate each step inline as you do it —
do not reference the procedure and assume it was followed (ledger L-014).

Order:
1. Confirm Rojo is actually serving and the plugin is Connected. State how you
   confirmed it. A dead sync has produced a false green TWICE on this project
   (ledger L-019, L-020).
2. P-1 static analysis — zero errors AND zero warnings. A warning is a gate
   failure, not a nit.
3. P-2 automated suite — I will press Play; you read the output.
   PASS REQUIRES BOTH: `failed` is 0, AND the total assertion count has moved to
   the number you predicted in P-3A. If the count is unchanged at 2,779, the
   suite ran over stale code — declare DESYNC, do not declare a pass.
4. P-3 prohibition greps — run all five, paste output verbatim.

Save all output to deliveries/evidence/ with today's date.

Then issue a Gate 2 verdict: MECHANICALLY-CLEAN or REJECTED-TO-GATE-1 with a
numbered defect list. If any suite fails, identify whether the TEST or the CODE
is wrong BEFORE changing either — ledger L-017 exists because I once nearly
loosened a real invariant to make a bad test pass.
```

---

## P-3C — Block 3 Gate 3 + Gate 4 audit  ✅ DONE

> **COMPLETE — do not re-run.** 5 rounds run across two vendors.

**WHEN:** P-3B returns MECHANICALLY-CLEAN.
**YOU DO:** Run the audit in your second vendor (Antigravity) and paste the result back.
**EXIT ARTIFACT:** Two verdicts with **numeric finding counts**.

```
Prepare the Gate 3 + Gate 4 audit brief for Block 3, written for a
FRESH-CONTEXT auditor in a different vendor. Write it to
deliveries/audit-briefs/<date>-block3-code-audit.md.

The brief MUST:
- Enumerate every Matrix D and Matrix E line INLINE, one row per line, with a
  verdict column. Do not write "audit against Matrix D" — a referenced checklist
  gets partially executed (ledger L-014). The last audit that did this reported
  9 lines evaluated when it had evaluated 4.
- Demand the output format:
      GATE 3 VERDICT: AUDIT-APPROVED | REJECTED-TO-GATE-1
      FINDINGS: <integer>
      GATE 4 VERDICT: SECURE | FLAGGED
      FINDINGS: <integer>
  A NUMERIC COUNT IS MANDATORY. "No findings" beside a body of text containing
  mitigation notes is a misclassification — a mitigation note IS a finding
  (ledger L-018). This requirement is what caught four real defects last round.
- Tag every finding with its threat-item ID (T-nn) or SRS requirement ID.
- List the exact files in scope with their line counts.
- State explicitly that the auditor is READ-ONLY and must never fix anything.

Include a scope note that this repository is PRIVATE, which is what permits the
threat model to be shared with the auditor. Do NOT include the Discord webhook
URL or any credential in the brief.
```

---

## P-3D — Audit remediation  ✅ DONE

> **COMPLETE — do not re-run.** All 12 findings closed.

**WHEN:** P-3C returns any finding count ≥ 1. Skip if both are 0.
**EXIT ARTIFACT:** Fixes committed + re-verified live at a moved assertion count.

```
Here are the audit results:

<PASTE BOTH VERDICTS AND ALL FINDINGS VERBATIM>

Remediate. For EACH finding, in order:

1. VERIFY IT AGAINST THE CODE FIRST. Do not accept the auditor at face value —
   auditors on this project have been wrong in both directions. State
   CONFIRMED or DISPUTED with the file:line evidence. A disputed finding gets a
   written rebuttal, not a silent skip.
2. For each CONFIRMED finding: fix it, and if it represents a threat class the
   THREAT_MODEL.md does not cover, add a new T-nn entry with its triggering fact.
3. Re-run the suite and confirm the assertion count MOVED by the expected delta.
   A green suite at the old count means the fix never reached Studio.
4. Commit with the finding IDs in the message.
5. Add a ledger entry for any finding that represents a repeatable mistake class,
   not a one-off typo.

Report a table: finding ID | CONFIRMED/DISPUTED | fix | new threat entry | test delta.
```

---

# 3. BLOCK 4 — THE CLIENT (nothing is playable until this lands)

`src/Client/` is currently **empty**. This is the largest remaining block, split
into three construction prompts so no single one is too big to verify.

## P-4A — Client foundation  ✅ DONE

> **COMPLETE — do not re-run.** NetClient + ClientBootstrap; sole wire boundary holds.

**WHEN:** Block 3 signed off through Gate 4.
**EXIT ARTIFACT:** `ClientBootstrap` + `NetClient` on disk; game boots without error.

```
Boot per CLAUDE.md (file-modifying session — full bootloader parse). Read
docs/blueprint/HLD.md §3 C-3 and §4, docs/blueprint/SRS.md FR-13, and
docs/blueprint/API_DATA_CONTRACT.md §1.

Execute BLOCK 4A — the client foundation. Two modules only. Build the spine
before the surfaces.

1. src/Client/ClientBootstrap.client.luau
   - Constructs client modules in dependency order, waits for Shared to replicate,
     fails LOUDLY and visibly if a required remote is missing rather than
     silently degrading.

2. src/Client/NetClient.luau
   - The SOLE outbound wrapper. No other client module may touch a RemoteEvent or
     RemoteFunction directly — same chokepoint principle as RemoteGateway on the
     server, so the audit surface is one file.
   - Client-side send throttling that is COOPERATIVE ONLY. State clearly in a
     comment that this is a UX courtesy and the server rate limiter is the real
     enforcement. A client-side limit is never a security control.
   - Typed wrappers over every remote in API_DATA_CONTRACT §1.
   - NO OUTBOUND MESSAGE MAY CARRY a price, balance, reward, score, level,
     duration, multiplier, or outcome (NFR-5). If you find yourself wanting to
     send one, the server-side API is wrong — tell me instead of sending it.

CONSTRAINTS: --!strict, zero warnings, no InvokeClient anywhere, Scale-based
sizing only when you touch UI, DUMMY_ID_* for any asset id.

Report files + line counts, and state exactly what is and is not yet playable.
Do not build the arena or any UI in this prompt.
```

---

## P-4B — Arena and dice renderer  ✅ DONE

> **COMPLETE — do not re-run.** SUPERSEDED IN FORM: the 3D pit was replaced by a 2D board (`BoardView`) with real 3D dice inside ViewportFrames, on operator instruction. Same requirements met, different presentation.

**WHEN:** P-4A lands.
**EXIT ARTIFACT:** A die visibly tumbles and resolves to the server's face.

```
Execute BLOCK 4B — the arena and the dice. This is the moment the game becomes
visible. Read HLD §4.3 before writing a line.

1. src/Client/ArenaView.luau
   - Contained low-poly 3D pit, top-down camera, holds 1–7 dice (FR-1.1).
   - Dice come to rest FULLY INSIDE the arena; a die that would settle outside is
     repositioned before the result is presented (FR-1.4).

2. src/Client/DiceRenderer.luau
   - THE LOAD-BEARING RULE: the server has ALREADY DECIDED the face. The renderer
     animates a tumble that RESOLVES TO that face. The physics body is decorative.
     The animation never determines, and is never read to determine, the outcome
     (FR-2.5). If the body settles wrong, correct orientation during the final
     settle — never change the result.
   - Implementation per HLD §4.3: a set of pre-authored tumble trajectories each
     ending with a known face up, plus the rotation mapping that terminal face to
     the server's face.
   - Tumble duration scales with payout so large wins feel large.
   - Instance POOLING — no allocation inside per-frame loops (NFR-1).
   - Bevelled low-poly solids with emissive numerals, face count matching shape
     (FR-1.2).
   - A die's mass distribution must be legible WITHOUT opening a menu — heavier
     faces visibly weightier via scale, glow, or inset depth (FR-1.3).

3. src/Client/FeedbackFX.luau
   - Floating payout text at the moment of credit (FR-2.8).
   - Respects the Settings particle/motion-blur toggles (FR-13.6).

CRITICAL: if the client disconnects, tabs out, or drops frames mid-animation, the
credited payout is UNAFFECTED (FR-2.6). Presentation is downstream of truth.
Write a comment at the top of DiceRenderer saying so, because the next person to
touch this file will be tempted to make animation authoritative.

Report files + line counts. State what I will see when I press Play.
```

---

## P-4C — Forge panel, HUD, and menus  ✅ DONE

> **COMPLETE — do not re-run.** Built by a 7-worker swarm; 47 findings closed.

**WHEN:** P-4B lands.
**EXIT ARTIFACT:** The full interface; forge preview matches payout exactly.

```
Execute BLOCK 4C — the interface. Read SRS FR-13 in full and FR-3.4.

1. src/Client/ForgePanel.luau  — THE PRIMARY SURFACE, build it first and best.
   - Reachable in AT MOST TWO TAPS from the arena (FR-13.8). It is the core
     mechanic, not a submenu.
   - Live preview using the SHARED ForgeMath — the same module the server uses.
     This is why ForgeMath is shared: the preview must match the payout EXACTLY.
     Do not reimplement any of its maths client-side.
   - Shows before committing: resulting per-face value, per-face landing
     probability, expected value per roll, and Void probability (FR-3.4).
     The maths is public by design; players optimise openly.
   - Shows the forge COST, which scales with magnitude of mass moved (FR-3.3).
   - Submits the COMPLETE proposed distribution. A rejected proposal must leave
     the UI showing the unchanged server state, not the failed proposal.

2. src/Client/HUD.luau
   - Top bar: Cash, Gems, Like Goal progress, Group Rewards, Robux shop (FR-13.2).
   - Bottom bar: ROLL and AUTO, playtime chest and daily spin entries (FR-13.5).
   - Current streak, its multiplier, and the loadout's Void probability
     CONTINUOUSLY VISIBLE (FR-5.5).
   - ROLL produces visible feedback within 100 ms, ahead of server confirmation.
     Optimistic feedback is VISUAL ONLY and never shows an unconfirmed currency
     change (NFR-7).

3. src/Client/MenuPanel.luau
   - Left sidebar: Forge, Add Die Slot, Shape, Auto-Roll Speed, Ascend (FR-13.3).
   - Right sidebar: Leaderboards, Statistics, Quests, Codes/Settings (FR-13.4).
   - A MENU ENTRY IS ADDED ONLY WHEN THE SYSTEM BEHIND IT EXISTS. Standing
     operator rule — the previous project shipped fifteen menu entries that were
     mostly dead buttons. Anything wired to an unbuilt Block 5 service shows an
     honest "coming soon" state, never a fake working button.

4. src/Client/AudioDirector.luau — SFX/music respecting Settings toggles.

STYLE (FR-13.1): 2D retro-pixel ScreenGui over the 3D arena, dark maroon and
charcoal panels, 1-pixel gold borders, monospace pixel type.

LAYOUT (FR-13.7, NFR-3): Scale-based sizing ONLY, never fixed Offset. Must render
without clipping or overlap from 320px through 4K.

NO FABRICATED SOCIAL PROOF ANYWHERE — no "someone just won" toasts, no invented
activity, no countdown that resets. Standing operator prohibition. The Like Goal
shows the REAL platform like count or it shows nothing.

Report files + line counts and a screen-by-screen description of what exists.
```

---

## P-4D — Block 4 Gate 2 + first runtime smoke  ✅ DONE

> **COMPLETE — do not re-run.** Row 6 confirmed by the operator: max mass on face 6 never lands. FR-2 observed end to end.

**WHEN:** P-4C lands.
**YOU DO:** Press Play and walk the 11-row smoke table yourself. **This is the first time the game is playable.**
**EXIT ARTIFACT:** `deliveries/evidence/<date>-smoke.txt`, all 11 rows observed.

```
Gate 2 for Block 4, plus the first real P-4 runtime smoke. Enumerate every step
inline.

1. Confirm Rojo sync is live. State how you confirmed it.
2. P-1 static analysis — zero errors, zero warnings.
3. P-2 automated suite — count must have moved.
4. P-3 prohibition greps — all five, verbatim output.
5. P-4 RUNTIME SMOKE — walk all 11 rows of TEST_PLAN §2 P-4 with me. Ask me to
   perform each action and report what I see. Do NOT mark a row passed that I
   did not confirm. In particular:
   - Row 5: the forge preview must have MATCHED the result exactly.
   - Row 6: after moving mass onto one face, that face must land DEMONSTRABLY
     LESS often over twenty rolls. If it lands more often, the sign is inverted
     somewhere and the whole forge is backwards.
   - Row 11: leave and rejoin — Cash, dice, and mass layouts restored EXACTLY.

Save the entire Output panel to deliveries/evidence/<date>-smoke.txt.

A row I did not perform is recorded as NOT PERFORMED, never as a pass.
Verdict: MECHANICALLY-CLEAN or REJECTED-TO-GATE-1 with numbered defects.
```

---

## P-4E — Block 4 Gate 3 + 4 audit  ✅ DONE

> **COMPLETE — do not re-run.** `docs/evidence/BLOCK4_CLOSEOUT.md`.

**WHEN:** P-4D passes.
**EXIT ARTIFACT:** Two verdicts with numeric counts; findings remediated.

```
Same structure as P-3C, scoped to Block 4. Write the brief to
deliveries/audit-briefs/<date>-block4-client-audit.md.

Additional Gate 4 focus areas specific to a client build — enumerate these as
explicit checklist rows in the brief:
- Does ANY client module touch a Remote directly, bypassing NetClient?
- Does ANY outbound message carry a price, balance, reward, score, level,
  duration, multiplier, or outcome? (NFR-5 — enumerate every send site.)
- Is any displayed currency value computed client-side rather than received
  from the server?
- Does any client-side rate limit sit where a server-side one should be?
- Can the tumble animation influence, delay, or suppress a credit?
- Does any UI element display a fabricated count, fake activity, or a resetting
  timer?

Then remediate per P-3D's verify-first procedure.
```

---

# 4. BLOCK 5 — MONETIZATION AND THE REMAINING SERVICES

## P-5.0 — OPERATOR TASK: create the Robux assets  ✅ DONE

> **COMPLETE — do not re-run.** All 14 ids supplied 2026-08-09 and wired.

**WHEN:** Before P-5A. **This is work for you in Studio, not a prompt for the AI.**
**EXIT ARTIFACT:** A list of real numeric asset IDs.

Create these in Roblox Studio / the Creator Dashboard, then paste the IDs back.
Agents never create monetized assets — standing operator rule.

**Gamepasses (FR-12.1):**

| Name | What it grants |
|---|---|
| +2 Dice Slots | Slot cap 5 → 7 |
| Ultra Auto-Roll | Lowers the auto-roll interval floor |
| Bad Roll Shield | Absorbs one streak break, then cooldown |
| VIP Vault | Vault 24h at 1.0 efficiency |

**Developer Products (FR-12.2):**

| Name | What it grants |
|---|---|
| Starter Bundle | One-time bundle — **genuinely once-only** |
| 2× Offline Payout | Doubles one vault claim |
| 2× Luck Boost | Timed luck multiplier |
| Time Skip (24h) | Credits 24h of vault accrual |

Paste back as `Name = 123456789` pairs. Until then everything stays
`DUMMY_ID_*` and fails closed (FR-12.6).

---

## P-5A — MonetizationService  ✅ DONE

> **COMPLETE — do not re-run.** Delivered as `MonetisationCatalog` + `PurchaseService` at `14fe582`. NOTE: this prompt's scope did NOT include applying the pass effects, which is why P-5A2 exists.

**WHEN:** Real asset IDs in hand.
**EXIT ARTIFACT:** `MonetizationService` + UT-9 passing.

```
Boot per CLAUDE.md (file-modifying session). Read SRS FR-12 and THREAT_MODEL.md
T-15, T-16, T-17 before writing.

Here are the real asset IDs:
<PASTE THE ID LIST>

Execute BLOCK 5A — src/Server/MonetizationService.luau.

THIS MODULE HANDLES REAL MONEY. Every rule below is non-negotiable.

- EXACTLY ONE ProcessReceipt assignment exists in the entire place (FR-12.3,
  T-17). Nothing at runtime warns you if a second assignment overwrites the
  first — the P-3 grep is the only detector. Verify it returns exactly 1 line.
- PurchaseGranted is returned ONLY after the grant DURABLY PERSISTS. Every other
  path — save failure, player offline, unknown product, exception — returns
  NotProcessedYet (FR-12.4, T-16). Returning PurchaseGranted on a failed save
  takes the player's Robux and gives them nothing.
- Idempotency via PlayerProfile.recordPurchase. The same PurchaseId grants
  EXACTLY ONCE, and still refuses after a server restart, because the ledger
  lives in the DataStore and not in memory (T-15).
- Note the T-13 amendment already in PlayerProfile: purchase-id eviction is
  TIME-AWARE, not count-only. Do not "simplify" it back to a count bound — that
  reintroduces a real-money double-grant.
- An unresolved or unknown product FAILS CLOSED and grants nothing.
- Gamepass entitlements are checked SERVER-SIDE against MarketplaceService and
  cached with a bounded TTL. Never trust a client claim of ownership.
- STARTER BUNDLE: the timer is GENUINELY ONCE-ONLY. Expired means permanently
  gone for that player, never re-offered under any name, no countdown reset.
  This is a standing operator prohibition on manufactured urgency, reaffirmed
  for this project. Implement expiry as a persisted boolean, not a timer that
  can be re-armed.
- FR-12.7: no purchase confers an economic capability unreachable through play,
  cosmetics excepted. If an ID above violates that, say so before wiring it.

Then write tests/Receipt.test.luau (UT-9) per TEST_PLAN §4 — using Fakes.luau,
never a live MarketplaceService.

Report the new assertion count delta and confirm the ProcessReceipt grep = 1.
```

---

## P-5A2 — Apply the pass effects  ⬅ RUN THIS NEXT

**WHEN:** Now. The monetisation backend landed at `14fe582`.
**WHY IT IS URGENT:** four gamepasses are sellable and have no effect.
**EXIT ARTIFACT:** a live test showing each pass changing behaviour, plus a grep
proving every entitlement function has at least one caller.

```
Block 5 continues. The monetisation backend is complete and committed at
14fe582: MonetisationCatalog holds all 14 real asset ids, PurchaseService owns
the place's single ProcessReceipt assignment, entitlements resolve at join into
a cache, and the suite is green at 3,370 assertions.

THE PROBLEM: PurchaseService exposes cashMultiplier, bonusDieSlots,
forgeCostMultiplier, hasStreakShield and hasAutoRoll -- all implemented, all
returning correct values -- and NOTHING CALLS ANY OF THEM. Verified: zero
callers outside PurchaseService itself. A player who buys 2x Cash gets 1x.

Wire each entitlement into the system that owes it:

  cashMultiplier      -> EconomyService, on every cash credit from a roll.
                         Must NOT apply to forge refunds or other credits, or a
                         player could launder the multiplier through the forge.
  bonusDieSlots       -> wherever the board's die count is resolved, added on
                         top of the profile's earned slots and CLAMPED to the
                         FR-1.1 ceiling of 7.
  forgeCostMultiplier -> ForgeService.computeForgeCost, applied to the final
                         cost. Forging stays ZERO-SUM (FR-3): this changes what
                         the re-forge COSTS, never how much mass moves.
  hasStreakShield     -> RollService, where a Void face breaks the streak.
  hasAutoRoll         -> gates the SetAutoRoll handler when it exists; for now,
                         make the client's AUTO button reflect real ownership
                         instead of reading (SOON).

CONSTRAINTS:
  * NFR-5 -- no multiplier, price or reward figure may cross the wire. The
    server applies the effect and StateSync reports the resulting balance.
  * FR-12.7 -- no purchase may confer an economic capability the game does not
    also make reachable through play. If wiring one would break that, say so
    and stop rather than shipping it.
  * A pass whose owner cannot be determined must behave as NOT OWNED. The
    ownership cache already fails closed; do not add a path that assumes
    ownership on lookup failure.

VERIFY, and do not report done without this:
  1. `grep` each of the five function names and show at least one caller
     outside PurchaseService.
  2. In Studio, inject ownership for a test player and demonstrate each effect
     changing a real number -- a roll paying double, a forge costing less, a
     Void face not breaking the streak. Numbers before and after.
  3. Suite green with its new assertion count stated.
```

---

## P-5A3 — The shop UI

**WHEN:** After P-5A2. Do not build a shop for passes that do nothing.
**EXIT ARTIFACT:** a screenshot of the shop rendering all sellable items, with
the three unavailable products absent.

```
Block 5 continues. All 14 items are wired server-side and completely
unreachable: SHOP is still a (SOON) button. Build the shop surface.

REQUIREMENTS:
  * Gate every entry on MonetisationCatalog.isSellable, NOT isResolved.
    isResolved says the asset exists; isSellable says this build can actually
    honour it. Three products are deliberately unsellable because the systems
    that grant them do not exist -- offering one would charge a player for
    nothing.
  * Do NOT display prices from the catalog. There are none, on purpose. Read
    the price from the platform (MarketplaceService product info) or show no
    price. A hardcoded price is a number the game asserts and the dashboard
    contradicts.
  * Owned passes must render as owned, from the entitlement cache.
  * Follow UITheme. No new colours, no new panel builders.
  * FR-13.7: no overlap, Scale-based sizing only, 320px through 4K.
  * FR-12.5: the Starter Bundle timer is GENUINELY once-only. If you render a
    countdown it must reflect real remaining time and, once expired, the offer
    is permanently gone. No resets, no re-offers, no manufactured urgency.

VERIFY: screenshot the shop open. Confirm the three unavailable products do not
appear. Confirm the suite is green.
```

---

## P-5B — Offline vault and leaderboards

**WHEN:** P-5A lands.
**EXIT ARTIFACT:** `OfflineService` + `LeaderboardService` + UT-10, UT-11.

```
Execute BLOCK 5B. Read SRS FR-8 and FR-11, and THREAT_MODEL T-20, T-23, T-24,
plus T-30 (which I added after an audit found the exploit described below).

1. src/Server/OfflineService.luau
   - earnings = min(elapsed, capacity) × averageIncomePerSecond × efficiency.
   - elapsed computed ENTIRELY server-side from os.time() at save vs load. No
     client value participates (FR-8.1).
   - Clamped to [0, capacity]. NEGATIVE elapsed credits EXACTLY ZERO and is
     logged (FR-8.4, T-23). Never a negative or wrapped payout.
   - averageIncomePerSecond comes from RollService.averageIncomePerSecond, which
     is ALREADY HARDENED against T-30: floored at MIN_RATE_WINDOW = 60 seconds
     and capped at MAX_RATE. Do not bypass it or recompute the rate locally —
     the unfloored version let a player join, roll once in 0.05s, leave, and
     mint an astronomical offline rate. That was a real shipped exploit.
   - Claiming CONSUMES the vault ATOMICALLY — the window closes and resets in the
     same transaction that credits it, so a second claim finds it empty
     (FR-8.6, T-24).
   - The Robux 2× claim is bound to its AccrualId and cannot be replayed against
     a later window.
   - Capacities per FR-8.3: base 4h @ 0.5, Cash-upgraded 12h @ 0.75, VIP Vault
     24h @ 1.0.

2. src/Server/LeaderboardService.luau
   - Three boards: Top Net Worth, Highest Single Roll, Max Prestiges (FR-11.1).
   - Published values are BOUNDED, LOG-SCALED, MONOTONIC INTEGERS derived from
     the true value — NEVER the raw number, which overflows signed 64-bit in an
     idle economy (FR-11.4, T-20). Assert the bound holds at raw = 1e300.
   - GetSortedAsync at most once per server per interval, cached and served to
     all players from that cache (FR-11.5).
   - Display names read from the Players service SERVER-SIDE, never from a
     client message (FR-11.6).

3. tests/Vault.test.luau (UT-11) and tests/Leaderboard.test.luau (UT-10).

Report the assertion delta.
```

---

## P-5B2 — Timed boosts

**WHEN:** With or after P-5B. Together they unblock the three dead products.
**EXIT ARTIFACT:** a boost that visibly expires, and the three products moving
from `unavailable` to sellable.

```
Block 5 continues. Three developer products are live on the dashboard and
CANNOT BE DELIVERED: 2x Luck Boost, 2x Offline Payout, Time Skip (24h). They are
marked `unavailable = true` in MonetisationCatalog so no shop offers them, but
they remain purchasable through Roblox's own store page -- a player who buys one
is charged, gets nothing, and the platform retries forever.

Build what they need:
  * A timed boost system: a boost has a kind, a multiplier and an expiry stored
    on the profile, survives a rejoin, and expires on server time (never client
    time -- a client clock is an input, not a fact).
  * Wire 2x Luck Boost and 2x Offline Payout to it, and Time Skip to the offline
    accrual from P-5B.
  * Then implement the Boost and TimeSkip branches in PurchaseService.applyGrant,
    which currently refuse with `not_implemented_boosts`, and REMOVE the
    `unavailable = true` marks.

DO NOT remove an `unavailable` mark before its grant path actually works. The
mark is the only thing standing between a player and being charged for nothing.

VERIFY: buy-path simulated end to end -- grant applies, profile persists, boost
expires on time, and a rejoin during the window still shows it active.
```

---

## P-5C — Progression and Ascension

**WHEN:** P-5B lands.
**EXIT ARTIFACT:** `ProgressionService` + `AscensionService` wired to real menus.

```
Execute BLOCK 5C. Read SRS FR-9 and FR-10.

1. src/Server/ProgressionService.luau
   - Three rotating daily quests, server-defined objectives, server-tracked
     progress (FR-10.1).
   - Daily login streak with EXACTLY ONE forgiveness token (FR-10.2).
   - Playtime chests on a SERVER-CLOCKED timer at 5/15/45 minutes of session
     time (FR-10.3). Client-clocked timers are free money.
   - Daily spin: one free spin per 24h from a server-held weighted table. THE
     WHEEL ANIMATION RESOLVES TO A PRE-DECIDED SERVER OUTCOME — same authority
     rule as the dice (FR-10.4).
   - Group Rewards verified server-side against Roblox group membership and
     RE-VERIFIED on each join (FR-10.5).
   - Promo codes matched against a server-held allowlist. Responses limited to
     valid / invalid / already-redeemed, and NEVER echo the submitted string
     (FR-10.6).
   - Like Goal: displays the REAL platform like count, triggers a timed 3× Cash
     event, SIMULATED PER SERVER INSTANCE in V1 because MessagingService is out
     of scope (FR-10.7, risk R-8). Players on different servers may see
     different event states — that is accepted, documented risk, not a bug.
     NO FABRICATED ACTIVITY ANYWHERE.

2. src/Server/AscensionService.luau
   - Grants Prestige Diamonds scaled to LIFETIME EARNINGS THIS RUN (FR-9.1).
   - Resets Cash, face layouts, mass budgets, Cash-purchased upgrades.
   - DIAMONDS AND THE DIAMOND TREE SURVIVE, always, never reset (FR-9.2).
   - Requires a minimum lifetime-earnings threshold to prevent degenerate
     rapid-ascend loops (FR-9.5).
   - The confirm screen states EXACTLY what is lost and EXACTLY what is gained
     before confirming (FR-9.4).
   - Streak Strength purchased pre-ascension still applies after.

3. Wire the Block 4 menu placeholders to these real services. Every "coming
   soon" state from P-4C should now be a working panel — list any that remain
   and why.

Report the assertion delta.
```

---

## P-5C2 — The twelve unhandled remotes

**WHEN:** After P-5C.
**EXIT ARTIFACT:** every declared remote either handled, or deleted from the
declaration with a reason.

```
Block 5 continues. Remotes.luau declares 16 RemoteFunctions. FOUR have handlers:
Roll, Forge, SetElement, SetShape. The other twelve are declared and bound to
nothing:

  BuyUpgrade, AddDieSlot, Ascend, BuyDiamondNode, SetAutoRoll, ClaimVault,
  ClaimQuest, ClaimChest, DailySpin, RedeemCode, ClaimGroupReward, GetLeaderboard

This is exactly the L-027 shape: a declared-but-unimplemented contract row reads
identically to a working one, and it took three swarm workers to notice the last
one. The client already tells the truth -- every unbacked control reads (SOON) --
but the declaration does not.

For each of the twelve: either implement the handler, or DELETE it from
Remotes.luau with a one-line note saying why it is out of scope for V1. A
declaration with no producer is a finding, not a placeholder.

Note SetAutoRoll specifically: the operator owns an Auto-Roll gamepass, so this
one is sold and must work.

VERIFY: a producer-direction sweep -- for every name in FunctionName, show the
line that registers a handler for it. No name may be unaccounted for.
```

---

## P-5D / P-5E — Block 5 Gate 2, then Gate 3+4

Run **P-3B** and **P-3C** verbatim, substituting "Block 5" for "Block 3" and
expecting suites **UT-9, UT-10, UT-11**. Add these Gate 4 rows to the brief:

- Can `PurchaseGranted` be reached on any path where the grant did not persist?
- Is there exactly one `ProcessReceipt` assignment? (grep count, stated numerically)
- Can any vault claim be replayed, double-claimed, or credited against a stale window?
- Can the offline rate be inflated by any join/roll/leave pattern?
- Does any leaderboard write publish a raw, unbounded value?
- Can a promo code response leak the allowlist by timing or echo?

---

# 5. BLOCK 6 — INTEGRATION, BALANCE, AND PRE-LAUNCH

## P-6A — Integration suites

**WHEN:** Block 5 signed off.
**EXIT ARTIFACT:** IT-1 … IT-5 written and passing; suite total 16.

```
Execute BLOCK 6A — the integration suites, per TEST_PLAN §5. All five, using
Fakes.luau.

- IT-1 Integration_RollLoop — full roll intent → sample → elements → streak →
  credit → RollResult. Assert Cash is credited BEFORE the event fires, and that
  a dropped RollResult leaves the credit INTACT (FR-2.6).
- IT-2 Integration_Forge — valid proposal applies; INVALID proposal leaves both
  budget and Cash BYTE-IDENTICAL to before.
- IT-3 Integration_SessionLock — A holds the lock, B fails closed and serves no
  default; A releases, B sees A's data; a stale lock is force-claimable; A's
  write after losing the lock is REFUSED.
- IT-4 Integration_Authority — THE ADVERSARIAL SUITE. Attempt to mutate Cash
  through every service other than EconomyService and assert the balance is
  unchanged in each case. Attempt every inbound remote with a spoofed economic
  parameter (price, amount, face, duration, multiplier) and assert each is
  rejected with NO state change. Assert no remote in API_DATA_CONTRACT §1
  ACCEPTS such a parameter at all.
- IT-5 Integration_Ascension — Diamonds and the tree survive; below-threshold
  ascension refused; pre-ascension Streak Strength still applies after.

TEST_PLAN P-2 requires the final suite count to be 16 (11 unit + 5 integration).
State the count you reach. If it is not 16, name every missing suite.

Write IT-4 as if you were attacking your own code, not documenting it.
```

---

## P-6B — Balance tuning pass

**WHEN:** P-6A clean.
**EXIT ARTIFACT:** A tuning report with numbers, not vibes.

```
Balance tuning pass. This is a NUMERICAL exercise — run simulations, do not
reason from intuition. Pre-code mathematical validation is the established
default on this project (ledger L-016, L-017), and my own first formula made
"never forge" the optimal play.

Write throwaway simulation scripts to the scratchpad, not the repo.

Verify, with numbers:
1. NO DOMINANT STRATEGY. Sweep Streak Strength b across its full purchasable
   range against all five shapes. FR-6.3 requires a CROSSOVER: low b favours few
   faces, high b favours many. A shape that wins at every b is a BALANCE DEFECT
   — report it as one.
2. THE FORGE IS WORTH USING. Expected value of an optimally forged die must
   meaningfully exceed a flat die, after forge cost. If forging never pays, the
   core mechanic is inert.
3. RE-FORGING IS NOT FREE. Confirm the FR-3.3 cost curve actually prevents
   constant re-optimisation. Free re-forging collapses the cross-die puzzle to a
   solved symmetric state (L-016).
4. ELEMENTS PRODUCE SPECIALISATION, NOT SYMMETRY. FR-4.5 measured a −0.949
   correlation: a die heavily invested in a conditional element should push its
   partners AWAY from that element. Re-measure it against the shipped code.
5. PROGRESSION CURVE. Time-to-first-ascension, and whether the Diamond tree
   costs make the second run feel meaningfully faster.
6. NO INERT CONDITIONAL. Re-confirm every element's payoff scales with combined
   invested mass. A flat conditional bonus is algebraically inert (FR-4.3).

Report every result HONESTLY, including negatives. Three of four simulations
returned negative results in the design phase and that is what made the design
work. Propose specific constant changes, with the before/after numbers.
```

---

## P-6C — Performance pass

**WHEN:** P-6B lands.
**YOU DO:** Run the MicroProfiler in Studio.
**EXIT ARTIFACT:** NFR-1 and NFR-2 measured — the coverage gap TEST_PLAN §6 declared.

```
Performance pass against NFR-1 and NFR-2. TEST_PLAN §6 explicitly declares these
as a KNOWN COVERAGE GAP — not unit-testable, deferred to a construction-phase
pass. This is that pass. They have never been measured.

Targets:
- NFR-1: 60 FPS desktop, 30 FPS mid-tier mobile, with SEVEN dice active. Client
  per-frame work under 4 ms. NO ALLOCATION inside per-frame loops.
- NFR-2: per-player per-roll server resolution under 0.5 ms. Cost must scale
  with DIE COUNT, never with physics complexity — the server runs no simulation,
  so if you find server cost tracking physics, something is architecturally wrong.

Guide me through:
1. MicroProfiler capture with 7 dice rolling continuously. Tell me exactly what
   to click and what to copy back.
2. Server-side timing instrumentation around the roll resolution path.
3. Allocation audit of DiceRenderer's per-frame path — instance pooling was
   required in P-4B; verify it actually holds under load.
4. A narrow-device layout check at 320px (NFR-3).

Save results to deliveries/evidence/<date>-performance.txt.
If a target is missed, say by how much and propose the specific fix. Do not
declare a target met that you did not measure.
```

---

## P-6D — Full pre-launch sweep

**WHEN:** P-6C lands.
**EXIT ARTIFACT:** Complete evidence set; every gate green simultaneously.

```
Full pre-launch verification sweep. Run the ENTIRE TEST_PLAN end to end —
P-1, P-2, P-3, P-4 — as though nothing before this had been verified. Enumerate
every step inline.

Plus these pre-launch-only checks, each with a stated PASS/FAIL:

1. NO DUMMY_ID_* REMAINS ANYWHERE in src/. grep and state the count. A dummy ID
   in production silently sells nothing.
2. Every gamepass and product ID resolves against the live MarketplaceService.
3. ONE live test purchase of one Developer Product, end to end. TEST_PLAN §6
   flags this as untestable without live IDs — it is testable now, so test it.
   Confirm the grant persisted and that re-processing the same receipt grants
   NOTHING.
4. Leave-and-rejoin persistence across a real server restart, not just Play Solo.
5. Two-client session-lock behaviour if you can arrange it; if not, say so
   rather than claiming coverage.
6. Every menu entry either works or is honestly absent. No dead buttons —
   standing operator rule.
7. No TODO/FIXME/TBD in src/. Stated count.
8. Confirm the repo contains NO credential: no webhook URL, no API key, no token.
   The Discord webhook in particular must never have entered the repository.
9. Doc-currency check (Gate 5): does every blueprint document still describe the
   code as built? List every divergence and amend the document, citing the
   triggering fact.

Produce a single go/no-go table. Any FAIL is a no-go — do not average them out.
```

---

## P-6E — Final cross-vendor security audit

**WHEN:** P-6D is all-green.
**EXIT ARTIFACT:** `SECURE` on the whole codebase.

```
Prepare the FINAL pre-launch security audit brief covering the ENTIRE codebase,
not a diff. Write it to deliveries/audit-briefs/<date>-prelaunch-full-audit.md.

Enumerate ALL thirty threat-model items T-1 … T-30 INLINE as checklist rows,
each with its mitigation location (file:line) and a verdict column. Do not
reference the threat model — reproduce it. A referenced checklist gets partially
executed (L-014).

Demand the numeric-count output format from P-3C. A "no findings" verdict beside
a body of mitigation notes is a misclassification (L-018) — that exact failure
once hid five real vulnerabilities on this project.

Highest-priority rows, called out explicitly at the top of the brief:
- Every real-money path (T-15, T-16, T-17)
- Every currency-minting path, including the offline rate (T-30)
- Every client-supplied numeric, checked finite BEFORE bounds (T-25)
- Session-lock and released-profile writes (T-10, T-26)
- Leaderboard overflow (T-20)
- The full remote inventory against NFR-5

Then remediate per P-3D's verify-first procedure. Do not launch on a FLAGGED
verdict.
```

---

# 6. BLOCK 7 — LAUNCH

## P-7A — Launch readiness and publish

**WHEN:** P-6E returns SECURE.
**YOU DO:** The actual publish. Irreversible — the assistant will confirm first.

```
Launch readiness. Read docs/blueprint/DEVOPS_RECORD.md.

1. Produce a final go/no-go table across every gate, with the evidence file for
   each row. Any missing evidence is a no-go.
2. Confirm the risk register: every R-n either mitigated or explicitly accepted
   by me in writing. List anything still open.
3. Confirm the ProfileStore vendor pin is unchanged at 45c9847 and the license
   attribution is correct — Apache-2.0, NOT MIT. I had that wrong in the docs
   once already.
4. Walk me through the publish steps for Roblox: place settings, experience
   description, thumbnails, genre, device support, the 30-day retention window
   on DataStore, and enabling Studio access to API services if it is not already.
5. STOP before publishing and ask me to confirm. Publishing is irreversible and
   outward-facing.

Then: what breaks first at 100 concurrent players, and what breaks first at
10,000? Name the specific module for each.
```

---

## P-7B — Post-launch monitoring

**WHEN:** Published.
**EXIT ARTIFACT:** A monitoring plan plus a Gate 6 ledger harvest.

```
Post-launch. Two things.

FIRST — monitoring. What do I watch, where, and what number means trouble?
- DataStore error and throttle rates
- ProcessReceipt failure rate (any sustained non-zero is money being lost)
- Session-lock conflict frequency
- Cash inflation: median and p99 net worth over time. Runaway p99 means an
  exploit, not a whale.
- Retention D1/D7 against the incumbent's known trajectory (2.55M visits, peak
  1,562 CCU, 4 CCU seven months later — that decay curve is the thing to beat)
- Server FPS and per-player memory

Give me a specific alerting threshold per item, not "monitor for anomalies".

SECOND — Gate 6 evolve. Harvest this build into .brain:
- Every ledger entry earned that is not yet written up.
- Whether the L-019/L-020 sync-canary rule should be promoted from a ledger
  entry into a skill file — it caught two false greens, which is a pattern.
- Whether the pre-code simulation gate should become a standing default rather
  than a per-project decision. It has now paid off twice.
- Any Antigravity behavioural observation worth adding to the model-split
  doctrine.
- Propose Operator Profile entries ONLY with pattern evidence attached (3+
  occurrences plus my explicit confirmation), per the ledger charter.

ALLOW_GOVERNANCE_EDIT is required for .brain writes — I will grant it explicitly
if I agree with your proposals. Do not edit .brain files before I do.
```

---

# 7. STANDING PROMPTS — run any time

## S-1 — Refresh the handoff document

```
Update HANDOFF.md to reflect the current state. It must remain accurate enough
that an assistant with ZERO context can resume the project from it alone.
Be honest about what is not built and what is not verified — the value of that
document is entirely in its accuracy, not its optimism.
```

## S-2 — Commit and push

```
Commit the current work. Message should name the block, the gate reached, the
suite count, and any finding IDs remediated. Push to origin/master.
Do not commit any credential. Confirm the diff contains no webhook URL.
```

## S-3 — Status check

```
Give me a status: what is built, what is verified, what is neither. Cite the
evidence file for every "verified" claim. Anything you cannot cite is unverified
— say so plainly rather than assuming it still holds.
```

## S-4 — Ledger harvest (mid-build)

```
Review this session for ledger-grade lessons. A lesson qualifies only if it is a
REPEATABLE mistake class with a mechanical defence, not a one-off typo. Propose
entries with their triggering facts. ALLOW_GOVERNANCE_EDIT=1 if I grant it.
```

---

# 8. CONTINGENCY PROMPTS

## C-1 — Suspected Rojo desync (the most likely failure)

**Symptom:** the suite passes at an **unchanged** assertion count, or your edit
appears to have no effect.

```
Suspected Rojo desync — the suite reported green at an unchanged assertion count.
This has happened TWICE on this project (ledger L-019: the server died silently;
L-020: the plugin dropped its connection on a Play start/stop cycle).

Do NOT trust the green. Diagnose in this order:
1. Is the rojo.exe process alive and serving on 34872?
2. Is the plugin showing Connected in Studio right now?
3. Does a script_read of one file I just changed show the NEW content in Studio?

If Studio has stale content, push the changes via MCP directly rather than
waiting on sync, then re-run and confirm the assertion count MOVES.

Note: multi_edit CANNOT address a script whose name contains a dot —
"Tests.Payout.test" parses as Tests → Payout → test. Use FindFirstChild plus a
Source assignment for those.
```

## C-2 — A test fails

```
A test is failing:
<PASTE THE VERBATIM OUTPUT>

Before changing ANYTHING, determine which side is wrong: the TEST or the CODE.
State your conclusion and the evidence for it FIRST.

Ledger L-017 exists because a failing "drift" test was my bad test, not bad
code — and loosening EPSILON to make it pass would have punched a hole in a real
invariant. Do not adjust a tolerance, threshold, or epsilon to make a test pass
unless you have proven the threshold itself was wrong.

Also check for tautologies in the test — L-018 caught
`check(res.streak == 0 or res.streak == 1)`, which could not fail.
```

## C-3 — MCP / Studio connection lost

```
The Roblox Studio MCP connection is unavailable. Fall back to the split-vendor
verification path: you AUTHOR tests, I EXECUTE them in Studio and return
verbatim output.

Under that mode you must NEVER cite execute_luau or start_stop_play as evidence,
and every test procedure must state its file, its literal steps, and its named
exit artifact — instructions that require inferring intent do not survive the
handoff (ledger, 2026-07-30).

Also: conserve MCP calls generally. Use the server only when disk-based tools
cannot answer the question.
```

## C-4 — An audit returns "no findings"

```
The auditor returned no findings. Treat that as SUSPECT until verified.

On this project a "no findings" verdict once sat beside FIVE real
vulnerabilities (ledger L-018). Check:
1. Did it return a NUMERIC count, or just prose? Prose without a count is not a
   verdict.
2. Does its body contain mitigation notes, caveats, or "consider" statements? A
   mitigation note IS a finding.
3. Did it enumerate every checklist row, or claim coverage it did not
   demonstrate? A previous audit reported 9 lines evaluated having evaluated 4
   (L-014).

If any of those hold, reject the audit and re-run it with the enumeration and
count requirements made explicit.
```

## C-5 — Scope pressure

```
Before you build that, check it against the V1 scope:
- MessagingService is OUT (risk R-8, operator scoping decision). Cross-server
  anything is out.
- No fabricated social proof, no manufactured urgency, no resetting timers.
- No menu entry without a working system behind it.
- Asset IDs are DUMMY_ID_* until I supply real ones.

If what I just asked for violates one of these, tell me before building it.
```

---

# 9. WHAT THIS ROADMAP DELIBERATELY DOES NOT COVER

Stated rather than hidden, so nobody discovers these by surprise:

- **Cross-server features of any kind.** MessagingService is out of V1 by
  operator decision (risk R-8). The Like Goal event is per-server-instance and
  two players on different servers may see different states.
- **Genuine multi-server contention testing.** IT-3 simulates session locking;
  it does not reproduce real contention.
- **Mobile device testing on real hardware.** P-6C measures against a mid-tier
  target in Studio, which is an approximation.
- **Localisation, accessibility, and analytics/telemetry.** None are in the SRS.
  If you want them, they are a new blueprint cycle, not a block.
- **Anything that makes the client authoritative.** Not deferred — prohibited.
  The previous project in this repository failed on exactly that, and the
  server-decides/client-animates split is the load-bearing decision of this one.
