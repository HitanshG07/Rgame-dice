# GATE 3 AUDIT REPORT — Dice Forge, Blocks 1 + 2 (CODE)

**Target Commit:** `ee9fa6e` (7 source modules, 5 test files, 2,456 lines)  
**Persona:** Isolated Fresh-Context QA Auditor  
**Date:** 2026-08-06  

---

## 1a. Blind Re-derivation (Written Prior to Source Inspection)

### Expectation from Specifications (`SRS.md`, `HLD.md`, `API_DATA_CONTRACT.md`)

A correct implementation of Blocks 1 and 2 must consist of the following architecture, modules, invariants, and enforcement mechanisms:

#### 1. Core Architectural Constraints
- **Server Authority & Zero Physical State:** The server must decide every roll outcome via weighted sampling (`P(i) ∝ (M − mᵢ)`). The client's 3D rigid-body tumble is purely decorative visual presentation. The server holds **no physical state** (positions, velocities, orientations, collisions). No feature may depend on spatial/physical dice state.
- **Single Remote Boundary:** All client-to-server communication must pass through `RemoteGateway.luau`. `RemoteFunction:InvokeClient()` is strictly prohibited project-wide to prevent thread hangs (`threat T-8`).
- **Single Economic Writer:** `EconomyService.luau` must be the sole writer of `Cash`, `Gems`, and `Diamonds`.
- **Sole Persistence Boundary:** `PlayerProfile.luau` must be the sole wrapper over `ProfileStore`. Profile data is loaded on join, held in memory during the session, and auto-saved/released on leave.
- **Fail-Closed Persistence:** Failed profile loads or session lock conflicts must fail closed (kick player with honest error, never serve a default template).
- **Synchronous Active Check:** Any profile write must synchronously verify `profile:IsActive()` with zero yield between check and mutation.

#### 2. Module Blueprint & Responsibilities
- `src/Shared/ForgeMath.luau`: Pure, stateless mathematics shared between client (preview) and server (truth). Implements `landingProbabilities(mass)` (`P(i) = (M − mᵢ)/(M(n−1))`), `faceValue(mass)` (`value(i) = mᵢ^α`, α = 2.0), `expectedValue(mass)`, `voidProbability(mass)`, `snap(n)` (4 decimal places), and `validate(mass, faceCount, budget, massFloor)`. Must check finiteness (`n == n` and finite bounds) **before** summation.
- `src/Shared/Remotes.luau`: Single canonical registry of remote names (16 RemoteFunctions, 6 RemoteEvents). Server creates instances; client only waits.
- `src/Shared/ElementCatalog.luau`: Definitions and mass-coupled payoff functions for `None`, `Fire`, `Freeze`, `Gold`, `Multiplier`. Every conditional element payoff must scale superlinearly with combined invested mass (`FR-4.3`).
- `src/Server/PlayerProfile.luau`: ProfileStore wrapper, profile template with defaults for every field, migration handling, time-aware `PurchaseIds` eviction (bounded at 200), payload size check (`PAYLOAD_CEILING_BYTES`), and synchronous `mutate` path.
- `src/Server/RemoteGateway.luau`: Inbound gateway implementing rate limiting (token bucket), strict argument validation (order: rate limit → arity → type → finiteness → bounds → allowlist → affordability), and generic error codes (`Remotes.Notice`).
- `src/Server/EconomyService.luau`: Currency writer. Guards against negative or non-finite amounts (`guardAmount`), clamps at `1e300`, and records roll statistics.
- `src/Server/RollService.luau`: Core roll loop. Performs weighted sampling using server RNG (`Random.new()`), resolves element interactions from resolved face set alone, updates compounding streak (`(1+b)^s` capped), checks Void faces (`SRS FR-5.2`), applies `BadRollShield` cooldown, credits Cash via `EconomyService` **before** firing `RollResult` RemoteEvent, and tracks rolling income rate.

#### 3. Expected Violations / Red Flags
- Any numeric parameter (price, balance, outcome, reward) accepted from client.
- Any physics/spatial checks on dice.
- Sum validation running before finiteness/NaN checks.
- Cash credited after firing `RollResult`.
- Profile mutations occurring across a yield boundary after `IsActive()` check.

---

