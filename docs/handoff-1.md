CONSUMED-BY: Operator / next session start
STATUS: LIVING — supersede with handoff-2.md, do not edit in place after handover

# HANDOFF 1 — DICE FORGE INCREMENTAL

**Written:** 2026-08-11
**Head at handover:** `bbf43ec`
**Working tree:** clean, everything pushed to `master`
**Suite:** 22 test files, **20 suites, 3,471 assertions, 0 failing**

---

## 1. THE OPERATOR'S RULES — binding on every future session

These were given during this session and override any default working style.

### 1.1 One element at a time, finished completely

> *"if you are doing some element completley finish it out first and only then move onto the next one"*
> *"i want you to strictly fix each element one by one it doesnt have to start from forge you can take the smallest and move your way up"*
> *"but if you are touching some element make sure all its functionalities are covered"*

**Do not** part-build three panels. Pick one, cover every capability it is supposed
to have, verify each one, then move on. Smallest-first is fine.

### 1.2 Verify by clicking it in Studio, not by reading the code

> *"you also have access to the roblox studio you can keep on checking and testing each ui elemt and fix it one by one"*

Studio MCP is connected. `user_mouse_input` drives real clicks;
`screen_capture` shows the result. **A screenshot of the thing working is the
evidence.** This session found four separate defects that every static check and
every green test had passed.

**Coordinate warning:** screenshot pixel coordinates are NOT game coordinates —
the capture is scaled. Always read `AbsolutePosition + AbsoluteSize/2` off the
Instance before clicking, or the click misses and you will misdiagnose a working
button as broken. This cost time in this session.

### 1.3 Keep the UI design; rebuild freely underneath

> *"i give you permision to rebuild anything you have to but maintain the ui design please unless you can suggest me a better ui"*

The neumorphic look stays. Use `UITheme`'s builders — never invent a second
visual language. Suggesting a better UI is allowed; changing it silently is not.

### 1.4 Ask questions, in plain terms

> *"ask me all the questions but in simple terms"*
> *"suggest me some if it feels less or not properly planned"*

Use `AskUserQuestion` with previews. No jargon. If a panel's plan looks thin,
say so and propose something.

### 1.5 Keep a running report of what was wrong

> *"keep on making a report for everything thing which was made wrong / went wrong / or made half right - or properly made"*

`docs/GOVERNANCE_AUDIT.md` is that report. `docs/ui_audit/` holds the measured
before/after of the UI. Keep both current.

### 1.6 No mock data. Everything hooked up for real

> *"everything has to be in effect no mock up data"*
> *"Each element working properly , hooked properly , tested properly"*

A panel that renders but is not wired to the server is not done.

### 1.7 Screenshots for before/after

> *"save the svreenshots somewhere so you can verify how it was before and how it is now"*

`docs/ui_audit/BASELINE_2026-08-11.md` records the measured before-state
(child counts per overlay, not impressions). `AFTER_2026-08-11.md` tracks the
after. Measured counts survive a session; screenshots do not.

### 1.8 Standing constraints from earlier (still binding)

- **No fabricated social proof, no manufactured urgency, no resetting timers.**
  The Starter Bundle timer is genuinely once-only.
- **The repository is private.** That is what permits the threat model to be discussed openly.
- **Agents never create monetised assets.** The operator creates them and supplies ids.
- **No client message may carry a price, balance, reward, multiplier or outcome** (NFR-5).
- `RemoteFunction:InvokeClient()` prohibited (T-8). Exactly one `ProcessReceipt` (T-17).
  No `SetAsync` for profile data (T-11). No `MessagingService` in V1 (R-8).

---

## 2. RECENT DESIGN DECISIONS

| Decision | Detail |
|---|---|
| **Start on the D2** | New players begin with a 2-faced die and climb: D2→D3→D4→D6→D8→D10→D12→D20, each rung gated on the one below |
| **Ladder priced in CASH** | Not Diamonds. Diamonds only arrive after an ascension, so a Diamond ladder is invisible for a player's entire first run |
| **Group rewards UNPLUGGED** | Commented out, not deleted. Two-line restore noted in `ServerBootstrap`. Server logic is complete and correct; it is waiting on the operator's group id |
| **Elements go in the forge** | A chip per face, cycling unlocked elements. Operator-approved over a separate panel |
| **Die tabs in the forge** | Numbered tabs, one per die that exists. Operator-approved |
| **EVEN button** | Operator-requested. Spreads mass equally. Distinct from RESET — EVEN proposes a new distribution and costs Cash; RESET discards unsaved edits and is free |
| **Settings behind a gear icon** | Top bar, next to the currencies. Operator-approved |
| **Settings will persist** | Operator chose to fix FR-13.6 properly rather than leave toggles session-only |

### The one tension to keep in mind

FR-6.1 says shapes are *"a build choice, never a tier ladder."* The operator asked
for a ladder. Both hold, and the distinction is load-bearing:

