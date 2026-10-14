# FUTURE UPDATES — features that are half-built, unreachable, or never made

**Written:** 2026-09-17 · **Swept against HEAD `7874a1c`** (Antigravity mid-batch-5,
working tree dirty) · Branch `finalized-ui-revamp-whole-repo`

Companion to `criticalbugfix.md`. **That file is about things that are broken.
This one is about things that are *absent* — and specifically about how much of
each is already sitting in the codebase waiting for a caller.**

Three parallel sweeps: server + shared, client, and spec-versus-code. Every
headline finding below was re-verified by hand before being written down.

---

## RESOLVED 2026-10-14 - the headline below is no longer true; the analysis is kept

**The finding under "READ THIS FIRST" (seven of nine upgrades cannot be bought) was resolved by `34f4777` on 2026-10-14.** Two purchase surfaces now exist: `src/Shared/UpgradeView.luau` (a pure row builder over the catalogs, so no id is hardcoded in the client), a new **UPGRADES & DIAMOND TREE overlay** in `V7MenuPanel.luau` that calls `NetClient.buyUpgrade` / `NetClient.buyDiamondNode` from the enumerated rows, and an **UPGRADES pod in `V7HUD.luau`** that opens it. `Luck` is also back, restored as a Cash upgrade folding into the `LuckBoost` term (max level 1.40x, below the paid 2x), which is what the operator asked for in the table row that says "removed by `7874a1c`".

**Everything below that heading is the 2026-09-17 reasoning, left intact on purpose** - why it dwarfed the rest, the correction about the streak cliff costing 8,730 Diamonds being wrong in the game's favour (it was unpurchasable, not expensive), and the "highest value-per-effort item in the project" argument all still explain why the work was prioritised.

**What is NOT established:** nothing has been run in Studio since `34f4777`. The overlay exists, is wired by reading, and has never been opened in a running game. Gate 2 has not passed. Treat "resolved" as "built and committed", not "verified". Whether the streak cliff at `b ~ 0.15` is now actually *reachable at a sensible price* is a balance question nobody has answered: `StreakStrength` is buyable, but its cost curve has never been playtested.

**F-7b (TRAITS) - the "ACTIVE" badge is also resolved.** The section header now reads **"COMING SOON"** (`V7MenuPanel.luau`, `buildSectionHeader(traitsBox, "TRAIT FORGE & INSPECTION", "COMING SOON", ...)`), so the one-line honesty fix F-7b asked for has landed. The rest of F-7b is untouched: backend 0%, the whole feature is still unbuilt, and the ~15% honest-scoping paragraph stands. Line numbers quoted in F-7b predate the Phase 3 deletion and the new overlay and have drifted.

**Other changes since this file was written (2026-09-17):** Phase 3 executed (`ForgePanel`, `MenuPanel`, `HUD`, `CurrencyModels` deleted, 3,662 lines) - see `docs/legacy_harvest.md` for what was and was not carried over. Several F-items that cite those four files (F-3 Statistics panel, F-28 CurrencyModels, F-29 and parts of F-2) now point at deleted code; retrieve with `git show 0e7b361:src/Client/<File>.luau`. The "HARVEST BEFORE PHASE 3" section near the end is historical.

**The `handoff-N.md` files cited in this file were deleted on 2026-10-14** (`HANDOFF.md` replaced all nine). Retrieve any with `git show c73774f:docs/handoff-2.md` (use `c73774f` or any earlier commit). F-18 cites `handoff-1.md` s4A, F-19 cites `handoff-2` s2-a, F-20 cites `handoff-2` s5-c.

---

## ⚠ READ THIS FIRST — one finding dwarfs the rest

### **Seven of the nine upgrades in the game cannot be bought by anyone.**

The client has exactly **two** purchase paths into the upgrade system:

| Call site | What it buys |
|---|---|
| `V7ForgePanel.luau:1241` | `NetClient.buyUpgrade("MassBudget")` — **hardcoded to one id** |
| `V7MenuPanel.luau:1188` | `NetClient.buyDiamondNode(inspectedShapeId)` — **a shape id**, which routes to the shape-unlock branch |

That is the whole surface. Verified by grep: those are the only two call sites in
`src/Client/`.

**Nothing can reach these seven, all of which are fully implemented server-side —
costed, capped, reset correctly on ascension, and wired to real gameplay effects:**

