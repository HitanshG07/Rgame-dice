# SWARM DECOMPOSITION PROOF — Blocks 4B + 4C (the client view layer)

**Date:** 2026-08-07
**Mode:** `.brain/modes/swarm.md`
**Authorisation:** explicit operator instruction — *"make use of swarm mode, spawn multiple sub agents"*.
**Orchestrator:** this session. **Coordinates only — constructs nothing inside the fan-out, audits nothing.**

---

## 1. ENTRY CRITERIA

| Criterion | Status |
|---|---|
| Three or more blocks with provably disjoint file sets | **MET** — see §3 |
| Host supports genuinely isolated sub-agents | **MET** — Agent tool, fresh contexts |
| Operator explicitly authorises the swarm run | **MET** |

## 2. SERIAL PRE-STEP — how the disjointness was CREATED

The seven view modules were **not** disjoint as specified. Two shared surfaces
would have been written by every worker:

1. **`ClientBootstrap.MODULE_ORDER`** — every module must be registered in it.
   Seven workers editing one array is a guaranteed merge conflict, and the
   Orchestrator owns conflicts.
2. **The FR-13.1 palette.** "Dark maroon and charcoal panels, 1-pixel gold
   borders, monospace pixel type" is one sentence. Three modules building panels
   from it independently produce three different maroons — and *nothing flags
   it*, because each panel individually satisfies the requirement.

Both were resolved **before** fan-out, as serial work under the normal pipeline:

- `src/Client/UITheme.luau` written — palette, layer ordering, and the sanctioned
  `panel` / `label` / `button` builders.
- `ClientBootstrap.MODULE_ORDER` populated with all seven names in dependency
  order.

**Both files are now READ-ONLY for every worker.** This is the move that makes
the remaining work genuinely disjoint rather than nominally so.

*Disclosure: this pre-step is Orchestrator-authored construction, which the mode
forbids INSIDE the fan-out. It was performed before entering the mode, as serial
work. It is unverified by a second party and is therefore explicitly in scope for
the consolidated Gate 4 at fan-in.*

## 3. DISJOINTNESS PROOF

Disjointness is proven on **write sets**. Read-only shared dependencies are
listed separately and are identical for all blocks, which is what makes them
safe to share.

### Block S-1 — The Arena (3D presentation)
```
src/Client/ArenaView.luau
src/Client/DiceRenderer.luau
src/Client/FeedbackFX.luau
```

### Block S-2 — The Forge (the primary surface, FR-13.8)
```
src/Client/ForgePanel.luau
```

### Block S-3 — Chrome and Audio
```
src/Client/HUD.luau
src/Client/MenuPanel.luau
src/Client/AudioDirector.luau
```

### Pairwise intersection

| Pair | Intersection |
|---|---|
| S-1 ∩ S-2 | ∅ |
| S-1 ∩ S-3 | ∅ |
| S-2 ∩ S-3 | ∅ |

**No file appears in two write sets. Disjointness holds.**

### Read-only shared dependencies (identical for all three)
```
src/Client/UITheme.luau          src/Client/NetClient.luau
src/Shared/ForgeMath.luau        src/Shared/DiceCatalog.luau
src/Shared/ElementCatalog.luau   src/Shared/Format.luau
src/Shared/Remotes.luau          docs/blueprint/SRS.md  (FR-1, FR-2, FR-13)
docs/blueprint/API_DATA_CONTRACT.md §1.2
```

**No worker may write any file outside its own block.** A worker that needs a
change to a shared file must report it to the Orchestrator rather than making it —
that is the single rule whose violation collapses the proof.

## 4. SIZING JUSTIFICATION

**Three pairs**, against a ceiling of six.

- **S-1 is one block, not three.** `ArenaView`, `DiceRenderer` and `FeedbackFX`
  are tightly coupled: the renderer needs the arena's camera and die anchors, and
  the feedback text anchors into the arena. Splitting them would create exactly
  the shared-surface problem the pre-step just removed.
- **S-2 is alone on purpose.** The forge is the core mechanic and FR-13.8 calls
  it the primary surface. Its preview must use the *shared* `ForgeMath` so the
  numbers match the server's payout exactly — the single highest-risk piece of
  client work in the project. It gets undivided attention and full reasoning
  capacity.
