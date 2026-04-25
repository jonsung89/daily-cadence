# DailyCadence — Progress

**Last updated:** 2026-04-24 (Phase B.2 — per-type semantic color overrides)
**Current phase:** Phase 1 MVP — iOS app for Jon + wife, TestFlight distribution

This is the living state of the project. Update at the end of every session.

---

## ✅ Shipped

### Foundation
- Xcode project created at `apps/ios/DailyCadence/` — iOS 17.6+, SwiftUI, Swift Testing framework, synchronized groups (files on disk auto-appear in Xcode)
- Supabase project provisioned: ref `zmlxnujheofgtrkrogdq`, email auth disabled (Apple + Google only), secrets stored in 1Password
- Design system v2 with dark mode committed at `design/claude-design-system/` (replaces stale v1 from Downloads)
- Root `.gitignore` extended with project-specific entries (`.DS_Store`, `*.xcconfig.local`, DerivedData, etc.)
- Stale Firebase references purged from `README.md` and `docs/ARCHITECTURE.md`

### Design system primitives (`apps/ios/DailyCadence/DailyCadence/DesignSystem/`)

**Tokens** (`Tokens/`)
- `Color+Hex.swift` / `UIColor+Hex.swift` — hex literal initializers
- `Colors.swift` — 30 color tokens, **all dark-mode-aware** via dynamic `UIColor { trait in ... }`
- `Spacing.swift` — 8pt grid scale (`s1`–`s9`)
- `Radius.swift` — sm/md/lg/pill
- `Shadow.swift` — 4 levels via `.dsShadow(_:)` modifier, tint + opacity switch by `colorScheme` (warm ink in light, pure black in dark)
- `Font+DS.swift` — typography tokens matching CSS type scale (`display`, `h1`–`h3`, `body`, `small`, `caption`, `label`, `mono`) + `serif()` / `sans()` / `manropeExtraBold()` helpers
- `FontLoader.swift` — idempotent, thread-safe Core Text registration called from `DailyCadenceApp.init` + lazily on first `Font.DS` access (covers Previews too)

**Bundled fonts** (`Resources/Fonts/`)
- Inter variable TTF (4 weights used via `wght` axis) + OFL license
- Playfair Display variable TTF (weights 400–900) + OFL license
- Manrope variable TTF (800 used for logomark) + OFL license

**Brand** (`Brand/`)
- `DailyCadenceLogomark` — sage/paleTaupe tile variants, Manrope 800 opening quote, 0.185em optical nudge, scales any size
- `DailyCadenceWordmark` — `.oneWord` (canonical, locked) / `.twoWord` (historical) layouts, Playfair Display 500
- `DailyCadenceLogo` — combined mark + wordmark
- Corrected `design/claude-design-system/assets/logo.svg` + `logomark.svg` (replaced stale export-bug SVGs that showed sunrise-over-horizon; now match the locked quote-tile design)

### Core UI components (`apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/` + `Models/`)
- `Models/NoteType.swift` — enum (workout/meal/sleep/mood/activity) with title/color/softColor/systemImage accessors
- `SectionLabel` — uppercase small-caps section header
- `TypeBadge` — dot + uppercase type label + optional time (head row of NoteCard)
- `NoteCard` — the white card on the timeline (type head / title / optional message); `message:` parameter name avoids colliding with `View.body`
- `TimelineItem` — time column + rail with dot + generic trailing slot; `LineStyle` enum for first/middle/last/only item rail rendering
- `TypeChip` — note-type picker chip (36pt soft-colored icon circle + label, ink-filled when selected) for the editor
- `FAB` — 56pt sage floating button with sage-tinted shadow
- `TabBar` — custom 5-column bottom nav, translucent cream backdrop with `.ultraThinMaterial` blur, active sage-deep dot indicator

### App shell + Timeline (`Navigation/`, `Features/`)
- `Navigation/RootTab.swift` — 5-tab enum (today / calendar / progress / library / settings) with title + SF Symbol
- `Navigation/RootView.swift` — swaps feature screen by selection, `TabBar` pinned via `safeAreaInset`
- `Features/Timeline/MockNotes.swift` — 9-note sample day driven by a `Content` enum with 4 variants (`text` / `stat` / `list` / `quote`) + `timelineTitle`/`timelineMessage` degradation so both views render from one source
- `Features/Timeline/TimelineViewMode.swift` — enum for Timeline | Cards selection
- `Features/Timeline/TimelineScreen.swift` — serif date header, Timeline|Cards segmented toggle, timeline rail OR Keep grid based on view mode, FAB overlay
- `Features/Placeholders/PlaceholderScreen.swift` — shared "coming soon" layout
- `Features/{Calendar,Dashboard,Library,Settings}/*.swift` — placeholders routing through `PlaceholderScreen`
- `ContentView.swift` deleted; `DailyCadenceApp` now launches `RootView`
- **App is end-to-end navigable:** launch → 5-tab shell → Today tab with Timeline|Cards toggle → tap other tabs for placeholders

