# CROSS-VENDOR AUDIT BRIEF — Dice Forge, Block 3 (Core Loop, Forge & Server Services)

**Date**: 2026-08-06  
**Auditor Persona**: Isolated Fresh-Context QA & Security Auditor (Cross-Vendor, Rung 1 Isolation)  
**Mandate**: **READ-ONLY**. You are evaluating implemented Luau server code and test suites against the binding specification. You must **NEVER fix or modify any source file** — evaluate, cite evidence, and report findings only.

---

## 1. REPOSITORY SCOPE & PRIVACY NOTE

- **Repository**: `HitanshG07/Rgame-dice` (Local Path: `C:\RGame`)
- **Visibility**: **PRIVATE**. Because this repository is private and access is restricted, the full threat model (`THREAT_MODEL.md`), system requirements (`SRS.md`), data contracts (`API_DATA_CONTRACT.md`), and high-level architecture (`HLD.md`) are disclosed in full to the auditor in this brief.
- **Credential & Secret Protection Notice**: This audit brief contains **ZERO credentials, ZERO private tokens, and ZERO Discord webhook URLs**. If any secret pattern is encountered during code inspection, log it immediately under Matrix E line `E-3` and tag it as a critical security finding.

---

## 2. GOVERNANCE CORRECTIONS & AUDIT RULES

Every checklist line in this brief is **enumerated inline**. Nothing is referenced from external checklists or summary documents. Two historical failures from prior audit cycles on this codebase directly inform these requirements:

### Failure 1 (Ledger L-014) — Partial Checklist Execution
> **Historical Fact**: A previous audit reported evaluating "every line of Matrix D" while only inspecting 4 of the 9 lines. Referenced checklists lead to silent omissions.
> **Mandatory Rule**: Every Matrix D and Matrix E line is enumerated as an individual row in an inline table with a mandatory `Verdict` column (`PASS`, `FAIL`, `N/A`) and `Evidence` column (`file:line` or verbatim quote). A blank row or missing line is a visible audit failure.

### Failure 2 (Ledger L-018) — Misclassification of Mitigation Notes
> **Historical Fact**: An audit returned `SECURE` claiming "no findings" in its summary, while the body text contained five substantive vulnerability mitigation notes. Four were real defects and one exposed a flaw in the author's threat model.
> **Mandatory Rule**: A mitigation note, hardening suggestion, "consider," "should also," or "for construction" remark **IS A FINDING**. It must be numbered, tagged, and counted in the numeric findings total. `"No findings"` coexisting with written weakness notes is a misclassification.

### Three Unbreakable Execution Directives
1. **Mandatory Verdicts**: Every inline line gets an explicit `PASS`, `FAIL`, or `N/A`. Every `N/A` requires a mandatory one-line justification. Unjustified `N/A` marks count as `FAIL`.
2. **Empirical Evidence**: Every passing row must cite empirical evidence (`file:line` or exact symbol reference). Unsubstantiated passes count as `FAIL`.
3. **Mandatory Tagging & Numeric Format**: Every finding MUST be tagged with its Threat ID (`T-nn`), Requirement ID (`FR-n.n` / `NFR-n`), API Contract ID (`C-n`), or Matrix Line ID (`D-n` / `E-n`). The final verdict block MUST match this exact format:

```text
GATE 3 VERDICT: AUDIT-APPROVED | REJECTED-TO-GATE-1
FINDINGS: <integer>
GATE 4 VERDICT: SECURE | FLAGGED
FINDINGS: <integer>
```

---

## 3. EXACT FILES IN SCOPE & LINE COUNTS

The audit scope covers **Block 3 Luau Server Implementations, Shared Catalogs, and Unit Test Suites**.

