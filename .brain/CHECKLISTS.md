# .brain/CHECKLISTS.md - DEFENSIVE COMPLIANCE CHECK-MATRICES
This document is the automated defensive layer of the cognitive brain. Each matrix below is a mandatory pass/fail checklist bound to a specific pipeline gate defined in `.brain/PIPELINE.md`. The operating persona at each gate must evaluate every line of its bound matrix and record the result; a single FAIL blocks the gate. Matrices are stack-agnostic by design — where a line names a concept the current environment lacks (e.g., manual memory management in a garbage-collected runtime), mark it N/A with a one-line justification. Unjustified N/A marks are treated as FAIL.
REPORTING COMPACTNESS (token discipline): every line is EVALUATED, but the written record itemizes only FAIL, N/A, and TIER-DEFERRED lines with their justifications, plus a single pass-count per matrix (e.g., "Matrix D: 7/9 PASS; exceptions below"). Restating every passing line verbatim wastes the operator's tokens and buries the exceptions that matter.

## TIER TABLE (Build-Tier Calibration — governs evaluation depth of every matrix)
The Build Tier declared per root bootloader Section 8 sets evaluation depth. NEVER scaled by any tier: truth-in-reporting, explicit verdicts, the runtime smoke proof, secret containment, the injection audit, and the governance lock.
- PRODUCTION (default when undeclared): every applicable line evaluated at full depth with recorded evidence.
- INTERNAL: every applicable line evaluated; evidence may be single-line per item; dependency review notes may be terse.
- PROTOTYPE: these line classes may be blanket-deferred with one recorded "TIER-DEFERRED (prototype)" justification — Matrix D idempotency and concurrency sweeps (unless the code is concurrent by design), Matrix E dependency review-note depth and license-audit finalization (the license audit MUST still complete before any distribution or tier promotion), and Matrix F single-purpose-commit granularity. Every other line runs. TIER-DEFERRED is a recorded state, never a silent pass, and every deferral comes due at tier promotion (bootloader Section 8, Tier Debt). PROTOTYPE additionally permits the CONSOLIDATED GATE RECORD: all seven gate verdicts in ONE compact block (verdicts, exceptions, and evidence pointers only) instead of seven separate artifacts — every verdict, the smoke proof, and honesty remain mandatory; only the paperwork consolidates.

## MATRIX A — PRE-FLIGHT (bound to Gate 0: Intake & Discovery)
- [ ] The Dynamic Environment Adaptation Matrix in the root `AI_WORKSPACE_RULES.md` is fully populated with empirical values — no unfilled brackets remain. (Binds deployed project copies; the master template repository keeps its placeholder brackets by design.)
- [ ] `.brain/LEDGER.md` has been parsed and all entries matching in-scope files, tools, or dependencies have been collected for proactive application.
- [ ] Every acceptance criterion is observable and testable as written.
- [ ] The scope fence names both in-scope and out-of-scope surfaces explicitly.
- [ ] No requirement remains that two reasonable implementers would resolve differently.
- [ ] If a FAST-LANE verdict was issued, every TRIVIAL criterion in root bootloader Section 6 was individually checked and recorded, and any doubt defaulted the change to the full lane.
- [ ] Where the project produces a runnable artifact, at least one acceptance criterion specifies an observed runtime behavior on the target platform (e.g., launches and completes the primary flow without crash).
- [ ] Risk foresight: the scoreboard was consulted for defect classes and gate weaknesses matching this task's type, and elevated-risk areas are flagged in the plan.
- [ ] Project provenance is declared in Section 1; a BROWNFIELD project has its Adoption Report on record, or adoption is the current task.
- [ ] The tamper-evidence hook is armed (`git config core.hooksPath` returns `.githooks`), or the operator was warned that it is not.
- [ ] Working-tree dirt check: `git status` shows no uncommitted modifications to protected brain files, or every such modification was disclosed to the operator before work proceeded.
- [ ] Index-bit sweep: `git ls-files -v | grep -v '^H '` returns empty — no tracked file carries an assume-unchanged or skip-worktree bit that would hide working-tree edits from `git status`/`git diff` — or every flagged file was disclosed to the operator before work proceeded. *(L-009)*