- the **unlock** is ordered — that is the progression;
- the **choice** stays free — once owned, switching is free and reversible, and
  at low Streak Strength a D2 or D3 genuinely beats a D20.

**Therefore the UI must present later shapes as DIFFERENT, not STRONGER.** If it
implies "bigger is better" it teaches players a wrong model of their own build.

---

## 3. WHAT IS DONE

### 3.1 Fully finished and click-verified

**THE FORGE** — every planned capability, each proven by clicking it:

| Capability | Evidence |
|---|---|
| Reads the live die | `DIE 1 · D6 · 6 faces · 70 mass` |
| Mass / landing % / payout per face | F3 at 55 mass → 4.3%, pays 3.02K |
| Zero-sum `+`/`−` | Total stayed invariant across every edit |
| Quoted cost before commit | From the **shared** formula the server charges with |
| Real commit | Server accepted; panel resynced to "No changes pending" |
| **EVEN** | All faces to 10, 16.7% each, Void 0.0%, quoted $400 |
| **Element chips** | Per face; shows `LOCKED` honestly when nothing is unlocked |
| **Die tabs** | Drawn from dice that exist; "2 empty slots" stated |
| **+ MASS** (FR-3.6) | All dice 60→70; every face sum still equals its budget |

**THE SHAPE LADDER** — all 8 rungs, live state (`OWNED` / `IN USE` / price /
`needs D3`), Cash prices, ladder order enforced.
⚠ **Needs one re-test** — see §4.

### 3.2 Built this session, not yet individually click-verified

- Daily quests (deterministic per player per UTC day), login streak with one
  non-renewing forgiveness token, playtime chests
- Server-driven auto-roll with a server-enforced interval (FR-7)
- Starter Bundle once-only timer (`BundleExpiry`, stamped once, never reset)
- Boosts now visible on the wire
- Vault and Slots overlays (were completely empty)

### 3.3 Defects found and fixed

**Four that could cost a player money or data:**

1. **`RemoteGateway.V` was never exported** — eight handlers threw on their first
   line for the entire build (`SetAutoRoll`, `BuyUpgrade`, `BuyDiamondNode`,
   `ClaimVault`, `RedeemCode`, `ClaimQuest`, `ClaimChest`, `GetLeaderboard`).
   Every one returned `server_error` to every call. **This is the single best
   explanation for "no ui element is properly working."**
2. **Forging die 2 overwrote die 1** (operator-reported). The commit sent
   `forge(1, ...)` regardless of the open tab.
3. **TimeSkip paid a flat 1,000** when it could not compute a rate, then returned
   `PurchaseGranted` — money kept, nothing delivered, no retry.
4. **FR-6.3 was violated outright** — the D20 won at all eight Streak Strengths
   tested, because mass budget scaled with face count.

**Plus:** `ClaimQuest`/`ClaimChest` returned `true` and granted nothing;
`claimGroupReward`'s "verified server-side" comment sat above no verification;
shapes could never be unlocked (read implemented, write absent); scientific
notation shown to players; three overlays completely empty; no overlay scrolled;
`setEnabled` never actually disabled input; button captions rendered unstyled.

### 3.4 New tests

- **UT-14 Balance** — runs the FR-6.3 crossover sweep every pass, against the
  shipping catalog. Also asserts the *cause* (uniform budget) so a failure
  reports why.
- **UT-15 RemoteContract** — asserts the validator surface exists **and exercises
  it**, so a validator that exists but errors also fails.

---

## 4. WHAT IS LEFT

### 4.1 Panels, in the suggested order (smallest first)

| Panel | State | Needs |
|---|---|---|
| **SETTINGS** | empty, and no button reaches it | gear icon in the top bar; particles + motion-blur toggles; promo code entry; **persist to profile** (needs a small server handler) |
| **VAULT** | built, capacity only | the real accrued figure — the snapshot does not carry it yet |
| **SHAPE** | built | **re-test** — `BuyDiamondNode` was one of the eight dead handlers, so the earlier unlock test is not trustworthy |
| **QUESTS** | built | verify a completed quest actually pays out |
| **SHOP** | renders and scrolls | verify a purchase prompt actually opens |
| **BOARDS** | static placeholder | wire to `GetLeaderboard` (now returns real data + rank) |
| **ASCEND** | static placeholder | FR-9.4 requires a confirm screen stating exactly what is lost and gained |
| **SLOTS** | built | verify ADD SLOT end to end |

### 4.2 Blocked on the operator

| Item | Why |
|---|---|
| **Roblox group id** | `ProgressionService.GROUP_ID = 0` fails closed. Needed to re-plug group rewards |
| **9 audio asset ids** | Still `DUMMY_ID_*` |
| **FR-10.7 Like Goal** | No server implementation. Must show the real platform count or nothing — fabricated activity is prohibited |

### 4.3 Known gaps not yet scheduled

- `src/Client/LegacyUI/` is a dead duplicate of every pre-V7 client module — delete
  once V7 is confirmed stable.
