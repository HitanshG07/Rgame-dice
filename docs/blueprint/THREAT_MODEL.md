CONSUMED-BY: Gate 4 / Matrix E
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# THREAT MODEL — DICE FORGE INCREMENTAL

Built first and richest, per `.brain/modes/blueprint.md`. The Cyber Security Master audits every change against the assets, boundaries, threats and mitigations declared here, tagging each finding to a `T-n`/`M-n` id or a Matrix E line. This audit runs IN ADDITION TO the full Matrix E sweep, never instead of it.

**One sentence of context that drives everything below:** the server decides every roll outcome by weighted sampling; the client's 3D dice tumble is animation resolving to an already-decided face. Almost every mitigation here follows from refusing to let that invert.

---

## 1. ASSETS

- **A-1 — Cash.** The soft currency, earned per roll and spent on forging. The primary theft target.
- **A-2 — Mass budget and face layouts.** The player's actual progress. Every die's total mass, its per-face distribution, and each face's element assignment. Losing this is losing the account.
- **A-3 — Prestige Diamonds and the Streak Strength tree.** Permanent currency and the permanent upgrade that defines a player's build cohort. Unrecoverable if corrupted — there is no re-grind that feels acceptable to a player who has ascended.
- **A-4 — Gems.** Premium currency, purchasable with Robux. Real money once granted.
- **A-5 — Robux receipts.** `PurchaseId` records proving a Developer Product was granted. Losing one causes a double-grant or a paid-and-not-delivered dispute. Real financial consequence in both directions.
- **A-6 — Gamepass entitlements.** VIP Vault, +2 Dice Slots, Ultra Auto-Roll, Bad Roll Shield. Persistent paid capability.
- **A-7 — The DataStore profile blob.** The container for A-1 through A-6. Its integrity is the integrity of everything.
- **A-8 — Leaderboard standings.** Top Net Worth, Highest Single Roll, Max Prestiges. Public, competitive, and therefore worth cheating for.
- **A-9 — Server frame budget.** A shared resource. One player able to consume it disproportionately is a denial-of-service vector against everyone else on that server.
- **A-10 — Offline vault accrual.** Time-based earnings, and therefore attackable through time itself.

---

## 2. TRUST BOUNDARIES

- **TB-1 — Client → Server (RemoteEvents / RemoteFunctions).** The only inbound channel a player controls. Every byte crossing it is hostile until validated.
- **TB-2 — The client process.** Fully untrusted. Roblox `LocalScript` source is readable and the runtime is modifiable by exploit tooling. Anything the client knows, an attacker knows; anything the client decides, an attacker decides. *(Direct analogue of L-007: a shipped client bundle is published, not secret.)*
- **TB-3 — Server ↔ DataStore.** Serialisation, session ownership, and write ordering across server instances.
- **TB-4 — Server ↔ MarketplaceService.** Receipt processing and gamepass ownership queries. The real-money boundary.
- **TB-5 — Server ↔ OrderedDataStore.** Cross-server leaderboard publication. Data written here is globally visible.
- **TB-6 — Physics ownership.** Roblox assigns network ownership of moving parts to a client by default. Dice are moving parts. This boundary exists whether or not it is acknowledged, which is precisely why it is listed.
- **TB-7 — Server clock ↔ wall clock.** Offline earnings depend on elapsed real time, which is not a trustworthy input.

---

## 3. THREAT CENSUS & MITIGATIONS

### TB-1 / TB-2 — the client boundary

**T-1 — Client claims a roll outcome.**
*Vector:* an exploiter fires the roll remote with a chosen face, or reports "I landed face 6" directly.
*M-1:* the client never transmits an outcome. It transmits **intent only** — "roll now". The server samples the face from the die's mass distribution using a server-held RNG, computes the payout, and pushes the result down. There is no remote parameter anywhere in the game capable of expressing a face, a value, or an amount. *(See `API_DATA_CONTRACT.md` §1: no inbound remote accepts a numeric economic quantity.)*

**T-2 — Client manipulates the physics to force a face.**
*Vector:* since Roblox grants network ownership of moving parts to the client, an exploiter freezes, rotates, or teleports a die so the desired face points up.
*M-2:* the landed face is **already decided before the animation starts** and is never read back from the rigid body. The dot-product face-reading described in the original design is deliberately NOT used to determine payout — it is used only by the client to choose a tumble that ends on the server's face. Manipulating the physics changes what the exploiter sees and nothing else. Dice are also client-owned by design, because their motion is cosmetic; this is a deliberate, recorded decision rather than an oversight.

