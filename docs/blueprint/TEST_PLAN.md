CONSUMED-BY: Gate 2 / Matrix C
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# TEST PLAN — DICE FORGE INCREMENTAL

Gate 2's mechanical pass executes this document. Every procedure names its literal steps and its output artifact, so an agent or operator can run it without inferring intent. *(Written this way deliberately: ledger L-014 established that a referenced instruction gets partially executed while an enumerated one gets executed.)*

**Verification path for this project:** this Claude session **authors** tests; no Roblox MCP server is connected, so it cannot execute them. The operator's Antigravity session or the operator executes them in Studio and returns **verbatim** output. A step not performed is recorded as not performed — never as a pass.

---

## 1. HARNESS CONTRACT

Every test module returns:

```lua
return {
    name = "UT-1 ForgeMath",
    run = function(): (boolean, string?, number)
        -- returns: passed, failureMessage, assertionCount
    end,
}
```

`tests/RunAll.server.luau` is a **Script** (not a ModuleScript). It:
1. `require`s every `*.test` module under `ServerScriptService.Tests`, wrapping each `require` in `pcall`;
2. reports a module that fails to load as a **FAILURE**, never skipping it silently — *the previous project shipped a suite that could not load and nobody noticed*;
3. runs each suite, printing `[PASS] <name> (<n> assertions)` or `[FAIL] <name>: <message>`;
4. terminates with exactly `=== SUITE COMPLETE: X passed, Y failed ===`.

`tests/Fakes.luau` provides injectable fakes for DataStoreService, MarketplaceService, Players, and ProfileStore, so **no unit test touches a live Roblox service.**

---

## 2. PROCEDURES

### P-1 — Static analysis
1. Open the place in Studio with Rojo connected.
2. **View → Script Analysis.**
3. Copy the **entire** panel, including the count line, even if zero.
4. Save to `deliveries/evidence/<date>-static-analysis.txt`.

**PASS = zero errors AND zero warnings.** A warning is a gate failure under Global Pipeline Law 5, not a nit. Do not filter any line.

**P-1 IS NOT OPTIONAL AND NOT SUBSTITUTABLE.** No Gate 2 verdict may be issued without `deliveries/evidence/<date>-static-analysis.txt` on disk. Amended 2026-08-06, triggering fact: a Block 3 Gate 2 was declared `MECHANICALLY-CLEAN` on P-2 and P-3 alone, with no P-1 artifact. `--!strict` analysis would have flagged the call to a nonexistent `ElementCatalog.getElement` immediately; the unit suite could not, because no suite required the module. **A missing evidence file is a missing procedure, and a missing procedure is a REJECTED gate — never a pass with a caveat.**

### P-2 — Automated suite
1. Press **Play Solo** (F5). Open **View → Output**.
2. Wait for `=== SUITE COMPLETE: X passed, Y failed ===`.
3. Copy the **entire** Output panel — every line, including warnings and tracebacks.
4. Save to `deliveries/evidence/<date>-unit-suite.txt`.

**PASS = `failed` is 0 AND every suite that EXISTS at this point in construction ran.** At the final pre-launch sweep the count must equal the full §4 + §5 set (13 unit + 5 integration = 18); mid-construction it must equal the suites written so far, enumerated by name in the gate record. A suite that exists on disk but is absent from the run is a failure, not a pass — that is a sync fault, and it has produced a false green on this project twice.

**AND the total assertion count must have MOVED by the delta the construction step predicted.** A suite reporting `X passed, 0 failed` at an *unchanged* assertion count has run over stale code — twice on this project a dead Rojo sync produced exactly that (ledger L-019, L-020). The assertion count is the sync canary; a green result without a moved count is not evidence.

### P-3 — Static prohibition grep
Run from the repo root and paste the output verbatim into `deliveries/evidence/<date>-prohibitions.txt`:

