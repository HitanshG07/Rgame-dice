# PROJECT HANDOFF — Dice Forge Incremental

**For an AI assistant continuing this project with zero prior context.**
Written 2026-08-06. Repo: `C:\RGame` → https://github.com/HitanshG07/Rgame-dice (**private**). HEAD: `176d0e3`.

Read top to bottom before touching anything. **Section 14 tells you exactly what to do first.**

---

## 1. PROJECT GOAL

A Roblox game called **Dice Forge Incremental**. Players throw 3D dice into a contained arena; earnings are spent to **forge individual faces** of their dice.

The distinguishing idea, which every technical decision exists to protect:

> **Forging is ZERO-SUM.** Each die has a fixed *mass budget*. Forging moves mass **between** faces — it never adds mass. Heavier faces pay superlinearly more but land **less often**. Every forge is a genuine trade-off, not a "buy the upgrade" button.

**Competitive reality, researched and accepted by the operator:** a live competitor (*Dice Rolling Incremental*, Logical Studios) took 2.55M visits, peaked at 1,562 concurrent players, and sat at **4 concurrent** seven months later. Roblox idle games spike then collapse. The bet is that zero-sum forging plus cross-die element synergy produces *decisions* rather than purchases, and that decisions retain players.

Visual style: low-poly 3D dice arena viewed top-down, overlaid by a retro-pixel 2D UI (dark maroon / charcoal panels, 1px gold borders, monospace pixel type).

---

## 2. THE SINGLE MOST IMPORTANT ARCHITECTURAL FACT

**The server decides every roll outcome by weighted sampling. The client's 3D dice tumble is ANIMATION resolving to an already-decided face, and is never read to determine anything.**

Why it is non-negotiable: Roblox assigns network ownership of moving parts to a client by default. Dice are moving parts. If the resting physical position determined the payout, an exploiter would rotate a die to show any face and mint currency at will — and the game has public leaderboards.

**The constraint this imposes:** the server holds **no rigid-body state** — no positions, velocities, orientations, collisions. Therefore **no game feature may depend on where a die is, what it hit, or how it moved.** Every element, bonus and interaction must resolve from the **resolved face set** alone.

A feature that cannot be expressed that way is **rejected at design time**, not implemented. The only alternatives are per-die server physics (breaks the performance budget) or client economic authority (breaks server authority and reopens the exploit). This exact failure class destroyed the previous project — ledger **L-015**.

---

## 3. TECHNOLOGIES

| Thing | Detail |
|---|---|
| Platform | Roblox |
| Language | **Luau**, `--!strict` on every module, zero Script Analysis warnings required |
| Sync | **Rojo** (`tools/rojo.exe`, port `34872`). Disk is the source of truth |
| Verification | **Roblox Studio MCP server is connected and working.** Run tests directly — see §15 |
| Persistence | **ProfileStore** by loleris — vendored, pinned `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31), **Apache-2.0** (attribution required; do not strip the header) |
| Leaderboards | `OrderedDataStore` |
| Monetization | `MarketplaceService` — asset IDs **do not exist yet**; use `DUMMY_ID_*` placeholders that fail closed |
| Excluded from V1 | **MessagingService** as a gameplay mechanism (ProfileStore uses it internally; explicitly carved out) |
| Third-party deps | **Exactly one**: ProfileStore. No HTTP, no external services |

---

## 4. FOLDER STRUCTURE

```
C:\RGame\
├── default.project.json          Rojo mapping (below)
├── HANDOFF.md                    this file
├── AI_WORKSPACE_RULES.md         governance bootloader — read before modifying files
├── CLAUDE.md / AGENTS.md / GEMINI.md   per-tool shims pointing at the bootloader
│
├── .brain/                       ← PROJECT MEMORY. See §13.
│   ├── LEDGER.md                 L-001..L-020. READ THIS FIRST.
│   ├── SCOREBOARD.md             every pipeline run, its rejections and defects
│   ├── PIPELINE.md               the 7 quality gates
│   ├── PERSONAS.md               the 5 role personas
│   ├── CHECKLISTS.md             Matrices A–G bound to each gate
│   ├── skills/roblox_luau.md     Roblox rules; §6 = Luau syntax traps
│   └── modes/                    behavioural modes (brainstormer, honest_advisor, …)
│
├── docs/blueprint/               ← THE SPEC. Binding. See §5.
│   ├── THREAT_MODEL.md           T-1..T-29 + T-30, mitigations, risks R-1..R-8
│   ├── SRS.md                    FR-1..FR-14, NFR-1..NFR-8
│   ├── HLD.md                    architecture, authority model, module list
│   ├── API_DATA_CONTRACT.md      every remote + the ProfileStore profile schema
│   ├── TEST_PLAN.md              UT-1..UT-11, IT-1..IT-5, procedures P-1..P-4
│   └── DEVOPS_RECORD.md          10 ops decisions + dependency register
│
├── deliveries/                   audit trail
│   ├── plans/                    Gate 0 plan artifacts
│   ├── audit-briefs/             enumerated Gate 3-4 briefs
│   └── evidence/                 verbatim test output + audit verdicts
│
├── src/
│   ├── Shared/     ForgeMath.luau  Remotes.luau  ElementCatalog.luau
│   ├── Server/     PlayerProfile.luau  RemoteGateway.luau  EconomyService.luau
│   │               RollService.luau
│   │   └── Vendor/ ProfileStore.luau   (2242 lines, pinned, DO NOT EDIT)
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

