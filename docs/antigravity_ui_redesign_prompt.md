# Antigravity prompt — UI redesign as a comparable mock preview

Paste everything below the line. Replace `<<PANEL>>` with the panel you want
reworked (e.g. `SHOP`, `SHAPES`, `FORGE`, `VAULT`, `ASCEND`, `QUESTS`,
`BOARDS`, `SETTINGS`, `SLOTS`, or `HUD`).

---

You are redesigning ONE panel of a Roblox game called Dice Forge, as a
**mock preview only**. Repo: `C:\RGame`.

## THE PANEL

AS THE USER WHICH ONE THEY WOULD LIKE TO TOUCH FIRST 

## READ THIS FIRST — WHAT WENT WRONG LAST TIME

A previous run of this prompt produced good-looking panels and broke the
game. Every item below actually happened and cost hours to find. Do not
repeat them.

1. **It edited `V7MenuPanel.luau` directly** despite the rule below saying not
   to. 705 insertions, 297 deletions, straight into the live file.
2. **It replaced `UITheme.toggle` with a hand-built TextButton** but left
   `refreshSettings` calling `UITheme.setEnabled` on it. That helper looks for a
   `Knob` child, does not find one, and silently recolours `TextColor3` instead
   — so all four settings rows read ACTIVE and clickable, including two that are
   supposed to be LOCKED because the game has no audio assets yet.
3. **It re-declared `refreshShop` with `local function` inside a nested block**,
   so the assignment `shopRefresh = refreshShop` hundreds of lines later stored
   `nil`. The fan-out over the refreshers used `ipairs`, which stops at the
   first `nil` — and shop was FIRST — so **all seven panels stopped receiving
   data**. Shop, shapes, quests, vault, slots, settings and ascend were all dead
   from one missing assignment.
4. **It mislabelled six of fourteen shop items** as CURRENCY because it inferred
   the category from "not a gamepass" instead of reading `entry.kind`, which the
   catalog already provides.
5. **It gave small print to three gamepasses out of eight**, which is what made
   the shop look uneven — the cards were geometrically identical.
6. **It fabricated an asset ID** from a source filename's timestamp
   (`rbxassetid://1786801062`) and wired an ImageLabel to it. Verified in
   Studio: the ID behaves exactly like a junk ID while a real control image
   loads. The settings button rendered blank.

The theme running through all six: **the visual layer was rebuilt and the wiring
behind it was not re-checked.** A panel that looks right and receives no data is
worse than an ugly one, because nothing announces the failure.

## HARD RULE — YOU MODIFY NO EXISTING FILE

This is a preview, not an implementation. You may create exactly ONE new file:

    src/Client/UIMockPreview.luau

You may NOT edit, refactor, or "improve" anything else. Specifically off limits:
`src/Client/UITheme.luau`, `src/Client/V7HUD.luau`, `src/Client/V7MenuPanel.luau`,
`src/Client/V7ForgePanel.luau`, `src/Client/ClientBootstrap.client.luau`,
`src/Shared/**`, `src/Server/**`, `tests/**`, `default.project.json`, anything
in `.brain/`.

If you believe a change outside that one file is required, STOP and say so
instead of making it. A preview that quietly edits the live UI is worse than no
preview, because the operator can no longer tell what they are looking at.

## WHAT TO BUILD — THREE VARIANTS IN A CAROUSEL

`UIMockPreview.luau` returns a module with `.show()` and `.hide()`. `.show()`
builds a full-screen `ScreenGui` (name it `UIMockPreview`, `DisplayOrder` above
everything else) containing:

1. **Three complete, independent redesigns of `<<PANEL>>`**, labelled A, B and C.
2. **A carousel** — one variant visible at a time, with `<` and `>` buttons and
   an A/B/C indicator showing which is on screen. Switching must be instant and
   must NOT rebuild the variants; build all three up front and toggle `Visible`,
   so the operator can flick back and forth and compare in real time.
3. **A close button** that calls `.hide()` and destroys the ScreenGui cleanly.

Each variant must be a genuinely different design direction, not three
recolours of one layout. If all three look like siblings, you have failed the
task.

## THE CONTENT MUST BE THE REAL CONTENT

**Read the live panel first and mirror exactly what it contains.** Do not invent
rows, buttons, stats, currencies, or features. Do not drop ones that exist.

