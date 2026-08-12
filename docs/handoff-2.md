# HANDOFF 2 — Operator defect report, triaged

**Date:** 2026-08-12
**Status:** RANKED, NOT FIXED. Nothing in this document has been actioned.
The operator asked for a severity ranking first and will give the go-ahead
per item.

**Head:** `bbbc6d7` · 21 suites, 3,548 assertions, 0 failing.

---

## HOW THESE ARE RANKED

By **what it costs if it ships**, not by how hard it is to fix:

- **S1 — Economy integrity.** A player can gain value they did not earn, or
  loses value they did earn. These corrupt saved data and are the only class
  that gets worse the longer it runs.
- **S2 — Broken core loop.** A player cannot play, or the game misrepresents
  its own central mechanic.
- **S3 — Progression blocked or misleading.** The game works but a player
  cannot advance, or is told something untrue about advancement.
- **S4 — Feature gap.** Something promised is missing. Nothing breaks.
- **S5 — Polish.** Looks or feels wrong. No functional consequence.

Two items in the report turned out to be **already correct** and are recorded
at the bottom so they are not re-investigated.

---

## S1 — ECONOMY INTEGRITY

### S1-a · The vault accrues while the player is sitting in the game
> *"vault works but it should only work when the user leaves the game and not
> when the user is idle inside the game"*

**Confirmed in code.** `Vault.LastSeen` is written in exactly two places —
`OfflineService.onPlayerRemoving` (on leave) and inside `claimVault`. It is
**never written on join**. So `getStatus` measures elapsed time from the moment
of the last *departure*, and every second spent idling in-game is counted as
offline time.

**Why this is the worst item on the list.** It is free money that requires no
action, it scales with session length, and it compounds with the vault's
capacity upgrades. It also directly undermines the offline mechanic's purpose:
there is no reason to ever leave. And unlike a UI bug, every second it runs
writes a larger number into a saved profile.

**Fix shape:** stamp `LastSeen` on join as well as on leave, so the accrual
window is strictly the gap between sessions. Needs care around the ordering
with the join-time vault read, or a player loses the accrual they just earned
by logging in to collect it.

---

### S1-b · ROLL is spammable
> *"the roll option is spammable which makes it like an exploit bug"*

**Confirmed.** `RateLimiter` allows `Roll` at **5/sec sustained, 10 burst**;
`NetClient` throttles to one per **0.15s** — but that client throttle is a
courtesy only and an exploiter running their own client ignores it entirely.
So the real ceiling is the server's 5/sec.

**The judgement call this needs from the operator.** 5/sec is not obviously
wrong — it is the documented FR-2.4 auto-roll ceiling, and the same limit the
Auto-Roll gamepass sells. Making manual rolling slower than the pass a player
can buy is a *design* decision about what that pass is worth, not purely a bug
fix. I would not change the number without you choosing it.

**Fix shape:** a short client-side cooldown with visible feedback on the ROLL
button (so it reads as a game rule rather than lag), plus a decision on whether
the server ceiling should drop for manual rolls specifically.

---

## S2 — BROKEN CORE LOOP

### S2-a · Void faces never appear
> *"i dont get the concept of the void face here - i dont see any void faces
> appearing what so ever"*

**Confirmed by arithmetic, and this one is subtle.** A face is a Void only when
`mass <= massFloor * VOID_FLOOR_FACTOR`, i.e. `mass <= 1.5`. The starting D2 has
both faces at **30**. Nothing about it can void, which is why the HUD honestly
reads `RISK 0%`.

**So the mechanic is not broken — it is unreachable.** To see a Void a player
must forge almost all mass onto other faces and leave one at ~1. That is a
deliberate, late, deep-forge action, and nothing in the game teaches it or
suggests it exists. The result is that the single most distinctive mechanic in
the design is invisible during the entire early game.

This is S2 rather than S3 because the Void is not a side feature — the whole
inverted-mass concept (heavy faces pay more but land less) only makes sense once
a player has *seen* the downside.

