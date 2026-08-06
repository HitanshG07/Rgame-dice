# CROSS-VENDOR AUDIT BRIEF — Dice Forge, Block 3 (re-audit)

**Date:** 2026-08-07
**Commit under audit:** see `git rev-parse HEAD` in `C:\RGame`
**Mandate:** **READ-ONLY.** Evaluate, cite, report. Never modify a source file.

---

## 0. WHY THIS IS A RE-AUDIT — read before anything else

Block 3 was audited on 2026-08-06 against a brief materially similar to this one.
That audit returned:

```
GATE 3 VERDICT: AUDIT-APPROVED    FINDINGS: 0
GATE 4 VERDICT: SECURE            FINDINGS: 0
```

with every checklist row marked PASS and every row carrying a `file:line`
citation.

**The code it approved contained a call to `ElementCatalog.getElement`, a
function that has never existed in this codebase.** Every element assignment
would have errored on first use.

Seven of its citations were then spot-checked against the files. **All seven
were wrong:**

| Claimed | Cited at | Actually at |
|---|---|---|
| `isVoidFace` | RollService 82–96 | **118** |
| `streakMultiplier` | RollService 50–65 | **94** |
| `PlayerProfile.mutate` | PlayerProfile 237–246 | **284** |
| `recordPurchase` | PlayerProfile 260–275 | **306** |
| `AddUserId` | PlayerProfile 210 | **222** |
| offline-rate guard (T-30) | RollService 365–375 | **340** |
| `snapAll` | ForgeMath 122 | **74** |

A wrong citation is proof the row was not evaluated. Row `D-8` — "blind
re-derivation was performed before opening the diff" — was self-certified PASS,
which no artifact can support.

This is logged as **ledger L-021**. The lesson: demanding a numeric finding count
was necessary and insufficient, because a plausible citation is cheaper to
generate than a real one. **This brief therefore requires citations to be
verifiable, and they will be verified on receipt.**

---

## 1. THE CITATION PROTOCOL — non-negotiable

1. **Every verdict row cites `file:line` for a line you actually opened.**
2. **Quote the line.** Each citation must include the verbatim text of the cited
   line, not only its number. A line number alone is not evidence; a quote that
   does not match the file is a detectable fabrication.
3. **On receipt, at least three PASS rows will be selected at random and
   resolved against the files.** If any citation is wrong, **the entire audit is
   rejected and re-run** — not the row, the audit.
4. **An unsubstantiated PASS counts as FAIL.**
5. If you cannot verify a row, mark it `UNVERIFIED` with a one-line reason.
   `UNVERIFIED` is an acceptable, honest answer. A fabricated PASS is not.

## 2. THE FINDINGS-COUNT PROTOCOL

A mitigation note, hardening suggestion, "consider…", "should also…", or
"for future construction…" **IS A FINDING.** It must be numbered, tagged, and
included in the count. "No findings" coexisting with written weakness notes is a
misclassification (ledger L-018).

Required verdict block, exactly this format:

```text
GATE 3 VERDICT: AUDIT-APPROVED | REJECTED-TO-GATE-1
FINDINGS: <integer>
GATE 4 VERDICT: SECURE | FLAGGED
FINDINGS: <integer>
```

Tag every finding with a threat id (`T-nn`), requirement id (`FR-n.n` / `NFR-n`),
or matrix line (`D-n` / `E-n`).

**Zero is a permissible answer.** It is also the answer that requires the most
evidence and historically received the least. If you reach zero, say explicitly
which rows you verified by opening the file.

---

## 3. SCOPE

Repository `HitanshG07/Rgame-dice`, local path `C:\RGame`. **PRIVATE** — which is
what permits `docs/blueprint/THREAT_MODEL.md`, `SRS.md`, `HLD.md` and
`API_DATA_CONTRACT.md` to be disclosed to you in full. Read them as source of
truth.

**This brief contains no credentials.** If you encounter any secret pattern in
the code, report it immediately as a critical finding tagged `E-3`.

### Files in scope