| Upgrade | Currency | Effect that already works | Reachable? |
|---|---|---|---|
| `AutoRollSpeed` | Cash | `RollService.autoInterval` | **No** |
| `VaultCapacity` | Cash | `OfflineService.getCapacity` | **No** |
| `VaultEfficiency` | Cash | `OfflineService.getEfficiency` | **No** |
| `Luck` | Cash | *(removed by Antigravity `7874a1c`; operator wants it back as a LuckBoost add-on)* | **No** |
| **`StreakStrength`** | Diamonds | `RollService.streakStrengthToB` | **No** |
| **`MassCeiling`** | Diamonds | grants mass onto the lightest face | **No** |
| **`SlotNodes`** | Diamonds | feeds `dieSlotCapFor` | **No** |

`UpgradeCatalog.getAllDiamondNodes()` — the enumerator a tree UI would loop —
has **zero callers anywhere**. `getAllCashUpgrades()` has two, both in tests.
These are finished accessors written for panels that were never built.

### I have to correct something I told you earlier today

Earlier I reported that the streak's design cliff (`b ≈ 0.15`) **"costs 8,730
Diamonds ≈ 9 trillion-dollar ascensions."** That was wrong, and wrong in the
game's favour.

**It is not expensive. It is unpurchasable at any price.** `StreakStrength` has no
buy path, so `b` is permanently `0`, so `(1+0)^streak = 1` for every player
forever. The MULT chip reads "LOCKED" and always will.

Which means **the sniper/grinder fork — the crossover the pre-code simulation was
built to prove, the thing `FR-5.4` calls "the primary build-defining axis" — is
not reachable in the shipped game at all.**

It also means **my own Phase 0b work is unreachable.** I wired `MassCeiling` to
grant mass and `SlotNodes` to add slots, verified both in a running game, and
shipped them. Both sit behind a door with no handle. The fixes were correct; the
door was never part of the ticket, and I did not check for it.

### What this actually needs

**Two panels.** Both enumerate an existing catalog and call an existing remote:

1. **A Diamond tree panel** — loop `getAllDiamondNodes()`, show level / cost /
   effect, call `NetClient.buyDiamondNode(nodeId)`. The handler, costs, caps,
   persistence and effects all exist.
2. **A Cash upgrade shop** — loop `getAllCashUpgrades()`, call
   `NetClient.buyUpgrade(id)` with something other than a hardcoded string.

Everything behind both is done. **This is the highest value-per-effort item in
the entire project** and it is not currently on the roadmap.

---

## STATUS LEGEND

| | |
|---|---|
| **~N% done** | How much already exists in code |
| **SEAM** | Deliberately left open — a comment or an unused accessor proves intent |
| **LEFTOVER** | Abandoned; no evidence anyone meant to come back |
| **LOSS RISK** | **Will be destroyed by the Phase 3 deletion unless harvested first** |

---

# TIER 1 — nearly done, small effort, real feature

## F-1 · The entire audio layer ships when you paste 9 asset IDs
**~90% · SEAM** · `AudioDirector.luau:75-131`

A complete 9-cue engine: `RollPress`, `RollLand`, `VoidHit`, `StreakUp`,
`UiClick`, `UiRefused`, `PanelOpen`, `PanelClose`, plus an arena music loop —
each with a per-cue mix volume and a per-cue voice-pool depth (roll cues get 2–3
voices, UI cues 1), round-robin allocation, and fail-closed behaviour on
`DUMMY_ID_*`.

The module's own comment costs the remaining work: *"later is a one-line-per-cue
edit to `ASSET_IDS` and no other change anywhere."* The capability path already
exists too — the moment real ids land, `setCapability("audio", true)` un-greys
the Music and SFX toggles automatically.

**Needs:** 9 uploaded asset IDs (**you**), then ~9 `AudioDirector.play` calls.

## F-2 · The client cannot tell the player anything went wrong
**~0% in V7, ~100% designed in a file about to be deleted · LOSS RISK**

`Remotes.Notice` enumerates seven refusal codes — `rate_limited`,
`invalid_request`, `insufficient_funds`, `not_unlocked`, `at_cap`,
`profile_unavailable`, `server_error`. `NetClient.onNotice` exists.

**Nothing subscribes, and no V7 surface has a status line at all.** Every refusal
from every panel except the forge is currently silent.