**Needs a design decision from you, not just code.** Options range from raising
`VOID_FLOOR_FACTOR`, to making the starting die slightly uneven so the mechanic
is visible on turn one, to teaching it explicitly in the forge. I would want
your call before touching a balance constant that FR-6.3's crossover depends on.

---

### S2-b · Ascension does not refresh in real time
> *"the assencion worked but it didnt not update with real time"*

**Believed confirmed.** `Ascend` is wrapped in `announcing`, so a snapshot IS
pushed — but the panel the player is looking at appears not to repaint until
something else forces it. The screenshot shows the ASCEND panel still reading
`+1 ♦ · Earned $525.01K · 1 ascension so far` *after* the reset had already
happened (cash was $0 by then).

**Needs diagnosis before a fix** — most likely the push races the profile write,
or `refreshAscend` is reading a snapshot built before the mutation committed.
I will not guess at the cause.

---

## S3 — PROGRESSION BLOCKED OR MISLEADING

### S3-a · Slot cap says 7, board shows 6, and dice overlap on the D2
> *"the maximum number of slots shows 7 but in game its only 6"*
> *"when i bought a slot while using the 2 faced dice it overlaps"*

**Partly contradicted by the code, so this needs real diagnosis.**
`DiceCatalog.MAX_DIE_SLOTS = 7`, `BoardView` has a precomputed 7-die layout
(`{4,3}` rows), and `DiceRenderer.MAX_DICE = 7`. All three agree on seven.

The operator's screenshot shows **6 dice** on a board reporting 7 slots — so
something is dropping one, and the overlap suggests the D2's ViewportFrame
scale is wrong for dense layouts specifically (the D2 is a wide flat lens, not
a compact cube, so `DIE_SCALE_FULL = 0.205` may be too generous for it).

Two distinct bugs likely hiding under one report. Must be measured, not assumed.

---

### S3-b · Slot cap should scale with ascensions
> *"make increase the total number of slots to be relative to the number of
> assension they have"*

**Design change, not a defect.** Currently a flat 7 for everyone, purchasable
with Cash. The request is to gate the ceiling behind prestige.

Ranked S3 because it is the operator's stated progression fix and interacts
with S3-a: raising the cap past 7 needs board layouts for 8+ dice, which do not
exist. **Needs the curve from you** (how many ascensions per extra slot, and a
hard maximum) before anything is built.

---

### S3-c · SHAPE cannot buy duplicates of the same die
> *"in shape we need to add options to buy multiple of the same dice - this
> helps progression"*

**Feature gap with a real progression consequence.** Ownership is currently a
boolean set (`Diamond.Shapes[id] = true`), so a shape is owned or not. Buying a
second D6 is not representable in the schema at all.

This is a **schema change**, which is why it is ranked above the cosmetic items:
`Diamond.Shapes` would need to become counts, and every read of it (`SetShape`,
`canUnlock`, the panel, the migration) has to handle both the old boolean shape
and the new one. Not difficult, but it touches saved data and must be migrated
carefully.

---

### S3-d · FORGE cannot assign which die sits in which slot
> *"in forge there has to be an option for you to select which dice sits on
> which slot"*

**Feature gap.** The forge has per-die tabs but no way to reorder or assign
dice to board positions. Server-side, `d.Dice` is an array and position is
implicit in index, so the data model already supports it — this is mostly UI
plus a reorder remote.

---

## S4 — FEATURE GAPS

### S4-a · Tiered vault earning rates
> *"offline vaults earning rate we will set it as a fixed rate for normal
> standard users / people who buy vip in game / people who have roblox premium
> all will have a different rate and we can decide on that later on"*

**Explicitly deferred by the operator** — "we can decide on that later on".
Recorded here so it is not lost. Note the rate is currently derived from the
player's own recent average income, not a fixed rate, so this is a change of
*model* and not just a multiplier. `OfflineService.getEfficiency` is the seam.

Roblox Premium detection is `Players.LocalPlayer.MembershipType` /
`Player.MembershipType` server-side — available, no extra product needed.

---

### S4-b · Audio
Nine `DUMMY_ID_*` placeholders. Parked by the operator this session. The system
fails closed and Settings honestly says "No sounds are installed yet". Dropping
real ids into `ASSET_IDS` is the only change needed.

