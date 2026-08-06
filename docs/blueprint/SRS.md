CONSUMED-BY: Gate 0 / Matrix A
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# SOFTWARE REQUIREMENTS SPECIFICATION — DICE FORGE INCREMENTAL

Every task's acceptance criteria must trace to a requirement here. An untraceable criterion is either a new requirement to be added by amendment, or scope creep to be fenced.

**Binding constraint on every requirement below:** the server holds no per-die rigid-body state and never reads a physical outcome. No requirement may depend on the client determining an economic result, and no requirement may depend on server state the HLD declares is not held. A proposed requirement violating either is rejected at design time rather than implemented. *(This is the defect class that broke the previous project — see ledger L-015.)*

---

## 2. FUNCTIONAL REQUIREMENTS

### FR-1 — Arena and dice presentation
- **FR-1.1** The arena renders as a contained low-poly 3D pit viewed top-down, holding between 1 and 7 dice.
- **FR-1.2** Each die renders as a bevelled low-poly solid with emissive numerals, its face count matching its shape (4, 6, 8, 12, or 20).
- **FR-1.3** A die's visual mass distribution is legible without opening a menu: heavier faces are visibly weightier (scale, glow intensity, or inset depth), so a player can read a die's build at a glance.
- **FR-1.4** Dice come to rest fully inside the arena. A die that would settle outside is repositioned within it before the result is presented.

### FR-2 — Rolling and outcome resolution
- **FR-2.1** Pressing ROLL sends an intent message carrying no outcome, value, or quantity of any kind.
- **FR-2.2** The server selects each die's landed face by weighted sampling over that die's mass distribution, using a server-held RNG, and is the sole authority on the result.
- **FR-2.3** Landing probability is inversely related to face mass: `P(face i lands up) ∝ (M − mᵢ)`, normalised across faces, where `M` is the die's total mass. Heavier faces land face-down more often.
- **FR-2.4** Face payout is superlinear in mass: `value(i) = k · mᵢ^α` with `α = 2.0`. Superlinearity is required — at `α ≤ 1` concentrating mass cannot pay and the forge becomes inert. *(Established numerically, ledger L-016.)*
- **FR-2.5** The client animates a tumble that resolves to the server's face. The animation never determines, and is never read to determine, the outcome.
- **FR-2.6** If animation is interrupted (disconnect, tab-out, frame loss), the credited payout is unaffected. Economic state never depends on animation completing.
- **FR-2.7** Total throw payout is the sum of each die's face value, modified by active elements (FR-4), the streak multiplier (FR-5), and owned boosts.
- **FR-2.8** Payout is displayed as floating text in the arena at the moment of credit.

### FR-3 — The Forge (zero-sum mass budget)
- **FR-3.1** Each die has a **Total Mass budget**. Forging moves mass between that die's faces and never creates it. Raising the budget is a separate, purchased progression step.
- **FR-3.2** A forge action is submitted as a complete proposed distribution. The server accepts it only if every mass is finite and non-negative, no face is below the minimum floor, and the total equals the player's server-held budget within a fixed epsilon. Any violation rejects the entire proposal and mutates nothing.
- **FR-3.3** Forging costs Cash. **The cost is non-trivial and scales with the magnitude of mass moved** — free or near-free re-forging collapses the cross-die puzzle into a solved symmetric state. *(Binding constraint from ledger L-016; this is a correctness requirement, not a monetisation lever.)*
- **FR-3.4** The forge UI shows, before committing: the resulting per-face value, the resulting per-face landing probability, the resulting expected value per roll, and the resulting Void probability. Players optimise openly; the maths is public by design.
- **FR-3.5** A face reduced to the minimum floor becomes a **Void face** (FR-5.2).
- **FR-3.6** Mass budget increases are purchased with Cash up to a per-shape cap, and beyond that with Prestige Diamonds.

### FR-4 — Elements
- **FR-4.1** A face may carry one element: **None**, **Fire**, **Freeze**, **Gold**, or **Multiplier**. Element assignment costs Cash and is limited to elements the player has unlocked.
- **FR-4.2** Elements are evaluated by the server against the throw's resolved faces. No element may require knowledge of a die's physical trajectory, position, or collision — that state does not exist server-side.
- **FR-4.3** **Every conditional element's payoff scales with the combined invested mass of the participating faces.** A flat conditional bonus is algebraically inert: the partner die's trigger probability enters as a constant multiplier and cannot shift any optimum. *(Proven in simulation; ledger L-016. A flat conditional bonus appearing in construction is a defect.)*
- **FR-4.4** Element behaviours, all resolvable from resolved faces alone:
  - **Fire** — adds a share of its own face value to every other die's value this throw.
  - **Gold** — pays a large bonus **only if at least one other die also landed Gold this throw**, scaled by the combined mass of the participating Gold faces.
  - **Freeze** — locks one other die's result, re-rolling it next throw and keeping the better of the two.
  - **Multiplier** — multiplies the throw total rather than adding to it.