Each document opens with `CONSUMED-BY: Gate X / Matrix Y` naming the gate that reads it, and `STATUS: LIVING — amend on divergence; every amendment cites its triggering fact`.

**If code and spec disagree, that is a defect — not a doc that needs quietly updating.** Either fix the code or amend the document *with the fact that triggered the amendment*. Silent divergence killed the previous project. This has already happened once here and the **spec won** — see finding F-G3-1 in §10.

---

## 6. FILES, AND WHAT EACH DOES

**2,514 lines of our Luau** across 7 modules and 5 test files, plus 2,242 vendored.

### `src/Shared/ForgeMath.luau` (251) — the mathematical heart
Pure. No state, no side effects, no authority. **Shared by client and server on purpose** so the preview a player optimises against is exactly the maths that pays them; safe because pure — a tampered client can only lie to its own preview.

| Function | Purpose |
|---|---|
| `isFinite(n)` | Rejects `NaN`, `±inf`, non-numbers. **Called at every numeric boundary** |
| `snap(n)` / `snapAll(t)` | Round to 4 dp. Stops float residuals compounding (T-27) |
| `validate(mass, faceCount, budget, floor)` | `ok, reason`. **Finiteness checked BEFORE the sum** |
| `landingProbabilities(mass)` | `P(i) = (M − mᵢ)/(M(n−1))`. Sums to exactly 1 |
| `faceValue(m)` | `m ^ ALPHA`, ALPHA = 2.0 |
| `expectedValue`, `voidProbability`, `preview` | UI + balance helpers |
| `sampleFace(mass, rng)` | Weighted draw. `rng` **injected** so tests pin a seed |

Constants: `ALPHA = 2.0`, `PRECISION = 4`, `EPSILON = 1e-3`.
**Do not retune ALPHA or the probability formula without re-running the simulation** — see §8.

### `src/Shared/Remotes.luau` (152) — remote name registry
Server creates every remote; client only waits. `getFunction`, `getEvent`, `createAll`. Enumerated `Notice` codes so the client gets a *code*, never an internal detail. **`RemoteFunction:InvokeClient()` prohibited project-wide** (T-8).

### `src/Shared/ElementCatalog.luau` (91) — element payoffs
`goldPayoff(count, combinedMass)` returns **0 below 2 participating faces** and scales **superlinearly with combined mass**. Plus `firePayoff`, `multiplierFactor`.

> **A flat conditional bonus is algebraically inert and is a DEFECT, not a tuning choice.** The partner's trigger probability enters as a constant multiplier on a term linear in your own, which cannot shift any optimum. Measured across three models. **L-016.**

### `src/Server/PlayerProfile.luau` (336) — the ONLY ProfileStore boundary
- `load(player)` → **FAILS CLOSED.** A failed load or foreign session lock **never** returns a default profile.
- `mutate(player, fn)` → **the only sanctioned write path.** Checks `IsActive()` **synchronously** with the mutation, no yield between (T-26).
- `recordPurchase(data, id, now)` → **time-aware** eviction. Returns `ceiling_reached_all_live` rather than dropping a still-replayable receipt (T-13).
- `_migrate`, `checkPayloadSize`, `getTemplate`.

### `src/Server/RemoteGateway.luau` (242) — the ONLY inbound door
Validation order is **fixed**: `rate limit → arity → type → finiteness → bounds → allowlist → affordability`. Finiteness precedes bounds/sums because `NaN` defeats a sum check. Per-player per-remote token buckets. Rejections log server-side with UserId and return a **generic** code. **Never auto-kick** — lag causes false positives.