The fix is already written twice, in `HUD.luau:415-443` and
`MenuPanel.luau:436-455`: one pooled label, 4-second expiry driven by the
heartbeat already ticking rather than a thread per message, and a token guard so
an earlier timer cannot clear a later message.

**Harvest it before Phase 3 deletes those files.**

## F-3 · Rebuild the Statistics panel — it makes three dead fields live
**~100% designed, 0% in V7 · LOSS RISK** · `MenuPanel.luau:607-687`

Nine stat rows (Cash, Gems, Diamonds, Streak, Die Slots, Lifetime, Best Roll,
Rolls, Ascensions) plus a per-die breakdown — `DIE n | Shape | MASS | VOID%` —
monospace-aligned, with an honest "waiting for the first snapshot" caption.

**V7 has nine overlays and no Statistics surface.** This is the direct explanation
for `lifetimeCash`, `highestRoll` and `totalRolls` being shipped by the server and
read by nobody: *the panel that consumed them was deleted and never rebuilt.*

## F-4 · Loadout reordering — everything but the gesture exists
**~85% · SEAM** · `NetClient.swapDice:224`, handler `ServerBootstrap:644-676`

The remote is complete, validated, race-safe (it re-reads bounds inside the
mutation), rate-limited, and was built to an explicit operator request: *"in forge
there has to be an option for you to select which dice sits on which slot."*

**Nothing calls it.** Meanwhile the Die Slots overlay already has per-slot cards,
`SLOT %02d` formatting, empty-slot states and a "SELECTED" pill. Every ingredient
of tap-two-to-swap is on screen.

## F-5 · Per-element proc feedback — the server already sends the data
**~50%, server side 100% · SEAM** · `RollService.luau:535`

`RollResult` carries **`elementsFired`** — the list of which elements procced —
on *every single roll*. **No client module reads it.**

`ElementCatalog` exists, `UITheme.elementColor` exists, `DiceRenderer` already has
a per-die overlay layer and knows which face landed. The server goes out of its
way to assemble this array every roll and it is thrown away.

## F-6 · `serverTime` is sent for countdowns nobody draws
**SEAM** · `StateSyncService.luau:325`

Shipped specifically so the client can render countdowns against *server* time
rather than its own clock. Read by nothing. It is the missing half of **three**
features at once: the boost countdown (roadmap 1c), the Starter Bundle expiry, and
a daily-reset timer on quests.

## F-7 · `onForgeResult` carries the real, authoritative forge price
**~70% · SEAM** · fired at `ForgeService.luau:461`, subscriber: none

The server fires `{ dieIndex, distribution, cost, ok }` after every forge. **`cost`
is the only place the true price ever crosses the wire** — the panel currently
re-derives an estimate from `ForgeMath.forgeCost` instead. Subscribing turns an
estimate into a receipt, and lets the panel recover from a server-side correction.

---

## F-7b · TRAITS — the largest drawn-but-empty surface in the game
**UI ~40%, backend 0% · SEAM** · `V7MenuPanel.luau:4125-4572`

Tracked in `docs/ROADMAP.md` as Phase 2c, but it belongs here too, because **the
UI already specifies the design in enough detail to build from** — and because it
is the only feature whose panel carries a currency that does not exist.

**What is on screen right now:**

| Element | Where | State |
|---|---|---|
| A whole quadrant, titled **"TRAIT FORGE & INSPECTION"** | `:4125` | Badged **"ACTIVE"** — which is untrue |
| The overlay's own title: **"~ Slots & Trait Forge ~"** | `:3655` | Half the panel's name is a feature that does not exist |
| **Two trait slots per die** | `:4421`, `:4492` | `"TRAIT 1: NOT YET AVAILABLE"`, `"TRAIT 2: NOT YET AVAILABLE"` |
| `createTraitEmblem` — real 28×28 emblem geometry | `:3867` | Built, drawn |
| **REROLL** | `:4323` | Inert via `setTraitControlInert` |
| **KEEP TRAITS** | `:4531` | Inert |
| **REROLL ALL** | `:4555` | Inert |
| A **ShardDeck** reading `◆ -- SHARDS` | `:4277-4313` | A fourth currency, named on screen |

**What exists server-side: nothing.** `grep -rli "trait" src/Server/ src/Shared/`
returns **zero files**. No schema field, no remote, no catalog, no test, and no
Shards currency anywhere in `PlayerProfile`, `EconomyService` or the snapshot.

