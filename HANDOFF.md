# PROJECT HANDOFF — Dice Forge Incremental

**For an AI assistant continuing this project with zero prior context.**
Written 2026-08-05. Repo: `C:\RGame` → https://github.com/HitanshG07/Rgame-dice (**private**). HEAD: `22af0ac`.

Read this document top to bottom before touching anything. Section 14 tells you exactly what to do first.

---

## 1. PROJECT GOAL

A Roblox game called **Dice Forge Incremental**. Players throw 3D dice into a contained arena; earnings are spent to **forge individual faces** of their dice.

The distinguishing idea, and the thing every technical decision protects:

> **Forging is ZERO-SUM.** Each die has a fixed *mass budget*. Forging moves mass **between** faces — it never adds mass. Heavier faces pay superlinearly more but land **less often**. So every forge is a genuine trade-off, not a "buy the upgrade" button.

Genre context, researched and accepted: a live competitor (*Dice Rolling Incremental*, Logical Studios) took 2.55M visits, peaked at 1,562 concurrent players, and sat at **4 concurrent** seven months later. Roblox idle games spike then collapse. The operator knows this. The bet is that zero-sum forging + cross-die element synergy produces *decisions* rather than purchases, and that decisions retain players.

Visual style: low-poly 3D dice arena viewed top-down, overlaid by a retro-pixel 2D UI (dark maroon / charcoal panels, 1px gold borders, monospace pixel type).

---

## 2. THE SINGLE MOST IMPORTANT ARCHITECTURAL FACT

**The server decides every roll outcome by weighted sampling. The client's 3D dice tumble is ANIMATION that resolves to an already-decided face, and is never read to determine anything.**

Why this is non-negotiable: Roblox assigns network ownership of moving parts to a client by default. Dice are moving parts. If the resting physical position determined the payout, an exploiter would rotate a die to show any face and mint currency at will — and the game has public leaderboards.

**The constraint this imposes:** the server holds **no rigid-body state** — no positions, velocities, orientations, collisions. Therefore **no game feature may depend on where a die is, what it hit, or how it moved.** Every element, bonus and interaction must resolve from the **resolved face set** alone.

A feature that cannot be expressed that way is **rejected at design time**, not implemented. The only two ways to build it are per-die server physics (breaks the performance budget) or client economic authority (breaks server authority and reopens the exploit). This exact failure class destroyed the previous project — see `.brain/LEDGER.md` entry **L-015**.

---

## 3. TECHNOLOGIES

