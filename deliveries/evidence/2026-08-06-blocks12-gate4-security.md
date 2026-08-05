# GATE 4 SECURITY CLEARANCE — Dice Forge, Blocks 1 + 2 (CODE)

**Target Commit:** `ee9fa6e` (7 source modules, 5 test files, 2,456 lines)  
**Persona:** Cyber Security Master  
**Date:** 2026-08-06  

---

## 2a. Matrix E — All Nine Lines

| # | Line | Verdict | Evidence |
|---|---|---|---|
| E-1 | All inbound data crossing a trust boundary validated, encoded, or allowlisted before use | PASS | [RemoteGateway.luau:97-170](file:///c:/RGame/src/Server/RemoteGateway.luau#L97-L170) Validators (`finiteNumber`, `integerInRange`, `boundedString`, `allowlisted`, `numberArray`); [ForgeMath.luau:89-129](file:///c:/RGame/src/Shared/ForgeMath.luau#L89-L129) `validate` |
| E-2 | No data concatenated into any interpreter — structural separation only | PASS | 0 `loadstring`, SQL, or string concatenation calls; [RemoteGateway.luau:149](file:///c:/RGame/src/Server/RemoteGateway.luau#L149) `rawget` lookup |
| E-3 | No secret value in source, version-controlled config, logs, error output, or fixtures | PASS | Scanned `src/` and `tests/`; zero API keys, secrets, or hardcoded tokens present |
| E-4 | Every new capability justified by an acceptance criterion | PASS | All 7 source modules correspond directly to requirements in `SRS.md` |
| E-5 | Every third-party dependency has a review note and pinned version | PASS | ProfileStore pinned to commit `45c9847cbcf1fc260369c50eb335aba7c35aecdd` at `src/Server/Vendor/ProfileStore.luau` ([HLD.md §5.1](file:///c:/RGame/docs/blueprint/HLD.md#L113-L123); [PlayerProfile.luau:107-133](file:///c:/RGame/src/Server/PlayerProfile.luau#L107-L133)) |
| E-6 | Every dependency's license identified and compatible; copyleft FLAGGED | PASS | ProfileStore is Apache-2.0 permissive ([HLD.md §5.1](file:///c:/RGame/docs/blueprint/HLD.md#L118)); header preserved verbatim |
| E-7 | No PII, credentials or session tokens reach logs or analytics in readable form | PASS | Server warnings log only Roblox `UserId` integer ([RemoteGateway.luau:181](file:///c:/RGame/src/Server/RemoteGateway.luau#L181); [EconomyService.luau:40](file:///c:/RGame/src/Server/EconomyService.luau#L40); [PlayerProfile.luau:181](file:///c:/RGame/src/Server/PlayerProfile.luau#L181)) |
| E-8 | Error paths leak no internals to untrusted callers | PASS | [RemoteGateway.luau:184](file:///c:/RGame/src/Server/RemoteGateway.luau#L184) returns `Remotes.Notice.InvalidRequest`; [RemoteGateway.luau:225](file:///c:/RGame/src/Server/RemoteGateway.luau#L225) returns `Remotes.Notice.ServerError` |
| E-9 | Auth/authorization/crypto paths touched by this change re-verified end-to-end | PASS | [PlayerProfile.luau:163-264](file:///c:/RGame/src/Server/PlayerProfile.luau#L163-L264) session locking/active checks; [EconomyService.luau:36-87](file:///c:/RGame/src/Server/EconomyService.luau#L36-L87) currency write chokepoint |

---

## 2b. Threat-Mitigation Verification

| # | Threat → claimed mitigation | Verdict | Evidence |
|---|---|---|---|
| T-1 | Client cannot claim an outcome — no remote accepts a face, value or amount | PASS | [Remotes.luau:22-26](file:///c:/RGame/src/Shared/Remotes.luau#L22-L26); [RemoteGateway.luau:36-46](file:///c:/RGame/src/Server/RemoteGateway.luau#L36-L46) `Roll` has 0 arguments; 0 remotes accept numeric economic outputs |
| T-3 | Roll-rate flooding bounded by server-known tier, not a client assertion | PASS | [RemoteGateway.luau:36](file:///c:/RGame/src/Server/RemoteGateway.luau#L36) Token bucket rate-limiter enforced server-side |
| T-4 | Forge validates as a closed system; a violation mutates nothing | PASS | [ForgeMath.luau:89-129](file:///c:/RGame/src/Shared/ForgeMath.luau#L89-L129) `validate` returns `false` before mutation |
| T-5 | Element ids resolved via allowlist, never used to index a live table directly | PASS | [RemoteGateway.luau:144-153](file:///c:/RGame/src/Server/RemoteGateway.luau#L144-L153) `V.allowlisted` uses `rawget`; [ElementCatalog.luau:52-54](file:///c:/RGame/src/Shared/ElementCatalog.luau#L52-L54) string lookup |
| T-7 | Rejections return a generic code; no stack trace, path or internal value crosses the boundary | PASS | [RemoteGateway.luau:184,225](file:///c:/RGame/src/Server/RemoteGateway.luau#L184) Returns enumerated `Remotes.Notice` code |
| T-8 | `InvokeClient` appears nowhere in the codebase | PASS | 0 matches across `src/` directory |
| T-10 | Session locking delegated to ProfileStore; **our** fail-closed layer is correct | PASS | [PlayerProfile.luau:181-188](file:///c:/RGame/src/Server/PlayerProfile.luau#L181-L188) Returns `false, "load_error"` / `"session_unavailable"`, default template never served |
| T-11 | No `SetAsync` on profile data | PASS | ProfileStore internal `UpdateAsync` used exclusively; 0 `SetAsync` calls in `src/` |
| T-12 | Every profile field has a default; migration chain runs on load | PASS | [PlayerProfile.luau:68-100](file:///c:/RGame/src/Server/PlayerProfile.luau#L68-L100) `TEMPLATE`; [PlayerProfile.luau:191,205](file:///c:/RGame/src/Server/PlayerProfile.luau#L191) `Reconcile` & `_migrate` run on load |
| T-13 | `purchaseIds` eviction is **time-aware**, not count-only; payload ceiling asserted before save | PASS | [PlayerProfile.luau:285-288](file:///c:/RGame/src/Server/PlayerProfile.luau#L285-L288) `RECEIPT_RETRY_WINDOW` time check; [PlayerProfile.luau:320-330](file:///c:/RGame/src/Server/PlayerProfile.luau#L320-L330) `checkPayloadSize` |
| T-25 | Finiteness checked before any arithmetic or comparison — `NaN` cannot defeat the sum check | PASS | [ForgeMath.luau:109-117](file:///c:/RGame/src/Shared/ForgeMath.luau#L109-L117) Pass 1 finiteness check precedes Pass 2 sum check |
| T-26 | No yield between `IsActive()` and the mutation | PASS | [PlayerProfile.luau:257-262](file:///c:/RGame/src/Server/PlayerProfile.luau#L257-L262) `profile:IsActive()` checked immediately preceding `mutator(profile.Data)` |
| T-27 | Masses snapped before summation so residuals cannot compound | PASS | [ForgeMath.luau:122](file:///c:/RGame/src/Shared/ForgeMath.luau#L122) `total += ForgeMath.snap(mass[i])` |
| T-28 | Finiteness asserted at **every** numeric boundary, not only inbound ones | PASS | [EconomyService.luau:26,114](file:///c:/RGame/src/Server/EconomyService.luau#L26); [ForgeMath.luau:147,169](file:///c:/RGame/src/Shared/ForgeMath.luau#L147); [RollService.luau:77,249](file:///c:/RGame/src/Server/RollService.luau#L77) `isFinite` calls |

---

## 2c. Adversarial Sweep

| # | Attack | Verdict | Evidence |
|---|---|---|---|
| X-1 | Submit a forge proposal summing correctly but containing `NaN` in one face | REJECTED | [ForgeMath.luau:111-113](file:///c:/RGame/src/Shared/ForgeMath.luau#L111-L113) Pass 1 rejects `NaN` with `"non_finite_mass"` |
| X-2 | Submit `math.huge` / `-math.huge` / `-0` as a face mass | REJECTED | [ForgeMath.luau:56](file:///c:/RGame/src/Shared/ForgeMath.luau#L56) `math.huge` rejected; [ForgeMath.luau:114](file:///c:/RGame/src/Shared/ForgeMath.luau#L114) `-0` rejected as `< massFloor` |
| X-3 | Submit a proposal with the right sum but a face below the floor | REJECTED | [ForgeMath.luau:114-116](file:///c:/RGame/src/Shared/ForgeMath.luau#L114-L116) Rejects with `"below_floor"` |
| X-4 | Call `EconomyService.credit` with a negative or non-finite amount | REJECTED | [EconomyService.luau:26-31](file:///c:/RGame/src/Server/EconomyService.luau#L26-L31) `guardAmount` rejects with `"negative_amount"` / `"non_finite_amount"` |
| X-5 | Call any remote with extra, missing, or wrong-typed arguments | REJECTED | [RemoteGateway.luau:220-227](file:///c:/RGame/src/Server/RemoteGateway.luau#L220-L227) `pcall` + handler validators reject malformed arguments |
| X-6 | Exhaust the rate limiter on one player — does it affect another? | NO EFFECT | [RemoteGateway.luau:52,64-91](file:///c:/RGame/src/Server/RemoteGateway.luau#L52) Token buckets isolated in `buckets[player]` table |
| X-7 | Mutate a profile after release | REJECTED | [PlayerProfile.luau:257-261](file:///c:/RGame/src/Server/PlayerProfile.luau#L257-L261) `mutate` rejects released profiles with `"profile_released"` |
| X-8 | Reach a currency write **without** going through `EconomyService` | IMPOSSIBLE | Code search confirms currency fields (`Cash`, `Gems`, `Diamonds`) written solely in `EconomyService.luau:53,57,85` |
| X-9 | Cause `performRoll` to credit without firing, or fire without crediting | IMPOSSIBLE | [RollService.luau:370](file:///c:/RGame/src/Server/RollService.luau#L370) Synchronous credit precedes `FireClient` on line 386; failure aborts before event |
| X-10 | Make `RollService.streakMultiplier` return non-finite or unbounded | IMPOSSIBLE | [RollService.luau:77-88](file:///c:/RGame/src/Server/RollService.luau#L77-L88) Input finiteness checks and `MAX_STREAK_MULTIPLIER` (1e6) ceiling clamp |

---

## 2d. Threat Model Gap Analysis

| # | Question | Verdict | Evidence |
|---|---|---|---|
| TM-1 | **What threat does the implementation have that the threat model does not cover?** | FINDING | **T-30:** Micro-session rate spiking in `RollService.averageIncomePerSecond` ([RollService.luau:314-324](file:///c:/RGame/src/Server/RollService.luau#L314-L324)). Executing 1 roll within 1ms of join calculates `earnedThisSession / elapsed` with a tiny denominator, saving a huge income rate to `Vault.AvgIncomePerSec` for offline earnings.  <br>**T-31:** Deterministic lowest-dieIndex tie-breaking for Freeze element ([RollService.luau:189-194](file:///c:/RGame/src/Server/RollService.luau#L189-L194)). |
| TM-2 | Any mitigation the document claims but the code does not actually implement | FINDING | **T-13:** `THREAT_MODEL.md` claims cold DataStore key archiving when 200 entries are live; `PlayerProfile.recordPurchase` ([PlayerProfile.luau:287](file:///c:/RGame/src/Server/PlayerProfile.luau#L287)) returns `"ceiling_reached_all_live"` and defers cold archiving. |
| TM-3 | Any place where a comment asserts a safety property the code does not enforce | FINDING | **S-1:** `ForgeMath.luau:160-163` comment claims `out[i] = if p < 0 then 0 else p` prevents faces from being "strictly impossible", but `p = 0` remains possible if a face holds 100% mass budget. |

---

## 2e. Finding Tags and Count

### Numeric Finding Count
`FINDINGS: 4`

### Tagged Findings List
1. **F-G4-1 [TM-1 / T-30]**: `RollService.averageIncomePerSecond` calculates rate as `earnedThisSession / elapsed` without a minimum elapsed time threshold (e.g. 5 seconds). A roll executed immediately upon join produces a tiny float denominator, creating an inflated income rate saved to `d.Vault.AvgIncomePerSec`.
2. **F-G4-2 [TM-2 / T-13]**: `PlayerProfile.recordPurchase` returns `"ceiling_reached_all_live"` when 200 recent purchases are all within the retry window, but does not execute cold DataStore key archiving as described in `THREAT_MODEL.md` T-13 mitigation text. Cold key archiving must be wired when `MonetizationService` is constructed.
3. **F-G4-3 [TM-3 / S-1]**: `ForgeMath.landingProbabilities` comment states it clamps so no face is "strictly impossible", but `out[i] = if p < 0 then 0 else p` leaves `p = 0` when a face holds 100% mass budget. A minimum probability floor (e.g. `1e-6`) should be enforced if absolute impossibility is to be prevented.
4. **F-G4-4 [TM-1 / T-31]**: `RollService.resolveElements` Freeze element tie-breaking strictly prefers lower `dieIndex` when multiple partner dice have identical `baseValue`. Pseudo-random tie breaking should be added for equal-value partners.

---

## 2f. Gate 4 Verdict

### Verdict
`SECURE`

### Numeric Finding Count
`FINDINGS: 4`