**T-3 — Roll-rate flooding.**
*Vector:* the roll remote is fired thousands of times a second, either to farm currency or to exhaust the server (A-9).
*M-3:* per-player token-bucket rate limiting at the gateway, with the ceiling derived from the player's *server-known* auto-roll tier — not from anything the client asserts. Requests over budget are dropped silently and counted; sustained abuse is logged with the `UserId`. Never auto-kick: lag produces false positives, and banning a laggy child is worse than absorbing a dropped request. *(Matrix E-1.)*

**T-4 — Forge request for mass the player does not have.**
*Vector:* a forge remote is called moving 10,000 mass onto a face when the budget is 600.
*M-4:* forging is expressed as a **redistribution proposal** which the server validates as a closed system: every face mass is a finite non-negative number, the proposed distribution sums to exactly the player's server-held budget within a fixed epsilon, no face falls below the floor, and the player can afford the forge cost. Any violation rejects the whole proposal and mutates nothing. **Zero-sum is a security property here, not only a design one** — a validator that checks the sum cannot be tricked into inflating a face.

**T-5 — Element assignment to unowned elements.**
*Vector:* the client asks to place `Gold` on a face before unlocking Gold.
*M-5:* element ids are resolved against a **server-held allowlist** intersected with the player's unlocked set. The client's string is used to look up, never to index directly into a table, and an unresolved id rejects the request. *(Matrix E-1, E-2.)*

**T-6 — Ability/consumable spoofing.**
*Vector:* the client claims a 2× Luck Boost is active, or that a Bad Roll Shield should absorb a streak break.
*M-6:* every boost and entitlement is server-held with a server-clocked expiry (`os.clock()` for durations, `os.time()` for wall-clock windows). The client is *told* what is active for display purposes and is never asked.

**T-7 — Error output leaks internals.**
*Vector:* a malformed remote call returns a Luau error string exposing module paths, table structure, or balance formulas.
*M-7:* rejections log fully server-side with the `UserId` and reason, and return a **generic** reason string to the client from a fixed enumerated set. No stack trace, path, or internal value crosses TB-1. *(Matrix E-8.)*

**T-8 — Server thread hang via `InvokeClient`.**
*Vector:* the server calls `RemoteFunction:InvokeClient()`; an exploiting client never returns, hanging the thread indefinitely.
*M-8:* `InvokeClient` is **prohibited project-wide**. All server-to-client communication is `RemoteEvent:FireClient()`. This is a build-time rule, verified by static grep in the test plan.

**T-9 — Reading the client to learn the odds.**
*Vector:* an exploiter reads `LocalScript` source to extract drop rates and optimal builds.
*M-9:* accepted rather than mitigated — see **R-2**. Balance formulas that must stay private live server-side only; the client receives resolved display values, not the formulas that produced them. The forge maths is intended to be public anyway, since community theorycrafting is a design goal.

### TB-3 — persistence

**T-10 — Concurrent session overwrite.**
*Vector:* a player joins server B while server A still holds their session; A's stale save overwrites B's newer state, or both interleave and corrupt.
*M-10:* session locking, **delegated to ProfileStore** (HLD §5.1) rather than hand-rolled — this is the highest-consequence logic in the project and a battle-tested implementation beats bespoke locking. The library claims the session lock atomically on load and refuses saves from a server that has lost it, and it force-claims locks older than its staleness threshold so a crashed server cannot lock a player out permanently. **Delegation moves the risk, it does not remove it:** correctness now depends on a third party, and on an unsupported one — see R-7. Our obligation is the FAIL-CLOSED behaviour on top of it (HLD §5.2 rule 1): a profile that will not load, or whose lock is held elsewhere, must never be replaced by a default profile. *(Amendment 2026-08-04; triggering fact: operator directed the use of ProfileService.)*

**T-11 — Lost update via `SetAsync`.**
*Vector:* read-modify-write races silently discard a purchase or a forge.
*M-11:* `SetAsync` is **prohibited** for profile writes. All mutations go through `UpdateAsync`, whose transform function is pure and side-effect free so it is safe to re-run on contention.

