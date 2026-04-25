# Daily Cadence — Design System

> A day logger inspired by Google Keep. Users log workouts, meals, sleep, mood, and activities on a clean timeline. Notes organize by time automatically; progress appears as charts. Design aesthetic: warm, earthy, minimal — inspired by Anthropic Academy.

## About this system

This design system was built from the written product brief. **No codebase, Figma file, or existing screenshots were provided** — every component, screen, and visual decision here is a first interpretation of the brief. Please review for brand-fit and iterate with real screens/assets when available.

**Inspiration sources** (cited in brief, not directly referenced):
- Anthropic Academy — warm earthy aesthetic
- Google Keep — simple freeform note-taking

**Font substitutions:** Playfair Display and Inter are loaded from Google Fonts. If the brand has licensed alternatives (e.g. a custom serif), swap them in `colors_and_type.css`.

---

## Index

| File / Folder | Purpose |
|---|---|
| `README.md` | This file — brand overview, content + visual rules, iconography |
| `SKILL.md` | Agent-skill manifest; lets Claude Code / other agents use this system |
| `colors_and_type.css` | All color, type, spacing, radius, shadow, motion tokens |
| `preview/` | Individual HTML cards that render in the Design System tab |
| `ui_kits/mobile/` | Mobile app UI kit — timeline, note editor, chart, calendar, dashboard |
| `ui_kits/web/` | Web app UI kit — sidebar dashboard + analytics |
| `assets/` | Logos, illustrations, icons |

---

## Product surfaces

1. **Mobile app (iOS / Android)** — the primary product. A minimal, journal-like day logger. Timeline-first, with quick note entry and typed cards (workout, meal, sleep, mood, activity).
2. **Web app** — a richer analytics + planning surface. Sidebar nav, multi-column dashboard, deeper charts. Same visual language; denser layout.

---

## Content Fundamentals

Daily Cadence's voice is **a thoughtful friend, not a coach.** Copy should feel like a warm journal prompt, not a fitness tracker.

### Tone
- **Simple, not corporate.** "Log a meal," not "Record nutrition data."
- **Human, not robotic.** "You slept 7h 20m last night — nice" rather than "Sleep duration: 7.33 hours."
- **Empowering + celebratory.** When the user hits something worth noticing, say so gently. Never gamified ("+50 XP!").
- **Flexible, non-judgmental.** Never imply a missed day is a failure. No streaks-gone-cold language.

### Voice rules
- Address the user as **you**. Refer to the app as **Daily Cadence** or implicitly; avoid "we" unless it's a real team statement.
- **Sentence case** for all UI (buttons, headings, labels). Not Title Case. Not ALL CAPS except for `.dc-caption` micro-labels.
- **Contractions are welcome** — "you're", "it's", "let's".
- **Short sentences.** One idea per line. Periods at the end of full sentences in body copy; no periods on single-phrase labels or buttons.
- **No exclamation marks** except in rare celebratory moments (hit a first-of-its-kind milestone).
- **No emoji in UI chrome.** Semantic color + wordmark does the emotional work. Emoji can appear *inside user-generated note content* because users type what they want.

### Examples

| Do | Don't |
|---|---|
| "What did you eat?" | "Log nutrition entry" |
| "Good morning. Anything to note?" | "Welcome back! Start tracking 💪" |
| "You're averaging 7h 12m this week" | "WEEKLY AVG: 7.2 HRS ↑" |
| "Skip for today" | "I'll do it later 😅" |
| "Saved to today" | "Entry successfully created." |

### Copy patterns
- **Empty states** are invitations: "Nothing yet. Tap + to add the first note of your day."
- **Confirmations** are short + past tense: "Saved", "Moved to yesterday", "Deleted".
- **Errors** explain what happened and offer an action: "Couldn't save — check your connection. Try again."

---

## Visual Foundations