### Today-view components
- `DesignSystem/Components/Segmented.swift` — reusable pill segmented control (taupe track, bg-2 active fill, warm-ink shadow on active, 14pt icons)
- `DesignSystem/Components/KeepCard.swift` — Google Keep-style card with 4 kind variants (text / stat / list / quote); background at soft-color @ 0.333 opacity, border at pigment @ 0.2 opacity
- `DesignSystem/Components/KeepGrid.swift` — 2-column alternating masonry layout (even→left, odd→right)

### Customization foundation — Phase A (added this round)

**Dynamic JSON-backed registries.** Palettes, primary themes, and fonts all live in `Resources/*.json` so a future admin panel / remote config (Phase F) can edit them without an App Store release.

- `Models/HexParser.swift` — String ↔ UInt32 hex utility (handles `#` prefix, rejects invalid input)
- `Models/Swatch.swift` / `ColorPalette.swift` — note-background palette model (Decodable)
- `Models/PrimarySwatch.swift` / `ColorPair.swift` — primary-color trio (primary / deep / soft × light/dark)
- `Models/NoteFontDefinition.swift` — font model with three sources (bundled / iosBuiltIn / system), resolves to `Font`
- `Services/PaletteRepository.swift` — loads 4 per-note-bg palettes × 6 swatches (neutral / pastel / bold / bright)
- `Services/PrimaryPaletteRepository.swift` — loads 8 primary themes (sage / blush / coral / mulberry / taupe / lavender / storm / teal); sage is the default
- `Services/FontRepository.swift` — loads 7 fonts (Inter, Playfair Display, New York, SF Rounded, Baskerville, American Typewriter, Noteworthy)
- `Services/ThemeStore.swift` — `@Observable`, persists primary selection to `UserDefaults`, gracefully recovers from stale ids
- `Resources/palettes.json`, `primary-palettes.json`, `fonts.json` — seed data

**The Color.DS.sage refactor.** `sage` / `sageDeep` / `sageSoft` are now computed (not stored) — they resolve from `ThemeStore.shared.primary.primary|deep|soft`. SwiftUI's Observation framework tracks reads of `ThemeStore.shared.primary` inside view bodies, so any theme change triggers re-render. `RootView` sets `.tint(Color.DS.sage)` so all buttons/links pick up the user's primary color automatically.

**Runtime swapping works today** — see `Features/Debug/DesignGalleryView.swift`. Open its SwiftUI Preview, tap a primary trio, and the whole gallery (plus any view reading `Color.DS.sage`) recolors live.

### Phase B (light) — Settings primary color picker

- `Features/Settings/SettingsScreen.swift` — real Settings tab with **Appearance** + **About** sections (version + build from `Info.plist`). No placeholder stubs.
- `Features/Settings/PrimaryColorPickerScreen.swift` — pushed from Settings → Appearance → Primary color. Lists all 8 primary themes; tap selects, persists via `ThemeStore`, live-updates every view reading `Color.DS.sage`. Doesn't pop on select — iOS convention is to let user try several before navigating back.
- `PrimaryTrioDots` — reusable trio preview component used by both the Settings row and the picker detail.
- **End-to-end flow works:** launch → Settings tab → tap Primary color → tap a theme → back out → FAB + active-tab indicator + any sage-accented control now reflects the choice.

### Phase C — Note Editor v1 (added this round)

The FAB now does something — tap it to actually create notes.

- `Services/TimelineStore.swift` — `@Observable` singleton holding the day's notes. Seeded with `MockNotes.today` on launch. Supports `add(_:)`. Replaces the old `@State var notes` in `TimelineScreen` so newly-created notes survive view re-creation and propagate via Observation.
- `Features/NoteEditor/NoteEditorScreen.swift` — the create sheet:
  - Horizontal `TypeChip` row at top (5 default types, defaults to `.mood` for max generality)
  - Title field (autofocused via `@FocusState`, serif 22pt)
  - Optional message (multi-line, `axis: .vertical`, lineLimit 3...12)
  - Cancel / Save in toolbar; Save disabled when title is empty
  - `presentationDragIndicator(.visible)` for the standard sheet handle
  - On save: stamps current wall-clock time, builds a `.text` content variant, calls `TimelineStore.shared.add(_:)`, dismisses