- **FR-4.5** Element interactions produce **role specialisation, not symmetry**: a die heavily invested in a conditional element pushes its partners *away* from that element and toward cash. Balance must preserve this. *(Measured correlation −0.949; ledger L-016.)*

### FR-5 — Streaks
- **FR-5.1** A streak counter increments on every throw in which no die lands a Void face, and resets to zero when any die does.
- **FR-5.2** A **Void face** is a face at or near the mass floor. It pays nothing, and because it is the lightest face it lands most often — the visible cost of concentrating mass elsewhere.
- **FR-5.3** The streak multiplier **compounds**: `(1 + b)^streak`, capped at a defined ceiling. Compounding is required — a linear multiplier cannot move the forge optimum at any strength. *(Ledger L-016.)*
- **FR-5.4** `b` (Streak Strength) is a **player-chosen permanent investment** via the Prestige tree (FR-9.3), not a global constant. Different investment levels make genuinely different mass distributions optimal, which is what produces distinct sniper and grinder cohorts.
- **FR-5.5** The current streak, its multiplier, and the Void probability of the active loadout are continuously visible.
- **FR-5.6** A player owning **Bad Roll Shield** does not lose their streak on a Void face. The shield has a server-clocked internal cooldown so it cannot absorb every break.

### FR-6 — Dice shapes
- **FR-6.1** Shapes are **D4, D6, D8, D12, D20**, and are a build choice, never a tier ladder. A shape change costs Prestige Diamonds and is freely reversible.
- **FR-6.2** Shape determines face count and therefore native volatility. Void probability at optimal play ranges from ≈0.33 at D4 to ≈0.05 at D20 — D4 is the volatile sniper, D20 the steady grinder. *(Measured; ledger L-016.)*
- **FR-6.3** No shape dominates at all Streak Strength values. Balance must preserve a crossover: low `b` favours few faces, high `b` favours many. **A build where one shape wins at every `b` is a balance defect.**

### FR-7 — Automation
- **FR-7.1** Auto-Roll is purchased with Cash and toggled by the player, firing rolls at a fixed server-enforced interval.
- **FR-7.2** Auto-Roll speed upgrades reduce that interval down to a floor. The interval is enforced server-side; the client cannot request a faster rate.
- **FR-7.3** **Ultra Auto-Roll** (gamepass) lowers the floor further. The rate ceiling is derived from server-held entitlements only.

### FR-8 — Offline vault
- **FR-8.1** Elapsed offline time is computed entirely server-side from `os.time()` at save versus load. No client value participates.
- **FR-8.2** `earnings = min(elapsed, capacity) × averageIncomePerSecond × efficiency`, where `averageIncomePerSecond` is a server-maintained rolling average of the player's recent active earning rate.
- **FR-8.3** Base capacity 4 hours at 0.5 efficiency; Cash-upgradable to 12 hours at 0.75; **VIP Vault** gamepass sets 24 hours at 1.0.
- **FR-8.4** Elapsed time is clamped to `[0, capacity]`. A negative elapsed value credits exactly zero and is logged. Never a negative or wrapped payout.
- **FR-8.5** On return after 5+ minutes away, a welcome screen shows the accrued amount with a standard claim and a Robux 2× claim.
- **FR-8.6** Claiming consumes the vault atomically — the accrual window closes and resets in the same transaction that credits it, so a second claim finds it empty.

### FR-9 — Prestige (Ascension)
- **FR-9.1** Ascending resets Cash, face layouts, mass budgets, and Cash-purchased upgrades, granting **Prestige Diamonds** scaled to lifetime earnings this run.
- **FR-9.2** Diamonds persist across every ascension and are never reset.
- **FR-9.3** Diamonds are spent on permanent trees: **Streak Strength** (`b`, FR-5.4 — the primary build-defining axis), mass budget ceiling, die slots, element unlocks, shape unlocks, and cosmetics.
- **FR-9.4** The ascension screen states, before confirming, exactly what is lost and exactly what is gained.
- **FR-9.5** Ascension requires a minimum lifetime-earnings threshold, preventing degenerate rapid-ascend loops.

