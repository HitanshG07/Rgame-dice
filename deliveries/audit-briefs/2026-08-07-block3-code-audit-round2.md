# CROSS-VENDOR AUDIT BRIEF — Dice Forge, Block 3, ROUND 2

**Date:** 2026-08-07
**Commit under audit:** `d39a4c3` (confirm with `git rev-parse HEAD` in `C:\RGame`)
**Mandate:** **READ-ONLY.** Evaluate, cite, report. Never modify a source file.

---

## 0. WHY THERE IS A ROUND 2

Round 1 (`2026-08-07-block3-code-audit.md`) returned:

```
GATE 3 VERDICT: REJECTED-TO-GATE-1    FINDINGS: 2
GATE 4 VERDICT: FLAGGED               FINDINGS: 1
```

**That audit was good work and all three findings were confirmed against the
code.** Its citations were verified: 33 of 35 verbatim-exact, the two misses off
by 1 and 3 lines *within the same function* with correct quoted text — drift, not
fabrication. It is accepted.

A Gate 3/4 rejection rewinds to Gate 1, and Gates 2–4 then **re-run in full**
(Global Pipeline Law 2). This is not a spot-check of three patches. It is a
complete second audit of a codebase that has changed materially since round 1.

### What changed, and why you should be suspicious of it

| Finding | Fix |
|---|---|
| **F-AD-1** mass-budget inflation via shape toggle | `Die.PurchasedBudget` split from `Die.MassBudget`; schema bumped **v1 → v2** with a migration |
| **F-AD-2** flat forge cost trivial late-game | cost now scales superlinearly in the die's budget |
| **F-AD-3** shallow `_reconcile` | made recursive, string-keys-only |

**The F-AD-1 fix introduced a NEW ECONOMIC FIELD.** `PurchasedBudget` is now a
persisted, server-held quantity that determines how much mass a die may hold. It
has the same character as a currency and it did not exist when you last looked.
It has never been audited. **Treat it as the primary attack surface in this
round.**

Two further self-reported facts, so your findings count reflects new information:

1. **The recursive `_reconcile` was initially wrong** and descended into arrays,
   merging the template's die into the player's die — a 120-budget die was
   silently overwritten with the template's 60. Caught by UT-7 before commit and
   fixed with a `type(k) == "string"` guard. **Verify that guard is correct and
   sufficient**; it is doing real work.
2. **F-AD-1 was a regression introduced during Block 3 itself**, while fixing the
   opposite defect (shape changes confiscating purchased progression). The same
   code path has now been wrong in both directions. It deserves the most
   scepticism in this brief.

---

## 1. THE CITATION PROTOCOL — unchanged, and it worked

1. Every verdict row cites `file:line` for a line you actually opened.
2. **Quote the line verbatim.** This is what distinguished honest drift from
   fabrication last round; it is the reason your round-1 audit was accepted.
3. Citations will be resolved against the files on receipt.
4. **A wrong QUOTE rejects the entire audit** — that is fabrication.
   A correct quote with a line number off by a few is logged, not disqualifying.
5. `UNVERIFIED` with a one-line reason is an acceptable, honest answer.
   A fabricated PASS is not.

## 2. THE FINDINGS-COUNT PROTOCOL

A mitigation note, hardening suggestion, "consider…", or "should also…" **IS A
FINDING** — numbered, tagged, counted. Required block:

```text
GATE 3 VERDICT: AUDIT-APPROVED | REJECTED-TO-GATE-1
FINDINGS: <integer>
GATE 4 VERDICT: SECURE | FLAGGED
FINDINGS: <integer>
```

Tag each finding with `T-nn`, `FR-n.n` / `NFR-n`, or `D-n` / `E-n`.

---

## 3. SCOPE

Repository `HitanshG07/Rgame-dice`, local `C:\RGame`. **PRIVATE**, which is what
permits `docs/blueprint/THREAT_MODEL.md`, `SRS.md`, `HLD.md` and
`API_DATA_CONTRACT.md` to be disclosed in full. Read them as source of truth.

**This brief contains no credentials.** Any secret pattern found in code is a
critical finding tagged `E-3`.

**Files in scope:** all of `src/Server/`, `src/Shared/`, and `tests/`.
**Out of scope:** `src/Server/Vendor/ProfileStore.luau` — pinned `45c9847`,
Apache-2.0, unmodified, 8 accepted static-analysis warnings recorded in
`DEVOPS_RECORD`. Do not audit its internals; **do** audit our use of it.

**Gate 2 state entering this round:**
P-1 0 errors / 0 first-party warnings / 8 accepted vendor ·
P-2 9 suites / 0 failed / **3,086 assertions** ·
P-3 all greps match · P-4 not performed (needs the client, Block 4).

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

## 7. ADVERSARIAL SWEEP — the round-2 set

Rows X-1…X-12 carry over from round 1 and must be re-run. X-13…X-22 are new and
target the remediation.

