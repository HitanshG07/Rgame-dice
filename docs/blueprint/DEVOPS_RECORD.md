CONSUMED-BY: Gate 1 / Matrix B
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# DEVOPS DECISIONS RECORD — DICE FORGE INCREMENTAL

Ten decisions, one line each. Decisions, not tool catalogues. **Secret locations and mechanisms only — never values.**

1. **Environments and how they mirror.** One Roblox place with two versions: the published production place, and Studio Play Solo for development. They mirror because both are built from the same `src/` tree via Rojo — Studio is never the source of truth, and no script is ever edited inside Studio, because Rojo overwrites on next sync and the change vanishes with no diff.

2. **Branching strategy.** `main` holds deployment-ready source. Feature work happens on single-purpose topic branches merged after their pipeline run completes. The repository is **private** (operator-confirmed 2026-08-04), which is what permits the threat model to be committed at all.

3. **What CI runs.** No hosted CI — Roblox has no headless runtime, so a GitHub Action cannot execute Luau against the engine. Verification is the four procedures in `TEST_PLAN.md` §2, executed in Studio. **This is an honest limitation, not a gap to be papered over:** this Claude session authors tests and cannot run them; the operator or an Antigravity session executes them and returns verbatim output.

4. **Where secrets live and how they are injected.** The project uses **no** credentials at runtime — no HTTP, no external services, no API keys. Should Roblox Open Cloud be adopted later, keys live in OS environment variables on the operator's machine and in CI secrets, never in source. `.env`, `.env.*` (with `!.env.example`) are in `.gitignore` **before** any key exists, because an ignore rule is a control and a code comment is not *(ledger L-007)*.

5. **Deploy target and mechanism.** Publish from Studio to the live place after a green Gate 2 run. Publishing is manual and deliberate — there is no auto-deploy, because a bad publish reaches every player instantly with no rollback window.

6. **What is monitored.** `ScriptContext.Error` for runtime errors, DataStore failure counts, receipt-processing outcomes, and rate-limit rejection volume per player. Roblox Experience Analytics for retention and revenue. **Retention curve shape in weeks 2–3 is the metric that matters** — the competitor research showed this genre spikes and collapses, and week-1 numbers say nothing.

7. **What alerts and to whom.** No paging infrastructure at this scale. The operator reviews the error log and DataStore failure rate after each publish and at least daily during the first week. A DataStore save-failure rate above a small threshold is the one condition warranting an immediate rollback decision.

8. **What is backed up.** Player data lives in Roblox DataStore, which Roblox replicates; we hold no separate backup and could not build one without Open Cloud. Source is backed by git. **A profile quarantined by the migration chain is retained under its own key rather than overwritten**, so a corrupted profile is recoverable by hand — that is the closest thing to a player-data backup this project has, and it is deliberate.

9. **How much loss is tolerable.** Target zero confirmed-transaction loss. The auto-save cadence bounds worst-case loss to one save interval of progress on an unclean shutdown. **Robux transactions tolerate zero loss** — `PurchaseGranted` is returned only after durable persistence, and every other path returns `NotProcessedYet` so Roblox retries *(threats T-15, T-16)*.

10. **Who can touch production.** The operator alone publishes. No agent in this workspace publishes, and no agent commits without the operator's explicit instruction. Commits touching protected brain files require `ALLOW_GOVERNANCE_EDIT=1`, set by the operator.

---

## DEPENDENCY REGISTER
*(Matrix E-5 / E-6. Amended 2026-08-04; triggering fact: operator directed ProfileStore after the maintenance finding.)*

| Dependency | Version | License | Review |
|---|---|---|---|
| **ProfileStore** (loleris) | **PINNED** `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31), vendored at `src/Server/Vendor/ProfileStore.luau`, sha256 `ad43737203688b8e…` | **Apache-2.0** — permissive, not copyleft, not FLAGGED. *(Corrected 2026-08-04: earlier entries said MIT. Verified against the GitHub license API at vendoring time. Apache-2.0 carries an attribution/NOTICE obligation — the vendored header must be preserved verbatim and not stripped.)* | Session-locked persistence. Chosen over bespoke locking because this is the highest-consequence code in the project. **Maintenance posture: actively supported** — ProfileStore is the successor to ProfileService, which is stable but no longer supported. Selected specifically on that basis after the maintenance finding was surfaced at Gate 1 *(supersedes the same-day ProfileService entry; risk R-7 resolved, retained for provenance)*. Also cuts DataStore call volume ~10× via a 300s default auto-save. **Uses MessagingService internally** for session-conflict resolution — library internals, not a gameplay use, and `TEST_PLAN.md` P-3 excludes `Vendor/` from the R-8 prohibition grep so the distinction is enforced mechanically. All library contact is confined to the `PlayerProfile` wrapper, so replacement is a one-module change. |

No other third-party dependency exists. Anything added later needs its own row here, a pinned version, and a Gate 4 review note.