### The design is already legible from the UI, and worth writing down

The three controls imply a complete mechanic that nobody has specified in prose:

- **Two trait slots per die** — so traits are per-die, not per-account. That
  matches the roadmap's note and confirms the six-site per-die problem below.
- **KEEP TRAITS + REROLL** is a **lock-and-reroll** loop — keep the trait you
  like, reroll the other. That is a deliberate, familiar mechanic, not a plain
  randomiser.
- **REROLL ALL** is the bulk action, so rerolling is expected to be repeated.
- **Shards** is the sink. A separate currency implies traits are *not* meant to
  compete with Cash (the forge) or Diamonds (prestige) for the same wallet.

### Why this is the most expensive item in the file, despite the UI existing

`criticalbugfix.md` §`DIE-1` already records that **a new per-die field must be
added in six places, and three of them DELETE it** — `performSetShape` and
`repairDie` both rebuild the die as a fresh four-field literal, so traits would
survive until a player's first shape change and then vanish. `StateSyncService`
builds the dice payload field-by-field too, so traits would never reach the client
and the cause would look like a UI bug.

And §`CURR-1` records that **a new currency touches 23 sites**, with the Diamond
fallthrough compiling silently once the union is widened.

**Both of those must be fixed before any trait code is written**, not during.

### Honest scoping

The panel makes this look ~40% done. It is closer to **15%** — the drawn surface
is the cheap part. What is missing: `TraitCatalog` in `src/Shared/`, the Shards
currency across 23 sites, per-die storage across six sites, a shard earning path,
a `RerollTraits` remote across six files, and the reroll RNG (server-seeded — a
reroll is a random, value-bearing action and must never be decided by the client).

**One thing to fix cheaply and immediately, regardless:** the section header says
**"ACTIVE"** over three dead buttons. That is the same class as the invented
`"+$2,500 CASH"` quest reward — a surface asserting something untrue. Changing it
to `"COMING SOON"` is a one-line honesty fix that does not wait for the feature.

---

# TIER 2 — half-built systems

## F-8 · `VaultSummary` — the "welcome back" moment, declared and never fired
**SEAM** · `Remotes.luau:67`, subscriber `NetClient.onVaultSummary:293`

Declared in the contract with `{ accrued, wouldHaveAccruedAtPeak, capacity,
efficiency }`. **No server code ever fires it.** This is the single thing an idle
player opens the game for, and `OfflineService.getStatus` already computes every
field it needs.

Note `wouldHaveAccruedAtPeak` **appears nowhere in the repository** — the contract
describes it as teaching "that leaving well-tuned pays more". That teaching moment
was never built.

## F-9 · `FR-8.5`'s vault welcome screen — three separate pieces, none built
**NOT BUILT**

The spec: *"On return after 5+ minutes away, a welcome screen shows the accrued
amount with a standard claim and a Robux 2× claim."*

- **No 5-minute return trigger exists anywhere.** The vault is seen only if the
  player opens the panel themselves.
- **There is one claim button, not two.**
- **There is no Robux 2× point of sale.** `OfflineX2` exists as an entitlement and
  applies if already owned — but nothing in the vault flow ever offers it. *The
  product has no point of sale in the flow the spec designed it for.*

## F-10 · `Freeze` runs invisibly — one field short of being seen
**~85%** · `RollService.resolveElements:222-235`

`Freeze` is the only element with cross-throw state: it picks a partner die,
re-samples it next throw, and keeps the better result. The mechanic **works**.

But `emitResult` sends `faces, payout, streak, multiplier, elementsFired,
voidHit` — **not `frozenDie`**. The client cannot draw which die is frozen, so the
most interesting element in the game is mechanically live and visually absent.

## F-11 · `FR-11.2` — the leaderboard's own-rank line
**PARTIAL, three shortfalls**

Spec: *"top 100 with avatar, username, rank and value, plus the local player's own
rank regardless of position."*

- **Top 50, not 100** (`GetSortedAsync(false, 50)`)
- **No avatar** — a single initial letter; no `rbxthumb://` anywhere in `src/`
- **"Own rank regardless of position" is not built.** `getPlayerRank` scans only
  the cached page and returns `nil` outside it — the comment admits it. *The
  requirement's entire point is the rank-9000 player, and that is exactly the case
  that returns nothing.*

*(Leaderboard **writes** were fixed by Antigravity at `7874a1c` — `updatePlayer` is
now called on exit, on a 60s loop, and in `BindToClose`.)*