### Source Modules (`src/`) — 13 Files, 2,255 Lines
| Relative Path | Lines | Purpose & Responsibility |
|---|---|---|
| `src/Shared/DiceCatalog.luau` | 88 | Per-shape face counts, mass floors, budget caps, shape lookup |
| `src/Shared/UpgradeCatalog.luau` | 131 | Upgrade definitions, tier costs, unlock requirements |
| `src/Shared/Format.luau` | 61 | Large number formatting, suffix ladder (precision-safe up to $1\text{e}300$) |
| `src/Shared/ForgeMath.luau` | 251 | Pure zero-sum forge math, weighted sampling, face values, probability |
| `src/Shared/Remotes.luau` | 152 | Remote name registry, creation helper, payload structure |
| `src/Shared/ElementCatalog.luau` | 91 | Element payoff functions (Gold, Fire, Multiplier) |
| `src/Server/RateLimiter.luau` | 76 | Extracted token-bucket rate limiting logic per player per endpoint |
| `src/Server/RemoteGateway.luau` | 184 | Sole inbound network trust boundary & remote handlers |
| `src/Server/RollService.luau` | 438 | Core roll loop, streak calculations, outcome resolution, cash payout |
| `src/Server/ForgeService.luau` | 219 | Mass redistribution, elemental face modifications, profile mutation |
| `src/Server/ServerBootstrap.server.luau` | 66 | Server startup sequence, service dependency wiring, player lifecycle |
| `src/Server/PlayerProfile.luau` | 373 | Sole ProfileStore persistence boundary, profile loading & mutations |
| `src/Server/EconomyService.luau` | 125 | Sole currency writer (Cash, Gems, Diamonds) |

### Test Modules (`tests/`) — 10 Files, 1,303 Lines
| Relative Path | Lines | Test Coverage Target |
|---|---|---|
| `tests/RunAll.server.luau` | 81 | Automated test runner harness & reporter |
| `tests/Fakes.luau` | 140 | Test doubles, mock player objects, and mock datastores |
| `tests/ForgeMath.test.luau` | 140 | Mathematical invariants, zero-sum budget, landing probabilities |
| `tests/ForgeValidation.test.luau` | 219 | Proposal validation, boundary checks, non-finite handling |
| `tests/Sampling.test.luau` | 182 | Weighted distribution empirical frequency & RNG determinism |
| `tests/Payout.test.luau` | 284 | Payout formulas, compounding streak multiplier, element bonuses |
| `tests/Elements.test.luau` | 74 | Element payoff functions & combined mass scaling |
| `tests/ProfileLifecycle.test.luau` | 65 | Session lock handling, load failures, fail-closed mechanics |
| `tests/ProfileSchema.test.luau` | 55 | Default profile template defaults & structural integrity |
| `tests/RateLimit.test.luau` | 63 | Token bucket replenishment, burst limits, player isolation |

**Total In-Scope Luau Codebase**: 23 files, **3,558 lines** (2,255 source + 1,303 test).

### Out of Scope Files
- `src/Server/Vendor/ProfileStore.luau` (2,243 lines — third-party vendored dependency, pinned `45c9847`, Apache-2.0).
- `src/Client/**` (Client presentation layer; unbuilt in V1 server scope).
- `.brain/**` (Governance files).

---

## 4. BINDING ARCHITECTURAL INVARIANTS & SPECIFICATIONS

The auditor must verify the implementation against the following binding documents located in `docs/blueprint/`:
1. `SRS.md` — Software Requirements Specification (FR-1..FR-14, NFR-1..NFR-8)
2. `HLD.md` — High-Level Architecture & Authority Model
3. `API_DATA_CONTRACT.md` — Network Remote Signatures & Profile Schema Invariants
4. `THREAT_MODEL.md` — Threat Catalogue (T-1..T-30), Mitigations & Risk Table (R-1..R-8)
5. `TEST_PLAN.md` — Test Suite Specification (UT-1..UT-11)

### Load-Bearing Architecture Facts
- **Server Authority**: The server decides every roll outcome by weighted sampling over face mass distributions. Client 3D rigid-body dice tumbles are **visual animations only** resolving to the server-determined outcome. The server holds zero physical rigid-body state.
- **Zero-Sum Forging**: Each die has a fixed total mass budget. Forging shifts mass between faces ($m_i$) but **never adds mass**.
- **Payout & Probability Math**:
  $$\text{Landing Probability: } P(i) = \frac{M - m_i}{M(n-1)}$$
  $$\text{Face Payout Value: } V(i) = m_i^\alpha \quad (\alpha = 2.0)$$
  $$\text{Compounding Streak Multiplier: } M_{\text{streak}} = (1 + b)^s \quad (\text{double capped})$$
