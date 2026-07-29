# .brain/skills/web.md - MODERN WEB DEVELOPMENT & SPA BEST PRACTICES

*COGNITIVE DIRECTIVE: This is a living evolutionary document. If you encounter a more optimized methodology, a newer API standard, or a superior architectural pattern during development, you are strictly mandated to activate the Cognitive Evolutionist persona during Gate 6 and rewrite these rules to permanently upgrade this skill.*

*(Forged by Skill Genesis in the bigdreamtour/Prachi child 2026-07-16; field-hardened and harvested to master 2026-07-17 with lessons L-004/L-006/L-008 from that project baked in.)*

When this skill is activated at Gate 0, you must treat published-bundle security, real-browser verification, and lean client architecture as hard requirements.

SCOPE LAW: apply only the sections matching the project's declared stack. React rules bind React projects; Tailwind rules bind Tailwind projects; the static-export security rule (Section 3) binds ANY client-bundled site (Vite/Next-static/Astro/CRA). A project takes only what its plan and manifest actually use.

## 1. Component Architecture (React / modern SPA)
- Prefer localized state (`useState`, `useReducer`); use context conservatively; avoid heavy global-state libraries unless structurally mandated. With React 19, manual memoization (`useMemo`/`useCallback`) is often unnecessary — keep components pure and let the compiler optimize, memoizing only for referential stability third-party libs require.
- Custom hooks encapsulate complex logic; Strict Mode active; framework ESLint rules strictly followed.
- **`useEffect` cleanup hazard (L-006):** never use a concise arrow body for `useEffect` unless you intend the return value as a cleanup function — `useEffect(() => setX(y), deps)` returns a non-function that React tries to call at unmount (`TypeError: destroy is not a function`), blanking the app under StrictMode. Always a block body.

## 2. Styling & Tailwind v4
- Utility-first for layout/typography/spacing; mobile-first breakpoints applied consistently.
- **Tailwind v4 has no `tailwind.config.js` by default (L-008):** do not read or create one. Use `@import "tailwindcss";` in the CSS entry, and declare theme extensions/keyframes/fonts in an `@theme` block via CSS custom properties. Centralize custom values in a theme file where it aids reuse.

## 3. Data Flow & Security (the published-bundle rule)
- **`VITE_`/client env vars are PUBLIC (L-004):** every `VITE_`-prefixed (or equivalent client-inlined) variable is compiled into the shipped bundle and visible to every visitor. Only public-by-design values (a form-relay site key, a Turnstile site key) may carry it. A PRIVATE key (Google Places, CRM, anything billed) must be fetched at BUILD time on a trusted machine — key in CI secrets, never client-prefixed — and committed as static JSON. A leaked client key is unrevocable-in-place and bills the operator until quota dies.
- Ship `.env`, `.env.*`, `!.env.example` in `.gitignore` at project setup, before the first key exists. A code comment is NOT a control; the ignore rule and the build-time fetch are.
- Forms: semantic HTML, robust client validation before transmission, HTTPS-only submission of PII (guard and refuse insecure POST), bot protection (e.g., Turnstile) on public endpoints, and a graceful fallback when the endpoint is missing/insecure.
- **Data-source shadowing:** before writing extracted or generated app data to a file, grep the codebase for where the UI actually READS its data (e.g., `src/data/`). Writing to a new disconnected file compiles clean and silently keeps rendering the old data — a green build masking an unwired change. Append/replace into the active source. (harvested from bigdreamtour L-014)

## 4. Build, Deployment & Verification
- Vite: prefer `@vitejs/plugin-react-swc`; avoid barrel files (large re-export indexes) that slow startup; keep the bundle lean (no unneeded deps; import images/fonts as URLs).
- Static export produces an SPA bundle; client-side routing needs server rewrites to `index.html` (e.g., `.htaccess` for Apache). Any deploy-coupled config (CSP origins, rewrite rules) must be generated from the same env source the app uses, never hardcoded to one environment.
- **Runtime smoke MUST be a real browser (L-006):** an SSR/`renderToString` pass does NOT execute effects, event listeners, or browser-only APIs — an entire defect class is invisible to it. Drive a real browser for the Gate 2 smoke (e.g., `puppeteer-core` against an installed Chrome/Brave, asserting the root has rendered content and zero page errors per route). If a served page mismatches the code, check for a stale dev server holding the port before debugging the code.

## 5. Frontend Interaction & Animation Patterns (harvested 2026-07-18 from bigdreamtour)
- **Scroll-spy detection:** anchor an `IntersectionObserver` to a viewport-CENTER band (`rootMargin: '-40% 0px -40% 0px'`), never to the top/padding offset — top-anchored bands hit subpixel race conditions where the exiting section overwrites the active one. Whichever section holds the visual center wins.
- **Framer Motion `layout` prop:** it injects an inline pixel `height`, overriding CSS `top/bottom` stretch — a background that must bleed past its bounds needs an explicit pixel height to interpolate, not CSS extension. And never wrap `<AnimatePresence>` in a flex container whose entering/exiting children carry their own full-width flex; use a plain relative wrapper, or crossfades crush.
- **Autonomous browser QA capture:** for `deep_qa` Phase 1 on a web app, a `puppeteer-core` script against an installed Chrome/Brave navigates every route and dumps the DOM/layout tree to JSON — a repeatable `qa_runs/` artifact generator feeding the Phase 2 cognitive review.
