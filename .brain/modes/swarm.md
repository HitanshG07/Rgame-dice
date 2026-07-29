# .brain/modes/swarm.md - PARALLEL SWARM EXECUTION PROTOCOL ("ultracode")

*MODE CONTRACT: living document; Gate 6 may refine it under double veto, but the disjointness proof, the per-pair circuit breaker, and the operator-authorization requirement may never be weakened.*

## ENTRY CRITERIA
Activated only when ALL three hold: (1) the task decomposes into three or more blocks with PROVABLY DISJOINT file sets — each block's complete file list is written down before fan-out and no file appears in two lists; (2) the host tool supports genuinely isolated sub-agents or git worktrees; (3) the operator explicitly authorizes the swarm run ("ultracode", "swarm this", or equivalent). If any condition fails, the task runs the standard serialized pipeline per Global Law 4. Trigger language alone never suffices — the disjointness proof is the gate.

## THE PRIME LAW
Parallelism multiplies speed; it never dilutes law. Every block walks the same gates, personas, honesty rules, and artifacts as serial work. The Orchestrator coordinates — it never constructs and never audits. Coordination and production stay separated, exactly as authorship and approval do.

## MANDATORY SEQUENCE
1. **Decomposition proof (Orchestrator = Product Manager persona):** split the approved plan into blocks; write each block's complete file set; verify pairwise disjointness. Any overlap merges those blocks or serializes them. The proof is recorded in the plan artifact.
2. **Fan-out with context slicing:** spawn one Worker and one Verifier per block in isolated fresh contexts (host sub-agents; git worktrees where supported). Each pair receives ONLY its plan-slice, its block's files, the Boot Digest, and the ledger entries matching its block — never the whole repository. Context slicing is law, not an optimization.
3. **Sizing justification:** the Orchestrator records why N pairs are needed (default ceiling: 6; one pair for anything small — a swarm of one is just the normal pipeline). Where the host supports model tiers, mechanical blocks route to cheaper models; architectural blocks keep full reasoning capacity.
4. **Execution ring (per pair):** the Worker constructs under Gate 1 discipline; the Verifier runs mechanical validation and the cognitive audit under Gate 2–3 discipline, owing Matrix C/D evidence per block — rubber-stamping is a protocol violation. Rejections rework inside the pair. The Rewind Circuit Breaker (root bootloader Section 2.4) caps each pair at three rejection cycles, then escalates to the Orchestrator, which may re-slice, reassign, or halt to the operator.
5. **Fan-in (Orchestrator):** re-verify disjointness against the files actually touched; integrate; run the full test suite AND the Runtime Smoke Command on the integrated result; then walk a single consolidated Gate 4 (Security) and Gate 5 (Delivery). Merge conflicts are Orchestrator-owned; Workers never resolve them.
6. **Recording:** one scoreboard line per block plus one integration line, all tier-stamped and marked `lane: swarm`; Gate 6 runs once, on the integrated whole.

## EXIT ARTIFACT
The Swarm Report inside the delivery summary: the decomposition proof, pairs spawned with sizing justification, per-block verdicts and rejection counts, integration test and smoke evidence, and any circuit-breaker escalations. A swarm run without its report is non-compliant.
