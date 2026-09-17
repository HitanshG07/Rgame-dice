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

### 2026-09-17 — Batch 2: Real Money (`ASC-1`, `PASS-1`, `SLOT-2`)
- **Date / Batch / Defect ID:** 2026-09-17 / Batch 2 / `ASC-1`, `PASS-1`, `SLOT-2`
- **What happened:**
  - `ASC-1`: `AscensionService.luau:66` executed `d.Gems = 0` on every ascension. Gems are purchased with real Robux (`MonetisationCatalog.luau`: `GemsSmall`, `GemsLarge`, `StarterBundle`) and are not in FR-9.1's reset list. Ascending silently confiscated up to 650 Robux-bought Gems with no warning.
  - `PASS-1`: The `+2 Die Slots` gamepass (`Catalog.Passes.DieSlots2`) granted 4 slots and 4 free dice instead of 2. When purchased mid-session, `PurchaseService.luau` called `PlayerProfile.grantDieSlots(data, 2, ...)` but did not update `data.PassSlotsGranted`. On next join, `applyPassSlotGrant` evaluated `already = data.PassSlotsGranted or 0` (0), saw a shortfall of 2, and granted 2 more slots.
  - `SLOT-2`: In `ServerBootstrap.server.luau:546`, buying a die slot called `DiceCatalog.dieSlotCost(data.DieSlots, data.Ascensions)` without passing `data.Diamond.SlotNodes`. When a player unlocked additional slot capacity via the Diamond Tree and reached the base ascension cap, `dieSlotCost` returned `nil`, causing the server to reject the purchase with `InvalidRequest` even though the client quoted a valid price.
- **What caused it:**
  - `ASC-1`: Unaudited exception in `AscensionService.luau` contradicting FR-9.1 reset list.
  - `PASS-1`: Missing counter update (`data.PassSlotsGranted = already + gained`) in mid-session gamepass purchase callback.
  - `SLOT-2`: Incomplete parameter propagation during commit `daac879` (threaded `slotNodes` on client `V7MenuPanel.luau` but missed server `ServerBootstrap.server.luau`).
- **How it was addressed:**
  - `ASC-1`: Removed `d.Gems = 0` from `AscensionService.luau:66` and documented that Gems survive prestige per operator decision.
  - `PASS-1`: In `PurchaseService.luau`, updated mid-session gamepass callback to record `data.PassSlotsGranted = already + gained`, guaranteeing idempotency across joins. Exposed `PurchaseService._onGamePassPurchaseFinished` for testing.
  - `SLOT-2`: In `ServerBootstrap.server.luau:546`, passed `data.Diamond.SlotNodes` to `DiceCatalog.dieSlotCost`.
- **Verified how:**
  - Full automated suite: 23 passed, 0 failed.
  - Assertions increased from 3,686 to 3,693 (+7 assertions).
  - Pin tests:
    - `tests/Integration_Ascension.test.luau`: Verified `postData.Gems == 500` preserved across ascension.
    - `tests/PassEffects.test.luau`: Tested mid-session purchase of `DieSlots2`, asserted `PassSlotsGranted == 2` and slots increased by 2, and asserted subsequent `applyPassSlotGrant` calls do not add more slots.
    - `tests/DiamondNodes.test.luau`: Tested server-side `dieSlotCost` contract with and without `slotNodes` when at base cap.
  - Evidence captured: `deliveries/evidence/2026-09-17-batch2-real-money.txt`.
- **Still open?** CLOSED. Fixed in Batch 2.

### 2026-09-17 — Batch 3: Permanent Player Loss (`ASC-2`, `LOGIN-1`, `NAN-1`)
- **Date / Batch / Defect ID:** 2026-09-17 / Batch 3 / `ASC-2`, `LOGIN-1`, `NAN-1`
- **What happened:**
  - `ASC-2`: On ascension, Cash upgrades were reset, but `MassBudget` was omitted from the reset list while dice were reset to a fresh budget-60 die. Because `MassBudget` remained maxed, the player could never purchase it again for the life of the account. Furthermore, newly granted dice in `PlayerProfile.grantDieSlots` started at base budget without inheriting active `MassBudget` levels, and `MassBudget` was missing from `TEMPLATE.Upgrades`.
  - `LOGIN-1`: In `ProgressionService.luau`, `checkLoginStreak` discarded the return value of `PlayerProfile.mutate` and credited rewards unconditionally. When profile writes failed, the player received currency while the streak failed to advance, creating an infinite reward mint on repeat rejoin. Sibling paths (spin, promo code, quests) set claim flags before credit confirmation, risking lost rewards on credit failure.
  - `NAN-1`: `PlayerProfile._reconcile` only checked for missing keys. If any numeric currency (`Cash`, `Gems`, `Diamonds`, `LifetimeCash`, `HighestRoll`, `Ascensions`, `TotalRolls`, `DieSlots`) became NaN or infinite, it persisted indefinitely, defeating comparison checks and permanently poisoning player saves.
- **What caused it:**
  - `ASC-2`: Omission in `AscensionService.luau` upgrade wipe loop and uninherited account upgrades in `PlayerProfile.grantDieSlots`.
  - `LOGIN-1`: Missing error check on `mutate` in `checkLoginStreak` and lack of atomic rollbacks in sibling reward claims.
  - `NAN-1`: Missing NaN/infinite type guards in `_reconcile` and `EconomyService.writeBalance`.
