CONSUMED-BY: Gate 2 / Matrix C
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# TEST PLAN — 2D BOUNCY BALL TYCOON

## 1. TEST STRATEGY & SCOPE
This document defines the automated and manual verification strategy for 2D Bouncy Ball Tycoon. All core mathematical formulas, data persistence routines, and network boundary handlers must be covered by unit tests or runtime smoke verification prior to delivery.

---

## 2. AUTOMATED UNIT TEST SUITES (`tests/`)

### UT-1: Upgrade Price Scaling Formula Test
- **Target Module**: `ReplicatedStorage.Source.Shared.UpgradeDefinitions`
- **Verification**: Asserts that `CalculatePrice(baseCost, growthFactor, level)` returns exact expected values across levels 0 to 100 without numeric overflow or NaN.

### UT-2: 2D Physics Vector & Collision Math Test
- **Target Module**: `ReplicatedStorage.Source.Client.Physics2DEngine`
- **Verification**:
  - Test ball velocity reflection vector calculation against circular arc normal.
  - Verify gap exit detection logic returns `true` when ball angle lies within `[GapStartAngle, GapEndAngle]`.
  - Verify spike collision triggers 2X multiplier flag.

### UT-3: DataStore Schema Migration & Fallback Test
- **Target Module**: `ServerScriptService.Source.Server.PlayerDataStoreManager`
- **Verification**:
  - Pass empty table `{}` into data loader and assert returned table contains all default fields with zero errors.
  - Pass legacy version 0 data and assert version 1 migration correctly assigns missing upgrade keys.

---

## 3. INTEGRATION TEST SUITES

### IT-1: Purchase Upgrade Network Transaction
- **Scenario**: Player with `$500` invokes `PurchaseUpgrade("AddBall")` costing `$100`.
- **Expected Outcome**: Server deducts `$100` (leaving `$400`), increments level to 1, fires `UpgradeSuccess` payload, and client spawns second ball.

### IT-2: Insufficient Funds Rejection
- **Scenario**: Player with `$50` attempts to buy upgrade costing `$100`.
- **Expected Outcome**: Server returns `success = false`, cash balance remains `$50`, UI triggers error animation.

---

## 4. RUNTIME SMOKE PROOF DEFINITION (GATE 2 / MATRIX C)
- **Target Platform**: Roblox Studio Play Solo mode (and `execute_luau` / `start_stop_play` MCP automation).
- **Smoke Steps**:
  1. Boot game session in Roblox Studio.
  2. Verify 2D ScreenGui canvas renders centered pink rotating ring and initial green ball.
  3. Verify ball bounces off ring arc cleanly at 60 FPS.
  4. Perform 1 upgrade purchase ("Add Ball") and verify second ball spawns without lag or console errors.
  5. Verify zero client/server warnings or error logs emitted during 30-second run.
