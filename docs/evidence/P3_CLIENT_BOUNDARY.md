# P-3 — Mechanical prohibition sweep, client view layer

**Head:** `d30b53a` — *The board goes 2D: ArenaView deleted, BoardView + a flat renderer replace it*
**Date:** 2026-08-09
**Scope:** `src/Client/**` (10 modules), plus project-wide checks for the four
threat-model prohibitions that are not client-specific.
**Method:** ripgrep over source with **Lua comments stripped** (`sed 's:--.*::'`)
before matching, so a rule's own documentation cannot satisfy or violate it.

---

## Why the comment stripping is not a detail

The first run of this sweep used `s://.*::g` — a **C-style** comment stripper —
against Luau source, which comments with `--`. It produced two false positives
in `HUD.luau`, both of them prose:

```
34:  -- for it, so there is no `OnServerInvoke` behind the RemoteFunction. An earlier
517: -- thread so the InvokeServer yield cannot delay the pulse past 100 ms
```

Neither is code. This is the same defect class as the earlier `:: Player` cast
check that fired on the comment explaining why not to cast: **a prohibition grep
that cannot strip its own language's comments will eventually match the sentence
describing the prohibition.** Every result below is from the corrected sweep.

---

## Results

| ID | Rule | Result | Evidence |
|----|------|--------|----------|
| **T-8** | `RemoteFunction:InvokeClient()` prohibited project-wide | **PASS** | 0 code occurrences in `src/**` excluding `Vendor`. The only textual hit is `Shared/Remotes.luau:7`, which is the comment *declaring* the prohibition. |
| **T-11** | `SetAsync` prohibited for profile data | **PASS** | 0 code occurrences first-party. Persistence is ProfileStore only. |
| **T-17** | Exactly one `ProcessReceipt` assignment | **VACUOUS — see below** | 0 occurrences. |
| **R-8** | No `MessagingService` in V1 | **PASS** | 0 code occurrences first-party. |
| **NFR-5** | No client message carries a price, balance, reward, score, level, duration, multiplier or outcome | **PASS** | Client outbound is `NetClient.luau` only, at two call sites (`:106`, `:200`). No other client module contains `FireServer`, `InvokeServer`, `OnClientEvent`, `RemoteEvent` or `RemoteFunction` in code. |
| **FR-12.6** | Robux asset ids are fail-closed `DUMMY_ID_*` placeholders | **PASS** | 9 ids in `AudioDirector.luau:78-86`, all `DUMMY_ID_*`. No numeric asset id anywhere first-party. |
| **Boundary** | `NetClient` is the sole wire boundary | **PASS** | `require(...Remotes)` appears in exactly one client module: `NetClient.luau`. |
| **Boundary** | No generic `invoke` escape hatch | **PASS** | No `NetClient.invoke` exported; every remote is a named method. Also asserted by UT-13. |

---

## T-17 is vacuous, not passing

**There is no monetisation code in the repository yet.** `src/Server/` contains
nine modules and none of them requires `MarketplaceService`; receipt handling is
Block 5 work that has not started, and is blocked on the operator creating four
gamepasses and four developer products.

So "exactly one `ProcessReceipt` assignment" is satisfied only in the sense that
zero is not more than one. **Recording that as PASS would be the L-027 failure
verbatim** — a specified-but-unimplemented row reading exactly like a working
one. It is recorded as VACUOUS and must be re-run, and re-read, the moment
`MarketplaceService` first appears.

---

## What changed under this sweep since it last ran

The view layer was rebuilt between the previous P-3 and this one:
`ArenaView.luau` (3D pit, 618 lines) was **deleted**; `BoardView.luau` (2D tray)
and a rewritten flat `DiceRenderer.luau` replaced it, and `FeedbackFX.luau` lost
its camera projection. The boundary results are unchanged by that work, which is
the expected outcome: **no view module ever touched the wire directly**, so
replacing two of them could not alter the boundary. That the numbers did not
move is the finding.

## Not covered here

P-3 is mechanical. It proves the prohibited *text* is absent; it does not prove
the *behaviour* is correct. Specifically out of scope:

- whether `StateSyncService` omits `PurchaseIds`/`CodesRedeemed` in practice
  (field-by-field construction — read at Gate 4, not grepped here);
- whether the client's outbound payloads are semantically free of the NFR-5
  categories, as opposed to structurally routed through one module;
- anything about the 2D board's *appearance*, which is P-4 and operator-judged.