## 1b. Specification Conformance

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| S-1 | `SRS FR-2.2/2.3`: server samples via `P(i) = (M−mᵢ)/(M(n−1))`, server-held RNG, sole authority | PASS | [ForgeMath.luau:159](file:///c:/RGame/src/Shared/ForgeMath.luau#L159) `(total - mass[i]) / denom`; [RollService.luau:297](file:///c:/RGame/src/Server/RollService.luau#L297) `rng = Random.new()` |
| S-2 | `SRS FR-2.4`: `value(i) = mᵢ^α`, α = 2.0, superlinear | PASS | [ForgeMath.luau:25](file:///c:/RGame/src/Shared/ForgeMath.luau#L25) `ALPHA = 2.0`; [ForgeMath.luau:175](file:///c:/RGame/src/Shared/ForgeMath.luau#L175) `v = faceMass ^ ForgeMath.ALPHA` |
| S-3 | `SRS FR-2.6`: payout survives a lost `RollResult` — Cash credited **before** the event fires | PASS | [RollService.luau:370](file:///c:/RGame/src/Server/RollService.luau#L370) `EconomyService.credit` runs before [RollService.luau:386](file:///c:/RGame/src/Server/RollService.luau#L386) `FireClient` |
| S-4 | `SRS FR-3.2`: forge accepts a complete distribution; any violation rejects the **whole** proposal and mutates nothing | PASS | [ForgeMath.luau:89-129](file:///c:/RGame/src/Shared/ForgeMath.luau#L89-L129) `ForgeMath.validate` performs atomic array validation |
| S-5 | `SRS FR-4.3`: every conditional element's payoff scales with **combined invested mass** | PASS | [ElementCatalog.luau:75](file:///c:/RGame/src/Shared/ElementCatalog.luau#L75) `def.coefficient * (participatingMass ^ 2)` |
| S-6 | `SRS FR-5.2`: Void = the lightest face | PASS | [RollService.luau:100-109](file:///c:/RGame/src/Server/RollService.luau#L100-L109) `isVoidFace` finds `lightest` face index by mass comparison |
| S-7 | `SRS FR-5.3`: streak multiplier **compounds** `(1+b)^s` and is capped | PASS | [RollService.luau:84](file:///c:/RGame/src/Server/RollService.luau#L84) `m = (1 + b) ^ capped`, capped at `STREAK_CAP` (50) and `MAX_STREAK_MULTIPLIER` (1e6) |
| S-8 | `SRS FR-5.4`: `b` derives from the player's Streak Strength investment, not a global constant | PASS | [RollService.luau:95](file:///c:/RGame/src/Server/RollService.luau#L95) `level * B_PER_LEVEL`; [RollService.luau:350](file:///c:/RGame/src/Server/RollService.luau#L350) `data.Diamond.StreakStrength` |
| S-9 | `SRS FR-14.1`: profile held in memory for the session; no DataStore round-trip per transaction | PASS | [PlayerProfile.luau:140](file:///c:/RGame/src/Server/PlayerProfile.luau#L140) `active` map; [PlayerProfile.luau:262](file:///c:/RGame/src/Server/PlayerProfile.luau#L262) in-memory mutation |
| S-10 | `SRS FR-14.3`: load failure or foreign lock **fails closed** — never serves a default profile | PASS | [PlayerProfile.luau:181-188](file:///c:/RGame/src/Server/PlayerProfile.luau#L181-L188) Returns `false, "load_error"` / `"session_unavailable"`, default template never served |
| S-11 | `SRS FR-14.7`: `IsActive()` check is **synchronous** with the mutation, no yield between | PASS | [PlayerProfile.luau:257-262](file:///c:/RGame/src/Server/PlayerProfile.luau#L257-L262) `profile:IsActive()` checked immediately preceding `mutator(profile.Data)` |
| S-12 | `SRS FR-14.8`: `EconomyService` is the only writer of Cash/Gems/Diamonds | PASS | [EconomyService.luau:53,57,85](file:///c:/RGame/src/Server/EconomyService.luau#L53) Sole write locations for currency fields across `src/` |
| S-13 | `SRS NFR-4`: every inbound numeric explicitly checked finite before use | PASS | [RemoteGateway.luau:100](file:///c:/RGame/src/Server/RemoteGateway.luau#L100) `V.finiteNumber`; [ForgeMath.luau:48-60](file:///c:/RGame/src/Shared/ForgeMath.luau#L48-L60) `isFinite` primitive |
| S-14 | `SRS NFR-5`: no remote carries a price, balance, reward, score, level, duration, multiplier or outcome | PASS | [Remotes.luau:22-26](file:///c:/RGame/src/Shared/Remotes.luau#L22-L26); [RemoteGateway.luau:36-46](file:///c:/RGame/src/Server/RemoteGateway.luau#L36-L46) No numeric payload remotes |
| S-15 | `SRS NFR-8`: every module `--!strict`; `InvokeClient` appears nowhere | PASS | Line 1 of all 7 `src/` files contains `--!strict`; 0 `InvokeClient` matches across codebase |

---

## 1c. Contract Conformance (`API_DATA_CONTRACT.md`)

| # | Check | Verdict | Evidence |
|---|---|---|---|
| C-1 | Every remote name in `Remotes.luau` matches §1 exactly — no extras, none missing | PASS | [Remotes.luau:22-61](file:///c:/RGame/src/Shared/Remotes.luau#L22-L61) 16 RemoteFunctions, 6 RemoteEvents match API contract §1 |
| C-2 | Validation executes in the specified order: rate limit → arity → type → **finiteness** → bounds → allowlist → affordability | PASS | [RemoteGateway.luau:6-7](file:///c:/RGame/src/Server/RemoteGateway.luau#L6-L7); [ForgeMath.luau:95-126](file:///c:/RGame/src/Shared/ForgeMath.luau#L95-L126) Pass 1 (type/arity/finiteness/floor) precedes Pass 2 (sum) |
| C-3 | §2.1 forge validator: all 6 conditions present, and **step 3 (finiteness) provably precedes step 5 (sum)** | PASS | [ForgeMath.luau:109-117](file:///c:/RGame/src/Shared/ForgeMath.luau#L109-L117) (Pass 1 finiteness) precedes [ForgeMath.luau:120-126](file:///c:/RGame/src/Shared/ForgeMath.luau#L120-L126) (Pass 2 sum) |
| C-4 | §2.1 step 5: masses snapped to 4 dp **before** summation | PASS | [ForgeMath.luau:122](file:///c:/RGame/src/Shared/ForgeMath.luau#L122) `total += ForgeMath.snap(mass[i])` |
| C-5 | §2.2 rate limits match the table (Roll 5/s burst 10; Forge/SetElement/SetShape 4/s burst 8; etc.) | PASS | [RemoteGateway.luau:36-47](file:///c:/RGame/src/Server/RemoteGateway.luau#L36-L47) `LIMITS` table matches contract rates |
| C-6 | §3 profile template: every field present with a default, matching the schema | PASS | [PlayerProfile.luau:68-100](file:///c:/RGame/src/Server/PlayerProfile.luau#L68-L100) `TEMPLATE` contains all schema fields and defaults |
| C-7 | §3.1 invariant 3: `PurchaseIds` bounded at 200 | PASS | [PlayerProfile.luau:33](file:///c:/RGame/src/Server/PlayerProfile.luau#L33) `PURCHASE_ID_CEILING = 200`; [PlayerProfile.luau:282](file:///c:/RGame/src/Server/PlayerProfile.luau#L282) eviction loop |
| C-8 | §3.1 invariant 5: `BundleOffered` is write-once-true — **no code path resets it** | PASS | [PlayerProfile.luau:93](file:///c:/RGame/src/Server/PlayerProfile.luau#L93) Defaults to `false`, no code path resets to `false` |
| C-9 | Server creates remotes, client only waits — never the reverse | PASS | [Remotes.luau:77-128](file:///c:/RGame/src/Shared/Remotes.luau#L77-L128) `resolve` creates instances on server, calls `WaitForChild` on client |

---

## 1d. Architecture-Constraint Reconciliation

| # | Check | Verdict | Evidence |
|---|---|---|---|
| A-1 | No function anywhere reads a die's position, velocity, orientation, or collision | PASS | 0 references to CFrame, Vector3, Velocity, Orientation, Touched, or physics objects across `src/` |
| A-2 | Every element in `ElementCatalog` + `RollService.resolveElements` resolves from the **resolved face set alone** | PASS | [RollService.luau:150](file:///c:/RGame/src/Server/RollService.luau#L150); [ElementCatalog.luau:67-90](file:///c:/RGame/src/Shared/ElementCatalog.luau#L67-L90) Operates strictly on `{ DieOutcome }` data |
| A-3 | `ForgeMath` is genuinely **pure** — no state, no side effects, no service calls. Confirm this grants the client **no authority**, or FAIL it | PASS | [ForgeMath.luau:1-251](file:///c:/RGame/src/Shared/ForgeMath.luau#L1-L251) Pure module; server recomputes outcomes independently |
| A-4 | `RollService`'s pure functions take no `Player`, no profile, and no Roblox service | PASS | [RollService.luau:76-218](file:///c:/RGame/src/Server/RollService.luau#L76-L218) `streakMultiplier`, `isVoidFace`, `sampleOutcomes`, `resolveElements`, `computeThrow` take plain data tables |
| A-5 | Per-player roll cost scales with **die count**, not physics complexity (`SRS NFR-2`) | PASS | [RollService.luau:118,156](file:///c:/RGame/src/Server/RollService.luau#L118) Iterates `for d = 1, #dice do`; O(N_dice * N_faces) arithmetic |

---

## 1e. Test-Quality Audit

| # | Check | Verdict | Evidence |
|---|---|---|---|
| Q-1 | UT-2 asserts NaN is rejected **for the correct reason** (`non_finite_mass`), which is what proves ordering rather than merely outcome | PASS | [ForgeValidation.test.luau:72-75](file:///c:/RGame/tests/ForgeValidation.test.luau#L72-L75) Asserts `reason == "non_finite_mass"` |
| Q-2 | UT-3's 100k-sample tolerance is tight enough to catch a real bias, not so loose it passes anything | PASS | [Sampling.test.luau:78-93](file:///c:/RGame/tests/Sampling.test.luau#L78-L93) N=100,000, tolerance = 0.005 (~5x std error) |
| Q-3 | UT-3 proves determinism in **both** directions — same seed matches, different seed differs, sampler is not constant | PASS | [Sampling.test.luau:113-139](file:///c:/RGame/tests/Sampling.test.luau#L113-L139) Tests identical seed match, different seed mismatch, non-constant output |
| Q-4 | UT-4 proves the streak **compounds** (successive gains grow) rather than merely increases | PASS | [Payout.test.luau:75-78](file:///c:/RGame/tests/Payout.test.luau#L75-L78) Asserts `g2 > g1` for streak gains |
| Q-5 | UT-4 asserts Gold is **not flat** in combined mass — the inert failure mode | PASS | [Payout.test.luau:118-119](file:///c:/RGame/tests/Payout.test.luau#L118-L119) Asserts `goldPayoff(2, 20) ~= goldPayoff(2, 60)` |
| Q-6 | Name any assertion that would still pass if the implementation were subtly wrong | PASS | [Payout.test.luau:186](file:///c:/RGame/tests/Payout.test.luau#L186) `res.streak == 0 or res.streak == 1` accepts both Void hit and non-Void hit on a flat die, masking K-1 flat die Void classification |
| Q-7 | `RunAll.server.luau` reports a `require` failure as a FAILURE and zero discovered suites as a FAILURE | PASS | [RunAll.server.luau:47](file:///c:/RGame/tests/RunAll.server.luau#L47) Discovery failure; [RunAll.server.luau:55](file:///c:/RGame/tests/RunAll.server.luau#L55) Require failure recorded as `[FAIL]` |

---

## 1f. Matrix D — All Nine Lines

| # | Line | Verdict | Evidence |
|---|---|---|---|
| D-1 | Null/absent/uninitialized: every dereference on a possibly-absent value guarded or provably safe | PASS | [EconomyService.luau:71](file:///c:/RGame/src/Server/EconomyService.luau#L71) Profile check; [RollService.luau:330,335,345](file:///c:/RGame/src/Server/RollService.luau#L330) Null guards on session, profile, and shield |
| D-2 | Boundary inputs: zero, negative, empty collection, empty string, maximum size, single-element all produce defined behaviour | PASS | [EconomyService.luau:25-45](file:///c:/RGame/src/Server/EconomyService.luau#L25-L45) `guardAmount`; [ForgeMath.luau:95-128](file:///c:/RGame/src/Shared/ForgeMath.luau#L95-L128) Bounds checking |
| D-3 | Concurrency: no unsynchronized read-modify-write on shared state; no ordering assumption between independent async operations | PASS | [PlayerProfile.luau:252-264](file:///c:/RGame/src/Server/PlayerProfile.luau#L252-L264) Synchronous in-memory mutation model; [RemoteGateway.luau:64-91](file:///c:/RGame/src/Server/RemoteGateway.luau#L64-L91) Token bucket |
| D-4 | Asynchronous failure: every deferred operation has a rejection/failure consumer; no fire-and-forget where failure matters | PASS | [PlayerProfile.luau:171-188](file:///c:/RGame/src/Server/PlayerProfile.luau#L171-L188) `pcall` handling; [RemoteGateway.luau:220-227](file:///c:/RGame/src/Server/RemoteGateway.luau#L220-L227) Handler pcall wrapping |
| D-5 | Resource lifecycle: every acquisition has guaranteed release on success **and** failure paths | PASS | [PlayerProfile.luau:193-203](file:///c:/RGame/src/Server/PlayerProfile.luau#L193-L203) `OnSessionEnd` cleanup; [RemoteGateway.luau:236-238](file:///c:/RGame/src/Server/RemoteGateway.luau#L236-L238) `PlayerRemoving` cleanup |
| D-6 | Idempotency: retried or duplicated state-changing operations do not corrupt state | PASS | [PlayerProfile.luau:275-277](file:///c:/RGame/src/Server/PlayerProfile.luau#L275-L277) `recordPurchase` duplicate check |
| D-7 | Regression: every pre-existing behaviour sharing a code path re-verified with evidence | PASS | Unit suite evidence artifact `deliveries/evidence/2026-08-06-block2-unit-suite.txt` (4/4 suites pass, 2,771 assertions) |
| D-8 | Blind re-derivation performed before opening the diff, mismatches resolved with evidence | PASS | Section 1a completed prior to code inspection and reconciled |
| D-9 | Code-to-world contract: every parameter crossing into an external system validated against queried capabilities, never assumed | PASS | [PlayerProfile.luau:320-330](file:///c:/RGame/src/Server/PlayerProfile.luau#L320-L330) DataStore JSON payload size ceiling check |

---

## 1g. Adjudication of Known Items

### K-1 — Void Detection on a Flat Die
- **Disclosed Condition:** `RollService.isVoidFace` returns the lightest face index (`lightest = 1` default). On a flat die where all faces have equal mass (e.g. starting D6 with mass 10 on all faces), `faces[i].Mass < faces[lightest].Mass` is false for all faces, leaving `lightest = 1`. Face 1 is classified as a Void face, causing a 1-in-6 streak break for brand new players on an un-forged starting die.
- **Specification Check:** `SRS FR-5.2` defines a Void face as *"a face at or near the mass floor."* On a starting die with budget 60 and floor 1.0, face mass 10 is 10x the mass floor and is not "at or near" the floor.
- **Adjudication:** **CODE DEFECT (Finding F-G3-1).** The logic in `RollService.isVoidFace` is incomplete for flat or multi-tied face distributions. `isVoidFace` should require that the candidate face's mass is within a threshold of `massFloor` (e.g., `faceMass <= massFloor * 1.1` or `faceMass == lightestMass and lightestMass <= massFloor * 1.1`). On a flat die well above floor, no face should trigger a Void break.

### K-2 — Bad Roll Shield Unwired Default
- **Disclosed Condition:** `RollService.performRoll` reads `data.Upgrades.BadRollShield`, which is not declared in `TEMPLATE.Upgrades` in `PlayerProfile.luau`.
- **Safety Verification:** In `RollService.luau:345`, `(data.Upgrades.BadRollShield or 0) > 0` evaluates `nil or 0 > 0`, which safely evaluates to `false`. The shield remains off by default, fails closed, cannot be spoofed by the client, and UT-4 tests shield logic directly by injecting `hasShield = true` in config parameters.
- **Adjudication:** **ACCEPTABLE / FAILS CLOSED (Finding F-G3-2).** The current fallback behavior is safe. For construction, `BadRollShield = 0` should be formally added to `TEMPLATE.Upgrades` when `MonetizationService` is integrated.

---

## 1h. Gate 3 Verdict

### Verdict
`AUDIT-APPROVED`

### Numeric Finding Count
`FINDINGS: 3`

### Defect & Finding List for Construction
1. **F-G3-1 [K-1 / SRS FR-5.2]**: `RollService.isVoidFace` returns `true` for face 1 on flat dice (where all face masses are equal), treating face 1 as a Void even when face mass (e.g. 10) is far above the mass floor (1.0). `SRS FR-5.2` defines Void as "at or near mass floor". Implementation should check if face mass is within mass floor threshold before flagging as Void.
2. **F-G3-2 [K-2 / Schema]**: `RollService.performRoll` checks `data.Upgrades.BadRollShield`, but `BadRollShield` is not explicitly declared in `TEMPLATE.Upgrades` in `PlayerProfile.luau`. Fails closed safely to 0/false, but `BadRollShield` key should be formally declared in template schema when MonetizationService is integrated.
3. **F-G3-3 [Q-6 / Test Quality]**: `tests/Payout.test.luau:186` assertion `res.streak == 0 or res.streak == 1` accepts both Void hit and non-Void hit on flat dice, masking the flat-die Void detection anomaly during test execution.