- **Single-Writer Enclosure**: `EconomyService.luau` is the ONLY authorized writer of currency (`Cash`, `Gems`, `Diamonds`). `PlayerProfile.luau` is the ONLY authorized writer to ProfileStore. `RemoteGateway.luau` is the ONLY inbound network boundary.

---

## 5. STEP 1 — GATE 3: COGNITIVE AUDIT

Persona: **Isolated Fresh-Context QA Auditor**

### 5a. Blind Re-Derivation Requirement
**BEFORE opening any source file**, the auditor must read `SRS.md`, `HLD.md`, and `API_DATA_CONTRACT.md`. Write down from spec alone what the Block 3 modules must enforce, what invariants must hold, and what edge cases would constitute a defect. Reconcile this re-derived spec against the actual code. Any mismatch is a finding until resolved with evidence.

### 5b. Specification Conformance Matrix
| ID | SRS Requirement | Check & Condition | Verdict | Evidence |
|---|---|---|---|---|
| S-1 | `FR-2.2` / `FR-2.3` | Server samples face via $P(i) = \frac{M-m_i}{M(n-1)}$ using server-side RNG | | |
| S-2 | `FR-2.4` | Face payout value calculated as $V(i) = m_i^{2.0}$ | | |
| S-3 | `FR-2.6` | Cash credited to player profile **BEFORE** `RollResult` network event is fired | | |
| S-4 | `FR-3.2` | Forge request accepts a complete mass distribution; any validation failure rejects the entire proposal and mutates nothing | | |
| S-5 | `FR-4.3` | Element payoff (e.g. Gold) scales superlinearly with combined mass and requires $\ge 2$ participating faces | | |
| S-6 | `FR-5.2` | Void face is detected as a face at or near mass floor ($m_i \le \text{floor} \times 1.5$) | | |
| S-7 | `FR-5.3` | Streak multiplier compounds as $(1+b)^s$ and is double-capped ($s \le 50$, $M_{\text{streak}} \le 10^6$) | | |
| S-8 | `FR-5.4` | Base streak strength $b$ derives from profile upgrade level (`StreakStrength`), not a global constant | | |
| S-9 | `FR-14.1` | Player profile stored in memory during active session; zero DataStore calls during transaction | | |
| S-10 | `FR-14.3` | Profile load failure or session lock conflict **fails closed** — never returns dummy/default state | | |
| S-11 | `FR-14.7` | `Profile:IsActive()` check is synchronous with data mutation (no yielding between check and write) | | |
| S-12 | `FR-14.8` | `EconomyService` is the sole writer of currency balances | | |
| S-13 | `NFR-4` | Every inbound numeric argument is explicitly verified with `ForgeMath.isFinite()` before use | | |
| S-14 | `NFR-5` | No network remote accepts a client-provided price, balance, reward, multiplier, or outcome | | |
| S-15 | `NFR-8` | All modules declare `--!strict`; `RemoteFunction:InvokeClient` appears nowhere in codebase | | |

### 5c. API Data Contract Conformance Matrix
| ID | Contract Check | Specification Requirement | Verdict | Evidence |
|---|---|---|---|---|
| C-1 | Remote Registry | Remote names in `Remotes.luau` match `API_DATA_CONTRACT.md` §1 exactly | | |
| C-2 | Validation Sequence | Inbound validation order is strictly: `rate limit → arity → type → finiteness → bounds → allowlist → affordability` | | |
| C-3 | Finiteness Precedence | In `ForgeService` / `RemoteGateway`, finiteness validation provably precedes mass summation | | |
| C-4 | Mass Precision | Face masses snapped to 4 decimal places via `ForgeMath.snapAll()` prior to validation | | |
| C-5 | Rate Limits | Rate limiter token buckets match contract limits (Roll: 5/s burst 10; Forge: 4/s burst 8) | | |
| C-6 | Profile Schema Defaults | Profile template in `PlayerProfile.luau` contains all fields and defaults specified in contract §3 | | |
| C-7 | Receipt Eviction | `PurchaseIds` array bounded at 200 items with time-aware eviction (3-day window) | | |
| C-8 | Bundle Flag | `BundleOffered` is write-once-true; no code path resets or clears the flag | | |
| C-9 | Remote Creation | Server constructs remotes via `Remotes.createAll()`; client only waits via `getEvent`/`getFunction` | | |