## F-12 · `FR-10.3` — playtime chests, two gaps
**PARTIAL**

- **"Free forge mass" was never implemented as a reward kind.** The spec names
  Cash, Gems *or free forge mass*; `CHEST_REWARDS` has only the three currencies.
  **The one reward that ties chests to the core mechanic does not exist.**
- **The timer the player sees is client-clocked.** `V7MenuPanel:1823` runs a local
  `os.clock()` stopwatch; the snapshot carries **no session or chest state at
  all**. The server re-checks on claim, so the two can disagree, and reopening the
  panel restarts the local clock.
- Spec says 5/15/45; the code ships **six** tiers (5/15/30/45/60/90) — an
  unrecorded expansion.

## F-13 · The multi-die loadout / bench system is ~70% real
`UnequipDie` removes a die but does not decrement `DieSlots` or touch `Inventory`;
re-equipping goes through `performSetShape`'s "next empty slot" branch gated on
the inventory quota. So *own N, equip a subset* mostly works — with no explicit
equip remote and no bench concept.

Related: **ascension wipes `Inventory` to `{ D2 = 1 }` while `Diamond.Shapes`
survives.** Cash-bought duplicate dice are destroyed by prestige but the right to
re-buy them is kept. That may be intended; it is the one place the newer
`Inventory` model and the older `Shapes` model disagree about what prestige means.

## F-14 · `Notice`, `EventState`, `VaultSummary` — three declared events, no emitters
The contract's own 2026-08-07 amendment says *"A specified-but-unimplemented event
is a defect in the contract, not merely an absence in the code."* Three of six
rows still have it.

---

# TIER 3 — specified, never built

## F-15 · The Like Goal → 3× Cash event loop
**Client ~100% designed, server 0% · LOSS RISK** · `HUD.luau:358-412`

A community like-count progress bar that, on reaching target, **is replaced in the
same HUD slot** by a "3× CASH EVENT ACTIVE" banner. The design reasoning is
recorded: the banner takes the bar's slot precisely because the event fires *as a
result of* the goal completing.

There is also a deliberate anti-dark-pattern note — no countdown is drawn, because
a timer is *"the exact shape of the manufactured-urgency pattern the operator
prohibited."*

**The roadmap lists Like Goal as "dropped, cut not deferred."** That decision was
made on the grounds that it needs live like-count integration. Recording here that
a complete client design exists, so the decision can be revisited with full
information rather than re-derived.

## F-16 · "AUTO SPEED" — a planned feature named nowhere else
`MenuPanel.luau:315-318` · **LOSS RISK**

A configurable auto-roll interval. `setAutoRoll` is boolean-only *by deliberate
design* — *"a client that could name its own interval would be naming its own
income rate"* — so this ships as **tiers the server prices**, which is a natural
Gems or gamepass sink. The idea survives nowhere in V7.

## F-17 · `FR-13.5` — chest and spin entry points in the bottom bar
Spec puts playtime chest and daily spin entry points in the bottom bar. Neither
exists; chests are buried inside the Quests overlay, a different surface entirely.

## F-18 · Element unlock ladder — the costs exist only in prose
`handoff-1.md` §4A records the proposal: **Fire 25 / Multiplier 40 / Freeze 70 /
Gold 120** Diamonds, with the reasoning that **Gold should be last** because
conditional elements only make sense with multiple dice.

**`ElementCatalog` has no cost, ladder, prerequisite or currency field at all.**
Whoever builds unlocks must author those four fields first — the roadmap's
estimate assumes they can be copied, and they cannot.

---

# TIER 4 — design decisions never made

These are not code gaps. **They are questions asked of you that were never
answered, so nothing was built.**

## F-19 · The Void mechanic is invisible for the entire early game
**No decision on record** · `handoff-2` §S2-a

> *"i dont get the concept of the void face here — i dont see any void faces appearing what so ever"*

A Void needs `mass <= massFloor × VOID_FLOOR_FACTOR` (~1.5). The starting D2 sits
at 30/30. So **the single most distinctive mechanic in the design is unreachable
during the entire first session.**

Three options were put to you — raise `VOID_FLOOR_FACTOR`, ship an uneven starting
die, or teach it in the forge. **None was chosen and nothing was built.** This is
the highest-value unbuilt item that is not simply a missing panel: it is a
first-session comprehension gap in the game's core concept.

