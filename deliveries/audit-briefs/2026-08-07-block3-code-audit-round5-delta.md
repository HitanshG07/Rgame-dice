# DELTA AUDIT BRIEF — Dice Forge, Block 3, ROUND 5

**Date:** 2026-08-07
**Commit under audit:** `778b493`
**Previously approved:** `30268f3` — round 4 returned `AUDIT-APPROVED / 0` and
`SECURE / 0`, and that verdict stands.
**Mandate:** **READ-ONLY.** Evaluate, cite, report.

---

## 0. THIS IS A DELTA AUDIT — small scope, deliberately

Round 4 approved `30268f3`. **One change has landed since**, and this brief
covers that change and nothing else. **Do not re-run the full matrices** — they
were run three days' worth of rounds in a row and passed clean on the code
underneath this delta.

### Why a delta audit at all

Round 4 marked **X-24** PASS: *"a mutating path that reaches `PlayerProfile.mutate`
without passing the invariant gate."* **That verdict was correct as scoped** —
all three `mutate` sites in `ForgeService` are gated.

I then asked the same question with a wider frame — *which paths write a die?*
rather than *which call `mutate`?* — and found a gap:

> **The invariant guarded every WRITE and nothing on READ.**
> `PlayerProfile._reconcile` (lines 185, 195) and `_migrate` (lines 437, 444)
> write `data.Dice` directly on the load path. Neither passes the gate. A die
> already illegal in storage loaded cleanly and was then honoured, because
> `performForge` validates the client's proposal against `die.MassBudget` — so a
> stored `99999` is simply believed.

Not hypothetical: **four defects in this block wrote invalid dice** before they
were caught (F-AD-1 inflated budget on a shape toggle, F-AD-4 by a rounding
residue). Any profile touched by that code still carries the result.

### The change

| Added | Where |
|---|---|
| `repairDie(die, shape)` — private | `src/Server/ForgeService.luau` |
| `ForgeService.validateStoredDice(player)` | `src/Server/ForgeService.luau` |
| One call to it, before `RollService.beginSession` | `src/Server/ServerBootstrap.server.luau` |
| Load-path regression tests | `tests/Forge.test.luau` (UT-12, now 329 assertions) |

Placed in `ServerBootstrap` rather than `PlayerProfile` because `PlayerProfile`
is required **by** `ForgeService`; the reverse would be a circular require.

**Design decision to scrutinise: violations are REPAIRED, not quarantined.** A
die can be illegal through no fault of the player — our own bugs wrote several —
so refusing the load would kick them over our mistakes. Repair clamps back into
the contract, keeps the shape, the known elements and the clamped entitlement,
and redistributes mass evenly.

---

## 1. THE QUESTIONS

Answer these. Nothing else is in scope.

| # | Question | Verdict | `file:line` + verbatim quote |
|---|---|---|---|
| **R-1** | **Can repair ever INCREASE what a player holds?** Any input — inflated, deflated, `NaN`, missing, wrong shape — where the repaired die is worth more than the illegal one, or more than a legitimate die of that shape could be. This is the whole safety argument: *repair can only reduce an illegal advantage.* Try to break it. | | |
| **R-2** | **Can repair leave a die the invariant would still reject?** `repairDie` output is not itself re-checked before being written. Is that provably safe for every input, or is it an assumption? | | |
| **R-3** | **Is a LEGAL die ever modified?** Repair must be a no-op on valid data. A forged layout being silently flattened would destroy player investment. | | |
| **R-4** | **Repeated invocation.** Idempotent? Can repeated joins ratchet a value in either direction? | | |
| **R-5** | **Failure paths.** `PlayerProfile.mutate` returning false; a `Dice` array that is empty, sparse, or holds non-tables; an unrecognised `Shape`. Does it throw, or fail closed? | | |
| **R-6** | **Ordering in `admitPlayer`.** It runs after `load()` and before `beginSession`. Can any roll, forge or remote be serviced in between? Is there a yield inside `validateStoredDice` that opens a window? | | |
| **R-7** | **Is repair the right call versus quarantine?** A judgement question, and I want the disagreement if you have it. Repair silently alters saved data — is logging sufficient, or does a player deserve to be told? | | |
| **R-8** | **Does anything else read a die WITHOUT the gate?** `RollService.performRoll` reads `data.Dice` at line 427 and samples from it. It now runs after validation on join — but is that guarantee actually airtight for the whole session? | | |

## 2. PROTOCOL

Unchanged. Quote the line verbatim; cite **implementation**, not a comment and
not this brief; a wrong quote rejects, a drifted line number does not;
`UNVERIFIED` with a reason is acceptable and honest.

```text
GATE 3 VERDICT: AUDIT-APPROVED | REJECTED-TO-GATE-1
FINDINGS: <integer>
GATE 4 VERDICT: SECURE | FLAGGED
FINDINGS: <integer>
```

**`AUDIT-APPROVED / 0` is a perfectly good answer** if the delta holds up. Round
4 reached it honestly and this is a far smaller surface. Say which of R-1…R-8
you verified by opening the file.

## 3. CONTEXT YOU MAY NEED

- **Gate 2 on `778b493`:** 9 suites, 0 failed, **3,307 assertions**. P-1 pending
  a re-read at the time of writing.
- **The invariant** is `ForgeService.assertDieInvariant`, seven clauses, the
  single definition of a valid die.
- **`maxDiamondCeiling()`** is 5,000 (D20's). `PurchasedBudget` is bounded by it
  globally; usable `MassBudget` is bounded per-shape by that shape's
  `diamondCeiling`.
- **Out of scope:** everything approved in round 4, and
  `src/Server/Vendor/ProfileStore.luau`.
