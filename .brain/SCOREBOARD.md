# .brain/SCOREBOARD.md - PIPELINE MEASUREMENT LAYER
Evolution must target measured weakness, not novelty. Update this file at every Gate 5 delivery (Matrix F duty) and consult it at every Gate 6 before hunting new patterns (Matrix G duty). Keep entries as single compact lines; when the run log grows past roughly 50 lines, distill it per the ledger's metabolism law — running tallies survive distillation, individual run lines are compressed.

## RUN LOG (one line per pipeline run)
Format: `[YYYY-MM-DD] task-slug | tier | lane: full/fast/swarm | rejections: (gate:count or none) | defect classes | final verdict`
Runs marked `(drill)` are compliance drills — recorded in the log but EXCLUDED from RUNNING TALLIES by design (see `.brain/DRILL.md`); the tallies count engineering runs only.
Rejections are appended to the active task's line AT REJECTION TIME (circuit-breaker persistence, root bootloader Section 2.4), never held back for Gate 5.
- [2026-07-30] 2d-bouncy-ball-tycoon-v1 | PRODUCTION | lane: swarm | rejections: none | none | DELIVERED *(record disputed — see L-013: delivered code contradicts its own delivered documents and its test suite could not load; treat this line as unreliable)*
- [2026-07-30] ball-escape-blueprint-regen | PRODUCTION | lane: full | rejections: G3:1 | doc-to-architecture-contradiction, audit-non-compliance | DELIVERED
- [2026-07-30] 2d-bouncy-ball-tycoon-production-suite | PRODUCTION | lane: swarm | rejections: none | none | DELIVERED *(SUPERSEDED — built against the retired tycoon design by a concurrent Antigravity session while the replacement blueprint was in flight; its output targets modules the current SRS does not contain. Operator directed wholesale replacement 2026-07-30. Line retained per truth-in-reporting: the run happened. Excluded from evolution targeting — it measures work that no longer exists.)*


- [2026-08-04] dice-forge-blueprint | PRODUCTION | lane: full | rejections: none | audit-finding-misclassification (G4, corrected at verification) | DELIVERED

- [2026-08-04] dice-forge-block1-backbone | PRODUCTION | lane: full (sequenced) | rejections: G2:2 | invalid-luau-syntax, incorrect-test-assertion | G2 CLEAN (90 assertions, 2/2 suites); G3-G4 PENDING

- [2026-08-06] dice-forge-block2-rollservice | PRODUCTION | lane: full (sequenced) | rejections: none | none | G2 CLEAN (2771 assertions, 4/4 suites, first MCP-verified run); G3-G4 PENDING

## RUNNING TALLIES
- Total pipeline runs: 3 (one superseded, one disputed — see run-log annotations)
- Rejections by gate: G2: 2 | G3: 1 | G4: 0 | G5: 0 | G6 vetoes: 0
- Most recurrent defect classes: **audit-classification failure, 2 occurrences** (2026-07-30 audit-non-compliance; 2026-08-04 findings misrecorded as "no findings"). Both were caught only because the authoring session verified the auditor's factual claims against the repo before accepting the verdict. Enumerated briefs fixed COMPLETENESS (L-014); they have not fixed CLASSIFICATION.
- Weakest gate: **Gates 3-4 (audit reliability)** — not from rejections, but because every cross-vendor audit so far has needed correction at verification. Gate 6 evolution should target this.
- Fast-lane share of runs: 0% (watch this: a rising share with rising G2-G4 rejections means triviality is being misclassified)

## EVOLUTION TARGETING RULE
At Gate 6, before pursuing novelty-driven mutations, read the RUNNING TALLIES. If a skill rule, checklist extension, or ledger promotion could reduce the most recurrent defect class or strengthen the weakest gate, that mutation takes priority. An evolution cycle that ignores a measured weakness in favor of a shiny new pattern must record why in the Evolution Report.