**T-12 — Schema drift orphans a profile.**
*Vector:* a new field ships; existing profiles lack it; code dereferences `nil` and the player's session breaks or resets.
*M-12:* every profile carries a schema `version`, and a migration chain runs on load with a **complete default for every field**. An unmigratable profile is quarantined under a separate key and the player is served a fresh profile with an operator alert — never a silent overwrite of data that might be recoverable.

**T-13 — Profile payload exceeds the DataStore key limit.**
*Vector:* per-purchase and per-code records accumulate forever until the profile exceeds the per-key ceiling, at which point **every subsequent save fails** — permanent, total loss for the longest-playing, highest-spending players.
*M-13:* `purchaseIds` is a **bounded** structure — most recent 200 entries, insertion-ordered, older entries evicted. **AMENDED 2026-08-04** *(triggering fact: Gate 4 cross-vendor audit, TM-5.1)* — the original justification, "safe because replays occur within a bounded window after purchase", was **wrong**: the bound is on entry COUNT, not on TIME. A player exceeding 200 lifetime purchases can have a still-replayable receipt evicted, and a platform retry then double-grants. Corrected mitigation: eviction is **time-aware, not count-only** — an entry is evictable only once it is older than the platform's maximum receipt-retry window, and if the 200-entry ceiling is reached while all entries are still inside that window, older ids are **archived to a cold DataStore key** rather than dropped. The payload ceiling assertion still governs total size. `codesRedeemed` is naturally bounded by the server-held code catalog. The writer **asserts a serialised payload ceiling before every save** and refuses to write beyond it, logging the refusal, so no future field can silently reintroduce unbounded growth. *(Carried forward from the previous project, where this was found only at Gate 4 audit.)*

**T-14 — DataStore outage causes silent progress loss.**
*Vector:* Roblox DataStore is unavailable; saves fail; the player plays for an hour and loses everything.
*M-14:* `pcall` on every call with bounded exponential backoff; failures retained in an in-memory session cache and retried; `game:BindToClose()` flushes all sessions on shutdown with the platform-allotted grace window. After repeated failures the player is shown an honest in-game warning that progress may not be saving — players tolerate a warning far better than silent loss.

### TB-4 — real money

**T-15 — Receipt replay / double-grant.**
*Vector:* the same `PurchaseId` is processed twice, granting Gems twice for one payment.
*M-15:* each `PurchaseId` is recorded in the **DataStore, not in memory** — an in-memory set is erased by every server restart, making the idempotency guarantee false in exactly the situation it is needed. The check-then-grant is made atomic inside a single `UpdateAsync`.

**T-16 — Grant lost after payment taken.**
*Vector:* `PurchaseGranted` is returned but the save then fails; Robux is taken and the player receives nothing.
*M-16:* `PurchaseGranted` is returned **only after the grant has durably persisted**. Every other path — player offline, unknown product, save failure, validation failure — returns `NotProcessedYet`, so Roblox retries later. Erring toward retry risks a duplicate that M-15 catches; erring the other way steals from a player.

**T-17 — Multiple `ProcessReceipt` assignments.**
*Vector:* two modules each assign `MarketplaceService.ProcessReceipt`; the second silently replaces the first and an entire product category stops granting.
*M-17:* **exactly one** assignment exists in the entire place, in `MonetizationService`. Verified by static grep in the test plan, because this failure is silent and catastrophic.

**T-18 — Gamepass check failure grants a benefit.**
*Vector:* `UserOwnsGamePassAsync` throws or times out and the error path treats the result as truthy.
*M-18:* the call is `pcall`-wrapped and cached per session. A failed check resolves to **unknown, which DENIES** the benefit and is retried — never "assume owned". Yielding network calls are never made inside the roll loop.

**T-19 — Unresolved product id grants something.**
*Vector:* a Developer Product id not present in the catalog is purchased.
*M-19:* product ids resolve against a server-held catalog and **fail closed**. Asset ids do not exist yet (**U-1**), so at present every product fails closed, which is the correct safe state.

### TB-5 — leaderboards

**T-20 — Integer overflow on the leaderboard key.**
*Vector:* an idle economy produces cash values far beyond the signed 64-bit range `OrderedDataStore` accepts; writes fail or wrap, corrupting global rankings.
*M-20:* leaderboard values are a **bounded, log-scaled, monotonic integer** derived from the true value, never the raw number. Monotonic so ordering is preserved; bounded so it provably cannot overflow. Verified against a cash value of 1e300 in the test plan.

