# Antigravity prompt — audit `tools/` and `screenshots/` for what is still needed

Paste everything below the line into Antigravity. This is an AUDIT that ends in
a recommendation list. It deletes nothing on its own — the operator decides
after reading your report.

---

You are auditing two directories in `C:\RGame` to find what is genuinely dead
and what must be kept. Repo branch: `ui-rewamp-ongoing`.

**Delete nothing. Produce a report.** The operator has been burned before by a
run that "cleaned up" and broke working things, so the deliverable is a
classified list with evidence per item, not a tidied directory.

## BACKGROUND — what is already known

A prior analysis established the following. Verify anything you doubt; do not
re-derive what is already settled.

- `tools/` currently holds **32 `.js` scripts**. Six spent one-offs were already
  removed in commit `0fcda4c` (five `copy_*` scripts that copied one fixed
  screenshot to one fixed path, plus `replace_inline_quests.js` whose line-marker
  guards no longer match). Do not look for those.
- `screenshots/` holds **45 PNGs, ~8MB total**.
- **34 of the 45 screenshots are named inside a capture script.** The scripts and
  the screenshots are ONE system: a script names the file it produces, so
  deleting a script removes the ability to regenerate that screenshot.
- `tools/roblox_studio_mcp_proxy.js` is the **live MCP transport**, referenced by
  `.mcp.json`. It was hardened in `a4704ed`. **Never touch it.**

### Three byte-identical duplicate pairs were found (md5-confirmed)

1. `quest_variant_b_casino_ledger.png` == `quest_variant_c_brutalist.png`
2. `ascend_sovereign_vault_armed.png` == `ascend_sovereign_vault_qualified.png`
3. `live_quests_production.png` == `live_quests_screen.png`

Pair 1 is **a capture defect, not merely waste**: two variants that are supposed
to be different design directions are the same image, meaning variant C was
never actually captured. Pair 2 shows two different states as identical pixels.
Establishing whether these are stale files or a live bug in the capture path is
part of this audit — see Task C.

## TASK A — classify all 32 scripts in `tools/`

For each script, determine which ONE bucket it belongs in, and give the evidence
that put it there:

- **LIVE INFRASTRUCTURE** — needed for the ongoing UI redesign work (displaying
  `UIMockPreview`, capturing variants, verifying layout in Studio). Deleting it
  would cost real work to rewrite.
- **REUSABLE** — generic enough to serve a future task even if idle right now
  (e.g. it takes a parameter, or captures whatever is on screen).
- **SPENT ONE-OFF** — hardcoded to a target that no longer exists, or performs a
  migration already committed. Cannot do useful work again.
- **BROKEN** — errors on invocation regardless of intent.

Method that actually distinguishes these:

1. Read the script. Does it hardcode a specific panel, filename, line number, or
   absolute path? Hardcoding to something already done implies SPENT.
2. Check whether its target still exists. A script writing into a directory that
   is gone, or splicing line numbers that have shifted, is SPENT or BROKEN.
3. **Run the read-only ones** — the `inspect_*`, `check_*`, `find_error*` scripts
   observe without mutating. Run each and record whether it succeeds, errors, or
   hangs. Report the actual output.
4. **Do not run scripts that mutate** (`sync_*`, `replace_*`, anything writing
   into `src/`). Classify those by reading alone and say that you did.

Pay particular attention to these, which look like near-duplicates and may
collapse into one:

- `find_error.js` vs `find_error_line.js`
- `inspect_columns.js` vs `inspect_exact_geometry.js` vs `inspect_live_geometry.js`
- `capture_refined.js` vs `capture_all_screens.js` vs `fast_capture_all_dice.js`
- `test_live_quests.js` vs `sync_and_test_live_quests.js`
- `capture_live_ascend_v2.js` vs `verify_live_ascend.js` vs `test_live_ascend_overlay.js`
- `open_preview_in_studio.js` vs `direct_open_preview.js` vs `show_preview_live.js`

If two scripts do the same job, say which one is the better version and why —
that is the judgement the operator wants, not a list of similarities.

## TASK B — classify all 45 screenshots