### 5d. Matrix D — Gate 3 Cognitive Audit Checklist (INLINE ENUMERATION)
| ID | Line Item Description | Verdict | Evidence / Justification |
|---|---|---|---|
| D-1 | **Null/absent/uninitialized values**: Every dereference on a possibly-absent value is guarded or provably safe. | | |
| D-2 | **Boundary inputs**: Zero, negative, empty collection, empty string, maximum size, and single-element cases all produce defined behavior. | | |
| D-3 | **Concurrency**: No unsynchronized read-modify-write on shared state; no ordering assumption between independent asynchronous operations. | | |
| D-4 | **Asynchronous failure**: Every deferred operation has a rejection/failure consumer; no fire-and-forget on operations whose failure matters. | | |
| D-5 | **Resource lifecycle**: Every acquisition (memory, handle, connection, lock, subscription, timer) has a guaranteed release on both success and failure paths. | | |
| D-6 | **Idempotency**: Retried or duplicated invocations of state-changing operations do not corrupt state. | | |
| D-7 | **Regression**: Every pre-existing behavior sharing a code path with the change was re-verified, with evidence. | | |
| D-8 | **Blind re-derivation**: Blind re-derivation was performed before opening the diff, and mismatches were resolved with evidence. | | |
| D-9 | **Code-to-world contract**: Every parameter crossing into an external system is validated against queried capabilities at runtime, never assumed. | | |

### 5e. Gate 3 Mandatory Verdict Format
The auditor MUST output Gate 3 findings tagged with requirement IDs and end with this exact verdict block:

```text
GATE 3 VERDICT: AUDIT-APPROVED | REJECTED-TO-GATE-1
FINDINGS: <integer>
```

---

## 6. STEP 2 — GATE 4: SECURITY CLEARANCE

Persona: **Cyber Security Master**

### 6a. Matrix E — Gate 4 Security Hardening Checklist (INLINE ENUMERATION)
| ID | Line Item Description | Verdict | Evidence / Justification |
|---|---|---|---|
| E-1 | **Trust Boundary Scrubbing**: All inbound data crossing a trust boundary is validated, encoded, or allowlisted before use. | | |
| E-2 | **Interpreter Separation**: No data is concatenated into any interpreter (query, shell, markup, template, deserializer, dynamic eval) — structural separation only. | | |
| E-3 | **Secret Containment**: No secret value appears in source, configuration under version control, logs, error output, or test fixtures. | | |
| E-4 | **Least Privilege**: Every new capability (endpoint, permission, file/network/process access) is justified by an acceptance criterion. | | |
| E-5 | **Dependency Review**: Every new third-party dependency has a review note (purpose, why nothing existing suffices, maintenance posture) and a pinned version where supported. | | |
| E-6 | **License Compliance**: Every new dependency's license was identified and is compatible with intended distribution; copyleft licenses are FLAGGED. | | |
| E-7 | **PII & Data Masking**: No PII, credentials, or session tokens reach logs, error messages, or analytics in readable form; sensitive fields masked/hashed. | | |
| E-8 | **Failure Leakage**: Error paths leak no internals (stack traces, paths, query text, configuration values) to untrusted callers. | | |
| E-9 | **Auth & Crypto Re-verification**: Authentication, authorization, and token/cryptographic verification paths touched by this change were re-verified end-to-end. | | |

