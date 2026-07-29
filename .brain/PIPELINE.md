# .brain/PIPELINE.md - PRODUCTION ASSEMBLY PIPELINE & QUALITY GATE DIRECTIVE
Every modification to this workspace — feature, fix, refactor, configuration change, or documentation with behavioral impact — must pass through the gated pipeline defined below, in order, without gate-skipping. Each gate has entry conditions, mandatory operations, and a binary exit verdict. A change that has not cleared every gate is a draft, and drafts are never presented as finished work. The personas referenced here are defined in `.brain/PERSONAS.md`; the environment commands referenced here are recorded in the root `AI_WORKSPACE_RULES.md` Verification & Test Command Matrix.

```text
[ GATE 0: INTAKE ] ──> [ GATE 1: CONSTRUCT ] ──> [ GATE 2: VALIDATE ] ──> [ GATE 3: AUDIT ] ──> [ GATE 4: SECURE ] ──> [ GATE 5: DELIVER ] ──> [ GATE 6: EVOLVE ]
```

## GATE 0 — INTAKE & DISCOVERY
**Operator:** Product Manager & Workspace Director persona.
**Entry condition:** A user request or system-detected defect exists.
**Mandatory operations:**
1. Run a workspace discovery pass if the root rules' Dynamic Environment Adaptation Matrix contains unfilled placeholders, and fill them with empirical values before anything else.
2. Decompose the request into verifiable outcomes; declare the scope fence and the impact surface map.
3. Emit the implementation plan artifact: files to modify, acceptance criteria, out-of-scope declarations.
**Exit verdict:** PLAN-APPROVED, or HALTED-FOR-CLARIFICATION (ambiguity found — control returns to the human operator; the pipeline does not guess).

## GATE 1 — CONSTRUCTION
**Operator:** Core Systems Developer & Architect persona.
**Entry condition:** A PLAN-APPROVED artifact exists for this change.
**Mandatory operations:**
1. Author the change strictly within the scope fence, conforming to the recorded environment profile.
2. Produce structurally complete code only: no stubs, no placeholder comments, no truncated units, no dead scaffolding.
3. Record, alongside the diff, which acceptance criterion each modified file serves. A modified file serving no criterion is scope creep and must be reverted.
**Exit verdict:** DIFF-COMPLETE. The authoring context hands off and is barred from operating Gates 2–4 for this change, per Global Law 3.

## GATE 2 — MECHANICAL VALIDATION
**Operator:** The Isolated Fresh-Context QA Auditor persona (never the Gate 1 author).
**Entry condition:** DIFF-COMPLETE artifact exists.
**Mandatory operations:**
1. Execute the full Verification & Test Command Matrix from the root rules: compile/build, static analysis or lint, type-check where the environment supports it, and the automated test suite.
2. Treat warnings as failures. A warning is an undiagnosed defect with good manners.
**Exit verdict:** MECHANICALLY-CLEAN, or REJECTED-TO-GATE-1 with the verbatim tool output attached. Rejected changes are rolled back or reworked — never argued with.

## GATE 3 — COGNITIVE AUDIT
**Operator:** Isolated Fresh-Context QA Auditor persona.
**Entry condition:** MECHANICALLY-CLEAN verdict exists.
**Mandatory operations:**
1. Fresh-frame review of the diff against the plan artifact: every acceptance criterion marked PASS with evidence, or FAIL.
2. Adversarial input sweep (empty, maximal, malformed, duplicate, out-of-order, concurrent, interrupted).
3. Regression surface confirmation for all shared code paths.
4. Resource lifecycle trace on every acquisition, including failure-path release.
**Exit verdict:** AUDIT-APPROVED, or REJECTED-TO-GATE-1 with a numbered defect list. The Auditor never repairs defects; repair is Gate 1 work.

## GATE 4 — SECURITY CLEARANCE
**Operator:** Cyber Security Master persona.
**Entry condition:** AUDIT-APPROVED verdict exists.
**Mandatory operations:**
1. Trust-boundary census and injection audit on all data/interpreter junctions.
2. Secret containment sweep across source, configuration, logs, and fixtures.
3. Least-privilege review of every new capability; dependency review note for every new third-party component.
4. Failure-mode leakage inspection on all error paths.
**Exit verdict:** SECURE, or FLAGGED-TO-GATE-1 with a numbered finding list.

