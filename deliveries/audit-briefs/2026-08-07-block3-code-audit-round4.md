# CROSS-VENDOR AUDIT BRIEF — Dice Forge, Block 3, ROUND 4

**Date:** 2026-08-07
**Commit under audit:** `30268f3` — confirm with `git rev-parse HEAD` before you start.
**Mandate:** **READ-ONLY.** Evaluate, cite, report. Never modify a source file.

---

## 0. THIS IS A NEW VERDICT ON NEW CODE — read this first

**Do not restate round 3.** Round 3's verdict was `REJECTED-TO-GATE-1 / 3` and
`SECURE / 0`, against commit `c4d34fb`. **All three findings have since been
fixed.** Confirming that they were fixed is NOT this round's job and is not a
verdict. This round issues a **fresh Gate 3 and Gate 4 verdict on `30268f3`.**

If you find nothing, the correct output is `AUDIT-APPROVED / FINDINGS: 0` — not
a summary of the previous round.

### What changed since you last looked

| Round-3 finding | Fix now in the code |
|---|---|
| **F-AD-5** invariant had no upper bound on `PurchasedBudget` | Bounded by `DiceCatalog.maxDiamondCeiling()` — the max across ALL shapes, because `PurchasedBudget` is shape-independent |
| **F-AD-6** `performSetElement` bypassed the gate | Now builds a candidate and gates it, and refuses a write onto an already-invalid die |
| **F-AD-7** invariant threw on malformed input | Type-guards the argument, `Faces`, and every slot up to `faceCount` (`#` on a sparse array is undefined in Lua) |

**PLUS one change round 3 did not ask for, which needs your scrutiny most.**
Chasing F-AD-5 revealed that `diamondCeiling` was declared in `DiceCatalog` for
all five shapes and **read nowhere**, while both the invariant and
`performSetShape` clamped to `cashBudgetCap`. SRS FR-3.6 says budget is
*"purchased with Cash up to a per-shape cap, and beyond that with Prestige
Diamonds"* — so `cashBudgetCap` is where one purchase path stops, not where the
die stops. Clamping there made the Diamond budget tier unreachable and would
have silently confiscated anything bought with Diamonds.

**Both now clamp to `diamondCeiling`. That is a change to the economic ceiling
of every die in the game, made by me, unprompted by any finding.** Audit it as
new code, not as an accepted fix:

- Is `diamondCeiling` the right bound, or does FR-3.6 imply something else?
- Can a die now reach a budget no purchase path could legitimately produce?
- `maxDiamondCeiling()` is currently 5,000 (D20). A D4's own ceiling is 1,000.
  Is bounding `PurchasedBudget` globally at 5,000 while capping usable budget
  per-shape coherent, or does it create a state that is legal but unreachable?
- Does anything else in the codebase still assume `cashBudgetCap` is the limit?

### The question from round 3 still stands

**IS THE INVARIANT COMPLETE?** It now has seven clauses. If you can construct a
die that passes `assertDieInvariant` and is nonetheless wrong — economically,
physically, or against any SRS requirement — that remains the highest-value
finding available, and round 3 proved it is not a rhetorical question.

---

## 1. CITATION PROTOCOL — one rule added since round 2

1. Every verdict row cites `file:line` and **quotes the line verbatim**.
2. A wrong **quote** rejects the entire audit. A correct quote with a line
   number off by a few is logged, not disqualifying. *(This is why rounds 1 and
   2 were accepted despite small numeric drift.)*
3. **NEW — cite IMPLEMENTATION, not a comment and not this brief.** Round 2
   marked `D-8` PASS while citing this brief's own prose, and cited comments
   rather than code for `E-1`, `E-2`, `E-4`, `E-5`, `E-8`, `T-11` and `T-12`.
   A comment asserting that something is done is **the claim under audit**, not
   evidence for it; quoting the brief back is circular. A row whose only
   citation is a comment or a brief line counts as `UNVERIFIED`.