### `src/Server/EconomyService.luau` (125) — the ONLY currency writer
`credit`, `debit`, `spend`, `balance`, `canAfford`, `recordRoll`. Single chokepoint by design: the audit surface for "can a player gain currency they did not earn" is one file. No overdraft, clamped at 1e300.

### `src/Server/RollService.luau` (432) — the core loop
**Deliberately split** into pure maths (plain tables + injected `Random`, no Player/profile/service) and a thin service shell, so tests exercise the real logic rather than a copy.

Pure: `streakMultiplier(streak, b)` compounding `(1+b)^s` double-capped · `streakStrengthToB(level)` · `isVoidFace(die, i, floor?)` · `sampleOutcomes(dice, rng)` · `resolveElements(outcomes)` → `additive, factor, fired, frozenDie` · `computeThrow(dice, rng, cfg)`.

Shell: `beginSession` / `endSession` / `getStreak` / `averageIncomePerSecond` / `performRoll(player)`.

Constants: `STREAK_CAP = 50` · `B_PER_LEVEL = 0.01` · `MAX_STREAK_MULTIPLIER = 1e6` · `SHIELD_COOLDOWN = 30` · `MASS_FLOOR = 1` · `VOID_FLOOR_FACTOR = 1.5` · `MIN_RATE_WINDOW = 60` · `MAX_RATE = 1e12`.

**Payout:** `(baseTotal + additive) × multiplicativeFactor × streakMultiplier × coinBonus`
**Cash is credited BEFORE `RollResult` fires**, so a dropped event never costs the player money (FR-2.6).

### `tests/`
`RunAll.server.luau` is a **Script**, not a ModuleScript. A module that fails to `require` is reported as a **FAILURE, never skipped**; zero discovered suites is also a failure. Terminates with `=== SUITE COMPLETE: X passed, Y failed ===`.

Each suite returns `{ name, run = function(): (boolean, string?, number) }` — passed, failureMessage, assertionCount.

---

## 7. DESIGN DECISIONS AND WHY

| Decision | Reasoning |
|---|---|
| Server samples, client animates | Roblox gives clients ownership of moving parts. Physics-driven payouts = free money for exploiters |
| Zero-sum mass budget | Every forge is a trade-off. **Also a security property** — a validator checking the sum cannot be tricked into inflating a face |
| `value = m^2.0`, `P ∝ (M−m)` | Measured. `ALPHA ≤ 1` makes the forge inert; `P ∝ 1/m` makes "never forge" optimal |
| Compounding streak `(1+b)^s` | A **linear** multiplier cannot move the forge optimum at any strength. Measured |
| Streak Strength as a Prestige tree | Bistable optimum with a cliff at `b ≈ 0.15`. Making `b` a player investment puts players on different sides → sniper vs grinder cohorts. **This is the build diversity** |
| Dice shape = build choice, not tier | Void probability ≈0.33 (D4) → ≈0.05 (D20). No shape wins at every `b` |
| Elements coupled to combined mass | A flat conditional bonus is algebraically inert |
| Re-forging must cost real Cash | Free re-forging collapses the cross-die puzzle to a solved symmetric state |
| Void requires proximity to the floor | An un-forged flat die must have **no** Void — otherwise new players break streaks unavoidably (F-G3-1) |
| Offline rate floored at a 60s window | Otherwise a 0.05s session manufactures an astronomical rate (T-30) |
| `ForgeMath` shared client+server | Pure, so grants no authority; guarantees preview matches payout |
| ProfileStore over ProfileService | ProfileService is **no longer supported**; ProfileStore is the successor |
| Single-writer services | `EconomyService` owns currency, `PlayerProfile` owns persistence, `RemoteGateway` owns inbound |
| Starter Bundle timer is once-only | Operator prohibits manufactured urgency. Expired = permanently gone. **No countdown may ever reset** |

---

## 8. THE PRE-CODE SIMULATIONS (why the numbers are what they are)

Before a single line of game code, four Python simulations tested whether the design had a **dominant strategy** — because if one distribution wins everywhere, the mechanic is decoration.

- **Sim 1 killed the first proposed formula.** `value ∝ m^1.5` with `P ∝ 1/m` made a FLAT distribution optimal at every shape and budget — optimal play was *never to use the mechanic*.
- **Sim 2/3:** a linear streak bonus cannot move the optimum at any strength. Two cross-die models returned null results **because the models had no trade-off in them** — reported as invalid tests, not design findings.
- **Sim 4:** a flat conditional bonus is algebraically inert (predicted structurally, then confirmed). The mass-coupled variant produced correlation **−0.949** — anti-mirroring: dice specialise into complementary roles.

