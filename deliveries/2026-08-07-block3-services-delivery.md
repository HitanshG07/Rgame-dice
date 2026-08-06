# GATE 5 DELIVERY RECORD — Block 3, `dice-forge-block3-services`

**Date:** 2026-08-07
**Head:** `778b493`
**Tier:** PRODUCTION
**Status:** **NOT YET DELIVERED — two items open.** See §7.

*(Matrix F durable delivery record. Written before sign-off, not after, so the
open items are visible rather than discovered later.)*

---

## 1. WHAT BLOCK 3 IS

The server-side service layer between the roll loop (Block 2) and the client
(Block 4). Eight new modules, four modified, five new suites.

| Built | Purpose |
|---|---|
| `DiceCatalog` | Per-shape face counts, mass floors, budget caps and ceilings |
| `UpgradeCatalog` | Cash and Diamond upgrade definitions and cost curves |
| `Format` | Suffix-ladder number formatting, precision-safe to 1e300 |
| `RateLimiter` | Per-player per-remote token buckets, extracted from `RemoteGateway` |
| `ForgeService` | Mass redistribution, element assignment, shape change |
| `ServerBootstrap` | Composition root, player lifecycle, `BindToClose` |
| `tests/Fakes.luau` | Injectable fakes so no unit test touches a live service |
| UT-5, UT-6, UT-7, UT-8, **UT-12** | Elements, rate limiting, schema, lifecycle, forge |

Modified: `PlayerProfile` (deep copy, live `_reconcile`, schema v2),
`RollService` (Freeze re-roll, emitter seam, `MASS_FLOOR` removed),
`EconomyService` (explicit balance branch helpers), `RemoteGateway`
(`RateLimiter` delegation, `ARITY` enforcement).

## 2. ARTIFACT CHAIN

| Gate | Verdict | Artifact |
|---|---|---|
| G1 Construct | DIFF-COMPLETE | commits `c9fc91d` … `778b493` |
| G2 Validate | **MECHANICALLY-CLEAN** | `evidence/2026-08-06-block3-static-analysis.txt` (P-1, 7 runs), `-remediated-unit-suite.txt` (P-2), `-remediated-prohibitions.txt` (P-3) |
| G3 Audit | **AUDIT-APPROVED / 0** on `30268f3` | `audit-briefs/…-round4.md` + returned report |
| G4 Secure | **SECURE / 0** on `30268f3` | same |
| G5 Deliver | **PENDING** | this document |
| G6 Evolve | pending | L-021 amended; L-022, L-023, L-024 added |

**P-4 runtime smoke: NOT PERFORMED.** It needs the client's view layer, which is
Block 4B/4C. Recorded as not performed, never as passing.

## 3. THE HONEST HISTORY

Block 3 was rejected **five times** before it held.

| # | Gate | Cause |
|---|---|---|
| 1 | G3 (my cross-verification) | `ElementCatalog.getElement` — a call to a function that has never existed. Every element assignment would have crashed. P-1 never run; UT-8 missing its three T-10/T-26 assertions; `_reconcile` dead code; `table.clone` sharing the template die across all profiles. |
| 2 | G2 (P-1, first ever run) | 149 warnings. Four type classes, plus `MonetizationManager` — an unmanaged script in the place file assigning a second `ProcessReceipt` with an in-memory ledger. |
| 3 | G3+G4 round 1 | **F-AD-1** shape toggle manufactured budget · **F-AD-2** flat forge cost inert late-game · **F-AD-3** shallow `_reconcile` |
| 4 | G3 round 2 | **F-AD-4** round-half-up made face shares sum above the budget |
| 5 | G3 round 3 | **F-AD-5** unbounded `PurchasedBudget` · **F-AD-6** `performSetElement` ungated · **F-AD-7** invariant threw on malformed input |

**The rewind circuit breaker tripped at rejection 3, and I breached it** by
building a fourth remediation without noticing — because the scoreboard line
that arms it had never been written. Disclosed in
`deliveries/2026-08-07-block3-breaker-report.md`; reset by explicit operator
authorisation for a structural remedy rather than a fifth patch.

**The diagnosis that ended it.** `performSetShape` was wrong three times in
three directions — confiscating budget, manufacturing it, inflating it by
rounding — because the rules a die must satisfy lived as prose across FR-3.6,
FR-6.1 and a comment. Every fix re-derived them and broke a clause nobody had
written down. The remedy was to write the contract **once, executably**:
`assertDieInvariant`, seven clauses, checked on every candidate before
persistence and on every stored die at join. `RemoteGateway.ARITY` is the same
move applied to call shape.

## 4. FINDINGS, TAGGED