### 6b. Threat Model Mitigation Verification Matrix (`THREAT_MODEL.md`)
| Threat ID | Claimed Mitigation | Verification Task in Code | Verdict | Evidence |
|---|---|---|---|---|
| T-1 | Server-Side Outcome Sampling | Confirm client sends no face, value, or payout amount in `RollService` | | |
| T-3 | Bounded Roll Rate | Confirm `RateLimiter` enforces server-defined token bucket per player | | |
| T-4 | Atomic Zero-Sum Mass Check | Confirm `ForgeService` rejects mass budget inflation and mutates nothing on fail | | |
| T-5 | Allowlisted Element IDs | Confirm element lookup in `ElementCatalog` uses static table allowlist | | |
| T-7 | Sanitized Error Return | Confirm `RemoteGateway` returns generic error codes (`invalid_payload`, etc.) | | |
| T-8 | Prohibited Client Invoke | Confirm `InvokeClient` is absent from all server scripts | | |
| T-10 | Fail-Closed Session Locking | Confirm `PlayerProfile.load` returns `false` on lock conflict or load error | | |
| T-11 | Prohibited `SetAsync` | Confirm `SetAsync` is never called directly on ProfileStore data | | |
| T-12 | Profile Migration Chain | Confirm schema version check and migration run on profile load | | |
| T-13 | Bounded Receipt Retention | Confirm `recordPurchase` evicts expired receipts (3-day window) | | |
| T-25 | Finiteness Guard on Arithmetic | Confirm `ForgeMath.isFinite` guards all calculations before mass summation | | |
| T-26 | Synchronous Mutation Check | Confirm `IsActive()` check has no yield (`task.wait` / async call) before mutate | | |
| T-27 | Mass Quantization | Confirm `snapAll` rounds face masses to 4 dp before budget validation | | |
| T-28 | Finiteness at Internal Boundaries | Confirm numeric values are checked finite at internal service entry points | | |
| T-30 | Offline Earnings Rate Floor | Confirm `averageIncomePerSecond` enforces 60s minimum rate window | | |

### 6c. Adversarial Attack Sweep
Evaluate the codebase against these 10 explicit attack vectors:
| Attack ID | Adversarial Input Vector | Target Module | Expected Code Defense | Verdict | Evidence |
|---|---|---|---|---|---|
| X-1 | Forge proposal with `NaN` mass in one face and valid sum | `ForgeService.luau` | `isFinite` fails before summation step | | |
| X-2 | Forge proposal with `math.huge`, `-math.huge`, or `-0` mass | `ForgeMath.luau` | `isFinite` returns false, proposal rejected | | |
| X-3 | Forge proposal meeting total sum but containing face mass below floor | `ForgeMath.luau` | `mass_below_floor` error returned | | |
| X-4 | `EconomyService.credit` called with negative or non-finite amount | `EconomyService.luau` | Transaction rejected with error | | |
| X-5 | Remote call with missing, extra, or wrong-typed arguments | `RemoteGateway.luau` | Arity & type check rejects with `invalid_args` | | |
| X-6 | Single player spamming network remote to exhaust rate limiter | `RateLimiter.luau` | Rate limit bucket isolated per `player.UserId` | | |
| X-7 | Profile mutation attempted after player session released | `PlayerProfile.luau` | `IsActive()` returns false, mutation skipped | | |
| X-8 | Direct state mutation bypassing `EconomyService` | `src/Server/**` | Zero direct writes to profile balance fields outside EconomyService | | |
| X-9 | Network packet dropped mid-roll transaction | `RollService.luau` | Cash credited synchronously prior to `RollResult` event fire | | |
| X-10 | Massive streak level causing floating point overflow in multiplier | `RollService.luau` | Multiplier double-capped at `MAX_STREAK_MULTIPLIER` ($10^6$) | | |

### 6d. Threat Model Gap Analysis
| ID | Gap Analysis Question | Verdict | Evidence & Findings |
|---|---|---|---|
| TM-1 | What threat or vulnerability exists in the implementation that is NOT covered in `THREAT_MODEL.md`? | | |
| TM-2 | What mitigation claimed in `THREAT_MODEL.md` is NOT fully implemented in the code? | | |
| TM-3 | Where does a code comment assert a safety property that the implementation does not actually enforce? | | |

### 6e. Gate 4 Mandatory Verdict Format
The auditor MUST tag every security finding with its Threat ID (`T-nn`) or Matrix E line (`E-n`) and end with this exact verdict block:

```text
GATE 4 VERDICT: SECURE | FLAGGED
FINDINGS: <integer>
```

---

## 7. AUDITOR EXIT ARTIFACT DIRECTIVE

Upon completion of the audit pass, the auditor MUST write their full findings and verbatim verdict blocks to the following disk artifact paths:
- **Gate 3 Evidence Artifact**: `deliveries/evidence/2026-08-06-block3-gate3-audit.md`
- **Gate 4 Evidence Artifact**: `deliveries/evidence/2026-08-06-block3-gate4-security.md`

**REMINDER**: As a READ-ONLY auditor, do NOT modify any source code under `src/` or `tests/`. Return findings and verdicts only.
