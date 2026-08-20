# Antigravity prompt — UI redesign as a comparable mock preview

**Maintained:** 2026-08-21. Check the STATUS REGISTER below against `git log`
before each run; a stale register is how a finished panel gets redesigned twice.

Paste everything below the line, having first replaced `<<PANEL>>` in the
"THE PANEL" section with one panel drawn from the NOT STARTED list.

---

You are redesigning ONE panel of a Roblox game called Dice Forge, as a
**mock preview only**. Repo: `C:\RGame`.

## THE PANEL

Redesign: `<<PANEL>>`

Do not ask which panel to work on, and do not choose one yourself. The operator
has already picked it and written it above. If `<<PANEL>>` is still literally
`<<PANEL>>`, or names a panel the register below marks DONE, STOP and say so —
do not substitute your own choice.

## STATUS REGISTER — WHAT IS ALREADY DONE

Three panels have completed the full mock → port cycle and are LIVE. **They are
finished. Do not redesign them, do not offer to, do not "harmonise" them with
your new work, and do not touch their code.**

| Panel | Status | Landed |
|---|---|---|
| ASCEND — The Sovereign Ascension Vault | **DONE, live** | `0af794b` |
| QUESTS — dual-column, 60/40 progression | **DONE, live** | `0af794b` |
| SHAPES — specimen stage + 12-dice scaling | **DONE, live** | `c3cd0c8` |
| SHOP | NOT STARTED | — |
| SETTINGS | NOT STARTED | — |
| VAULT | NOT STARTED | — |
| BOARDS | NOT STARTED | — |
| SLOTS | NOT STARTED | — |
| FORGE | NOT STARTED | — |
| HUD | NOT STARTED | — |

The three DONE panels are still worth READING — they are the house style your
variants should feel native beside. `SPECIMEN_SCALE_MAP` and
`RACK_CARD_SCALE_MAP` (V7MenuPanel around line 505) and the Sovereign Ascension
Vault (around line 3318) are the current quality bar. Read them; do not edit
them.

SLOTS was mocked once in an earlier run and the operator abandoned those
variants. It is genuinely NOT STARTED — treat any `Slots_Variant_*.png` in
`screenshots/` as a dead end, not as prior art to build on.

## READ THIS FIRST — WHAT WENT WRONG LAST TIME

Every item below actually happened in this repository and cost hours to find.
Items 1–6 come from the run that broke the game; items 7–11 come from the three
successful ports and are logged in `.brain/LEDGER.md` as L-060 through L-064. Do
not repeat any of them.

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
7. **It put bordered cards inside a `ScrollingFrame` and lost 1px of every
   border** (L-060). `UITheme.overlay()` returns a `ScrollingFrame` body, and a
   `ScrollingFrame` forces `ClipsDescendants = true` at engine level — it cannot
   be turned off. A `UIStroke` with `ApplyStrokeMode.Border` centres on the edge,
   so its outer half falls outside the frame and is clipped away. Three attempts
   at padding and rescaling failed before the cause was found. For a modal that
   does not actually need to scroll, host the cards in a plain `Frame` with
   `ClipsDescendants = false` and explicit margins instead.
8. **It hit the Luau compiler's 200-register limit** (L-061). Building a dense
   overlay inline inside `V7MenuPanel.new()` raised `Out of local registers:
   exceeded limit 200` — that limit counts locals, temporaries and upvalues per
   function frame, and eight modal builders in one function blows past it. Put
   each overlay in its own module-scope helper function.
9. **It froze a modal at `UDim2.new(0, 920, 0, 580)`** and the panel came out
   40–60px shorter than every other overlay (L-062). Real overlays are
   responsive — `UDim2.new(0.86, 0, 0.86, -137.6)` with a `UISizeConstraint`
   capped at 900x1100 — so on a tall screen they grow to 622px+ while the
   hardcoded one stays at 580. Never override `Panel.Size` with pixel constants.
10. **It scaled the D6 off the edge of its own viewport** (L-063). `GetBoundingBox`
    is axis-aligned, so the cube reports its 2.76-stud SIDE even though its own
    diagonal is 4.78 studs, while higher polyhedra report AABBs of ~4.8–5.0
    studs. Dividing by `maxDim` therefore computed `scale / 2.76` for the D6
    against `scale / 4.84` for the D20 — scaling the cube 1.77x too large and
    blowing it out of the frustum. Per-shape scale tables fixed it. If your mock
    renders dice, reuse `SPECIMEN_SCALE_MAP` / `RACK_CARD_SCALE_MAP` rather than
    computing your own.