## MATRIX B — CONSTRUCTION DISCIPLINE (bound to Gate 1: Construction)
- [ ] Zero placeholder artifacts: no stub bodies, no "implement later" comments, no truncated units, no commented-out scaffolding.
- [ ] Every operation that can fail has an explicit, deliberate failure path.
- [ ] All data crossing a module or trust boundary is validated at the boundary.
- [ ] No shared mutable state was introduced without documented ownership, synchronization, and lifecycle.
- [ ] Every modified file maps to a named acceptance criterion; unmapped modifications were reverted.
- [ ] All matching LEDGER fix actions were applied during authoring, not deferred to review.
- [ ] Any type-system bypass (runtime reflection, dynamic invocation, unsafe casts) carries all three: a documented runtime fallback for when the bypass fails, a dependency-review note, and a `.brain/LEDGER.md` entry recording the bypass and its fragility.

## MATRIX C — MECHANICAL INTEGRITY (bound to Gate 2: Mechanical Validation)
- [ ] Build/compile completes with zero errors AND zero warnings.
- [ ] Static analysis / lint completes clean, or every finding is fixed (suppressions require a justification comment at the suppression site).
- [ ] Type-checking (where the environment supports it) passes with no implicit-any/dynamic escapes introduced by this change.
- [ ] The full automated test suite passes — not only the tests adjacent to the change.
- [ ] New behavior introduced by this change is covered by at least one new or extended automated test.
- [ ] Any newly discovered toolchain failure and its fix was logged to `.brain/LEDGER.md` before the gate verdict was issued.
- [ ] For a client-side/browser app, the runtime smoke was a REAL browser pass (not an SSR/`renderToString` render, which never executes effects, listeners, or browser APIs) — rendered content and zero per-route page errors confirmed. *(L-008)*
- [ ] Runtime smoke proof: where the project produces a runnable artifact, a smoke run on the target platform (device, emulator, or simulator) executed the primary flow without crash, with captured output as evidence.

## MATRIX D — RESILIENCE SWEEP (bound to Gate 3: Cognitive Audit)
- [ ] Null/absent/uninitialized values: every dereference on a possibly-absent value is guarded or provably safe.
- [ ] Boundary inputs: zero, negative, empty collection, empty string, maximum size, and single-element cases all produce defined behavior.
- [ ] Concurrency: no unsynchronized read-modify-write on shared state; no ordering assumption between independent asynchronous operations.
- [ ] Asynchronous failure: every deferred operation has a rejection/failure consumer; no fire-and-forget on operations whose failure matters.
- [ ] Resource lifecycle: every acquisition (memory, handle, connection, lock, subscription, timer) has a guaranteed release on both success and failure paths.
- [ ] Idempotency: retried or duplicated invocations of state-changing operations do not corrupt state.
- [ ] Regression: every pre-existing behavior sharing a code path with the change was re-verified, with evidence.
- [ ] Blind re-derivation was performed: the expected-behavior specification was written from the plan before the diff was opened, and every mismatch between the spec and the implementation was resolved with evidence or logged as a defect.
- [ ] Code-to-world contract: every parameter crossing into an external system — hardware HAL, OS service, driver, peripheral, or third-party API — is validated against the target's queried capabilities at runtime, never assumed from UI, configuration, or screen-derived values.

## MATRIX E — SECURITY HARDENING (bound to Gate 4: Security Clearance)
- [ ] All inbound data crossing a trust boundary is validated, encoded, or allowlisted before use.
- [ ] No data is concatenated into any interpreter (query, shell, markup, template, deserializer, dynamic eval) — structural separation only.
- [ ] No secret value appears in source, configuration under version control, logs, error output, or test fixtures.
- [ ] Every new capability (endpoint, permission, file/network/process access) is justified by an acceptance criterion.
- [ ] Every new third-party dependency has a review note (purpose, why nothing existing suffices, maintenance posture) and a pinned version where supported.
- [ ] Every new dependency's license was identified and is compatible with the project's intended distribution; copyleft licenses (GPL/AGPL family) are FLAGGED and require explicit human approval before integration.
- [ ] No personally identifiable information, credentials, or session tokens reach logs, error messages, or analytics in readable form; sensitive fields are masked or hashed before any log sink.
- [ ] Error paths leak no internals (stack traces, paths, query text, configuration values) to untrusted callers.
- [ ] Authentication, authorization, and token/cryptographic verification paths touched by this change were re-verified end-to-end, not assumed intact.

