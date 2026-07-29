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
