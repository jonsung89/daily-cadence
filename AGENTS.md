# DailyCadence — Codex context

This file is auto-loaded at the start of every session. Read it, then follow the session-start protocol below.

## What this is

DailyCadence is a SwiftUI iOS day-logger app inspired by Google Keep with built-in progress tracking. Solo developer (Jon), Phase 1 MVP for Jon + his wife via TestFlight.

## Stack (see `docs/ARCHITECTURE.md` for detail)

- **iOS:** SwiftUI, iOS 26+, SwiftData for local cache, Swift Charts, `@Observable`, `NavigationStack`. iOS 26 floor unlocks the native `TextEditor(text: $attributedString, selection: $selection)` + `AttributedString.transformAttributes(in:)` APIs used by the rich-text note body (Phase E.2).
- **Backend:** Supabase direct from iOS — **no Express/Node middle-tier in Phase 1**. Future server work (when needed): Next.js on Vercel.
- **Auth:** Sign in with Apple (`AuthenticationServices`) + Google (via Supabase OAuth). Email auth is disabled.
- **Testing:** Swift Testing (`@Test`, `#expect`) for unit tests; XCTest for UI tests. Run unit tests only via `-only-testing:DailyCadenceTests` (UI tests are slow).

## Key paths

- iOS app: `apps/ios/DailyCadence/DailyCadence.xcodeproj`
- Design system (visual source of truth, v2 with dark mode): `design/Codex-design-system/`
  - Tokens: `colors_and_type.css` — light + dark values, type scale, spacing, radius, shadow, motion
  - Mobile UI kit CSS: `ui_kits/mobile/mobile.css`
  - Voice + visual foundations: `README.md`
- Architecture + progress: `docs/ARCHITECTURE.md`, `docs/PROGRESS.md`
- **Feature spec (cross-platform parity reference)**: `docs/FEATURES.md` — must stay in sync with any user-visible change. PROGRESS = changelog narrative; FEATURES = current-behavior spec. Both update together.
- Supabase project ref: `zmlxnujheofgtrkrogdq` (secrets in Jon's 1Password, never in chat)
- Wireframe + product specs live in Jon's Downloads folder (see memory `project_paths.md`)

## Conventions (enforced)

1. **Brand is `DailyCadence`** — one word, always, in UI/docs/labels/copy. The design system README's two-word prose ("Daily Cadence") is historical — don't mirror it in our code or docs.
2. **Verify, never guess** — schema, column names, API endpoints, PS font names. `Grep`/`Read` the source before referencing. Write unit tests for non-trivial logic.
3. **Design System zip is visual source of truth** — for any UI/UX token (color, type, spacing, shadow, radius, motion, voice). The wireframe fills gaps the design system doesn't cover (specific screen layouts).
4. **Keep docs current** — `README.md`, `docs/ARCHITECTURE.md`, `docs/PROGRESS.md`, and **`docs/FEATURES.md`** stay in sync with the code. Update in the same change as stack/structure shifts. FEATURES.md specifically is the cross-platform parity reference — touch it any time user-visible behavior changes.
5. **No Firebase.** Explicitly rejected.
6. **Memory is active context** — entries in `~/.Codex/projects/-Users-jonsung-Desktop-project-daily-cadence/memory/` capture Jon's preferences and project decisions. Re-read relevant ones before acting on topics they cover.
7. **Only commit when asked.** Progress tracking lives in `docs/PROGRESS.md`, not in git log.

## Session-start protocol

When Jon says "resume", "pick up where we left off", or similar:

1. Read `docs/PROGRESS.md` — the current state
2. Run `git log --oneline -10` and `git status` — recent movement
3. Summarize in **≤150 words**: what shipped last, what's in flight, what's next
4. Propose the next concrete step
5. **Wait for Jon to confirm or redirect** before writing code

## End-of-session protocol

Before wrapping any session — or when work hits a natural stopping point:

1. Update `docs/PROGRESS.md` — move completed items to ✅ Shipped, update 🚧 In flight, adjust 🧭 Next if priorities shifted, bump the "Last updated" date
2. Update memory (`MEMORY.md` + individual files) if any new preference, decision, or fact emerged
3. Final user-facing message summarizes in 2-3 bullets

## Jon's working style

- Last used Xcode ~8 years ago — walk him through UI steps (menus, panes, signing) when relevant
- New-ish to modern Swift — briefly explain new idioms (`@Observable`, SwiftData, variable fonts) the first time they come up; prefer modern patterns over legacy
- Wants **scalable, easy to use, cheap** — in that order
- Responds well to **clear proposals with tradeoffs**, not decided plans — present options, recommend one, wait for green light before large changes
- Expects specs read cover-to-cover before coding; flag spec conflicts back to him
