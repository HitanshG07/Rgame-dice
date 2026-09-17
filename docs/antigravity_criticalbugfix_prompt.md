# Antigravity prompt — work the critical bug fix plan

**Maintained:** 2026-09-17. **Check the STATUS REGISTER in `criticalbugfix.md`
against `git log` before each run** — a stale register is how a fixed defect gets
"fixed" twice, and two of the defects in that file were *created* by exactly that
kind of unchecked edit.

Paste everything below the line. The agent will ask you which batch to work on.

---

You are fixing defects in a Roblox game called **Dice Forge Incremental**.
Repo: `C:\RGame`. Language: Luau, `--!strict` everywhere.

## YOUR SOURCE OF TRUTH

**`C:\RGame\criticalbugfix.md`** — read it in full before you touch anything. It
contains 23 defects found by a full-repository sweep, each with its location,
root cause, concrete fix code, the test to add, and how to verify it in a running
game.

**Do not re-derive the defects. Do not re-audit whether they are real.** They
were each traced and confirmed, and several were measured in a live session. Your
job is to *apply* the fixes, not to rediscover them.

But **do verify every line number before you edit it.** They were accurate on
2026-09-17; commits since then may have moved them. If a citation is stale, find
the real location and say so in your commit message.

## THE BATCH — ASK ME FIRST

**Your first action is to ask me which batch to work on, then wait.** Do not pick
one yourself. Present the remaining list and do not offer a batch marked DONE.

Ask it plainly:

> Which batch would you like me to fix? Remaining: **1 (the forge)**, **2 (real money)**, **3 (permanent loss)**, **4 (inert features)**, **5 (wrong numbers)**, **6 (safety nets)**, **7 (everything else)**.

**One batch per run. Do not start a second batch without asking me.** Batch 1 is
two lines; batch 6 is large. They are not the same size and should not be
bundled.

If I pick a batch out of order, do it — but tell me first if the order matters
for that one. It does for two:

- **Batch 1 before anything else.** `FORGE-1` makes the forge report success on
  every failure, which is actively *hiding* `FORGE-2`. Until it is fixed you
  cannot tell whether any other forge fix worked.
- **Batch 6 before any Phase 2 feature work.** Those items are not the most
  painful today; they are the ones that turn into data loss the moment new
  currencies or per-die fields ship.

---

## HARD RULES — violating any of these fails the work

These are project law, not preferences. They are in `.brain/` and
`docs/blueprint/`.

1. **NFR-5 — no client message may carry a price, balance, reward, score, level,
   duration, multiplier, or outcome.** The client sends *intent*; the server
   sends *truth*. If a fix seems to need a figure on the wire, it is the wrong
   fix. (One defect in the file — `QUEST-1` — exists because the client invented
   a reward figure the server deliberately withholds.)

2. **The server is the sole authority on every economic outcome.** No client
   argument may influence a payout, cost, or grant without being verified — not
   merely type-checked. Two defects in the file are exactly this mistake.

3. **`EconomyService` is the only module permitted to mutate Cash, Gems or
   Diamonds.** Do not write a balance directly, even inside a `mutate`.

4. **Never confiscate.** If a fix would reduce something a player already owns —
   slots, budget, currency — that is the wrong fix. The established pattern is
   `AddDieSlot`: refuse new purchases past a cap, never take back what was
   bought. Say so explicitly in your commit when a fix could have confiscated and
   does not.

5. **`RemoteFunction:InvokeClient()` is prohibited project-wide.** Exactly one
   `ProcessReceipt` assignment exists; do not add another. No `SetAsync` for
   profile data. No `MessagingService` in our code.

6. **Zero placeholders.** No stubs, no "TODO", no commented-out scaffolding. A
   file you touch must be complete and production-grade when you finish.

7. **Do not touch `src/Server/Vendor/ProfileStore.luau`.** 2,242 lines of pinned
   third-party code. An upstream update would clobber any edit.

---

## STOP AND ASK ME — do not decide these yourself

Three defects are **economy decisions**, not code decisions. `criticalbugfix.md`
marks them `NEEDS A DECISION` and gives a recommendation. **Bring me the
recommendation and wait for my answer.**