- **S-3 groups the remaining 2D chrome plus audio.** All three are
  presentation-only, none is coupled to the others, and none carries economic
  logic.

A fourth pair would have to split either the arena trio or the forge, and both
splits reintroduce coupling. **More pairs would be slower, not faster.**

## 5. THE RULES EVERY WORKER CARRIES

These are non-negotiable and are repeated in every worker's slice:

1. **The server has already decided the outcome.** The client animates toward a
   result that is already true. The tumble never determines, and is never read to
   determine, the face (FR-2.5). If the animation is interrupted, the credited
   payout is unaffected (FR-2.6).
2. **No outbound message may carry a price, balance, reward, score, level,
   duration, multiplier or outcome** (NFR-5). All server traffic goes through
   `NetClient`; no module may touch a Remote directly. **UT-13 and P-3 both
   enforce this and will fail the build.**
3. **`Scale`-based sizing only**, never fixed `Offset`, except 1px borders
   (FR-13.7, NFR-3).
4. **No allocation inside per-frame loops. Pool instances.** (NFR-1)
5. **A menu entry is added only when the system behind it exists.** Anything
   awaiting Block 5 shows an honest "coming soon", never a fake working button.
6. **No fabricated social proof, no manufactured urgency, no resetting timers.**
   Standing operator prohibition.
7. **`--!strict`, zero warnings, no TODO/FIXME/TBD.**

## 6. EXECUTION RING

Per `modes/swarm.md` §4. Each pair caps at three rejection cycles before
escalating to the Orchestrator.

**Deviation, disclosed:** Verifiers are spawned *after* their Worker completes
rather than concurrently. A verifier has nothing to verify until code exists;
concurrent spawning would only idle a context. The pairing itself is intact —
one verifier per block, fresh context, and the Worker never verifies its own
output.

## 7. FAN-IN (Orchestrator-owned)

1. Re-verify disjointness against files **actually** touched, not merely planned.
2. Integrate; resolve any conflict (Workers never do).
3. Run the full suite — expect 10 suites and a **moved** assertion count
   (L-020 canary).
4. Run P-1; first-party warnings must be **zero**.
5. Run P-3 including the client-boundary rules.
6. **Run P-4, the 11-row runtime smoke — the first time this game is playable.**
7. One consolidated Gate 4 and Gate 5, covering the serial pre-step in §2.
8. Gate 6 once, on the integrated whole.

## 8. EXIT ARTIFACT

The Swarm Report, appended to this document at fan-in: per-block verdicts,
rejection counts, integration evidence, smoke evidence, and any circuit-breaker
escalations.

---

## 9. FAN-IN ACTION ITEMS RAISED BY WORKERS

Workers are forbidden from writing outside their block. Each of these was
**correctly reported rather than acted on** — that is the discipline the proof
depends on, and it worked.

### A-1 (S-2, HIGH) — the forge cost function now exists in two places

`ForgePanel` needs the cost before the player commits (FR-3.3 makes it a
pre-commit decision input), but **a client cannot require a server module**. The
worker therefore reimplemented `ForgeService.computeForgeCost` locally as
`estimateCost`, duplicating `BASE_COST_PER_MASS_UNIT = 5.0`,
`REFERENCE_BUDGET = 60.0` and `SCALE_EXPONENT = 2.0`.

**This is exactly the failure mode of L-025** — a rule living in two places gets
re-derived, and the two copies drift silently. It is the same shape as the die
contract that cost Block 3 five rejections. The worker labelled it `~` in the UI
and never treats it as truth, which is the right mitigation, but mitigation is
not resolution.

**ORCHESTRATOR ACTION:** move the three constants and the cost function into
`src/Shared/ForgeMath.luau` and have both `ForgeService` and `ForgePanel` call
the one definition — precisely as `landingProbabilities` and `faceValue` are
already shared. `ForgeMath` is a shared file and therefore Orchestrator-owned;
no worker could have done this. Assert single-definition in UT-12.

### A-2 (S-2, HIGH) — `StateSync` is specified but never emitted