```bash
grep -rn "InvokeClient"           src/ | grep -v "^$"   # threat T-8  — MUST be empty
grep -rn "ProcessReceipt"         src/                  # threat T-17 — MUST be exactly 1 line
grep -rn "SetAsync"               src/                  # threat T-11 — MUST be empty for profile data
grep -rn "MessagingService" src/ --exclude-dir=Vendor   # V1 scope — MUST be empty (risk R-8).
# Vendor/ is excluded deliberately: ProfileStore uses MessagingService internally for
# session-conflict resolution. R-8 excludes it as a GAMEPLAY mechanism, not as library
# internals. Our own code using it still fails this check.
grep -rnE "TODO|FIXME|TBD"        src/                  # Matrix B    — MUST be empty
```

**EVERY TEXT CHECK MUST STRIP COMMENT LINES BEFORE MATCHING.** Amended 2026-08-07, triggering fact: the Block 4A sweep reported a `:: Player` cast violation, and the match was the source comment *explaining why a cast must not be used*. A grep that trips on the documentation of its own rule punishes writing the rule down, and the reflex fix — deleting the comment — destroys the explanation instead of the defect. Pipe through `grep -vE '^[[:space:]]*--'` first.

**PASS = each line matches its stated expectation.** These are silent-failure classes: nothing at runtime tells you a second `ProcessReceipt` assignment overwrote the first.

**P-3 MUST ALSO SWEEP THE LIVE DATAMODEL, not only `src/`.** Amended 2026-08-06, triggering fact: `ServerScriptService.MonetizationManager` — a leftover from the retired tycoon project, present in the `.rbxl` place file but in no Rojo-managed directory — was found assigning `MarketplaceService.ProcessReceipt`, holding its receipt ledger in memory only, and returning `PurchaseGranted` before anything persisted (threats T-15, T-16, T-17). **Every grep in this procedure scans the repository, so not one of them could ever have seen it.** Rojo syncs disk *into* Studio; it does not remove what disk never put there. Enumerate every `LuaSourceContainer` in the place, flag any whose full name falls outside `ServerScriptService.Server`, `ServerScriptService.Tests`, or `ReplicatedStorage.Shared`, and re-run each prohibition check against those sources too. An unmanaged script in the place is untracked, unreviewed, and unversioned — treat its presence as a finding in its own right.

### P-4 — Runtime smoke
Press **Play Solo** and work down this table, noting any row that misbehaves.

| # | Action | Expected |
|---|---|---|
| 1 | Observe the arena | Low-poly 3D die visible in a contained pit, top-down |
| 2 | Press ROLL | Die tumbles, settles, payout floats, Cash rises |
| 3 | Press ROLL ten times | No errors; Cash monotonically rises; streak counter tracks |
| 4 | Open the Forge | Per-face mass, value, landing probability, and Void probability all shown |
| 5 | Move mass onto one face, commit | Preview matched the result; Cash deducted; die visibly heavier on that face |
| 6 | Roll twenty times | The heavier face demonstrably lands **less** often |
| 7 | Force a Void landing | Streak visibly resets |
| 8 | Toggle AUTO | Rolls fire at the server interval and stop cleanly on toggle-off |
| 9 | Open all four right-sidebar menus | Each renders, none errors |
| 10 | Resize narrow → wide | No clipping, no overlap, nothing off-screen |
| 11 | Leave and rejoin | Cash, dice, and mass layouts all restored exactly |

Save the **entire** Output panel to `deliveries/evidence/<date>-smoke.txt`.
**PASS = every row observed AND zero errors/warnings across the whole run.**

---

## 3. COVERAGE MAP

| Area | Suites |
|---|---|
| Forge maths | UT-1, UT-2 |
| Outcome sampling & payout | UT-3, UT-4 |
| Boundary validation | UT-5, UT-6 |
| Forge application | UT-12 |
| Client boundary | UT-13 |
| Persistence | UT-7, UT-8 |
| Monetization | UT-9 |
| Leaderboard | UT-10 |
| Offline vault | UT-11 |
| End-to-end | IT-1 … IT-5 |

---

## 4. UNIT SUITES

