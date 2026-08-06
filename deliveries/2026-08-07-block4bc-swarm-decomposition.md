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
