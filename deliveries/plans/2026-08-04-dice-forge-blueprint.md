# GATE 0 PLAN ARTIFACT — dice-forge-blueprint
**Date:** 2026-08-04 · **Tier:** PRODUCTION (operator-confirmed) · **Mode:** `blueprint.md` · **Provenance:** GREENFIELD · **Lane:** full

## REQUEST, DECOMPOSED
Generate the PRODUCTION-tier planning document set for Dice Forge Incremental, so construction has a contract to build against. No game code this run.

## MATRIX A PRE-FLIGHT — 9/12 PASS, 3 disclosed
- **A.11 FAIL→DISCLOSED:** protected brain files carry uncommitted modifications (`LEDGER.md`, `SCOREBOARD.md`, `skills/INDEX.md`, `AI_WORKSPACE_RULES.md`, plus untracked `skills/roblox_luau.md`). All are this session's own governance writes. Disclosed to the operator before work proceeded, per the honesty clause.
- **A.7 N/A:** no runnable artifact is produced by a document-only change, so no runtime acceptance criterion applies. The smoke duty is deferred to construction, never waived.
- **A.8 ELEVATED RISK:** the scoreboard's only two recorded defect classes — `doc-to-architecture-contradiction` and `audit-non-compliance` — both originate from the previous blueprint run, i.e. this exact task type. Mitigations carried into this run: the design was validated numerically before any document was written (L-016), and the Gate 3/4 brief will ENUMERATE every matrix line inline rather than referencing it (L-014).
- Hook armed (`.githooks`) PASS · index-bit sweep empty PASS · provenance GREENFIELD confirmed (0 source files) PASS.

## LEDGER RECALL — entries applied to this run
`L-014` enumerate audit checklists inline · `L-015` never specify per-entity behaviour against an aggregate model · `L-016` couple, don't curve-shape · `L-017` distinguish modelling error from design finding · `L-007` client bundles are public (Roblox client scripts are readable) · `L-008` real-runtime smoke is mandatory · `L-013` a clean scoreboard over unexecuted work is worthless · 2026-07-17 no manufactured urgency · 2026-07-17 Antigravity needs enumerated instructions.

## FILES TO CREATE
| File | CONSUMED-BY | Serves |
|---|---|---|
| `docs/blueprint/THREAT_MODEL.md` | Gate 4 / Matrix E | AC-1, AC-6 |
| `docs/blueprint/SRS.md` | Gate 0 / Matrix A | AC-2, AC-4 |
| `docs/blueprint/HLD.md` | Gate 0 / Matrix A | AC-3, AC-4 |
| `docs/blueprint/API_DATA_CONTRACT.md` | Gate 3 / Matrix D | AC-5 |
| `docs/blueprint/TEST_PLAN.md` | Gate 2 / Matrix C | AC-7 |
| `docs/blueprint/DEVOPS_RECORD.md` | Gate 1 / Matrix B | AC-8 |
| `deliveries/audit-briefs/2026-08-04-dice-forge-audit.md` | Gates 3–4 | AC-9 |

Generation order is mandated by the mode: threat model FIRST and richest, then SRS, then HLD/API contract, then DevOps record and test plan.
**Skipped:** ERD — no relational database exists; persistence is a single key-value DataStore blob whose schema is specified in the API contract.

## ACCEPTANCE CRITERIA (each observable and testable as written)
- **AC-1** `THREAT_MODEL.md` follows ASSETS → TRUST BOUNDARIES → THREATS → MITIGATIONS → RISK REGISTER, every `T-n` mapped 1-to-1 to an `M-n`, and includes the monetization and leaderboard boundaries. *Check: grep counts of `T-` and `M-` ids match; section order verified by reading.*
- **AC-2** Every SRS functional and non-functional requirement is stated so a pass/fail test can be written from the text alone, with no follow-up question. *Check: per-requirement review at Gate 3.*
- **AC-3** `HLD.md` states the authority model explicitly: server decides outcomes by weighted sampling; client 3D physics is animation only. *Check: string present and unambiguous.*
- **AC-4** **Every SRS requirement is achievable under the HLD authority model.** No requirement may depend on the client determining an economic outcome, and no requirement may depend on server state the HLD says is not held. *Check: line-by-line reconciliation — this is the L-015 defect class and the single highest-risk criterion in this run.*
- **AC-5** `API_DATA_CONTRACT.md` specifies every remote's name, direction, arity, argument types, validation rule, and failure response; and the complete DataStore schema with a default for every field.
- **AC-6** The three simulation-derived constraints appear as binding design rules in the documents: conditional elements scale with combined invested mass; elements produce specialisation not symmetry; re-forging carries real cost. *Check: each present and attributed to L-016.*
- **AC-7** `TEST_PLAN.md` names, for every suite, its file path, its literal execution procedure, and its named output artifact — executable by an agent without inferring intent.
- **AC-8** `DEVOPS_RECORD.md` records ten decisions, naming secret LOCATIONS and MECHANISMS only, never values.
- **AC-9** Every document opens with `CONSUMED-BY: Gate X / Matrix Y` and `STATUS: LIVING`, naming a gate and matrix that exist in `CHECKLISTS.md`.
- **AC-10** Zero placeholders (`TBD`/`TODO`/`FIXME`). Genuinely unknown values are recorded as explicit `UNKNOWN` entries with their reason, and every UNKNOWN also enters the risk register.

## SCOPE FENCE
**IN:** the seven files above; `.brain/LEDGER.md` appends; `.brain/SCOREBOARD.md` line; `AI_WORKSPACE_RULES.md` Section 1 (done, Gate 0 duty).
**OUT — explicitly not this run:** any `src/**` or `tests/**` game code · `default.project.json` / Rojo config · Robux asset IDs (operator has not created the products; recorded UNKNOWN) · balance numbers beyond the simulation-derived ranges · art, audio, or asset production · any git commit or push (repository visibility unconfirmed).

## IMPACT SURFACE MAP
No existing product code exists to affect — the repository was cleared. The documents become the binding contract for every later construction run. `roblox_luau.md` is consumed as guidance and remains PROVISIONAL. No external contracts, no persisted data formats in production, no live consumers.

## RISKS CARRIED INTO THIS RUN
1. **AC-4 is where the last run died.** A requirement the architecture cannot deliver survived into the documents and past an audit. Mitigated by making it an explicit acceptance criterion and an enumerated audit row.
2. **Cross-die coupling is validated only in its mass-coupled form.** The flat conditional variant is algebraically inert. If a document specifies a flat conditional bonus, that is a defect.
3. **Repository visibility is unconfirmed.** The threat model is an exposure inventory; it will be written to the working tree but NOT staged or committed until the operator confirms visibility.

## GATE 0 VERDICT: **PLAN-APPROVED**
Operator authorization on record: *"treat this as your official authorization to immediately enter Blueprint Mode and generate the production document set and threat model."* Build Tier PRODUCTION confirmed by the operator's own wording. Proceeding to Gate 1.