### Colors
- Background is **warm cream** (`#F5F3F0`), never pure white. White (`#FFFFFF`) is reserved for *cards layered on cream* to create subtle elevation.
- **Sage green** is the single primary accent. Use it for primary buttons, active nav, selected states, and key data emphasis. Don't use it for decorative chrome.
- **Semantic colors** (workout / meal / sleep / mood / activity) only appear when a note of that type is present. They are not decoration — they're the app's data legend.
- Each semantic color has a **-soft** companion for chip fills and timeline lanes. Full-saturation swatches never fill large areas; they live on small dots, icons, and single-line accents.

### Typography
- **Playfair Display** (serif) for headlines, greetings, and moments of warmth. Use 500–700 weight. Italic works beautifully for quotes or reflective prompts.
- **Inter** for everything else — UI, body, numbers, micro-copy. 400/500/600/700.
- **Display serif is sparing.** One serif moment per screen, typically the screen title or the day's date header. The rest of the screen is Inter.
- **Numbers** (charts, durations, weights) lean on Inter's tabular figures — use `font-variant-numeric: tabular-nums` for stat rows.

### Spacing & layout
- 8pt grid with a 4px half-step. Common gaps: `8 / 12 / 16 / 24 / 32`.
- **Generous whitespace.** Card padding is `20–24px` minimum. Section gaps are `32–48px`.
- **Cards carry most content.** White surface on cream background, 1px `--border-1` border, `--radius-md` (10px), soft `--shadow-1`.
- Mobile screens use a single column with 16px outer padding. Web dashboard uses a 12-col grid with a 240px fixed sidebar.

### Backgrounds & imagery
- Primary backgrounds are **solid warm cream** — no gradients, no patterns. Depth comes from soft shadows, not texture.
- No hand-drawn illustrations or photos in core UI. If imagery is needed (onboarding, empty states), use **soft, warm, low-contrast photography** — morning light, natural textures, no people.
- **No gradients** on backgrounds or cards. Gradients appear *only* in chart fills (a tinted sage area under a line) with low opacity (10–20%).
- **No grain, no noise, no glassmorphism.**

### Corner radii
- `6px` on small chips and inputs.
- **`10px` on cards, buttons, menus** — the system default.
- `14px` on prominent hero cards or bottom sheets.
- `999px` on pills, avatar rings, and floating action buttons.

### Shadows (soft, warm, low)
Shadows are tinted with warm ink (`rgba(44, 38, 32, …)`) not neutral black, so they stay warm against the cream.
- `--shadow-1` — resting cards
- `--shadow-2` — floating elements (popovers, bottom sheets)
- `--shadow-3` — modals
- `--shadow-hover` — lift on hover (desktop)

### Borders
- 1px solid `--border-1` (`#E3DFD9`) is the default card and input border.
- Focus states: 2px sage ring with `outline-offset: 2px`, never blue browser default.
- Dividers inside lists use `--border-1` at 1px, not shadows.

### Motion
- **Smooth, not bouncy.** No spring overshoot. Default easing is `--ease-out` (`cubic-bezier(0.2, 0.8, 0.2, 1)`).
- Durations: `140ms` for hover / press, `220ms` for reveals, `380ms` for page transitions.
- Fades and slide-ins (8–12px travel) are preferred over scale animations.
- No parallax. No auto-playing motion in the UI chrome.

### Hover (desktop)
- Cards lift: `--shadow-1` → `--shadow-hover`, translate Y `-2px`, 140ms.
- Buttons darken: sage → `--dc-sage-deep`.
- Icons/links: subtle background tint fill (sage-soft, 50% opacity).

### Press (mobile + desktop)
- No shrink. Buttons go to a slightly darker color and drop shadow to `--shadow-1` (or none).
- Cards press to a faint cream inset for ~80ms.

### Transparency / blur
- Blur is used **only** on sticky top bars over scrolling content — `backdrop-filter: blur(12px)` with `--bg-1 / 80%`. Never on cards, never as decoration.
- Transparency otherwise limited to **-soft** semantic tints (which are solid, not transparent, for legibility).

