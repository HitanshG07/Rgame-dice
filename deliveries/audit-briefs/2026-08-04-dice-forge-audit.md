# CROSS-VENDOR AUDIT BRIEF — Dice Forge blueprint (2026-08-04)

You are auditing a PRODUCTION-tier planning document set. Two steps: Gate 3 (cognitive audit) then Gate 4 (security clearance). **You never fix anything — report only.**

## HOW THIS BRIEF IS WRITTEN, AND WHY

Every checklist line is **enumerated inline** with a `Verdict` and `Evidence` column. Nothing is referenced from another file. This is deliberate: ledger entry **L-014** records that on a previous audit, checklist lines that were *referenced* got partially executed and silently truncated (4 of 9 Matrix D lines evaluated, reported as all), while criteria spelled out as an explicit table were evaluated accurately.

**Three hard rules.**
1. **Every row gets a verdict** — `PASS`, `FAIL`, or `N/A`. Every `N/A` carries a one-line justification. An unjustified `N/A` counts as `FAIL` (CHECKLISTS.md line 2).
2. **Every evidence cell cites something you actually read** — a file and line number, or a verbatim quote. If you cannot produce evidence, the verdict is `FAIL`, not `PASS`.
3. **A blank row is a visible omission.** That is the point of the format.

**A zero-finding result is a possible outcome, not a target.** On the previous project a zero-finding audit was wrong, and the change it approved contained a material defect. Treat your own "everything passes" conclusion with suspicion before writing it.

---

## WHAT YOU ARE AUDITING

Commit `0c7f800`. Six documents in `docs/blueprint/`: `THREAT_MODEL.md`, `SRS.md`, `HLD.md`, `API_DATA_CONTRACT.md`, `TEST_PLAN.md`, `DEVOPS_RECORD.md`. Plan artifact with acceptance criteria: `deliveries/plans/2026-08-04-dice-forge-blueprint.md`.

**Out of scope:** `src/**`, `tests/**` (no game code exists yet — this run produced documents only), and `.brain/**` governance files.

**The design in three sentences.** Players throw 3D dice in a contained arena and spend earnings forging individual faces under a **zero-sum mass budget** — mass moves between faces, never accumulates. Heavier faces pay superlinearly but land less often, so every forge is a trade-off. **The server decides every roll outcome by weighted sampling; the client's 3D tumble is animation resolving to an already-decided face.**

---

# STEP 1 — GATE 3: COGNITIVE AUDIT
Persona: **Isolated Fresh-Context QA Auditor.**

## 1a. Blind re-derivation — do this BEFORE opening any document
From the three-sentence design summary above **alone**, write what a correct PRODUCTION document set should contain: which documents, what each must cover, and what would make them mutually consistent. **Then** open the files. Every gap between your expectation and reality is a finding until resolved with evidence. Include your written expectation in the artifact. *(Do not restate the acceptance criteria below as your "expectation" — that finds nothing the criteria did not already ask for.)*

## 1b. Acceptance criteria

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| AC-1 | `THREAT_MODEL.md` runs ASSETS → TRUST BOUNDARIES → THREATS → MITIGATIONS → RISK REGISTER; every `T-n` has a mapped `M-n` | | |
| AC-2 | Every SRS requirement is testable as written, no follow-up question needed — **see 1c, all rows required** | | |
| AC-3 | `HLD.md` states the authority model unambiguously: server samples outcomes, client physics is animation only | | |
| AC-4 | **Every SRS requirement is achievable under that authority model** — see 1d, this is the highest-risk criterion | | |
| AC-5 | `API_DATA_CONTRACT.md` gives every remote's name, direction, arity, types, validation and failure response; plus a complete profile schema with a default for every field | | |
| AC-6 | The three simulation-derived constraints appear as binding rules: conditional elements scale with combined invested mass; elements produce specialisation not symmetry; re-forging carries real cost | | |
| AC-7 | `TEST_PLAN.md` gives every suite a file path, a literal procedure, and a named output artifact | | |
| AC-8 | `DEVOPS_RECORD.md` has ten decisions and names secret LOCATIONS/MECHANISMS only, never values | | |
| AC-9 | All six documents open with `CONSUMED-BY` + `STATUS: LIVING`, naming gates/matrices that exist in `.brain/CHECKLISTS.md` | | |
| AC-10 | Zero placeholders. Unknowns are explicit with reasons and also appear in the risk register | | |

## 1c. SRS testability — every requirement, individually
For each: could you write a pass/fail test from the text alone? Requirements are FR-1…FR-14 and NFR-1…NFR-8. **Count them yourself in the file and fill one row per requirement group.**

| Req group | Verdict | Evidence | | Req group | Verdict | Evidence |
|---|---|---|---|---|---|---|
| FR-1 Arena & presentation | | | | FR-9 Prestige | | |
| FR-2 Rolling & resolution | | | | FR-10 Progression rewards | | |
| FR-3 The Forge | | | | FR-11 Leaderboards | | |
| FR-4 Elements | | | | FR-12 Monetization | | |
| FR-5 Streaks | | | | FR-13 Interface | | |
| FR-6 Dice shapes | | | | FR-14 Persistence | | |
| FR-7 Automation | | | | NFR-1 … NFR-4 | | |
| FR-8 Offline vault | | | | NFR-5 … NFR-8 | | |

## 1d. Authority-model reconciliation — the check that matters most
The HLD states the server holds **no per-die rigid-body state** — no positions, velocities, orientations or collisions. On the previous project, requirements were specified that the chosen architecture could not deliver, and the audit missed it (ledger L-015).