| File | Lines | Status |
|---|---|---|
| `src/Shared/DiceCatalog.luau` | ~112 | new in Block 3 |
| `src/Shared/UpgradeCatalog.luau` | ~135 | new in Block 3 |
| `src/Shared/Format.luau` | ~62 | new in Block 3 |
| `src/Server/RateLimiter.luau` | ~80 | new in Block 3 (extracted from RemoteGateway) |
| `src/Server/ForgeService.luau` | ~300 | new in Block 3 |
| `src/Server/ServerBootstrap.server.luau` | ~150 | new in Block 3 |
| `src/Server/PlayerProfile.luau` | ~420 | **modified** — deep copy, `_reconcile` on the live path, Studio-only seam |
| `src/Server/RollService.luau` | ~490 | **modified** — Freeze re-roll, emitter seam, MASS_FLOOR removed |
| `src/Server/EconomyService.luau` | ~145 | **modified** — explicit balance branch helpers |
| `src/Server/RemoteGateway.luau` | ~180 | **modified** — rate limiting delegated to RateLimiter |
| `tests/Fakes.luau` + 9 `*.test.luau` | ~1,900 | suites UT-1…UT-8, UT-12 |

### Out of scope
`src/Server/Vendor/ProfileStore.luau` — third-party, pinned `45c9847`,
Apache-2.0, vendored unmodified. Its 8 accepted static-analysis warnings are
recorded in `DEVOPS_RECORD`. **Do not audit its internals; do audit our use of it.**

### Gate 2 state entering this audit
- P-1 static analysis: 0 errors, 0 first-party warnings, 8 accepted vendor warnings
- P-2 suite: 9 suites, 0 failed, **3,046 assertions**
- P-3 prohibition greps: all match expectation
- P-4 runtime smoke: **not performed** — needs the client, which is Block 4

---

## 4. MATRIX D — RESILIENCE (Gate 3). Enumerated inline; one verdict per row.

| ID | Line item | Verdict | `file:line` + verbatim quote |
|---|---|---|---|
| D-1 | Every dereference on a possibly-absent value is guarded or provably safe. | | |
| D-2 | Boundary inputs — zero, negative, empty collection, empty string, maximum size, single-element — all produce defined behaviour. | | |
| D-3 | No unsynchronised read-modify-write on shared state; no ordering assumption between independent async operations. | | |
| D-4 | Every deferred operation has a failure consumer; no fire-and-forget where failure matters. | | |
| D-5 | Every acquisition (memory, handle, connection, lock, subscription, timer) has a guaranteed release on success **and** failure paths. | | |
| D-6 | Retried or duplicated invocations of state-changing operations do not corrupt state. | | |
| D-7 | Every pre-existing behaviour sharing a code path with the change was re-verified, with evidence. | | |
| D-8 | Blind re-derivation performed: expected behaviour written from the spec **before** the diff was opened, mismatches resolved with evidence or logged. | | |
| D-9 | Every parameter crossing into an external system is validated against queried capabilities at runtime, never assumed. | | |

**D-8 specifically:** if you did not do this, mark it `UNVERIFIED`. It was
self-certified PASS last time and that is not auditable.

## 5. MATRIX E — SECURITY (Gate 4). Enumerated inline.

| ID | Line item | Verdict | `file:line` + verbatim quote |
|---|---|---|---|
| E-1 | All inbound data crossing a trust boundary is validated, encoded, or allowlisted before use. | | |
| E-2 | No data concatenated into any interpreter — structural separation only. | | |
| E-3 | No secret in source, version-controlled config, logs, error output, or test fixtures. | | |
| E-4 | Every new capability justified by an acceptance criterion. | | |
| E-5 | Every new third-party dependency has a review note and a pinned version. | | |
| E-6 | Every new dependency's licence identified and compatible; copyleft FLAGGED. | | |
| E-7 | No PII, credentials or tokens reach logs in readable form. | | |
| E-8 | Error paths leak no internals to untrusted callers. | | |
| E-9 | Auth / authorization / session paths touched by this change re-verified end to end. | | |

## 6. THREAT MODEL — verify each mitigation in code

| Threat | Claimed mitigation | Verdict | `file:line` + quote |
|---|---|---|---|
| T-3 | Per-player per-remote token buckets bound the roll rate | | |
| T-5 | Element ids resolved against a static allowlist, never used as a live index | | |
| T-7 | Generic notice codes outward; detail stays in the server log | | |
| T-8 | `InvokeClient` appears nowhere | | |
| T-10 | Failed load / foreign lock **fails closed**; no default profile is ever served | | |
| T-11 | No `SetAsync` on profile data | | |
| T-12 | Versioned migration chain; every field defaulted | | |
| T-13 | Receipt retention bounded **and time-aware**; payload ceiling enforced | | |
| T-25 | Finiteness checked **before** summation | | |
| T-26 | `IsActive()` check synchronous with the mutation, no yield between | | |
| T-30 | Offline rate floored at a 60s window and capped | | |

## 7. ADVERSARIAL SWEEP — attack it, do not describe it

