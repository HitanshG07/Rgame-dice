# CROSS-VENDOR AUDIT BRIEF — Dice Forge, Blocks 1 + 2 (CODE)

You are auditing **implemented Luau code** against a binding specification. Two steps: Gate 3 (cognitive audit), then Gate 4 (security clearance). **You never fix anything — report only.**

---

## HOW THIS BRIEF IS WRITTEN, AND THE TWO FAILURES IT CORRECTS

Every checklist line is **enumerated inline**. Nothing is referenced from another file. Two prior audits on this project each needed correction at verification, and the fixes are baked into this document:

**Failure 1 (ledger L-014) — incompleteness.** An audit reported evaluating "every line of Matrix D" while addressing 4 of 9, and reported checking "NFR-1 through NFR-5" against a document containing NFR-1 through NFR-8. *Fix: everything is a numbered row with a mandatory verdict column. A blank row is a visible omission.*

**Failure 2 (ledger L-018) — misclassification.** The next audit returned `SECURE` with section 2c reading **"no findings"**, while the same artifact contained five substantive vulnerabilities each with a written "mitigation note for construction." Four were genuine; one exposed a real reasoning error in the author's own threat model. *Fix, and this is binding:*

> **A mitigation note, hardening suggestion, "should also," "consider," or "for construction" remark IS A FINDING.** It must be numbered, tagged, and counted. You must state a **numeric finding count** in each verdict block. `"no findings"` cannot coexist with any populated discussion of weaknesses. If you write a sentence describing something that should be improved, that is a finding — classify it as one.

**Three hard rules.**
1. **Every row gets a verdict**: `PASS`, `FAIL`, or `N/A`. Every `N/A` carries a one-line justification. An unjustified `N/A` counts as `FAIL`.
2. **Every evidence cell cites something you actually read** — `file:line`, or a verbatim quote. No evidence ⇒ the verdict is `FAIL`, not `PASS`.
3. **State a numeric finding count** in both verdict blocks, even if it is zero.

A zero-finding result is a *possible* outcome, not a target. Both previous zero/low-finding audits on this project were wrong. Treat your own "everything passes" conclusion with suspicion before writing it.

---

## WHAT YOU ARE AUDITING

Commit `ee9fa6e`. **7 source modules + 5 test files, 2,456 lines.**

```
src/Shared/ForgeMath.luau         251   pure forge mathematics
src/Shared/Remotes.luau           152   remote-name registry
src/Shared/ElementCatalog.luau     91   element payoff functions
src/Server/PlayerProfile.luau     331   sole ProfileStore boundary
src/Server/RemoteGateway.luau     242   sole inbound trust boundary
src/Server/EconomyService.luau    125   sole currency writer
src/Server/RollService.luau       398   the core roll loop
tests/RunAll.server.luau           81   harness
tests/ForgeMath.test.luau         140   UT-1
tests/ForgeValidation.test.luau   219   UT-2
tests/Sampling.test.luau          182   UT-3
tests/Payout.test.luau            244   UT-4
```

**Binding specification** — audit the code against these, they are the contract:
`docs/blueprint/SRS.md` · `HLD.md` · `API_DATA_CONTRACT.md` · `THREAT_MODEL.md` · `TEST_PLAN.md`

**Out of scope:** `src/Server/Vendor/ProfileStore.luau` (third-party, pinned, Apache-2.0) · `docs/blueprint/**` (already audited, commit `4082e26`) · `.brain/**` · anything unbuilt (all client code, `ForgeService`, `MonetizationService`, `LeaderboardService`, `OfflineService`, `ProgressionService`, `AscensionService`, `ServerBootstrap`, `DiceCatalog`, `UpgradeCatalog`, `Format`, `Fakes.luau`, UT-5…UT-11, IT-1…IT-5).

**Gate 2 is already CLEAN and independently verified:** 4/4 suites, 2,771 assertions, executed live in Studio 2026-08-06. Evidence: `deliveries/evidence/2026-08-06-block2-unit-suite.txt`. **Do not re-run the tests.** Your job is the cognitive and security audit that passing tests cannot provide.

---

## THE ARCHITECTURE IN FIVE SENTENCES

