# .brain/skills/roblox_luau.md - ROBLOX PLATFORM & LUAU ENGINEERING PROTOCOL

*COGNITIVE DIRECTIVE: This is a living evolutionary document. If you encounter a more optimized methodology, a newer API standard, or a superior architectural pattern during development, you are strictly mandated to activate the Cognitive Evolutionist persona during Gate 6 and rewrite these rules to permanently upgrade this skill.*

*(Forged by Skill Genesis in the RGame/Ball-Escape child, 2026-07-30. Corroborated against the official Roblox Creator Hub, the Roblox/creator-docs repository, the Roblox Developer Forum, and the ProfileService reference — sources listed at the foot of this file. RATIFIED by the operator 2026-08-04.)*

When this skill is activated at Gate 0, you must treat server authority, save-data integrity, and receipt idempotency as hard requirements, not as hardening to be added later. On Roblox the client is an attacker-controlled process by default: every LocalScript, every `ReplicatedStorage` module, and every remote name is readable and callable by any player running an exploit executor.

SCOPE LAW: apply only the sections matching what the project actually uses. Section 3 binds only places that monetize; Section 2 binds only places that persist data. Sections 1, 4, and 5 bind every Roblox project.

## 1. Server Authority & the Client Trust Boundary
- **The server is the sole source of truth** for simulation state, rules, progression, currency, and every consequential decision. The client's only jobs are to render and to send *intent*. A client message may say "I want to buy upgrade X"; it may never say "add 500 cash" or "I earned a payout." Any handler that accepts an amount, a price, a score, or a reward value from the client is a defect, not a shortcut.
- **Every argument arriving on a remote is hostile.** The leading `Player` argument is injected by the engine and cannot be spoofed; nothing after it can be trusted. Explicitly type-check and range-check each parameter before use (`if type(id) ~= "string" then return end`), and allowlist against a server-held catalog rather than accepting a client-supplied key blindly.
- **Rate-limit every remote, per player.** Exploiters fire remotes at arbitrary frequency; an unthrottled handler is a denial-of-service surface as well as an economy surface. Track last-call timestamps server-side and drop calls inside the cooldown.
- **Never call `RemoteFunction:InvokeClient()`.** An exploiting client can make the callback yield forever, hanging the calling server thread indefinitely. Use `RemoteEvent:FireClient()` for all server→client messaging; reserve `RemoteFunction` for client→server request/response only.
- **Obfuscation is not a control.** Anything parented under `ReplicatedStorage` is enumerable by every client, and renaming remotes buys minutes. Server-side rejection is the only real defense; never let a design depend on the client not knowing something.
- **On validation failure, log and ignore — do not auto-kick.** Aggressive kicking produces false positives from lag and legitimate edge cases. Reserve kicks and bans for repeated, unambiguous abuse patterns, and record the evidence server-side first.
- **Partition from day one:** authoritative logic and data live in `ServerScriptService`; only genuinely shared definitions go in `ReplicatedStorage`. Retrofitting this boundary after a codebase exists is a rewrite, not a refactor.

## 2. Persistence & DataStore Integrity
- **Use `UpdateAsync`, not `SetAsync`, for any key that two servers could touch.** `UpdateAsync` reads the stored value before writing, so a stale session cannot clobber newer data — this is the single largest cause of mysterious progress rollbacks.
- **Session locking is mandatory** for any place a player can rejoin or teleport into. Write the owning server's `JobId` plus a timestamp into the profile, claim that lock atomically inside the same `UpdateAsync` that reads the data, and refuse to save when the lock is no longer yours. Without it, Server A finishing a late save after Server B has loaded and written will silently erase everything the player did on B.
- **Give locks an expiry.** A lock older than a defined staleness threshold may be force-claimed; otherwise a crashed or hard-killed server locks that player out of their own save permanently.
- **Every DataStore call is wrapped in `pcall` with bounded exponential-backoff retry.** DataStore requests fail routinely under throttling and service degradation; an unguarded call is an unhandled error path.
- **`game:BindToClose()` must flush every active session.** Shutdown is the highest-risk moment for concurrent writes and the most common source of "I lost an hour of progress."
- **Version the key and ship a migration function.** Keys carry an explicit version (`Profile_v1`); loading applies a default-fallback table so a field added after launch is populated, never nil-dereferenced. A schema change without a migration path is a data-loss event scheduled for release day.
- **Never write a raw exponential currency into an `OrderedDataStore`.** Ordered stores are bounded by the signed 64-bit integer range, and idle/incremental economies exceed it routinely. Store a bounded, compressed ranking value (a log-scaled or clamped integer) and keep the true balance in the standard DataStore.

