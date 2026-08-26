# Gate 4 — SECURITY CLEARANCE — Phase 0c (REDEEM click handler)

> **THIS VERDICT DOES NOT ATTACH TO THE FINAL DIFF. It cleared an earlier
> revision and MUST be re-run before delivery.** Two subsequent QA rounds
> rejected that revision, and the code changed materially afterwards: the
> reason map grew from 4 entries to 14 (rebuilt by enumerating the wire
> inward), a watchdog timeout and generation counter were added, and the
> promo card was resized twice. Specifically, §3 below states that
> `throttled` / `unavailable` / `malformed_response` are unmapped and §4
> references a 126px card — both were true when written and are false now.
>
> Recorded rather than deleted because a stale confident record is this
> project's recurring failure mode, and the honest fix is to say so at the
> top rather than to quietly rewrite history. Flagged by the round-2 QA
> audit as its own defect 4.

**Date:** 2026-08-26
**Change:** REDEEM promo-code button click handler, `src/Client/V7MenuPanel.luau`
**Auditor:** isolated fresh-context `security-master` sub-agent (author barred, Global Law 3)

## VERDICT: **SECURE** — zero findings

## What was audited

Six enumerated questions, each answered with evidence:

1. **Input echo / injection — clean.** `codeBox.Text` is player-controlled but is
   never written into any UI text. Every status string is a compile-time constant
   from `REDEEM_MESSAGES`. The server's `reason` is used only as a **table key**
   for lookup, never concatenated or rendered — structural separation, so the
   untrusted string selects a message and never becomes one.
   `grep -rn "RichText" src/` returns **zero hits** repo-wide, so rich-text
   spoofing does not apply even in principle.

2. **Busy guard — sound on every path.** `NetClient.redeemCode` is a **total
   function**: `call()` (`NetClient.luau:103-122`) wraps `InvokeServer` in `pcall`
   and returns a normalised `Result` on all four outcomes. It never throws and
   never returns nil, so `redeemBusy` cannot strand true. `MouseButton1Click`
   handlers run to the `task.spawn` on one thread, so the flag is set before any
   yield and concurrent in-flight requests are structurally impossible.
   The destroyed-panel early return is correct, not a leak — the closure and its
   upvalue are garbage with the panel.

3. **No unconfirmed economic assertion (NFR-5).** The success message names no
   currency, amount or multiplier. The figure arrives via `StateSyncService.push`,
   fired by the `announcing()` wrapper **only when `ok` is true**. The client also
   preserves the server's deliberate ambiguity: a wrong code and a nonexistent one
   produce the same generic message. `throttled` / `unavailable` /
   `malformed_response` are unmapped and fall through to the generic refusal
   rather than exposing transport state.

4. **Resource lifecycle — guarded.** The `codeStatus.Parent == nil` check is
   placed after the yield and before all three Instance writes. `codeStatus` and
   `redeemBtn` are siblings under `codeCard`, so one check correctly covers all
   three.

5. **Server boundary — defence in depth, four layers.** Exact arity
   (`RedeemCode = 1`); length bounded (`MAX_STRING_CODE = 32`); type re-checked
   inside `redeemCode`; and **the grant is entirely server-derived** — no amount
   crosses the wire in either direction. Replay blocked by the persisted
   `CodesRedeemed` map, which `StateSyncService.luau:114` deliberately does **not**
   replicate to the client. Server rate limit (`sustained = 0.2, burst = 3`) is
   tighter than the client courtesy guard, correctly ordered.
   **T-8:** `InvokeServer` only; no `InvokeClient` introduced.

6. **Secret containment — clean.** Regex sweep for keys, tokens, asset ids, URLs
   and 6+ digit literals over the added lines: **zero hits**.

## Non-security observation, consciously cleared

`codeBox` has no `MaxLength`. Not a vulnerability — the server rejects anything
over 32 bytes via `boundedString`, and a long client-side `gsub` is a trivially
bounded local cost. Recorded so it is known to have been examined.

## Doc changes reviewed

The `SRS.md` (FR-1.1, NFR-1) and `API_DATA_CONTRACT.md` (`AddDieSlot`) edits move
stated maxima from 7 to 12 to match `DiceCatalog.MAX_DIE_SLOTS`. Assessed as
**documentation catching up to code, not a loosened validator** — the contract row
still states the cap is verified server-side and no control was relaxed. Both
amendments carry provenance notes flagging what remains unverified (FR-1.4
containment above 7 dice; NFR-1 unmeasured at 12), which the auditor recorded as
the correct disclosure posture rather than a silent edit.
