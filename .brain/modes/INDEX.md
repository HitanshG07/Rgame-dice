# .brain/modes/INDEX.md - INTENT ROUTING REGISTRY
Modes are intent-triggered operating protocols: where skills define what the brain KNOWS (loaded by stack detection), modes define how the brain BEHAVES for the task at hand (activated by intent detection at Gate 0, per root bootloader Section 7). This registry is agent-writable and additive-only, like the skill registry; modifying or removing existing routes is human-only and mechanically enforced by the pre-commit registry lock.

## ACTIVE MODE ROUTES
Evaluated at Gate 0 against the operator's request. Exactly ONE mode is active per task; `teacher_overlay.md` is the sole exception — an overlay that layers onto any mode or the standard pipeline. If no route matches, the standard pipeline runs unmodified. An explicit operator instruction naming a mode always overrides detection.
- `bug_hunter.md` <- defect language: "bug", "crash", "broken", "stopped working", "regression", or any report that observed behavior differs from expected behavior.
- `project_setup.md` <- an empty or near-empty repository plus initiation language: "start", "new project", "set up", "scaffold", "begin building".
- `honest_advisor.md` <- evaluation requests: "what do you think of", "critique", "review my idea/plan", "should I", "is this viable", "tear this apart".
- `brainstormer.md` <- exploration requests: "help me think", "brainstorm", "ideas for", "explore options", "I'm not sure what I want yet".
- `release_sweep.md` <- shipping language: "ready to ship", "release", "deploy", "audit everything", "pre-launch check", "is it safe to publish".
- `teacher_overlay.md` <- explanation requests at any point: "explain", "teach me", "in simple terms", "why are we doing this", "what does this mean" — or a standing operator instruction to keep the overlay on.
- `deep_qa.md` <- comprehensive testing language: "full QA run", "test the UI", "visual audit", "deep test", "stress-test the app". DISAMBIGUATION with neighbors: one known defect -> `bug_hunter.md`; discovering unknown defects across the running UI -> `deep_qa.md`; security or ship clearance -> `release_sweep.md`. A request spanning two is resolved by asking the operator.
- `swarm.md` <- explicit parallel-execution language: "ultracode", "swarm this", "run these in parallel", or batch work over many independent units (multi-language localization, disjoint module scaffolds). HARD GATE: routing alone never activates it — the mode additionally requires the disjoint-file-set proof and explicit operator authorization per the mode file; absent either, the standard pipeline runs.
- `consolidate.md` <- maintenance language: "consolidate", "run the dream cycle", "maintenance pass" — or an agent recommendation after a harvest or ~10 pipeline runs (the operator confirms; agents never self-start it).
- `adoption.md` <- automatic Gate 0 detection of a pre-built codebase with empty brain memory (root bootloader Section 9), or operator language: "adopt this project", "the brain was just installed here". Runs once per project.
- `harvest.md` <- master-repository language: "harvest [child path]", "pull the lessons from the child", post-project wrap-up. Runs ONLY in the master brain repository, never inside a child; audit precedes every merge.
- `blueprint.md` <- planning-document language: "blueprint", "generate the planning docs", "write the SRS/PRD/threat model" — or the mandatory Gate 0 recommendation at the close of an INTERNAL/PRODUCTION `project_setup.md` intake. Runs only on operator confirmation (agents never self-start it); a declared-PROTOTYPE project never routes here. (Registered at the v1.4 forge, 2026-07-18, from the bigdreamtour field trial.)

## MODE LAWS
1. **Announcement duty:** Gate 0 must announce the detected intent and activated mode ("Task intent: X -> mode Y", or "No mode — standard pipeline") before any plan is drafted. Silent mode activation, or proceeding without classification, is a protocol violation.
2. **One mode at a time;** the teacher overlay is the only layerable exception. Ambiguous intent is resolved by asking the operator, never by guessing.
3. **Modes bend the pipeline shape only as their file specifies;** they never waive honesty, verdicts, matrices, or the governance lock. Any mode whose work requires a file modification routes that modification through the standard gates.
4. **Exit-artifact duty:** every mode run must produce its required exit artifact; a mode run without its artifact is non-compliant and must be re-run.
5. **Additive-only registry:** agents may append new routes (with their mode files, in the same commit); existing routes change only by human direction.
6. **Modes are living documents:** Gate 6 may refine them under the standard double veto, but may never weaken an exit-artifact requirement or an entry lock (e.g., the bug hunter's Gate 1 lock, the advisor's kill-list mandate).