## 3. Monetization Integrity (MarketplaceService)
- **`ProcessReceipt` must be idempotent AND durable.** Roblox re-invokes it for the same `PurchaseId` after network failures, server restarts, and when the player rejoins. Record every granted `PurchaseId` in a **DataStore** — an in-memory table loses its record on restart and double-grants the item while the player is charged once.
- **The check-then-grant sequence must be atomic** via `UpdateAsync`, so a concurrent retry cannot slip between reading "not yet granted" and writing "granted."
- **Return `NotProcessedYet` unless the grant durably persisted.** `PurchaseGranted` is irreversible and consumes the player's Robux; returning it after a failed save takes real money and delivers nothing. When the player is offline or the save failed, `NotProcessedYet` is correct — Roblox will call again.
- **Exactly one `ProcessReceipt` assignment may exist in the entire place.** It is a single callback property, and a second assignment silently replaces the first, disabling every product the first one handled.
- **Use the right idempotency key.** For Developer Product purchases the key is `receiptInfo.PurchaseId`. `TransferRequestId` is a *different* field belonging to the separate `PromptRobuxTransferAsync` flow — the official MarketplaceService page discusses both, and conflating them silently breaks receipt deduplication. Verify which flow you are in before choosing the key.
- **`UserOwnsGamePassAsync` is a yielding network call.** Wrap it in `pcall`, cache the result per session, and never call it inside a loop or per-frame path. Treat a `pcall` failure as "unknown," not as "does not own."

## 4. Luau Discipline & Type Safety
- **`--!strict` at the top of every module**, and Roblox Studio Script Analysis must report zero errors *and* zero warnings. Under the pipeline's warning-equals-failure law, an analysis warning blocks the gate.
- **Annotate boundaries, infer bodies.** Type function parameters, return values, and exported types explicitly; let Luau infer local variables where the inferred shape stays precise. Annotation spam on inferable locals adds maintenance cost without adding safety.
- **Every module returns exactly one table or class and declares no globals.** An implicit global in Luau is a cross-script mutable singleton with no ownership.
- **Never use an untimed `:WaitForChild()`.** Pass an explicit timeout and write an explicit failure path; an infinite wait converts a missing-instance bug into a silent hang that logs one warning and then nothing at all.
- **Narrow before you use.** Data arriving from a remote, a DataStore blob, or `HttpService:JSONDecode` is `any`-shaped until explicitly checked. Validate its type and range at the boundary, then let inner layers trust it.

## 5. Performance, the Task Scheduler & Project Layout
- **Pick the right scheduler phase.** `RenderStepped`/`BindToRenderStep` is client-only, runs before every single frame renders, and must carry *only* camera- and input-coupled work. Gameplay logic that affects physics belongs in `PreSimulation`; reactions to physics results belong in `PostSimulation`. Anything that does not need per-frame resolution belongs on a timer, not on a frame event.
- **Nothing allocates inside a per-frame loop.** No `Instance.new`, no table construction, no closure creation per iteration. Favour stable table shapes and direct field access so the Luau runtime keeps its fast paths; churn shows up as GC pauses, which read to players as stutter.
- **Pool GUI instances.** Creating and destroying `GuiObject`s per frame or per event is the most common cause of frame-time collapse in UI-driven Roblox games. Allocate once, hide and reuse.
- **`src/` on disk is the source of truth; Rojo syncs it into Studio.** `default.project.json` maps folders onto services. Never hand-edit a synced script inside Studio — the next sync overwrites it, and the change is lost with no diff.
- **Pin the toolchain.** Declare the Rojo version in `aftman.toml` (or `rokit.toml`) so every machine and every agent syncing this place uses the same version; an unpinned toolchain makes "works on my Studio" unreproducible.