| # | Check | Verdict | Evidence |
|---|---|---|---|
| AM-1 | No SRS requirement depends on where a die is, what it hit, or how it moved | | |
| AM-2 | Every element in FR-4.4 resolves from the **resolved face set alone** | | |
| AM-3 | No inbound remote in API §1.1 accepts a price, balance, reward, score, level, duration, multiplier or outcome | | |
| AM-4 | No requirement needs server state the HLD says is not held | | |
| AM-5 | The `ForgeMath` module is shared client+server — confirm this grants the client no authority, or FAIL it | | |

## 1e. Cross-document consistency — all six, none optional

| # | Check | Verdict | Evidence |
|---|---|---|---|
| X-1 | Every module named in `HLD.md` §3 is named identically wherever else it appears | | |
| X-2 | **Every SRS functional requirement** is reflected in HLD, API contract and test plan, or is deliberately absent | | |
| X-3 | Every remote in API §1.1/§1.2 has its trust boundary covered by a threat | | |
| X-4 | **Every mitigation `M-1`…`M-25`** names a mechanism some document actually specifies — not an intention | | |
| X-5 | The ProfileStore pivot is coherent across all six documents — **no document still describes the dependency as unsupported or names ProfileService as the chosen library** | | |
| X-6 | Risk `R-8` (no MessagingService) and the `TEST_PLAN` P-3 grep are consistent, including the `Vendor/` exclusion | | |

## 1f. Matrix D — all nine lines, verbatim from `CHECKLISTS.md`
Applied to the **design the documents describe**. Several may be genuinely `N/A` for a document-only change — say so with a justification rather than leaving blank.

| # | Line | Verdict | Evidence |
|---|---|---|---|
| D-1 | Null/absent/uninitialized: every dereference on a possibly-absent value guarded or provably safe | | |
| D-2 | Boundary inputs: zero, negative, empty collection, empty string, maximum, single-element all defined | | |
| D-3 | Concurrency: no unsynchronized read-modify-write on shared state; no ordering assumption between independent async ops | | |
| D-4 | Asynchronous failure: every deferred operation has a rejection/failure consumer | | |
| D-5 | Resource lifecycle: every acquisition has guaranteed release on success and failure paths | | |
| D-6 | Idempotency: retried or duplicated state-changing operations do not corrupt state | | |
| D-7 | Regression: every pre-existing behaviour sharing a code path re-verified with evidence | | |
| D-8 | Blind re-derivation performed before opening the diff, mismatches resolved with evidence | | |
| D-9 | Code-to-world contract: every parameter crossing into an external system validated against queried capabilities, never assumed | | |

## 1g. Gate 3 verdict
Exactly one of `AUDIT-APPROVED` or `REJECTED-TO-GATE-1` + numbered defect list.
**Exit artifact, this exact path:** `deliveries/evidence/2026-08-04-gate3-audit.md`

---

# STEP 2 — GATE 4: SECURITY CLEARANCE
Persona: **Cyber Security Master.** Run only if Gate 3 returned `AUDIT-APPROVED`; if it rejected, stop and report.

## 2a. Matrix E — all nine lines, verbatim

| # | Line | Verdict | Evidence |
|---|---|---|---|
| E-1 | All inbound data crossing a trust boundary validated, encoded, or allowlisted before use | | |
| E-2 | No data concatenated into any interpreter — structural separation only | | |
| E-3 | No secret value in source, version-controlled config, logs, error output, or fixtures | | |
| E-4 | Every new capability justified by an acceptance criterion | | |
| E-5 | Every third-party dependency has a review note and pinned version | | |
| E-6 | Every dependency's license identified and compatible; copyleft FLAGGED | | |
| E-7 | No PII, credentials or session tokens reach logs or analytics in readable form | | |
| E-8 | Error paths leak no internals to untrusted callers | | |
| E-9 | Auth/authorization/crypto paths touched by this change re-verified end-to-end | | |

**On E-5/E-6:** this project has **exactly one** third-party dependency — ProfileStore by loleris. Verify its review note, pinning requirement and license claim in `DEVOPS_RECORD.md`. *(On the previous project an auditor reviewed the license of a library that was not a dependency at all. Confirm what is actually declared before assessing it.)*

## 2b. Threat model audit — its own first security audit

| # | Question | Verdict | Evidence |
|---|---|---|---|
| TM-1 | Asset census complete — name anything worth stealing or breaking that A-1…A-10 omits | | |
| TM-2 | Trust boundaries complete — name any place data ownership changes hands that TB-1…TB-7 misses | | |
| TM-3 | Every mitigation is **mechanical**, not aspirational — quote any amounting to "we will be careful" | | |
| TM-4 | No risk in R-1…R-8 is actually mitigable and merely accepted for convenience | | |
| TM-5 | **What threat is missing entirely?** You are a different model family than the author — this is the highest-value row in this brief. An empty answer is the least believable outcome | | |

Specific areas worth adversarial attention, since they carry real money or unrecoverable player state: the forge validator ordering (T-25 — does checking finiteness before summation actually close it?); receipt idempotency across a server restart (T-15/T-16); session-lock fail-closed behaviour (T-10); offline vault clock handling (T-23/T-24); and leaderboard integer bounds (T-20).

## 2c. Finding tags
Every finding carries a tag: a Matrix E line number, or a `T-n`/`M-n`/`R-n` id. **If there are no findings, write "no findings" — do not list example tags.** *(On the previous audit, tag strings were listed that corresponded to no findings and appeared nowhere else in the artifact; that reads as fabricated evidence.)*

## 2d. Gate 4 verdict
Exactly one of `SECURE` or `FLAGGED-TO-GATE-1` + numbered tagged finding list.
**Exit artifact, this exact path:** `deliveries/evidence/2026-08-04-gate4-security.md`

---

## RETURN
Both artifacts at the exact paths above, every table fully populated, plus the two verdict strings. Modify no file other than those two artifacts. A step you could not perform is reported as not performed — never as a pass.