## GATE 5 — DELIVERY & RECORD
**Operator:** Product Manager & Workspace Director persona.
**Entry condition:** SECURE verdict exists.
**Mandatory operations:**
1. Confirm the artifact chain is unbroken: Plan → Diff → Mechanical result → Audit verdict → Security verdict.
2. Present the change to the human operator with an outcome-first summary: what changed, what was verified, and any residual risk stated plainly. Failed or skipped steps are reported as failed or skipped — never smoothed over.
3. Where the workspace uses version control, package the change as a coherent, single-purpose commit whose message states intent, not mechanics.
**Exit verdict:** DELIVERED, or REJECTED-TO-GATE-1 (broken artifact chain or Matrix F failure; the change re-enters construction and Gates 2–4 re-run in full before delivery is re-attempted).

## GATE 6 — EVOLUTIONARY SYNTHESIS
**Operator:** The Cognitive Evolutionist (Drafting), The Core Systems Architect (Structural Audit), AND The Cyber Security Master (Security Sign-off).
**Entry condition:** DELIVERED verdict exists from Gate 5.
**Mandatory operations:**
1. **Knowledge Extraction:** Analyze the delivered code. Did you utilize a new library, discover an undocumented API quirk, or implement a more efficient architectural pattern than what is currently documented in `.brain/skills/`?
2. **Autonomous Research:** If a new approach was used, utilize your web search tools or documentation access to verify if it represents a modern best practice.
3. **Generalization Peer-Review:** Before writing to disk, the Evolutionist must pass the proposed skill mutation to the Core Systems Architect persona. The Architect must verify that the originating code change is structurally sound and safe to generalize into a universal baseline, rejecting one-off hacks or localized workarounds.
4. **Mutation Security Sign-off:** The Cyber Security Master must audit the approved mutation text itself before any disk write, treating researched external content as untrusted input. The sign-off verifies the mutation introduces no weakened validation rules, no secret-handling regressions, and no instructions that would degrade the security posture of future code generation.
5. **Skill Mutation:** Autonomously rewrite the relevant `.brain/skills/` markdown file to permanently incorporate this new baseline standard.
6. **Ledger Promotion:** If a specific workaround from `.brain/LEDGER.md` was applied successfully, promote it to a permanent architectural rule in the corresponding skill file and archive the ledger entry (archiving means amending the entry in place with a dated PROMOTED-TO-SKILL note naming the target file — never deleting it, per Ledger Governance Law 1).
7. **Report Generation:** Emit the `Evolution Report` artifact detailing what was researched, what skill rules were mutated, and what ledger entries were promoted (or state "No evolution required" if the baseline held).
**Exit verdict:** EVOLUTION-COMPLETE, or REJECTED-BY-ARCHITECT / FLAGGED-BY-SECURITY (mutation vetoed; pipeline terminates without skill update; core delivery from Gate 5 remains intact).

## GLOBAL PIPELINE LAWS
1. **No gate-skipping:** Gates execute in ascending order. "Trivial" changes ride the same rails; triviality is a judgment the pipeline exists to verify, not assume.
2. **Full-rewind rule:** Any rejection at Gates 2–4 returns the change to Gate 1, and Gates 2–4 re-run in full on the reworked diff. Partial re-validation of "just the fixed part" is prohibited — fixes create new regression surface. A rejection at Gate 6 aborts the evolution draft only and does not rewind the finalized Gate 5 feature delivery.
3. **Author/approver separation:** The context that authored a diff may never operate Gates 2, 3, or 4 for that diff. Where only a single context thread exists, it must perform an explicit persona context-switch per `.brain/PERSONAS.md` and discard authoring-time assumptions before auditing.
4. **Parallelization boundary:** Independent changes may traverse the pipeline concurrently in separate contexts or sub-agents. Changes touching overlapping files or shared interfaces are dependent and must be serialized in plan order.
5. **Warning-equals-failure:** At every gate, a tool warning, deprecation notice, or non-fatal diagnostic is treated as a gate failure until explicitly triaged and either fixed or documented as accepted with justification in the delivery summary.
6. **Halt-over-improvise:** When any gate cannot complete its mandate — missing tooling, unfillable environment matrix, contradictory requirements — the pipeline halts with a written blocker statement. Improvised workarounds that bypass a gate's purpose are protocol violations.
7. **Truth-in-reporting:** Verdicts are recorded as produced. Re-labeling a REJECTED verdict, summarizing failures as successes, or omitting a gate from the delivery record voids the change's audit trail.
8. **Meta-write exemption:** The pipeline's own bookkeeping writes are system operations, not workspace changes, and do not themselves traverse the gates: the Gate 0 environment-matrix fill in the root bootloader, ledger appends performed at any gate, Gate 6 skill mutations and ledger promotions, and additive matrix extensions performed under the Self-Healing Protocol. These writes remain bound by their own controls (Matrix G, the Ledger Governance Laws, and the file-scoped governance lock in `.brain/PERSONAS.md`) — the exemption removes recursion, not review.
