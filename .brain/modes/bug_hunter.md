# .brain/modes/bug_hunter.md - EVIDENCE-FIRST DEBUGGING PROTOCOL

*MODE CONTRACT: living document; Gate 6 may refine it under double veto, but the Gate 1 lock and the root-cause proof requirement may never be weakened.*

## ENTRY CRITERIA
Activated when the task is a defect report: observed behavior differs from expected behavior. If investigation reveals the report is a feature request in disguise ("it crashes because that feature was never built"), exit to the standard pipeline via Gate 0 re-classification and say so plainly.

## THE PRIME LAW
Gate 1 (Construction) is LOCKED. No source file may be edited and no fix may be drafted until the root cause is PROVEN. Guessing a fix and checking whether the symptom disappears is prohibited — symptom disappearance is not root-cause proof; it is how bugs go dormant and return.

## MANDATORY SEQUENCE
1. **Reproduce:** make the bug happen on demand — a failing test, a script, or an exact manual procedure — and show the actual failing output. If it cannot be reproduced, report "cannot reproduce" with everything that was tried and ask the operator for more signal; never proceed on an unreproduced bug.
2. **Scope the blast radius:** establish what works, what fails, since when (git history is evidence — bisect when useful), and under which inputs, platforms, or conditions.
3. **Hypothesize:** list the plausible root causes ranked by likelihood, each paired with the specific evidence that would confirm or eliminate it.
4. **Instrument and eliminate:** gather evidence — trace code paths, add temporary instrumentation, isolate variables — until exactly one hypothesis survives with positive proof of the mechanism, not an inference from absence. All temporary instrumentation is removed before delivery.
5. **Prove:** present the Root-Cause Proof: the mechanism, the evidence chain, and why it explains every observed symptom. This artifact — and only this artifact — unlocks Gate 1.
6. **Fix through the standard pipeline:** the fix walks Gates 1–6 normally. The reproduction from step 1 becomes a permanent regression test that must pass at Gate 2, and the root cause plus its definitive fix are logged in `.brain/LEDGER.md`.

## EXIT ARTIFACT
The Root-Cause Proof: reproduction procedure, surviving hypothesis, evidence chain, and the elimination reasoning for the alternatives. No proof, no fix.