### Dark mode

Dark mode is a **warm near-black** family, not neutral black — Daily Cadence stays warm after dusk.

- Activation: `<html data-theme="dark">`. The shared script `theme-toggle.js` (loaded in each UI kit `index.html`) sets this attribute, persists the user's choice in `localStorage('dc-theme')`, and honors `prefers-color-scheme` for the first paint.
- Supports three preferences: **light**, **dark**, **system**. The floating sun/moon/auto pill in the bottom-right is the default UI; pages can opt out with `<script src="theme-toggle.js" data-no-toggle>` and call `window.DCTheme.set(...)` manually.
- All tokens in `colors_and_type.css` have dark-mode counterparts under `:root[data-theme="dark"]`. Role tokens (`--bg-1`, `--fg-1`, `--border-1`, `--shadow-*`) remap automatically; pigments (clay, turmeric, dusk, plum, moss) and sage are *lifted* for legibility on dark backgrounds.
- **Authoring:** write UI with role tokens (`var(--bg-2)`, `var(--fg-1)`, `var(--border-1)`, `var(--shadow-1)`). Never hardcode cream/ink/white in component CSS or it will break in dark mode. For one-off surface tints that don't map to a role, define a local var with a light default and override inside `:root[data-theme="dark"] .your-component { --local-var: …; }` (see `.sidebar` and `.phone` for examples).
- **White text on a pigment chip** in light mode flips to a dark tint on the same (lifted) pigment in dark mode — `--fg-on-accent` handles this automatically.

### Layout rules
- **Fixed mobile header** (56px) and **bottom tab bar** (72px with safe area).
- **Fixed web sidebar** (240px) with scrollable main area.
- The page background (cream) is always visible at the edges; content doesn't go full-bleed except imagery.

---

## Iconography

See the `# Iconography` section below for full details, plus the live examples in `preview/icons.html`.

**Chosen icon system:** a **custom hand-drawn line set** specified directly in `preview/icons.html` as inline SVG. Drawn for Daily Cadence with a consistent rhythm: 24×24 viewBox, 1.75 stroke weight, round caps and joins, generous arc radii. Curves win over right angles — the set leans soft and warm, not technical.

For production, consider extracting these into `assets/icons/` as individual SVGs (one per glyph) so they can be imported directly. Until then, copy the inline SVG you need from `preview/icons.html`.

### Rules
- **Line icons only.** Never filled — it fights the soft, airy feel. (Exception: the tiny dots inside icons like `more`, `calendar`, `tag` are filled intentionally as punctuation.)
- **20–26px** display size. 16px for inline. 24–26px for primary nav + large affordances.
- **`currentColor`** always — icons inherit from their container so semantic type colors carry through. Semantic icons (workout, meal, sleep, mood, activity) are drawn in their pigment color; UI chrome icons (home, search, settings) are `--fg-1`.
- **1.75 stroke weight.** Don't mix weights on one screen.
- **Round caps and joins.** Always. No miter joins.
- **No emoji** in the UI chrome. Users may use emoji *inside their own note content*.
- **No unicode symbols as icons.** Use a real icon.
- **Semantic color dots** (solid filled circles, 8px) are used heavily for note-type legends — these are not icons, they're the data.

### Logo
A simple wordmark in Playfair Display plus a small sage circle (representing a completed "cadence" — a day). See `assets/logo.svg`.

---

## Ask for iteration

- Real screenshots, a Figma file, or a codebase will sharpen everything here.
- Confirm the font choices (Playfair Display is a placeholder for "warm elegant serif" — several alternatives like Fraunces, DM Serif Display, or a licensed custom would work).
- Confirm the custom icon set — it's drawn as a first pass. A production set would extract each glyph into `assets/icons/` and add the full range (arrows, file types, device states, empty-state illustrations).