---
### SOURCES (Skill Genesis, 2026-07-30)
Primary (Roblox official): [Security and cheat mitigation tactics](https://create.roblox.com/docs/scripting/security/security-tactics) · [Implement player data and purchasing systems](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing) · [MarketplaceService reference](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService) · [Task scheduler](https://create.roblox.com/docs/performance-optimization/microprofiler/task-scheduler) · [Roblox/creator-docs performance guidance](https://github.com/Roblox/creator-docs/blob/main/content/en-us/performance-optimization/improve.md) · [Custom leaderboards with ordered data stores](https://create.roblox.com/docs/tutorials/use-case-tutorials/data-storage/create-leaderboard) · [Rojo installation](https://rojo.space/docs/v7/getting-started/installation/)
Corroborating (independent): [Session locking explained — Roblox DevForum](https://devforum.roblox.com/t/session-locking-explained-datastore/846799) · [Keeping your game secure: protecting remotes — Roblox DevForum](https://devforum.roblox.com/t/keeping-your-game-secure-part-1-protecting-remotes/2788472) · [ProcessReceipt duplicate-grant report — Roblox DevForum](https://devforum.roblox.com/t/processreceipt-duplicating-when-buying-dev-product-more-than-once/3186309) · [ProfileService: developer products](https://madstudioroblox.github.io/ProfileService/tutorial/developer_products/) · [OrderedDataStore integer limit — Roblox DevForum](https://devforum.roblox.com/t/ordereddatastoreleaderboard-intlimit/4080554)

## 6. LUAU SYNTAX TRAPS THAT ONLY SURFACE AT RUNTIME
*(Added 2026-08-04 from the Dice Forge Block 1 build. Each cost a Studio round-trip because no headless Luau parser is available to the authoring session.)*

1. **A type annotation is ILLEGAL on a table-field assignment.** `Module.CONST: number = 2.0` and `Module.Map: { [string]: T } = {}` are SYNTAX ERRORS, not type errors — the module fails to load entirely and every dependent test reports "Requested module experienced an error while loading". Annotations are permitted only on `local` declarations and function parameters/returns. To keep the type, annotate a local and bind it: `local MAP: { [string]: T } = {...}` then `Module.Map = MAP`. Verify with `grep -nE '^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_]+[[:space:]]*:[^=]+='` over `src/` before every commit.
2. **Deleting a file from disk does not remove the instance from the place.** Rojo owns only the branches declared in `default.project.json`; instances created by earlier work persist inside the `.rbxl` and keep executing, emitting warnings that pollute every evidence artifact. Retiring a system means deleting its instances in the Explorer as well as its files.
3. **A failing test is not evidence the CODE is wrong.** Identify which side is broken before changing anything. In this build a "drift" failure was the test driving a value below a floor it had itself defined — loosening the tolerance to make it pass would have punched a hole in the invariant the validator exists to protect. See ledger L-017.

4. **`table.create(n)` with no fill value has type `{unknown}`, not `{number}`.** Assigning it to a typed target warns, and *annotating the local does not fix it* — that only makes the mismatch explicit. Supply a fill value (`table.create(n, 0)`, `table.create(n, "")`), or use `{}` where the elements are TABLES, because a fill value there shares ONE table across every slot. Read the warning's COLUMN, not just its line: a column pointing at `table.create` rather than at the variable is what distinguishes the two diagnoses.
5. **`Players.LocalPlayer` is typed `Player?`.** Indexing it directly warns. Narrow it once at the top with a nil check that errors, not with a `:: Player` cast — the cast silences the checker and still indexes nil if the script is ever parented somewhere it does not belong.
6. **`math.clamp(x, min, max)` ERRORS when `min > max`.** Wherever both bounds are derived from data (a catalog, a config, a profile), that is a live crash waiting on a constant change. If the bounds come from tunable data, assert `min <= max` in the test suite so a tuning pass fails at the bench rather than at a player's join.
7. **`#` on a SPARSE array is undefined.** `{[1]=a,[3]=b}` may report 1 or 3. A length check therefore cannot prove a slot is populated; iterate to the expected count and type-check each element before indexing it.
8. **Round-half-up is wrong for splitting a total.** Dividing a budget into `n` equal shares with a round-to-nearest snap makes the shares sum to MORE than the budget. Use a snap-toward-zero variant wherever parts must not exceed the whole, and write the residue direction into the assertion (`sum(parts) <= whole`), never just equality-within-epsilon.

## 7. THE EXECUTABLE CONTRACT PATTERN
*(Promoted from the Dice Forge Block 3 build, 2026-08-07. Five rejections, twelve findings, one circuit-breaker trip. This is the pattern that ended it — see ledger L-025.)*

**A rule that lives as prose in more than one document will be re-derived, and re-derived wrongly, by every fix that touches it.**

Dice Forge's `performSetShape` was wrong three times in three different directions — it confiscated purchased progression, then manufactured it, then inflated it by a rounding residue. Each fix satisfied the complaint in front of it and silently broke a clause nobody had written down, because the rules a die had to satisfy were scattered across two SRS requirements and a code comment. Nothing was thrashing; the *design* was missing.

**The remedy, in order:**
1. **Write the contract as ONE function** returning `(ok, reason)`, listing every clause. Not a comment, not a doc section — a function, so it can be called.
2. **Gate every WRITE on a CANDIDATE**, before any currency or state moves. Checking a candidate rather than the stored result turns a violation into a clean refusal instead of a rollback.
3. **Gate every READ too.** Guarding writes is worth nothing while reads are trusted: data written by an earlier version of the code is still in the database. Validate on load and *repair* rather than quarantine — a record can be illegal through no fault of the user, and repair clamping back into the contract can only ever reduce an illegal advantage.
4. **Assert the contract from the suite after EVERY mutation**, over a fixture sweep, so "did we break a clause this time?" is answered on every run rather than re-derived by the next auditor.
5. **Add new rules to that function**, never inline in a handler. A rule with one documented exception acquires a second.

**The same move applies to call shape.** Declaring every remote's arity in one table and enforcing it centrally in `bind()` closed a defect that no unit test could reach — the suite calls handlers directly and never crosses a RemoteFunction.

**The tell that you need this:** the same function is fixed twice in opposite directions. That is not bad luck and not a careless author; it is an unwritten contract being guessed at.

## 8. VERIFICATION INTEGRITY ON THIS PLATFORM
*(Dice Forge Blocks 1–3. Every line here was bought with a false green or a false alarm.)*

- **Studio Script Analysis (P-1) is NOT substitutable by the unit suite and must never be skipped.** It catches what no test can reach: a call to a function that does not exist in a module nothing requires. A gate declared clean on the suite alone shipped exactly that. It is also not exposed to any MCP tooling — a human reads the panel.
- **The assertion COUNT is the sync canary.** Record it before a change; require it to move by the expected delta after. A green suite at an unchanged count has run over stale code (ledger L-019, L-020).
- **Verify sync BEFORE pressing Play, not after.** Read a marker your change introduced out of the live DataModel first. A green result is only evidence if you established beforehand that the runtime held the new code.
- **The place file is a SUPERSET of the repository.** Rojo syncs disk *into* Studio; it never removes what disk never put there. Every prohibition grep must also sweep the live DataModel for `LuaSourceContainer`s outside the managed folders — a retired script assigning `ProcessReceipt` survived every repository-side check because it existed only in the `.rbxl` (ledger L-023).
- **MCP `execute_luau` does not share the running VM's module cache.** Each call re-requires and gets a fresh instance, so every module-level state container reads as EMPTY. It is valid for pure evaluation and DataModel/`Source` reads, and INVALID for inspecting live service state — it will confidently report an empty session table and look exactly like a fail-open (ledger L-022).
- **Cross the wire in at least one test.** Handlers called directly never exercise arity, serialisation, or the gateway. A real client invoking a real remote found a contract violation five audit rounds had missed.

## 9. PARALLEL CONSTRUCTION ON THIS PLATFORM -- measured, not assumed
*(Dice Forge Blocks 4B/4C, 2026-08-07. One swarm run: 3 workers, 7 modules, 5,236 lines of client code in roughly 25 minutes, then 7 verifiers returning 6 REJECTED / 1 APPROVED and 47 findings.)*

- **Parallel construction is genuinely fast and does not reduce the verification cost at all.** The fan-out compressed days of typing into minutes; the findings still had to be read, reproduced and fixed one at a time. Plan the schedule around verification -- authoring stopped being the bottleneck the moment the swarm existed.
- **Make the work disjoint BEFORE claiming it is.** Seven view modules sharing one palette sentence and one registration array are not disjoint. Writing `UITheme` and the module list first, as serial work, is what converted a nominal split into a real one. Without it, three workers produce three different maroons and every panel individually satisfies the requirement.
- **A worker that reports a cross-block need instead of fixing it is the whole discipline.** All seven of this run's integration items arrived as reports, not edits -- including on the highest-risk file, where the worker duplicated a server function rather than reach outside its block, and said so.
- **NEVER COMMIT DURING AN ACTIVE FAN-OUT.** A commit taken on one agent's completion notification captures whatever is on disk for the others, and a half-written file produces a diff that looks entirely normal. A worker noticed it, not the orchestrator. Wait for every agent to report, then commit once.
- **Isolated contexts converging on the same finding is the strongest signal available.** Three workers independently reported the same missing event; four verifiers independently reported the same shared-module divergence. One agent flagging something may be a misreading; several isolated ones cannot be.
- **Verifiers cannot run the toolchain.** Every one reported honestly that no Luau analyser, linter or headless runtime exists in the workspace, so their Gate 2 was UNVERIFIED and their findings were source-derived. Their value is cognitive, not mechanical: P-1 and the suite still have to be run by whoever can actually run them, and a verifier saying AUDIT-APPROVED never means the code was executed.