## F-20 · Dice roll/fall animation quality
**No spec agreed** · `handoff-2` §S5-c

> *"we need to optimize and make the aniamtion of the dice rolling and falling on the board to be better"*

Never closed, because it was never scoped. The answer on record: *"Subjective and
open-ended. Would want specifics on what reads wrong — too fast, too floaty, wrong
settle, no impact."* **Needs you to name the failure mode.**

## F-21 · Tiered vault rates — a change of model, not a multiplier
> *"offline vaults earning rate we will set it as a fixed rate for normal standard users / people who buy vip in game / people who have roblox premium… we can decide on that later on"*

What shipped is tiered **efficiency on top of the player's own rolling average**.
You asked for a **fixed rate per tier**. Seam is `OfflineService.getEfficiency`.
Roblox Premium detection needs no new product.

Note `vault.hasPremium` **is already in the snapshot and read by nothing** — so a
Premium player's tier is currently invisible to them either way.

## F-22 · Seven dice shapes have never been balance-validated
**My own finding, verified independently**

`FR-6.1` names **five** shapes: D4, D6, D8, D12, D20. The game ships **twelve** —
and **D2, the starting die, is not in the spec at all.**

This matters because of what sits behind FR-6: the void probabilities in `FR-6.2`
came from a simulation run on five shapes, and **`FR-6.3` explicitly states that "a
build where one shape wins at every `b` is a balance defect"** — a property nobody
has ever checked across twelve.

`UT-14 Balance` has **4 assertions and names no shape at all.** The only tests
touching D3/D5/D7/D10/D14/D16 are forge *validation* tests.

Suggestive: **D7 and D14** — two of the seven unspecified shapes — are exactly the
pair `FORGE-2` found could not be forged at all. Content added outside the spec
did not get the spec's scrutiny.

---

# TIER 5 — tooling and infrastructure already built

## F-23 · `arbitratesChildren` is a working UI-layout linter with no caller
`UITheme.luau:1345` · **~100% done**

A runtime auditor that detects overlapping hand-positioned siblings, with an
auditable `LayoutExempt` attribute escape hatch. Written to be run over live
panels in Studio. **Nothing runs it.** Given how many layout defects this project
has hit, a dev tool that finds them mechanically is worth wiring to a command.

## F-24 · An entire second-generation component system, unused
**14 functions in `UITheme` with zero callers**

`toggle` (animated pill switch), `listRow` (collision-proof text + action
columns), `card`, `actionButton`, `statusPill`, `verticalStack`, `paragraph`,
`smallPrint`, `createProgrammaticIcon`, and five more.

The comments name the exact defects they were written to eliminate — *"OWNED"
drawn through "USE 5◆"*, *shop blurb struck through by small print*. **Then
V7MenuPanel and V7ForgePanel were written in the old hand-positioned style
anyway.** `UITheme.toggle`'s own comment records that it *was* wired up and then
removed rather than fixed after a crash — and V7's settings rows now use the
ambiguous ACTIVE/INACTIVE text buttons its docstring argues against.

## F-25 · `UIMockPreview` — an in-game design A/B browser
`UIMockPreview.luau`, 721 lines, **zero references**

Three complete, finished redesigns of the roll result bar, plus a floating
variant-switcher. Two opportunities: adopt one of the three designs, or **wire the
harness itself as a reusable in-game design tool** — `select(variantId)` at `:708`
is a stub whose body is literally `-- Switch`.

⚠ **The Antigravity UI prompt overwrites this file wholesale on every run.**
Anything kept here must be moved elsewhere first.

## F-26 · The `source` taxonomy — a complete economy telemetry set with no sink
**The biggest unbuilt seam in the server**

Every currency movement already carries a source string: `roll`, `forge`,
`buy_upgrade`, `unlock_shape`, `vault_claim`, `daily_spin`, `code_redemption`,
`group_reward`, `quest_*`, `chest_*`, `login_streak`, plus `*_refund` variants.

`EconomyService.credit` says *"`source` is recorded for telemetry"* — **it is
recorded nowhere.** It is interpolated into warn strings on refusal and used once
as a behaviour switch. A complete, already-threaded faucet-and-sink taxonomy with
no consumer. **An economy dashboard is one function call at one chokepoint** —
and `P-7B` explicitly asks for "Cash inflation: median and p99" monitoring that
has nothing to read.