---

## S5 — POLISH

### S5-a · AUTO should read "AUTO OFF" when off
> *"for auto button display it should also show auto off - whileits off and
> auto on while its on"*

Currently reads `AUTO` / `AUTO ON`. Trivial change to the off caption. Ranked
lowest because the state is already unambiguous (cyan + glow when on), but the
operator is right that explicit is better than implicit.

---

### S5-b · Dice faces render with a dark shade
> *"some of its face ahve a dark shade on them like shadow -need this to be
> like shadowless for all faces for all dice"*

Visible in the operator's screenshots — the D2 shows one face noticeably darker.
Parts already have `CastShadow = false`, so this is ViewportFrame lighting:
a `ViewportFrame` has its own `LightDirection` / `Ambient` and unlit faces go
dark. Fix is flat ambient lighting per viewport, not a geometry change.

---

### S5-c · Dice roll/fall animation quality
> *"we need to optimize and make the aniamtion of the dice rolling and falling
> on the board to be better"*

Subjective and open-ended. Would want specifics from the operator on what reads
wrong — too fast, too floaty, wrong settle, no impact.

---

## NEEDS DIAGNOSIS BEFORE IT CAN BE RANKED

### "settings also seems to be bugged"
**No detail given, and I could not reproduce a fault.** The operator's own
screenshot shows Settings rendering correctly: Particles off, Motion Trail on,
both audio rows correctly disabled with "No sounds are installed yet", promo
code field present.

**I need to know what you saw.** Candidates I would check first: a toggle not
sticking after rejoin, the promo box not accepting input, or the audio rows
looking broken rather than deliberately disabled.

---

## ALREADY CORRECT — DO NOT RE-INVESTIGATE

### "it ascended and everything is gone - by this i mean dice"
**This is the ascension working as specified.** FR-9.1: ascending resets face
layouts, mass budgets and Cash upgrades. The panel states it explicitly before
confirming — "Your dice, reset to one starting D2" and "Extra die slots" are
both listed under YOU LOSE.

Worth confirming with the operator that the *intent* is understood, but the
behaviour matches the design and the UI warned about it.

### "the starting number of dice is 1 and it has to be the 2 faced dice"
**Already true and pinned by a test.** Verified this session: template, factory
and `STARTING_SHAPE` all produce one D2 with two faces at 30 mass each. UT-7 now
asserts the literal value, the face count, and template/factory agreement field
by field, so it cannot silently drift.

The screenshot after ascension shows exactly one gold D2 coin — correct.

---

## SUGGESTED ORDER

1. **S1-a** vault-while-idle — free money, compounds, corrupts saves
2. **S1-b** roll spam — needs your decision on the number
3. **S2-b** ascension refresh — small, and it makes S2/S3 testing honest
4. **S3-a** diagnose the 6-vs-7 and the D2 overlap — two bugs, must measure
5. **S2-a** Void visibility — **needs your design call first**
6. **S3-d** forge slot assignment — self-contained
7. **S3-c** duplicate shapes — schema change, do it deliberately
8. **S3-b** ascension-scaled slots — **needs your curve**, and depends on S3-a
9. **S5-b** viewport lighting — quick, visible win
10. **S5-a** AUTO OFF caption — one line
11. **S5-c** animation — **needs your specifics**
12. **S4-a / S4-b** — deferred by you

**Waiting on you for:** the Void design call, the roll cooldown number, the
ascension→slots curve, what you saw in Settings, and what reads wrong in the
animation.

---

## OUTSTANDING FROM BEFORE THIS REPORT

- `ASCEND_MIN_LIFETIME_CASH` is **100000 for testing — ship 1e6.**
  One line in `DiceCatalog`, clearly marked.
- Roblox group id still unset (`GROUP_ID = 0`); group rewards built and
  commented out.
- Balance tuning unvalidated against real play.
- Element unlocks (Fire/Freeze/Gold/Multiplier) built server-side with no
  unlock path; belongs in ASCEND.
- `src/Client/LegacyUI/` is dead duplicate code awaiting deletion.