4. `UNVERIFIED` with a one-line reason is an acceptable, honest answer. Round 1
   marked `D-8` UNVERIFIED and that was the right call. A fabricated PASS is not.

## 2. FINDINGS-COUNT PROTOCOL

A mitigation note, hardening suggestion, "consider…" or "should also…" **IS A
FINDING** — numbered, tagged, counted. Required block, integers matching the list:

```text
GATE 3 VERDICT: AUDIT-APPROVED | REJECTED-TO-GATE-1
FINDINGS: <integer>
GATE 4 VERDICT: SECURE | FLAGGED
FINDINGS: <integer>
```

Tag each with `T-nn`, `FR-n.n` / `NFR-n`, or `D-n` / `E-n`.

---

## 3. SCOPE

Repository `HitanshG07/Rgame-dice`, local `C:\RGame`. **PRIVATE**, which permits
`THREAT_MODEL.md`, `SRS.md`, `HLD.md` and `API_DATA_CONTRACT.md` to be disclosed
in full. Read them as source of truth. **No credentials in this brief**; any
secret found in code is a critical `E-3` finding.

**Primary scope — Block 3:** all of `src/Server/` and `src/Shared/`, plus the
nine suites in `tests/`.

**Secondary scope — `src/Client/` (Block 4A).** `ClientBootstrap` and `NetClient`
are live in the place and were built after round 2. They are *formally* a
different change, but auditing them here is cheaper than a separate round and
they are the only code that crosses the wire. Report findings against them
normally; they will be tagged to Block 4.

**Out of scope:** `src/Server/Vendor/ProfileStore.luau` — pinned `45c9847`,
Apache-2.0, unmodified, 8 accepted static-analysis warnings recorded in
`DEVOPS_RECORD`. Do not audit its internals; **do** audit our use of it.