- **How it was addressed:**
  - `ASC-2`: Reset `d.Upgrades.MassBudget = 0` in `AscensionService.luau`. Added `MassBudget = 0` to `TEMPLATE.Upgrades`. In `PlayerProfile.grantDieSlots`, auto-inherited account `MassBudget` levels for newly created dice up to `shape.cashBudgetCap`.
  - `LOGIN-1`: Gated `checkLoginStreak` reward credit on successful profile `mutate`. Implemented atomic rollbacks on partial failures in `claimSpin`, `redeemCode`, `claimQuest`, and `claimChest`.
  - `NAN-1`: In `PlayerProfile._reconcile`, sanitized all 8 numeric scalars against NaN and non-finite values. In `EconomyService.writeBalance`, refused non-finite value assignments.
- **Verified how:**
  - Full automated suite: 23 passed, 0 failed.
  - Assertions increased from 3,693 to 3,707 (+14 assertions).
  - Pin tests:
    - `tests/Integration_Ascension.test.luau`: Seeded `MassBudget = 10`, asserted `Upgrades.MassBudget == 0` wiped on ascension.
    - `tests/ProfileLifecycle.test.luau`: Verified `grantDieSlots` auto-inherits account `MassBudget` levels on new dice up to cap.
    - `tests/ProfileSchema.test.luau`: Verified NaN and non-finite values across all 8 numeric scalars are repaired to safe template defaults, and verified `TEMPLATE.Upgrades.MassBudget == 0`.
  - Evidence captured: `deliveries/evidence/2026-09-17-batch3-permanent-loss.txt`.
- **Still open?** CLOSED. Fixed in Batch 3.

### 2026-09-17 — Batch 4: Inert Features (`BOARD-1`, `LUCK-1`, `SHAPE-1`, `QUEST-1`)
- **Date / Batch / Defect ID:** 2026-09-17 / Batch 4 / `BOARD-1`, `LUCK-1`, `SHAPE-1`, `QUEST-1`
- **What happened:**
  - `BOARD-1`: Leaderboard scores were never written because `updatePlayer` was never called from player exit, graceful shutdown, or periodic auto-save. All three OrderedDataStores remained empty and the BOARDS panel rendered empty forever. In `getBoard`, `lastFetch` was stamped after the yielding `GetSortedAsync` call, exposing DataStore to concurrent burst storms (M3) when multiple players refreshed simultaneously.
  - `LUCK-1`: `Upgrades.Luck` was sold for up to ~$23.7M Cash but was read by zero gameplay code. It could not bias face sampling without violating FR-3.4 (would make forge probability preview inaccurate); and reading as a payout multiplier would introduce an uncalibrated 3rd stacking multiplier alongside `CashX2` and `LuckBoost`.
  - `SHAPE-1`: In `V7MenuPanel.luau:1073` and `:1157`, `playerInventory` resolved to a nil global because `playerInventory` was declared in `buildSlotsOverlay` closure. Owned total was always 0, causing players holding multiple dice to see "[ NO DICE OWNED ]" and disabling the Equip button.
  - `QUEST-1`: `questRows` in `buildQuestsOverlay` was constructed and never updated by `refreshQuests`. Quest cards displayed fabricated hardcoded text `"REWARD: +$2,500 CASH"` (violating NFR-5 server omission). Quests sat at default values, `rowState.id` remained nil, and CLAIM failed every time.
- **What caused it:**
  - Missing server lifecycle hooks (`onPlayerRemoving`, `BindToClose`, periodic tick) and post-yield cache timestamp in `LeaderboardService`.
  - Unwired sink in `UpgradeCatalog` that was superseded by `BoostService.LuckBoost`.
  - Variable scoping mismatch across closures in `V7MenuPanel`.
  - Disconnected UI renderer and hardcoded mock text in `buildQuestsOverlay`.
- **How it was addressed:**
  - `BOARD-1`: Hooked `pcall(LeaderboardService.updatePlayer, player)` in `ServerBootstrap.onPlayerRemoving` (before profile release), in `game:BindToClose` across all players, and in a 60s periodic background loop. Moved `cache.lastFetch = now` before the `GetSortedAsync` yield in `LeaderboardService.getBoard` to protect against concurrent fetch storms.
  - `LUCK-1`: Operator confirmed Option 1: removed `Luck` from `UpgradeCatalog.CASH_UPGRADES`. Retained `d.Upgrades.Luck = 0` in `AscensionService.luau` and `PlayerProfile.TEMPLATE` for save-file backward compatibility.
  - `SHAPE-1`: Declared `shapesInventory: { [string]: number }` in `buildShapesOverlay`, populated in `refreshShapes` from `state.inventory`, and read at lines 1073 and 1157.
  - `QUEST-1`: Replaced fabricated reward string with `"REWARD ON COMPLETION"`. Wired `refreshQuests` to walk `state.quests`, map quest IDs to titles/descriptions, update progress bars and completion counts, set `rowState.id / isReady / isClaimed`, and drive button states.
- **Verified how:**
  - Full automated suite: 23 passed, 0 failed.
  - Assertions increased from 3,707 to 3,712 (+5 assertions).
  - Pin tests in `tests/Leaderboard.test.luau`:
    - Verified `UpgradeCatalog.getCashUpgrade("Luck") == nil` and absent from `getAllCashUpgrades()`.
    - Verified `LeaderboardService.getPlayerRank` returns nil safely for unranked player.
    - Verified `LeaderboardService.getBoard` handles unknown boards without error.
    - Verified `LeaderboardService.updatePlayer` safely exits when player has no loaded profile.
  - Evidence captured: `deliveries/evidence/2026-09-17-batch4-inert-features.txt`.
- **Still open?** CLOSED. Fixed in Batch 4.