### FR-10 — Progression rewards
- **FR-10.1** Three rotating daily quests with server-defined objectives (roll counts, streak thresholds, forge actions), each rewarding Cash or Gems. Progress is server-tracked.
- **FR-10.2** A daily login streak with escalating rewards and exactly one forgiveness token.
- **FR-10.3** Playtime chests on a server-clocked timer at 5, 15, and 45 minutes of session time, rewarding scaling Cash, Gems, or free forge mass.
- **FR-10.4** A daily spin wheel, one free spin per 24 hours, outcomes drawn from a server-held weighted table. **The wheel animation resolves to a pre-decided server outcome** — same authority rule as dice.
- **FR-10.5** Group Rewards grants a permanent Luck bonus, verified server-side against Roblox group membership and re-verified on each join.
- **FR-10.6** Promo codes are matched against a server-held allowlist. Responses are limited to valid / invalid / already-redeemed and never echo the submitted string.
- **FR-10.7** A Like Goal displays the experience's **real** like count and triggers a timed 3× Cash event when reached. **V1 scope: the event is simulated per server instance** — each server tracks and triggers independently, because MessagingService is out of scope for V1 *(operator scoping decision, 2026-08-04; accepted as risk R-8)*. Two players on different servers may therefore see different event states. Displayed like progress is real platform data; no fabricated activity of any kind appears anywhere in the game. *(Standing operator prohibition, 2026-07-17.)*

### FR-11 — Leaderboards
- **FR-11.1** Three global boards: **Top Net Worth**, **Highest Single Roll**, **Max Prestiges**.
- **FR-11.2** Each shows the top 100 with avatar, username, rank and value, plus the local player's own rank regardless of position.
- **FR-11.3** Ranks 1–3 receive distinct gold, silver and bronze framing.
- **FR-11.4** Values published to `OrderedDataStore` are bounded, log-scaled, monotonic integers derived from the true value — never the raw number, which overflows the signed 64-bit range in an idle economy. *(Threat T-20.)*
- **FR-11.5** Board data is fetched once per server on a fixed interval and served to all players from that cache.
- **FR-11.6** Display names are read from the `Players` service server-side, never from a client message.

### FR-12 — Monetization
- **FR-12.1** Gamepasses: **+2 Dice Slots** (5→7), **Ultra Auto-Roll**, **Bad Roll Shield**, **VIP Vault**.
- **FR-12.2** Developer Products: **Starter Bundle**, **2× Offline Payout**, **2× Luck Boost**, **Time Skip (24h)**.
- **FR-12.3** All grants flow through `MarketplaceService.ProcessReceipt`. **Exactly one** `ProcessReceipt` assignment exists in the place. *(Threat T-17.)*
- **FR-12.4** `PurchaseGranted` is returned only after the grant durably persists; every other path returns `NotProcessedYet`. *(Threat T-16.)*
- **FR-12.5** The **Starter Bundle timer is genuinely once-only.** Once it expires the offer is permanently gone for that player and never reappears under any name. No countdown resets, no re-offers, no manufactured urgency anywhere in the game. *(Standing operator instruction, 2026-07-17; reaffirmed for this project 2026-08-04.)*
- **FR-12.6** Product asset ids do not yet exist (UNKNOWN U-1). An unresolved product **fails closed** and grants nothing.
- **FR-12.7** No purchase confers an economic capability the game does not also make reachable through play, with the sole exception of cosmetics.

### FR-13 — Interface
- **FR-13.1** A 2D retro-pixel `ScreenGui` overlays the 3D arena: dark maroon and charcoal panels, 1-pixel gold borders, monospace pixel type.
- **FR-13.2** Top bar: Cash, Gems, Like Goal progress, Group Rewards, Robux shop.
- **FR-13.3** Left sidebar: Forge (the primary surface), Add Die Slot, Shape, Auto-Roll Speed, Ascend.
- **FR-13.4** Right sidebar: Leaderboards, Statistics, Quests, Codes/Settings.
- **FR-13.5** Bottom bar: ROLL and AUTO, plus the playtime chest and daily spin entry points.
- **FR-13.6** Settings can disable particles and motion blur for performance, persisted per player.
- **FR-13.7** All layout uses `Scale`-based sizing, never fixed `Offset`, and renders without clipping or overlap from phone through 4K.
- **FR-13.8** The forge is reachable in **at most two taps** from the arena. It is the core mechanic, not a submenu.