| ID | Tag | Status |
|---|---|---|
| getElement crash | — | Fixed `c9fc91d` |
| F-G3-1/2/3, F-G4-1 | T-30 | Fixed in Blocks 1–2 remediation |
| 149 static warnings | NFR-8 | Fixed `17cf3e2`, `44b2cf2` |
| `MonetizationManager` | T-15, T-16, T-17 | Deleted `df6fa34`, source archived |
| F-AD-1 | FR-3.6, FR-6.1 | Fixed `d39a4c3` — `PurchasedBudget` split, schema v2 |
| F-AD-2 | FR-3.3, L-016 | Fixed `d39a4c3` — cost scales superlinearly in budget |
| F-AD-3 | T-12 | Fixed `d39a4c3` — recursive `_reconcile` |
| F-AD-4 | FR-6.1 | Fixed `5c8f53e` — `ForgeMath.snapDown` |
| F-4A-1 | API §1.1 | Fixed `80602c0` — central `ARITY` table |
| F-AD-5 | FR-3.6 | Fixed `30268f3` — bounded entitlement; exposed the `cashBudgetCap`/`diamondCeiling` divergence |
| F-AD-6 | — | Fixed `30268f3` — `performSetElement` gated |
| F-AD-7 | — | Fixed `30268f3` — invariant returns instead of throwing |
| **F-SELF-1** | T-12 | Fixed `778b493` — **awaiting delta audit** |

## 5. WHAT WAS VERIFIED

- **P-1:** 0 errors, 0 first-party warnings, 8 accepted vendor warnings (pinned
  ProfileStore, bounded and recorded in `DEVOPS_RECORD`). **Re-read pending on
  `778b493`.**
- **P-2:** 9 suites, 0 failed, **3,307 assertions** (from 2,779 at block start).
- **P-3:** all prohibition greps match, including the DataModel sweep added
  after `MonetizationManager`.
- **Live wire:** client → server → client proven end to end. `Roll()` succeeds,
  `Roll(999)` is refused, an inflated forge proposal returns `sum_mismatch`, and
  25 rapid rolls produce 11 server-side refusals.
- **Live persistence:** a real profile loads, session-locks and saves.

## 6. DOC CURRENCY (consumer-gate law)

| Document | Result |
|---|---|
| `TEST_PLAN.md` | Amended — UT-12 registered with its triggering fact; P-1 declared non-skippable; P-2 requires the assertion count to move; P-3 sweeps the live DataModel |
| `SRS.md` | Amended — NFR-8 scoped to first-party code with a bounded vendor exclusion |
| `DEVOPS_RECORD.md` | Amended — accepted vendor warnings recorded with bounds and a re-evaluation trigger |
| `API_DATA_CONTRACT.md` | **Amended this document's date** — schema v2, `PurchasedBudget`, and the executable die contract. It still described `SchemaVersion = 1` with no `PurchasedBudget`; caught by this Gate 5 check, not by any audit |
| `THREAT_MODEL.md` | Current — T-30 added in the Blocks 1–2 cycle |
| `HLD.md` | Current |

## 7. OPEN ITEMS — why this is not signed off

1. **P-1 re-read on `778b493`.** Expected 0 errors / 8 vendor / 0 first-party.
   Not claimed until read.
2. **Round-5 delta audit** of `validateStoredDice` and `repairDie`
   (`audit-briefs/…-round5-delta.md`). This code landed **after** the round-4
   approval, so HEAD is not the audited commit. It is additive and narrows the
   attack surface, but it touches the load path and "one more thing after
   approval" is how unaudited code accumulates.

## 8. RESIDUAL RISK, STATED

- **Nothing is playable.** The client has a spine and no view layer. This is now
  the largest risk on the project.
- **P-4 has never run**, so no end-to-end player flow has been observed.
- **NFR-1/NFR-2 performance targets are unmeasured** (roadmap P-6C).
- **FR-6.3's shape crossover is unverified.** All five shapes carry an identical
  mass floor and 10 mass per face; the numerical sweep is roadmap P-6B. **If it
  fails, `DiceCatalog` constants change and UT-12's sweep changes with them.**
- **Forge cost numbers are provisional.** The structure closes F-AD-2; the values
  are P-6B's to settle.
- **Repair alters saved data.** `validateStoredDice` rewrites an illegal die
  without telling the player. Logged server-side; deliberately not surfaced.
  R-7 in the delta brief asks whether that is the right call.
- **The audit loop found a defect in every round until the fourth.** Round 4 was
  clean and I then found F-SELF-1 by widening one question. That is evidence
  convergence is real, and also that a clean audit is not proof of absence.
