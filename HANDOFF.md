# PROJECT HANDOFF — Dice Forge Incremental

**The descriptive project document. For an operator or an AI assistant picking
this up with zero prior context.**

Written 2026-08-06, **substantially rewritten 2026-08-26** after 129 commits had
made the status sections false. Repo: `C:\RGame` →
https://github.com/HitanshG07/Rgame-dice (**private**). HEAD: `0f7a3c7`.

Read top to bottom before touching anything. **Section 14 tells you exactly what
to do first.**

**How this document relates to the others.** This is the wide view — what the
game is, how it is built, and where it stands. Four companions go deeper:

| Document | Answers |
|---|---|
| `docs/blueprint/` (6 files) | *What must be true.* The binding spec, written before the code |
| `docs/ROADMAP.md` | *What happens next.* The plan to launch, in four phases |
| `docs/handoff-8.md` | *What happened last.* The most recent session record |
| `.brain/LEDGER.md` | *What has already gone wrong.* L-001…L-079, with root causes |

When this document and `docs/blueprint/` disagree, **the blueprint wins** — see §5.

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
├── HANDOFF.md                    this file — the descriptive project document
├── AI_WORKSPACE_RULES.md         governance bootloader — read before modifying files
├── CLAUDE.md / AGENTS.md / GEMINI.md   per-tool shims pointing at the bootloader
│
├── .brain/                       ← PROJECT MEMORY. See §13.
│   ├── BOOT_DIGEST.md            read FIRST every session
│   ├── LEDGER.md                 L-001..L-079. The accumulated lessons
│   ├── SCOREBOARD.md             every pipeline run, its rejections and defects
│   ├── PIPELINE.md               the 7 quality gates
│   ├── PERSONAS.md               the 5 role personas
│   ├── CHECKLISTS.md             Matrices A–G bound to each gate
│   ├── skills/roblox_luau.md     Roblox rules; §6 = Luau syntax traps
│   └── modes/                    behavioural modes (brainstormer, honest_advisor, …)
│
├── docs/
│   ├── blueprint/                ← THE SPEC. Binding. See §5.
│   │   ├── THREAT_MODEL.md       T-1..T-30, mitigations, risks R-1..R-8
│   │   ├── SRS.md                FR-1..FR-14, NFR-1..NFR-8
│   │   ├── HLD.md                architecture, authority model, module list
│   │   ├── API_DATA_CONTRACT.md  every remote + the profile schema
│   │   ├── TEST_PLAN.md          UT-1..UT-11, IT-1..IT-5, procedures P-1..P-4
│   │   └── DEVOPS_RECORD.md      ops decisions + dependency register
│   ├── ROADMAP.md                ← THE PLAN TO LAUNCH. Phases 0–3
│   ├── handoff-1..8.md           session records, newest = most authoritative
│   ├── GOVERNANCE_AUDIT.md       governance self-audit
│   └── antigravity_ui_redesign_prompt.md   the external UI-agent brief
│
├── deliveries/                   audit trail
│   ├── plans/                    Gate 0 plan artifacts
│   ├── audit-briefs/             enumerated Gate 3-4 briefs
│   └── evidence/                 verbatim test output + audit verdicts
│
├── src/                          ~28,900 lines of our Luau + 2,242 vendored
│   ├── Shared/   (3,518)  pure data + pure functions, safe to replicate
│   ├── Server/   (5,936)  sole authority
│   │   └── Vendor/ProfileStore.luau   (2,242 lines, pinned, DO NOT EDIT)
│   └── Client/   (19,407) presentation only — now the largest area by far
│
├── tests/        (5,102)  22 suites + RunAll.server.luau
└── tools/rojo.exe
```

**Rojo mapping** (`default.project.json`):
```
src/Shared  → ReplicatedStorage.Shared
src/Server  → ServerScriptService.Server
src/Client  → StarterPlayer.StarterPlayerScripts.Client
tests       → ServerScriptService.Tests
```

**Note the shape of it.** The client is roughly three times the server. That is
normal for this design and not a smell: the server holds no rigid-body state and
does almost nothing but sample, validate and credit, while the client carries the
entire 3D arena, the dice renderer, and seven UI panels.

---

## 5. THE SPEC IS BINDING

`docs/blueprint/` is not documentation-after-the-fact. It is the contract, written before the code, and every gate audits against it.

Each document opens with `CONSUMED-BY: Gate X / Matrix Y` naming the gate that reads it, and `STATUS: LIVING — amend on divergence; every amendment cites its triggering fact`.

**If code and spec disagree, that is a defect — not a doc that needs quietly updating.** Either fix the code or amend the document *with the fact that triggered the amendment*. Silent divergence killed the previous project. This has already happened once here and the **spec won** — see finding F-G3-1 in §10.

---

## 6. FILES, AND WHAT EACH DOES

**~28,900 lines of our Luau** across three areas and 22 test suites, plus 2,242
vendored. The entries below go deepest on the modules that carry the most risk;
the rest are tabulated after them.

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

### The rest of `src/Server/` — built since the original draft

| Module | Lines | What it does |
|---|---|---|
| `ServerBootstrap.server.luau` | 950 | Constructs services in dependency order, wires player lifecycle, starts the tick, registers `BindToClose`. Also holds the **shape-unlock branch at `:348-379`** — the working template for the element-unlock work in the roadmap |
| `ForgeService.luau` | 764 | Validates and applies mass redistribution as a **closed system**; applies element assignment and shape changes. Reads `diamondTree.Elements` at `:506` to gate which elements a player may assign — **that field is never written**, which is roadmap item 2 |
| `PurchaseService.luau` | 519 | The single `ProcessReceipt` assignment (T-17) and all gamepass entitlement checks |
| `ProgressionService.luau` | 485 | Quests, login streak, playtime chests, daily spin, codes, group rewards. **Daily spin and codes both work end to end** — they are missing only a button |
| `OfflineService.luau` | 457 | Rolling income-rate average, vault accrual, atomic claim. Rate floored at a 60s window (T-30) |
| `StateSyncService.luau` | 379 | Builds the periodic snapshot every client panel renders from. **Nothing may be added here carrying a price, balance or reward** (NFR-5) |
| `LeaderboardService.luau` | 256 | Log-scaled publication and cached retrieval |
| `AscensionService.luau` | 129 | Prestige reset and Diamond-tree purchases |
| `RateLimiter.luau` | 113 | Per-player per-remote token buckets |
| `BoostService.luau` | 66 | Owns boost timers. **`getMultiplier` is never called by anything** — roadmap item 4, and the one that involves real money |

### The rest of `src/Shared/`

`DiceMeshBuilder` (1,209) builds the dice geometry · `DiceCatalog` (490) per-shape
face counts, mass floors, budget caps, and the shipping constants
(`MAX_DIE_SLOTS = 12`, `ASCEND_MIN_LIFETIME_CASH = 1e6`) · `MonetisationCatalog`
(312) the fourteen purchasable entries — **carries no price on purpose**, because
Roblox owns pricing and a client-side figure would be contradicted by the
platform's own prompt · `GearMeshBuilder` · `VaultCatalog` · `SettingsCatalog` ·
`UpgradeCatalog` · `Format` (suffix ladder, precision-safe to 1e300).

### `src/Client/` — the live UI is the `V7` set

| Module | Lines | Status |
|---|---|---|
| `V7MenuPanel.luau` | 5,804 | **The big one.** Shop, ascend, vault, boards, slots, shapes, quests, settings. All seven refreshers fan out from `applyState` |
| `DiceRenderer.luau` | 1,501 | Tumble-to-target animation and instance pooling |
| `V7ForgePanel.luau` | 1,454 | The core screen — live preview via `ForgeMath`, one element chip per face |
| `UITheme.luau` | 1,401 | Shared theme, the `UIScale` typography system, and the overlay factory |
| `BoardView.luau` | 1,215 | Leaderboards |
| `V7HUD.luau` | 1,113 | Roll button, currency readouts, streak |
| `V7VaultOverlay.luau` | 806 | Offline earnings |
| `UIMockPreview.luau` | 721 | The external UI agent's scratch canvas. **Overwritten wholesale on each agent run** — never put anything load-bearing here |
| `AudioDirector.luau` | 423 | 9 `DUMMY_ID_*` placeholders; fails closed, Settings shows Music/SFX as LOCKED |
| `NetClient.luau` | 314 | The sole outbound wrapper |
| `ClientBootstrap.client.luau` | 375 | Loads and wires the V7 panels |
| `FeedbackFX.luau` | 618 | Payout-scaled feedback |
| **`ForgePanel` / `MenuPanel` / `HUD` / `CurrencyModels`** | **3,662** | **DEAD.** Superseded by the V7 set and loaded by no client code — but three of the four are still named by `tests/ClientContract.test.luau`, so deleting them means editing that suite too. Deletion is roadmap item 10 |

**`applyState` is the single most important function in the client.** It fans out
one state snapshot to all seven refreshers, each wrapped in its own `pcall` with a
warn on a missing refresher. That structure is not decoration — an unguarded throw
in the first refresher escapes into the StateSync handler and takes the other six
panels *and* the forge with it. That is **L-057**, and it has already killed seven
panels once.

### `tests/` — 22 suites

`RunAll.server.luau` is a **Script**, not a ModuleScript. A module that fails to
`require` is reported as a **FAILURE, never skipped**; zero discovered suites is
also a failure. Terminates with `=== SUITE COMPLETE: X passed, Y failed ===`.

Each suite returns `{ name, run = function(): (boolean, string?, number) }` —
passed, failureMessage, assertionCount.

`RemoteContract.test.luau` deserves a specific mention: **six files must agree for
a new remote to exist**, and that suite fails loudly if any one is missed. When it
fails during remote work, it is doing its job — it is not an obstacle to route
around.

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

## 9. THE GAME AS A PLAYER MEETS IT

The spec describes requirements. This section describes the experience, because
no other document does.

### The loop, in one minute

You spawn over a low-poly pit. You press **ROLL**. Dice tumble in, land, and a
number floats up. That number is Cash. You press ROLL again.

Within a few minutes you have enough Cash to open the **Forge** — and this is the
moment the game either lands or does not. The forge shows your die as a ring of
faces, each with a mass. You drag mass from one face onto another. Every number on
the screen moves as you drag: the face's payout, its landing chance, your expected
value per roll, and your Void chance.

**You never gain mass. You only move it.** Making face 6 pay four times more makes
it land less often, and drains the faces you took from. There is no "buy the
upgrade" button in the forge — only a trade.

### What opens up, roughly in order

| Stage | What appears | The decision it introduces |
|---|---|---|
| First minutes | Roll, Cash, the Forge | Where does mass go? |
| Early | **Void faces** and the **streak** | A face at the floor pays nothing and lands *most* often. Concentrating mass buys power with streak risk |
| Early-mid | **More dice** (up to 12 slots) | Dice interact. A second die is not 2× — it is a partner |
| Mid | **Elements** — Fire, Gold, Freeze, Multiplier | Gold pays **only if another die also lands Gold**. Now your dice have *roles* |
| Mid | **Shapes** — D4…D20 | Not a ladder. D4 is a volatile sniper (~33% Void), D20 a steady grinder (~5%) |
| Mid-late | **Ascension** — reset for Diamonds | Give up Cash and dice to buy permanent tree nodes |
| Late | **Streak Strength** in the Diamond tree | The deepest lever in the game — see below |
| Throughout | Vault (offline earnings), quests, boards, shop | The idle-game scaffolding |

### Why Streak Strength is the point

The streak multiplier is `(1 + b)^streak`, and **`b` is bought by the player** in
the Diamond tree rather than being a global constant.

Simulation before any code was written found a **cliff at `b ≈ 0.15`**. Below it,
few faces win: concentrate mass, accept Voids, take the big hits. Above it, many
faces win: spread mass, never break the streak, grind.

So two players with the same dice and the same Cash, who invested differently in
one tree node, have **genuinely different optimal builds**. That is the whole
design bet: the game produces *decisions* rather than purchases, and decisions
retain players where purchases do not.

### The honest caveat, recorded openly

The odds genuinely follow the mass you forged — `P(face i) ∝ (M − mᵢ)` — so your
mental model is entirely correct. But it is **arithmetic, not collision solving**.
The tumble you watch is animation resolving to a face the server already chose.
This is recorded as accepted risk **R-1** rather than concealed, and §2 explains
why it cannot be otherwise.

---

## 9b. CURRENT IMPLEMENTATION STATUS

**Everything above is built and playable.** That is the headline change from the
original draft of this document, which said the client was empty.

### Verified working — executed live in Studio, output captured

```
=== SUITE COMPLETE: 21 passed, 0 failed ===   3,569 assertions
```

Run in a live Studio session, not inferred from reading code. Twenty-two suite
files exist; `Fakes.luau` is a helper, not a suite.

### What works end to end

Rolling · forging · elements · streaks and the shield · shapes · dice slots ·
ascension and the Diamond tree · the vault and offline earnings · quests, login
streak and playtime chests · leaderboards · settings · persistence with session
locking and fail-closed loading · the full V7 UI.

### What is built but not reachable

- **Daily Spin** — remote, handler and client wrapper all work. **No button.**
- **REDEEM code** — backend fully works, button drawn, **no click handler**.
- **Group Rewards** — complete and correct, deliberately unplugged (`GROUP_ID = 0`).

### What takes currency and delivers nothing

**This is the most important line in this section.**

- **Luck Boost / Offline 2x** cost **real Robux**. `BoostService.getMultiplier` is
  never called by anything. The player gets a countdown that does nothing.
- **MassCeiling / SlotNodes** cost Diamonds, store the level, and display it. Each
  has exactly **one read in the whole codebase, for display only**. The real caps
  still come from a flat constant and from ascension count.

Nothing should ship in this state. It is **Phase 0** of the roadmap.

### What is decoration

- **Trait Forge** — the panel is drawn, but no trait or shard concept exists in
  `src/Server/` or `src/Shared/` at all. Currently held inert behind one switch.
- **Element unlocks** — `Diamond.Elements` is *read* to gate elements and **never
  written**, so every player is stuck on plain faces forever.

### Known blockers

| Blocker | Owner |
|---|---|
| **158 Script Analysis warnings** (NFR-8 requires zero) | Code. Decide the `Vendor/ProfileStore.luau` policy first — 2,242 lines that must not be edited |
| **9 audio asset IDs** | **Operator.** Cannot be done in code |
| **A real `GROUP_ID`** | **Operator.** Cannot be done in code |
| **Robux product IDs** | **Operator.** Agents never create monetized assets |

Shipping constants are already at release values: `ASCEND_MIN_LIFETIME_CASH = 1e6`,
`PLAYTEST_DIE_COUNT = 0`, `MAX_DIE_SLOTS = 12`.

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
| **`.brain/LEDGER.md`** | **Read first.** L-001…L-079, each with root cause and fix. Most relevant on **design**: **L-015** (per-entity behaviour vs aggregate state), **L-016** (coupling not curve-shaping — the simulation findings). On **process**: **L-013** (a clean scoreboard over unexecuted work is worthless), **L-017** (modelling error ≠ design finding), **L-019 / L-020** (green suites over stale code), **L-051** (a metric merely NEAR the property certifies a broken build). On **the client**, which is where the recent entries cluster: **L-057** (a `nil` in an `ipairs` fan-out silently cancels everything after it — the one that killed seven panels), **L-058** (`TextFits` reports truncation, not containment), **L-061** (the Luau 200-register limit on large UI builders), **L-062** (hardcoded pixel dimensions break cross-modal parity) |
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

**`docs/ROADMAP.md` is the authority here.** This is the summary; that document
has the worked examples and the reasoning.

### The governing rule the operator set

> **Build the UI once, freeze it, then do backend only.**

The alternative — port a screen, return later for another feature, reopen it a
third time — is exactly how this codebase broke before. The failure log records
the cause as *"the visual layer was rebuilt and the wiring behind it was not
re-checked."* Touching each panel once removes that entire class of failure.

**The freeze rule:** once UI is signed off, connect buttons to real functions and
replace placeholder values with real ones — but **never move, resize, restyle or
re-lay-out anything.** If wiring cannot be done without a visual change, **stop and
ask the operator** rather than deciding alone.

### The four phases

**Phase 0 — stop charging for nothing.** Pure backend, no screen touched, so it
does not conflict with UI-first and can run while the UI agent designs. Boost
multipliers (the hook already exists and is already guarded at
`RollService.luau:302`, hardcoded to `1` at `:458`) · MassCeiling and SlotNodes
feeding the real caps · the REDEEM click handler, one line.

**Phase 1 — all UI, finalised then frozen.** Only two new screens exist: the
element-unlock section (into the Shapes panel, which already does "unlock a thing
with currency") and Daily Spin (a single control). External UI agent, **one panel
per run**.

**Phase 2 — backend only, against frozen UI.** Element unlocks · Daily Spin
wiring · Trait Forge, the largest item.

**Phase 3 — cleanup and launch readiness.** Delete the 3,662 dead lines · Script
Analysis to zero · the operator-supplied IDs.

### Three traps that will bite silently

1. **Currency fallthrough.** `EconomyService` uses one explicit branch per
   currency and its `else` returns **Diamonds**. A missed branch for a new
   currency reads the wrong balance and *does not error*. No test pins the
   currency list — add one.
2. **Per-die migration.** `Profile.Dice` is a flat positional array (**the index
   IS the slot**), and the reconcile logic deliberately **never descends into
   arrays**. Any new per-die field needs an explicit entry in the per-die loop at
   `PlayerProfile.luau:325`, following the `PurchasedBudget` precedent directly
   above it.
3. **The remote contract.** Six files must agree for a new remote.
   `tests/RemoteContract.test.luau` fails loudly if any is missed — intended
   behaviour, not an obstacle.

### Standing habits

- **Verify the assertion count moved** after any test change. An unchanged count
  on a change that adds assertions means stale code (L-020).
- **Re-run the simulation** before retuning any balance constant (L-016).
- **Verify an auditor's claims** before accepting a verdict.
- **A green build says nothing about types.** Rojo does not type-check and there
  is no CLI type-checker in this repo. A declaration-order defect that would have
  thrown on every snapshot built perfectly cleanly. Studio's analysis pane is the
  only mechanical check that exists.
- **A stub is a present function.** Four refreshers once had bodies consisting of
  a single comment; they were called on every snapshot and did nothing, and the
  panels rendered perfectly. A silent console is not proof a panel is live.
- **When a number and a screenshot disagree, the screenshot wins.**

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

Dice Forge Incremental is a Roblox idle game whose core mechanic is a **zero-sum
mass budget** on dice faces: heavier faces pay superlinearly more but land less
often, so every forge is a genuine trade-off rather than a purchase. The server
decides every outcome by weighted sampling and the client's 3D physics is pure
animation — this is what makes the game exploit-proof, and it forbids any feature
depending on where a die physically is. The maths was validated by simulation
before any code was written and must not be retuned without re-running it; the
deepest lever is **Streak Strength**, a player-bought value with a cliff at
`b ≈ 0.15` that makes genuinely different builds optimal for different players.
About **28,900 lines** of our Luau now exist across three areas plus 2,242
vendored, with **21 suites and 3,569 assertions passing live**. The game is
**playable end to end** — rolling, forging, elements, streaks, shapes, ascension,
the vault, quests, boards and persistence all work. What remains is not new
systems but **finishing**: two purchase paths currently take currency (one of them
**real Robux**) and deliver nothing, three built features have no button, the
Trait Forge is decoration, ~3,700 lines of superseded client code are dead, and
158 Script Analysis warnings stand against a zero-warnings requirement. The plan
to close all of it is `docs/ROADMAP.md`, and its governing rule is the operator's:
**build the UI once, freeze it, then do backend only.**