11. **It stacked a 3D viewport above four telemetry rows and squeezed the
    viewport to 68px**, with percentage labels colliding with their own progress
    bars (L-064). A metric name, a bar and a value do not fit on one row under
    ~200px wide. Split display and stats horizontally, and put each metric's
    label/value on one tier with its bar on the tier below.

The theme running through 1–6: **the visual layer was rebuilt and the wiring
behind it was not re-checked.** The theme running through 7–11: **a value that
was correct in isolation was wrong in the container it landed in.** A panel that
looks right and receives no data is worse than an ugly one, because nothing
announces the failure.

## HARD RULE — YOU MODIFY EXACTLY ONE SOURCE FILE

This is a preview, not an implementation. You may write to exactly one source
path:

    src/Client/UIMockPreview.luau

**That file already exists and is tracked in git** — it currently holds the mock
from the last panel that went through this process. **Overwrite it wholesale**
with your three variants for `<<PANEL>>`. Do not append to it, do not preserve
the previous panel's variants alongside yours, and do not create a second mock
file. The old contents are safe in git history; the operator does not need them
on disk.

**The one sanctioned exception is image output.** You will also save three new
screenshots into `screenshots/` as required by the deliverable. Those are
capture artefacts, not source, and they are the only other paths you may create.
Nothing else — no new modules, no config, no notes files, no edits to anything
that already exists on disk apart from `UIMockPreview.luau` itself.

So the complete, exhaustive list of paths you may write is:

    src/Client/UIMockPreview.luau      (overwrite)
    screenshots/<Panel>_Variant_A.png  (create)
    screenshots/<Panel>_Variant_B.png  (create)
    screenshots/<Panel>_Variant_C.png  (create)

If you find yourself wanting to write a fifth path, that is the signal to STOP
and say so instead.

You may NOT edit, refactor, or "improve" anything else. Specifically off limits:
`src/Client/UITheme.luau`, `src/Client/V7HUD.luau`, `src/Client/V7MenuPanel.luau`,
`src/Client/V7ForgePanel.luau`, `src/Client/ClientBootstrap.client.luau`,
`src/Shared/**`, `src/Server/**`, `tests/**`, `default.project.json`, anything
in `.brain/`, anything in `docs/`.

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

The operator's exact complaint about the original UI: *"it has emojis and
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

The three panels already shipped landed in this territory, and your variants
should look like they belong in the same product. Study them before you start.

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
  breakage was states that only exist at runtime. For each panel, the mock must
  show at minimum: owned / not owned, affordable / unaffordable,
  locked-with-reason, and empty. Put them on different rows of the same variant
  so they can be compared at a glance.
- **Name your elements the same as the live ones** (`Item_<key>`, `Setting_<key>`,
  `OwnedPill`, `BuyButton`, `ToggleButton`). Whoever ports it will grep for those.
- **Say what you are NOT showing.** If a state or element is omitted, list it in
  the deliverable. An honest gap can be planned around; a silent one cannot.

## DO NOT BREAK THE GAME — THE WIRING RULES

You are not touching live code, so you cannot break it directly. But your design
will be ported, and these are the traps that broke it before. Design so the
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
- **Inherit the modal's responsive size.** `UITheme.overlay()` sizes panels at
  `0.86` scale under a `UISizeConstraint`. Design your variants to fill whatever
  that yields, and size internal bands fractionally, so the panel scales as one
  piece. A pixel-locked child inside a scaling parent is defect 9 above.

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
- **Actions line up across a row.** Anchor a card's button to the card's own
  bottom edge, not to the end of the text above it — otherwise a card with more
  copy pushes its button lower than its neighbour's. Measured on the live shop
  before this was fixed: a 30px stagger between adjacent cards.
- **Size a uniform grid for its WORST case.** Every cell shares one height, so
  the tallest content is what must fit. Sizing for the typical item makes the
  longest one render straight through whatever sits below it.