| # | Vector | Verdict | Evidence |
|---|---|---|---|
| X-1 | `NaN` / `±inf` mass in a forge proposal | | |
| X-2 | Forge proposal that sums correctly but puts a face below the shape floor | | |
| X-3 | Forge proposal of the wrong length, or a non-table payload | | |
| X-4 | Element id that is not in the catalog; element the player has not unlocked | | |
| X-5 | Shape the player has not unlocked; shape already equipped (must not charge) | | |
| X-6 | Any path where Cash is deducted but the mutation does not apply | | |
| X-7 | Any path where a mutation applies without the cost being deducted | | |
| X-8 | Remote spam past the burst cap; one player's exhaustion affecting another | | |
| X-9 | Mutation attempted against a **released** profile | | |
| X-10 | Join → single roll → leave, to inflate the offline rate (T-30) | | |
| X-11 | Currency written by any module other than `EconomyService` | | |
| X-12 | Any inbound remote accepting a price, balance, reward, level, duration, multiplier or outcome (NFR-5) | | |

---

## 8. AREAS I WANT ADVERSARIAL ATTENTION ON

Written by the author of the code. Treat these as leads, not as a boundary — a
finding outside this list is worth more, not less.

1. **The three Studio-only test seams.** `PlayerProfile._injectProfileForTesting`
   writes straight into the active-session table, bypassing session locking
   entirely. `RollService._setResultEmitterForTesting` and
   `ForgeService._setResultEmitterForTesting` redirect player-facing results.
   Each is guarded by `RunService:IsStudio()`. **Is that guard sufficient?** Is
   there any path in a live server where `IsStudio()` returns true? Would you
   accept these existing at all in shipped code?

2. **The shape-change carry-over.** `performSetShape` carries the purchased mass
   budget across, clamped into the new shape's range, and carries elements for
   as many faces as the new shape has. Can that be used to launder budget or
   elements between shapes for profit — for example D20 → D4 → D20?

3. **The forge cost curve.** `BASE_COST_PER_MASS_UNIT = 5.0`, flat and never
   scaling with progression. FR-3.3 requires re-forging to be non-trivial
   because free re-forging collapses the cross-die puzzle (ledger L-016). Is 5
   cash per mass unit still non-trivial at late-game balances?

4. **Refund paths.** All three forge handlers refund on a refused mutation. Can a
   refund fire without the spend having succeeded, or twice?

5. **`_reconcile` now runs on the live load path.** It mutates the profile
   in-place immediately after ProfileStore's own `Reconcile()`. Can it damage a
   valid profile? Its type-repair branches overwrite a wrongly-typed field with
   a default — is that ever destructive to recoverable data?

6. **The `RateLimiter.consume` `atTime` parameter.** Optional, for tests, with
   non-finite values rejected in favour of `os.clock()`. Only `RemoteGateway`
   calls it and never passes the parameter. Is this a real attack surface?

7. **`ServerBootstrap`'s join path.** `PlayerAdded` is connected before any
   yielding require; joins during startup are queued; `admitPlayer` is
   idempotent; a delayed sweep catches stranded players. **Can a player end up
   seated with no profile and no kick?** That is a fail-open on T-10 and it is
   the specific outcome this structure exists to prevent.

## 9. KNOWN GAPS — do not report these as discoveries

Stated so your findings count reflects new information.

- **P-4 runtime smoke has not run.** No client exists; Block 4 builds it.
- **NFR-1 / NFR-2 performance targets are unmeasured.** Deferred to roadmap P-6C.
- **FR-6.3's shape crossover is unverified.** All five shapes currently carry an
  identical mass floor of 1 and 10 mass per face. Deliberate and documented in
  `DiceCatalog`; the numerical sweep is roadmap P-6B. Balance opinions are
  welcome but are not Gate 3/4 findings.
- **`MonetizationService` does not exist.** Zero `ProcessReceipt` assignments is
  currently correct; the "exactly one" rule binds from Block 5.
- **Vendored ProfileStore's 8 static-analysis warnings are accepted**, bounded
  and recorded in `DEVOPS_RECORD`.
- **`Format` and `UpgradeCatalog` have no consumer yet.** Blocks 4 and 5 wire
  them.

## 10. WHAT A GOOD REPORT LOOKS LIKE

- Every row in §4–§7 carries a verdict, a `file:line`, and the quoted line.
- Findings numbered, tagged, and counted — with the count matching the list.
- Anything you did not verify marked `UNVERIFIED` with a reason.
- The verdict block in exactly the §2 format.

**Reporting three real findings beats reporting zero.** The last zero cost this
project a shipped crash.