Where to read each panel:
- SHOP, SHAPES, BOARDS, ASCEND, QUESTS, VAULT, SETTINGS, SLOTS →
  `src/Client/V7MenuPanel.luau` (search for `UITheme.overlay("<name>")`)
- FORGE → `src/Client/V7ForgePanel.luau`
- HUD → `src/Client/V7HUD.luau`

Also read `src/Client/UITheme.luau` in full. It holds the current palette
(`UITheme.Colors`), the 4px spacing/type ladder (`UITheme.Scale`), and these
builders, which are what the game actually draws with:

    neumorphicButton  neumorphicPod  neumorphicTile  panel  overlay  card
    listRow  verticalStack  textLine  paragraph  actionButton  statusPill
    label  smallPrint  toggle  button  createProgrammaticIcon

Your mock may draw its own primitives instead of calling these — that is the
point of exploring a new look — but every ELEMENT present in the real panel must
be present in all three variants, with the same wording and the same numbers.
Use realistic sample values read from the catalogs (`src/Shared/DiceCatalog.luau`,
`MonetisationCatalog.luau`, `VaultCatalog.luau`), never `Lorem ipsum` or "Item 1".

Nothing in the mock may be interactive beyond the carousel controls. Buttons are
drawn, not wired. This previews appearance only.

## MAKE IT NOT LOOK AI-GENERATED

The operator's exact complaint about the current UI: *"it has emojis and
everything making it look as if it was made by an ai, and not a proper
developer."* That is the bar you are clearing.

**Banned outright:**
- Emoji anywhere. Every icon must be drawn geometry (Frames, UICorner,
  rotation) or a Roblox-native shape. No `rbxassetid` for icons either — and
  **never invent an asset ID**; a previous attempt fabricated one from a
  filename timestamp and shipped a blank button.
- Purple-to-blue or pink-to-cyan gradients, "glassmorphism" frosted panels,
  neon glow on everything, and evenly-spaced identical cards with a coloured
  left border. These are the visual signature of generated UI.
- Centred text everywhere. Real interfaces align to a grid.

**What good looks like here.** This is a game about *dice, mass and weight* —
you physically move mass between faces and heavier faces land less often. The
visual language should feel like precision instruments, machined metal,
weighing scales, casino felt, engraved numerals. Three directions worth
exploring (pick three, or better ones):
- **Machinist** — brushed metal, engraved labels, tight monospace figures,
  physical toggle switches, everything looking milled.
- **Casino ledger** — deep felt, brass rules, serif headings, values set like
  a printed betting sheet.
- **Brutalist data** — heavy type, no rounding, stark hierarchy, numbers as
  the loudest thing on screen.

**Non-negotiable quality floors** (these come from the project's own UI rules
in `.brain/skills/ui_ux_design.md` — read it):
- Exactly ONE visually dominant action per screen. Competing emphasis is a
  defect.
- All spacing, radii and type sizes from ONE scale. No numbers invented per
  element.
- Text contrast at least 4.5:1. Every interactive element at least 44x44px.
- Colour is never the only signal — pair it with text, icon, or shape.
- At most ~4 type sizes and 2 weights per screen.

## LAYOUT MUST BE COMPUTED, NOT HAND-PLACED

Arrange every container with `UIListLayout` / `UIGridLayout` / `UIPadding`, or
give it exactly one child. Do NOT position siblings by hand-picked `UDim2.fromScale`
values — that is how the current panels ended up with text drawn straight
through buttons (a status label spanning x 0.44–0.66 next to a button starting
at x 0.585). A layout makes that overlap impossible by construction.

The mock must hold up at 1280x720, 800x600 and a 420px-wide phone. Text wraps
or truncates; nothing overflows its card.

## THE MOCK IS A CONTRACT — WHAT IS PREVIEWED IS WHAT GETS BUILT

The variant the operator picks will be reimplemented in the live panel, by
someone who was not you, working only from your mock. So the mock is a
specification, not a mood board.

- **Every element must be real and complete.** If the live panel has a status
  chip, a price, a locked state, a scroll region or a refusal message, the mock
  has it too, worded identically. Do not simplify for the preview and assume the
  detail gets added later — it will not, because nobody will know it was missing.
- **Show EVERY state, not just the happy one.** The single largest source of
  breakage last time was states that only exist at runtime. For each panel, the
  mock must show at minimum: owned / not owned, affordable / unaffordable,
  locked-with-reason, and empty. Put them on different rows of the same variant
  so they can be compared at a glance.