Bucket each as:

- **CURRENT** — depicts the UI as it exists now, or is a design variant still
  under consideration for the redesign.
- **SUPERSEDED** — an earlier capture of something since redesigned. The newer
  capture exists; name it.
- **DUPLICATE** — byte-identical to another file (three pairs listed above; look
  for more).
- **ORPHAN** — no script produces it and no document references it.

These eleven are produced by NO script, so their provenance is the mock-preview
sessions and only you can date them:

    ascend_variant_a_armed_state.png      ascend_variant_a_machinist.png
    ascend_variant_b_armed_state.png      ascend_variant_b_casino_ledger.png
    ascend_variant_b_locked_state.png     ascend_variant_c_brutalist.png
    live_quests_production.png            quest_variant_a_machinist.png
    quest_variant_b_casino_ledger.png     quest_variant_c_brutalist.png
    studio_verified_ascend.png

For each, state whether it reflects a design still in play or a rejected/older
direction. **Open the images and look at them** — filenames lie, and the
duplicate pairs above prove it.

## TASK C — determine whether the capture path is still broken

This is the highest-value part of the audit, because it affects work in flight.

Two variant screenshots being byte-identical means one capture silently did not
happen. Determine which explanation holds:

- The carousel did not actually switch variants before the second capture, OR
- The same frame was captured twice, OR
- The screenshot-saving path dropped one image and an older file remained.

Relevant fact: the MCP proxy's screenshot save was fixed in `a4704ed`. It
previously tracked captures in a single pending slot, so whichever JSON-RPC
reply arrived first claimed it — an `initialize` response could consume a
capture and the PNG would silently never be written, leaving a stale file in
place. That is now keyed by request id.

**Test it now that the fix is in:** display `UIMockPreview`, capture two
DIFFERENT variants in one session, and md5 the two outputs. If they differ, the
path is healthy and the duplicates are historical. If they match, the defect is
live and is a bug report, not a cleanup item. Report the md5s either way.

## TASK D — settle `gp_images/`

15 files, ~2MB (`x2_cash.png`, `vip_vault.png`, `starter_bundle.png`,
`large_gem_pack.png`, and so on). **No code references any of them**; only
`settings_gear.jpg` appears, in `docs/handoff-7.md`.

They match entries in the monetisation catalog, and `HANDOFF.md` records that
Roblox asset IDs do not exist yet (`DUMMY_ID_*` placeholders that fail closed).
The likely reading is that these are gamepass art pending upload — assets, not
debris.

Confirm or refute: do the filenames correspond to entries in
`src/Shared/MonetisationCatalog.luau`? Is there any record of them having been
uploaded? Recommend KEEP or DELETE with your reasoning.

## HARD LIMITS

- **Delete nothing.** Recommend only.
- **Do not touch `C:\RGame\.brain\`** — governance and project memory, off limits.
- **Do not touch `src/Client/UIMockPreview.luau`** — the operator is actively
  working in it.
- **Do not touch `tools/roblox_studio_mcp_proxy.js`** — live MCP transport.
- **Do not modify any file in `src/`, `tests/`, or `docs/`.**
- Run only read-only scripts. Name every script you ran and every one you chose
  not to run.
- Finish with `git status --porcelain` and paste it verbatim. It should be
  empty. If it is not, say so at the top of your report.

## DELIVERABLE

1. **A table of all 32 scripts**: name, bucket, one-line evidence.
2. **A table of all 45 screenshots**: name, bucket, one-line evidence.
3. **The Task C verdict**: is the capture path healthy or still dropping images?
   Include the two md5 hashes.
4. **The `gp_images/` recommendation** with reasoning.
5. **A ranked deletion list** — what you would remove, most-confident first, with
   the reclaimed size per item and what would break if you were wrong.
6. **An explicit KEEP list** of anything that looked deletable but must stay,
   and why. This list is as valuable as the deletion list.

Report what you actually observed and ran. If a script errored, paste the error.
If you could not determine something, say "undetermined" and state what evidence
would settle it — a confident guess dressed as a finding is the most expensive
thing you can hand back, because the operator will act on it.