**T-21 — Leaderboard injection via display name.**
*Vector:* a client-supplied name string is written to the leaderboard and rendered to other players.
*M-21:* display names are read from the `Players` service server-side and never accepted from a client message. Rendering uses text properties, never rich-text interpolation of untrusted strings. *(Matrix E-1, E-2.)*

**T-22 — Leaderboard request flooding.**
*Vector:* repeated `GetSortedAsync` calls exhaust the API budget and break rankings server-wide.
*M-22:* one server-wide cached fetch on a fixed interval, shared by all players on that server. Player requests read the cache and never trigger a fetch.

### TB-7 — time

**T-23 — Offline earnings via clock manipulation.**
*Vector:* the player changes their device clock, or the client reports elapsed offline time, to claim a large vault payout.
*M-23:* elapsed time is computed **entirely server-side** from `os.time()` at save versus load. The client never supplies, and is never asked for, a timestamp or a duration. Elapsed time is clamped to `[0, vaultCapacity]` — a **negative** elapsed value (clock skew, or a profile saved with a future timestamp) credits exactly zero and is logged, never a negative or wrapped payout.

**T-24 — Time Skip / 2× Offline stacking.**
*Vector:* the "2× Offline Payout" prompt is accepted repeatedly against the same accrued vault, or Time Skip is claimed twice for one window.
*M-24:* the vault is **consumed atomically on claim** — the accrual window closes and resets inside the same `UpdateAsync` that credits it. A second claim finds an empty vault. Consumable purchases are bound to a specific vault-accrual id so a receipt cannot be applied to a window it was not bought for.

### Cross-cutting

**T-25 — Forge validator arithmetic abuse.**
*Vector:* `NaN`, `math.huge`, `-0`, or a denormal is submitted as a face mass. `NaN` fails every comparison, so a naive `sum == budget` check passes and the budget invariant breaks.
*M-25:* every inbound numeric is checked for finiteness explicitly (`n == n` for NaN, plus finite bounds) **before** any arithmetic or comparison. This is called out as its own threat because a sum-based validator is exactly the shape that `NaN` defeats. *(Matrix E-1.)*

**T-26 — Post-yield mutation of a released profile.**
*Vector:* a service checks `profile:IsActive()`, then **yields** (a DataStore call, a MarketplaceService query, a `task.wait`), and during that yield `ListenToRelease` fires. The subsequent mutation is applied to a released profile and is silently lost — or worse, applied after another server has claimed the session.
*M-26:* the active check must be **synchronous with the mutation** — no yield may occur between `IsActive()` and the write. Where a yield is unavoidable, the check is re-performed immediately after it and immediately before applying state. This is a code-shape rule, verifiable by review, and it is why FR-14.7 now specifies synchronicity rather than merely requiring a check. *(Added 2026-08-04; triggering fact: Gate 4 cross-vendor audit, TM-5.2.)*

**T-27 — Floating-point residual accumulation defeats the forge sum invariant.**
*Vector:* mass values are floats. Repeated forge operations accumulate IEEE 754 residuals, so `sum(distribution)` drifts against the stored budget. Drift either exceeds `EPSILON` and locks the player out of forging entirely, or — if `EPSILON` is loosened to compensate — permits real mass inflation across many operations.
*M-27:* per-face masses are **snapped to a fixed decimal precision before sum validation and before storage**, so residuals cannot compound across operations. `EPSILON` then guards only single-operation representation error, not accumulated drift. *(Added 2026-08-04; triggering fact: Gate 4 cross-vendor audit, TM-5.5.)*

**T-28 — Non-finite value reaches the leaderboard transform.**
*Vector:* the published value is `math.clamp(math.floor(math.log10(math.max(raw, 1)) * 1e6), 0, 9e15)`. `NaN` propagates through every one of those operations — `math.max(NaN, 1)` does not sanitise it — and `OrderedDataStore:SetAsync` then throws, breaking leaderboard publication for that player permanently.
*M-28:* `raw` is asserted **finite** (`raw == raw`, plus finite bounds) before the transform; a non-finite value is refused, logged, and the previous published value retained. **This is the same hazard as T-25, which was closed for the forge validator and left open here** — the inconsistency is the actual defect, so finiteness assertion is hereby a rule at *every* numeric boundary, not only inbound ones. *(Added 2026-08-04; triggering fact: Gate 4 cross-vendor audit, TM-5.4.)*