## F-27 · The rejection counter is a soft-signal hook with no reader
`RateLimiter.recordRejection/rejectionCount` accumulates per-player refusals for a
whole session and is exposed through `RemoteGateway.rejectionCount` — consumed
only by a `warn` string. The module deliberately refuses auto-kick (T-4), which
makes this exactly the shape of a *flag-for-review* signal. No threshold, no
reader.

## F-28 · `CurrencyModels` — 3D currency icons, and the harness to show them
`CurrencyModels.luau` · **~70% · LOSS RISK**

Procedural 3D cash-stack and glass+neon gems in pink and blue. **Zero references
anywhere.** But the delivery mechanism already works: `V7HUD:271-378` renders
`GearMeshBuilder` into a live `ViewportFrame` with a 0.55s spin-on-click. Drop
these models into the same pattern and the flat currency chips become spinning 3D
icons.

## F-29 · `FeedbackFX` — a complete floating-text engine, deliberately unsubscribed
**~95% · SEAM** · `FeedbackFX.luau:300`

A 10-item pooled system with magnitude-scaled width, duration and travel, a
motion-blur ghost, four radial sparks per item, and distinct credit / debit / VOID
/ NaN renderings. **The frame loop is connected and running right now; nothing
ever calls `present`.**

It was disconnected on purpose because board-anchored payout text collided with
the dice. Retargeted away from board centre it is a ready-made renderer for
"STREAK ×12!", element procs, quest-complete, boost-expired.

## F-30 · Smaller seams worth knowing

| Item | Where | Opportunity |
|---|---|---|
| `MonetisationCatalog.unavailable` + `isSellable` | `:63`, `:309` | A kill-switch for undeliverable products. No entry sets it, but the shop **already gates on it** — flipping one flag hides a product. A ready-made operator control |
| `describeTier` | `VaultCatalog.luau:145` | A complete upsell string with suppression once owned. Never printed |
| `RollService.isAutoRolling` | `:610` | Auto-roll state is session-only and absent from the snapshot; this is the missing half |
| `readyIn` | `NetClient.luau:91` | *"Exposed so the HUD can grey a button out instead of firing and being refused."* The legacy HUD did; V7 does not |
| 8 remotes on the default rate limit | `RateLimiter.luau:11-49` | `Ascend`, `ClaimVault`, `ClaimQuest`, `ClaimChest`, `DailySpin`, `BuyVaultHours`, `SetAutoRoll`, `ClaimGroupReward` silently take `{2, 5}` |
| Per-shape balance fields are all identical | `DiceCatalog.luau:53-55` | `massFloor`, `defaultBudget`, `cashBudgetCap`, `diamondCeiling` are per-shape *structurally* and uniform in value. An entire tuning axis plumbed and sitting at neutral |
| `PROMO_CODES` | `ProgressionService.luau:21` | Three hardcoded codes, no expiry, no per-code limit. `CodesRedeemed` is already per-code, so event codes are a table edit away |
| `TotalRolls` | persisted, shipped, unread | A fourth leaderboard is one line — `submitScore` takes an arbitrary board id |
| `LoginStreak.ForgivenessLeft` | spent, never renewable | A "streak insurance" reward or purchase — there is a consumer with no producer |
| Quest observer seam | `setRollObserver` / `setForgeObserver` | `advanceQuests` already supports gauges and counters; new metrics (cash earned, elements fired, void survived) need one call at an existing site |
| Purchase ledger | `PlayerProfile:625-645` | A complete timestamped, bounded, evicting receipt history. Only `hasPurchase` reads it — no reporting or support tooling |
| Forge presets | `V7ForgePanel:1276` | **SAFE is byte-identical to EVEN.** It was clearly meant to be JACKPOT's opposite — minimise void probability. `ForgeMath.voidProbability` is already imported |
| Forge step | `V7ForgePanel:36` | Hardcoded `STEP = 5`. The legacy panel cycled `{1, 5, 25, 100}`. At late-game budgets a fixed 5 makes the forge unusable — a straight regression |
| `UITheme.overlay` body | `:405` | Builds a scrolling padded content container that **all eight callers immediately hide** in favour of `formatModalShell` |

---

# ⚠ HARVEST BEFORE PHASE 3 DELETES THESE