**Generalizable rule (L-016): a scalar optimum over a fixed budget is always solvable. Context-dependence must come from COUPLING, not curve-shaping.**

Scripts are **not** in the repo — run in a scratch directory, now gone. To retune `ALPHA`, the streak cliff, or element coefficients, **rewrite and re-run the simulation first.** Changing these by intuition will silently destroy the design.

---

## 9. CURRENT IMPLEMENTATION STATUS

### Verified working — executed live in Studio, output captured
```
[PASS] UT-1 ForgeMath        38 assertions
[PASS] UT-2 ForgeValidation  52
[PASS] UT-4 Payout           62
[PASS] UT-3 Sampling       2627
=== SUITE COMPLETE: 4 passed, 0 failed ===   total 2779
```
Evidence: `deliveries/evidence/2026-08-06-blocks12-postaudit-suite.txt`

### Gate status — Blocks 1 + 2 are COMPLETE through Gate 4
| Gate | Verdict |
|---|---|
| Blueprint (6 docs) | **DELIVERED**, Gates 0–6 |
| Block 1+2 Gate 2 | **MECHANICALLY-CLEAN** — 4/4 suites, 2,779 assertions |
| Block 1+2 Gate 3 | **AUDIT-APPROVED** (cross-vendor, 3 findings, all remediated) |
| Block 1+2 Gate 4 | **SECURE** (4 findings, all remediated) |

### Written and audited but with a caveat
- `performRoll` (the service shell) is **not directly unit-tested** — needs `tests/Fakes.luau`, which does not exist. Only the pure functions are covered.

### Not started
- **All client code.** `src/Client/` is empty. **Nothing is playable.**
- `ForgeService`, `ProgressionService`, `AscensionService`, `OfflineService`, `MonetizationService`, `LeaderboardService`, `ServerBootstrap`, `RateLimiter` (separate module)
- Shared: `DiceCatalog`, `UpgradeCatalog`, `Format`
- `tests/Fakes.luau`; UT-5…UT-11; IT-1…IT-5

---

## 10. BUGS ENCOUNTERED AND FIXES

| # | Bug | Root cause | Fix |
|---|---|---|---|
| 1 | Whole module failed to load | **`T.field: Type = value` is invalid Luau.** Annotations legal only on locals and function signatures. 5 occurrences | Typed via annotated locals bound afterwards. `c5a051f` |
| 2 | UT-2 "drift" failure | **The TEST was wrong, not the validator.** It drove a face below the mass floor and misattributed the rejection | Rewrote to test real properties. `d0ac804`. **L-017** |
| 3 | Stale `ServerMain` / `Source` warnings | Retired-project instances **inside the `.rbxl`**; Rojo only manages branches it declares | Operator deleted manually |
| 4 | 5 more legacy scripts in `StarterPlayerScripts` | Same cause | Deleted via MCP |
| 5 | Blueprint contradiction: per-ball physics vs aggregate state | Requirements specified behaviour the architecture could not deliver | Re-expressed as aggregate modifiers. **L-015** |
| 6 | `purchaseIds` bounded by COUNT, justified on TIME | A player past 200 purchases could have a live receipt evicted → real-money double-grant | Time-aware eviction. **T-13 amended** |
| 7 | `NaN` reaching the leaderboard transform | Hazard closed for the forge (T-25), left open here — **the inconsistency was the defect** | Finiteness at *every* numeric boundary. **T-28** |
| 8 | ProfileStore documented as MIT | Never verified | It is **Apache-2.0**. Corrected |
| 9 | Suite reported clean `2 passed` — **two suites simply missing** | `rojo serve` had died silently; files on disk and in git never reached Studio | Restarted. **L-019** |
| 10 | Post-fix suite reported clean 4/4 **at the OLD assertion count** | Rojo *plugin* dropped its connection on Play start/stop. Server alive, files correct, plugin silently detached | Push via MCP `Source` assignment. **L-020: the assertion count is the sync canary** |
| 11 | **F-G4-1 / T-30 — offline-rate exploit** | `averageIncomePerSecond` divided earnings by elapsed session time with **no minimum window**. Join → roll at 0.05s → leave = astronomical rate feeding `Vault.AvgIncomePerSec` | Floored at `MIN_RATE_WINDOW` (60s), capped at `MAX_RATE`. **Found by cross-vendor audit** |
| 12 | **F-G3-1 — Void on a flat die** | `isVoidFace` ignored proximity to the floor, so an un-forged die treated face 1 as a Void; new players broke streaks 1-in-6 unavoidably. **Spec was right, code was wrong** | Requires `mass <= floor × 1.5` |
| 13 | **F-G3-3 — a tautology in my own test** | `check(res.streak == 0 or res.streak == 1)` — after one throw from streak 0 those are the only options. Could not fail | Replaced with deterministic assertions |
| 14 | **F-G3-2 — `BadRollShield` undeclared** | Read from `data.Upgrades.BadRollShield`, absent from the template | Declared with a `0` default; still fails closed |

