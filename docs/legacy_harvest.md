# LEGACY HARVEST — what to keep before Phase 3 deletes four files

**Written:** 2026-09-17 · **Against HEAD `0e7b361`**

Roadmap Phase 3 deletes `src/Client/ForgePanel.luau`, `MenuPanel.luau`,
`HUD.luau` and `CurrencyModels.luau` — 3,662 lines — described there as *"dead
weight, superseded by the V7 set."*

**Most of it is. Some of it is not.** This file preserves the parts that exist
nowhere else, so the deletion can go ahead without losing them.

## How to read this

Git keeps the code either way. **The problem this file solves is that nobody
greps a deleted file.** So each entry gives:

- **what it is** and why it has no V7 equivalent
- **the reasoning**, quoted — that is the part git preserves badly, because a
  reader who finds the code won't know why it was written that way
- **the exact retrieval command**
- **verbatim code** where the item is pure logic small enough to inline

**Retrieve any original with:**

```bash
git show 0e7b361:src/Client/HUD.luau > /tmp/HUD.luau
git show 0e7b361:src/Client/MenuPanel.luau > /tmp/MenuPanel.luau
git show 0e7b361:src/Client/ForgePanel.luau > /tmp/ForgePanel.luau
git show 0e7b361:src/Client/CurrencyModels.luau > /tmp/CurrencyModels.luau
```

## ⚠ One item is an active bug fix, not a future feature

**H-1 below is the correct implementation of `RISK-1`**, the defect in
`criticalbugfix.md` where the HUD reads `state.dice[1]` only and understates real
streak-break risk by up to 66 points. **Do not write that fix from scratch — it
is already written, correctly, with its edge cases reasoned out, in a file
scheduled for deletion.**

---

# H-1 · Whole-loadout Void probability — **the `RISK-1` fix, already written**

**From:** `HUD.luau:185-248` · **Status:** *use this, don't rewrite it*

`ClientBootstrap.computeVoidRiskPct` reads only the first die. This computes
`1 − Π(1 − pᵢ)` across every die, which is the actual quantity — `FR-5.1` breaks
the streak when **any** die lands Void.

Three edge cases it gets right that a fresh implementation would likely miss:

1. **The per-shape floor is a required argument, not an optional one.** Without
   it `voidProbability` cannot apply the proximity gate and reports the lightest
   face's landing probability as though it were the streak-break chance — *"16.7%
   on a starting D6 whose true Void chance is zero."*
2. **An unrecognised shape returns `nil`, not a guess.** `getMassFloor` answers 1
   for an unknown id, and *"a guessed floor produces a confident percentage
   measured against a gate the server would never have applied."*
3. **A flat, un-forged die contributes exactly 0 and that is correct, not a
   special case** — *"a die that cannot land a Void cannot break the streak."*

```lua
local function loadoutVoidProbability(dice: any): number?
	if type(dice) ~= "table" then
		return nil
	end

	local survive = 1.0
	local counted = 0

	for _, die in ipairs(dice :: { any }) do
		local faces = readTable(die, "Faces")
		if faces == nil then
			return nil
		end

		local mass: { number } = {}
		for _, face in ipairs(faces :: { any }) do
			local m = readNumber(face, "Mass")
			if m == nil then
				return nil
			end
			table.insert(mass, m)
		end

		if #mass < 2 then
			return nil
		end

		local shapeId = readString(die, "Shape")
		if shapeId == nil or DiceCatalog.getShape(shapeId) == nil then
			return nil
		end

		-- ForgeMath raises on degenerate input (zero total mass, for instance).
		-- A snapshot that trips it is a display problem, never a crash.
		local ok, p = pcall(ForgeMath.voidProbability, mass, DiceCatalog.getMassFloor(shapeId))
		if not ok or type(p) ~= "number" or not ForgeMath.isFinite(p) then
			return nil
		end

		survive *= (1 - p)
		counted += 1
	end

	if counted == 0 then
		return nil
	end
	return 1 - survive
end
```

**Porting note:** `readTable` / `readNumber` / `readString` are local safe-readers
in `HUD.luau`. `ClientBootstrap` already has equivalent tolerance inline (the
face-shape handling at `:232-253` that exists because an all-zero mass list once
took the whole client down). Keep the existing guards; replace only the
aggregation.

---

# H-2 · The pooled status / notice line — **V7 cannot speak to the player at all**

**From:** `HUD.luau:415-434`, and a second implementation at `MenuPanel.luau:436-455`

`Remotes.Notice` enumerates seven refusal codes. `NetClient.onNotice` exists.
**Nothing subscribes, and no V7 surface has a status line**, so every refusal
outside the forge is silent.

Three design decisions worth keeping:

- **One pooled label.** No toast instances created or destroyed per message.
- **Expiry on the heartbeat that is already ticking**, not a thread per message.
- **Messages must expire.** *"A 'SLOW DOWN' left on screen stops describing what
  just happened and starts describing the interface as permanently unhappy, and
  the player has no way to tell a message about this press from one about a press
  two minutes ago."*

```lua
local STATUS_SECONDS = 4
local statusUntil = 0

local function setStatus(text: string): ()
	setText(statusLabel, "status", text)
	statusUntil = if text == "" then 0 else os.clock() + STATUS_SECONDS
end

local function expireStatus(now: number): ()
	if statusUntil > 0 and now >= statusUntil then
		setStatus("")
	end
end
```

`MenuPanel.luau:415` adds one more idea worth taking: **a token guard so an
earlier timer cannot clear a later message.**

---

# H-3 · The Statistics panel — the only consumer of three live snapshot fields

**From:** `MenuPanel.luau:607-687`

**V7 has nine overlays and no Statistics surface.** This is the direct
explanation for `lifetimeCash`, `highestRoll` and `totalRolls` being shipped by
the server every snapshot and read by nobody: *the panel that consumed them was
deleted and never rebuilt.*

```lua
local STAT_FIELDS: { StatField } = {
	{ label = "CASH",       field = "cash",         counted = false },
	{ label = "GEMS",       field = "gems",         counted = false },
	{ label = "DIAMONDS",   field = "diamonds",     counted = false },
	{ label = "STREAK",     field = "streak",       counted = true  },
	{ label = "DIE SLOTS",  field = "dieSlots",     counted = true  },
	{ label = "LIFETIME",   field = "lifetimeCash", counted = false },
	{ label = "BEST ROLL",  field = "highestRoll",  counted = false },
	{ label = "ROLLS",      field = "totalRolls",   counted = true  },
	{ label = "ASCENSIONS", field = "ascensions",   counted = true  },
}

-- Monospace type (UITheme.Font is Enum.Font.Code), so a fixed-width label
-- column actually lines the values up into one.
local function statLine(label: string, value: string): string
	return string.format("%-11s%s", label, value)
end
```

Plus a **pooled per-die breakdown**, `MAX_DIE_ROWS` rows toggled rather than
created per render:

```lua
row.Text = string.format("DIE %d  %s  MASS %s  VOID %s",
	index, readString(die, "Shape") or EMPTY,
	money(readNumber(die, "MassBudget")), dieVoidText(die))
```

**The rule this panel is built on, worth keeping verbatim:** *"a field the
snapshot does not carry renders as a dash rather than as a zero, because a zero
here would be a claim about the player's account that no authority made."*

It also handles the pre-first-snapshot window with an explicit caption that
disappears once data lands — *"nine dashes with no caption look like a broken
panel rather than a waiting one."*

---

# H-4 · The capability `Entry` model — makes a wiring omission render *visibly*

**From:** `MenuPanel.luau:12-26`, entries at `:296-345`

Every menu entry is a record with a declared status:

| Status | Renders |
|---|---|
| `Live` | This module opens the surface itself, right now |
| `NeedsSurface` | Owned by another module, reached through an opener the orchestrator wires in. **Until that opener is set the entry renders unavailable, so a wiring omission is VISIBLE rather than silent** |
| `Pending` | The server system does not exist. Greyed, suffixed `(SOON)`, and says which update it waits for when pressed |

```lua
{ id = "Shape", label = "SHAPE", side = "Left",
  status = "NeedsSurface", surface = "Shape",
  note = "the shape surface is not attached" },

{ id = "AutoSpeed", label = "AUTO SPEED", side = "Left",
  status = "Pending", surface = nil, note = NO_SERVER },
```

*"The statuses are declared in ONE table. Turning a Pending entry live when Block
5 lands is a one-line status change with the note removed, and the diff shows
exactly which promise was just kept."*

**Why this matters now.** V7 replaced this with hardcoded strings —
`setTraitControlInert`, `"NOT YET AVAILABLE"`, `"Trait enhancements unlock in
upcoming updates."` — which is exactly the *"hardcoded note someone has to
remember to remove"* that `ClientBootstrap:171-176` argues against for audio.

**A partial survivor already exists:** `SettingsCatalog.requires` +
`V7MenuPanel:setCapability` is the same idea with **one** capability registered
(`"audio"`). It is a seam waiting for `"chest"`, `"spin"`, `"group"`, `"traits"`.

---

# H-5 · The optimistic ROLL pulse (NFR-7)

**From:** `HUD.luau:445-474`, driven at `:650-666`

A pre-allocated gold `Frame` child of the ROLL button, faded on the heartbeat.
Sub-100ms press feedback with **zero per-press allocation**.