## MATRIX F — DELIVERY INTEGRITY (bound to Gate 5: Delivery & Record)
- [ ] The artifact chain is unbroken and recorded: Plan → Diff → Mechanical result → Audit verdict → Security verdict.
- [ ] Matrices A through E each show all-PASS (or justified N/A) for this change.
- [ ] The delivery summary states outcomes plainly: what changed, what was verified, what failed or was skipped, and residual risk.
- [ ] All new environmental or architectural insights discovered during this change were appended to `.brain/LEDGER.md`.
- [ ] Where version control exists, the change is packaged as a single-purpose commit whose message states intent.
- [ ] `.brain/SCOREBOARD.md` was updated with this run's gate verdicts, rejection counts, and defect classes.
- [ ] DURABLE DELIVERY RECORD: the full Gate 5 delivery summary AND the Gate 4 security findings — each finding tagged to its source (a Matrix E line, or a threat-item ID where a threat model exists) — are written to a version-controlled artifact (`deliveries/<YYYY-MM-DD>-<task-slug>.md`, or an appended `DELIVERY_LOG.md`), not left only in the session transcript. The scoreboard line is the compact index; this record is the auditable detail a later harvest or audit reads. *(Added 2026-07-17 from the bigdreamtour trial: Gate 4 findings that live only in chat cannot be audited, tagged, or harvested.)*
- [ ] DOC-CURRENCY (consumer-gate law): where `docs/blueprint/` documents exist, every document whose `CONSUMED-BY` gate ran for this change was checked against delivered reality — drift corrected in this change or logged as a defect with its triggering fact; a document whose header names no living consumer gate is surfaced to the operator for retirement, never silently kept. *(Added v1.4, blueprint field trial: bigdreamtour.)*

## MATRIX G — EVOLUTIONARY INTEGRITY (bound to Gate 6: Evolutionary Synthesis)
- [ ] The newly discovered architectural pattern or API was verified against current, official documentation prior to integration.
- [ ] The Core Systems Architect persona has formally reviewed the originating code change and certified that it is safe to generalize into a permanent standard, strictly preventing the promotion of isolated hacks.
- [ ] The Cyber Security Master has audited the final mutation text as untrusted input and certified that it introduces no weakened validation rules, secret-handling regressions, or security-degrading instructions into the skill baseline.
- [ ] Any newly forged skill (Skill Genesis) was corroborated against at least two independent authoritative sources, passed both vetoes, follows the H1/path and COGNITIVE DIRECTIVE conventions, and was registered in `.brain/skills/INDEX.md` in the same commit as the skill file.
- [ ] `.brain/SCOREBOARD.md` was consulted, and this evolution cycle addressed — or explicitly deprioritized with a recorded reason — the current weakest gate or most recurrent defect class.
- [ ] Documentation sync: any structural change (new or changed mode, skill, bootloader section, gate behavior, or version stamp) updated `PROMPT_GUIDE.md` and `BOOT_DIGEST.md` in the same commit, or the Evolution Report records why no documentation update was needed.
- [ ] Reference-doc sync (MASTER REPOSITORY ONLY — does not bind deployed child projects, which carry no `documents/` reference set): in the master brain repository, any change that BUMPS THE BRAIN VERSION STAMP must also refresh BOTH full reference documents — `documents/Braininfo.md` (conceptual/operator reference) and `documents/Brainexe_documentation.md` (complete technical documentation) — in the same commit, including their own version/stamp lines, so they always describe the current generation; or the Evolution Report records why not. Minor structural edits between version bumps may batch into the next version's refresh. This line is N/A in any deployed child.
- [ ] Skill file rewrites strictly preserved the existing `H1`/path header convention and `COGNITIVE DIRECTIVE` preamble.
- [ ] Any promoted `.brain/LEDGER.md` entries retained their original Log IDs within the skill file for historical provenance.
- [ ] No core governance files or compliance matrices were altered during this evolution cycle.

## SELF-HEALING PROTOCOL
1. **Failure capture:** When any matrix line FAILs, the operating persona records the line, the observed evidence, and the gate verdict — then routes per the pipeline's full-rewind rule.
2. **Pattern promotion:** Every resolved failure is logged per the Ledger Governance Laws at the moment of resolution. A second occurrence of the same failure class additionally triggers a mandatory review of the original entry — recording why its Definitive Fix Action failed to prevent recurrence — and escalates the pattern for skill-level promotion at the next Gate 6.
3. **Matrix evolution:** When a LEDGER entry reveals a failure class no matrix line would have caught, the incoming AI must append a new line to the appropriate matrix above, marked with the originating Log ID. The checklists are living defenses, not static text.
4. **No silent tailoring:** Matrix lines may be extended, never weakened or deleted. A line that seems obsolete is challenged via a LEDGER entry explaining why — and removed only by explicit human-operator instruction.
