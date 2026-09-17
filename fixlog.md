# Dice Forge Incremental — Critical Fix Log

**Maintained:** 2026-09-17  
**Branch:** `finalized-ui-revamp-whole-repo`  
**Standard:** `.brain/PIPELINE.md` under PRODUCTION tier  

---

## Log Entries

### 2026-09-17 — Batch 1: The Forge (`FORGE-1`, `FORGE-2`)
- **Date / Batch / Defect ID:** 2026-09-17 / Batch 1 / `FORGE-1`, `FORGE-2`
- **What happened:**
  - `FORGE-1`: `NetClient.forge` and `NetClient.buyUpgrade` return a single `Result = { ok: boolean, reason: string? }` table. `V7ForgePanel.luau` destructured as `local ok, reason = ...`. In Lua, tables are truthy, so `ok` was truthy on every call (even when `result.ok == false`), causing the button to display "CALIBRATED" in green and clearing `dirty` state unconditionally on failure.
  - `FORGE-2`: `DiceCatalog.newDie` snaps per-face mass shares down to 3dp, giving D7 a budget of 59.997 and D14 a budget of 59.990. `V7ForgePanel.luau:1311` computed `drift = math.floor(budget + 0.5) - sum` which forced the sum to 60. `ForgeMath.validate` checks `|total - budget| <= 0.001`, which rejected D7 (drift 0.003) and D14 (drift 0.010) on every submission attempt.
- **What caused it:**
  - Caller-signature mismatch (`V7ForgePanel` assumed tuple return from `NetClient` rather than single table).
  - Client-side rounding assumption (`math.floor(budget + 0.5)`) enforcing integer budgets when the server never required integers and stored float budgets for D7/D14.
- **How it was addressed:**
  - In `V7ForgePanel.luau:1239` & `:1325`, read `local result = NetClient...` and check `result.ok` / `result.reason`.
  - In `V7ForgePanel.luau:1311`, target the die's real budget: `local drift = budget - sum`.
  - Discovered during test suite execution: on D16 (16 faces, 3.75 mass each, budget 60), rounding up to 4 produces sum 64 and drift -4. Subtracting 4 from a single face dropped it to 0 (`below_floor`). Extended drift resolution to distribute negative drift across heaviest faces without breaching `floor`.
- **Verified how:**
  - Full automated suite: 23 passed, 0 failed.
  - Assertions increased from 3,642 to 3,686 (+44 assertions: +6 in UT-13 ClientContract, +38 in UT-2 ForgeValidation).
  - Live interactive verification in Studio Play Solo via MCP:
    - Opened Forge via HUD button.
    - Verified Jackpot preset calibration ($290 deducted, F1=59, F2=1 persisted).
    - Verified Even preset calibration ($290 deducted, F1=30, F2=30 persisted).
    - Verified insufficient funds handling ($120 cash remaining vs $290 cost): button disabled, cost in red, submission cleanly blocked with no false CALIBRATED state.
  - Evidence captured: `deliveries/evidence/2026-09-17-batch1-the-forge.txt` + screenshots.
- **Still open?** CLOSED. Fixed in Batch 1.
