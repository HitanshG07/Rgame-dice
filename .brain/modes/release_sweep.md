# .brain/modes/release_sweep.md - FULL-REPOSITORY PRE-SHIP AUDIT

*MODE CONTRACT: living document; Gate 6 may refine it under double veto, but the whole-repository scope and the blocking-severity rule may never be weakened.*

## ENTRY CRITERIA
Activated by shipping intent: a release, deployment, publication, or "is it safe to ship" request. Distinct from Gate 4, which audits individual changes as they happen — this mode audits the ACCUMULATED STATE of the entire repository, because per-change audits cannot see cross-change interactions, configuration drift, or anything that predates the brain's deployment in the project.

## THE PRIME LAW
The sweep is executed by the Cyber Security Master persona (Persona 4) at the strongest isolation rung available (Isolation Ladder, root bootloader Section 5), read-only, against the whole tree — never just the latest diff.

## MANDATORY SWEEP
1. **Matrix E against the repository:** every trust boundary; every data/interpreter junction; secret containment across all source, configuration, logs, and fixtures — including `git log -p` history for secrets that were committed and later "removed"; dependency audit (pinned versions, known-vulnerable releases checked against current advisories); error-path leakage to untrusted callers.
2. **Production-configuration check:** debug flags, verbose logging, permissive CORS, default credentials, exposed admin or diagnostic surfaces, missing rate limits — everything that was acceptable in development and is a hole in production.
3. **Mechanical full pass:** the complete Verification & Test Command Matrix executed from a clean state; warnings block per Global Pipeline Law 5.
4. **Ledger cross-check:** every logged Definitive Fix Action is still in place; no previously resolved ledger entry has regressed.
5. **Severity-ranked findings:** every finding carries file:line, the concrete attack or failure scenario, and a severity. Any CRITICAL or HIGH finding BLOCKS the release verdict — no "ship now, fix later" unless the human operator explicitly accepts the named risk in writing, which is then recorded in the ledger.

## EXIT ARTIFACT
The Release Verdict: SHIP-CLEARED or SHIP-BLOCKED, with the full findings table, the exact commands executed and their real output, and — when blocked — the shortest path to clearance. The sweep and its outcome are recorded in `.brain/SCOREBOARD.md`.