**T-29 — Cross-cluster clock skew inflates the offline vault.**
*Vector:* `os.time()` may differ slightly between Roblox hardware clusters. A profile saved on a forward-skewed server and loaded on a backward-skewed one yields an inflated elapsed time.
*M-29:* already **bounded** by M-23's clamp to `[0, capacity]` — the worst case is one extra full vault, not unbounded currency, so this is a hardening item rather than an exploit. Additional hardening: elapsed time is sanity-checked against server uptime, and a `LastSeen` timestamp in the future is treated as zero elapsed and logged. *(Added 2026-08-04; triggering fact: Gate 4 cross-vendor audit, TM-5.3. Severity assessed lower than the auditor stated, because the existing clamp already caps the damage.)*

---

## 4. RISK REGISTER
Risks accepted rather than mitigated. **The operator's explicit acknowledgment of this section is required at Gate 5 before DELIVERED is issued.**

- **R-1 — The physics is honest theatre.** Players are told they are throwing dice; the outcome is decided before the tumble begins. *Accepted:* it is indistinguishable from the player's side, it is the only exploit-proof option with public leaderboards, and it lets the presentation be choreographed. Recorded openly so no one later mistakes it for a bug.
- **R-2 — Client code is readable.** Odds, formulas and build maths can be extracted from `LocalScript` source. *Accepted:* nothing economically authoritative lives client-side, and public forge maths actively serves the theorycrafting goal.
- **R-3 — DataStore outages.** Roblox platform availability is outside our control. *Accepted*, mitigated by M-14 retry, cache and honest player warning.
- **R-4 — Repository visibility UNCONFIRMED.** This document is an exposure inventory; publishing it while findings are open is itself an exposure. *Status:* the file is written to the working tree but **must not be staged or committed** until the operator confirms visibility. If the repository is public and the operator declines to change it, this file is added to `.gitignore` and lives operator-side only.
- **R-5 — Rate limits are per-player, not per-account-network.** A coordinated multi-account attack is not addressed. *Accepted* as disproportionate to the value at stake for a game with no tradable assets.
- **R-7 — RESOLVED, retained for provenance. Third-party dependency on the integrity-critical path.** *Originally recorded 2026-08-04 as "the persistence library is unsupported", when ProfileService was selected. **Resolved the same day**: the maintenance finding was surfaced at Gate 1 and the operator pivoted to **ProfileStore**, loleris's actively-supported successor. The unsupported-library risk no longer applies.* The **residual** risk is narrower and still accepted: session-locking correctness — the property standing between a player and total progress loss — depends on third-party code we do not control. *Accepted:* a maintained, widely-deployed library is a better bet than bespoke locking logic, and all contact is confined to `PlayerProfile` so replacement is a one-module change. Our own obligation on top of it remains the FAIL-CLOSED behaviour (HLD §5.2 rule 1), which is ours to get right regardless of the library.
- **R-8 — Server-wide events are per-server only.** MessagingService is out of scope for V1 (operator scoping, 2026-08-04), so the Like Goal 3× event triggers independently on each server rather than globally. Two players on different servers can see different event states. *Accepted* for a clean MVP launch; genuinely global events require MessagingService and a later threat pass covering cross-server message trust.
- **R-6 — No cross-server duplication defence beyond session locking.** Session locking prevents the common case; a determined attacker with control over join timing may still find edges. *Accepted* at this scale; revisit if tradable items are ever introduced. **Adding trading would invalidate this acceptance and require a new threat pass.**

---

## 5. UNKNOWNS
Recorded rather than invented. Per the blueprint mode's brownfield law every UNKNOWN also enters the risk register above for operator acknowledgment.

- **U-1 — Robux asset ids do not exist.** The operator has not yet created the Game Passes and Developer Products. The catalog ships empty and every product **fails closed** (M-19). Resolving this is a one-line catalog change per product once ids are supplied.
- **U-2 — Final balance constants are untuned.** The simulations established *structure* — superlinear value, inverse-mass probability, a streak cliff near `b≈0.15`, mass-coupled conditional elements — not shipping numbers. Tuning is a construction-phase activity against live telemetry.