`grep` over `src/Server` finds no `StateSync` fire. Every 2D surface reads its
authoritative state from it. The worker parsed the API contract defensively and
falls back to template defaults, which **over-reports locking** — the forge will
show every element locked until `StateSync` carries `Diamond.Elements` and
`Diamond.Shapes`.

Failing toward "locked" is the safe direction. But the panel cannot honestly show
entitlements until a server emits the event, and the contract's §1.2 payload list
does not currently name the Diamond sets.

**ORCHESTRATOR ACTION:** amend `API_DATA_CONTRACT` §1.2 to include them, and
implement the emitter. Server-side and outside every worker's block.

### A-3 (S-2/S-3 boundary) — one forge entry point, not two

FR-13.3 puts Forge in the left sidebar, which is S-3's `MenuPanel`; the panel
itself is S-2's. S-2 exposed `ForgePanel.setVisible(boolean)` and additionally
built a permanently visible left-edge FORGE tab so the panel is reachable in
**one** tap (FR-13.8 permits two).

**ORCHESTRATOR ACTION:** wire `MenuPanel`'s Forge entry to
`ForgePanel.setVisible`, and decide whether the edge tab and the sidebar entry
should both exist. Two controls for one surface is a UI defect, not a feature.

### A-4 (S-2, MEDIUM) — element and shape costs are not displayed

Shown as "server prices it" rather than as numbers, to avoid duplicating two more
server constants — the same reasoning as A-1. FR-3.4 requires only the four
preview numbers and FR-3.3's forge cost, both of which ARE shown, so this is
compliant. It becomes displayable for free once A-1 moves the pricing into
`ForgeMath`.

### A-5 (S-1 **and** S-2, BLOCKING) — `StateSync` is specified and emitted by nothing

**Two workers in isolated contexts, given different slices, independently
reported the same gap.** That convergence is the strongest signal this swarm has
produced: it is not one worker's misreading.

`grep StateSync src/Server` returns nothing. `RollService` fires only
`RollResult`. Consequences, both confirmed by the workers who hit them:

- **`DiceRenderer` never learns die shape or mass.** Every die renders as a
  uniform dim D6, so **FR-1.3 — "a die's mass distribution is legible without
  opening a menu" — is unverifiable at the P-4 smoke.** The module is correct and
  ready; the data never arrives.
- **`FeedbackFX` never learns the Settings toggles**, so particles and motion
  blur default to on regardless of what the player saved (FR-13.6).
- **`ForgePanel` cannot see entitlements** and shows every element locked.

**The contract is also incomplete, in two places:**
1. §1.2's `StateSync` payload is `{ cash, gems, diamonds, dice, upgrades,
   streak, boosts, serverTime }` — **no `settings`**, which FR-13.6 requires to
   reach the client.
2. It does not carry `Diamond.Elements` / `Diamond.Shapes`, which the forge needs
   to show what is unlocked honestly.

**ORCHESTRATOR ACTION:** amend `API_DATA_CONTRACT` §1.2, then implement the
emitter — on join, and after any state change. Server-side, outside every
worker's block. **This blocks the P-4 smoke**, so it is fan-in work, not
follow-up work.

### A-6 (S-1, note) — the face-index → geometry mapping is invented client-side

Nothing in `DiceCatalog` or the SRS says which physical facet is "face 3". The
worker generates normals deterministically per shape at module load, so the
mapping is stable across clients and sessions.

Presentation-only and coherent as long as `ForgePanel` and `DiceRenderer` agree
that "face 3" means the same *index* — which they do, since both index the same
array. **Not a defect.** Recorded because if a canonical mapping is ever
specified it belongs in `DiceCatalog`, not in a renderer.

### A-7 (S-1, decision) — `FeedbackFX` fires on `RollResult` arrival, not on landing

FR-2.8 says "at the moment of credit". The credit precedes the message, so
arrival is the earliest honest moment, and it keeps the payout visible to a
player who drops every frame of the tumble (FR-2.6).

The alternative — text on landing — reads better but couples a *credit
notification* to an *animation completing*, which is the exact dependency FR-2.6
exists to forbid. **Keeping arrival.** Flagged because it is a deliberate choice
against the more satisfying option, and the smoke will make it visible.
