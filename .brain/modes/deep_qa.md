# .brain/modes/deep_qa.md - TWO-PHASE DEEP UI/UX QA PROTOCOL

*MODE CONTRACT: living document; Gate 6 may refine it under double veto, but the two-phase isolation (mechanical capture vs. cognitive review) and the run-tracking ontology may never be weakened.*

## ENTRY CRITERIA
Activated by operator requests for a comprehensive QA sweep, visual audit, interaction testing, or defect discovery across the entire running UI. DISAMBIGUATION with neighboring modes: one known defect is `bug_hunter.md`; security and ship clearance is `release_sweep.md`; this mode DISCOVERS unknown defects in the running artifact. A request spanning two modes is resolved by asking the operator.
Write discipline: this mode modifies NO product source files. It writes exclusively inside its own run directory (`qa_runs/` at the project root) — no fixes, no refactors, no "while I'm here" edits. Its sole output is evidence and a verdict.

## THE PRIME LAW
Two-Phase Isolation. Phase 1 (Mechanical Execution) acts as a blind automaton: it navigates, clicks, types, dumps layout trees, takes screenshots, and logs everything — it NEVER analyzes. Phase 2 (Cognitive Review) acts as the Senior QA Analyst in an isolated frame: it reads the Phase 1 evidence, cross-references confirmed failures with the source code, and writes the verdict — it NEVER drives the app.
Phase 2 must run at the strongest Isolation Ladder rung available (root bootloader Section 5). A cross-vendor relay — one tool captures, a different model family reviews — is Rung 1 and the ideal execution of this mode.
Re-check valve: when Phase 2 doubts a Phase 1 observation (ambiguous screenshot, incomplete log line), it may REQUEST a bounded, targeted re-capture, which executes as a Phase 1 action. The two roles never blend within a single context.

## THE RUN ONTOLOGY (STRICT STRUCTURE)
All output routes to `qa_runs/` at the PROJECT ROOT — never inside `.brain/`, which holds the brain's mind, not test output. Binary artifacts are excluded from version control via `.gitignore`; only the verdict, the logs, and the tracker are commit-worthy.
Before touching the application:
1. Check `qa_runs/run-tracker.json`. If missing, create it: `{ "last_run": 0, "runs": [] }`.
2. Increment `last_run` and create the zero-padded directory `qa_runs/run-XX/`.
3. Scaffold the exact sub-structure:
   - `screenshots/` (format: `<seq>_<screen>_<action>.png`) — gitignored
   - `logs/layout-dumps/` (UI tree JSONs) — gitignored
   - `logs/interaction-log.md` (clickstream) — committed
   - `logs/console-log.md` (terminal and runtime output) — committed
4. Register the run in `run-tracker.json` with a `status` field for cross-tool handoff: `phase1_in_progress` -> `phase1_complete` -> `phase2_in_progress` -> `verdict_delivered`. Any agent, in any tool, resumes from the tracker's recorded state — never by inferring state from which files happen to exist.

## MANDATORY SEQUENCE: PHASE 1 (MECHANICAL CAPTURE)
1. **Toolchain resolution:** identify the stack's interaction tooling (e.g., ADB/UIAutomator for Android, Playwright/Puppeteer for web, XCUITest for iOS) for driving the UI and capturing raw trees and screenshots.
2. **Constraint mapping:** read `.brain/LEDGER.md` and the project plan to identify physical limitations (e.g., "emulator cannot exercise Bluetooth mesh"). Log each as `[UNTESTABLE]` (⛔) in the run summary so coverage gaps are declared, never disguised as passes or failures.
3. **The navigation loop — for EVERY reachable screen:**
   - *Capture default:* screenshot the idle screen and dump the UI layout tree to JSON.
   - *Element discovery:* parse the layout tree for every interactive element (clickable, focusable, scrollable).
   - *Interact and diff:* execute the interaction (tap, type, swipe), capture the new screenshot, and dump the post-action layout diff.
   - *Log:* record the exact action, coordinates or selectors, expected state, and observed state in `interaction-log.md`, tagging every outcome with paired grep-safe tokens: `[PASS]` (✅), `[FAIL]` (❌), `[CRASH]` (💥), `[NO-RESPONSE]` (🔇).
4. **Edge cases:** scroll fatigue (swipe to the true bottom of every scrollable), rapid repeated taps on primary CTAs, and permission prompts exercised down BOTH paths (accept and deny).
5. **Close Phase 1:** set tracker status to `phase1_complete`. Phase 1 draws no conclusions — an automaton does not have opinions.

## MANDATORY SEQUENCE: PHASE 2 (ISOLATED COGNITIVE REVIEW)
1. **Reconciliation:** the QA Auditor persona reads `interaction-log.md` and verifies every `[FAIL]`, `[CRASH]`, and `[NO-RESPONSE]` against the corresponding screenshots and layout dumps — viewing the actual images, not trusting the log's word. Doubtful observations go through the re-check valve, never into the verdict unverified.
2. **Source mapping:** every confirmed defect is traced to the exact file, class, and line in the workspace source (e.g., "null dereference behind the tapped element — `home_screen.dart:142`"). A defect that cannot be source-mapped is reported with its best-known boundary and marked for `bug_hunter.md`.
3. **Severity ranking** (paired grep-safe tokens):
   - `[CRITICAL]` (🔴) — crashes, data loss, security exposure.
   - `[HIGH]` (🟠) — broken primary features, navigation dead-ends.
   - `[MEDIUM]` (🟡) — visual clipping, state inconsistencies.
   - `[LOW]` (🟢) — cosmetic issues, spacing, polish.

## EXIT ARTIFACT & HANDOFF
The Final QA Verdict at `qa_runs/run-XX/qa_verdict.md`: executive summary, screen-by-screen analysis, the severity-ranked defect list cross-referenced to screenshot numbers and source `file:line` anchors, and the `[UNTESTABLE]` declarations. Close by setting tracker status to `verdict_delivered`.
Handoff duties — the verdict feeds the pipeline, it never dead-ends:
1. Confirmed defect classes and counts are recorded in `.brain/SCOREBOARD.md`.
2. This mode fixes nothing: each confirmed defect enters the pipeline as a new Gate 0 task — `bug_hunter.md` for non-obvious root causes, the standard or fast lane for straightforward cosmetic fixes.
3. Defect classes recurring across runs trigger the Self-Healing Protocol: a checklist extension or skill mutation at the next Gate 6.