### FR-14 — Persistence
- **FR-14.0** Persistence uses **ProfileStore** (loleris), pinned and vendored, accessed exclusively through the `PlayerProfile` wrapper module. No other module touches the library. *(Operator-directed 2026-08-04; dependency review note in HLD §5.1; maintenance risk R-7.)*
- **FR-14.1** The profile is loaded once on join and **held in memory for the entire session**. The game loop mutates the in-memory profile and never performs a DataStore round-trip per transaction. The library auto-saves on its cadence; the profile is explicitly released on leave and on `BindToClose()`.
- **FR-14.2** All persistence goes through the library's session-locked write path. Direct `SetAsync` on profile data is prohibited. *(Threat T-11.)*
- **FR-14.3** Session locking is delegated to ProfileStore. A profile that fails to load, or whose lock is held by another server, **fails closed**: the player is shown an honest error and is never served a default profile that could overwrite real saved data. *(Threat T-10; HLD §5.2 rule 1.)*
- **FR-14.7** A **released** profile is immutable. Every write path verifies the profile is still active **synchronously with the mutation — no yield may occur between the check and the write**; where a yield is unavoidable the check is repeated immediately after it. A write against a released profile is logged and dropped, never applied. *(HLD §5.2 rule 2; threat T-26. Amended 2026-08-04, triggering fact: Gate 4 audit TM-5.2 — the original wording required a check but not synchronicity, leaving a yield window.)*
- **FR-14.8** The in-memory profile is the single source of truth during play. No module keeps a parallel copy of Cash, Gems, Diamonds, mass budgets, or Streak Strength, and `EconomyService` is the only writer. *(HLD §5.2 rule 3.)*
- **FR-14.4** Every field carries a default, and a versioned migration chain runs on load. *(Threat T-12.)*
- **FR-14.5** The writer asserts a serialised payload ceiling before every save and refuses to exceed it. *(Threat T-13.)*
- **FR-14.6** A load failure or foreign live lock **fails closed** — the player is never served a default profile that would overwrite real saved data.

---

## 3. NON-FUNCTIONAL REQUIREMENTS

- **NFR-1 — Client frame budget.** 60 FPS on desktop and 30 FPS on mid-tier mobile with 7 dice active. Client per-frame work under 4 ms. No allocation inside per-frame loops.
- **NFR-2 — Server cost.** Per-player per-roll resolution under 0.5 ms. Cost scales with **die count**, never with physics complexity, because the server runs no simulation.
- **NFR-3 — Responsive layout.** Correct rendering from 320 px wide through 4K, `Scale` units only.
- **NFR-4 — Numeric safety.** Cash is representable to 1e300 without precision loss in display or comparison. All leaderboard values are bounded log-scaled integers. Every inbound numeric is explicitly checked finite before use — `NaN` fails all comparisons and would silently defeat the forge sum validator. *(Threat T-25.)*
- **NFR-5 — Server authority.** No client message may carry a price, balance, reward, score, level, duration, multiplier, or outcome. This is verifiable by inspecting the remote inventory in `API_DATA_CONTRACT.md` §1.
- **NFR-6 — Save integrity.** No confirmed transaction is lost to a single DataStore failure. Retries are bounded and failures surfaced honestly to the player rather than hidden.
- **NFR-7 — Input latency.** A ROLL press produces visible feedback within 100 ms, ahead of server confirmation. Optimistic feedback is **visual only** and never displays an unconfirmed currency change.
- **NFR-8 — Static cleanliness.** Every **first-party** module `--!strict`. Roblox Script Analysis reports **zero errors across the whole place, and zero warnings across all first-party code** — `src/Server/`, `src/Shared/`, `src/Client/`, and `tests/`. `RemoteFunction:InvokeClient()` appears nowhere in the codebase. *(Threat T-8.)*
  - **Scoped to first-party 2026-08-06**, triggering fact: the first-ever P-1 run reported 149 warnings, of which the residue after all first-party fixes came from `src/Server/Vendor/ProfileStore.luau` — loleris's library, 2,242 lines, **pinned and vendored unmodified**. Those warnings are `string.len` receiving `*error-type* & string`, an artefact of the library's own internal typing.
  - **Zero errors remains whole-place and unscoped.** Only warnings are scoped, and only for vendored code.
  - **The exclusion is a policy, not a silence.** The vendor warnings are accepted under Global Pipeline Law 5 as documented-with-justification: adding `--!nocheck` to the drop would clear the panel but break byte-parity with upstream, and every future re-pin would then have to remember to re-apply it — at which point "pinned" no longer means what it says. An unmodified pin has more security value than a clean count. The accepted warning count is recorded in the P-1 evidence artifact each run; **an increase in that count is a finding**, because it means the vendored file changed.
  - **This exclusion covers `Vendor/` only.** It is not a general licence to accept warnings. First-party warnings remain gate failures under Global Pipeline Law 5, and the P-1 artifact must state the first-party count separately from the vendor count so the two can never be conflated.