```lua
local ROLL_PULSE_SECONDS = 0.18

-- Called synchronously on the press, before any network work is scheduled, so
-- the pulse is on screen in the same frame the player clicked. It moves colour
-- and nothing else: no figure on this HUD changes until the server says so.
```

**The rule:** an optimistic *balance* that a refusal later revokes is worse than
an 80ms-late one — so the pulse moves colour and never a number. Check V7HUD's
roll button against this before deleting.

---

# H-6 · The Like Goal → 3× Cash event UI

**From:** `HUD.luau:358-412` (`renderLikeGoal`, `renderEvent`), handler `:733-741`

A community like-count progress bar (`LIKE GOAL 1,204 / 5,000`) that, on reaching
target, **is replaced in the same HUD slot** by a `3x CASH EVENT ACTIVE` banner.

Two design decisions recorded there:

- **The banner takes the bar's slot deliberately**, because the event fires *as a
  result of* the goal completing — so the bar has nothing left to report.
- **No countdown is drawn**, because a timer is *"the exact shape of the
  manufactured-urgency pattern the operator prohibited."*

**Status:** the roadmap lists Like Goal as **dropped — "cut, not deferred"**, on
the grounds that it needs live like-count integration. Preserved so that decision
can be revisited with full information rather than re-derived from nothing. The
payload shape (`likeGoalProgress`, `likeGoalTarget`, `eventActive`) is settled and
`EventState` is still declared in `Remotes.luau`.

---

# H-7 · `CurrencyModels.luau` — 3D currency icons, and a harness that already works

**From:** the whole file, 81 lines · **Zero references anywhere in the repo**

Procedural 3D cash-stack (base + bill + band) and a glass-and-neon gem in pink
(Diamonds) and blue (Gems).

**This is not merely dead — the delivery mechanism already works elsewhere.**
`V7HUD:271-378` renders `GearMeshBuilder.build(viewport)` into a live
`ViewportFrame`, complete with a 0.55s spin-on-click at `:453-490`. Drop these
three models into the same pattern and the flat currency chips become spinning 3D
icons.

Keep the file itself rather than the description — `git show` it back when wanted.

---

# H-8 · Forge capabilities V7 dropped

**From:** `ForgePanel.luau:939-995` and `:390`

Two things the old forge could do that `V7ForgePanel` cannot:

**Per-face element assignment.** Select a face, assign an element to *that face*,
with a locked-state refusal naming the Diamond Tree. V7 cycles elements
(`:1028-1031`) but has **zero `setShape` calls** — shape changing moved to a
separate overlay entirely.

**Proportional-headroom mass redistribution** (`moveMass`, `:390`). Draws from
other faces *in proportion to their room above the floor*. V7's `adjust` uses a
flat step, which is why `+` on a starting D2 returns only 2 of the 5 mass that
`−` removed (recorded as a defect in `futureupdates.md`).

Also lost: the `~` cost-estimate discipline (`estimateCost`, `:292`), and the
step cycler `STEPS = { 1, 5, 25, 100 }` (`:102`) — V7 hardcodes `STEP = 5`, which
makes the forge unusable at late-game budgets.

---

# WHAT IS GENUINELY DEAD — delete without ceremony

Everything else in the four files. Specifically confirmed superseded:

- All panel construction, layout and theming — the V7 set replaces it wholesale
  and is the house style
- `NetClient` usage patterns — identical in V7
- The overlay/sidebar shells — replaced by `formatModalShell`
- Anything referencing the retro-pixel theme — superseded by the operator-approved
  Cozy Mocha redesign

---

# THE DELETION CHECKLIST

Do these **in one commit**, in this order:

1. **Harvest first.** Port `H-1` (it is an open bug fix) and decide on `H-2`,
   `H-3`, `H-4`. The rest can stay in git history with this file as the index.
2. **Run the L-028 check** — already done and clean: none of the four touches
   `Workspace`, `Lighting`, `CurrentCamera`, `Terrain` or `Atmosphere`, and no
   other module looks up their GUIs. The `ArenaView` failure does not repeat here.
3. **Edit `tests/ClientContract.test.luau` in the same commit** — `:104-106`
   (`VIEW_MODULES`) and `:162` (the `shutdown()` list) both name `HUD`,
   `ForgePanel` and `MenuPanel`. The suite fails loudly on a missing named module,
   which is its stated purpose. **Deleting without this edit turns the suite red.**
4. **Expect the assertion count to drop**, and say so. Removing three names from
   each list legitimately lowers the total — that is correct, not a regression.
5. **Delete the Like Goal residue too**: `Remotes.luau:30` and `:68`
   (`EventState`), and `NetClient.luau:280-282` (`onEventState`). Verified: no
   server emitter exists.

**`CurrencyModels.luau` has zero references anywhere** — it is the one file that
can be deleted with no test edit at all.