- Balance *tuning* is unvalidated. UT-14 proves a crossover exists; it does not
  prove it sits at a sensible `b`. Shape ladder prices (500 → 4.2M) are a first pass.

---

## 4A. PROPOSED FUTURE WORK — THE ELEMENT SYSTEM

**Not scheduled. Written down so the next session does not have to rediscover it.**

### The situation

Elements are the feature the design calls the game's main differentiator — the
thing a competitor with 2.55M visits does not have. Right now:

| Piece | State |
|---|---|
| `ElementCatalog` — Fire, Freeze, Gold, Multiplier, with real payoff maths | **built** |
| Server evaluation across resolved faces | **built** |
| `SetElement` remote + validation | **built** |
| UT-5 Elements, 32 assertions | **passing** |
| Forge chip to assign one to a face | **built this session** |
| **Anything that UNLOCKS an element** | **does not exist** |

The profile grants `Elements = { None = true }` and nothing anywhere sets another
to `true`. So the chips read `LOCKED` and will read `LOCKED` forever. This is the
same shape as the shape-unlock defect fixed this session — **read implemented,
write absent** (ledger L-027), and it will stay invisible for the same reason.

### Proposed design

**1. Where they unlock — the ASCEND panel.**
FR-9.3 already lists "element unlocks" as part of the Diamond tree, so the panel
that panel is already meant to hold them. It is currently a static placeholder,
so this work folds naturally into building it rather than adding a new surface.

**2. How they unlock — Diamonds, and deliberately NOT the Cash ladder.**
The shape ladder was moved to Cash because it must be reachable in a first run.
Elements are the opposite: they are the *second* layer of build depth, and having
them arrive after an ascension gives prestige something concrete to buy. Suggested
first-pass costs, unvalidated:

```
Fire        25 Diamonds    flat bonus on its own face
Multiplier  40 Diamonds    scales with own mass
Freeze      70 Diamonds    conditional, re-rolls
Gold       120 Diamonds    conditional, scales with combined invested mass
```

**3. Order matters, and Gold should be last.**
Gold and Freeze are the *conditional* elements — the ones whose payoff depends on
what other dice rolled (FR-4.3). They are also the ones that only make sense with
more than one die. Gating them behind the cheaper unconditional pair means a
player meets the simple version of the mechanic first.

**4. The forge chip already handles it.**
`V7ForgePanel` reads `state.diamondTree.Elements` and cycles only what is
unlocked. **Setting one flag to true is the entire client-side change** — the chip
will start working with no further UI work.

### What this must NOT become

FR-4.3 is explicit: *"Every conditional element's payoff scales with the combined
invested mass of the participating faces. A flat conditional bonus is
algebraically inert."* This was **proven in simulation** (ledger L-016) — a flat
conditional bonus enters as a constant multiplier and cannot shift any optimum,
so it looks like a feature and does nothing.

If a future session simplifies Gold or Freeze to a flat bonus "to make the maths
easier", that is a defect, not a simplification.

### Rough size

Half a day. The server is done; this is a purchase path, four rows in the ascend
panel, and a test that a purchased element actually appears in the snapshot.

### Sequencing note

Worth doing **with or straight after ASCEND**, not before. Elements are only
interesting with several dice in play, and a player reaching their first
ascension has usually bought slots by then.

---

## 5. HOW TO PICK UP

1. Read `docs/GOVERNANCE_AUDIT.md` for the full defect ledger.
2. Read `docs/ui_audit/BASELINE_2026-08-11.md` for the measured before-state.
3. Start Rojo (`tools/rojo.exe`, port 34872) and open Studio.
4. Pick **one** panel from §4.1. Cover every capability. Click every control.
   Screenshot the result. Only then move on.
5. Commit with an honest message naming what was wrong, not just what changed.

### The rules that keep earning their keep

- **Verify by running it.** Every defect above passed static analysis.
- **Registered is not implemented.** Eight handlers were registered and dead.
- A green suite at an unchanged assertion count is not a pass (L-020).
- A comment asserting a control ("verified server-side") is a claim needing the
  same evidence as a test.
- A specified row with a READ but no WRITE is invisible to every audit (L-027).
- A balance requirement is a property of the **numbers**; no code test sees it (L-034).

---

## 6. HONEST ASSESSMENT

The **server is in good shape**. The core loop, economy, persistence, receipts,
rate limiting and the die invariant are correct and genuinely tested. The
inverted-mass mechanic — the reason this game exists — has been observed working
by the operator and is now legible on screen in the forge.

The **client was the problem**, and the cause was structural rather than cosmetic:
a complete visual design with almost no data path, sitting on top of eight server
handlers that threw on their first line. Two panels are now genuinely finished.
Six remain.

Nothing on the remaining list is hard. It is breadth, and it needs the same
treatment the forge got: one at a time, every control clicked, no assumptions.

The one piece of genuinely NEW design still owed is the element unlock path
(§4A) — everything else is connecting things that already exist.
