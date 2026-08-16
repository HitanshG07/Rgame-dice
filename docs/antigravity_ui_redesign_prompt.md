# Antigravity prompt — UI redesign as a comparable mock preview

Paste everything below the line. Replace `<<PANEL>>` with the panel you want
reworked (e.g. `SHOP`, `SHAPES`, `FORGE`, `VAULT`, `ASCEND`, `QUESTS`,
`BOARDS`, `SETTINGS`, `SLOTS`, or `HUD`).

---

You are redesigning ONE panel of a Roblox game called Dice Forge, as a
**mock preview only**. Repo: `C:\RGame`.

## THE PANEL

AS THE USER WHICH ONE THEY WOULD LIKE TO TOUCH FIRST 

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

Report what you actually built and verified. If something did not work, say so
plainly rather than describing the intent as though it succeeded.