| Thing | Detail |
|---|---|
| Platform | Roblox |
| Language | **Luau**, `--!strict` on every module, zero Script Analysis warnings required |
| Sync | **Rojo** (`tools/rojo.exe`, serving on `localhost:34872`). Disk is the source of truth |
| Persistence | **ProfileStore** by loleris — vendored, pinned commit `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31), **Apache-2.0** (attribution required; do not strip the header) |
| Leaderboards | `OrderedDataStore` |
| Monetization | `MarketplaceService` — asset IDs **do not exist yet**, use `DUMMY_ID_*` placeholders that fail closed |
| Excluded from V1 | **MessagingService** as a gameplay mechanism (ProfileStore uses it internally; that is fine and explicitly carved out) |
| Third-party deps | **Exactly one**: ProfileStore. Nothing else. No HTTP, no external services |

---

## 4. FOLDER STRUCTURE

```
C:\RGame\
├── default.project.json          Rojo mapping (see below)
├── HANDOFF.md                    this file
├── AI_WORKSPACE_RULES.md         governance bootloader — READ IF MODIFYING FILES
├── CLAUDE.md / AGENTS.md / GEMINI.md    per-tool shims pointing at the bootloader
│
├── .brain/                       ← THE PROJECT'S MEMORY. See section 13.
│   ├── LEDGER.md                 hard-won lessons, L-001..L-018. READ THIS.
│   ├── SCOREBOARD.md             every pipeline run and its defects
│   ├── PIPELINE.md               the 7 quality gates
│   ├── PERSONAS.md               the 5 role personas
│   ├── CHECKLISTS.md             Matrices A-G bound to each gate
│   ├── skills/roblox_luau.md     Roblox domain rules — §6 is Luau syntax traps
│   └── modes/                    behavioural modes (brainstormer, honest_advisor, …)
│
├── docs/blueprint/               ← THE SPEC. Binding. See section 5.
│   ├── THREAT_MODEL.md           29 threats T-1..T-29, 29 mitigations, risks R-1..R-8
│   ├── SRS.md                    FR-1..FR-14, NFR-1..NFR-8
│   ├── HLD.md                    architecture, authority model, module list
│   ├── API_DATA_CONTRACT.md      every remote + the ProfileStore profile schema
│   ├── TEST_PLAN.md              UT-1..UT-11, IT-1..IT-5, procedures P-1..P-4
│   └── DEVOPS_RECORD.md          10 ops decisions + dependency register
│
├── deliveries/                   audit trail — plans, evidence, delivery records
│
├── src/
│   ├── Shared/     ForgeMath.luau  Remotes.luau  ElementCatalog.luau
│   ├── Server/     PlayerProfile.luau  RemoteGateway.luau  EconomyService.luau
│   │               RollService.luau
│   │   └── Vendor/ ProfileStore.luau   (2242 lines, pinned, do not edit)
│   └── Client/     EMPTY — nothing built yet
│
├── tests/          RunAll.server.luau  ForgeMath.test  ForgeValidation.test
│                   Sampling.test  Payout.test
└── tools/rojo.exe
```

**Rojo mapping** (`default.project.json`):
```
src/Shared  → ReplicatedStorage.Shared
src/Server  → ServerScriptService.Server
src/Client  → StarterPlayer.StarterPlayerScripts.Client
tests       → ServerScriptService.Tests
```

---

## 5. THE SPEC IS BINDING

`docs/blueprint/` is not documentation-after-the-fact. It is the contract, written before the code, and every gate audits against it.

Each document opens with `CONSUMED-BY: Gate X / Matrix Y` naming which gate reads it, and `STATUS: LIVING — amend on divergence; every amendment cites its triggering fact`.

**If code and spec disagree, that is a defect — not a doc that needs updating.** Either fix the code or amend the document *with the fact that triggered the amendment*. Silent divergence is exactly what killed the previous project.

---

## 6. FILES CREATED, AND WHAT EACH DOES

### `src/Shared/ForgeMath.luau` (251 lines) — the mathematical heart
Pure. No state, no side effects, no authority. **Shared by client and server on purpose** so the preview a player optimises against is exactly the maths that pays them; safe because it is pure — a tampered client can only lie to its own preview.

| Function | Purpose |
|---|---|
| `isFinite(n)` | Rejects `NaN`, `±inf`, non-numbers. **Called at every numeric boundary** |
| `snap(n)` / `snapAll(t)` | Round to 4 dp. Stops float residuals compounding (threat T-27) |
| `validate(mass, faceCount, budget, floor)` | Returns `ok, reason`. **Finiteness is checked BEFORE the sum** |
| `landingProbabilities(mass)` | `P(i) = (M − mᵢ) / (M(n−1))`. Sums to exactly 1 |
| `faceValue(m)` | `m ^ ALPHA`, ALPHA = 2.0 |
| `expectedValue(mass)` | Σ P·value |
| `voidProbability(mass)` | Probability of the **lightest** face — the streak breaker |
| `preview(mass)` | All of the above in one pass for the UI |
| `sampleFace(mass, rng)` | Weighted draw. `rng` **injected** so tests pin a seed |

**Constants:** `ALPHA = 2.0`, `PRECISION = 4`, `EPSILON = 1e-3`.
**Do not retune ALPHA or the probability formula without re-running the dominant-strategy simulation** — see section 8.

### `src/Shared/Remotes.luau` (152 lines) — remote name registry
Server creates every remote; client only waits. `getFunction`, `getEvent`, `createAll`. Enumerated `Notice` codes so the client receives a *code*, never an internal detail. **`RemoteFunction:InvokeClient()` is prohibited project-wide** (threat T-8: an exploiting client can yield forever and hang the server thread).

### `src/Shared/ElementCatalog.luau` (91 lines) — element payoffs
`goldPayoff(count, combinedMass)` returns **0 below 2 participating faces**, and scales **superlinearly with combined mass**. `firePayoff`, `multiplierFactor`.

> **A flat conditional bonus is algebraically inert and is a DEFECT, not a tuning choice.** The partner's trigger probability enters as a constant multiplier on a term linear in your own, which cannot shift any optimum. Measured across three separate models. See L-016.

### `src/Server/PlayerProfile.luau` (331 lines) — the ONLY ProfileStore boundary
No other module touches the library, so swapping it is a one-module change.
- `load(player)` → **FAILS CLOSED.** A failed load or foreign session lock **never** returns a default profile (that would silently overwrite real saved data).
- `mutate(player, fn)` → **the only sanctioned write path.** Checks `IsActive()` **synchronously** with the mutation, no yield between (threat T-26).
- `recordPurchase(data, id, now)` → **time-aware** eviction, not count-only. Returns `ceiling_reached_all_live` rather than dropping a still-replayable receipt (threat T-13).
- `_migrate`, `checkPayloadSize`, `getTemplate`.

### `src/Server/RemoteGateway.luau` (242 lines) — the ONLY inbound door
Validation order is **fixed and specified**: `rate limit → arity → type → finiteness → bounds → allowlist → affordability`. Finiteness precedes bounds/sums because `NaN` defeats a sum check. Per-player per-remote token buckets. Rejections log server-side with UserId and return a **generic** code. **Never auto-kick** — lag causes false positives.

### `src/Server/EconomyService.luau` (125 lines) — the ONLY currency writer
`credit`, `debit`, `spend`, `balance`, `canAfford`, `recordRoll`. Single chokepoint by design: the audit surface for "can a player gain currency they did not earn" is one file. No overdraft, clamped at 1e300.

### `src/Server/RollService.luau` (~330 lines) — the core loop
**Deliberately split** into pure maths (plain tables + injected `Random`, no Player/profile/service) and a thin service shell, so tests exercise the real logic rather than a copy.

Pure: `streakMultiplier(streak, b)` — compounding `(1+b)^s`, double-capped · `streakStrengthToB(level)` · `isVoidFace(die, i)` · `sampleOutcomes(dice, rng)` · `resolveElements(outcomes)` → `additive, factor, fired, frozenDie` · `computeThrow(dice, rng, cfg)` → full `ThrowResult`.

Shell: `beginSession` / `endSession` / `getStreak` / `averageIncomePerSecond` / `performRoll(player)`.

**Payout formula:** `(baseTotal + additive) × multiplicativeFactor × streakMultiplier × coinBonus`
**Cash is credited BEFORE `RollResult` fires**, so a dropped event never costs the player money (SRS FR-2.6).

### `tests/`
`RunAll.server.luau` is a **Script**, not a ModuleScript. A module that fails to `require` is reported as a **FAILURE, never skipped**; zero discovered suites is also a failure. Terminates with `=== SUITE COMPLETE: X passed, Y failed ===`.

Each suite returns `{ name = "...", run = function(): (boolean, string?, number) }` (passed, failureMessage, assertionCount).

---

## 7. DESIGN DECISIONS AND WHY

| Decision | Reasoning |
|---|---|
| Server samples, client animates | Roblox gives clients network ownership of moving parts. Physics-driven payouts = free money for exploiters |
| Zero-sum mass budget | Makes every forge a trade-off. **Also a security property** — a validator checking that mass sums to the budget cannot be tricked into inflating a face |
| `value = m^2.0`, `P ∝ (M−m)` | Measured. `ALPHA ≤ 1` makes the forge inert; `P ∝ 1/m` makes "never forge" optimal |
| Compounding streak `(1+b)^s` | A **linear** multiplier cannot move the forge optimum at any strength. Measured |
| Streak Strength as a Prestige tree | Bistable optimum with a cliff at `b ≈ 0.15`. Making `b` a player investment puts different players on different sides → sniper vs grinder cohorts. **This is the build diversity** |
| Dice shape = build choice, not tier | Void probability runs ≈0.33 (D4) → ≈0.05 (D20). D4 volatile sniper, D20 steady grinder. No shape wins at every `b` |
| Elements coupled to combined mass | A flat conditional bonus is algebraically inert |
| Re-forging must cost real Cash | Free re-forging collapses the cross-die puzzle to a solved symmetric state |
| `ForgeMath` shared client+server | Pure, so it grants no authority; guarantees the preview matches the payout |
| ProfileStore over ProfileService | ProfileService is **no longer supported**. ProfileStore is the successor |
| Single-writer services | `EconomyService` owns currency, `PlayerProfile` owns persistence, `RemoteGateway` owns inbound |
| Starter Bundle timer is once-only | Operator prohibits manufactured urgency. Expired = permanently gone. **No countdown may ever reset** |

---

## 8. THE PRE-CODE SIMULATIONS (why the numbers are what they are)

Before a single line of game code, four Python simulations tested whether the design had a **dominant strategy** — because if one distribution wins everywhere, the mechanic is decoration.

- **Sim 1 killed the first proposed formula.** `value ∝ m^1.5` with `P ∝ 1/m` made a FLAT distribution optimal at every shape and budget — optimal play was *never to use the mechanic*.
- **Sim 2/3:** a linear streak bonus cannot move the optimum at any strength. Two cross-die models returned null results **because the models had no trade-off in them** — reported as invalid tests, not design findings.
- **Sim 4:** a flat conditional bonus is algebraically inert (predicted structurally, then confirmed). The mass-coupled variant produced correlation **−0.949** — anti-mirroring, i.e. dice specialise into complementary roles.

**Generalizable rule (L-016): a scalar optimum over a fixed budget is always solvable. Context-dependence must come from COUPLING, not from curve-shaping.**

Scripts are **not** in the repo — they were run in a scratch directory and are gone. If you need to retune `ALPHA`, the streak cliff, or element coefficients, **rewrite and re-run the simulation first.** Changing these values by intuition will silently destroy the design.

---

## 9. CURRENT IMPLEMENTATION STATUS

### Verified working (executed in Studio, output captured)
- `ForgeMath` — UT-1, 38 assertions ✅
- `ForgeMath.validate` — UT-2, 52 assertions ✅
- Evidence: `deliveries/evidence/2026-08-04-block1-unit-suite.txt`

### Written but NEVER EXECUTED — treat as unproven
- `ElementCatalog`, `EconomyService`, `RollService`
- `tests/Sampling.test.luau` (UT-3), `tests/Payout.test.luau` (UT-4)

### Not started
- **All client code.** `src/Client/` is empty. No UI, no arena, no dice rendering.
- `ForgeService`, `ProgressionService`, `AscensionService`, `OfflineService`, `MonetizationService`, `LeaderboardService`, `ServerBootstrap`, `RateLimiter` (separate module)
- Shared: `DiceCatalog`, `UpgradeCatalog`, `Format`
- `tests/Fakes.luau` — needed for any test touching profiles/services
- UT-5…UT-11, IT-1…IT-5

### Gate status
- Blueprint: **DELIVERED** (Gates 0–6 complete)
- Block 1: **Gate 2 CLEAN**, Gates 3–4 **PENDING**
- Block 2: written, **Gate 2 not yet run**, Gates 3–4 pending
- Operator decision on record: **audit Blocks 1 and 2 together** after Block 2's suite passes

---

## 10. BUGS ENCOUNTERED AND FIXES

| # | Bug | Root cause | Fix |
|---|---|---|---|
| 1 | Whole module failed to load; all suites reported failure | **`T.field: Type = value` is invalid Luau.** Annotations are legal only on locals and function signatures. 5 occurrences | Removed annotations; kept typing via annotated locals bound afterwards (`local FN: {...} = {...}` then `Remotes.Fn = FN`). Commit `c5a051f` |
| 2 | UT-2 failed: "snapped round-trip forging drifted out of tolerance" | **The TEST was wrong, not the validator.** It moved 0.1 from one face 500×, driving it below the mass floor after 90 iterations; `validate` correctly returned `below_floor`. The sum never drifted. It also modelled a flow that doesn't exist — the client sends a *complete* distribution each time, validated fresh | Rewrote to test real properties: snap idempotence, 2000 randomised transfers, floor accepted at the boundary and rejected one notch below. Commit `d0ac804` |
| 3 | Stale `ServerMain` / `ReplicatedStorage.Source` throwing yield warnings | Retired-project instances **inside the `.rbxl`**. Rojo only manages branches it declares; deleting files from disk cannot remove them | Operator deleted them manually in the Explorer |
| 4 | Blueprint contradiction: per-ball physics vs aggregate server state | Requirements specified behaviour the architecture could not deliver | Re-expressed all behaviours as aggregate modifiers. **L-015** |
| 5 | `purchaseIds` bounded by COUNT while justified on TIME | A player past 200 purchases could have a live receipt evicted → real-money double-grant | Time-aware eviction with cold-key archival. **T-13 amended** |
| 6 | `NaN` reaching the leaderboard log transform | The identical hazard was closed for the forge (T-25) and left open here — **the inconsistency was the defect** | Finiteness asserted at *every* numeric boundary. **T-28** |
| 7 | Documented ProfileStore as MIT | Never verified | It is **Apache-2.0**. Corrected in HLD + DEVOPS_RECORD |

**Pattern worth internalising: two of these were caught only because the operator executes the code.** The authoring session cannot run Luau. Never claim something works without execution evidence.

---

## 11. CODING CONVENTIONS

1. **`--!strict` on every module**, first line. Zero Script Analysis warnings — a warning is a gate failure, not a nit.
2. **Never `T.field: Type = value`.** Verify before committing:
   `grep -rnE '^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_]+[[:space:]]*:[^=]+=' src/ tests/ --exclude-dir=Vendor`
3. **Zero placeholders.** No `TODO`, `FIXME`, `TBD`, no stub bodies. Every file complete at write time.
4. **Explicit failure paths.** Every fallible operation is `pcall`-guarded or has a visible failure branch. Never swallow errors.
5. **Return `(ok, reason)`** rather than throwing across a boundary. Reasons are enumerated snake_case strings.
6. **Finiteness checked before arithmetic**, always.
7. **Pure logic separated from Roblox services**, so tests drive the real code.
8. **Inject `Random`** — never a hidden global RNG.
9. **Comments explain WHY**, especially citing threat IDs (`T-nn`), requirement IDs (`FR-n.n`) and ledger entries (`L-0nn`).
10. **Never edit scripts inside Studio.** Rojo overwrites on next sync and the change vanishes with no diff.
11. Tab indentation, matching existing files.

---

## 12. CONSTRAINTS AND REQUIREMENTS

### Absolute
- **No client message may carry** a price, balance, reward, score, level, duration, multiplier, or outcome. Client sends **intent**; server sends **truth**.
- **`RemoteFunction:InvokeClient()` nowhere.**
- **Exactly one `ProcessReceipt` assignment** in the entire place (threat T-17). Silent and catastrophic if violated.
- **`SetAsync` prohibited** for profile data.
- **`PurchaseGranted` only after the grant durably persists**; every other path returns `NotProcessedYet`.
- **No fabricated social proof or manufactured urgency.** No fake "someone just bought" toasts, no resetting countdowns. Standing operator instruction.
- **No `MessagingService`** in our code (Vendor/ is exempt).

### Performance
- 60 FPS desktop / 30 FPS mid-tier mobile with 7 dice; client < 4 ms/frame; no per-frame allocation.
- Server < 0.5 ms per player per roll; cost scales with **die count**, never physics.
- All UI in `Scale` units, never fixed `Offset`. Must render 320px → 4K.

### Process
- Build Tier **PRODUCTION**. Every change walks the 7 gates in `.brain/PIPELINE.md`.
- **The author of a diff may not audit it.** Gates 3–4 run in a separate context.
- Verification is **manual**: this repo's AI authors tests, the operator runs them in Studio and pastes verbatim output. A step not performed is recorded as not performed, never as a pass.

---

## 13. WHERE THE MEMORY LIVES

Everything needed to reconstruct context is on disk and in git. Nothing important exists only in a chat log.

| Source | Contains |
|---|---|
| **`.brain/LEDGER.md`** | **Read this first.** L-001…L-018: every hard-won lesson with root cause and fix. Most relevant: **L-013** (a clean scoreboard over unexecuted work is worthless), **L-014** (enumerated audit briefs), **L-015** (per-entity behaviour vs aggregate state), **L-016** (coupling not curve-shaping — the simulation findings), **L-017** (modelling error ≠ design finding), **L-018** (audit classification failures) |
| `.brain/SCOREBOARD.md` | Every pipeline run, its rejections and defect classes. Honest, including failures |
| `.brain/skills/roblox_luau.md` | Roblox domain rules. **§6 = the Luau syntax traps that cost real time** |
| `docs/blueprint/*` | The binding spec — threats, requirements, architecture, contract, tests, ops |
| `deliveries/` | Plans, audit briefs, cross-vendor audit artifacts, delivery records with residual risk |
| `git log` | Every commit message explains **why**, not just what. `git log --stat` is a real changelog |
| `AI_WORKSPACE_RULES.md` | The governance bootloader. §1 holds the environment matrix |

**If you are a Claude Code session in this repo:** `CLAUDE.md` auto-loads and points at the bootloader. Read `.brain/BOOT_DIGEST.md` first; parse the full governance files before proposing any file modification.

**If you are ChatGPT or another assistant without file access:** ask the operator to paste `.brain/LEDGER.md`, `docs/blueprint/SRS.md`, `docs/blueprint/HLD.md`, and `docs/blueprint/API_DATA_CONTRACT.md`. Those four give you ~90% of the working context.

---

## 14. EXACT NEXT STEPS

### Step 1 — Run the suite (operator, in Studio)
Rojo is serving. Press **F5**, open **View → Output**, wait for `=== SUITE COMPLETE: X passed, Y failed ===`, paste the **entire** panel.

**Expected: `4 passed, 0 failed`, ~210 assertions.** UT-3 draws 100,000 samples so allow a moment.

If it fails, the failure is informative — do not tidy the output. Determine **which side is wrong** (see bug #2 above) before changing anything.

### Step 2 — Fix anything the run surfaces
Likely candidates: `--!strict` type errors in `RollService` (never type-checked), or a `require` path problem for `ServerScriptService.Server.RollService` from the tests.

### Step 3 — Two open design questions the operator must decide

**(a) Void definition on a flat die.** `RollService.isVoidFace` returns the **lightest** face regardless of whether it is near the mass floor. On a perfectly flat starting die, face 1 is therefore a Void — a new player breaks their streak 1-in-6 rolls with no way to avoid it. SRS FR-5.2 says a Void is *"a face at or near the mass floor"*, which implies a flat die should have **no** Void. **The spec is probably right and the code wrong**, but it is a design call.

**(b) Bad Roll Shield is unwired.** `performRoll` reads `data.Upgrades.BadRollShield`, which is not in the profile template — the shield is a **gamepass**, and `MonetizationService` does not exist yet. It safely defaults to off, and UT-4 tests the logic directly, but the wiring is a stub until Block 3.

### Step 4 — Gates 3–4 audit of Blocks 1 + 2 together
Operator's decision. Write an **enumerated** audit brief — every Matrix D and E line spelled out inline as a numbered row with a verdict column. Referencing a checklist in another file gets it partially executed; enumerating it gets it executed (**L-014**).

Template: `deliveries/audit-briefs/2026-08-04-dice-forge-audit.md`.

**Then verify the auditor's factual claims against the repo before accepting the verdict.** Both audits so far returned a verdict that survived scrutiny while carrying a record that did not (L-014, L-018).

### Step 5 — Block 3
`ForgeService` (applies validated mass redistribution) · `DiceCatalog` · `UpgradeCatalog` · `ServerBootstrap` (wires services, player lifecycle, `BindToClose`) · `tests/Fakes.luau` · UT-5…UT-8.

### Step 6 — Block 4: client
`src/Client/` is completely empty. Arena rendering, dice tumble-to-target animation, forge panel with live preview, HUD. **Nothing playable exists yet.**

---

## 15. OPTIONAL BUT HIGH VALUE — MCP

The **Roblox Studio MCP server is registered and running** (`~/.claude.json`, project scope `C:/RGame`; `StudioMCP.exe` alive). It was registered *after* the current session started, and MCP servers connect at session startup — so the running session cannot see it.

**Starting a fresh Claude Code session in `C:\RGame` gives that session the Studio tools**, ending the manual paste loop: it could run the suite itself and iterate on failures in seconds. Studio must be open with the MCP plugin connected.

Given that two defects so far each cost a full round-trip, doing this before Block 3 is worth it.

---

## 16. THE ONE-PARAGRAPH VERSION

Dice Forge Incremental is a Roblox idle game whose core mechanic is a zero-sum mass budget on dice faces: heavier faces pay superlinearly more but land less often, so forging is a real trade-off. The server decides every outcome by weighted sampling and the client's 3D physics is pure animation — this is what makes the game exploit-proof, and it forbids any feature depending on where a die physically is. The maths was validated by simulation before any code was written, and those constants must not be retuned without re-running it. Roughly 1,190 lines of our Luau exist across seven modules plus five test files; `ForgeMath` and its validator are proven by 90 passing assertions, everything else is written but unexecuted, and the entire client is unbuilt. The immediate task is running the four-suite test in Studio and reporting the verbatim output.