The server decides every roll outcome by weighted sampling; the client's 3D dice tumble is animation resolving to an already-decided face. The server therefore holds **no rigid-body state** — no positions, velocities, orientations, collisions — so **no feature may depend on where a die is, what it hit, or how it moved**; everything resolves from the *resolved face set* alone. Forging is **zero-sum**: each die has a fixed mass budget, and forging moves mass between faces rather than adding it, which is a security property as much as a design one. Heavier faces pay superlinearly (`value = mass²`) but land less often (`P = (M−mᵢ)/(M(n−1))`), and those two formulas were established by simulation before any code existed. Persistence is ProfileStore with fail-closed session locking.

---

# STEP 1 — GATE 3: COGNITIVE AUDIT
Persona: **Isolated Fresh-Context QA Auditor.**

## 1a. Blind re-derivation — BEFORE opening any source file

Read **only** `SRS.md`, `HLD.md`, and `API_DATA_CONTRACT.md`. Then write, from the spec alone, what a correct implementation must contain: which modules, what each must enforce, what invariants must hold, and what would constitute a violation. **Then** open the code.

Every gap between your written expectation and the implementation is a finding until resolved with evidence. Include your written expectation verbatim in the artifact.

*(Do not restate the criteria below as your "expectation." That finds nothing the criteria did not already ask for, and is what happened on the first blueprint audit.)*

## 1b. Specification conformance

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| S-1 | `SRS FR-2.2/2.3`: server samples via `P(i) = (M−mᵢ)/(M(n−1))`, server-held RNG, sole authority | | |
| S-2 | `SRS FR-2.4`: `value(i) = mᵢ^α`, α = 2.0, superlinear | | |
| S-3 | `SRS FR-2.6`: payout survives a lost `RollResult` — Cash credited **before** the event fires | | |
| S-4 | `SRS FR-3.2`: forge accepts a complete distribution; any violation rejects the **whole** proposal and mutates nothing | | |
| S-5 | `SRS FR-4.3`: every conditional element's payoff scales with **combined invested mass** | | |
| S-6 | `SRS FR-5.2`: Void = the lightest face | | |
| S-7 | `SRS FR-5.3`: streak multiplier **compounds** `(1+b)^s` and is capped | | |
| S-8 | `SRS FR-5.4`: `b` derives from the player's Streak Strength investment, not a global constant | | |
| S-9 | `SRS FR-14.1`: profile held in memory for the session; no DataStore round-trip per transaction | | |
| S-10 | `SRS FR-14.3`: load failure or foreign lock **fails closed** — never serves a default profile | | |
| S-11 | `SRS FR-14.7`: `IsActive()` check is **synchronous** with the mutation, no yield between | | |
| S-12 | `SRS FR-14.8`: `EconomyService` is the only writer of Cash/Gems/Diamonds | | |
| S-13 | `SRS NFR-4`: every inbound numeric explicitly checked finite before use | | |
| S-14 | `SRS NFR-5`: no remote carries a price, balance, reward, score, level, duration, multiplier or outcome | | |
| S-15 | `SRS NFR-8`: every module `--!strict`; `InvokeClient` appears nowhere | | |

## 1c. Contract conformance — `API_DATA_CONTRACT.md`

| # | Check | Verdict | Evidence |
|---|---|---|---|
| C-1 | Every remote name in `Remotes.luau` matches §1 exactly — no extras, none missing | | |
| C-2 | Validation executes in the specified order: rate limit → arity → type → **finiteness** → bounds → allowlist → affordability | | |
| C-3 | §2.1 forge validator: all 6 conditions present, and **step 3 (finiteness) provably precedes step 5 (sum)** | | |
| C-4 | §2.1 step 5: masses snapped to 4 dp **before** summation | | |
| C-5 | §2.2 rate limits match the table (Roll 5/s burst 10; Forge/SetElement/SetShape 4/s burst 8; etc.) | | |
| C-6 | §3 profile template: every field present with a default, matching the schema | | |
| C-7 | §3.1 invariant 3: `PurchaseIds` bounded at 200 | | |
| C-8 | §3.1 invariant 5: `BundleOffered` is write-once-true — **no code path resets it** | | |
| C-9 | Server creates remotes, client only waits — never the reverse | | |

## 1d. Architecture-constraint reconciliation — the highest-risk section

The server holds **no per-die physical state**. Ledger L-015 records that the previous project died from specifying behaviour the architecture could not deliver.

| # | Check | Verdict | Evidence |
|---|---|---|---|
| A-1 | No function anywhere reads a die's position, velocity, orientation, or collision | | |
| A-2 | Every element in `ElementCatalog` + `RollService.resolveElements` resolves from the **resolved face set alone** | | |
| A-3 | `ForgeMath` is genuinely **pure** — no state, no side effects, no service calls. It is shared client+server; confirm this grants the client **no authority**, or FAIL it | | |
| A-4 | `RollService`'s pure functions take no `Player`, no profile, and no Roblox service | | |
| A-5 | Per-player roll cost scales with **die count**, not physics complexity (`SRS NFR-2`) | | |