| ID | File | Asserts |
|---|---|---|
| **UT-1** | `tests/ForgeMath.test.luau` | `landingProbabilities` sums to 1.0 for every shape; `P ∝ (M−m)` holds; a heavier face has strictly lower probability; `faceValue` is superlinear (gain from 2m→3m exceeds m→2m); flat distribution gives uniform probabilities. |
| **UT-2** | `tests/ForgeValidation.test.luau` | Rejects: wrong array length, negative mass, mass below floor, sum ≠ budget, **`NaN`**, `math.huge`, `-math.huge`. **Asserts finiteness is checked BEFORE the sum** by submitting `NaN` in an otherwise-valid distribution and confirming rejection (threat T-25). Confirms a rejected proposal mutates nothing. |
| **UT-3** | `tests/Sampling.test.luau` | Over 100k seeded samples, empirical face frequency matches `P ∝ (M−m)` within tolerance; a fixed seed reproduces exactly; every face count 4/6/8/12/20 sums to 1.0. |
| **UT-4** | `tests/Payout.test.luau` | Payout = `Σ faceValue × elements × streak × boosts`; streak multiplier is `(1+b)^s`, capped; Void resets the streak to 0; Bad Roll Shield prevents exactly one break then enters cooldown. |
| **UT-5** | `tests/Elements.test.luau` | Gold pays **only** when ≥2 dice land Gold; its payoff **scales with combined invested mass** (SRS FR-4.3 — a flat conditional bonus is a defect, assert the scaling explicitly); Fire spills to other dice; Freeze re-rolls and keeps the better; Multiplier multiplies the total rather than adding. **Every element resolves from the resolved face set alone, with no positional input.** |
| **UT-6** | `tests/RateLimit.test.luau` | Token buckets enforce §2.2 sustained and burst rates per remote; over-budget calls are dropped and counted; buckets refill; one player's exhaustion does not affect another's. |
| **UT-7** | `tests/ProfileSchema.test.luau` | An empty table reconciles to the full template with every field defaulted; a v0 profile migrates to v1 with no data loss; a profile missing `Dice` gets a valid starting die; an unmigratable profile is quarantined and **not** overwritten. |
| **UT-8** | `tests/ProfileLifecycle.test.luau` | A failed load **fails closed** and never returns a default profile; a foreign live lock fails closed; a **released** profile rejects every write (SRS FR-14.7); the payload ceiling refuses an oversized save (threat T-13); `PurchaseIds` evicts at 200 in insertion order. |
| **UT-9** | `tests/Receipt.test.luau` | The same `PurchaseId` grants **exactly once** across repeated calls; a restart with a persisted id still refuses (proving the ledger is in the DataStore, not memory — threat T-15); a failed save returns `NotProcessedYet`, never `PurchaseGranted` (threat T-16); an unknown product fails closed; player-offline returns `NotProcessedYet`. |
| **UT-10** | `tests/Leaderboard.test.luau` | The log-scale transform is monotonic across 0 → 1e300; the result stays within the signed 64-bit bound at `raw = 1e300` (threat T-20); ordering matches raw ordering; `GetSortedAsync` is called at most once per interval regardless of request volume. |
| **UT-11** | `tests/Vault.test.luau` | `earnings = min(elapsed, capacity) × rate × efficiency`; **negative elapsed credits exactly zero** (threat T-23); elapsed clamps at capacity; claiming consumes the vault so a second claim yields zero (threat T-24); the 2× receipt is bound to its `AccrualId` and cannot be replayed against a later window. |
| **UT-12** | `tests/Forge.test.luau` | Forge cost scales with the **magnitude of mass moved** and is non-trivial (FR-3.3); a rejected proposal leaves the distribution, the budget **and** Cash byte-identical (FR-3.2); an unknown or **locked** element id is refused (FR-4.1, threat T-5); a shape change **carries the purchased mass budget and the assigned elements across** rather than confiscating them (FR-6.1), and the resulting die is immediately forgeable because its faces sum to its stored budget. |
| **UT-13** | `tests/ClientContract.test.luau` | The client module LOADS (the assertion whose absence let a call to a nonexistent function ship); one `NetClient` wrapper exists per remote in `Remotes.Fn` and one subscription per event in `Remotes.Ev`; **no generic `invoke`/`fire`/`send`/`call`/`request` escape hatch**; every remote has a declared server-side arity; `readyIn` answers for a known and an unknown remote; `awaitReady` REFUSES to run off-client rather than reporting a false ready. |

