---
name: daily-cadence-design
description: Use this skill to generate well-branded interfaces and assets for Daily Cadence, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for prototyping.
user-invocable: true
---

Read the README.md file within this skill, and explore the other available files.

Key files:
- `README.md` — brand voice, visual foundations, iconography, full token reference
- `colors_and_type.css` — all color, type, spacing, radius, shadow, motion tokens (light + dark)
- `theme-toggle.js` — shared light/dark/system toggle; auto-mounts a floating pill
- `ui_kits/mobile/` — iPhone-shell UI kit (timeline, note editor, chart, calendar, dashboard)
- `ui_kits/web/` — desktop UI kit (sidebar dashboard + analytics)
- `preview/` — per-token/component preview cards
- `assets/` — logo, logomark

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts or production code, depending on the need.

## Quick reference
- **Background:** `#F5F3F0` (cream) in light, `#1A1714` (warm near-black) in dark. Cards sit on top — white in light, `#221E1A` in dark.
- **Primary accent:** `#5A7B6D` sage in light; lifted to `#7FA594` in dark. Only for primary actions and active states.
- **Semantic note types** (natural pigments): workout = **clay** `#B05B3B`, meal = **turmeric** `#C9893A`, sleep = **dusk** `#3E4A64`, mood = **plum** `#8B6B85`, activity = **moss** `#7B8B52`. Each has a `-soft` tint companion and a lifted dark-mode variant.
- **Fonts:** Playfair Display (headings, warm moments) + Inter (everything else). Both loaded from Google Fonts via `colors_and_type.css`.
- **Radii:** 6 / 10 / 14 / pill. Default is 10.
- **Icons:** custom line set in `preview/icons.html` — inline SVG, 24px viewBox, 1.75 stroke, round caps/joins, `currentColor` for UI chrome and pigment colors for semantic note-types.
- **Voice:** warm, simple, non-judgmental. Sentence case. No emoji in UI chrome.

## Dark mode
- Always write UI against **role tokens** (`--bg-1`, `--bg-2`, `--fg-1`, `--fg-2`, `--fg-on-accent`, `--border-1`, `--border-2`, `--shadow-1..3`). They remap automatically under `:root[data-theme="dark"]`.
- Don't hardcode cream/ink/white hex values inside component CSS. If you need a one-off surface, define a local var with a light default (`background: var(--my-surface, #EFEBE5);`) and override it inside `:root[data-theme="dark"] .your-component { --my-surface: …; }`.
- Include `theme-toggle.js` from any new artifact that wants the toggle pill, or set `<html data-theme="dark|light">` manually.