- **Padding is symmetric** unless you state a reason. `PaddingLeft = 0` beside
  `PaddingRight = 16` is invisible in code and unmistakable on screen; it is
  exactly what "everything is shifted left" looks like.
- **Apply an inset in ONE place.** A body offset 14px that also carries 16px of
  padding insets by 30, and neither declaration says so.
- **Never mix scale and offset in one space budget.** Cells of
  `0.485 scale - 8px` with a `0.03 scale` gutter do not sum to the row. Express
  the whole budget in one system so it totals exactly at any width.

## TECHNICAL CONSTRAINTS

- `--!strict` at the top.
- **Roblox Script Analysis currently reports 158 warnings across roughly 20
  files.** That is a known, recorded debt being worked separately — it is NOT
  your licence to add more. Your file must contribute **zero new errors and zero
  new warnings**. Count the warnings before you start and after you finish, and
  report both numbers. If the count went up, every one of the new warnings will
  be inside `UIMockPreview.luau`, and you fix them THERE before reporting done.
  Do not attempt to fix the pre-existing 158. They are out of your scope, and
  they are being worked separately. Some of them sit in files not named on the
  off-limits list — that is NOT an invitation. The four-path list above is
  exhaustive and overrides any reasoning of the form "this file was not
  forbidden, so I may edit it."
- A type annotation on a table-field assignment is a SYNTAX error in Luau
  (`Module.Foo: number = 1`). Annotate locals only.
- Keep each variant's builder in its own module-scope function. A single
  function that builds all three will exceed Luau's 200-register limit — that is
  defect 8 above, and it is a hard compiler error, not a warning.
- Verify every `Enum` symbol you use exists. An invalid one fails module load
  silently.
- No `require` cycles. Do not require any `src/Server/**` module.
- Build the whole preview without needing a server: no remotes, no profile
  reads, no `NetClient`.
- **A `UIListLayout` owns every child of its frame and overrides `Position`.**
  Pinning one child to an edge does nothing but change its sort order. To mix
  flowing rows with a pinned element, put the flowing rows in their own
  container so the layout governs only them.
- **`TextFits` is not a containment check.** It reports TRUNCATION, and it is
  permanently true once `AutomaticSize` is set — the label can always grow, so
  it never truncates while its text spills over the control beneath it. If you
  verify layout, test element RECTANGLES against their container and against
  the siblings they must not overlap.
- **`ScrollingFrame` clips unconditionally.** If your variant puts stroked cards
  near the edge of the overlay body, they will lose a pixel of border and no
  amount of padding will bring it back. Use a plain `Frame` with
  `ClipsDescendants = false` for non-scrolling content — defect 7 above.

## HOW TO SHOW IT TO ME

`UIMockPreview.luau` must be runnable from the Studio command bar in one line,
and tell me that line. Something like:

    require(game.StarterPlayer.StarterPlayerScripts.Client.UIMockPreview).show()

## DELIVERABLE

1. The overwritten `src/Client/UIMockPreview.luau`.
2. The one-line command to display it.
3. A screenshot of each of the three variants, saved into `screenshots/` as
   `<Panel>_Variant_A.png` / `_B` / `_C`.
4. Two or three sentences per variant on what design idea it is testing and
   what you think its weakness is.
5. **The Script Analysis warning count before and after your change**, stated as
   two numbers. If the after-count exceeds the before-count, the new warnings are
   in your file and you fix them there before reporting done.
6. **A PORTING NOTE for the variant you think is strongest**, covering:
   - every existing element it REPLACES rather than restyles, and for each, the
     helper functions that drive it today (`setEnabled`, `setButtonText`,
     `setPill`, `toggle`) which would need a replacement;
   - every state it shows and every state it does NOT;
   - any figure it displays and which catalog that figure comes from.
   This is what stops the port from looking right and doing nothing.
7. **Confirmation of exactly what you modified**, as the literal output of
   `git status --porcelain`. It should list `src/Client/UIMockPreview.luau` as
   modified plus your three new screenshots, and nothing else. If it lists
   anything else, say so at the top of your report rather than leaving it to be
   discovered.

Report what you actually built and verified. If something did not work, say so
plainly rather than describing the intent as though it succeeded. A report that
describes intent as outcome is the single most expensive thing you can hand
back, because it moves the cost of finding the failure to someone who does not
know where to look.