> **UT-13 amendment, 2026-08-07.** Triggering fact: `NetClient` and `ClientBootstrap` were built, statically cleaned, hand-tested over the wire and audited as secondary scope — and required by **no suite at all**. That is precisely the property UT-12's header names as the reason a call to a nonexistent function survived a clean gate.
>
> **Scope split, learned the hard way.** A first draft asserted structural rules by reading `ScriptInstance.Source` and failed at runtime: `Source` requires `PluginOrOpenCloud` capability, which a game script does not have. The rules were correct and misplaced. **Anything provable only from the TEXT belongs in P-3**, which greps the repository from disk — sole-boundary enforcement, forbidden parameter names, the fatal path. **Anything provable from the LOADED MODULE belongs here.**

> **UT-12 amendment, 2026-08-06.** Triggering fact: `ForgeService` shipped calling `ElementCatalog.getElement`, an accessor that has never existed — every element assignment would have crashed. It passed a `MECHANICALLY-CLEAN` Gate 2 and a zero-finding cross-vendor Gate 3/4 because **no suite required the module** (the forge was covered only at integration level in IT-2, three blocks later) and **procedure P-1 was never run**. A service module that no suite requires is a module whose symbols are never resolved. UT-12 closes that gap at unit level; IT-2 still runs in Block 6 and is not replaced by it.

---

## 5. INTEGRATION SUITES

| ID | File | Scenario |
|---|---|---|
| **IT-1** | `tests/Integration_RollLoop.test.luau` | Full roll: intent in → sample → elements → streak → credit → `RollResult` out. Asserts Cash is credited **before** the event fires, and that a dropped/never-delivered `RollResult` leaves the credit intact (SRS FR-2.6). |
| **IT-2** | `tests/Integration_Forge.test.luau` | Valid proposal: cost deducted, distribution stored, subsequent sampling reflects the new masses. Invalid proposal: `ok=false`, and **both** budget and Cash byte-identical to before. |
| **IT-3** | `tests/Integration_SessionLock.test.luau` | Server A holds the lock; server B's load **fails closed** and serves no default. A releases; B loads and sees A's data. A stale lock is force-claimable. A's write after losing the lock is refused. |
| **IT-4** | `tests/Integration_Authority.test.luau` | **The adversarial suite.** Attempts to mutate Cash through every service other than `EconomyService` and asserts the balance is unchanged in each case. Attempts every inbound remote with a spoofed economic parameter (price, amount, face, duration, multiplier) and asserts each is rejected with no state change. Asserts no remote in §1.1 accepts such a parameter at all. |
| **IT-5** | `tests/Integration_Ascension.test.luau` | Ascend grants Diamonds proportional to lifetime earnings; Cash, face layouts and Cash-upgrades reset; **Diamonds and the Diamond tree survive**; below-threshold ascension is refused; Streak Strength purchased pre-ascension still applies after. |

---

## 6. KNOWN COVERAGE GAPS
Stated rather than hidden.

- **NFR-1/NFR-2 performance targets are not unit-testable.** Frame budget and per-player server cost need Studio's MicroProfiler under load. Deferred to a construction-phase performance pass; **not** claimed as covered.
- **Real Robux purchase flows cannot be tested without live asset ids (U-1).** UT-9 exercises `ProcessReceipt` against a faked MarketplaceService. The live path needs a real test purchase before launch.
- **Cross-server behaviour is out of scope for V1** (risk R-8) and therefore untested. IT-3 covers session locking with simulated servers, not genuine multi-server contention.
- **The forge preview's visual accuracy** (SRS FR-3.4) is asserted numerically in UT-1 but its rendering is only checked by eye in P-4 row 4.
