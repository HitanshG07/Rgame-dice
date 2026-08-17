# .brain/skills/ui_ux_design.md - UNIVERSAL UI/UX DESIGN PROTOCOL

*COGNITIVE DIRECTIVE: This is a living evolutionary document. If you encounter a more optimized methodology, a newer API standard, or a superior architectural pattern during development, you are strictly mandated to activate the Cognitive Evolutionist persona during Gate 6 and rewrite these rules to permanently upgrade this skill.*

When this skill is activated at Gate 0, you must enforce deliberate visual hierarchy, complete interface states, accessibility floors, and friction-conscious interaction design on every UI surface built or modified. This skill loads ALONGSIDE the stack skill (cumulative matching): it governs design quality, never implementation technology.

## 1. Visual Hierarchy & Spacing Discipline
- Every screen has ONE visually dominant primary action; secondary actions are visibly subordinate. Competing emphasis is a design defect.
- Spacing, sizing, and corner radii come from one consistent scale (4/8-based, or the project's established design tokens) — no magic numbers invented per screen.
- Typography uses a deliberate scale: at most ~4 sizes and 2 weights per screen; body text never falls below platform-legible minimums.

## 2. The Five Interface States (all mandatory)
- Every data-bearing view ships with all five states designed: IDEAL; EMPTY (first-run guidance, never a blank void); LOADING (skeletons or indicators without layout jumps); ERROR (plain-language message plus a recovery action — never a raw exception); and PARTIAL (some data failed, offline, or degraded).
- State transitions never destroy user input: anything the user typed survives errors, retries, and navigation.

## 3. Accessibility Floors (non-negotiable at every Build Tier)
- Text contrast at least 4.5:1 (3:1 for large text); every interactive element has visible focus and pressed states.
- Touch targets at least 44x44pt / 48x48dp; keyboard and screen-reader traversal follows visual order where the platform supports it.
- Color is never the only signal — pair it with an icon, text, or shape change.

## 4. Responsive & Adaptive Fluidity
- Layouts are built on flexible containers (flex, grid, constraints) — never fixed-pixel canvases. Test both extremes: the smallest supported screen and a tablet/ultra-wide.
- Breakpoints are content-driven, not device-name-driven; user font-size settings must not break layouts.
- Dark mode is a first-class parity variant wherever the platform supports it: same hierarchy, re-verified contrast, zero forgotten hardcoded colors.

## 5. Interaction & Flow Ergonomics
- Destructive actions require confirmation or offer undo — and the dangerous option is never the default nor the easiest to hit accidentally.
- Forms: every field labeled; inline validation at field exit (not only on submit); input preserved on error; OPTIONAL fields marked rather than required ones; platform autofill supported.
- Feedback within ~100ms for every tap or click (visual acknowledgment); progress indication for anything longer than ~1 second.
- Motion is purposeful and brief (150–300ms), respects the platform's reduced-motion preference, and never blocks input.

## 6. Collections: Cards, Rows and Grids
*(Added 2026-08-18 from the Dice Forge shop and settings work. Every rule here was bought with a defect the operator saw before any check did.)*
- **Items of one kind carry the SAME rows in the SAME order.** A card with three text rows beside one with two does not read as "less to say", it reads as broken — the eye finds the hole where the row should be. When content is missing, WRITE IT rather than reflowing the layout to disguise the gap: the defect is absent content, not excess height.
- **Actions align across a row, which means anchoring them to the card, not to the text above.** In a flow layout the button lands wherever the copy ends, so cards with more text push it lower — measured, a 30px stagger between neighbours. Pin the action to the card's edge and let the content area take what remains.
- **Size a uniform grid for its WORST case, not its average.** Every cell shares one height, so the tallest content is what has to fit; sizing for the typical item makes the longest one overflow into whatever sits below.
- **Padding is symmetric unless there is a stated reason.** `PaddingLeft = 0` against `PaddingRight = 16` is invisible in code — the two values are on different lines — and unmistakable on screen. Read insets from one shared scale so sibling panels cannot drift apart.
- **Apply an inset in ONE place.** A container offset by 14px that also carries 16px of padding insets by 30, and nothing in either declaration says so. Pick the padding or the offset, never both.
- **Never mix scale and offset in one space budget.** Cells of `0.485 scale − 8px` with a `0.03 scale` gutter do not sum to the row: express the whole budget in one system (`0.5 − gutter/2` with a pixel gutter) so it totals exactly at any width.
- **Derive per-item width from the COUNT.** A literal tuned for three tabs pushes the fourth off the panel the day someone adds a category.
- **A modal scrim must cover the WHOLE screen, including any platform chrome.** A scrim that stops at its canvas edge leaves a bright, undimmed band that reads as an outline rather than a dimmed page. Strength is lower than instinct suggests — dim enough to recede, light enough that the content behind stays legible, because that content is usually what the panel is about.
- **A control has THREE states, not two: on, off, and unavailable.** The third is not a shade of the other two. It needs its own treatment and a stated reason ("no sounds are installed yet"), or a permanently-inert switch reads as a bug — and a shared `setEnabled` helper written for a different widget will silently paint nothing at all.