## 1e. Test-quality audit — do the tests test the right thing?

Passing tests are not evidence of correct tests. **This project has already shipped one test that failed for the wrong reason** (a "drift" test that actually drove a value below the mass floor and misattributed the rejection — ledger L-017). Loosening the tolerance to make it pass would have punched a hole through the invariant that stops players inventing mass.

| # | Check | Verdict | Evidence |
|---|---|---|---|
| Q-1 | UT-2 asserts NaN is rejected **for the correct reason** (`non_finite_mass`), which is what proves ordering rather than merely outcome | | |
| Q-2 | UT-3's 100k-sample tolerance is tight enough to catch a real bias, not so loose it passes anything | | |
| Q-3 | UT-3 proves determinism in **both** directions — same seed matches, different seed differs, sampler is not constant | | |
| Q-4 | UT-4 proves the streak **compounds** (successive gains grow) rather than merely increases | | |
| Q-5 | UT-4 asserts Gold is **not flat** in combined mass — the inert failure mode | | |
| Q-6 | **Name any assertion that would still pass if the implementation were subtly wrong.** An empty answer here is not credible for 2,771 assertions | | |
| Q-7 | `RunAll.server.luau` reports a `require` failure as a FAILURE and zero discovered suites as a FAILURE | | |

## 1f. Matrix D — all nine lines, verbatim

| # | Line | Verdict | Evidence |
|---|---|---|---|
| D-1 | Null/absent/uninitialized: every dereference on a possibly-absent value guarded or provably safe | | |
| D-2 | Boundary inputs: zero, negative, empty collection, empty string, maximum size, single-element all produce defined behaviour | | |
| D-3 | Concurrency: no unsynchronized read-modify-write on shared state; no ordering assumption between independent async operations | | |
| D-4 | Asynchronous failure: every deferred operation has a rejection/failure consumer; no fire-and-forget where failure matters | | |
| D-5 | Resource lifecycle: every acquisition has guaranteed release on success **and** failure paths | | |
| D-6 | Idempotency: retried or duplicated state-changing operations do not corrupt state | | |
| D-7 | Regression: every pre-existing behaviour sharing a code path re-verified with evidence | | |
| D-8 | Blind re-derivation performed before opening the diff, mismatches resolved with evidence | | |
| D-9 | Code-to-world contract: every parameter crossing into an external system validated against queried capabilities, never assumed | | |

## 1g. Two known items — adjudicate, do not merely rediscover

Both are disclosed deliberately. Give each an explicit verdict.

**K-1 — Void detection on a flat die.** `RollService.isVoidFace` returns the **lightest** face regardless of whether it sits near the mass floor. On a starting die (all faces equal), face 1 is therefore treated as a Void, so a new player breaks their streak 1-in-6 rolls with no way to avoid it. `SRS FR-5.2` defines a Void as *"a face at or near the mass floor,"* which implies a flat die should have **none**.
**Your task: is the code wrong, is the spec wrong, or is this acceptable? Give a reasoned verdict.**

**K-2 — Bad Roll Shield is unwired.** `RollService.performRoll` reads `data.Upgrades.BadRollShield`, which does not exist in the profile template — the shield is a gamepass and `MonetizationService` is unbuilt. It defaults to off, and UT-4 tests the logic directly by passing the flag.
**Your task: confirm the default is genuinely safe (fails closed, cannot be spoofed), and that no other code path assumes the field exists.**

## 1h. Gate 3 verdict

State exactly one: `AUDIT-APPROVED` or `REJECTED-TO-GATE-1` + numbered defect list.
**State the numeric finding count**, even if zero.
**Exit artifact, this exact path:** `deliveries/evidence/2026-08-06-blocks12-gate3-audit.md`

---

# STEP 2 — GATE 4: SECURITY CLEARANCE
Persona: **Cyber Security Master.** Run only if Gate 3 returned `AUDIT-APPROVED`. If it rejected, stop and report.

## 2a. Matrix E — all nine lines, verbatim