- `TimelineScreen` refactor: now reads `TimelineStore.shared.notes` (read inside `body` so SwiftUI tracks the dependency) and presents the editor sheet via `.sheet(isPresented:)`.

**End-to-end flow works:** launch → Today tab → tap FAB → editor sheet slides up with title autofocused → pick a type → type a title (and optionally a message) → tap **Save** → sheet dismisses, new note appears at the bottom of the timeline with the correct type color and the current time. Persists for the session; resets on relaunch (Supabase persistence is Phase 1's later rounds).

### Phase D.1 — Per-note solid-color backgrounds (added this round)

Notes can now carry a custom background swatch, picked from any of the 4 palettes (Neutral / Pastel / Bold / Bright × 6 swatches each).

- `MockNote.Background` enum (`.color(swatchId: String)`) + optional field on `MockNote`. ID-based — graceful fallback when the palette JSON drops a swatch (returns `nil`, note keeps its data, card renders with type default).
- `MockNote.backgroundSwatch` computed property resolves through `PaletteRepository`.
- `NoteCard` and `KeepCard` apply the user's swatch at the same 0.333 opacity used by the type-tinted defaults; type-color border is preserved on `KeepCard` so the data legend reads even with a custom fill.
- `Features/NoteEditor/BackgroundPickerView.swift` — sheet presented from the editor's "Background" row. None option (with diagonal-slash convention), `Segmented` palette tabs, adaptive swatch grid, checkmark on active selection.
- `NoteEditorScreen` updated: new "Background" row at the bottom of the form, paintpalette icon + current selection name + swatch dot. Tapping presents `BackgroundPickerView`; selection updates editor preview tint live (mirrors how the saved note will render).
- Demo notes in `MockNotes.today`: 10:05 AM Mood gets `pastel.mint`, 6:20 PM Mood quote gets `bold.cobalt` — verifies rendering works without needing to use the editor.

### Repository thread-safety fix (real bug, not just stale DerivedData)

The "Crash: DailyCadence at <external symbol>" we hit twice was actually a **Swift `lazy var` race condition** under parallel Swift Testing. The three repositories (`PaletteRepository`, `PrimaryPaletteRepository`, `FontRepository`) used `private lazy var cached: [...] = loadSeed()`. Swift's `lazy var` is documented as **not thread-safe**; under parallel test execution multiple test threads triggered the lazy initializer concurrently, racing the iterator destroy and crashing the host app.

**Fix:** all three repositories now load eagerly in `init` via a `static func loadSeed(bundle:)`. `cached` is `let`, not `lazy var`. JSON decode is <5ms; the cost is negligible vs. the crash risk.

If you ever see "Crash: DailyCadence at outlined destroy of IndexingIterator<...>" again, look for new `lazy var` usage in shared/observable types and convert to eager init.

### Phase D.2.1 — Per-note image backgrounds (added this round)

PhotosPicker integration plus an opacity slider. Notes can now carry a photo background that renders behind the text.

- `MockNote.Background` extended with `.image(ImageBackground)` case alongside `.color(swatchId:)`
- `MockNote.ImageBackground` — struct holding `imageData: Data` + clamped `opacity: Double`. Stored inline (in-memory MVP); Phase F+ swaps to Supabase Storage URL without changing the case shape
- `DesignSystem/Components/NoteBackgroundStyle.swift` — UI-layer enum (`.none / .color / .image`) decoupling the design system from the model. `note.resolvedBackgroundStyle` is what cards consume.
- `NoteCard` + `KeepCard` refactored to take `NoteBackgroundStyle`. Images render `.scaledToFill()` at user opacity, clipped to the card's corner radius. Default surface (`bg-2`) sits underneath so reduced-opacity reads correctly.
- `BackgroundPickerView` rebuilt with three sections: **None**, **Photo** (`PhotosPicker` + opacity slider when set), **Color** (existing palette tabs). Mutually exclusive — picking a swatch clears the photo and vice versa.
- `NoteEditorScreen` preview updated to render image backgrounds live; "Background" row now shows a circular thumbnail when an image is selected.

**End-to-end flow works:** Today tab → tap **+** → tap Background → tap "Choose a photo" → pick from your library → opacity slider appears → drag to taste → Done → editor preview tints with the photo at chosen opacity → Save → note appears in timeline with the photo behind the text.

**Deferred to D.2.2:**
- Interactive pan/zoom crop UI (currently auto scale-to-fill the card)
- Image downscaling on import (currently stores full-res library asset; fine for MVP, will matter when notes are persisted)

### Phase E.1 — Per-field font + color customization (added this round)

Each note can now style its title and message independently — different fonts and colors for the two text elements within a single card.

- `Models/TextStyle.swift` — model holding optional `fontId` (looks up in `FontRepository`) + optional `colorId` (looks up across all 4 palettes in `PaletteRepository`). Empty styles auto-collapse to `nil` so they don't leak into persistence.
- `MockNote.titleStyle` + `messageStyle` — per-field overrides. `nil` falls back to the card's default (Inter 16/14 with ink/fg2 colors).
- `NoteCard` + `KeepCard` resolve TextStyle through helpers on `Optional<TextStyle>` so call sites stay clean (`titleStyle.resolvedFont(...)` works whether or not the note has a style).
- `Features/NoteEditor/StylePickerView.swift` — sheet pushed from the editor's "Style" row. Two sections (**Title** / **Message**), each with a live-preview row + Font picker + Color picker. Detail screens (`FontPickerScreen`, `TextColorPickerScreen`) push from each row, list options grouped by palette/source, render samples in the actual font/color.
- `NoteEditorScreen` — new "Style" row above Background; fields render in the chosen font/color live as the user edits; saves include the styles.
- Demo: 10:05 AM Mood note in `MockNotes.today` ships with `TextStyle(fontId: "playfair", colorId: "bold.emerald")` so the styling renders without needing to use the editor.

**End-to-end flow:** Today tab → tap **+** → tap **Style** → pick a font/color for Title and/or Message → see preview in the editor → Save → new note appears in timeline with the chosen styling.

**Why no in-line rich-text editing yet (Phase E.2 deferred):** SwiftUI's `TextEditor` doesn't support `AttributedString` editing on iOS 17 — that landed in iOS 18+. To ship selection-based formatting (bold a word, color a phrase) we'd either bump deployment target to iOS 18 or wrap a `UITextView` via `UIViewRepresentable`. Per-field styling covers most use cases and is achievable today on iOS 17.

### Phase B.2 — Per-type semantic color overrides (added this round)

User can now repaint a note type globally — "make my Workout cobalt instead of clay." All workout-related visuals across the app pick up the new color (timeline dots, KeepCard borders, TypeChip icons, type badges).

- `Services/NoteTypeStyleStore.swift` — `@Observable` singleton holding `[NoteType.rawValue: swatchId]` overrides; persists to `UserDefaults`. Stale ids (after a palette JSON update removes a swatch) gracefully fall back to defaults at read time.
- `NoteType.color` refactored to read through the store; new `NoteType.defaultColor` exposed for "show me the default" preview moments.
- `Features/Settings/NoteTypePickerScreen.swift` — Settings detail. Lists all 5 types with current color preview; tap pushes `TextColorPickerScreen` (reused from E.1 with new `title` parameter) to pick from any palette swatch or "Default."
- `Settings → Appearance` now has two rows: **Primary color** (theme) and **Note Types** (per-type overrides). Reset-all action available on the Note Types screen.
- `NoteTypesRow` mini-preview shows five overlapping circles colored by current per-type colors.

**End-to-end flow:** Settings → Appearance → Note Types → tap **Workout** → tap **Bold > Cobalt** → back out → all workout dots, borders, icons across the app are now cobalt. Persists across launches; reset clears every override.

**Caveat:** This phase overrides `NoteType.color` (the full pigment used for dots, icons, borders). `NoteType.softColor` — used as the KeepCard background tint and TypeChip's unselected icon-circle — still falls back to the design-system default. Visual mismatch is minor but visible on KeepCard fill tints; can be addressed in a polish round if needed.

### Tests (76/76 passing — +6 this round)
- `ColorHexTests` (16) — hex initializer, every palette family in light + dark, invariant tokens, role flips
- `FontLoaderTests` (5) — bundled font registration + variable-axis weight
- `PaletteRepositoryTests` (4) — palette order, swatch count, known swatch resolution, hex round-trip
- `PrimaryPaletteRepositoryTests` (4) — eight themes load in order (sage / blush / coral / mulberry / taupe / lavender / storm / teal), default is sage, sage trio matches historical values, unknown id → nil
- `FontRepositoryTests` (4) — fonts load, default is inter, bundled PS names resolve, iOS built-in PS names resolve on simulator
- `HexParserTests` (6) — `#`-prefix handling, unprefixed, rejection, format round-trip
- `ThemeStoreTests` (4) — defaults to sage, persists across instances, unknown id preserved state, stale id → default
- `TimelineStoreTests` (5) — initial seed match, empty start, append order, content variant round-trip, default seed matches `MockNotes.today`
- `MockNoteBackgroundTests` (11) — nil/valid/stale swatch resolution, sample swatch from each of the 4 palettes, color round-trip through `TimelineStore`, image round-trip through store, opacity clamping (0...1), resolved style for color/image/stale id/nil
- `TextStyleTests` (10) — empty detection, MockNote auto-collapses empty styles, valid/unknown font + color id resolution, nil/empty optional fallback to default color, partial style preservation, store round-trip
- **`NoteTypeStyleStoreTests` (6)** — empty default state, persistence across instances, nil/empty-string clears override, stale id resolves to nil at read time, reset-all clears every override

### Tests (21/21 passing)
- `ColorHexTests` (16) — hex initializer, every palette family in light + dark, invariant tokens, role flips
- `FontLoaderTests` (5) — registration succeeds, every bundled font resolves by its PS name, Inter variable font accepts weight axis
- Components + screens are verified via SwiftUI Previews (layout/presentation, not unit-tested)

### Docs + session infrastructure
- `README.md` + `docs/ARCHITECTURE.md` reflect current Supabase stack
- `CLAUDE.md` (repo root) + `docs/PROGRESS.md` (this file) enable cross-session handoffs
- Memory populated: user profile, stack, paths, Supabase coordinates, design/brand decisions, testing/docs/verification feedback

---

## 🚧 In flight

Nothing active — Phase B.2 (per-type semantic color overrides) landed.

---

## 🧭 Next (Phase 1 roadmap, rough order)

**Customization phases** (from the earlier design discussion):

- **Phase B.2 polish (optional)** — extend overrides to `NoteType.softColor` so KeepCard fill tints + TypeChip icon circles match the user's chosen color, not just dots/borders/icons. ~½ round if/when the visual mismatch becomes annoying.
- **Phase D.2.2 — Interactive crop UX for image backgrounds.** Pan/zoom inside a fixed-aspect frame; store offset+scale on `ImageBackground`; cards apply the same transform on render. Plus image downscaling on import (1024px max) so memory doesn't balloon when many notes are persisted. *1–2 rounds.*
- **Phase E.2 — Selection-based rich text.** `AttributedString`-backed message body, inline format toolbar (font + color) triggered by text selection. Requires either bumping deployment target to iOS 18+ (which has native AttributedString TextEditor support) OR wrapping `UITextView` in `UIViewRepresentable`. *2–3 rounds.*
- **Phase F — Remote config pipeline.** Host `palettes.json` / `primary-palettes.json` / `fonts.json` on Supabase Storage, client fetches + caches + falls back to bundle. Enables admin panel editing without App Store release. *1 round.*

**Other roadmap items:**

- **Drag-to-reorder on the Keep grid** — matches `.keep.drag` CSS; long-press to enter reorder mode
- **Inject mock data via view model** — replace hardcoded `MockNotes.today` with an `@Observable` `TimelineViewModel`
- **Apple Developer enrollment** — $99/yr, blocker for TestFlight + Sign in with Apple Services ID
5. **Supabase schema** — first SQL migration: `notes` table (with a `content_kind` column matching the four variants) + RLS policy (`user_id = auth.uid()`)
6. **Supabase Swift SDK** — add via Swift Package Manager, build auth client
7. **Auth providers** — configure Apple + Google in Supabase dashboard once bundle ID is registered with Apple
8. **Wire notes CRUD** to Timeline + Editor (swap mock data for real)
9. **Exercise tracking** (`exercises`, `workout_logs` tables) + Swift Charts progression view
10. **Calendar view** (wireframe Screen 6) — replace `CalendarScreen` placeholder
11. **Dashboard widgets** (wireframe Screen 7) — replace `DashboardScreen` placeholder
12. **Settings screen** — replace `SettingsScreen` placeholder (wireframe Screen 9)
13. **TestFlight submission**

## 🧊 Parked / Deferred

- **Express / Next.js backend** — not needed for Phase 1; Supabase direct covers CRUD
- **Android port** — Phase 2+
- **Web dashboard** — Phase 3+
- **Onboarding / empty states / settings screens** — after core flow works
- **Photo attachments + Supabase Storage** — after notes CRUD lands
- **Migrating to Supabase Pro org** — only if free tier limits are hit

---

## Session reference

- Default simulator: **iPhone 17 Pro** (Xcode 26.3 installed at `/Applications/Xcode.app/`)
- Build + test command:
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -scheme DailyCadence \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -only-testing:DailyCadenceTests \
    -project apps/ios/DailyCadence/DailyCadence.xcodeproj \
    test
  ```
- Build only (no tests): swap `test` for `build`
