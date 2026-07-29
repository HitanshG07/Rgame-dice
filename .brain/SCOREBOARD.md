# .brain/SCOREBOARD.md - PIPELINE MEASUREMENT LAYER
Evolution must target measured weakness, not novelty. Update this file at every Gate 5 delivery (Matrix F duty) and consult it at every Gate 6 before hunting new patterns (Matrix G duty). Keep entries as single compact lines; when the run log grows past roughly 50 lines, distill it per the ledger's metabolism law — running tallies survive distillation, individual run lines are compressed.

## RUN LOG (one line per pipeline run)
Format: `[YYYY-MM-DD] task-slug | tier | lane: full/fast/swarm | rejections: (gate:count or none) | defect classes | final verdict`
Runs marked `(drill)` are compliance drills — recorded in the log but EXCLUDED from RUNNING TALLIES by design (see `.brain/DRILL.md`); the tallies count engineering runs only.
Rejections are appended to the active task's line AT REJECTION TIME (circuit-breaker persistence, root bootloader Section 2.4), never held back for Gate 5.
- [2026-07-30] 2d-bouncy-ball-tycoon-v1 | PRODUCTION | lane: swarm | rejections: none | none | DELIVERED
- [2026-07-30] 2d-bouncy-ball-tycoon-production-suite | PRODUCTION | lane: swarm | rejections: none | none | DELIVERED


## RUNNING TALLIES
- Total pipeline runs: 2
- Rejections by gate: G2: 0 | G3: 0 | G4: 0 | G5: 0 | G6 vetoes: 0
- Most recurrent defect classes: none yet
- Weakest gate (most rejections over the trailing 10 runs): none yet
- Fast-lane share of runs: 0% (watch this: a rising share with rising G2-G4 rejections means triviality is being misclassified)

## EVOLUTION TARGETING RULE
At Gate 6, before pursuing novelty-driven mutations, read the RUNNING TALLIES. If a skill rule, checklist extension, or ledger promotion could reduce the most recurrent defect class or strengthen the weakest gate, that mutation takes priority. An evolution cycle that ignores a measured weakness in favor of a shiny new pattern must record why in the Evolution Report.
