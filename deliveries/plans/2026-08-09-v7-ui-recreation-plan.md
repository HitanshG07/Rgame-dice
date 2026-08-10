# GATE 0 INTAKE PLAN: V7 CLIENT UI RECREATION FOR DICE FORGE INCREMENTAL

**Date:** 2026-08-09  
**Build Tier:** PRODUCTION  
**Persona:** Product Manager  
**Mode:** Standard Pipeline (7-Gate Verification)  
**Scope Fence:** Client UI Construction (`src/Client/`) based on UI Preview V7 specification. Existing UI preserved intact inside `src/Client/LegacyUI/`.

---

## 1. Goal & Requirements
Recreate the complete in-game Roblox client UI using Luau `--!strict` modules to match the **UI Preview V7** design (V2 spacious 3D arena view + full-screen dedicated feature overlays).

### Operator Non-Negotiable Directive:
> **DO NOT REMOVE THE CURRENT UI.** Preserved completely as a safekeep inside `src/Client/LegacyUI/`.

---

## 2. Component Architecture & Files

1. **`src/Client/LegacyUI/` [NEW / SAFEKEEP]**
   - Exact copy of pre-existing UI files (`HUD.luau`, `ForgePanel.luau`, `MenuPanel.luau`, `UITheme.luau`, `ClientBootstrap.client.luau`) for instant rollback if desired.

2. **`src/Client/UITheme.luau` [MODIFY]**
   - Single source of visual truth (SRS FR-13.1).
   - V7 Color Palette:
     - `PanelDark`: `Color3.fromRGB(11, 14, 26)` (Obsidian Glass)
     - `PanelMaroon`: `Color3.fromRGB(20, 16, 28)`
     - `BorderGold`: `Color3.fromRGB(245, 158, 11)` (Emissive Gold)
     - `PrimaryCyan`: `Color3.fromRGB(0, 243, 255)`
     - `FireRed`: `Color3.fromRGB(239, 68, 68)`
     - `FreezeBlue`: `Color3.fromRGB(59, 130, 246)`
     - `MultiplierGreen`: `Color3.fromRGB(16, 185, 129)`

3. **`src/Client/V7HUD.luau` [NEW]**
   - Top nav HUD containing Cash, Gems, Prestige Diamonds, Like Goal Event banner (`3× Cash Event`), and action icons.
   - Scale-only layout (`UDim2.fromScale()`) per SRS FR-13.7.

4. **`src/Client/V7ForgePanel.luau` [NEW]**
   - Full-screen dedicated overlay for face mass budget forging.
   - Die selection sidebar (Die 1 to 7).
   - Zero-sum face mass budget sliders/adjusters (`+`/`-`), element selection (Gold, Fire, Freeze, Multiplier), EV & Void risk calculations via `ForgeMath.luau`.

5. **`src/Client/V7MenuPanel.luau` [NEW]**
   - Full-screen dedicated overlays manager for:
     - Dice Shapes (D4, D6, D8, D12, D20)
     - Die Slots (Slots 1–7)
     - Ascension Tree ($b$ Streak Strength build axis)
     - Shop & Passes (Gamepasses + Dev Products with `Starter Bundle` countdown)
     - Leaderboards (Top Net Worth, Highest Roll, Max Prestiges)
     - Quests, Vault, Settings.

6. **`src/Client/ClientBootstrap.client.luau` [MODIFY]**
   - Initializes V7 Client UI modules and mounts them to `StarterGui`. Includes toggle parameter to switch to LegacyUI if needed.

---

## 3. Testable Acceptance Criteria

- **AC-1:** `--!strict` on 100% of first-party Luau client scripts. Zero Script Analysis warnings or errors.
- **AC-2:** No illegal syntax patterns (e.g. zero occurrences of `T.field: Type = value`).
- **AC-3:** Existing client files safely backed up in `src/Client/LegacyUI/`.
- **AC-4:** V7 UI panels created cleanly using `UITheme.luau` scale-based helpers (`UDim2.fromScale`).
- **AC-5:** Full integration with `NetClient.luau` and `StateSync` remote payload data without breaking server authority (SRS NFR-5).

---

## 4. Verification & Gate Walk Strategy

- **Gate 0:** Intake & Plan (This document + `implementation_plan.md`) -> `PLAN-APPROVED`
- **Gate 1:** Code Construction (`src/Client/`) -> `DIFF-COMPLETE`
- **Gate 2:** Mechanical Validation (Syntax, strict checks, syntax trap grep) -> `MECHANICALLY-CLEAN`
- **Gate 3:** QA Audit (Spec & Remote Data Contract verification) -> `AUDIT-APPROVED`
- **Gate 4:** Security Audit (Server authority, remote trust boundary) -> `SECURE`
- **Gate 5:** Delivery Summary -> `DELIVERED`
- **Gate 6:** Evolution & Scoreboard update -> `EVOLUTION-COMPLETE`