| # | Vector | Verdict | Evidence |
|---|---|---|---|
| X-1 | `NaN` / `±inf` mass in a forge proposal | | |
| X-2 | Proposal that sums correctly but puts a face below the shape floor | | |
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
| **X-13** | **Any sequence of shape changes that RAISES `PurchasedBudget`.** Try every ordered pair and triple across D4/D6/D8/D12/D20. | | |
| **X-14** | **Any sequence where `MassBudget` ends above `PurchasedBudget`.** That is budget from nowhere. | | |
| **X-15** | **Any sequence that raises the usable budget above the current shape's `cashBudgetCap`.** | | |
| **X-16** | **Forging at a capped budget, then switching to a wider shape** — does the restored budget interact correctly with the faces actually stored? | | |
| **X-17** | **A profile whose `PurchasedBudget` is absent, zero, negative, `NaN` or `inf`.** Does the fallback in `performSetShape` fail closed, or does it hand out a default? | | |
| **X-18** | **The v1 → v2 migration.** Is it lossless? Idempotent if run twice? What happens to a profile with several dice, or a die with no `MassBudget`? | | |
| **X-19** | **A v2 profile loaded by an older server** (`SchemaVersion > TEMPLATE`). Does it quarantine rather than overwrite? | | |
| **X-20** | **The recursive `_reconcile`.** Can it corrupt a valid profile, overwrite live data with template values, recurse unboundedly, or descend into any array it should not? | | |
| **X-21** | **The forge cost scaling.** Can `budget` reach a value making cost 0, negative, `NaN`, or overflow? Is a large-budget forge ever CHEAPER than a small-budget one? | | |
| **X-22** | **Refund correctness with the new cost.** The refund credits `cost` — can the recomputed cost ever differ from the amount actually charged? | | |

---

## 8. AREAS I WANT ADVERSARIAL ATTENTION ON

1. **`PurchasedBudget` as an economic quantity.** It is persisted, server-held,
   and determines mass capacity. Who can write it? Today: `ForgeService`
   (carrying it unchanged) and `PlayerProfile._reconcile` / `_migrate` (seeding
   it). **Is that the complete list?** Should it be behind `EconomyService` like
   the currencies are, given it is bought with Cash under FR-3.6?

2. **The `minViable` floor.** `performSetShape` clamps to
   `shape.massFloor * shape.faceCount`. Is that always achievable — can the
   resulting per-face mass ever land below the floor after `ForgeMath.snap`
   rounding, leaving a die that cannot be forged?

3. **The exactBudget re-derivation.** `faceMass = snap(newBudget / faceCount)`
   then `exactBudget = snap(faceMass * faceCount)`. This deliberately makes the
   stored budget match what the faces can actually sum to. **Does it drift?**
   Repeated shape changes each re-derive — can the budget ratchet down (or up)
   over many changes?

4. **F-AD-1's fix versus its own regression history.** This path has now been
   wrong in both directions: first confiscating purchased progression, then
   manufacturing it. Convince yourself the third version is right, and say what
   would have to be true for it to be wrong again.

5. **The three Studio-only seams**, re-verified: still `IsStudio()`-guarded,
   still unreachable from a client?

6. **Test integrity.** UT-12 briefly asserted against a die that a *refused*
   call had left untouched — the assertions passed vacuously until the missing
   unlock was found. **Are there other vacuous assertions?** A test that cannot
   fail is worse than no test.

## 9. KNOWN GAPS — do not report these as discoveries

- **P-4 runtime smoke has not run.** No client exists; Block 4 builds it.
- **NFR-1 / NFR-2 performance targets unmeasured.** Roadmap P-6C.
- **FR-6.3's shape crossover is unverified.** All five shapes carry an identical
  mass floor of 1 and 10 mass per face. Documented in `DiceCatalog`; the sweep is
  roadmap P-6B. Balance opinions welcome but are not Gate 3/4 findings.
- **Forge cost NUMBERS are provisional.** `BASE_COST_PER_MASS_UNIT = 5.0`,
  `REFERENCE_BUDGET = 60`, `SCALE_EXPONENT = 2.0`. The F-AD-2 fix delivers the
  STRUCTURE; the values are P-6B's to settle. Report a structural flaw; do not
  re-report "the numbers are untuned".
- **`MonetizationService` does not exist.** Zero `ProcessReceipt` assignments is
  correct until Block 5.
- **Vendored ProfileStore's 8 warnings are accepted**, bounded, recorded.
- **`Format` and `UpgradeCatalog` have no consumer yet.**

## 10. WHAT A GOOD REPORT LOOKS LIKE

Every row verdicted, cited, and quoted. Findings numbered, tagged, counted, with
the count matching the list. Anything unverified marked `UNVERIFIED` with a
reason. Verdict block in exactly the §2 format.

Round 1 found three real defects, one of which was a live progression exploit.
**Aim to beat it.**