**Patterns worth internalising.** Two bugs (#9, #10) were *green suites over stale code* — the most dangerous failure mode in this project, because success and failure look identical. Two more (#2, #13) were **bad tests, not bad code**; the lazy fix in each case would have punched a hole through a real invariant.

---

## 11. CODING CONVENTIONS

1. **`--!strict` on every module**, first line. Zero Script Analysis warnings — a warning is a gate failure.
2. **Never `T.field: Type = value`.** Verify before committing:
   `grep -rnE '^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_]+[[:space:]]*:[^=]+=' src/ tests/ --exclude-dir=Vendor`
3. **Zero placeholders.** No `TODO`, `FIXME`, `TBD`, no stub bodies. Complete at write time.
4. **Explicit failure paths.** Every fallible operation `pcall`-guarded or with a visible failure branch.
5. **Return `(ok, reason)`** rather than throwing across a boundary. Reasons are enumerated snake_case strings.
6. **Finiteness checked before arithmetic**, always.
7. **Pure logic separated from Roblox services**, so tests drive the real code.
8. **Inject `Random`** — never a hidden global RNG.
9. **Comments explain WHY**, citing threat IDs (`T-nn`), requirements (`FR-n.n`), ledger entries (`L-0nn`), findings (`F-Gn-n`).
10. **Never author code inside Studio.** Disk is the source of truth. (Pushing disk content *into* Studio to work around a dead sync is fine — that is what Rojo does.)
11. Tab indentation.

---

## 12. CONSTRAINTS AND REQUIREMENTS

### Absolute
- **No client message may carry** a price, balance, reward, score, level, duration, multiplier, or outcome. Client sends **intent**; server sends **truth**.
- **`RemoteFunction:InvokeClient()` nowhere.**
- **Exactly one `ProcessReceipt` assignment** in the place (T-17). Silent and catastrophic if violated.
- **`SetAsync` prohibited** for profile data.
- **`PurchaseGranted` only after the grant durably persists**; every other path returns `NotProcessedYet`.
- **No fabricated social proof or manufactured urgency.** No fake activity, no resetting countdowns. Standing operator instruction.
- **No `MessagingService`** in our code (`Vendor/` exempt).

### Performance
- 60 FPS desktop / 30 FPS mid mobile with 7 dice; client < 4 ms/frame; no per-frame allocation.
- Server < 0.5 ms per player per roll; cost scales with **die count**, never physics.
- All UI in `Scale` units, never fixed `Offset`. 320px → 4K.

### Process
- Build Tier **PRODUCTION**. Every change walks the 7 gates in `.brain/PIPELINE.md`.
- **The author of a diff may not audit it.** Gates 3–4 run in a separate context — Antigravity has been the cross-vendor path.
- **Always verify an auditor's factual claims against the repo before accepting its verdict.** Three audits so far; every one needed correction. The last produced 4 genuine findings including a real exploit.

---

## 13. WHERE THE MEMORY LIVES

Everything needed to reconstruct context is on disk and in git.

| Source | Contains |
|---|---|
| **`.brain/LEDGER.md`** | **Read first.** L-001…L-020, each with root cause and fix. Most relevant: **L-013** (a clean scoreboard over unexecuted work is worthless), **L-014** (enumerated audit briefs), **L-015** (per-entity behaviour vs aggregate state), **L-016** (coupling not curve-shaping — the simulation findings), **L-017** (modelling error ≠ design finding), **L-018** (audit misclassification), **L-019 / L-020** (green suites over stale code) |
| `.brain/SCOREBOARD.md` | Every pipeline run, rejections, defect classes. Honest, including failures |
| `.brain/skills/roblox_luau.md` | Roblox rules. **§6 = Luau syntax traps that cost real time** |
| `docs/blueprint/*` | The binding spec |
| `deliveries/evidence/` | Verbatim test output and both audit verdicts |
| `deliveries/audit-briefs/` | Reusable enumerated brief templates |
| `git log` | Every commit explains **why**. `git log --stat` is a real changelog |

**Claude Code in this repo:** `CLAUDE.md` auto-loads and points at the bootloader. Read `.brain/BOOT_DIGEST.md` first; parse the full governance files before proposing any file modification.

**An assistant without file access:** ask the operator to paste `.brain/LEDGER.md`, `docs/blueprint/SRS.md`, `HLD.md`, and `API_DATA_CONTRACT.md`. Those four give ~90% of the working context.

**Do NOT ask for the raw chat transcript** (`~/.claude/projects/c--RGame/*.jsonl`). It is ~1.1M tokens, mostly superseded work from two scrapped projects, and **contains a live Discord webhook URL in plaintext**.

---

## 14. EXACT NEXT STEPS

### Immediate — Block 3, remaining server (~1 session)
Blocks 1–2 are audited and clean. Nothing blocks construction.

Build: `ForgeService` (applies validated mass redistribution) · `DiceCatalog` (per-shape face counts, mass floors, budget caps — **`RollService.MASS_FLOOR` should move here**) · `UpgradeCatalog` · `Format` (suffix ladder, precision-safe to 1e300) · `ServerBootstrap` (wires services in dependency order, player lifecycle, `BindToClose`) · `tests/Fakes.luau` · UT-5…UT-8.

After this the **server is functionally complete**: a player could roll, forge, and persist — with no way to see any of it.

### Then — Block 4: the client (~2–3 sessions, the biggest chunk)
`src/Client/` is empty. Arena rendering · dice tumble-to-target animation · **forge panel with live preview** (the core screen) · HUD · retro-pixel menus.

The interesting problem is the animation: pre-authored tumbles resolving to the server's chosen face, so it looks like physics decided when it did not.

**First playable build lands at the end of this block.**

### Then — Block 5: monetization + leaderboards
`MonetizationService` · `LeaderboardService` · `ProgressionService` · `AscensionService` · `OfflineService`.
**The operator must create the Robux products** and supply the IDs; everything currently fails closed on `DUMMY_ID_*`.

### Then — Block 6: pre-launch
Full audit sweep · balance tuning against playtest data · the P-4 smoke checklist · publish.

### Standing habits
- **Verify the assertion count moved** after any test change. An unchanged count on a change that adds assertions means stale code (L-020).
- **Re-run the simulation** before retuning any balance constant (L-016).
- **Verify an auditor's claims** before accepting a verdict.

---

## 15. THE MCP SETUP (working — use it)

The **Roblox Studio MCP server is connected**. Tools available include `execute_luau`, `start_stop_play`, `get_console_output`, `multi_edit`, `script_read`, `search_game_tree`.

**Run the suite yourself:**
1. `get_studio_state` → confirm Edit mode
2. `start_stop_play(true)`
3. `get_console_output` → read the result
4. `start_stop_play(false)`

**Two operational gotchas, both learned the hard way:**
- **The Rojo plugin drops its connection on Play start/stop** (L-020). After editing files, verify the change actually reached Studio — probe a new symbol, or check the assertion count moved. Do not trust a green suite alone.
- **`multi_edit`'s dot-notation path cannot address a script whose name contains a dot.** `game.ServerScriptService.Tests.Payout.test` parses as `Tests → Payout → test` and fails. Use `execute_luau` with `FindFirstChild("Payout.test")` and direct `Source` assignment.

Keep MCP use lean — the operator has asked to conserve tokens. Batch queries into single `execute_luau` calls rather than many small ones.

---

## 16. THE ONE-PARAGRAPH VERSION

Dice Forge Incremental is a Roblox idle game whose core mechanic is a zero-sum mass budget on dice faces: heavier faces pay superlinearly more but land less often, so forging is a real trade-off. The server decides every outcome by weighted sampling and the client's 3D physics is pure animation — this is what makes the game exploit-proof, and it forbids any feature depending on where a die physically is. The maths was validated by simulation before any code was written and must not be retuned without re-running it. About 2,514 lines of our Luau exist across seven modules and five test files; **Blocks 1 and 2 are complete and have passed Gates 2, 3 and 4**, with 2,779 assertions passing live and seven audit findings folded in — including a real offline-earnings exploit the threat model had missed. The entire client is unbuilt and nothing is playable yet. The next task is Block 3: the remaining server services, then the client.
