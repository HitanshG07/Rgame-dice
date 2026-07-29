# .brain/modes/blueprint.md - PRE-CODE PLANNING DOCUMENT PROTOCOL

*MODE CONTRACT: living document; Gate 6 may refine it under double veto, but the consumer-gate law, the tier scaling, the threat-model-first order, the entry locks, and the exit-artifact requirement may never be weakened (restating INDEX Mode Law 6 with this file's specifics). Forged as BRAIN v1.4 from the bigdreamtour field trial (decision record: ledger 2026-07-16; PASS declared by the operator 2026-07-18) — trial-first, codify-after.*

## ENTRY CRITERIA
Two routes; the operator confirms in both — agents never self-start this mode:
1. **Recommended handoff:** at the close of a `project_setup.md` intake that declared INTERNAL or PRODUCTION tier, Gate 0 MUST recommend this mode by name and list the documents the tier mandates. It runs only on the operator's confirmation; a declined recommendation is recorded in the Setup Manifest. PROTOTYPE tier generates nothing beyond the six-pillar manifest and is never routed here.
2. **On demand:** explicit operator invocation in any project at any point. On a brownfield project, the Adoption Protocol must have completed first (see BROWNFIELD LAW). On a declared-PROTOTYPE project, invocation never runs the mode and never silently promotes the tier: the mode halts and asks the operator to either confirm a tier promotion by their word (Tier Debt applies, bootloader Section 8) or withdraw the request — the PROTOTYPE prohibition is absolute while the declaration stands.

## THE PRIME LAW — CONSUMER-GATE
A document no gate reads is dead weight, guaranteed to rot. Every generated document MUST open with:

```
CONSUMED-BY: Gate X / Matrix Y
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact
```

A document whose consumer gate cannot be named is NOT generated — no exceptions, no "for reference" artifacts. The header is a contract: the named gate's persona must consult the document whenever that gate runs, and Gate 5 checks currency (Matrix F doc-currency line).

## THE TIER-SCALED DOCUMENT SET
The tier is the one declared at Gate 0 per bootloader Section 8 — never inferred by an agent.
- **PROTOTYPE:** nothing beyond the six-pillar Setup Manifest. This mode does not run.
- **INTERNAL:** PRD-lite (goals, users, feature list with acceptance-criteria seeds) + ERD and/or API contract IF the project has a database or exposes/consumes an API.
- **PRODUCTION:** all of INTERNAL, plus SRS (functional + non-functional requirements: performance, security, scaling, uptime), HLD (macro architecture, data flow, integrations), threat model, DevOps decisions record, and test plan.

Documents live at `docs/blueprint/` — one canonical path every gate persona and every harvest checks. Pre-mode planning documents found elsewhere (e.g., a trial-era `THREAT_MODEL.md` at the repo root) are MIGRATED into `docs/blueprint/` with `CONSUMED-BY` headers added on this mode's first run in that project — grandfathered in place until then. Generation order: threat model FIRST, then SRS/PRD, then HLD/ERD/API contract, then DevOps record and test plan. Skip-eligibility is limited to the reality-conditional documents — ERD and API contract, skipped with a one-line reason in the Blueprint Manifest when no database or API exists, never generated empty. The threat model, SRS, HLD, DevOps decisions record, and test plan are mandatory at PRODUCTION, and PRD-lite is mandatory at INTERNAL; none of these is ever skip-eligible — a skipped threat model would silently revert Gate 4 to a generic-only sweep.

## CONSUMER WIRING (who reads what)
- **PRD / SRS → Gate 0 / Matrix A:** every task's acceptance criteria trace to a requirement; an untraceable criterion is either a new requirement to be added by amendment or scope creep to be fenced.
- **Test plan → Gate 2 / Matrix C:** names the suites, the coverage expectations, and the runtime-smoke definition the mechanical pass executes.
- **ERD / API contract → Gate 3 / Matrix D (code-to-world):** schema and endpoint reality are audited against the declared contract; divergence is a finding or an amendment with its triggering fact.
- **Threat model → Gate 4 / Matrix E:** the Security Master audits against DECLARED assets, boundaries, threats, and mitigations, tagging every finding to its source (Matrix E line # or threat-item ID). This audit runs IN ADDITION TO, never instead of, the full Matrix E sweep — it upgrades Gate 4 from generic-only to project-specific, proven in the field trial (L-007).
- **All documents → Gate 5 / Matrix F:** the doc-currency check.

## THE THREAT MODEL (first and richest)
Structure, in order: **ASSETS** (what is worth stealing or breaking) → **TRUST BOUNDARIES** (where ownership of data changes hands) → **THREATS** per boundary, numbered T-1, T-2, … → **MITIGATIONS**, each mapped to its threat → **RISK REGISTER** (risks accepted rather than mitigated, stated plainly; the operator's acknowledgment is collected at the generation run's Gate 5 delivery and recorded in the Blueprint Manifest — DELIVERED is not issued without it). Amendments are logged in the project ledger with their triggering facts, harvest-ready. **REPOSITORY VISIBILITY:** a threat model is an exposure inventory — in a public repository, publishing unmitigated findings is itself an exposure. The operator explicitly confirms repository visibility before the document is first committed. Operator-eyes-first, mechanically: a model carrying open exposures is written to the working tree but neither staged nor committed until the operator's visibility confirmation is recorded in the Blueprint Manifest; if the operator declines publication in a public repository, the file is added to `.gitignore` and lives operator-side only.

## THE DEVOPS DECISIONS RECORD (one page, decisions not tools)
Ten decisions, roughly one line each: environments and how they mirror; branching strategy; what CI runs; where secrets live and how they are injected; deploy target and mechanism; what is monitored; what alerts and to whom; what is backed up; how much loss is tolerable; who can touch production. The record names secret LOCATIONS and MECHANISMS, never secret values. Tool names are recorded choices, never imported mandates. Enforced at construction wherever `devops_infra.md` is loaded.

## BROWNFIELD LAW
On an existing codebase this mode never writes fresh documents from intent: the Adoption Protocol's archaeology pass feeds RECONSTRUCTED documents describing what IS. The reconstructed threat model records existing exposures as findings, not aspirations; the legacy boundary (bootloader Section 9) stays intact; reconstruction gaps are recorded as UNKNOWN, never invented — and every UNKNOWN in a reconstructed threat model additionally enters the risk register for operator acknowledgment, so an unanalyzed boundary is formally owned, never merely noted.

## PIPELINE PASSAGE
Generated documents are project files, and their generation is a file-modifying task: it traverses the standard gates as one planned change. Matrix B's zero-placeholder law applies to documents — no "[TBD]" bodies; what cannot be known yet is either asked at intake or recorded as an explicit UNKNOWN with its reason. Gate 4's audit of the threat model text is that model's own first audit. For a document-only change, Matrix C reduces to what mechanically applies — markdown/format lint and link validity where tooling exists, with build/type/test/smoke lines marked N/A (no runnable artifact) — and the Gate 3 cognitive review is the real check. KNOWN LIMIT (stated, not hidden): only Gate 5 carries a mechanical matrix line for the consumer-gate law (Matrix F doc-currency); consumption at Gates 0/2/3/4 is a prose duty carried by this mode and the documents' headers — a deliberate minimal footprint that leaves `PIPELINE.md` and `PERSONAS.md` untouched. If field use shows the prose duty slipping, the fix is additive matrix lines, never gate redefinition.

## REJECTED ARTIFACTS (recorded so they stay rejected; reversal is operator-only)
Decided 2026-07-16, reaffirmed at the forge:
- **LLD-as-document:** with an AI team the code is the low-level design; an LLD document is stale the moment Gate 1 closes, and its only future is drift.
- **WBS / Jira / sprint artifacts:** they exist to coordinate many humans with calendars; phase directives already serve a one-operator-plus-AI team.
- **Figma / design-system mandates:** `ui_ux_design.md` enforces the accessibility and state floors in code, where they are checkable; a mandated design document without a design tool is theater.
- **Enterprise-tool prescriptions** (Terraform/Kubernetes/ELK/PagerDuty catalogs): decisions matter and tool catalogs rot; the DevOps record captures the decisions only.

## EXIT ARTIFACT
The **Blueprint Manifest**: the generated documents with their `CONSUMED-BY` lines, the tier and its mandate list, every skipped document with its one-line reason, and the operator's confirmation record. Delivered through Gate 5 honestly — anything deferred is listed as deferred, never silently dropped.
