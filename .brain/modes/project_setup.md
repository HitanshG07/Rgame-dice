# .brain/modes/project_setup.md - GREENFIELD BOOTSTRAP PROTOCOL

*MODE CONTRACT: living document; Gate 6 may refine it under double veto, but the decide-before-code ordering may never be weakened.*

## ENTRY CRITERIA
Activated on an empty or near-empty repository with initiation intent. Adding features to an existing project is the standard pipeline, not this mode.

## THE PRIME LAW
Structure is decided before feature code exists. A project that skips its foundations does not fail today — it falls apart in a month, when the shortcuts compound. No feature code may be written while this mode is active.

## MANDATORY SEQUENCE
1. **Interrogate first (Socratic duty — the six-pillar intake):** ask the operator in simple language, one batch, before proposing anything: (1) CORE LOOP — the single must-have action this project exists to perform; (2) LOOK — any visual anchor or reference product for the UI, where a UI applies; (3) PERFORMANCE ENVELOPE — expected speed, data volume, and user count in rough numbers, flagging mismatches (e.g., instant responses over massive datasets) immediately; (4) USERS — who operates it and how technical they are, since that calibrates UI complexity and error handling; (5) INTENT TIER — throwaway prototype, internal tool, or production system, stated explicitly, because it calibrates engineering rigor for the whole project; (6) SCOPE FENCE — which tempting features are explicitly OUT of version 1. Record every answer in the plan artifact; hard constraints (platforms, offline, budget, deadlines) ride along with pillar 3.
2. **Decide the skeleton, with reasons:** language and framework (matched to the operator's stack and the loaded skills), directory layout, module boundaries, and naming conventions — every choice recorded with a one-line why, so future sessions inherit decisions instead of re-arguing them.
3. **Foundations before features:** version control initialized with the brain deployed and the governance hook armed (`git config core.hooksPath .githooks`); a test runner installed with one passing example test executed and shown; linter/formatter configured; the environment matrix in the root bootloader filled with this project's real commands; a secrets pattern established (environment files excluded from version control, an example file committed); a README stating how to run, test, and build.
4. **Walk the skeleton:** build one thin end-to-end slice — however trivial — proving the architecture connects from entry point to output. The slice goes through the standard gates like any change.
5. **Record the constitution:** write the project's conventions summary and log the stack decisions in `.brain/LEDGER.md` (Codebase and Architectural Constraints) so every future session starts oriented.

## EXIT ARTIFACT
The Setup Manifest: the decisions with their reasons, the foundation checklist fully checked, the passing example test's real output, and the walking skeleton demonstrated. Delivered through Gate 5 honestly — anything deferred is listed as deferred, not silently dropped.
