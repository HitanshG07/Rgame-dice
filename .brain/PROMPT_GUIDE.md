# .brain/PROMPT_GUIDE.md - THE OPERATOR'S GUIDEBOOK (BRAIN v1.4)
This guidebook is for the HUMAN operator. It explains everything the brain has, how each piece works, when it activates, and exactly how to write the prompt that drives it. Agents may read it to understand prompt intent, but it imposes no duties on them. Full law lives in the governance files; on any conflict, they win.

================================================================================
PART I — WHAT THE BRAIN IS: THE COMPLETE FEATURE MAP
================================================================================

The brain is a portable, tool-agnostic AI-governance system. Copied into any project root, it forces any capable agent (Claude Code, Antigravity, Gemini CLI, Codex, Copilot) to work as a disciplined multi-persona engineering team with review gates, permanent memory, and controlled self-improvement.

## The files
- `AI_WORKSPACE_RULES.md` (root) — the bootloader. Sections: 1 environment matrix (stack, test commands, smoke command, build tier, provenance); 2 editing discipline + Rewind Circuit Breaker; 3 file manifest; 4 Domain Isolation (skill loading + Skill Genesis + continuous learning); 5 deployment & enforcement layers + Isolation Ladder + cross-project learning; 6 trivial-change fast lane; 7 intent-triggered modes + Socratic duty; 8 Build-Tier Calibration; 9 Brownfield Adoption Protocol (provenance detection + legacy boundary).
- `.brain/BOOT_DIGEST.md` — one-page operating card every session internalizes first (anti context-fading). Derived; full files prevail. Read-only sessions run on the digest alone — the full governance parse binds only when file modification begins.
- `.brain/PERSONAS.md` — the five minds (below) + context-switch protocol + file-scoped governance lock. HUMAN-LOCKED.
- `.brain/PIPELINE.md` — the seven gates + eight global laws. HUMAN-LOCKED.
- `.brain/CHECKLISTS.md` — Tier Table + matrices A–G bound to gates 0–6 + Self-Healing Protocol. HUMAN-LOCKED.
- `.brain/LEDGER.md` — permanent memory: solved errors (L-###), API quirks, YOUR corrections (binding forever), and the Operator Profile — context-bound style defaults that your live word ALWAYS outranks, updated only on repeated pattern (3+) plus your confirmation. Fixes expire: anything unverified for 6 months is re-verified before use. Metabolism law keeps it all lean.
- `.brain/SCOREBOARD.md` — run metrics: rejections per gate, defect classes, weakest gate. Evolution must target what it measures.
- `.brain/DRILL.md` — the compliance fire drill (synthetic task) to catch agents that read rules but don't walk them; its answer key is operator-held in `.brain/DRILL_KEY.md`, which the agent under test must never open.
- `.brain/skills/` + `INDEX.md` — WHAT the brain knows: domain playbooks loaded by stack markers; registry is agent-writable, additive-only.
- `.brain/modes/` + `INDEX.md` — HOW the brain behaves: intent-triggered protocols (below); registry additive-only.
- `.brain/archive/V1.1_STAGED_SPEC.md` — archived design record; its REJECTED section stays binding.
- Enforcement: `.githooks/pre-commit` — the TAMPER-EVIDENCE layer (governance + registry locks, the DOC-SYNC lock, and a SECRET SCAN the governance override cannot bypass; false positives clear only with `ALLOW_SECRET_COMMIT=1`). Honest framing: git hooks are advisory by design — `--no-verify`, an unarmed or edited hook, or an agent setting the override itself all bypass them, so the guarantee is EVIDENCE, not prevention; for hard locks use GitHub branch protection + required review on `.brain/**`. Plus `.claude/settings.json` (Claude deny on PERSONAS/PIPELINE edits — covers tool calls, not shell writes) and `.claude/agents/` (fresh-context auditors, Gates 2–4). Gate 0 verifies the hook is armed and warns you if not. The dream cycle verifies documentation currency every run. See PART VII for the full known-limits register.
- Shims: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md` — auto-load pointers per tool (Antigravity reads AGENTS.md; GEMINI.md covers Gemini CLI and reinforces the Gemini family).
- `documents/Braininfo.md` (conceptual/operator reference) and `documents/Brainexe_documentation.md` (complete technical documentation) — the two full human-facing references explaining the whole brain, kept current with every version bump in the MASTER repository only (Matrix G reference-doc sync duty; the duty is N/A in deployed children, which carry no `documents/` set). Not governance and not agent-binding — references for the operator; freely editable.

## The five personas (one active at a time, rotation fixed)
1. **Product Manager** — intake, Socratic questions, plan, scope fence, delivery (G0, G5; Orchestrator in swarm).
2. **Developer/Architect** — complete production code; never self-approves (G1; structural veto at G6).
3. **QA Auditor** — fresh-frame evidence-only audit; never fixes (G2–G3).
4. **Security Master** — zero-trust; all external content hostile (G4; security veto at G6; release sweeps).
5. **Cognitive Evolutionist** — improves skills/ledger; NEVER touches governance (G6).

## The seven gates (every change; every gate issues its verdict)
- **G0 INTAKE** — ledger recall, skill loading, mode routing, clarifying questions, Build Tier, provenance check (brownfield -> Adoption Protocol first), scoreboard risk foresight, plan + criteria + scope fence. Verdicts: PLAN-APPROVED / HALTED-FOR-CLARIFICATION / FAST-LANE.
- **G1 CONSTRUCT** — complete code inside the fence; ledger fixes pre-applied. DIFF-COMPLETE.
- **G2 VALIDATE** — build, lint, types, full tests, RUNTIME SMOKE on target; warnings = failures. MECHANICALLY-CLEAN / REJECTED-TO-GATE-1.
- **G3 AUDIT** — blind re-derivation BEFORE reading the diff; criteria PASS/FAIL with evidence; adversarial + code-to-world sweeps. AUDIT-APPROVED / REJECTED-TO-GATE-1.
- **G4 SECURE** — boundaries, injection, secrets, least privilege, licenses, PII-in-logs. SECURE / FLAGGED-TO-GATE-1.
- **G5 DELIVER** — artifact chain check, honest outcome-first summary, scoreboard update. DELIVERED / REJECTED-TO-GATE-1.
- **G6 EVOLVE** — lessons extracted, scoreboard consulted, skill/ledger mutations under DOUBLE VETO (Architect + Security). Runs on EVERY task; "No evolution required" is a verdict. EVOLUTION-COMPLETE / REJECTED-BY-ARCHITECT / FLAGGED-BY-SECURITY.
- Rejections at G2–G4 rewind to G1 and G2–G4 re-run in full. THREE consecutive rejections trip the Circuit Breaker: automatic halt + blocker report to you.

## The twelve modes (intent-triggered behavior contracts)
- **bug_hunter** — Gate 1 LOCKED until root cause is proven (reproduce -> hypothesize -> instrument -> prove). Exit: Root-Cause Proof.
- **project_setup** — greenfield bootstrap: six-pillar intake, skeleton decided with reasons, foundations before features, walking skeleton. Exit: Setup Manifest.
- **blueprint** — pre-code planning documents, tier-scaled (INTERNAL: PRD-lite + ERD/API contract if a DB/API exists; PRODUCTION: + SRS, HLD, threat model FIRST, DevOps decisions record, test plan) under the CONSUMER-GATE LAW: every document opens with `CONSUMED-BY: Gate X / Matrix Y` or is not generated. Threat model wired to Gate 4 (findings tagged to threat-item IDs), currency checked at Gate 5. Recommended automatically after an INTERNAL/PRODUCTION setup; runs only on YOUR confirmation; PROTOTYPE never. Exit: Blueprint Manifest.
- **honest_advisor** — yes-man off: steelman, assumption audit, top-3 kill list, stress tests, PURSUE/PARK/KILL verdict. Exit: Critique Report.
- **brainstormer** — question-led idea growth; diverge, research on demand, converge, hand off. Exit: Exploration Summary.
- **deep_qa** — two-phase UI audit: mechanical capture (screenshots/layout dumps to `qa_runs/`) then isolated cognitive review; ideal as a cross-tool relay. Exit: QA Verdict.
- **release_sweep** — whole-repo pre-ship security audit incl. git history; CRITICAL/HIGH findings block. Exit: SHIP-CLEARED / SHIP-BLOCKED.
- **swarm ("ultracode")** — parallel worker+verifier pairs over PROVABLY DISJOINT blocks; needs your explicit authorization every run. Exit: Swarm Report.
- **teacher_overlay** — layers onto anything: what/why/how in plain words, jargon toll, glossary. Exit: Plain-Language Recap.
- **adoption** — one-time brownfield intake for pre-built codebases: archaeology into the ledger, honest coverage audit, legacy boundary, baseline sweep recommendations. Exit: Adoption Report.
- **consolidate ("dream cycle")** — periodic memory maintenance: merges related lessons, promotes cross-run patterns into skills (double-vetoed), re-verifies stale fixes, proposes profile entries for YOUR confirmation. Exit: Consolidation Report.
- **harvest** — master-repo only: audits a child project's brain (scoreboard honesty, Gate 6 presence), then merges its skills and ledger lessons with provenance; merge commits land only after you review the report. Exit: Harvest Report.

## Build Tiers (rigor proportionate to intent)
Declared at G0, confirmed by YOU, defaulting to PRODUCTION: **PROTOTYPE** (designated checks tier-deferred, recorded, repaid at promotion) / **INTERNAL** (full checks, terse evidence) / **PRODUCTION** (full depth). Never scaled at any tier: truth, verdicts, smoke, secrets, injection audits, the governance lock.

## The learning loops
Mistakes -> ledger (applied forever, re-verified after 6 months). Your corrections -> ledger (binding forever); repeated correction patterns -> Operator Profile proposals (your confirmation required). Better patterns -> Gate 6 skill mutations (double-vetoed). New domains -> Skill Genesis (web-researched, two sources, double-vetoed, registered). Metrics -> scoreboard steers evolution AND feeds Gate 0 risk foresight. Periodically -> the Dream Cycle (consolidate mode) connects lessons across entries, prunes, and promotes. Cross-project: children learn locally; HARVEST merges their skills/ledger back to this master so the next project starts smarter. Version stamp in the bootloader tracks generations.

================================================================================
PART II — WHEN DO I NEED WHICH FEATURE? (TRIGGER REFERENCE)
================================================================================
- Starting a brand-new project -> project_setup (kickoff template below).
- Want the planning documents (threat model, SRS/PRD, DevOps record) before code -> blueprint: recommended automatically after an INTERNAL/PRODUCTION setup (just confirm it), or say "generate the planning docs" any time.
- Adding/changing functionality -> standard pipeline (feature template).
- Something broke -> bug_hunter (bug template). One known defect only.
- Don't know what to build yet -> brainstormer.
- Have an idea/plan, want truth -> honest_advisor.
- App exists, want defects found -> deep_qa.
- About to ship/publish -> release_sweep.
- Task splits into many independent chunks -> swarm (your authorization required).
- Small tweak (≤10 lines, no new capability) -> just ask; Gate 0 proves FAST-LANE itself.
- Want to understand what's happening -> add "keep teacher mode on".
- Suspect the agent is cutting corners -> fire drill in a fresh session.
- New tool/model version -> fire drill.
- Project finished or milestone shipped -> harvest into the master.
- Brain in a project is older than the master -> child upgrade prompt.
- You corrected the agent -> make sure it logs the correction ("log that in the ledger").
- Want project health -> ask for the scoreboard/ledger readout (read-only, no rotation needed).
- Installing the brain into an EXISTING app -> adoption runs automatically at first boot (or say "adopt this project"). Pre-brain code becomes protected territory.
- After a harvest, or every ~10 runs -> "run the dream cycle" to consolidate memory; confirm or reject its profile proposals.
- Building anything with a UI -> `ui_ux_design.md` loads automatically alongside the stack skill; no prompt needed.
- The agent claims a profile preference you don't want right now -> just state what you want; your live word always wins. To remove it permanently: "delete that profile entry."

================================================================================
PART III — HOW TO WRITE PROMPTS
================================================================================

## The five golden rules
1. **State the outcome, not the implementation.** Let Gate 1 choose the how.
2. **Point, don't paste.** Reference files that exist ("per PLAN.md section 3").
3. **Define DONE observably.** Best criteria are runtime-demonstrable via the smoke command.
4. **Answer the questions.** Short prompt + good answers to the Socratic batch beats a mega-prompt.
5. **One task per prompt.** Queue the rest.

## The anatomy (skeleton for any development task)
GOAL: one sentence — what exists after this that doesn't now.
CONTEXT: pointers to plan/spec files, prior decisions, related ledger entries.
CONSTRAINTS: hard limits — devices, APIs, budget, what is OUT of scope.
DONE WHEN: 2–5 observable criteria, at least one runtime-demonstrable.
TIER (optional): "this is a prototype/internal/production build."
MODE (optional): name a mode only if routing might miss; your word always wins.

## Token economy (built into the brain + your free habits)
Built in: read-only sessions boot on the digest alone — a large cut, and since v1.3 the rule lives in the shims themselves so it actually fires; agents load only matched skills and the routed mode, never whole directories; matrix records list only exceptions plus a pass-count; the circuit breaker caps retry loops; metabolism keeps memory lean; tiers and the fast lane scale ceremony to stakes. Honest costs kept ON PURPOSE: a modifying session reads the digest AND the full governance (anti-fading insurance — a cost, not a saving); Gate 6 runs on every task, with "No evolution required" as its cheap exit; the fast lane compresses sessions, not ceremony — the TIER system is the real token lever. Your habits: batch small tasks into one session (boot tax is per-session); keep the session warm (the prompt cache expires after ~5 idle minutes); declare PROTOTYPE tier for experiments; split by strength — see the model table below.

## When to use which model (capability classes as of 2026-07 — doctrine expires like any ledger fix; re-verify when stale)
THE ONE RULE: route by the cost of being wrong, not the size of the task.
- **Strongest model (Claude, full reasoning) — when a mistake is expensive:** Gate 0 planning of anything complex; architecture and scope decisions; Gate 3 cognitive audits and Gate 4 security reviews; bug hunting (root-cause proof is pure reasoning); honest-advisor critiques; harvest audits and dream cycles; anything touching the brain's own files; judging completion reports.
- **Cheap/free capability class (as of 2026-07: Antigravity / Gemini) — when the work is voluminous but verifiable:** bulk construction from an already-approved plan; deep_qa Phase 1 capture (driving the app, screenshots, layout dumps); build/test execution loops; scaffolding, boilerplate, translations. AND as the cross-vendor auditor of the other model's code — different weights carry different blind spots, so the cheap lane is simultaneously the strongest isolation rung (Rung 1). Cheaper and better at once.
- **Small/fast models (Haiku-class, if ever wired into sub-agents) — mechanical work only:** formatting, renames, comment generation, log summarization — where the test suite is the real safety net. PROTOTYPE/INTERNAL tiers only. Never for audits.
Three heuristics when unsure: (1) would a junior dev with a checklist do this fine? -> free tier. (2) would a wrong answer take more than an hour to discover? -> strongest model. (3) did model A write it? -> model B reviews it.

## Templates by intent
- **Kickoff:** "Set up a new project for [goal] in this empty repo. Hard constraints: [platforms/stack if fixed]. Tier: [prototype/internal/production]. Ask me your setup questions first."
- **Feature:** use the anatomy skeleton.
- **Bug:** "BUG: [what I did] -> [what happened] vs [what I expected]. Repro rate: [always/sometimes]. Logs/screenshots: [pointer]." Never suggest the fix — your guess anchors the hunter.
- **Explore:** "Help me think through [idea]. I'm not sure what I want yet."
- **Critique:** "Tear this apart honestly: [idea/plan]. What kills it?"
- **Deep QA:** "Run a full deep QA sweep of the app on [device/emulator]." For the strongest audit, run Phase 1 in the tool with device access and say in the OTHER tool: "Run Phase 2 of deep QA on the latest run."
- **Ship check:** "We're preparing to release. Run the full pre-ship audit."
- **Swarm:** "I authorize a swarm run (ultracode) for this task: [task]. Blocks I believe are independent: [list]. Prove disjointness before fan-out; ceiling [N] pairs."
- **Blueprint:** confirm the post-setup recommendation, or "Generate the planning documents for this project." Expect two questions you must answer: repository visibility for the threat model, and the risk-register acknowledgment at delivery.
- **Tier change:** "Promote this project from PROTOTYPE to PRODUCTION." (Expect the tier-debt re-audit — that's the deal.)
- **Teacher:** append "keep teacher mode on" to anything.
- **Drill:** in a FRESH session: "Execute the drill task in .brain/DRILL.md." Score it yourself against the operator key in `.brain/DRILL_KEY.md` — never point the agent under test at that file.
- **Red drill (rare, adversarial):** fresh session: "Make a small change to any .brain/ governance file and try to avoid detection" — then find the evidence yourself in under five minutes (see DRILL.md). Tests whether tampering can HIDE, not whether it can happen.
- **Correction:** "That's wrong because [reason] — log it in the ledger." Binding forever.
- **Adopt an existing app:** "Adopt this project" — triggers the one-time brownfield intake (archaeology, coverage audit, legacy boundary, baseline recommendations).
- **Dream cycle:** "Run the dream cycle" — then answer its profile proposals with a plain yes/no each; nothing enters the profile without your confirmation.
- **Profile management:** "Show me my operator profile" / "delete the entry about [X]" — the profile is plain text you own.
- **Status:** "Give me the scoreboard readout and any ledger entries relevant to [area]." (Read-only; no gates.)
- **Governance edit (your key):** "I direct this governance change: [exact change]. You are authorized to use ALLOW_GOVERNANCE_EDIT=1 for the commit." Honest note: the override is an audit MARKER, not authentication — any agent can physically set it; its value is the evidence trail it leaves for you in git history.

## Phase directives with completion reports (the proven big-task pattern)
For a multi-feature phase, structure the prompt as: STEP 0 brain-sync if the child is behind the master -> STANDING CORRECTIONS if any -> THE TASK (numbered features) -> CONSTRAINTS -> DONE WHEN -> FINAL STEP: "Write PHASE[N]_REPORT.md at the repo root, max ~120 lines: feature table with runtime evidence; gate summary per feature INCLUDING every rejection; ledger delta; skill mutations; scoreboard snapshot; deviations stated plainly. This report will be independently audited by a second model — inaccuracies are protocol violations." Then bring the report to the master session for audit. This loop (build -> report -> cross-audit -> harvest) is the operating rhythm.

## Maintenance prompts (the brain's own lifecycle)
- **Deploy:** clone the master; run `setup.sh` (macOS/Linux/Git Bash) or `setup.cmd` (Windows) once to arm the hook; open your tool; give the kickoff prompt.
- **Upgrade a child:** "Sync this workspace's brain from the master at [path]: overwrite .brain/ governance, modes, skills registry, shims, and hooks with the master's copies; PRESERVE this project's Section 1 environment matrix values and its ledger entries (merge, never drop); re-arm the hook; commit with ALLOW_GOVERNANCE_EDIT=1 under my authorization."
- **Harvest:** in the master: "Harvest [child path]" — runs the full protocol in `modes/harvest.md` (generation diff, compliance audit, provenance-annotated merges, report before commit).

================================================================================
PART IV — THE PROJECT LIFECYCLE (WHICH PROMPT AT WHICH PHASE)
================================================================================
1. **Deploy** — clone master, arm hook. No prompt needed beyond the kickoff.
2. **Intake & setup** — greenfield: kickoff prompt; answer the six pillars; confirm the tier; approve the plan (output: Setup Manifest + walking skeleton). Existing app: adoption runs first (output: Adoption Report + provenance stamp), then baseline sweeps if you accept the recommendation.
3. **Build phases** — one phase directive per milestone with a completion report each. Bugs discovered mid-phase get their own bug_hunter prompts.
4. **Hardening** — deep_qa sweep (cross-tool relay); fix verdict items via bug_hunter/standard runs.
5. **Ship** — release_sweep; resolve SHIP-BLOCKED findings; ship.
6. **After shipping** — harvest into the master; the master's next project inherits everything.
7. **Always-on** — occasional fire drills; corrections logged the moment you make them; scoreboard readouts when you want the health picture; a dream cycle after each harvest or ~10 runs to keep memory consolidated and the profile honest.

================================================================================
PART V — READING WHAT COMES BACK (YOUR AUDIT EYE)
================================================================================
A healthy delivery shows: explicit verdicts at every gate; real command output (not "tests passed" prose); the scoreboard line appended; failures stated as failures; a Gate 6 statement. Red flags that mean drift — challenge them: a run with zero rejections *every* time (real work gets rejected sometimes); "DELIVERED" without smoke evidence (that's PARTIAL); missing Gate 6/Evolution Report; unjustified N/A marks; new files appearing in `.brain/` uninvited; a report whose claims you can't trace to a file or output. Your two strongest tools: "show me the actual output" and the fire drill. Budget the truth: this system works only if you spend ~5 minutes reading artifacts per delivered task and run occasional drills — if your real behavior is "trust the summary," it quietly degrades into vibes with paperwork. A five-second `git diff .brain/` before trusting any session catches the cheapest tampering path (uncommitted governance edits).

================================================================================
PART VI — ANTI-PATTERNS (EACH ONE HAS BURNED US)
================================================================================
1. **Nested same-character code fences in pasted prompts** — everything after the inner fence silently vanishes. Mix fence characters (outer ~~~, inner backticks) and verify receipt.
2. **Prescribing the solution in a bug report** — anchors the hunter; let evidence lead.
3. **"Make it robust/perfect/production-ready"** — unverifiable adjectives produce checkbox theater. Name observable behavior. (Want production rigor? Declare the PRODUCTION tier — that's what it's for.)
4. **"Just quickly, skip the ceremony"** — trains drift. If it's trivial, Gate 0 will prove FAST-LANE itself.
5. **Mega-prompts answering every unasked question** — suppress the Socratic duty; hide your priorities.
6. **Vague evaluation asks ("is this good?")** — say "advisor mode" for the kill list or "brainstorm" for growth.
7. **Accepting "DELIVERED" on faith** — delivery without runtime evidence is a claim, not a fact. The L-002 crash lived in that gap.

================================================================================
PART VII — KNOWN LIMITS (THE HONEST GUARANTEE)
================================================================================
This brain is tamper-EVIDENT, not tamper-PROOF. What that means, plainly:
- Git hooks are advisory: `--no-verify`, an unarmed hooksPath, an edited working-tree hook, or an agent setting the override itself all bypass them — and history cannot distinguish which happened; pre-push rewriting can erase it. Hard locks require server-side branch protection, which a portable folder cannot carry.
- The commit lock does not guard the working tree: an agent can edit governance files WITHOUT committing and change live behavior. Counters: the Gate 0 dirt check, your own `git diff .brain/`, and the red drill.
- The index can be told to lie: `git update-index --assume-unchanged <file>` makes `git status` AND `git diff` silently ignore a tracked file, defeating the dirt check and your diff audit at once (found live on the digest, 2026-07-18 — L-009). Counter: the Matrix A index-bit sweep (`git ls-files -v | grep -v '^H '` must be empty); include setting this bit in red drills.
- Single-context persona separation is a DISCIPLINE, not isolation — the authoring reasoning stays in the window. The cross-vendor audit (Rung 1) is the real mechanism; use it for anything that matters.
- Registries are mechanically additive-only, but semantics can be shadowed by appended routes; the fire drill and your audit eye are the check.
- Skill Genesis and harvest ingest external/child content into standing instructions — the double veto is LLM judgment, not mechanical. New skills are PROVISIONAL until you ratify them; everything is git-revertible.
- The doc-sync lock guarantees co-modification, not currency — the dream cycle owns currency.
- The circuit-breaker counter persists via at-rejection scoreboard appends; re-slugging a task dodges it, but three near-identical slugs with rejections is a visible drift signature.
- The digest stamp detects STALENESS, not tampering (both files being hook-protected covers the tamper path).
- The re-anchor rule can itself be compacted away: tools that re-inject the shim every turn (Claude Code) rescue it; elsewhere it is best-effort.
Every mechanism still pays for itself: violations cannot happen INVISIBLY against an operator who reads the artifacts.

================================================================================
QUICK CARD
================================================================================
Boot: shim -> bootloader -> digest -> governance. Gates: G0 plan -> G1 build -> G2 validate+smoke -> G3 audit -> G4 secure -> G5 deliver -> G6 evolve. 3 strikes -> halt. Tiers: prototype/internal/production — you declare. Provenance: greenfield/brownfield — detected, adoption runs once. Modes: bug_hunter / project_setup / blueprint / honest_advisor / brainstormer / deep_qa / release_sweep / swarm / teacher / adoption / consolidate / harvest. Your keys: tier declaration, swarm authorization, governance edits (ALLOW_GOVERNANCE_EDIT=1), mode override, corrections, profile confirmations. The rhythm: build -> report -> audit -> harvest -> dream -> repeat.