| Defect | The question |
|---|---|
| `ASC-1` | Should Gems survive ascension? (They are bought with Robux and are not on FR-9.1's reset list — but they are the vault-capacity sink) |
| `LUCK-1` | Should `Upgrades.Luck` be implemented or removed? It currently costs ~$23.7M and does nothing |
| `QUEST-1` | May quest reward amounts be shown at all? Showing them needs the reward table moved to `src/Shared/`, which is a design change |

Also stop and ask if:

- A fix would require changing a **balance constant** validated by the pre-code
  simulation (`ALPHA`, the probability formula, the streak cliff, element
  coefficients). Those must not be retuned without re-running the simulation.
- A fix would require a **UI layout change**. Minor additions are fine; a
  redesign is not. Describe what you need and wait.
- The fix in `criticalbugfix.md` looks **wrong to you**. Say so with your
  reasoning rather than silently doing something else. You may well be right —
  but I want to know.

---

## FOUR PLACES THE OBVIOUS FIX IS WRONG

`criticalbugfix.md` carries a **"WHY THIS AND NOT THAT"** note on these. Read it
before you start, because the tempting version would be rejected at audit:

- **`FORGE-1`** — do *not* change `NetClient.forge` to return a tuple. Five other
  call sites already read the table correctly; you would break them to
  accommodate two that are wrong.
- **`FORGE-2`** — do *not* start by normalising `DiceCatalog.newDie`. Existing
  saved D7/D14 dice keep their 59.997 budget, so the client stays broken for
  every current owner and you inherit a migration. Fix the client first.
- **`PASS-1`** — credit `PassSlotsGranted` by what was **actually granted**, not
  by the amount owed. A player at the ceiling would otherwise permanently forfeit
  slots. The correct pattern is already written at `PurchaseService:419-421`.
- **`MULT-1`** — do *not* just change `500` to `50`. That is the third hardcoded
  copy of a server-owned constant in one function. Move the constants to
  `src/Shared/`, the way `ForgeMath` already is.

---

## HOW TO WORK

### Before you edit

1. Read `criticalbugfix.md` in full, then the entries for your batch again.
2. Read `.brain/LEDGER.md` — L-019, L-020, L-022, L-025, L-027, L-057 are the
   ones that bite on this work.
3. Verify every line number in your batch against the live file.

### While you edit

**Grep every call site in the same commit.** This is the single most important
instruction in this document, because it is how two of the defects you are
fixing were created. When you change a shared function's behaviour — especially
if you add an *optional* parameter — the compiler will not tell you which callers
are now wrong. Optional means silent. Find them yourself.

**Comment the non-obvious.** This codebase explains *why*, not *what*. When you
fix something subtle, leave the reasoning at the site so the next reader does not
"fix" it back. Several defects in your list are exactly that: a later author
undoing an earlier correct decision because nothing said why.

### Tests

**Every fix needs a test that fails before it and passes after.** Not a test that
merely exercises the code — one that would have *caught* this defect.

Two anti-patterns to avoid, both of which have already happened here:

- **A test whose assertions are its own literals cannot fail.** Eleven such
  assertions were once added, inflating the count while covering nothing.
- **Testing only the convenient case.** A real-money defect shipped because its
  test only ever passed `doubled = true` — the one value no real caller uses.

### Verification — RUN IT IN ROBLOX STUDIO, THROUGH THE MCP SERVER

**This is mandatory and it is not satisfied by reading code, by reasoning, or by
a build succeeding.** Rojo does not type-check. A green build proves nothing.

**Use the Roblox Studio MCP server.** It is connected and working —
`execute_luau`, `start_stop_play`, `get_console_output`, `screen_capture`,
`user_mouse_input` and `script_read` are all available. Drive the real game with
them.

> **Note on a stale rule.** `AI_WORKSPACE_RULES.md:12` states *"No Roblox MCP
> server is connected to this workspace."* **That line is out of date** — it is
> dated 2026-07-30 and MCP has been used extensively since. It is a Section 1
> environment-matrix line, which is the part of the bootloader explicitly meant
> to be re-measured against reality. Do not let it block you, and do not edit it
> — it is human-locked. Just report that you used MCP.

**The loop, per batch — repeat until it is clean:**

1. **Confirm sync before trusting anything.** The Rojo plugin drops silently and
   has done so repeatedly in this project. Hash the file on disk and in Studio
   and compare, or probe for a symbol that exists only in your new code. A green
   suite over stale code looks *identical* to a real pass (L-019, L-020).
   Rojo also **cannot inject a NEW file while Play is running** — a brand-new
   test suite will simply be absent and report nothing at all, which is silence,
   not failure.
2. **`start_stop_play(true)`**, then **`get_console_output`**.
3. **Read the whole suite result**, not just the summary line. Note the
   **assertion count** and every warning.
4. **If anything fails — fix it and run again.** Do not move on, do not report
   partial success, and **do not weaken an assertion to make it pass.** If a test
   is genuinely wrong, say so explicitly and explain why; that has happened here
   before and it is a legitimate finding, but it must be stated, not silently
   done.
5. **Exercise the actual fix in the running game.** Click the real button with
   `user_mouse_input`, read the real label, watch the real balance move.
   `screen_capture` the result. Several defects in your list **passed a green
   suite** and were caught only by looking at the screen.
6. **Repeat from step 1 until the suite is green, the console is clean, and the
   fix is visibly working.**

**Report the assertion count before and after.** An unchanged count on a change
that adds assertions means the code never reached Studio. If it goes *down*,
explain why — that is sometimes correct (deleting a fake test) and sometimes a
regression.

**Two MCP gotchas that will cost you time if you do not know them:**

- **`execute_luau` holds its own module cache (L-022).** A Server-context script
  cannot see the live player's profile. If you need live profile state, drive the
  client or add a temporary probe — do not conclude the feature is broken.
- **The `studio_id` changes between sessions.** Re-run `list_roblox_studios` if a
  call fails with a disconnected instance.

### P-1 STATIC ANALYSIS — I need this from you specifically

**This is the standing blocker on every gate in this project, and you may be the
only one who can clear it.** `AI_WORKSPACE_RULES.md:12` designates your session
as the one that executes verification.

Open Studio's **Script Analysis** pane and report the output verbatim. The
baseline is **158 warnings**. I need:

- The count after your change (zero **new** warnings is the standard).
- The full list saved to `deliveries/evidence/<date>-static-analysis.txt`.

`TEST_PLAN.md:45` is explicit that a missing P-1 artifact is a **rejected gate,
never a pass with a caveat.** One defect in your list (`SHAPE-1`, an undefined
global) would have been caught by this immediately.

If you genuinely cannot access the pane, say so plainly — do not substitute
anything else for it and do not call the gate clean.

---

## THE FIX LOG — maintain this from your very first fix

**Create `C:\RGame\fixlog.md` on your first fix and keep it updated as you go.**
Not at the end of a batch — **as each issue happens.** A log written from memory
afterwards is the thing this project keeps getting burned by.

This is separate from `criticalbugfix.md`. That file is the *plan*; this one is
the *record of what actually happened when you executed it*.

**Every entry, in order, for every problem you hit — however small:**

| Field | What goes in it |
|---|---|
| **Date / batch / defect ID** | Which fix you were on |
| **What happened** | The symptom, verbatim. Paste the real error, the real failing assertion, the real console line |
| **What caused it** | The actual root cause, once you know it |
| **How it was addressed** | What you changed, or why you decided not to |
| **Verified how** | Suite result, assertion count, what you saw in the running game |
| **Still open?** | If you could not resolve it, say so and leave it open |

**Log these too, not just code failures:**

- A test that failed for a reason in the *test* rather than the code.
- A line number in `criticalbugfix.md` that turned out to be stale.
- A fix that did not work the first time, and what the second attempt changed.
- Anything that made you stop and ask me something.
- Anything you were unsure about and decided anyway — especially that.

**Do not tidy it.** A log with only successes in it is worthless, and I will not
believe it. The failures and the false starts are the part I actually need —
they are what tells the next person which parts of this codebase are dangerous.

Keep appending across runs. **Never rewrite an earlier entry** — if something you
recorded turns out to be wrong, add a new entry correcting it and leave the
original standing.

---

## COMMITS

**One commit per batch**, single-purpose. Message states *intent*, not mechanics:
what was broken, what a player lost, why this fix and not the obvious one.

End every commit message with:

```
Co-Authored-By: Antigravity <noreply@antigravity>
```

**Do not amend or force-push.** Do not commit anything you have not verified.

---

## WHEN YOU FINISH A BATCH

Report back with:

1. **Which defects you fixed**, by ID, and which you skipped and why.
2. **The assertion count** before and after, plus the suite result verbatim.
3. **The P-1 output** — count and the evidence file path.
3b. **Confirmation that the suite is GREEN in Studio via MCP**, with the verbatim
   result, and confirmation that `fixlog.md` is up to date through this batch.
4. **What you proved in a running game**, and what you could not.
5. **Anything you found that is not in `criticalbugfix.md`.** The sweep that
   produced it was round 1 of a planned two; round 2 was deferred. If you trip
   over something new, say so rather than quietly fixing it.
6. **Anything you were unsure about.** Say it plainly. A stated uncertainty is
   worth more than a confident guess — this project has been bitten repeatedly by
   confident records that turned out to be stale.

Then **update the status in `criticalbugfix.md`** for the entries you closed —
mark them FIXED with the commit sha — and **stop**. Do not begin the next batch.

---

## ONE LAST THING

**Your work will be audited by a fresh context that has not seen you write it.**
That is project law: the author never verifies their own work. It is not
distrust — it is the only thing that has reliably caught this class of defect
here. Two of the bugs you are fixing were introduced *by fixes*, passed a green
suite, and were found only by someone reading the diff cold.

So write the fix you would want to defend, and record honestly what you did not
verify. **"I could not prove this one in a running game" is a perfectly good
answer. A claim that turns out to be untrue is not.**