**Gate 2 state:** P-1 0 errors / 0 first-party warnings / 8 accepted vendor ·
P-2 9 suites / 0 failed / **3,291 assertions** · P-3 all greps match ·
P-4 not performed (needs the client's view layer, Block 4B/4C).

---

## 4. MATRIX D — RESILIENCE (Gate 3)

| ID | Line item | Verdict | `file:line` + verbatim quote |
|---|---|---|---|
| D-1 | Every dereference on a possibly-absent value is guarded or provably safe. | | |
| D-2 | Boundary inputs — zero, negative, empty collection, empty string, maximum size, single-element — all produce defined behaviour. | | |
| D-3 | No unsynchronised read-modify-write on shared state; no ordering assumption between independent async operations. | | |
| D-4 | Every deferred operation has a failure consumer; no fire-and-forget where failure matters. | | |
| D-5 | Every acquisition has a guaranteed release on success **and** failure paths. | | |
| D-6 | Retried or duplicated invocations of state-changing operations do not corrupt state. | | |
| D-7 | Every pre-existing behaviour sharing a code path with the change was re-verified, with evidence. | | |
| D-8 | Blind re-derivation performed before the diff was opened. | | |
| D-9 | Every parameter crossing into an external system validated against queried capabilities at runtime. | | |

## 5. MATRIX E — SECURITY (Gate 4)

| ID | Line item | Verdict | `file:line` + verbatim quote |
|---|---|---|---|
| E-1 | All inbound data crossing a trust boundary validated, encoded, or allowlisted before use. | | |
| E-2 | No data concatenated into any interpreter. | | |
| E-3 | No secret in source, version-controlled config, logs, error output, or fixtures. | | |
| E-4 | Every new capability justified by an acceptance criterion. | | |
| E-5 | Every third-party dependency has a review note and a pinned version. | | |
| E-6 | Every dependency's licence identified and compatible; copyleft FLAGGED. | | |
| E-7 | No PII, credentials or tokens reach logs in readable form. | | |
| E-8 | Error paths leak no internals to untrusted callers. | | |
| E-9 | Auth / authorization / session paths re-verified end to end. | | |

## 6. THREAT MODEL

| Threat | Claimed mitigation | Verdict | `file:line` + quote |
|---|---|---|---|
| T-3 | Per-player per-remote token buckets bound the roll rate | | |
| T-5 | Element ids resolved against a static allowlist | | |
| T-7 | Generic notice codes outward; detail stays server-side | | |
| T-8 | `InvokeClient` appears nowhere | | |
| T-10 | Failed load / foreign lock fails closed; no default profile served | | |
| T-11 | No `SetAsync` on profile data | | |
| T-12 | Versioned migration chain; every field defaulted | | |
| T-13 | Receipt retention bounded and time-aware; payload ceiling enforced | | |
| T-25 | Finiteness checked before summation | | |
| T-26 | `IsActive()` synchronous with the mutation | | |
| T-30 | Offline rate floored at a 60s window and capped | | |

## 7. ADVERSARIAL SWEEP

X-1…X-22 carry over and must be re-run. X-23…X-32 target this round's code.

| # | Vector | Verdict | Evidence |
|---|---|---|---|
| X-1 | `NaN` / `±inf` mass in a forge proposal | | |
| X-2 | Proposal summing correctly but putting a face below the shape floor | | |
| X-3 | Proposal of the wrong length, or a non-table payload | | |
| X-4 | Element not in the catalog; element not unlocked | | |
| X-5 | Shape not unlocked; shape already equipped (must not charge) | | |
| X-6 | Cash deducted but the mutation does not apply | | |
| X-7 | Mutation applies without the cost being deducted | | |
| X-8 | Remote spam past the burst cap; cross-player interference | | |
| X-9 | Mutation against a **released** profile | | |
| X-10 | Join → single roll → leave, to inflate the offline rate | | |
| X-11 | Currency written by any module other than `EconomyService` | | |
| X-12 | Any inbound remote accepting a price, balance, reward, level, duration, multiplier or outcome | | |
| X-13 | Any shape-change sequence that RAISES `PurchasedBudget` | | |
| X-14 | Any sequence where `MassBudget` ends above `PurchasedBudget` | | |
| X-15 | Any sequence raising the usable budget above the shape's `cashBudgetCap` | | |
| X-16 | Forging at a capped budget, then switching to a wider shape | | |
| X-17 | `PurchasedBudget` absent, zero, negative, `NaN` or `inf` | | |
| X-18 | The v1 → v2 migration: lossless, idempotent, multi-die | | |
| X-19 | A v2 profile loaded by an older server — quarantine, not overwrite | | |
| X-20 | The recursive `_reconcile`: corruption, unbounded recursion, array descent | | |
| X-21 | Forge cost scaling: zero, negative, `NaN`, overflow; ever cheaper at a larger budget? | | |
| X-22 | Refund correctness — can the recomputed cost differ from what was charged? | | |
| **X-23** | **A die that PASSES `assertDieInvariant` and is still wrong.** Seven clauses now. Round 3 answered this affirmatively; try again. | | |
| **X-33** | **The `diamondCeiling` switch.** Can a die reach a budget no purchase path could produce? Is a global 5,000 bound on `PurchasedBudget` with per-shape usable caps coherent? | | |
| **X-34** | **Anything still assuming `cashBudgetCap` is the limit.** Grep it; every remaining use must be deliberate. | | |
| **X-24** | **A mutating path that reaches `PlayerProfile.mutate` WITHOUT passing the invariant gate.** Grep every write to `d.Dice`. | | |
| **X-25** | **`assertDieInvariant` itself.** Can it error rather than return `false`? Wrong-typed input, missing `Faces`, a `Faces` table with holes, a non-table face? | | |
| **X-26** | **Epsilon abuse.** Three clauses compare with `ForgeMath.EPSILON` (1e-3). Can repeated operations each drift within epsilon and accumulate into real budget? | | |
| **X-27** | **The arity gate.** Any remote reachable with the wrong argument count? Does `select("#", ...)` behave as assumed for trailing nils from a real client? | | |
| **X-28** | **A registered remote missing from `ARITY`.** `bind()` errors at startup — verify that is reachable and that no remote slips through. | | |
| **X-29** | **`NetClient`.** Any path sending a price, balance, level, duration, multiplier or outcome? Any way to reach a remote bypassing it? | | |
| **X-30** | **`ClientBootstrap` failure paths.** Can it proceed after a fatal? Can a module failing to load be mistaken for one not yet built? | | |
| **X-31** | **The three Studio-only seams**, re-verified: still `IsStudio()`-guarded, still unreachable from a client. | | |
| **X-32** | **Test integrity.** Any assertion that cannot fail, or that passes vacuously because a prior call was refused? Two such have already been found. | | |

---

## 8. LEADS

1. **Invariant completeness (X-23).** The five clauses are: shape identity and
   face count; `PurchasedBudget` finite and positive; `MassBudget` within
   `[minViable, min(PurchasedBudget, cashBudgetCap)]`; every face finite, above
   floor, known element; faces sum to budget. **What is missing?** Candidates
   worth testing rather than assuming: a die with every face at the floor and no
   Void; duplicate conditional elements; a budget legal for the shape but
   unreachable by any purchase path; `PurchasedBudget` above every shape's cap.

2. **Ordering.** The gate runs before `canAfford` and `spend`. Correct for
   atomicity — but is there any state read *before* the gate and written *after*
   it that could change in between? There is no yield, so this should be
   provable rather than assumed.

3. **Epsilon (X-26).** `snapDown` fixed one direction of drift. Clauses using
   `EPSILON` tolerate 1e-3. Over many operations, does anything ratchet?

4. **`performSetElement` has no invariant gate.** It changes only `Element`, so
   no mass clause can move — but the element clause *can*. Is skipping the gate
   there correct, or an omission?

5. **`NetClient` deliberately has no generic `invoke()`.** Is that boundary
   actually closed, or can a client module reach `Remotes.getFunction` directly?

6. **Regression risk from the arity gate.** It rejects before type validation.
   Confirm no legitimate call shape in `NetClient` or the tests is now refused.

## 9. KNOWN GAPS — do not report these as discoveries

- **P-4 runtime smoke has not run.** The client has a spine but no view layer;
  Blocks 4B/4C build it.
- **NFR-1 / NFR-2 performance targets unmeasured.** Roadmap P-6C.
- **FR-6.3's shape crossover unverified.** All five shapes carry an identical
  mass floor of 1 and 10 mass per face. Documented in `DiceCatalog`; the sweep is
  roadmap P-6B. Balance opinions welcome but are not Gate 3/4 findings.
- **Forge cost NUMBERS are provisional** (`BASE = 5.0`, `REFERENCE_BUDGET = 60`,
  `SCALE_EXPONENT = 2.0`). The structure closes F-AD-2; the values are P-6B's.
  "The numbers are untuned" is not a finding.
- **`MonetizationService` does not exist.** Zero `ProcessReceipt` assignments is
  correct until Block 5.
- **Vendored ProfileStore's 8 warnings are accepted**, bounded, recorded.
- **`Format` and `UpgradeCatalog` have no consumer yet.**

## 10. WHAT A GOOD REPORT LOOKS LIKE

Every row verdicted, cited, quoted from **implementation**. Findings numbered,
tagged, counted. Unverified rows marked `UNVERIFIED` with a reason. Verdict block
in exactly the §2 format.

Across three rounds this codebase has yielded a crash, a progression exploit, an
inert cost curve, a shallow reconcile, a rounding inflation, an unbounded budget
field and an ungated write path. **If this round
finds nothing, say so plainly and say which rows you verified by opening the
file — a clean verdict that has earned itself is exactly what Block 3 needs to
close.**