| # | Line | Verdict | Evidence |
|---|---|---|---|
| E-1 | All inbound data crossing a trust boundary validated, encoded, or allowlisted before use | | |
| E-2 | No data concatenated into any interpreter — structural separation only | | |
| E-3 | No secret value in source, version-controlled config, logs, error output, or fixtures | | |
| E-4 | Every new capability justified by an acceptance criterion | | |
| E-5 | Every third-party dependency has a review note and pinned version | | |
| E-6 | Every dependency's license identified and compatible; copyleft FLAGGED | | |
| E-7 | No PII, credentials or session tokens reach logs or analytics in readable form | | |
| E-8 | Error paths leak no internals to untrusted callers | | |
| E-9 | Auth/authorization/crypto paths touched by this change re-verified end-to-end | | |

**On E-5/E-6:** exactly one third-party dependency exists — ProfileStore, pinned `45c9847`, **Apache-2.0** (verify the header is preserved; Apache-2.0 requires attribution). *A prior audit on this project reviewed the license of a library that was not a dependency at all — confirm what is actually declared before assessing it.*

## 2b. Threat-mitigation verification — is the code actually doing what the model claims?

The threat model asserts these mitigations exist. **Verify each in the code**, not in the document.

| # | Threat → claimed mitigation | Verdict | Evidence |
|---|---|---|---|
| T-1 | Client cannot claim an outcome — no remote accepts a face, value or amount | | |
| T-3 | Roll-rate flooding bounded by server-known tier, not a client assertion | | |
| T-4 | Forge validates as a closed system; a violation mutates nothing | | |
| T-5 | Element ids resolved via allowlist, never used to index a live table directly | | |
| T-7 | Rejections return a generic code; no stack trace, path or internal value crosses the boundary | | |
| T-8 | `InvokeClient` appears nowhere in the codebase | | |
| T-10 | Session locking delegated to ProfileStore; **our** fail-closed layer is correct | | |
| T-11 | No `SetAsync` on profile data | | |
| T-12 | Every profile field has a default; migration chain runs on load | | |
| T-13 | `purchaseIds` eviction is **time-aware**, not count-only; payload ceiling asserted before save | | |
| T-25 | Finiteness checked before any arithmetic or comparison — `NaN` cannot defeat the sum check | | |
| T-26 | No yield between `IsActive()` and the mutation | | |
| T-27 | Masses snapped before summation so residuals cannot compound | | |
| T-28 | Finiteness asserted at **every** numeric boundary, not only inbound ones | | |

## 2c. Adversarial sweep — attack the code

For each, state whether the attack succeeds, and cite the line that stops it (or the absence of one).

| # | Attack | Verdict | Evidence |
|---|---|---|---|
| X-1 | Submit a forge proposal summing correctly but containing `NaN` in one face | | |
| X-2 | Submit `math.huge` / `-math.huge` / `-0` as a face mass | | |
| X-3 | Submit a proposal with the right sum but a face below the floor | | |
| X-4 | Call `EconomyService.credit` with a negative or non-finite amount | | |
| X-5 | Call any remote with extra, missing, or wrong-typed arguments | | |
| X-6 | Exhaust the rate limiter on one player — does it affect another? | | |
| X-7 | Mutate a profile after release | | |
| X-8 | Reach a currency write **without** going through `EconomyService` | | |
| X-9 | Cause `performRoll` to credit without firing, or fire without crediting | | |
| X-10 | Make `RollService.streakMultiplier` return non-finite or unbounded | | |

## 2d. TM — what is missing entirely?

| # | Question | Verdict | Evidence |
|---|---|---|---|
| TM-1 | **What threat does the implementation have that the threat model does not cover?** You are a different model family than the author. This is the highest-value row in this brief; an empty answer is the least believable outcome | | |
| TM-2 | Any mitigation the document claims but the code does not actually implement | | |
| TM-3 | Any place where a comment asserts a safety property the code does not enforce | | |

## 2e. Finding tags and count
Every finding carries a tag: a Matrix E line, or a `T-n`/`R-n`/`S-n`/`X-n` id. **State the numeric count.** If genuinely zero, write `FINDINGS: 0` — but re-read the L-018 rule at the top first, because a hardening note counts.

## 2f. Gate 4 verdict
Exactly one: `SECURE` or `FLAGGED-TO-GATE-1` + numbered tagged finding list, plus the numeric count.
**Exit artifact, this exact path:** `deliveries/evidence/2026-08-06-blocks12-gate4-security.md`

---

## RETURN
Both artifacts at the exact paths above, every table fully populated, both verdict strings, and both numeric finding counts. Modify no file other than those two artifacts. A step you could not perform is reported as not performed — never as a pass.