- **Name your elements the same as the live ones** (`Item_<key>`, `Setting_<key>`,
  `OwnedPill`, `BuyButton`, `ToggleButton`). Whoever ports it will grep for those.
- **Say what you are NOT showing.** If a state or element is omitted, list it in
  the deliverable. An honest gap can be planned around; a silent one cannot.

## DO NOT BREAK THE GAME — THE WIRING RULES

You are not touching live code, so you cannot break it directly. But your design
will be ported, and these are the traps that broke it last time. Design so the
port cannot hit them:

- **Do not invent a control the theme cannot already express.** If you replace a
  `UITheme.toggle` with something custom, the port must also replace every
  `UITheme.setEnabled`/`setButtonText` call that drives it — helpers that fail
  SILENTLY on the wrong widget type. Prefer restyling an existing builder over
  substituting a new control. If you do substitute one, say so explicitly in the
  deliverable and list every state the replacement must handle.
- **A control has three states, not two:** on, off, and unavailable. The third is
  not a shade of the other two, and it needs its own visible treatment plus a
  reason string. Music and SFX are permanently unavailable right now.
- **Never invent an `rbxassetid`.** Not from a filename, not from a timestamp,
  not as a placeholder. If a design needs an image, STOP and say so.
- **Read categories and figures from the catalogs**, never from a guess about
  what a thing is. `entry.kind` distinguishes Currency / Boost / Bundle /
  TimeSkip; a card that is not a gamepass is not automatically currency.
- **Respect the Roblox topbar.** Modal panels use `IgnoreGuiInset = false` so
  their canvas equals the visible screen and a 0.5/0.5 centre is genuinely
  centred. Setting it true starts the canvas 58px above the screen and no
  arithmetic correction fixes it cleanly — four were tried.

## UNIFORMITY IS A REQUIREMENT, NOT A STYLE NOTE

Within one variant, elements of the same kind must be identical in structure:

- Every card of a type has the SAME rows in the SAME order. If one card has
  three text lines and its neighbour has two, the row is missing, not optional —
  write the missing content from the catalogs rather than leaving a gap.
- Every button of a role has one height, one type size, one corner radius.
- Every tab in a bar shares the row: derive tab width from the COUNT so adding a
  category cannot push the last one off the panel. A literal `0.32` fits three
  tabs and silently breaks on the fourth — that happened.
- All spacing, radii and type sizes come from one scale.

## TECHNICAL CONSTRAINTS

- `--!strict` at the top. Roblox Script Analysis must report **zero errors and
  zero warnings** — the project is currently at zero and must stay there.
- A type annotation on a table-field assignment is a SYNTAX error in Luau
  (`Module.Foo: number = 1`). Annotate locals only.
- Verify every `Enum` symbol you use exists. An invalid one fails module load
  silently.
- No `require` cycles. Do not require any `src/Server/**` module.
- Build the whole preview without needing a server: no remotes, no profile
  reads, no `NetClient`.

## HOW TO SHOW IT TO ME

`UIMockPreview.luau` must be runnable from the Studio command bar in one line,
and tell me that line. Something like:

    require(game.StarterPlayer.StarterPlayerScripts.Client.UIMockPreview).show()

## DELIVERABLE

1. The single new file.
2. The one-line command to display it.
3. A screenshot of each of the three variants.
4. Two or three sentences per variant on what design idea it is testing and
   what you think its weakness is.
5. **A PORTING NOTE for the variant you think is strongest**, covering:
   - every existing element it REPLACES rather than restyles, and for each, the
     helper functions that drive it today (`setEnabled`, `setButtonText`,
     `setPill`, `toggle`) which would need a replacement;
   - every state it shows and every state it does NOT;
   - any figure it displays and which catalog that figure comes from.
   This is what stops the port from looking right and doing nothing.
6. **Confirmation that you modified no existing file**, as the literal output of
   `git status --porcelain`. If it lists anything other than your one new file,
   say so at the top of your report rather than leaving it to be discovered.

Report what you actually built and verified. If something did not work, say so
plainly rather than describing the intent as though it succeeded. A report that
describes intent as outcome is the single most expensive thing you can hand
back, because it moves the cost of finding the failure to someone who does not
know where to look.