Roadmap Phase 3 deletes `ForgePanel.luau`, `MenuPanel.luau`, `HUD.luau` and
`CurrencyModels.luau` — 3,662 lines. **They contain finished work that exists
nowhere else:**

| What | Where | Why it matters |
|---|---|---|
| **The Statistics panel** | `MenuPanel.luau:607-687` | The only consumer of three live snapshot fields |
| **The pooled status/notice line** | `HUD.luau:415-443` | V7 has no way to speak to the player at all |
| **Whole-loadout Void maths** | `HUD.luau:185-235` | Computes `1 − Π(1 − pᵢ)` across every die — the correct version of the `RISK-1` defect |
| **The Like Goal / 3× event UI** | `HUD.luau:358-412` | A complete social loop design |
| **The capability `Entry` model** | `MenuPanel.luau:12-26` | `Live` / `NeedsSurface` / `Pending` per entry, so a *wiring omission renders visibly*. V7 replaced it with hardcoded "NOT YET AVAILABLE" strings |
| **"AUTO SPEED"** | `MenuPanel.luau:315` | A feature idea named nowhere else |
| **The optimistic ROLL pulse** | `HUD.luau:445-474` | Sub-100ms press feedback with zero per-press allocation (NFR-7) |
| **3D currency icons** | `CurrencyModels.luau` | See F-28 |
| **Per-face element assignment + in-panel shape switching** | `ForgePanel.luau:939-995` | Also the proportional-headroom `moveMass`, which V7 replaced with a flat step |

**Recommendation: copy this material into a reference file before the deletion
commit, or defer the deletion until the harvest is done.** The roadmap currently
treats those files as pure dead weight. They are not.

---

# CORRECTIONS TO EARLIER RECORDS

| Claim | Correction |
|---|---|
| *"The streak cliff costs 8,730 Diamonds ≈ 9 trillion-dollar ascensions"* (mine, earlier today) | **Wrong.** `StreakStrength` has no purchase path. It is not expensive — it is unpurchasable at any price |
| *`BOARD-1` — leaderboards never written* (`criticalbugfix.md`) | **FIXED** by Antigravity at `7874a1c`. `updatePlayer` now runs on exit, on a 60s loop, and in `BindToClose` |
| *`LUCK-1` — decide whether to implement or remove* | **Removed** at `7874a1c`. Operator has since decided to reinstate it as a permanent multiplier stacking with `LuckBoost` — see the conversation record |
| `ProgressionService` header: *"chests at 5, 15 and 45 minutes"* | Stale. Six tiers ship (5/15/30/45/60/90) |
| `ForgeService.validateStoredDice:280` falls back to `D6` | Starting shape is `D2`; the file's own comment says "falls back to the starting shape" |
| `API_DATA_CONTRACT.md` §1 remote inventory | Missing four live remotes: `SetSetting`, `SwapDice`, `UnequipDie`, `BuyDieInstance`. NFR-5 says the authority model is verifiable by inspecting that list — it currently is not |
| `API_DATA_CONTRACT.md` §3 profile template | Missing seven fields added since `SchemaVersion = 2`, and lists the starting die as D6 when the code ships D2 |

---

# CHECKED AND CLEAN

Recorded so it is not re-swept:

- **All 12 shapes are reachable** and present in `UNLOCK_ORDER` with real geometry
  and prices. No orphaned catalog content.
- **All 5 elements are defined** and all are used by `resolveElements`.
- **Deleted-file history holds nothing lost.** Everything removed from `src/` was
  either retired Ball Escape residue (cleared 2026-08-04) or a recorded decision
  (`ArenaView` → `BoardView`, L-028).
- **`_reconcile` handles every new field additively**, so most of the above needs
  no schema migration.

---

# SUGGESTED ORDER

**Before anything else:** build the two upgrade panels (the headline). They
activate seven finished systems, including the Phase 0b work that currently
cannot be reached.

**Then, cheapest first:**

1. Paste the 9 audio asset IDs (**you**) — F-1
2. Subscribe `onNotice` + rebuild the status line — F-2
3. Rebuild the Statistics panel — F-3
4. Wire `swapDice` into the Slots overlay — F-4
5. Consume `elementsFired` — F-5
6. `serverTime` → one countdown component serving three features — F-6

**Decisions only you can make:** F-19 (Void visibility — the most valuable),
F-20 (animation), F-21 (vault model), F-22 (whether twelve shapes get a balance
pass).

**Before Phase 3:** the harvest above.
