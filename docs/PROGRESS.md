# DailyCadence — Progress

**Last updated:** 2026-04-29 (post-1.0 hotfixes — gallery videos no longer disappear after upload. Two interlocking root causes, both fixed: (1) **video re-encode trips Storage cap**: HEVC 1080p (`AVAssetExportPresetHEVC1920x1080`) at iPhone HDR bitrates produced 53.4 MB on a 21.8 s clip — over Supabase Storage Free tier's 50 MB upload limit. Switched to H.264 720p (`AVAssetExportPreset1280x720`); a full 60 s clip lands ~38 MB worst-case, comfortable headroom under the cap. Codec is reversible in one line when storage tier moves up. Apple doesn't ship a 720p HEVC preset, so the codec swap was the simplest path. (2) **`mergeFetched` + race-guard double-jeopardy**: even after fix #1, `persistAdd`'s post-insert race guard (which soft-deletes the server row when the user deletes a note mid-upload) was firing spuriously. Root cause: `mergeFetched` was already dropping optimistic notes from `notes` when an incidental refetch landed mid-upload (server didn't yet have the row), which then made the race guard's `notes.contains(...)` check misfire. Fix introduces two `Set<UUID>`s in `TimelineStore`: `pendingInsertIds` (populated in `add(_:)`, removed in `persistAdd`'s `defer`; `mergeFetched` skips dropping IDs in this set) and `userDeletedDuringInsertIds` (populated by `delete(noteId:)` only when the deleted ID is still pending; the race guard now consults this set instead of `notes.contains`). Both sets cleared in `resetForUserChange` and the `persistAdd` catch path. Pre-existing TestFlight 1.0 (1) ship notes preserved below. 🎉 **TestFlight 1.0 (1) shipped**. Jon + wife both have the app installed and running. Massive day: Phase F.2 real auth (Apple + Google + onboarding sign-in screen + Sign Out + cache reset on user-change + brand-correct scheme-aware buttons), Phase F.3 account deletion (Edge Function `delete-account` deployed via dashboard editor, JWT-verify toggle OFF, typed-email confirmation flow on dedicated DeleteAccountConfirmationScreen, Danger Zone section in Settings), Phase F.4 onboarding flow (6 pages: Welcome / Profile / Theme & Icon / Note Types / Reminders / Done; journal-pen illustration vocabulary established with sun/plant/squiggle/sparkle/dot/moon/bell motifs in `JournalShapes.swift`; chrome auto-applies corner ambient ornaments + theme-tinted gradient + scrollEdgeEffectStyle soft fade; PhotosPicker → circular crop → upload pipeline for profile photos with `ProfileImageCache` two-layer cache (UIImage + signed URL TTL); `profile-images` Storage bucket with RLS), Settings restructure (Profile row at top → ProfileEditorScreen with avatar + first/last + Save; gear icon on Today now actually navigates to Settings tab via callback closure; reusable `tabBarBottomClearance()` modifier; TabBar hides on keyboard show via NotificationCenter observer in RootView). App Store Connect ready: privacy manifest declares UserDefaults usage (CA92.1), `ITSAppUsesNonExemptEncryption = NO`. Build uploaded via Xcode Organizer, processed cleanly with one non-blocking warning (missing iPad 152×152 alternates — fine for iPhone-only TestFlight, address before App Store or drop iPad target).)
**Current phase:** Phase 1 MVP — iOS app for Jon + wife, TestFlight distribution

This is the living state of the project. Update at the end of every session.

---

## ✅ Shipped

### Foundation
- Xcode project created at `apps/ios/DailyCadence/` — iOS 26.0+ (Phase E.2; raised from 17.6 to use the native `AttributedString` `TextEditor` selection API), SwiftUI, Swift Testing framework, synchronized groups (files on disk auto-appear in Xcode)
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
- `Features/Timeline/TimelineViewMode.swift` — enum for Timeline | Board selection
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

**Deferred to D.2.2:** ✅ landed — see the Phase D.2.2 entry below.

### Phase E.1 — Per-field font + color customization (added this round)

Each note can now style its title and message independently — different fonts and colors for the two text elements within a single card.

- `Models/TextStyle.swift` — model holding optional `fontId` (looks up in `FontRepository`) + optional `colorId` (looks up across all 4 palettes in `PaletteRepository`). Empty styles auto-collapse to `nil` so they don't leak into persistence.
- `MockNote.titleStyle` + `messageStyle` — per-field overrides. `nil` falls back to the card's default (Inter 16/14 with ink/fg2 colors).
- `NoteCard` + `KeepCard` resolve TextStyle through helpers on `Optional<TextStyle>` so call sites stay clean (`titleStyle.resolvedFont(...)` works whether or not the note has a style).
- `Features/NoteEditor/StylePickerView.swift` — sheet pushed from the editor's "Style" row. Two sections (**Title** / **Message**), each with a live-preview row + Font picker + Color picker. Detail screens (`FontPickerScreen`, `TextColorPickerScreen`) push from each row, list options grouped by palette/source, render samples in the actual font/color.
- `NoteEditorScreen` — new "Style" row above Background; fields render in the chosen font/color live as the user edits; saves include the styles.
- Demo: 10:05 AM Mood note in `MockNotes.today` ships with `TextStyle(fontId: "playfair", colorId: "bold.emerald")` so the styling renders without needing to use the editor.

**End-to-end flow:** Today tab → tap **+** → tap **Style** → pick a font/color for Title and/or Message → see preview in the editor → Save → new note appears in timeline with the chosen styling.

**E.1's per-field message styling was superseded by Phase E.2** (rich-text message body via `AttributedString` + iOS 26's `TextEditor(text:selection:)`). The `messageStyle` field was dropped; per-run attributes on the AttributedString replace it. Title styling still uses per-field `TextStyle`.

### Phase B.2 — Per-type semantic color overrides (added this round)

User can now repaint a note type globally — "make my Workout cobalt instead of clay." All workout-related visuals across the app pick up the new color (timeline dots, KeepCard borders, TypeChip icons, type badges).

- `Services/NoteTypeStyleStore.swift` — `@Observable` singleton holding `[NoteType.rawValue: swatchId]` overrides; persists to `UserDefaults`. Stale ids (after a palette JSON update removes a swatch) gracefully fall back to defaults at read time.
- `NoteType.color` refactored to read through the store; new `NoteType.defaultColor` exposed for "show me the default" preview moments.
- `Features/Settings/NoteTypePickerScreen.swift` — Settings detail. Lists all 5 types with current color preview; tap pushes `TextColorPickerScreen` (reused from E.1 with new `title` parameter) to pick from any palette swatch or "Default."
- `Settings → Appearance` now has two rows: **Primary color** (theme) and **Note Types** (per-type overrides). Reset-all action available on the Note Types screen.
- `NoteTypesRow` mini-preview shows five overlapping circles colored by current per-type colors.

**End-to-end flow:** Settings → Appearance → Note Types → tap **Workout** → tap **Bold > Cobalt** → back out → all workout dots, borders, icons across the app are now cobalt. Persists across launches; reset clears every override.

**Caveat:** This phase overrides `NoteType.color` (the full pigment used for dots, icons, borders). `NoteType.softColor` — used as the KeepCard background tint and TypeChip's unselected icon-circle — still falls back to the design-system default. Visual mismatch is minor but visible on KeepCard fill tints; can be addressed in a polish round if needed.

### Phase F.1 — Board layout sub-modes: Grouped + Free (added this round)

The Today screen's Board view now has a 3-position sub-toggle (**Stack / Group / Free**) that appears below the Timeline | Board control whenever Board is selected. Inspired by macOS desktop stacks: organize your day's notes by type, or arrange freely.

- `Features/Timeline/BoardLayoutMode.swift` — enum with `.stacked` / `.grouped` / `.free` cases + title + SF Symbol per case
- `TimelineScreen` updated:
  - New `boardLayout: BoardLayoutMode` state (default `.free` = current behavior)
  - Sub-toggle Segmented control, only rendered when `viewMode == .board`, animated in/out via `.animation(.easeOut(0.18), value: viewMode)` + `.transition(.opacity.combined(with: .move(edge: .top)))`
  - `boardContent` dispatches between `KeepGrid` (Free) and `groupedView` (Grouped + stub Stacked)
  - `groupedView` renders cards in `LazyVGrid` sections, one section per `NoteType`, with type-colored dot + uppercase header + count. Empty types are filtered.
- **Stacked is stubbed for F.1** — currently renders the Grouped layout. F.2 will replace with overlapping-cards visual + tap-to-expand animation using `matchedGeometryEffect`.
- **Free mode persistence (drag-to-reorder)** lands in F.3 alongside a custom `position` field on `MockNote`.

**End-to-end flow:** Today tab → tap **Board** → sub-toggle slides in → tap **Group** → cards re-organize into 5 sections by note type → tap **Free** → back to 2-col masonry.

### Phase F.2 — Real Stacked Board mode (added this round)

The `.stacked` branch of `boardContent` now renders an actual macOS-Stacks-inspired visual with smooth expand/collapse.

- `Features/Timeline/StackedBoardView.swift` — top-level container that takes `[(type, notes)]` and lays out stacks in a **column-based 2-col masonry**, mirroring `KeepGrid`'s alternation rule (index 0 → left, 1 → right, 2 → left, …) so Stacked and Free place items in the same columns.
  - Two independent `VStack` columns inside an `HStack`. Tapping a stack expands its cards **vertically inside the same column**, oldest at the top of the section and newest at the bottom. The other column is untouched, so cells never jump sideways or to the top of the screen.
  - One stack open at a time — switching stacks collapses the current one as it expands the new one (`spring(response: 0.42, dampingFraction: 0.82)`).
- `CollapsedStackCell`:
  - *No header chrome* — the top card already carries the type's pigment dot + uppercase label, so a duplicate header on the stack would be redundant. The whole fan is the tap target.
  - **Newest card sits at the bottom**, older layers peek *above* it (each `8pt` higher, `0.04` smaller, `0.16` more faded). Peeking-above keeps the stack readable even when the newest card is taller than older ones (peeking-below would disappear behind a tall top card and the stack would look like a single card).
  - `+N` badge anchored to the bottom-right corner of the newest card if the group has more than 3 notes.
- `ExpandedColumnSection`:
  - Cards rendered in `group.notes` order (oldest → newest) stacked vertically; "Collapse ↑" pill anchored at the **bottom-right** below the newest card so the affordance is reachable without scrolling back to the top.
- **Single-card stacks are non-interactive** — when a group has exactly one note, `CollapsedStackCell` skips the `Button` wrapper entirely. Tapping does nothing because there's nothing to expand to.
- **`matchedGeometryEffect` gotcha (`properties: .position` + `.fixedSize`)** — every card carries `matchedGeometryEffect(id:in:properties: .position)` so it slides smoothly between its stack and expanded positions. The `.position` choice (instead of the default `.frame`) is **load-bearing**: `.frame` propagates the source's *size* to the destination, and the front-most card in the stack passes its scaled / ZStack-clamped frame to its expanded twin, truncating the text to a single line. We also pin `.fixedSize(horizontal: false, vertical: true)` on each card so the expanded copy uses its intrinsic height even if any residual frame info leaks through.
- **`KeepCard` opacity fix** — the card background now layers tint/image on top of a solid `Color.DS.bg2` base. Stacked layers no longer see through to each other (previously the translucent type-tint compounded with each peeking layer producing a muddy look).

**End-to-end flow:** Board → Stack → see a 2-col masonry of stacks (one per type) with the latest note on top of each → tap a stack → its cards unfurl vertically inside its own column; the top card morphs into the bottom of the unfurled list while older cards fade in above → tap the "Collapse" pill (or tap another stack) → it folds back into a single cell.

### Phase F.2.1 — Stack-mode collapsed spacing fix (added this round)

User reported that collapsed multi-card stacks could leave abnormally large gaps before the next stack in the column, making the Board rhythm feel inconsistent and causing the next stack/card to sit lower than expected.

- `Features/Timeline/StackedBoardView.swift`
  - **Badge overlay no longer participates in layout height.** The collapsed stack's total-count badge moved from an inner child using `.frame(maxHeight: .infinity)` to `.overlay(alignment: .topTrailing)`. This keeps the badge visually pinned to the stack without advertising flexible vertical size back to the parent `VStack` column.
  - **Stack gutter now matches the rest of Board.** The outer `HStack` column gap and each column's `VStack` item gap both changed from 8pt → 12pt so Stack mode shares the same rhythm as Cards mode.
- `docs/FEATURES.md` updated to reflect the current Stack behavior (12pt gutters, 4pt peek depth, total-count badge in the upper-right).

**Verification**
- `xcodebuild -list -project apps/ios/DailyCadence/DailyCadence.xcodeproj` succeeds with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild test -project apps/ios/DailyCadence/DailyCadence.xcodeproj -scheme DailyCadence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:DailyCadenceTests` builds the app and test target, compiles the updated `StackedBoardView.swift`, but the simulator on this machine fails to launch the app (`FBSOpenApplicationServiceErrorDomain` / `SBMainWorkspace` request denied), so no green unit-test result was available this round.

### Phase E.1.1 — Inline Style toolbar (added this round)

The Note Editor's "Style" entrypoint changed from a fullscreen modal sheet (3 nav levels deep) to an **always-on tray pinned above the keyboard**, inspired by Instagram Story's text formatting tray. Picking a font or color is now one tap with live preview on the canvas — no modal navigation.

- `Features/NoteEditor/StyleToolbar.swift` — new component:
  - **Target label** ("STYLING TITLE" / "STYLING MESSAGE", 10pt small-caps) so the user knows which field the next tap will affect.
  - **Font row** — horizontal `ScrollView` of capsule chips, each rendered in its own face (Default + 7 fonts from `FontRepository`). Selected chip = filled `ink` capsule with `bg2` text; unselected = `bg1` with thin border.
  - **Color row** — horizontal `ScrollView` of 28pt dots; "Default" first (slash-glyph convention), followed by every swatch across all 4 palettes (Neutral / Pastel / Bold / Bright) flat. Selected dot has a 2pt `ink` ring at 32pt; unselected has a hairline border.
  - `NoteEditorField` enum (`.title` / `.message`) is the toolbar's target. The `updatedStyle` collapse-empty-to-nil helper mirrors `StylePickerView`'s persistence convention.
- `NoteEditorScreen` rewired:
  - `@FocusState var focusedField: NoteEditorField?` replaces the old single-field `titleFocused: Bool`.
  - `@State lastEditedField: NoteEditorField` snapshots the most recently focused field; the toolbar reads this so the target stays meaningful when focus drops (e.g. while the Background sheet is up). Updated via `.onChange(of: focusedField)`.
  - The toolbar mounts via `.safeAreaInset(edge: .bottom, spacing: 0)` so it pins above the keyboard automatically and floats above the home-indicator zone when the keyboard is dismissed.
  - The old "Style" row + `Divider` + `.sheet(isPresented: $isStylePickerPresented)` modifier + `isStylePickerPresented`/`styleSummary`/`styleRow` helpers are deleted.
- `StylePickerView.swift` kept around (sheet shell currently unreferenced) — header now carries a Phase E.1.1 deprecation note explaining why the file stays: `FontPickerScreen` and `TextColorPickerScreen` are still used by Settings → Note Types → \<Type> for type-color overrides (Phase B.2), and the shell may be reused for a future "Advanced" entrypoint.

**End-to-end flow:** tap **+** → editor sheet → toolbar already visible above keyboard, "STYLING TITLE" label → tap **Playfair** chip → title re-renders in Playfair live → tap message field → label flips to "STYLING MESSAGE" → tap a Bold/Cobalt dot → message text turns cobalt live → Save.

**Tests:** no new tests this round — the toolbar's logic is a pure plumbing pass-through to `TextStyle` (already covered by `TextStyleTests`'s 10 tests on collapse-to-nil, partial style preservation, font/color id resolution, and store round-trip). The visual layout is verified via `StyleToolbar`'s SwiftUI Preview. 79/79 existing tests still pass.

### Phase E.2 — Rich-text message body (added this round)

The note's **message** is now an `AttributedString` with per-character runs (font + foregroundColor). Tapping a chip in the inline `StyleToolbar` no longer flattens existing styling — it either restyles the current selection or sets the typing attrs for newly-typed text. This was Jon's stated complaint with E.1.1; landed alongside a deployment-target bump.

**Deployment target:** iOS 17.6 → **iOS 26.0** (app target only; project default and tests target were already on 26.2). The bump unlocks two iOS-26-only APIs that make this clean:
- `TextEditor(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>)` — native rich-text editor with selection tracking.
- `AttributedString.transformAttributes(in: &selection, body: { container in ... })` — single call that does double duty: applies attrs to a selected range, OR (when the selection is collapsed) sets the typing attributes on the cursor so the *next* characters typed inherit the change. No manual diff/insertion-detection needed.

The fallback (sticking with iOS 17/18) would have meant either typing-attrs-only behavior with no selection-based formatting, or a UIKit `UITextView` bridge — both worse for code complexity and end-user feel. Phase 1 is TestFlight to Jon + wife only, so the device-compat hit is acceptable; we'll reassess at TestFlight expansion.

**Model changes**
- `MockNote.Content.text(title:message:)` — `message` is now `AttributedString?` (was `String?`). Plain text seeds wrap as `AttributedString("…")`.
- `MockNote.messageStyle` is **gone** — per-run AttributedString attributes replace it. The init signature, `MockNoteBackgroundTests`, `TextStyleTests`, and `TimelineScreen.swift`'s `NoteCard(...)` call site were all updated to drop the parameter.
- `MockNote.timelineMessage` returns `AttributedString?` instead of `String?`. Stat / list variants synthesize plain `AttributedString(...)` so the consumer always gets one type.

**Component changes**
- `KeepCard.textContent` — message rendered via `Text(_: AttributedString)`. The `.font` / `.foregroundStyle` modifiers below now act as the **default** for runs without explicit attrs (per-run overrides win). Previews updated.
- `NoteCard` — same pattern; `messageStyle` parameter dropped from the init.

**Editor changes (`NoteEditorScreen.swift`)**
- New `@State`: `messageText: AttributedString`, `messageSelection: AttributedTextSelection`, `messageFontId: String?`, `messageColorId: String?` (the last two mirror the toolbar's chip highlight; the AttributedString itself is the source of truth for what gets *rendered*).
- The message field is now a `TextEditor(text: $messageText, selection: $messageSelection)` with `.scrollContentBackground(.hidden)` so the live preview background still shines through. The placeholder ("What's on your mind?") is overlaid behind via a `ZStack` that hides as soon as `messageText.characters` is non-empty (TextEditor has no native placeholder API).
- `applyMessageFont(id:)` / `applyMessageColor(id:)` use a single call:
  ```swift
  messageText.transformAttributes(in: &messageSelection) { container in
      container.font = … // or .foregroundColor = …
  }
  ```
  Range selections get attrs stamped on every char; collapsed cursors get typing attrs on the selection so subsequent typing inherits the choice.
- Save trims leading/trailing whitespace via a small `AttributedString.trimmingTrailingAndLeadingWhitespace()` helper that drops boundary chars while preserving attrs on the rest.

**StyleToolbar refactor**
- API shape changed from "two `Binding<TextStyle?>` plus `activeField`" to a callback shape: `currentFontId`, `currentColorId`, `onSelectFont(_:)`, `onSelectColor(_:)`. The toolbar is now a dumb picker; the editor decides what to do per-field (per-field `TextStyle` for title vs `transformAttributes` for the message).
- No visual change.

**Tests:** 80/80 passing (was 79; +1).
- New: `TimelineStoreTests.attributedMessagePreservesPerRunAttributes` — round-trips a styled `AttributedString` through `TimelineStore.add` to guard against silent flattening on save.
- Updated: `TextStyleTests.mockNoteCollapsesEmptyStyleToNil` and `mockNotePreservesNonEmptyStyle` no longer reference the dropped `messageStyle` parameter.

**Known limitations / future polish**
- The chip highlight in the toolbar reflects only the *most recently tapped* font/color, not the actual run at the cursor. If the user taps Playfair, types "world", moves the cursor into a default-Inter region, the chip still says Playfair. Fix: introduce a custom `AttributedStringKey` (`fontId` / `colorId`) so app-level metadata round-trips with the rendered attrs, and read from it on cursor-position change. ~½ round when it becomes annoying.
- Title is still plain `String` + `TextStyle`. Per-run rich text in titles is intentionally out of scope — uniform titles read better, and limiting rich text to messages kept the model migration small.

### Phase E.2.1 — Editor polish: draft recovery, size slider, keyboard clearance (added this round)

Three small but high-impact polish passes on the rich-text editor.

**1. `StyleToolbar` keyboard clearance.** The color row's selection ring used to graze the keyboard's top edge when active — `safeAreaInset` placed the toolbar flush with the keyboard but the row had no breathing room. Bumped the toolbar from symmetric `padding(.vertical, 10)` to `top: 10, bottom: 18`. Negligible diff in toolbar height; visible improvement when a color dot is selected.

**2. Draft recovery via `NoteDraftStore`.**
- `Services/NoteDraftStore.swift` — `@Observable` singleton holding every editable field (title, message AttributedString, message selection, message font/color/size, titleStyle, selectedType, background).
- `NoteEditorScreen` was rewritten to use `@Bindable var draft = NoteDraftStore.shared` everywhere — the view holds *no* local field state of its own anymore. Bindings to TextField / TextEditor / pickers all go through the store.
- Lifecycle: **Save** builds the note + calls `draft.clear()`; **Cancel** calls `draft.clear()` + dismisses (intentional discard); **background dismiss** (swipe-down / outside tap) dismisses without clearing — next FAB tap restores the in-progress note.
- Nav title swaps from "New note" → "Resume draft" when `draft.isEmpty == false`, so the user knows on open whether they're picking up where they left off.
- **Scope:** in-memory only — drafts don't survive app relaunch. UserDefaults / on-disk persistence is a Phase F follow-up. The current behavior covers the much more common "I swiped the sheet away by accident" case.

**3. Vertical text-size slider (Instagram-Story-style).**
- `Features/NoteEditor/VerticalSizeSlider.swift` — custom drag-driven control (no rotated `Slider` — rotated SwiftUI sliders keep their pre-rotation layout footprint and fight right-edge alignment). Built from a track Capsule + filled-portion Capsule + ink-colored knob inside a translucent `.ultraThinMaterial` backdrop pill, with `Aa` glyphs at top and bottom to telegraph the affordance.
- 12...48pt range, 200pt track height, 36pt overall width. `DragGesture(minimumDistance: 0)` — tap-to-jump anywhere on the track.
- Mounted via `.overlay(alignment: .trailing)` on the message editor's ZStack. `showMessageSizeSlider` gate keeps it hidden when the title field is focused or there's no message context yet; transitions in/out via `.opacity.combined(with: .move(edge: .trailing))`.
- `applyMessageSize(_:)` runs the same `transformAttributes(in: &selection)` pipeline as the font/color chips — range selections get the new size stamped on every char, collapsed cursors get typing attrs so the next characters typed inherit it. The font *family* is preserved by deriving the new font from `draft.messageFontId` (or DS Inter as the default), since `AttributeContainer` can't preserve per-run families across a multi-font selection in one call.

**Tests:** 80/80 still passing. No new tests this round — `NoteDraftStore` is a pure state container (set / clear / read) and `VerticalSizeSlider` is a visual control. Both are exercised end-to-end via the editor's SwiftUI Preview and at runtime.

**End-to-end flow (recovery):** tap **+** → type "Slept poorly," → swipe sheet down by accident → tap **+** again → nav bar reads "Resume draft," title field shows "Slept poorly," cursor returns to where you left off. Save or Cancel to clear and start fresh next time.

**End-to-end flow (size):** tap **+** → tap into message → vertical slider fades in on the right edge → drag the knob up → the typed message scales live up to ~48pt → drag down to shrink. Combine with chip taps for font + color on the same range.

### Phase E.2.2 — Compact icon-bar toolbar with expandable panels (added this round)

The editor felt crowded — three always-on rows (label + fonts + colors) plus the Background row plus the size slider added up to ~200pt of chrome below the canvas. This phase collapses the styling controls to a 56pt icon bar; pickers are one tap away.

**Layout change**
- **Before:** dedicated Background row in the form (~52pt) + always-on toolbar with target-label / font row / color row (~140pt with Phase E.2.1 padding) = ~192pt of editor chrome.
- **After:** icon bar (56pt) with `Aa` font · `●` color · `↕` size · `🖼` background. Tapping a styling icon expands a single panel above the bar (~64pt) with its picker; tapping `🖼` opens the existing `BackgroundPickerView` sheet. Net: ~136pt of canvas reclaimed when collapsed, ~70pt reclaimed when a picker is open.

**StyleToolbar refactor (`Features/NoteEditor/StyleToolbar.swift`)**
- New `StyleToolbarPanel` enum (`.font / .color / .size`) hoisted to file scope so the editor can drive the size slider's visibility off the same state.
- New params: `expandedPanel: Binding<StyleToolbarPanel?>`, `backgroundPreview: AnyView`, `onTapBackground: () -> Void`.
- Each icon button doubles as a **live preview** of its current value:
  - `Aa` icon renders the user's currently-active font face → swap from Inter to Playfair and the icon's `Aa` re-renders in Playfair.
  - `●` icon's center fills with the current swatch color (slash-glyph for Default).
  - `↕` icon uses two stacked `A` glyphs — small over large, the typographic convention for "size."
  - `🖼` icon shows the background preview (tag-color dot, swatch dot, or photo thumbnail) so the user knows what the saved card will look like without opening anything.
- Active panel button fills with `ink` (matches the chip-selected pattern) so the open state is unambiguous.
- The `STYLING TITLE / STYLING MESSAGE` label moved out of the bar and into the expanded panel header (e.g. "FONT · MESSAGE"). The cursor on the canvas already tells the user which field is focused, so the label is only useful when a picker is actually open.
- Tap rules: tap an icon → toggle its panel; tap a different icon → swap; the bg icon never expands (always opens the sheet).
- Animation: panel expands/collapses with `.move(edge: .bottom).combined(with: .opacity)` over `.easeOut(0.2)`.

**Size slider gated on `expandedPanel == .size`**
- Previously visible whenever the message field was focused; that meant it always covered the canvas's right edge while writing.
- Now only renders when the user explicitly opens the Size panel — the message canvas is fully unobstructed during ordinary typing.
- Slider footprint also shrunk: track height 200 → 140, knob 18→14pt visible / 28→24pt hit, backdrop pill 32→26pt wide. Visually lighter and less of a thumb obstacle on small phones.
- The Size panel's body shows a one-line hint ("Drag the slider on the right to resize.") so users discover the canvas-edge control on first open.

**NoteEditorScreen changes**
- Added `@State expandedPanel: StyleToolbarPanel? = nil`.
- Removed the `backgroundRow` view from the form VStack (and its dedicated `Divider`).
- New `backgroundIconPreview` view that returns the right swatch/photo thumbnail for the toolbar's `🖼` icon.
- Tapping the icon flips `isBackgroundPickerPresented = true`, same sheet as before.

**Tests:** 80/80 still passing. No new tests this round — the change is visual (callback wiring + state plumbing already covered).

**End-to-end flow:** tap **+** → small icon bar above keyboard → tap **Aa** → font row slides in, header reads "FONT · MESSAGE" → tap **Playfair** → messages typed thereafter render in Playfair → tap **Aa** again to collapse → tap **↕** → Size hint appears in the panel + vertical slider fades in on the canvas edge → drag → tap **🖼** → existing background sheet opens. Cancel or Save clears the draft.

### Phase E.2.3 — Collapsible type picker + neutral `.general` default (added this round)

The five-chip type row was eating ~96pt at the top of the editor for a control most users only touch once per note. Two small changes shrink that to ~60pt and clean up the default state.

**1. New `NoteType.general` (default).** Sixth case added at the front of `allCases`:
- Title: "General"
- Icon: `note.text` (SF Symbol — generic paper-with-lines glyph)
- Pigment: `Color.DS.warmGray` (warm neutral grey, not a category color)
- Soft: `Color.DS.taupe` (cream-adjacent, won't fight other types on the timeline)

`NoteDraftStore.shared.selectedType` now defaults to `.general` (was `.mood`). Without `.general`, the editor implicitly tagged every quickly-typed note as a Mood — wrong default. Users can still pick a category any time; `.general` just frees them from committing on creation.

`Settings → Note Types` now lists six types instead of five (the user can override `.general`'s color too — same code path as the others). `MockNotes.today` is unchanged; the seeded notes still use specific categories.

**2. Collapsible type picker.**
- New `@State typePickerExpanded = false` in `NoteEditorScreen`.
- **Collapsed (default):** a single `TypeChip` showing the current selection (with `isSelected: true`). Tap → expand.
- **Expanded:** the full horizontal row of every `NoteType.allCases` chip. Tap any chip — including the currently-selected one — sets the selection and collapses. The selected chip is its own "close" affordance, no separate X needed.
- Toggle uses `withAnimation(.easeOut(duration: 0.2))` so the swap reads as a smooth row reflow rather than a discrete jump.

**Net canvas reclaimed:** ~60pt at rest (one chip vs. five). With Phase E.2.2's icon bar that's ~196pt of editor chrome reclaimed since the start of this polish stretch.

**Tests:** 80/80 still passing. Existing `NoteTypeStyleStoreTests` work unchanged — the override store is keyed by raw value and gracefully accommodates any new cases.

**End-to-end flow:** tap **+** → top of editor shows a single "General" chip → tap → all six chips slide in → tap "Workout" → row collapses back to just "Workout" → tap that chip again to re-expand and switch.

### Phase E.2.4 — Open / Cancel polish (added this round)

Three behavioral refinements to the editor's lifecycle so the dismiss paths feel intentional.

**1. Type picker auto-expanded on fresh open.** `typePickerExpanded`'s initial value is now `NoteDraftStore.shared.isEmpty` instead of `false`. When the user starts a *new* note all six types are immediately discoverable; when they're *resuming* a draft (drag-dismissed earlier and re-opened) the picker collapses to the chosen chip — they've already committed.

**2. Cancel asks before discarding (only when there's something to lose).** Cancel was a silent draft-clear before; an accidental tap evaporated everything. Now:
- Empty draft → Cancel dismisses immediately (no point confirming nothing).
- Non-empty draft → Cancel surfaces a `.confirmationDialog` ("Discard draft? / Your in-progress note will be lost." with a destructive **Discard Draft** + cancel **Keep Editing**). Discard clears + dismisses; Keep Editing closes the dialog and leaves the editor open.

**3. Drag-to-dismiss preserves the draft (verified, no code change).** The `presentationDragIndicator(.visible)` swipe path doesn't touch `draft.clear()` — it just dismisses the sheet. Re-opening restores everything via `NoteDraftStore.shared`. This was already the intended behavior from E.2.1; called out here because it's now part of a coherent three-path discard model:

| Path | Clears draft? | Confirms? |
| --- | --- | --- |
| **Save** | yes | no — explicit commit |
| **Cancel** | yes | yes (if non-empty) |
| **Drag-to-dismiss** | no | no — recovery path |

**Tests:** 80/80 still passing. No new tests — the changes are pure UI plumbing covered by visual smoke testing in the editor sheet.

### Phase E.2.5 — Whole-canvas scroll (added this round)

The TextEditor's internal scroll was the *only* scrollable surface in the editor — so a long title that wrapped to four lines plus a tall message left no way to pan the type picker back into view, and on smaller phones the whole layout felt cramped under the keyboard + toolbar.

**Layout change**
- The editor's content (`typePicker` + divider + `form`) is now wrapped in a single outer `ScrollView(.vertical)` with `.scrollDismissesKeyboard(.interactively)`. Pull down on the canvas to dismiss the keyboard mid-typing.
- `TextEditor` got `.scrollDisabled(true)` so it stops being its own scroll container and self-sizes to its content. The outer ScrollView is now the single source of vertical scroll — no nested-scroll gesture conflicts.
- Title `TextField`'s `.lineLimit(1...3)` relaxed to `.lineLimit(1...)` — long titles can grow as many lines as they need; the parent ScrollView absorbs overflow.
- Removed `maxHeight: .infinity` from the form's frame (it was fighting ScrollView's unbounded vertical space).

**Slider relocation**
- `VerticalSizeSlider` moved out of the `messageEditor` view and onto the outer `ScrollView`'s `.overlay(alignment: .trailing)`. Result: the slider stays anchored to the visible viewport while content scrolls underneath, instead of riding off-screen with the message canvas.
- Animation/visibility logic (`expandedPanel == .size`) is unchanged.

**Tests:** 80/80 still passing.

**End-to-end flow:** tap **+** → type a title that wraps to 4 lines → write a long message → pull the canvas down to scroll the type picker back into view, or to dismiss the keyboard. Tap **↕** in the toolbar → slider fades in on the right edge and stays there as you scroll.

### Phase E.3 — Photo/video notes (added this round)

DailyCadence now supports media notes alongside text notes — pick a photo or video from your library, optionally caption it, save. Cards render the asset full-width respecting its aspect ratio; tapping opens a full-screen viewer with pinch-zoom (images) or AVKit playback (videos). Cards also got a hard max-height cap so a single tall note can't dominate the Board grid.

**Model**
- `Models/Media.swift` — new `MediaPayload` value type carrying `kind` (`.image` / `.video`), the asset bytes, an optional first-frame `posterData` for videos, an aspect ratio (clamped to `0.4 ... 2.5` so panoramas/portraits can't break the masonry layout), and an optional caption (whitespace-trimmed; empty→`nil`).
- `MockNote.Content.media(MediaPayload)` — sixth case alongside `.text/.stat/.list/.quote`.
- `MockNote.timelineTitle` falls back to `"Photo"` / `"Video"` when a media note has no caption; `timelineMessage` is `nil` for media notes (the asset *is* the body). New `mediaPayload` accessor for view code.

**Rendering — max height + media area**
- `KeepCard.maxHeight = 480` and `NoteCard.maxHeight = 520` clamp every card. Text overflow is clipped (the existing `lineSpacing` modifiers handle in-card flow); media is clipped via `RoundedRectangle.clipShape`.
- Both cards render `.media` notes via a new `mediaContent(_:)` / `mediaArea(_:)` view: a tappable `ZStack` showing the asset (or `posterData` for video) at the note's `aspectRatio`, with a `.ultraThinMaterial` play button centered on video posters.
- Tap → `.fullScreenCover` presents `MediaViewerScreen`.

**Full-screen viewer (`Features/MediaViewer/MediaViewerScreen.swift`)**
- Black backdrop, top-trailing close (X) button, optional caption gradient at the bottom.
- **Images** — `ImagePinchZoomView` uses iOS 17's zoomable `ScrollView` (pinch + double-tap zoom built in). Decode happens off-main via `Task.detached`.
- **Videos** — writes the bytes to `temporaryDirectory/dc-video-<UUID>.mov` on appear (AVPlayer reads from `URL`, not raw `Data`), wraps an `AVPlayer` in SwiftUI's `VideoPlayer`, auto-plays on display, cleans up the temp file on dismiss.

**Import pipeline (`Services/MediaImporter.swift`)**
- `MediaImporter.makePayload(from: PhotosPickerItem) async throws -> MediaPayload` — single entry point for the editor.
- For images: decodes via `UIImage(data:)`, reads `size.width / size.height` for aspect ratio.
- For videos: writes bytes to a temp file, opens an `AVURLAsset`, loads the first video track's `naturalSize` + `preferredTransform` (so a portrait recording reports the right aspect), generates a poster via `AVAssetImageGenerator.image(at: .zero)` async API, JPEG-encodes at 0.85 quality. Cleans up the temp file in a `defer`.

**Editor (`Features/NoteEditor/MediaNoteEditorScreen.swift`)**
- Single-purpose flow — no styling toolbar, no rich-text apparatus, no draft-store (the asset is the substance; re-pick on dismiss is less disruptive than re-typing).
- Mirrors the text editor's collapsing type picker (defaults to `.general`).
- Body: live preview with play overlay for videos + Replace / Remove actions, then a rounded-rectangle "Caption" `TextField` (1...4 lines).
- The whole content is wrapped in a `ScrollView` with `.scrollDismissesKeyboard(.interactively)` to match the text editor's gesture vocabulary.

**FAB flow (`TimelineScreen`)**
- Tap **+** → `.confirmationDialog("Add to today")` with two options: **Text Note** (existing flow) and **Photo or Video** (new).
- Photo or Video → `.photosPicker` opens with `matching: .any(of: [.images, .videos])`. On selection → `.sheet` presents `MediaNoteEditorScreen(initialItem:)`. The picker item is cleared via `onDismiss` so a second pass starts clean.

**Tests:** 87/87 passing (was 80, +7).
- `MediaPayloadTests` (7) — aspect-ratio clamp (min, max, in-range), caption trim/empty→nil, media content `.media` round-trip through `TimelineStore`, `timelineTitle` "Photo"/"Video" fallback for captionless media, `mediaPayload` accessor.

**End-to-end flows**
- *Photo:* FAB → "Photo or Video" → pick → editor opens with preview → type caption → Save → photo appears in timeline + board, sized to its aspect ratio inside the card → tap → full-screen pinch-zoom viewer.
- *Video:* same flow → video poster shows in card with play button overlay → tap → full-screen viewer with AVPlayer controls.

**Deferred (Phase E.3.x)**
- **Camera capture.** UIImagePickerController + Info.plist `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` strings. Will land alongside the existing FAB action sheet as a third option ("Camera"). One round.
- Multi-asset attachments per note, in-place crop/edit, image downscaling on import.

### Phase E.4 — Full-bleed media cards + FAB Menu (added this round)

Architectural refactor of how photo/video notes render and how the FAB triggers note creation. Two distinct concerns merged into one round because they're both about *what kind of note is this and how does the UI tell you*.

**1. `MockNote.Kind` enum** — high-level scaffold discriminator:
```swift
enum Kind: String, Hashable { case text, photo, video }
var kind: Kind  // .photo / .video for `.media(_:)`, .text for everything else
var isMediaNote: Bool  // == kind != .text
```
Derived from `Content` — no model duplication, no migration. Distinct from `NoteType` (which is the *category*: workout / meal / mood / etc.). Cards consume `isMediaNote` to pick between two scaffolds; tests in `MediaPayloadTests.noteKindReflectsContent` lock in the mapping rules.

**2. Full-bleed media scaffold** in `KeepCard` and `NoteCard`. Before E.4, a media note rendered with the same chrome as a text note: type-chip head, padded inset, the media area carrying its own rounded clip inside the card. Now:
- Text notes → original scaffold (head + content, padded in `bg-2` rounded surface).
- Media notes → **full-bleed**: photo/video poster fills the card edge-to-edge, no type-chip head, no inner padding. Caption (when present) sits at the bottom in a `LinearGradient(.clear → .black @ 0.55)` overlay so it reads regardless of underlying brightness. Video posters get the same `.ultraThinMaterial` play button as before, centered.
- Both scaffolds still share the rounded clip + max-height cap + (for `NoteCard`) the level-1 shadow.

Stack/Group views are unchanged — they organize by `NoteType`, which is orthogonal to `Kind`. A photo tagged `.workout` still sits in the Workout group/stack; it just renders full-bleed inside its tile.

**3. Modern FAB Menu.** The bottom-of-screen `confirmationDialog` was awkward when the trigger is a bottom-right FAB — the popup felt disconnected from the button.
- New `FABAppearance` view exposes the FAB's pure visual (no built-in `Button`) so a `Menu { … } label: { FABAppearance() }` can own the gesture without conflicting with the regular tap-action `FAB`.
- `TimelineScreen` now uses `Menu` directly: tap → glassy popover anchors to the FAB itself with **Text Note** / **Photo or Video** rows (each with an SF Symbol).
- Removed `isNewNoteSheetPresented` state — `Menu` handles its own presentation.

**Tests:** 88/88 passing (was 87, +1 in `MediaPayloadTests.noteKindReflectsContent`).

**End-to-end flow:**
- Tap **+** → menu pops up next to the FAB → tap **Text Note** for the existing editor, tap **Photo or Video** → PhotosPicker → MediaNoteEditorScreen → Save → media note appears with full-bleed scaffold (no type head, caption gradient at the bottom).

**Coming up — recommended ordering for Phase E.5+:**
- **E.5** Inline text formatting toggles (bold / italic / underline / strikethrough) — extends the existing `StyleToolbar` font panel via `transformAttributes` toggling `Font` traits.
- **E.6** Auto-bullet on `-` and Apple-Notes-style checkboxes in the message body.
- **E.7** Inline attachments in text notes — recommended pattern is Apple-Notes-style (image as an `AttributedString` attachment run, flows with text). Free-position drag is much harder on phones and rarely beats inline.
- **E.x** Pinch-to-zoom in the crop tool, video trim, camera capture (`UIImagePickerController` + Info.plist privacy strings).

### Phase E.4.1 — Photo crop + media editor cleanup (added this round)

Three connected polish passes on the media-note flow.

**1. Photo crop tool (`Features/MediaCrop/PhotoCropView.swift`).**
- New `PhotoCropAspect` enum: Free / 1:1 / 4:3 / 3:4 / 16:9 / 9:16. `Free` falls back to the source's native aspect.
- New `PhotoCropState` (`@Observable` class) owns crop state — image, current `aspect`, `offset`, and a sticky `savedOffset` so chained drag gestures accumulate. Exposed as a `@Bindable` reference from the parent so `MediaNoteEditorScreen.save()` can call `state.commitCrop()` to compute the final cropped JPEG.
- `PhotoCropView` renders the source image at scale-to-fill into a viewport sized by the chosen aspect. A `DragGesture` pans the image inside the viewport's clip region; pan is clamped via `clampedOffset(_:viewport:)` so the viewport never sees an empty edge.
- Aspect chip row mirrors the StyleToolbar's chip styling (selected = `ink`-filled capsule with `bg2` text).
- **Pan-only for v1.** Pinch-to-zoom is a known-deferred follow-up — pinch + pan compounds two scale terms in the crop math (base fill scale × user scale), and the gesture interactions are subtle. Pan-only meets the "fit to chosen aspect" need without the engineering ramp; we'll revisit if users want to crop tighter than scale-fill.
- **Crop math.** `commitCrop()` derives `baseScale = max(viewportW/imageW, viewportH/imageH)`, computes the visible image region in source coordinates as `viewportSize / baseScale`, and shifts that region by `-offset / baseScale` to apply the user's pan. `CGImage.cropping(to:.integral)` extracts the JPEG.
- **UIImage normalization.** `UIImage.normalizedUp()` redraws non-`.up` orientations (iPhone portrait photos arrive as `.right`-oriented) so subsequent CGImage cropping uses the visible coordinate space, not the raw rotated pixel space. Without this, a portrait photo from the camera would crop sideways.

**2. `MediaNoteEditorScreen` simplified.**
- **Type picker removed.** Media notes default to `NoteType.general` — they don't read as a category, and forcing a workout/meal/etc. tag added friction without value. Stack/Group views still work (everything bunches under General until the user manually edits later).
- **Crop view embedded** for image payloads — full-height (420pt) `PhotoCropView` mounted at the top of the editor, then Replace/Remove row, then caption field. Save commits the crop before adding the note.
- Videos still skip the crop step (timeline trim is a separate feature) — they show a read-only poster + Replace/Remove + caption.
- The picker callout (when no media is loaded yet) lost the dashed border-strip mid-tier styling consistency tweak.

**3. Caption below the image, not overlaid.**
- Earlier rounds rendered the caption inside a `LinearGradient(.clear → .black @ 0.55)` overlay at the bottom of the media area. That meant the caption ate part of the image, the gradient looked dated, and on light photos the white caption read poorly.
- Both `KeepCard` and `NoteCard` now use a vertical stack: image at native aspect ratio at top, caption text on the card's `bg-2` surface beneath (12–14pt padding). Image uses `aspectRatio(contentMode: .fill)` so it covers its cell without letterbox, addressing the "image isn't filling the cell" feedback.

**Tests:** 88/88 still passing. No new tests this round — `PhotoCropState`'s crop math is exercised at runtime via simulator and is hard to assert against without a fixture image; deferring crop-math unit tests to a follow-up that builds a deterministic test image.

**End-to-end flow:** tap **+** → menu → **Photo or Video** → pick photo → editor opens with the photo in the crop view → tap **1:1** chip → viewport snaps square → drag the photo to position → optionally type a caption → **Save** → photo appears in the timeline as a full-bleed square card with the caption text beneath.

### Phase E.4.2 — Crop tool rewrite + media cell width fix (added this round)

Two connected fixes — the crop tool's "Free" mode wasn't usable (pan-only meant Free was just "show the whole image") and media cards on the Board were rendering narrower than their column. Both addressed.

**1. Crop tool — Photos.app model.**

Pan-only crop ([Phase E.4.1](#phase-e41--photo-crop--media-editor-cleanup-added-this-round)) is replaced by a proper resizable crop rectangle:

- Image is fixed at scale-to-fit inside the canvas. The **crop rectangle** floats on top in canvas coordinates.
- **Four corner handles** (white L-shapes, 18×18 visual / 36×36 hit target) — drag to resize. Free mode resizes freely; presets (1:1 / 4:3 / 3:4 / 16:9 / 9:16) maintain their ratio by anchoring the resize to the corner opposite the dragged handle.
- **Center drag** — invisible inset region inside the crop rect (shrunk by the handle hit-zone so the corner gestures stay grabbable). Drags the crop rect across the image.
- **Dimmed exterior** — eo-fill `Canvas` overlay with a hole punched at `cropRect`, anchoring user attention on what survives the crop.
- **Rule-of-thirds guides** — two horizontal + two vertical lines at 1/3 / 2/3 inside the crop rect at 0.4 opacity, matching the Photos.app aesthetic.
- **Aspect chips** apply by snapping the crop rect to the chosen ratio centered inside the visible image rect; Free leaves the rect free-form.
- **Minimum crop dimension** — 60pt in canvas coords. Resize attempts that would shrink below this push the moving edge back so the rect never collapses.

`PhotoCropState` got a clean rewrite:
- Tracks `imageRect` (the scaled-to-fit visible rect) plus `cropRect` (in canvas coords).
- `setImageRect(_:)` is called from `PhotoCropView`'s `GeometryReader` so the state always knows the current image layout.
- `commitCrop()` maps `cropRect` → source-image pixel coords via `imageSize / imageRect.size` scale, defensively clamps a fraction-of-a-pixel out of bounds, crops via `CGImage.cropping(to:)`, and JPEG-encodes at 0.9 quality.

**Pinch-to-zoom on the image is deferred to a follow-up.** Combining pinch with the crop rect needs coordinated gesture priority (handle drag > center drag > image pan, and pinch must update both image transform and the crop rect's reference frame). The current corner-resize + center-drag covers the dominant "crop to a chosen region" UX; pinch is the next polish step when users want to crop tighter than scale-to-fit.

**2. Media cell width — `GeometryReader` + explicit sizing.**

The prior layout chained `.aspectRatio(_, contentMode: .fit)` + `.frame(maxWidth: .infinity)` on a `ZStack`. Under the parent's `.frame(maxHeight: 480)` constraint, the aspectRatio modifier could reduce the rendered width below the column width — leaving whitespace on either side of media cards (visible on the "Paw prints" card in user's screenshot).

Both `KeepCard.mediaImageRow` and `NoteCard.mediaImageRow` now use:
```swift
GeometryReader { geo in
    let width = geo.size.width
    let height = width / media.aspectRatio
    ZStack { ... }.frame(width: width, height: height)
}
.aspectRatio(media.aspectRatio, contentMode: .fit)
.frame(maxWidth: .infinity)
```

The outer aspectRatio + maxWidth still controls the cell's external footprint, but inside, the GeometryReader reads the actual width and forces the image to render at exactly `width × width/aspectRatio`. The image always fills the cell edge to edge.

`Button { ... } label: { ... }` was replaced with `.contentShape(Rectangle()).onTapGesture { … }` so the tap target sits cleanly on the image itself without `Button`'s default styling fighting the GeometryReader-driven layout.

**Tests:** 88/88 still passing. No new tests this round — both changes are pure visual / interaction with no straightforwardly assertable model state. Verified at runtime in the simulator.

**End-to-end flow:** tap **+** → **Photo or Video** → pick photo → editor opens with the crop rect filling the image → drag a corner inward to crop tighter → drag the center to reposition → tap **16:9** to lock the aspect → corners now resize maintaining 16:9 → Save → resulting card on the Board fills its column edge to edge at the new aspect.

### Phase E.4.3 — Free Board: uniform gutter + drag-to-reorder (added this round)

Both items from the user's earlier feedback that pivot-to-crop deferred.

**1. Uniform 12pt gutter on the Board.**
- `KeepGrid.spacing` default bumped from 8 → 12pt (column gap and row gap match).
- `TimelineScreen.horizontalPadding(for: .board)` reduced from 16 → 12pt to match.
- Net effect: every card on the Board sits inside a single 12pt rhythm — outer margin, inter-column gap, and inter-row gap are all identical, which is the Google Keep look.

**2. Drag-to-reorder + Reset for Free layout.**
- `Services/FreeViewOrderStore.swift` — `@Observable` singleton holding a custom `[UUID]` order. Empty ⇒ chronological fallback from `TimelineStore`. `move(_:before:in:)` seeds from the current chronological order on the first reorder so subsequent sorts are stable; `reset()` clears.
- `sorted(_:)` returns notes in the custom order, with notes added after the last reorder (not yet tracked) sorting to the **end** rather than silently jumping into the middle of a hand-curated layout. Stable sort uses input array index as the tiebreaker.
- `TimelineScreen.freeBoardGrid` wraps each `KeepCard` with `.draggable(note.id.uuidString) { previewView }` and `.dropDestination(for: String.self) { … move … return true }`. iOS handles the long-press-to-start gesture; SwiftUI's drag preview is a 0.85-opacity miniature of the dragged card.
- `resetOrderRow` — small "↺ Reset order" pill anchored top-right, only rendered when `viewMode == .board && boardLayout == .free && hasCustomOrder`. Tapping it animates the cards back to chronological order and dismisses the pill.

**Tests:** 95/95 passing (was 88, +7).
- `FreeViewOrderStoreTests` covers empty fallback, first-move seeding from chronological, subsequent-move preservation, new-notes-after-reorder-sort-to-end, reset, move-to-self no-op, and unknown-target defensive behavior.

**Known limitation.** SwiftUI's `.draggable` / `.dropDestination` only commit the reorder on **drop** — the cards don't shift in real time as you drag. That's the same model as Apple Mail's mailbox reorder; users do see the drag preview hovering. For real-time live reflow during drag (Google Keep web style), we'd need a custom `DragGesture` + measurement pass on the masonry. Punted to a follow-up if it ends up feeling sluggish.

**End-to-end flow:** Today → **Board** → **Free** → long-press any card → drag onto another card → release → cards reorder + the **↺ Reset order** pill appears at the top → tap the pill → cards animate back to chronological + pill disappears.

### Phase E.4.4 — Card height inflation fix (added this round)

User reported persistent gaps in the Free Board layout after E.4.3's spacing tune. Initial theory was masonry column-mismatch, but the real issue was *internal* — short cards had empty space inside them.

**Root cause.** `KeepCard` and `NoteCard` had `.frame(maxHeight: Self.maxHeight, alignment: .top)` on their body. With only `maxHeight` (no `idealHeight`), the view reports a *flexible* preferred size to its parent — anywhere from 0 up to 480pt. SwiftUI's `VStack` (the column wrapper inside `KeepGrid`) is allowed to give that flexible child more height than its content needs when the column has spare vertical space, which it does whenever the other column is taller. The `alignment: .top` parameter then pinned content to the top of the inflated frame, leaving visible empty space below.

**Fix.** Added `.fixedSize(horizontal: false, vertical: true)` BEFORE the `.frame(maxHeight:)`:
```swift
.fixedSize(horizontal: false, vertical: true)
.frame(maxHeight: Self.maxHeight)
```
`fixedSize(vertical: true)` forces the view to report its **intrinsic** height as its preferred size, so the parent VStack can no longer inflate it. The `maxHeight` cap still kicks in for genuinely tall content (long messages, very portrait photos) — that's why the modifier order matters.

`alignment: .top` removed from the frame since `fixedSize` keeps content tight against the frame edges anyway.

**Tests:** 95/95 still passing. No new tests — the fix is purely a layout assertion best verified visually.

**End-to-end:** Today → **Board** → **Free** → short cards (e.g., a one-word "Focused" mood) now render at their intrinsic ~60pt height instead of expanding to fill the column's spare space; columns pack tight in the masonry; gaps between cards are exactly the 12pt gutter.

### Phase E.4.5 — Custom `MasonryLayout` (added this round)

Phase E.4.4's `.fixedSize(vertical: true)` fix turned out to be insufficient — when long-pressing a card to start a drag, the user could see the card's *actual* allocated frame extended below its visible content (a white box behind a small mood card). The HStack-of-VStacks layout was still over-allocating space to short cards, the `.background` only coloring the inner content, and `.draggable` / `.dropDestination` interactions exposing the gap during the lift visualization.

**Fix.** Replaced KeepGrid's `HStack { VStack; VStack }` body with a custom `Layout`:

- `DesignSystem/Components/MasonryLayout.swift` — implements `Layout` (iOS 16+) with shortest-column-first packing.
- `sizeThatFits` and `placeSubviews` both compute child sizes via `subview.sizeThatFits(.init(width: columnWidth, height: nil))` — this returns each child's **intrinsic** height for the column width, with no flex ambiguity.
- `placeSubviews` then calls `subview.place(at:anchor:proposal:)` with the exact intrinsic height so the framework can't inflate it later.
- Shortest-column-first balances columns automatically, replacing the prior strict alternation (idx 0 → left, idx 1 → right, …). The user's drag-to-reorder still works for hand-curated arrangements.

`KeepGrid` is now a 30-line wrapper that builds a `MasonryLayout` and passes the items through a `ForEach`. The previews still verify visually.

**Trade-off.** Shortest-column-first means insertion order isn't strictly column-alternating anymore — a fresh sequence of cards might pack 3 in the left column before placing one on the right if the left's heights are tiny. That's the expected Google Keep behavior. The Free view's drag-to-reorder gives users explicit control when the auto-pack puts things in an unexpected order.

**Tests:** 95/95 still passing — `MasonryLayout` is a pure layout primitive verified through SwiftUI Previews and at runtime; no straightforwardly assertable model state.

**End-to-end:** Long-press a small card on the Free Board layout — the card lifts at exactly its visible size; no phantom white space below.

### Phase E.4.6 — Drop operation = `.move` (added this round)

User saw a green "+" badge attached to the dragged card during long-press-and-drag. That's iOS's standard "copy" indicator — SwiftUI's `.dropDestination(for:)` defaults to `DragOperation.copy`, which the system renders with the "+". For reorder, we want `.move` (no badge).

**Fix.** Replaced `.dropDestination` with `.onDrop(of:delegate:)` + a custom `NoteReorderDropDelegate`:
- `Features/Timeline/NoteReorderDropDelegate.swift` — implements `DropDelegate`. The key method is `dropUpdated(_:) -> DropProposal?` returning `DropProposal(operation: .move)`, which tells iOS to render the move-style indicator instead of the copy badge.
- `performDrop` reads the dragged UUID-string payload via `NSItemProvider.loadObject(ofClass: NSString.self)`, hops to MainActor, and calls `FreeViewOrderStore.shared.move(_:before:in:)` inside an `easeOut(0.2)` animation.
- `validateDrop` gates on `[.text]` UTType so the delegate ignores non-text drags.

`freeBoardGrid` swapped its `.dropDestination(for: String.self) { items, _ in … }` for `.onDrop(of: [.text], delegate: NoteReorderDropDelegate(…))`. The `.draggable` source side is unchanged.

**Tests:** 95/95 still passing.

**End-to-end:** Long-press a card, drag onto another, release — card moves into place with no green-plus badge during the drag.

### Phase E.4.7 — Rounded drag-lift preview (added this round)

iOS's long-press lift preview was rectangular even though the card itself has rounded corners — `.clipShape` only affects the rendered card, not the drag system's lift preview. Fix is to declare the preview shape explicitly via `.contentShape(.dragPreview, _:)`:

```swift
KeepCard(note: note)
    .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 10, style: .continuous))
    .draggable(note.id.uuidString) { … same shape on the preview view … }
```

`ContentShapeKinds.dragPreview` is the iOS 17+ knob for "what shape should iOS use when clipping the drag-lift preview." Both the source (in-place lift) and the explicit drag preview view now carry the same `RoundedRectangle(cornerRadius: 10)`.

**Tests:** 95/95 still passing.

**End-to-end:** Long-press any Free-Board card → the lifted halo follows the card's rounded outline instead of showing as a sharp-cornered white rectangle.

### Phase E.4.8 — Live reorder during drag (added this round)

Reorder used to commit only on drop release — the user could see the lifted preview move with their finger, but the underlying grid didn't reflow until release. The fix moves the reorder out of `performDrop` and into `dropEntered`, which fires the moment the drag enters another card's hit zone:

- **`DragSessionStore.shared`** (`@Observable`) — caches the dragged note's UUID so subsequent `dropEntered` events during the same drag react synchronously. Without this, every per-card hover would re-await `NSItemProvider.loadObject(...)` and the reflow would stutter.
- **`NoteReorderDropDelegate.dropEntered`** — fast path reads from `DragSessionStore.shared.draggingNoteId`; slow path (first hover of a drag) loads from the item provider, populates the store, then triggers the move. Either way, the move is wrapped in `withAnimation(.easeOut(0.18))` so the surrounding cards animate into place.
- `performDrop` now does almost nothing — clears `DragSessionStore.shared.draggingNoteId` and returns true. The actual reorder already happened.

`dropUpdated` still returns `DropProposal(operation: .move)` from Phase E.4.6, so the `.copy` "+" badge stays gone.

**Tests:** 95/95 still passing — the change is in delegate timing, not order semantics, so `FreeViewOrderStoreTests` covers the underlying behavior unchanged.

**End-to-end:** Long-press a card on Free Board → drag → as you pass over each other card, the cards underneath shift to make room *while* you're still dragging. Release to drop in place.

### Phase E.4.9 — `.onDrag` for synchronous drag-start hook (added this round)

Phase E.4.8's live reflow wasn't actually working. Two reasons, both fixed here:

**1. `dropEntered`'s async load was racing the drag.** It tried to read the dragged UUID via `NSItemProvider.loadObject(ofClass:)`, but iOS often defers item-data resolution until drop time — so during the drag the load never completed and `DragSessionStore.draggingNoteId` stayed `nil`. No live reflow.

**2. `performDrop` had no fallback.** When `dropEntered`'s async load failed, Phase E.4.8's `performDrop` just cleared the session — the actual reorder never ran. Drops appeared to do nothing.

**Fix.**
- Switched the source side from `.draggable(_:preview:)` (whose payload is an `@autoclosure` and can't carry side effects) to `.onDrag(_:preview:)` (whose data closure runs **at drag start**). That closure now sets `DragSessionStore.shared.draggingNoteId = note.id` synchronously before returning the `NSItemProvider`.
- `NoteReorderDropDelegate.dropEntered` reads from the store synchronously — no async, no race. If the drag enters this card and the session has a dragging id, move immediately under `withAnimation(.easeOut(0.18))`.
- `performDrop` regained a fallback move: if a dragging id is set and the user drops directly on a card the live reflow didn't catch, the move is applied on release. Then it clears the session.

**Tests:** 95/95 still passing — the change is in the drag-start mechanism and async timing, not the underlying reorder semantics that `FreeViewOrderStoreTests` covers.

**End-to-end:** Long-press a card → cards underneath actually shift in real time → drop on an empty area or on another card → the dragged card lands in the position the live reflow advertised.

### Phase E.5 — Default Today view + Free-first sub-toggle (added this round)

Two small Settings/UX adjustments.

**1. Default Today view picker.** New `Services/AppPreferencesStore.swift` (`@Observable` singleton, `UserDefaults`-backed) exposes `defaultTodayView: TimelineViewMode`. Settings → **Today** section gets a `Picker` row that flips the value between Timeline and Board (with their SF Symbols). Saved value survives app relaunch; the Today tab reads it as the initial state for `TimelineScreen.viewMode`.

Distinct from `ThemeStore` and `NoteTypeStyleStore`, which cover *visual* preferences — `AppPreferencesStore` is for *behavioral* defaults.

**2. Board sub-toggle reordered to Free / Stack / Group.** Free is the most-used arrangement (and the default), so it now sits in the first slot of the segmented control instead of being tucked at the right end. Updated:
- `BoardLayoutMode.allCases` declaration order: `.free` → `.stacked` → `.grouped`.
- `BoardLayoutModeTests.declaredOrderIsStable` updated to assert the new sequence.

**Tests:** 95/95 still passing.

**End-to-end:**
- *Default view:* Settings → Today → tap **Default view** → pick **Board** → close Settings → reopen the app → Today opens in Board.
- *Reorder:* Today → Board → segmented sub-toggle now reads **Cards / Stack / Group** left-to-right.

### Phase E.5.1 — "Free" → "Cards" rename (added this round)

User feedback: "Free" didn't communicate what the layout *is*. Renamed to **Cards** across the codebase for consistency.

**User-facing changes**
- The Board's first segmented option now reads **Cards** instead of Free.

**Code changes**
- `BoardLayoutMode.free` → `BoardLayoutMode.cards`. Title string updated. Comments updated.
- `Services/FreeViewOrderStore.swift` → `Services/CardsViewOrderStore.swift` (file + type rename). Doc comment carries a "renamed from FreeViewOrderStore" note for git-blame/grep continuity.
- `DailyCadenceTests/Services/FreeViewOrderStoreTests.swift` → `CardsViewOrderStoreTests.swift` (file + type rename, all `FreeViewOrderStore()` instantiations updated).
- `TimelineScreen.swift`: `freeBoardGrid` → `cardsBoardGrid`, `freeViewOrderBarVisible` → `cardsOrderBarVisible`, `boardLayout: .free` → `.cards`.
- `NoteReorderDropDelegate.swift`: `FreeViewOrderStore.shared` → `CardsViewOrderStore.shared`; doc comments updated.
- `BoardLayoutModeTests.declaredOrderIsStable` updated to expect `[.cards, .stacked, .grouped]`.

`PhotoCropAspect.free` is **not** renamed — it's a separate enum where "free" is the right word ("no aspect lock").

**Tests:** 95/95 still passing.

**End-to-end:** Today → Board → first chip is now **Cards** (was Free); same drag-to-reorder behavior.

### Phase E.5.2 — First tab mirrors the default view (added this round)

Once the user has chosen a default Today view, the bottom tab bar's first slot reads that choice — **Timeline** with `list.bullet` or **Board** with `square.grid.2x2` — instead of the static "Today" label.

- `Navigation/RootView.swift` — `tabItems` overrides the `.today` slot's title + icon from `AppPreferencesStore.shared.defaultTodayView`. Reading the preference inside `body` registers `RootView` as an observer, so changing the default in Settings updates the tab live (no relaunch needed).
- `RootTab.today.title` / `.systemImage` are kept as fallbacks/historical defaults but are unused for the active label since the override covers all cases.

**Tests:** 95/95 still passing.

**End-to-end:** Settings → Today → **Default view** → Board → close Settings → bottom tab's first slot now reads **Board** with the grid icon. Switch back to Timeline → tab updates immediately.

### Phase E.5.3 — Persistent FAB with `.contentMargins` clearance (added this round)

User flagged that the FAB was covering the bottom card when fully scrolled. We tried two iterations of "hide on scroll-down, show on scroll-up" (Material-style) before settling on the **iOS-native** answer: keep the FAB persistent and reserve enough scroll-content buffer that the last card never lands underneath it.

**The native API:** iOS 17+'s `.contentMargins(_:_:for:)` on `ScrollView` is designed for exactly this — reserves space at an edge of the **content** without affecting the visible scroll bounds. Apple Mail, Apple Reminders, Google Keep iOS, etc. all keep their FAB-like buttons persistent and rely on bottom content insets.

```swift
ScrollView { … }
    .contentMargins(.bottom, 120, for: .scrollContent)
```

120pt covers the FAB's 56pt frame + 16pt bottom padding + ~48pt of breathing room for the level-2 shadow.

**Why we backed out of hide-on-scroll.** Two reasons:
1. The pattern is more Material Design (Android) than iOS-native — most modern iOS apps don't do it.
2. The implementation kept needing edge-case patches (rubber-band bounce-back at the content end re-revealed the FAB; freezing state in the bottom region was its own hack). The cleaner architectural answer is to take the FAB out of the scroll's interactivity surface entirely.

The earlier draft's `onScrollGeometryChange` listener, `ScrollSnapshot` struct, `isFABVisible` / `lastScrollY` state, and the FAB's `opacity`/`scaleEffect`/`offset`/`allowsHitTesting` modifiers were all removed.

**Tests:** 95/95 still passing.

**End-to-end:** Today → scroll all the way to the last card → there's a clear 48pt gap between the bottom of the last card and the FAB's top edge. No overlap, no hide-on-scroll friction.

### Phase E.5.4 — Default view leads the segmented toggle (added this round)

User flagged that picking Board as the default made the bottom-tab icon flip but the in-screen segmented toggle still showed **Timeline | Board** with Timeline first. The toggle now puts the default first:

- **Default = Timeline** → toggle is **Timeline | Board** (existing behavior).
- **Default = Board** → toggle is **Board | Timeline**.

`TimelineScreen.orderedViewModes` reads `AppPreferencesStore.shared.defaultTodayView` inside `body`, so flipping the default in Settings re-orders the segmented control live.

**Tests:** 95/95 still passing.

**End-to-end:** Settings → Today → **Default view** → Board → close Settings → in-screen toggle now reads **Board | Timeline** left-to-right (matching the bottom tab's Board label).

### Phase E.5.5 — Drag visual feedback (added this round)

User reported the Cards-layout drag-to-reorder feels inconsistent — works, but hard to tell when. Two visual additions to clarify what's happening, without changing the underlying gesture mechanics:

**1. Source card fades to ~0.35 opacity while dragging.** Immediately confirms the long-press registered, and removes the visual confusion of a "ghost" source card being rendered in the same column as the floating drag preview during live reflow.

**2. Live drop target outline.** Whichever card the finger is over gets a 2pt sage-tinted border (uses the user's primary theme color). Set via `DragSessionStore.currentDropTargetId` on `dropEntered`, cleared on `dropExited`. Tells the user *exactly* where the drop will land before they release.

Implementation:
- `DragSessionStore` extended with `currentDropTargetId: UUID?` plus an `endSession()` helper that clears both ids.
- `NoteReorderDropDelegate.dropEntered` sets `currentDropTargetId = targetNote.id` (in addition to triggering the move).
- `NoteReorderDropDelegate.dropExited` clears `currentDropTargetId` if this card was the active target. **Doesn't** clear `draggingNoteId` — drag is still active and likely about to enter another card's zone.
- `NoteReorderDropDelegate.performDrop` calls `DragSessionStore.shared.endSession()`.
- `cardsBoardGrid` reads both ids inside `body` (so the cards re-render when state changes via `@Observable`), applies `.opacity(isSourceOfDrag ? 0.35 : 1)` and a conditional sage `RoundedRectangle.strokeBorder(_, lineWidth: 2)` overlay. Both transitions ride a 0.18s `.easeOut`.

**FEATURES.md updated** with the new visual contract.

**Tests:** 95/95 still passing — visual feedback only, no model changes.

**End-to-end:** Long-press a card → it fades to half-opacity, lifted preview floats with finger → as you pass over other cards, each one in turn outlines in sage → release → fade clears, outline clears, card lands in the highlighted slot.

### Phase E.5.6 — Cascade guard + stale-session reset (added this round)

User saw two issues with drag-to-reorder when dropping precisely on a target card: (1) the dropped card sometimes "went back" to its previous position, and (2) the source's faded state persisted after release. Both come from structural limits of SwiftUI's `.onDrag` / `.onDrop` system.

**1. `dropEntered` cascade guard.** During live reflow, cards animate to new positions. The user's stationary finger ends up over different cards as the layout shifts, each firing another `dropEntered` and another move — the dragged card "bounces" through positions before the user releases.

`DragSessionStore.lastMoveTargetId` now records which target we most recently committed a move *toward*. `NoteReorderDropDelegate.dropEntered` skips when re-firing on the same target id, so cascades within one hover don't re-shuffle. Crossing into a new target id resets the guard so legit hover-over-new-card moves still apply.

**2. Stale-session reset at drag start.** When the user drops *precisely on* the source's drop zone, iOS filters the source out — no `performDrop` fires, our cleanup never runs, the source stays at 35% opacity until "something" clears it. We now call `DragSessionStore.shared.endSession()` at the top of every `.onDrag` closure so the *next* drag self-heals the prior one's stale state.

**Documented limitations.** Both fixes are mitigations on top of the iOS-native drag system, not full solutions. The proper fix is a custom `DragGesture` reorder (no `.onDrag` / `.onDrop` involved). Spec'd in [docs/TODO_CUSTOM_DRAG_REORDER.md](TODO_CUSTOM_DRAG_REORDER.md) — picks up in a future session.

`docs/FEATURES.md` updated with the cascade guard description and the limitations callout.

**Tests:** 95/95 still passing.

**End-to-end:** Long-press a card → drag onto another card → release → moves cleanly without bouncing through intermediate positions. If the move was glitchy and source stayed faded, starting another drag resets state immediately.

### Phase E.5.7 — Custom `DragGesture` reorder (added this round)

The Cards-layout reorder is rewritten on a single `LongPressGesture(0.4).sequenced(before: DragGesture(coordinateSpace: .named(...)))` chain owned by `cardsBoardGrid` — replacing the prior `.onDrag` / `.onDrop` / `NoteReorderDropDelegate` plumbing and the patches layered on it through E.5.6. We now own hit-testing, lifecycle, and the floating preview, which cleanly resolves the three structural limits called out in [docs/TODO_CUSTOM_DRAG_REORDER.md](TODO_CUSTOM_DRAG_REORDER.md).

**Why this was overdue.** The iOS drag-and-drop system gave us no `onEnded` when the drop landed outside any registered target, fired `dropEntered` cascades as cards reflowed under a stationary finger, and offered no cancel-on-empty semantics. E.5.6's `lastMoveTargetId` and `endSession()` patches mitigated 2/3 of those, but the in-flight session could still leak past a single drag (source-fade-stuck) and dropping on empty always committed.

**Architecture**
- `Services/DragSessionStore.swift` — rewritten around a `DragSession` struct (source `noteId`, `currentLocation`, `grabOffset`, `preDragOrder` snapshot, `lastTargetId`) plus a `cardFrames: [UUID: CGRect]` hit-test table. New methods: `beginSession(...)`, `updateLocation(_:in:)`, `endDrag(finalLocation:in:)`. Old `draggingNoteId` / `currentDropTargetId` are kept as computed projections so the source-fade and drop-target outline visuals (E.5.5) work unchanged. Medium haptic on drag-start, light haptic on commit.
- `Services/CardsViewOrderStore.swift` — added `restore(_:)` so the gesture can revert to the snapshot when the user releases over empty space.
- `Features/Timeline/CardFramePreferenceKey.swift` — new `PreferenceKey` mapping `[UUID: CGRect]`. Each card publishes its frame in the grid's named coord space via a `GeometryReader` background.
- `Features/Timeline/TimelineScreen.swift`'s `cardsBoardGrid` — `.gesture(reorderGesture(...))` per card; `.coordinateSpace(name: cardsGridCoordinateSpace)` on the grid; `.onPreferenceChange(CardFramePreferenceKey.self)` syncs frames into `DragSessionStore.cardFrames`; `.overlay` renders a duplicate `KeepCard` at the finger position offset by the grab point so the card stays "in hand" instead of jumping to be centered on the finger.
- `Features/Timeline/NoteReorderDropDelegate.swift` — **deleted**. No longer referenced.

**Gesture mechanics.** `.updating($dragGestureBuffer)` is used (not `.onChanged`) because `SequenceGesture<LongPressGesture, DragGesture>.Value` isn't `Equatable`. The `@GestureState` buffer is an unused `Bool` — all real state lives in `DragSessionStore`; side-effects from the closure are how the store stays in sync. First `.second(true, drag?)` callback initializes the session (captures grab offset + pre-drag order snapshot); subsequent callbacks call `updateLocation`. `onEnded` extracts the final location from the value and calls `endDrag`.

**End-of-drag classification**
| Path | Final state | Haptic |
| --- | --- | --- |
| Released over a card | Commit current (live-reflowed) order | Light |
| Released over empty space | Restore pre-drag snapshot via `CardsViewOrderStore.restore(_:)` | None |

**Tests (98/98, +3 this round)**
- `restoreReplacesCustomOrderWithSnapshot` — explicit revert path: pre-existing custom order, mid-drag move, restore returns to pre-drag.
- `restoreEmptySnapshotEqualsReset` — guards that a drag-cancel from a no-prior-custom-order state correctly clears `customOrder` instead of locking in the mid-drag move.
- `dragCommitOnTargetMovesExactlyOnce` — re-firing the same `move(...)` is idempotent (mirrors the gesture's `target.id != session.lastTargetId` cascade guard at the store layer).

**Acceptance criteria from the TODO** — all satisfied:
- ✅ Dropping precisely on a card commits, no fade-stuck state (we always call `endDrag` from `onEnded`).
- ✅ Dropping on empty space reverts (`restore(snapshot)`).
- ✅ No `dropEntered` cascade — moves only fire on different `lastTargetId`, and the gesture system doesn't fire spurious enter callbacks at all.
- ✅ Existing `CardsViewOrderStoreTests` still pass.
- ✅ +2 new tests (we landed +3) covering the revert and commit-once semantics.
- ✅ `docs/FEATURES.md` updated to drop the limitations caveats.

**Tradeoff carried.** We lose iOS's auto-rendered drag-lift preview; we render our own duplicate card via the grid's `.overlay`. The custom preview is `.scaleEffect(1.03)` with a soft `.shadow(...)` so the lifted feel is preserved (and arguably nicer — we now own the spring on release). Net code change is roughly neutral after deleting `NoteReorderDropDelegate.swift` and the `.onDrag` boilerplate.

**End-to-end:** Long-press a card → haptic → card fades, floating preview appears at the finger → drag → cards reflow live as the finger crosses into different targets → release on a card → light haptic, lands in the highlighted slot. Release on empty space → snaps back to the pre-drag order. Same drag again, no stale state.

### Phase E.5.8 — Lift confirmation on long-press (added this round)

User feedback on Phase E.5.7: the long-press → drag transition wasn't visually obvious — the medium haptic fired, but the card didn't change until the drag actually moved, so it was easy to be unsure whether you'd held long enough. Adds a dedicated **lifted** state distinct from active dragging.

**The new three-state visual contract for the source card**
| State | Trigger | Look |
| --- | --- | --- |
| At rest | Default | Opacity 1, scale 1, no shadow |
| **Lifted** | Long press completes (~0.4s), drag hasn't moved yet | Opacity 1, **scale 1.04**, soft shadow (black @ 0.18 / r12 / y6), `zIndex(1)`, medium haptic |
| Dragging | First drag delta after the lift | Opacity 0.35, scale 1, no shadow (floating preview takes over) |

Animations: `.spring(response: 0.28, dampingFraction: 0.7)` on `isLifted` (pop feel); `.easeOut(0.18)` on `isSourceOfDrag` (smooth fade hand-off to the floating preview).

**`DragSessionStore` changes**
- Added `liftedNoteId: UUID?` — the card whose long press has completed but whose drag hasn't started moving.
- New `liftSource(noteId:)` method — idempotent across repeat calls, fires the medium-impact haptic.
- `beginSession(...)` no longer fires the haptic (lift owns it now); it clears `liftedNoteId` as it transitions into the active drag.
- `endDrag(...)` clears `liftedNoteId` at the top — covers the long-press-then-release-without-moving case where there's no active session to clear.
- `cancelSession()` also clears `liftedNoteId`.

**Gesture wiring (`TimelineScreen.reorderGesture`)**
- The single `case .second(true, let drag?)` branch was split into a switch:
  - `.first(true)` → `liftSource(noteId:)`
  - `.second(true, nil)` → `liftSource(noteId:)` (idempotent — fires when the gesture transitions before the drag updates)
  - `.second(true, let drag?)` → existing init-or-update logic
- `cardsBoardGrid` reads `liftedId` and applies the lifted visual when it matches the card's id (and the card isn't already the active drag source).

**Tests:** 98/98 still passing. No new tests this round — the lift state is pure UI plumbing on top of the gesture's value stream; the underlying reorder semantics covered by `CardsViewOrderStoreTests` are unchanged.

**End-to-end:** Long-press a card → at ~0.4s the card pops up (scale + shadow) with a medium haptic — clear "drag mode active" cue. Drag → card fades, floating preview takes over. Release → light haptic if dropped on a card, snap back to pre-drag if dropped on empty.

### Phase E.5.9 — Double-tap-to-collapse on expanded Stack (added this round)

Quick shortcut on top of the existing "Collapse ↑" pill. In Stack-mode, when a stack is expanded, double-tapping anywhere in the section collapses it.

**Implementation** — `Features/Timeline/StackedBoardView.swift`'s `ExpandedColumnSection`:
- `.contentShape(Rectangle())` on the section's outer `VStack` so the gaps between cards become part of the tappable surface (without it, only the cards themselves would catch taps).
- `.onTapGesture(count: 2) { onCollapse() }` calls the same closure the pill uses, so the toggle animation (`spring(response: 0.42, dampingFraction: 0.82)`) is shared.

**Compatibility note.** The expanded section can contain media cards (`KeepCard` for a `.media` note), which carry their own single-tap → fullscreen viewer. Double-tap on the parent introduces a small (~250ms) "is it a double?" disambiguation delay on those single taps — standard iOS behavior (Apple Photos uses the same pattern). Acceptable; the shortcut is worth more than the lost millis.

**Tests:** 98/98 still passing. No new tests — pure UI gesture, no model state.

**End-to-end:** Stack mode → tap a stack → cards unfurl → double-tap any card or gap → stack collapses.

### Phase E.5.10 — Media as a first-class `NoteType` (added this round)

Bare photo / video notes now auto-tag as `NoteType.media` instead of `.general`. Resolves the long-standing awkwardness in the Group / Stack layouts where photos got stuffed into the "General" catch-all alongside genuine generic text notes — a media note is *inherently* media, not a category.

**Design framing.** Conceptually we now distinguish two flows:
- **Bare media logging** ("here's a photo") → `MediaNoteEditorScreen`, no type picker, auto-tags `.media`.
- **Semantic context with media** ("here's my workout, with a photo of it") → text note with an attached image. The canonical pattern, but it depends on inline-attachments-in-text-notes which is a deferred follow-up. Until then, captioned media notes carry their context via the optional caption field.

Forcing the user to pick a type for a bare photo was friction without value. Removing it sharpens the data model: `NoteType` is now strictly about **what kind of thing this note records**, with a clean Media bucket carved out.

**Changes**
- `Models/NoteType.swift` — new `.media` case (declared last in `allCases` so existing pickers' visual order is preserved). Pigment `Color.DS.periwinkle`, soft `Color.DS.periwinkleSoft` (unused tokens that read as a soft media-y violet, no conflict with the warm-toned existing types). Icon `photo.on.rectangle` (matches the FAB menu's "Photo or Video" affordance for visual continuity).
- New `NoteType.textEditorPickable` static accessor — returns `allCases` minus `.media`. The text-note editor's type picker uses this so a text note can't accidentally be tagged Media. Group / Stack views, Settings → Note Types, and the per-type style store all keep using `allCases`, so Media participates in color overrides and section rendering normally.
- `Features/NoteEditor/NoteEditorScreen.swift` — type-picker `ForEach(NoteType.allCases)` swapped for `ForEach(NoteType.textEditorPickable)`.
- `Features/NoteEditor/MediaNoteEditorScreen.swift` — the hardcoded `type: .general` on save flipped to `type: .media`. The screen never had a type-picker UI (Phase E.4.1 removed it); this just lands the auto-tagging at the data layer to match.
- `Features/Settings/NoteTypePickerScreen.swift` — doc comment refreshed; functionally unchanged since it iterates `allCases` (Media row appears for free).

**Tests:** 98/98 still passing. `NoteTypeStyleStoreTests` iterates `NoteType.allCases` so Media is covered for default-state, persistence, stale-id, and reset-all assertions automatically. No new tests this round — the behavior is "media notes save as type `.media` instead of `.general`," which is a one-line constant change in the editor's `save()` and a new enum case; both pieces are exercised end-to-end by the existing build + the editor's SwiftUI Preview.

**End-to-end:** FAB → "Photo or Video" → pick a photo → caption + Save → photo appears in Today, tagged Media (periwinkle dot in card chrome). Switch to Board → Group → new "Media" section appears with the photo. Switch to Stack → photo lives in its own Media stack alongside Workout / Meal / etc. stacks.

### Phase E.5.11 — Horizontal scroll rails for Group view (added this round)

The Group Board sub-mode used to render each `NoteType` section as a 2-col vertical `LazyVGrid` — a busy type pushed every other type far down the screen. Switched each section to a horizontal scroll rail (Apple Music / App Store pattern) so all sections are visible at a glance and deep types just swipe within the rail.

- Each section's body is now a `ScrollView(.horizontal)` of `KeepCard`s.
- Cards size to ~55% of the viewport via iOS 17's `.containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width * 0.55 }`. Two fully visible + a peek of the third — clear "more to swipe" affordance, adapts to phone size.
- `.scrollTargetLayout()` + `.scrollTargetBehavior(.viewAligned)` snap flicks to card boundaries.
- Card heights stay intrinsic (capped at the existing `KeepCard.maxHeight`); section height = tallest card.

Carves out a meaningfully different role from Stack ("compact glance per type") and Cards ("free 2-col masonry"): Group is now "all types visible, swipe each row to browse deep types."

### Phase E.5.12 — Drag scroll/lift regression fix (added this round)

Jon reported on test build: after creating a new note, touching any card on Cards Board immediately entered drag mode and the page wouldn't scroll. Root cause was a **stale gesture state across the editor sheet's lifecycle** combined with `.gesture()`'s exclusive touch claim conflicting with the parent ScrollView's pan recognizer.

**Four fixes, layered:**

1. **`.simultaneousGesture` instead of `.gesture`** on the per-card reorder gesture. With `.gesture`, our `LongPressGesture.sequenced(before: DragGesture(minimumDistance: 0))` exclusively claimed the touch, blocking the ScrollView's pan recognizer. `.simultaneousGesture` lets both track in parallel; `LongPressGesture`'s built-in `maximumDistance` (~10pt) still fails it cleanly when the user starts a scroll, so we don't accidentally lift on every swipe.
2. **`.scrollDisabled(isCardReorderActive)`** on the outer ScrollView, gated on `liftedNoteId != nil || activeSession != nil`. Once a card is actually lifted or being dragged, the page freezes so it doesn't skid under the gesture. Auto-releases when `endDrag` clears both ids.
3. **`onDismiss: { DragSessionStore.shared.cancelSession() }`** on both the text-note and media-note editor sheets. Sheet presentations interrupt the touch sequence in ways that left our `LongPressGesture`'s internal state half-completed; the next touch on return was being misinterpreted as the tail of a still-tracked long-press, instantly re-firing the lift. Resetting on dismiss is a clean baseline.
4. **Removed the parallel `.first(true)` lift trigger** from the gesture switch. We were calling `liftSource` on both `.first(true)` and `.second(true, nil)` — the latter is the more reliable post-success transition (the explicit "long press done, drag pre-start" callback). Dropping the redundant `.first(true)` branch eliminates a path where SwiftUI was firing it before the duration was actually met (notably right after sheet dismissal).

**Tests:** 98/98 still passing. The bug was state-management in the gesture's lifecycle hooks, not in the underlying reorder semantics, so existing `CardsViewOrderStoreTests` cover the right thing without modification.

**End-to-end retest:** add a text or media note → return to Today → touch a card briefly → page scrolls normally. Long-press a card → at ~0.4s, lift visual + haptic fire. Drag → reorder. Drop → commit / revert.

### Phase E.5.13 — Toolbar Menu for Board sub-mode (added this round)

The Cards / Stack / Group sub-picker used to live in a second segmented row that appeared below the Timeline | Board toggle whenever Board was active — about 50pt of vertical chrome, only there to host a setting users mostly set once. Moved it to a top-right toolbar `Menu` (Apple Files / Photos pattern), which is the established iOS idiom for "primary view discriminator + view variants."

- New `boardSubModeMenu` view in `TimelineScreen.swift` — `Menu` containing a `Picker(selection: $boardLayout)` over `BoardLayoutMode.allCases`. Picker-inside-Menu auto-renders checkmarks for the active option, so we get the native "current selection has a checkmark" affordance for free.
- The Menu's icon mirrors the active sub-mode (`square.grid.2x2` / `square.stack.3d.up` / `rectangle.grid.2x2.fill`) so the user has a glance-level cue of which layout is current without opening the Menu.
- Menu only renders when `viewMode == .board` (Timeline has no sub-modes). Mounts/unmounts with an `.opacity.combined(with: .scale(scale: 0.85))` transition so it pops in/out cleanly when toggling primary views.
- The inline `boardLayoutToggle` row was deleted, along with its segmented control + the conditional padding adjacent to it. The remaining `segmentedToggle` (Timeline | Board) now uses one consistent bottom padding (12pt when the Cards-order reset pill follows; 16pt otherwise).
- Added `.animation(.easeOut(duration: 0.18), value: boardLayout)` next to the existing `viewMode` animation so picking a new sub-mode from the Menu reflows the content with the same easing as the primary toggle.
- `BoardLayoutMode.swift`'s doc comment refreshed to describe the new Menu-based picker; the segmented-control historical note remains for context.

**Trade-off accepted.** Switching sub-modes is now 2 taps (open Menu → tap option) instead of 1. Cards/Stack/Group is a setting users set occasionally rather than every visit, so the saved chrome wins. If we ever decide rapid sub-mode switching is a hot path, we can add a long-press-on-Board affordance for direct cycling.

**Tests:** 98/98 still passing. No new tests this round — the change is pure UI plumbing with no model-layer state.

**End-to-end:** Today → Board → top-right header gains a small grid icon → tap → Menu pops with Cards / Stack / Group rows (checkmark on active) → tap one → content reflows to the new layout. Switch back to Timeline → the icon disappears.

### Phase E.5.14 — Type-indicator polish on cards (added this round)

The dot + label that identifies a note's `NoteType` was visually a footnote rather than a header — a 7-8pt dot and a 9-10pt label (grey on Timeline cards) made the user read the title first and the tag second. Bumped sizing on both card surfaces and unified the color treatment so the tag reads as the visual anchor.

**KeepCard (Board view) `head`:**
- Dot 7pt → 9pt
- Label 9pt → 11pt (still bold, still `type.color`)
- Spacing 6pt → 7pt
- Bottom padding 2pt → 4pt (more separation before the title row)

**TypeBadge (Timeline `NoteCard`):**
- Dot 8pt → 10pt
- Label 10pt → 11pt
- **Label color flipped from `Color.DS.fg2` (grey) → `type.color`** — biggest perceptual change. Brings Timeline into parity with KeepCard's already-colored treatment so a Workout note reads as "WORKOUT" before the eye even lands on the title.
- Spacing 8pt → 10pt to match the larger dot.
- Time still in `fg2` mono — it's secondary info that doesn't need the colored treatment.

**Why this restraint.** A pill / capsule treatment (Apple Mail thread label style) would also work and was considered, but adding solid backgrounds on every card would clash with the existing per-type color tint we apply to `KeepCard` (the cards are already lightly tinted by `type.color` at 0.333 opacity). A bigger colored dot + label uses contrast and size for emphasis without doubling up on background fills.

**Tests:** 98/98 still passing. No new tests this round — pure visual sizing + color, no model state.

**End-to-end:** Today → either Timeline or Board → tag is now the strongest readable element on each card after the title; type identity registers at a glance, especially in Board view at masonry density.

### Phase E.5.15 — Pin + Delete on cards (added this round)

Two per-card actions land together: **pinning** (promote a note to a Pinned section at the top of every Board sub-mode) and **deleting** (with a confirmation dialog). Modeled on Google Keep + Apple Notes: a visible glyph for the high-frequency action (pin) plus a `.contextMenu` (long-press) for the lower-frequency / dangerous one (delete).

**Why both surfaces.** Pin is one tap from anywhere, often, and deserves a dedicated affordance. Delete is destructive — burying it inside a long-press menu is exactly right (Apple uses this pattern in Notes, Mail, Photos). Both routes flow through the same store methods, so the surface is consistent under the hood.

**Why a visible pin glyph (not swipe-to-pin).** Swipe is a *list* pattern (Apple Mail, Notes list view). For card UIs Apple uses always-visible icons (Notes gallery, Google Keep) or context menus (Photos library). Swipe-on-masonry would also conflict with Group view's horizontal-scroll rails. The visible glyph wins on consistency across all three sub-modes and zero gesture conflicts.

**Gesture coexistence.** Cards in the Cards Board layout still long-press for drag-to-reorder. The `.contextMenu` long-press and our `LongPressGesture(0.4).sequenced(before: DragGesture)` reorder gesture *naturally arbitrate*: hold + immediately move → drag (the movement disambiguates), hold + stay still past ~0.5s → context menu opens. Same Apple Photos pattern. No custom timing code needed; SwiftUI's built-in arbitration handles it.

**Model + store changes**
- `Services/PinStore.swift` — new `@Observable` singleton holding a `Set<UUID>` of pinned note ids. Methods: `isPinned(_:)`, `pin(_:)`, `unpin(_:)`, `togglePin(_:)`, `forget(_:)` (called on delete to clear ghost references). In-memory only for Phase 1; Supabase persistence is a Phase F follow-up.
- `Services/TimelineStore.swift` — added `delete(noteId:)`. Removes the note + calls `PinStore.shared.forget(_:)` so a deleted note never leaves a "still pinned" ghost id behind.
- `MockNote` is intentionally NOT mutated — pin state is a separate concern (single-column boolean in the future schema), kept off the value type so the model stays a snapshot.

**UI changes**
- `DesignSystem/Components/PinButton.swift` — new component. 13pt SF Symbol (`pin` outline / `pin.fill` in honey-yellow) inside a 32pt hit area. Outline is rotated -30° when unpinned for a subtle visual differentiator beyond color.
- `KeepCard.swift` + `NoteCard.swift` — both gain a top-trailing `PinButton` overlay (gated on `showsActions` / `noteId != nil`) plus a `.contextMenu { Pin/Unpin · Delete }`. Media cards layer a thin `.ultraThinMaterial` backdrop circle behind the glyph so it stays readable over any photo. Both cards expose an `onRequestDelete` callback so deletion is a screen-level concern (the screen owns the confirmation dialog).
- `TimelineScreen.swift` — adds `pendingDeleteId: UUID?` state + a `.confirmationDialog("Delete this note?" / "This can't be undone.")` with destructive **Delete** + cancel **Keep**. The screen's `requestDelete(_:)` closure is threaded into every card call site (cardsBoardGrid, groupedView, StackedBoardView, timelineView).
- `StackedBoardView` extended to forward `onRequestDelete` to its `CollapsedStackCell` + `ExpandedColumnSection` children, which thread it down to each `KeepCard`.

**Pinned section rendering**
- New `pinnedSection` view in `TimelineScreen` mounted at the top of `boardContent` whenever `!pinnedNotes.isEmpty`.
- Header: uppercase **PINNED** + honey `pin.fill` + count.
- Layout per sub-mode:
  - **Cards / Stack** → 2-col flat masonry of pinned cards (Stack mode's per-type stacks live below; pinned items are pulled out and shown plainly so they're immediately readable).
  - **Group** → horizontal scroll rail matching the per-type rails' visual rhythm (Phase E.5.11 pattern).
- The sub-mode layouts (`cardsBoardGrid`, `groupedNotes`, etc.) now operate on `unpinnedNotes` so a pinned note never appears twice.
- **Drag-to-reorder is intentionally not wired for the pinned section.** Pinned items keep chronological order; the user unpins + re-pins to rearrange. Matches Apple Notes' pinned-section behavior.

**Tests (106/106, +8 this round)**
- `PinStoreTests` (6) — default empty, toggle flips, idempotent pin/unpin, forget removes id, multiple pins coexist.
- `CardsViewOrderStoreTests` gained 2 new tests covering `TimelineStore.delete(_:)` — removal of the note + no-op on unknown ids.

**End-to-end:** Tap the pin glyph on any card → glyph fills honey-yellow → card moves into the Pinned section at top of the current Board sub-mode (Cards/Stack as a 2-col masonry, Group as a horizontal rail). Long-press a card → context menu pops with Pin/Unpin + Delete → tap Delete → "Delete this note? · This can't be undone." dialog → confirm → card animates out, gone. Long-press + drag still reorders unpinned cards in Cards layout — gestures arbitrate cleanly.

### Phase E.5.16 — Pin glyph as status indicator only (added this round)

E.5.15 shipped the pin glyph on every card (both pinned and unpinned). Visually busy — every unpinned card carried an outline pin icon as permanent chrome. Modern card UIs treat the pin as a **state indicator, not a button**: Apple Notes, Apple Mail's flag column, iMessage pinned-conversation header all hide the glyph on un-flagged items and show only the filled state on flagged ones.

**The change:**
- `KeepCard.swift` + `NoteCard.swift` — the pin overlay now mounts only when `isPinned` is true. Unpinned cards have zero pin chrome.
- Tapping the visible (pinned) glyph still unpins.
- Pinning an unpinned card now goes through the **`.contextMenu` Pin entry** (long-press → Pin). The context menu was already wired in E.5.15; this just makes it the canonical entry point for pinning.
- `.transition(.scale.combined(with: .opacity))` on the overlay so the glyph pops in/out smoothly when pinning state flips, rather than appearing instantly.

**Trade-off (acknowledged).** New users won't see "pin is a feature" by glancing at unpinned cards — discoverability moves to the long-press menu. For Phase 1 (Jon + wife on TestFlight), a one-line hand-off covers it; for broader release we'll add a one-shot empty-state hint or a tooltip on first launch.

**Tests:** 106/106 still passing — pure visual conditional, no model changes.

**End-to-end:** All cards land on the Today screen with no permanent pin chrome. Long-press a card → Pin → glyph appears in the corner with a scale/opacity pop, card moves to the Pinned section. Tap the glyph on a pinned card → glyph disappears, card returns to its sub-mode position.

### Phase E.5.17 — Delete confirmation: alert instead of action sheet (added this round)

E.5.15's delete confirmation used `.confirmationDialog`, which on iPhone slides up as a bottom action sheet. Action sheets are Apple's pattern for **multi-option pickers** (Mail's "Trash / Archive / Move to..."), not for binary destructive confirmations on single items. For irreversible per-item destruction Apple consistently uses the **centered `.alert`**:

- Apple Notes — "Delete Note?" → alert
- Apple Photos — "Delete Photo?" → alert
- Apple Calendar — "Delete Event?" → alert
- Apple Reminders — "Delete Reminder?" → alert

The alert pattern is more "in your face" by design, which is exactly the right vibe for an irreversible delete. Action sheets feel routine.

**Change:** one modifier swap on `TimelineScreen.swift` — `.confirmationDialog(...)` → `.alert(...)`. Same call shape (`isPresented` + `presenting:` + button closure + message closure), so the diff is essentially the modifier name and the comment. Buttons unchanged: destructive **Delete** + cancel **Keep**.

**Tests:** 106/106 still passing.

### Phase E.5.18 — Inline media in text notes (added this round)

The big one this round: a text note can now carry photos and videos *inline*, journal-app style. Previously bare media notes lived in the Media section (auto-tagged) and text notes were text-only — there was no way to attach a photo to a thought. Phase E.5.18 closes that gap with a **block-based body model** (text + media blocks in any order), a `+image` button in the editor's StyleToolbar that opens the iOS PhotosPicker, and **per-image Small / Medium / Large sizing** (Apple Notes pattern) so the user controls the visual presence.

**Why block-based, not NSTextAttachment.** SwiftUI's read-only `Text(_:AttributedString)` doesn't render NSTextAttachment images for cards — the only path to mid-paragraph inline rendering is wrapping UITextView in UIViewRepresentable for both edit and read. That's a 3+ round refactor of our existing rich-text editor (Phase E.2). The block model delivers the same user-facing journaling feel ("write, drop a photo, keep writing") with native SwiftUI components: each `.paragraph` is a `Text(AttributedString)` in cards / `TextEditor` in the editor; each `.media` is an `InlineMediaBlockView`. They stack vertically. Apple Notes / Notion / Google Keep / Bear all do this same block approach for inline media.

**Model**
- `Models/TextBlock.swift` — new `TextBlock` value type (id-stable Identifiable wrapper) + `MediaBlockSize` enum (`small` / `medium` / `large` with corresponding width fractions ~45% / ~75% / 100%).
- `MockNote.Content.text(title:body:)` — replaces `.text(title:message:)`. Body is `[TextBlock]`. A backward-compat static `text(title:message:)` constructor wraps a single AttributedString into one paragraph block so seed data, tests, and existing editor save paths keep working unchanged.
- `MockNote.timelineMessage` — flattens paragraph blocks into a single AttributedString for the dense Timeline rail (skipping inline media); the full block layout is the Board view's job.
- `MockNote.textBodyBlocks` — convenience accessor returning the body for `.text` content.

**Card rendering (`KeepCard`)**
- `textContent(title:body:)` walks the block list. Paragraph blocks render as `Text(AttributedString)`, media blocks render via the new `InlineMediaBlockView`.
- `InlineMediaBlockView` (new component) sizes the asset by `MediaBlockSize.widthFraction` of the card's content width, height proportional to clamped aspect ratio. Centered for Small/Medium, full-width for Large. Tap → fullscreen viewer (reuses `MediaViewerScreen`).

**Editor (`NoteEditorScreen`)**
- New `+image` icon in the `StyleToolbar` icon bar (Phase E.5.18 added the `onTapInsertImage` parameter; renders only when the callback is provided). SF Symbol `photo.badge.plus`, mirrors the `🖼` background icon's styling so the right side of the bar reads as a coherent "asset actions" cluster.
- Tap → iOS PhotosPicker (`.any(of: [.images, .videos])`) → on selection, `MediaImporter.makePayload` runs → `NoteDraftStore.insertMedia(payload, size: .medium)` adds a `TextBlock.media` block (after the focused paragraph + a fresh trailing paragraph for continued typing).
- New `attachmentsStrip` view below the message editor renders one row per media block in the draft body. Each row is a SwiftUI `Menu` containing a size `Picker` (Small / Medium / Large) + destructive **Remove** button. The `InlineMediaBlockView` is rendered with `isInteractive: false` so the Menu's tap-to-open captures the gesture (no fullscreen viewer collision in the editor).
- Removing the last block restores an empty paragraph so the editor keeps a cursor target.
- Errors during photo import surface inline below the strip ("Couldn't load that file…") rather than via a disruptive alert.

**Save path**
- `NoteEditorScreen.save()` serialises `draft.body` directly into `.text(title:body:)`. Empty paragraph blocks are dropped; non-empty paragraphs get leading/trailing whitespace trimmed (preserving per-run AttributedString attributes on the kept characters); media blocks pass through unchanged.

**Draft store (`NoteDraftStore`)**
- `body: [TextBlock]` is the canonical state, defaulting to a single empty paragraph (so the editor always has a cursor target).
- `focusedBlockId: UUID?` tracks which paragraph block has the cursor — used by `insertMedia(...)` to decide where to place the new media block.
- `insertMedia(_:size:)`, `removeBlock(id:)`, `resizeMediaBlock(id:to:)`, `updateParagraph(id:to:)` — public block-list mutators.
- **Single-paragraph compatibility bridge**: `message: AttributedString` is a computed property that reads/writes the first paragraph block. Lets the existing single-pane editor continue working (Phase E.5.18 ships the simpler "appended attachments" UX rather than per-block focused TextEditors). Mid-paragraph editor is a future iteration when the demand is real.
- `clear()` resets body to a single empty paragraph (alongside the rest of the draft fields).

**MockNotes**
- `MockNotes.inlineMediaDemo(payload:size:)` — opt-in helper that builds a sample text note with a `[paragraph, media, paragraph]` body. Not added to `today` so a TestFlight build doesn't ship a synthetic-looking demo card; useful for previews and a future debug menu.

**Tests (127/127, +21 this round)**
- `TextBlockTests` (9): id stability across edits, empty/paragraph/media predicates, full block round-trip through TimelineStore (paragraph-media-paragraph), backward-compat constructor wraps message into one paragraph, title-only constructor produces empty body, timelineMessage flattens paragraphs / drops media, timelineMessage returns nil for media-only or empty bodies, MediaBlockSize width-fraction order invariant.
- `NoteDraftStoreTests` (12): fresh draft starts with one empty paragraph, message bridge reads/writes first paragraph, message bridge prepends paragraph if body starts with media, insertMedia places after focused paragraph + appends trailing paragraph, insertMedia with no focus appends at end, removeBlock deletes & preserves neighbors, removeBlock restores empty paragraph if body would empty, resizeMediaBlock updates size, resize on paragraph is no-op, updateParagraph mutates text, clear resets body to single empty paragraph.
- `TimelineStoreTests` updated for the new body shape.

**End-to-end:** Tap **+** in the FAB menu → editor opens → type "Felt strong this morning" → tap the **`+image`** icon in the toolbar → PhotosPicker opens → pick a photo → photo appears as a Medium-sized thumbnail row below the text → tap the photo in the editor → Menu pops with **Small / Medium / Large / Remove** → pick Large → Save → the note shows up on the Board (Cards mode) as: title + paragraph + full-width photo, vertically stacked. Tap the photo on the card → fullscreen viewer.

**Known scope (deferred for future iteration):**
- **Mid-paragraph image insertion in the editor.** The data model supports interleaved blocks; the editor UI currently appends new media after the typed paragraph. To insert mid-paragraph would mean per-block focused TextEditors with split/merge logic — significant rework, deferred until use justifies it.
- **Drag-to-reorder blocks.** Same — data model supports it; UI doesn't yet.

### Phase E.5.18a — Inline-media editor polish (added this round)

Three asks landed together based on Jon's first pass with the inline-media editor:

1. **Couldn't add text after the image** — the editor only had one TextEditor (above the attachments strip); no way to type after a photo.
2. **Wanted crop control on insert** — using existing `PhotoCropView` (freeform + aspect presets).
3. **Wanted tap-to-view-fullscreen** — the `Menu` wrapper was capturing every tap so users couldn't preview attachments at full size from the editor.

**Trailing TextEditor (#1).**
- `NoteDraftStore.insertMedia(...)` rewritten to maintain the structural invariant `[firstParagraph?, media*, trailingParagraph]` — each new media block inserts *just before* the trailing paragraph (rather than appending media + new paragraph each time). Multi-insert keeps a single trailing paragraph.
- New `NoteDraftStore.trailerMessage: AttributedString` accessor (read/write the last paragraph) + `hasMedia: Bool`.
- New `NoteEditorField.trailer` case + `isBodyText` helper. The editor's title remains `.title`; the top messageEditor remains `.message`; the new bottom editor uses `.trailer`. StyleToolbar treats both `.message` and `.trailer` as body-text styling.
- New `trailerEditor` view in `NoteEditorScreen` — a TextEditor bound to `draft.trailerMessage`, only rendered when `draft.hasMedia` is true (hidden when there's no media so the single messageEditor isn't double-bound).
- Style apply functions (`applyMessageFont`/`Color`/`Size`) now route through a shared `transformActiveBody(_:)` helper that picks `draft.message` (first paragraph) or `draft.trailerMessage` (last paragraph) based on `lastEditedField`. Existing single-selection behavior preserved — SwiftUI's TextEditor writes its own selection into `draft.messageSelection` when focused.

**Crop-on-insert sheet (#2).**
- `NoteEditorScreen` gained `pendingCropPayload: MediaPayload?` + `pendingCropState: PhotoCropState?`.
- `importAttachment(_:)` now branches: images → stage for cropping (sheet opens); videos → insert directly.
- Crop sheet body re-uses `PhotoCropView` (already used by `MediaNoteEditorScreen`) — same freeform + 1:1 / 4:3 / 3:4 / 16:9 / 9:16 aspect presets, same corner-drag + center-drag UX, same `commitCrop()` to produce the cropped JPEG + new aspect ratio.
- Confirm builds a fresh `MediaPayload` from the cropped bytes and calls `draft.insertMedia(...)`. Cancel discards the staged image.

**Tap behavior on attachments (#3).**
- Editor's `attachmentRow` was `Menu { … } label: { InlineMediaBlockView(isInteractive: false) }` — Menu captured every tap.
- Now: `InlineMediaBlockView(isInteractive: true).contextMenu { Picker · Remove }` — **tap opens the fullscreen `MediaViewerScreen`** (Apple Photos pattern), **long-press opens the resize/remove context menu** (Apple Notes pattern). Same gesture vocabulary as inline media in cards (Phase E.5.18) so the experience is consistent everywhere.

**Bonus polish.** The previous commit's TextEditor `minHeight: 60` (down from 160) carries through — empty editor still has a clear tap target without leaving a big gap before the attachments strip.

**Tests (131/131, +4 this round)**
- `NoteDraftStoreTests`: `insertMediaPlacesBeforeTrailingParagraphAndPreservesIt`, `insertMediaAppendsTrailingParagraphWhenNoneExists`, `multipleInsertsKeepSingleTrailingParagraph`, `trailerMessageReadsLastParagraph` / `trailerMessageWritesLastParagraph`, `hasMediaReflectsBodyContents`. Replaces older insertMedia-after-focus tests that were tied to the prior insertion semantics.

**End-to-end:** Tap **+** in FAB → text editor → type "Felt strong this morning" → tap the **`+image`** icon → PhotosPicker → pick a photo → **crop sheet opens** → adjust corners + pick an aspect chip → tap **Add** → photo lands in the strip below your text → **a second TextEditor ("Add more thoughts…") appears below the photo** → type "Cooldown was great" → tap the photo → **fullscreen viewer opens** → swipe down to dismiss → long-press the photo → menu pops with **Small / Medium / Large / Remove**. Save → card renders all three blocks vertically (intro text → photo → outro text).

### Phase E.5.18b — Duplicate-text bug fix (added this round)

Jon reported: typed "my snack for today" + Enter into the message editor, tapped `+image`, picked a photo. The trailing TextEditor that appeared below the image rendered the same "my snack for today" text — duplicated in two editors.

**Root cause.** `NoteDraftStore.insertMedia(...)` ensured a *trailing* paragraph but not a *leading* one. With body `[paragraph("my snack...")]` (single typed paragraph) the logic saw the last block was already a paragraph, inserted media before it, and produced `[media, paragraph("my snack...")]`. The `message` accessor (first paragraph) and `trailerMessage` accessor (last paragraph) then resolved to the **same** block — both TextEditors rendered the same text.

**Fix.** `insertMedia` now ensures BOTH a leading and a *distinct* trailing paragraph before placing the media. Algorithm:
1. If body's first block isn't a paragraph, prepend a fresh paragraph.
2. If body's last block isn't a paragraph OR is the same block as the leading paragraph, append a fresh paragraph.
3. Insert the media just before the trailing paragraph.

The leading paragraph keeps the user's typed text intact; the trailing paragraph is a fresh empty target for the trailerEditor.

**Tests (132/132, +1 this round).**
- `NoteDraftStoreTests.insertMediaIntoSingleParagraphBodyAddsDistinctTrailingParagraph` — explicit regression test for the duplicate-text bug. Asserts `message` returns "my snack for today" and `trailerMessage` returns "" after insertMedia (different blocks, different content).
- `insertMediaIntoMediaOnlyBodyEnsuresLeadingAndTrailingParagraphs` — the prior `insertMediaAppendsTrailingParagraphWhenNoneExists` test, updated for the new behavior (leading paragraph is also prepended).

### Phase E.5.19 — StyleToolbar floating-pill redesign (added this round)

The previous StyleToolbar was a flush opaque rectangle (`Color.DS.bg2`) spanning the full width with a hairline top border — visually divided the canvas from the keyboard. Apple Notes / Mail / Reminders all moved to a **floating glass pill** in iOS 17+ (rounded RoundedRectangle backed by `.ultraThinMaterial`, inset from the screen edges). Modernized to match.

**`StyleToolbar.swift` changes:**
- Outer container: each piece (expanded panel + icon bar) is now its own RoundedRectangle (corner radius 22) backed by `.ultraThinMaterial` for the glass look — `toolbarPillBackground` view extracted for reuse.
- Horizontal inset (12pt) so the pills float free of the screen edges.
- 8pt vertical gap between expanded panel and icon bar (each reads as its own surface, like Notes' format toolbar that stacks two pills).
- Hairline border at `Color.DS.border1.opacity(0.5)` defines the pill edge against the keyboard backdrop without being heavy.
- Subtle drop shadow (`.shadow(color: .black.opacity(0.06), radius: 6, y: 1)`) for a slight lift off the keyboard.

**Bare-icon styling on glass:**
- `iconButton` (font / color / size): dropped the `Color.DS.bg1` background + border. Icons now render bare on the glass pill. Active state still fills with `Color.DS.ink` (the user can see at a glance which panel is open).
- `backgroundIcon` + `insertImageIcon`: also dropped per-icon backgrounds. Background icon shows just the swatch / photo preview circle with a thin border; insert-image icon is a bare `photo.badge.plus` glyph.
- iconBar's outer padding tightened (horizontal 14→8, vertical asymmetric→6/6) since the pill itself supplies the visual container.

**Removed:** the legacy `toolbarBackground` ZStack (flush bg2 + 0.5pt border).

**Tests:** 132/132 still passing — pure visual change, no behavior shifts.

**End-to-end:** Open the editor → keyboard rises → the styling toolbar above it is now two floating glass pills (or one when no panel is expanded) inset from the screen edges with rounded corners, translucent backdrop, soft shadow. Tap the **Aa** icon → font panel pill grows above the icon-bar pill with the same glass styling. Tap a font chip → applies. Same icons, much more modern feel.

### Phase E.5.24 — Cards-mode scroll-from-card fix via UIKit gesture bridge (added this round)

Jon reported: in Cards Board mode the page would only scroll if the pan started over empty space outside any card. Touches that started on a card never handed control back to the parent `ScrollView`'s pan recognizer.

**Root cause.** The Cards-mode reorder used SwiftUI's `LongPressGesture(0.4).sequenced(before: DragGesture(minimumDistance: 0))` attached via `.simultaneousGesture` (Phase E.5.7 / Phase E.5.12). On iOS 26 that combination still claims the touch sequence in a way that prevents the parent ScrollView's pan from engaging — `.simultaneousGesture` improved the situation but didn't fully resolve it. The arbitration happens inside SwiftUI's gesture machinery, where simultaneity with the underlying UIKit ScrollView's pan recognizer isn't reliable for this exact chain.

**Fix.** Bridge to UIKit at the proper layer. New `Features/Timeline/CardReorderRecognizer.swift` is a `UIGestureRecognizerRepresentable` (iOS 18+ first-class SwiftUI ↔ UIKit gesture bridge) wrapping a single `UILongPressGestureRecognizer`:

- `cancelsTouchesInView = false` — the recognizer doesn't swallow touches on their way to the underlying view hierarchy.
- A `Coordinator: NSObject, UIGestureRecognizerDelegate` returns `true` for `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` — UIKit lets the ScrollView's pan and our long-press track the same touch sequence in parallel.
- Single recognizer instead of a sequenced chain. After the press duration elapses the recognizer transitions to `.began` (the lift) and then reports finger movement via `.changed` (the drag) until release (`.ended`) — one state machine, no SwiftUI value-type discrimination across `.first(true)` / `.second(true, _)` callbacks.
- Locations are reported in the cards-grid named coordinate space directly via `context.converter.location(in: coordinateSpace)` — the touch coords are already in the space `cardFrames` are stored in, no manual conversion.

**TimelineScreen** loses `@GestureState dragGestureBuffer` and the `reorderGesture(for:allNotes:)` helper. The card now attaches the recognizer with `.gesture(CardReorderRecognizer(coordinateSpace: .named(Self.cardsGridCoordinateSpace), minimumDuration: 0.4) { event in handleReorderEvent(event, …) })`. The new `handleReorderEvent(_:for:allNotes:)` switch maps `.began` / `.changed` / `.ended` / `.cancelled` to `DragSessionStore` calls.

**DragSessionStore** gains a `liftLocation: CGPoint?` field and `liftSource(noteId:at:)` now captures it. On the first `.changed` after a lift, `handleReorderEvent` reads `liftLocation` to compute the floating preview's grab offset against where the finger actually landed — not where it's already moved to by the time the first `.changed` fires (which can be tens of points later if the user starts dragging fast). `beginSession`, `endDrag`, and `cancelSession` clear it.

**Net result:** the page scrolls cleanly from anywhere — over a card, between cards, on the header. Long-press on a card still triggers the lift haptic + the live drag preview at the same 0.4s threshold and the reorder UX is unchanged (lift → drag → drop or drop-on-empty-reverts). Build passes; no test changes (the gesture layer isn't unit-tested — verified via the iOS Simulator running the Cards layout).

### Phase E.5.25 — Cards grid migrated to UICollectionView (added this round)

User reported a regression right after E.5.24: in Cards mode, long-pressing a card brought up the action menu before drag-to-reorder could reliably take over. That exposed the deeper issue: even after moving one recognizer down to UIKit, Cards mode still had **two separate long-press systems** competing on the same surface (`KeepCard`'s SwiftUI `.contextMenu` and the custom reorder recognizer). That's not a timing bug; it's the wrong architecture for this interaction mix.

**Clean fix: move Cards mode onto UIKit's native collection-view interaction model.**

- New `Features/Timeline/CardsBoardCollectionView.swift`
  - `UIViewRepresentable` wrapper around a self-sizing, non-scrollable `UICollectionView` embedded inside the existing Today-screen `ScrollView`.
  - Each cell renders the existing SwiftUI `KeepCard` via `UIHostingConfiguration`, so the visual design stays identical while interaction ownership moves to UIKit.
  - The collection view owns:
    - **context menus** via `collectionView(_:contextMenuConfigurationForItemAt:point:)`
    - **drag reorder** via `UICollectionViewDragDelegate` / `UICollectionViewDropDelegate`
    - **order persistence** by writing the resulting id order back to `CardsViewOrderStore`
- New `Features/Timeline/CardsBoardMasonryLayout.swift`
  - Native 2-column shortest-column-first masonry layout mirroring the SwiftUI `MasonryLayout`: same 12pt gutter, same intrinsic-height packing, same no-trailing-bottom-gap behavior.
- `DesignSystem/Components/KeepCard.swift`
  - Added `showsContextMenu: Bool?` so a parent container can disable the card-owned SwiftUI `.contextMenu` while still keeping the pin-status overlay visible. Cards-mode collection cells use `showsContextMenu: false`; other surfaces keep the old default behavior.
- `Features/Timeline/TimelineScreen.swift`
  - `cardsBoardGrid` now renders `CardsBoardCollectionView(notes:onRequestDelete:)` instead of the old custom SwiftUI gesture grid.
  - Removed the old Cards-only scroll freeze (`.scrollDisabled(isCardReorderActive)`) and the editor-sheet drag-session reset hooks, since Cards mode no longer uses the custom `DragSessionStore` gesture path.

**Why this is better**
- Scroll-from-card, long-press drag reorder, and long-press context menus now live in the **same native interaction system** instead of being arbitrated across SwiftUI gesture modifiers.
- This is the common iOS architecture for a surface with **variable-height cards + reorder + context menu**.
- The rest of Today stays SwiftUI; only Cards mode crosses the bridge, which keeps the refactor scoped.

**Verification**
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/DailyCadence/DailyCadence.xcodeproj -scheme DailyCadence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' build` succeeds.
- Direct simulator install succeeds via `xcrun simctl install booted .../DailyCadence.app`.
- Direct simulator launch still fails on this machine with `FBSOpenApplicationServiceErrorDomain` when opening `com.jonsung.DailyCadence`, so I could not do an interaction-level manual verification pass from the CLI.

### Phase E.5.26 — Cards-mode live reflow during reorder (added this round)

After the E.5.25 collection-view migration, reordering was structurally sound but still behaved like a "pick up, hover, then reconcile on drop" flow: the dragged card floated over the masonry while the surrounding cards stayed put, which looked wrong when moving a taller card into a tighter slot.

**Root cause.** The collection view was still using a manual `UICollectionViewDragDelegate` / `UICollectionViewDropDelegate` implementation that only mutated `orderedIDs` in `performDropWith`. That means the custom masonry layout didn't get a new ordering while the drag was in flight, so it had no chance to repack the columns around the dragged card's size until after the drop committed.

**Clean fix: adopt diffable-data-source reordering, not manual drop commits.**

- `Features/Timeline/CardsBoardCollectionView.swift`
  - Removed the manual drop-commit reorder path.
  - Enabled `UICollectionViewDiffableDataSource.reorderingHandlers`:
    - `canReorderItem = true`
    - `didReorder` captures the collection view's final item order from the diffable transaction and persists it to `CardsViewOrderStore`
  - Set `collectionView.reorderingCadence = .immediate` so the native collection-view reorder engine continuously repacks as the user drags, instead of waiting for drop.
  - Cards mode still keeps native context menus via `contextMenuConfigurationForItemAt` and native drag lift via `UICollectionViewDragDelegate`.

**Why this is the modern/common path**
- This hands live reflow back to UIKit's **own reorder machinery** instead of simulating it ourselves in `performDropWith`.
- It keeps one source of truth for in-flight reorder state: the collection view + diffable data source, not a second custom hover model.
- The custom masonry layout now simply reacts to the order UIKit is actively maintaining during the drag.

**Verification**
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/DailyCadence/DailyCadence.xcodeproj -scheme DailyCadence -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' build` succeeds after the reorderingHandlers + `.immediate` change.

### Phase E.5.27 — Cards reorder rewritten in pure SwiftUI (added this round)

In real use the E.5.25 / E.5.26 collection-view path had visible layout breakage on drop — cards landing with the wrong height for their slot, neighboring cards overlapping, and a ~2-second settle while the layout reconciled. After several scoped patches (drop delegate, masonry frame-cache invalidation, height memoization), the underlying issue was clearly architectural rather than perf: the bridge maintained **three independent representations of card height** (the cell's `UIHostingConfiguration`, a sidecar `UIHostingController` used to pre-measure, and the masonry layout's `[CGFloat]` array). Each rendered in a different SwiftUI context, so they drifted under real workloads.

**Clean fix: delete the bridge entirely; use SwiftUI's native primitives.**

- New `Features/Timeline/CardsBoardView.swift` (~90 lines)
  - `MasonryLayout(columns: 2, spacing: 12)` reuses the existing `DesignSystem/Components/MasonryLayout.swift` (the same custom `Layout` Stack mode already uses) — no duplicate. The same render context measures and places each card, so what the layout packs is exactly what gets drawn.
  - `.draggable(NoteDragPayload(id: note.id))` on each card and `.dropDestination(for: NoteDragPayload.self)` on each card. Both route through iOS's system drag-and-drop (`UIDragInteraction`), which arbitrates with the parent `ScrollView`'s pan recognizer at the UIKit gesture layer — scrolling continues to work from any touch start, including over a card.
  - `NoteDragPayload` is a small `Codable` + `Transferable` wrapper using `CodableRepresentation(contentType: .data)`. Generic-data content type keeps the drag intra-app — text-accepting apps (Notes, Mail) don't advertise as drop targets, and we don't have to register a custom UTType in Info.plist.
  - Drop handler calls `CardsViewOrderStore.shared.move(sourceID, onto: note.id, in: notes)` inside `withAnimation(.easeInOut(duration: 0.22))`. On empty-space release iOS cancels the drag and no order change happens — no manual snapshot/revert plumbing needed.
  - `CardsViewOrderStore.move(_:before:in:)` was renamed to `move(_:onto:in:)` and its semantics tightened: source lands at target's original slot regardless of direction (forward drag → source after target; backward drag → source before target). The previous "insert before target" rule made forward drag onto an immediate-next neighbor a no-op (source was already there), which read as "drag did nothing." Two new tests pin the symmetric behavior; one obsolete cascade-guard test (Phase E.5.7-era) was deleted because the system drag pipeline doesn't fire repeated moves during a single drag.
  - `KeepCard`'s built-in `.contextMenu` (Pin / Delete) coexists with `.draggable` automatically: tap-and-hold-without-drift opens the menu; tap-and-hold-then-drag begins reorder. Standard iOS disambiguation.

- `Features/Timeline/TimelineScreen.swift`
  - `cardsBoardGrid` now renders `CardsBoardView(notes:onRequestDelete:)` and the inline doc comment notes the rationale for the rewrite.

**Deleted (the entire bridge — six files):**

- `Features/Timeline/CardsBoardCollectionView.swift` — the `UIViewRepresentable` + diffable-data-source coordinator
- `Features/Timeline/CardsBoardMasonryLayout.swift` — the UIKit-side `UICollectionViewLayout` masonry
- `Features/Timeline/CardReorderRecognizer.swift` — UIKit long-press recognizer bridge from the pre-collection-view era
- `Features/Timeline/CardFramePreferenceKey.swift` — preference key feeding the old gesture's hit-test map
- `Services/DragSessionStore.swift` — drag-session state for the old custom-gesture path
- `docs/TODO_CUSTOM_DRAG_REORDER.md` — historical spec for the deleted custom-gesture flow

**Why this is solid/stable/common**
- One framework, one sizing model. SwiftUI measures each card via `Layout.subviews[i].sizeThatFits(...)`; that's the same call that produces the rendered frame. No second measurement, nothing to drift.
- `.draggable` + `.dropDestination` is the iOS-canonical drag-to-reorder primitive — same surface Notes / Reminders / Files use. iOS owns long-press initiation, haptic, lift, floating preview, and cancel-on-empty.
- `CardsViewOrderStore.move(_:onto:in:)` is the single drop primitive — no other reorder service-layer plumbing needed.
- ~600 lines deleted, ~90 lines added.

**Behavior trade-off (transparent)**
- E.5.26's "live reflow during drag" (cards shifting around a hovering finger) is gone. With system `.draggable` the reorder commits on drop. This matches the iOS Notes / Reminders pattern and is the more common idiom; if live reflow becomes a wanted refinement later it can be added on top of the SwiftUI surface.

**Verification**
- Code-level grep confirms no dangling references to deleted symbols (`DragSessionStore`, `CardsBoardCollectionView`, `CardReorderRecognizer`, `CardFramePreferenceKey`, `IntrinsicHeightCollectionView`, `CardHeightCache`).
- Xcode build verification pending — Jon to run on his machine since the CLI environment lacks an active Xcode developer directory.

### Phase D.2.2 — Interactive crop for image backgrounds + downscale on import (added this round)

Closes the Phase D.2.1 deferral. Backgrounds now route through the same crop UI media notes already use, and picked photos are downscaled before being stored.

**Unification, not duplication.** Instead of writing a second crop tool (the originally-proposed pan/zoom transform stored as `(offset, scale)` metadata applied at render time), we reuse the existing `Features/MediaCrop/PhotoCropView` directly. Backgrounds become **pre-cropped bytes** — same storage shape as media notes — so:

- `MockNote.ImageBackground` shape stays `(imageData: Data, opacity: Double)` — no new `Crop` struct.
- `NoteBackgroundStyle.image(data:opacity:)` unchanged.
- `KeepCard` / `NoteCard` render unchanged — still `.scaledToFill().clipped()` against the (now user-cropped) bytes.
- One crop UI file is the single source of truth for cropping in the whole app. Future tweaks (haptics, snap-to-thirds, undo) land in one place.

**Background photo flow:**

1. User taps `🖼` in the editor toolbar → `BackgroundPickerView` opens.
2. User picks a photo from their library.
3. `BackgroundPickerView.loadPhoto` calls `MediaImporter.downscale(_:maxDimension: 1024)` — re-encodes as JPEG q=0.85 with the longest edge clamped to 1024pt. A 4032×3024 HEIC (~3 MB) becomes a ~150–250 KB 1024×768 JPEG. Plenty for cards (which never render larger than ~400pt × 480pt onscreen) and keeps future Supabase Storage costs bounded.
4. The downscaled bytes seed both `selection` and a fresh `PhotoCropState` — the crop sheet auto-launches (Apple Notes / Notion pattern, lands the user straight in the framing decision).
5. User crops with the existing chip set (Free / 1:1 / 4:3 / 3:4 / 16:9 / 9:16) and corner-resize + center-drag UX. **Done** writes `result.data` back to `selection`. **Cancel** keeps the uncropped picked photo as-is.
6. Subsequent edits via the new **Edit crop** button re-open the same sheet against the current bytes for refinement.

**Files:**
- `Services/MediaImporter.swift` — added `static func downscale(_ data: Data, maxDimension: CGFloat) -> Data?` (decode → redraw at clamped size → JPEG q=0.85). Used only by backgrounds; media-note photos preserve full quality so the fullscreen `MediaViewerScreen` can show the original.
- `Features/NoteEditor/BackgroundPickerView.swift` — `@State private var cropState: PhotoCropState?`, `cropSheet` body, `confirmCrop()` / `openCropForCurrent()`, "Edit crop" button between Replace and Remove, downscale + auto-launch in `loadPhoto`.
- `DailyCadenceTests/Services/MediaImporterTests.swift` (new, 5 tests) — landscape & portrait clamp to 1024 long edge, already-small images aren't upscaled, output is JPEG (magic bytes), invalid bytes return nil.

**Decisions called out + outcome:**
- **Destructive crop, no "revert to original."** If the user wants the source photo back, they re-pick from the library. Matches Apple Notes / Notion. No state to track for an "undo crop" affordance.
- ~~**No pinch-to-zoom this phase.**~~ Reversed mid-round — see "Crop tool: pinch + pan + handle inset" below.
- **Auto-launch crop on first pick.** Tighter than "pick → see uncropped → tap Crop." Cancel keeps the uncropped photo, so it's a recoverable default.
- **Downscale only for backgrounds.** Media notes keep full bytes; backgrounds are clamped at 1024px max. Avoids regressing the fullscreen photo viewer.

**Behavior preserved**
- Existing notes' image backgrounds (already in memory before this change) keep working — same model shape, same render path. Their bytes are whatever they were; no migration needed.

**Verification**
- `MediaImporterTests` + existing `MockNoteBackgroundTests` cover the model + helper invariants.
- UI flows verified via SwiftUI Previews; manual interaction verification pending Xcode build on Jon's machine.

### Crop tool: pinch + pan + handle inset (added this round)

Two refinements to `PhotoCropView` that benefit both media notes and the new background flow (since both share the same crop UI per Phase D.2.2):

**Pinch-to-zoom + image pan.** The crop tool now matches Apple Photos' interaction model.
- `PhotoCropState` gains `imageScale: CGFloat = 1.0` (range 1×–5×) and `imageOffset: CGSize = .zero`, plus a `displayedImageRect` computed property and a `clampedOffset(_:for:)` helper.
- `Image` gets `.scaleEffect(imageScale, anchor: .center).offset(imageOffset)`.
- New `MagnifyGesture` on the canvas updates `imageScale` (re-clamps offset on every change so pinching out doesn't expose canvas chrome).
- The single-finger drag inside the crop-rect interior, which previously moved the rect, now **pans the image** under it. The rect is fixed; the image moves. This is the Apple Photos pattern and removes the gesture-overload concern that delayed pinch in earlier phases.
- `commitCrop` maps the canvas-space crop rect through `displayedImageRect` (which folds in pinch + pan) instead of `imageRect`. At zoom 1× / offset 0 this collapses to the original mapping, so existing workflows are unchanged.
- Aspect chip selection resets `imageScale` and `imageOffset` to defaults (matches Apple Photos: changing aspect is a clean state).
- `clampPosition` (only used by the removed center-drag-of-rect) deleted.

**Corner handle inset.** Visible L-glyph offset 9pt inward from the corner so it stays inside the crop rect, regardless of where the rect lands. Bug: when the rect equaled the image rect at a canvas edge (typical for portrait photos in a wider canvas), the corner-centered handles half-rendered above the canvas top and got eaten by `.clipped()`. Hit zone (36pt) stays centered for a generous touch target — only the 18pt visible glyph moved.

**Crash fix: 48 MP ProRAW jetsam.** A user-reported crash on a specific image surfaced through the new logs:

```
types=com.adobe.raw-image
loaded 61897601 bytes (59.0 MB)
imagePayload decoded: 6048×8064 (48.8 MP) orientation=3
PhotoCropState.init decoded: 6048×8064 (48.8 MP) orientation=3
normalizedUp redraw: 6048×8064 (48.8 MP) orientation=3
                                                             ← OS terminated for memory pressure
```

A ProRAW capture from an iPhone 14 Pro: 59 MB on disk, ~187 MB fully decoded as RGBA. The pipeline held *two* full decodes in parallel (`MediaPayload.data`-derived UIImage + `PhotoCropState.original`) and then `normalizedUp()` tried to allocate a third same-size bitmap for EXIF rotation. ~560 MB live → jetsam.

**Fix: switch the downscale path to ImageIO's thumbnail API.** `CGImageSourceCreateThumbnailAtIndex` decodes the source *directly to the target size* without ever holding the full-resolution decode in memory. Peak memory drops from ~187 MB to a few MB. Also bakes in EXIF orientation (`...WithTransform`), so the returned JPEG is already `.up`-oriented and `normalizedUp()` short-circuits.

- `MediaImporter.downscale(_:maxDimension:)` rewritten on top of `CGImageSourceCreateThumbnailAtIndex`. Same signature, same JPEG q=0.85 output, but memory-bounded.
- `MediaImporter.imagePayload` now calls `downscale(_, maxDimension: mediaNoteMaxDimension /* 2048 */)` *before* any full UIImage decode. Stored `MediaPayload.data` is the downscaled JPEG, so `PhotoCropState` and downstream cells never see the 48 MP source.
- 2048px cap is generous for fullscreen viewing on iPhone 15 Pro Max (1290×2796) but ~10× smaller than a 48 MP ProRAW. RAW notes lose RAW-quality, but media notes are journal snapshots, not master files.
- Backgrounds keep their existing 1024px cap (defined in `BackgroundPickerView`); they benefit from the more memory-efficient `downscale` implementation too.

**Crash logging instrumentation (kept).** `OSLog` calls across `MediaImporter` (byte counts, decoded dimensions, orientation) and `PhotoCropView` (PhotoCropState init, normalizedUp redraw entry/exit). The `autoreleasepool` wrap on `normalizedUp` stays as a defensive safety net for any remaining edge case where a smaller image still needs orientation rebake. Sequence-aware logging proved its worth on the first repro.

### Cards-board reorder: suppress the system "+" copy badge (added this round)

User noticed the green `+` badge on the drag preview during reorder — iOS's system "drop accepts copy" indicator. Misleading for a reorder (which is a move, not an add); Apple's own Notes / Reminders show a "move" cursor (no badge) instead.

**Why the rewrite couldn't avoid it.** The modern `.dropDestination(for:action:)` modifier doesn't expose drop *operation* type, so it always defaults to `.copy` and surfaces the `+` badge. The only SwiftUI path that lets you specify `.move` is the legacy `.onDrop(of:delegate:)` + a `DropDelegate` whose `dropUpdated` returns `DropProposal(operation: .move)`. That's what the Phase E.4.6 codepath did before the Phase E.5.27 rewrite.

**Fix.** Switch the *drop side* (only) from `.dropDestination(for: NoteDragPayload.self)` to `.onDrop(of: [.data], delegate: CardsReorderDropDelegate(targetID:notes:))`. Drag side keeps `.draggable(NoteDragPayload(id:))` — same `Transferable` payload, just decoded manually in `performDrop` via `NSItemProvider.loadDataRepresentation`. The delegate runs the same `CardsViewOrderStore.move(_:onto:in:)` call inside the same animation block.

This stays much smaller than the original Phase E.4.6 implementation: no separate file, no frame-collection preference key, no async-load race conditions (the drop already implies the drag completed, so the loadDataRepresentation callback is synchronous in practice). ~30 lines added in `CardsBoardView.swift`.

**Files:**
- `Features/MediaCrop/PhotoCropView.swift` — pinch + pan, handle inset, OSLog, autoreleasepool. Net ~+50 / −30 lines.
- `Services/MediaImporter.swift` — OSLog instrumentation in import path.

### Long-press → context menu discoverability hint (added this round)

`TipKit` popover surfaces the "long-press a card" gesture for first-time users without adding permanent chrome. Apple's iOS 17+ canonical onboarding-tip pattern.

- New `Features/Timeline/CardActionsTip.swift` — `Tip` conformance with title ("Pin or delete a card") + message ("Touch and hold any card to see options.") + `hand.tap.fill` glyph + an event-based rule that disqualifies the tip after first use.
- `DailyCadenceApp.init` calls `Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])` so per-tip rules drive frequency, not the global rate limiter.
- `KeepCard.contextMenu` Pin and Delete button actions donate `CardActionsTip.userDidUseContextMenu` (fire-and-forget `Task` since donate is async). Tapping the standalone pin glyph does NOT donate — that's a separate affordance and doesn't prove the user found the menu.
- `TimelineScreen.segmentedToggle` carries the `.popoverTip(cardActionsTip, arrowEdge: .top)` modifier. The toggle is always visible above the cards in both Timeline and Board modes, so the popover lands with the right visual context regardless of which view the user is on.

The tip's lifecycle: shows on first app launch with at least one note → user long-presses a card → uses Pin or Delete → tip's `userDidUseContextMenu.donations.isEmpty` flips to false → rule fails → tip never shows again. Self-extinguishing without any "x to dismiss" button needed (TipKit shows one anyway, plus a swipe-down dismiss, in case the user wants to dismiss without using the menu).

### Pinned section now lives on Timeline too (added this round)

The "Pinned" shelf was Board-only since Phase E.5.15. Extending it to Timeline gives the user one consistent affordance across both view modes.

**Duplication semantics differ by mode** — a deliberate design choice:
- **Board** sub-modes feed `unpinnedNotes` to their content, so a pinned note appears once (in the shelf only).
- **Timeline** feeds the full chronological list to the rail, so a pinned note appears twice (shelf + natural time slot). Pulling pinned items out of the chronological rail would distort the day's timeline shape, which is the whole point of Timeline mode — the shelf is a quick-access shortcut, not a re-categorization.

**Files (~30 lines):**
- `Features/Timeline/TimelineScreen.swift` — new `timelineContent` view that wraps the timeline rail with an optional `pinnedSection` above it; `content` switch dispatches to it for `.timeline`. Tightened the pinned-section's rail/masonry condition from `boardLayout == .grouped` to `viewMode == .board && boardLayout == .grouped` so a stale `boardLayout = .grouped` from a previous session can't leak the rail layout onto Timeline. Doc comments on `pinnedSection` + `boardContent` updated to reflect cross-mode use.
- `docs/FEATURES.md` — refactored: new shared "Pinned section" subsection, Timeline view block references it, Board view block thins down (no longer the home of the pinned-section docs).

### Phase F prep — schema design + SDK install (added this round)

The pre-enrollment prep work for Phase F (Supabase persistence). Schema is drafted in `supabase/migrations/`; the iOS Supabase SDK is wired into the Xcode project. **Nothing is applied to the live Supabase project from the iOS side yet** — that ships in the next session once Apple Developer enrollment clears (currently in review).

**Schema design (`supabase/migrations/20260427000001_notes_init.sql`).** Detailed in `supabase/README.md`. Key decisions:

- **Types are data, not enums.** `note_types` table holds system + user-created types. Each row carries a `structured_data_schema jsonb` describing the editor fields for that type. Field `kind` vocabulary is recursive (`object` + `list` with `item_schema`) so workouts → exercises → sets/reps/weight compose without bespoke kinds.
- **Backgrounds are an account-level library.** `backgrounds` table holds system presets + user-created entries. `notes.background_id` is a FK so library entries are reusable across notes.
- **`notes` shape:** hybrid — common fields typed; variant content in `body jsonb` (paragraph/media/checkbox blocks) + `structured_data jsonb` (per-type fields). No `content_kind` discriminator.
- **Reorder:** fractional indexing (`position double precision`).
- **Soft delete:** `deleted_at timestamptz` nullable, 30-day retention via future scheduled cleanup.
- **Reschedule audit trail:** `cancelled_at` + `rescheduled_from_id` columns. Push-to-next-day inserts a fresh note with `rescheduled_from_id = original.id`, then marks original `cancelled_at = now()`. Original stays visible at original date with a "moved" indicator.
- **Evergreen notes:** `occurred_at` is **nullable**. NULL = no specific date (running grocery list, ongoing reference); past = journal; future = reminder/todo.
- **Reminders / todos orthogonal to type.** `notification_offsets int[]` reserved on `notes` (Phase F+ UI). `completed_at timestamptz` for todo-style completion (any note can be completable).
- **Sharing — unified per-note + group-tag model.** `note_collaborators` (role + status: invited/accepted/declined/left) covers per-note share/invite ("share with viewer" and "invite as editor" are the same row, just different role). `shared_groups` + `shared_group_members` (also status-tracked) covers group-tag sharing. Only group owners can invite; members can leave. RLS reads share tables from day one so adding the share UI later doesn't require policy rewrites.
- **Discriminator vocabulary:** `kind` for JSONB shapes (block kinds, background kinds, structured-data field kinds); `type` reserved for the note's category (`note_types.slug`). They never collide.

**Storage (`supabase/migrations/20260427000002_storage_buckets.sql`).** Two private buckets — `note-media` for inline media in `body` blocks, `note-backgrounds` for image backgrounds. Per-user folder isolation via `(storage.foldername(name))[1] = auth.uid()::text` in the RLS.

**iOS SDK install.** `supabase-swift` 2.44.1 added via SPM with the umbrella `Supabase` library on the `DailyCadence` target. Resolved deps: swift-asn1, swift-clocks, swift-concurrency-extras, swift-crypto, swift-http-types, xctest-dynamic-overlay. Build verified (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... build` → BUILD SUCCEEDED).

**Apple Developer enrollment:** in review as of 2026-04-27 evening. Started ~24h before. Once approved: enable Sign in with Apple capability on the App ID; create a Services ID + signing key for the Supabase OAuth provider; configure Supabase dashboard Auth → Providers → Apple.

**Dev-mode plan (interim, while enrollment is pending):** anonymous auth. Supabase's `signInAnonymously()` creates real sessions with generated user_ids; RLS works identically. Wires the data layer + tests CRUD/Storage/Realtime end-to-end without depending on Apple. When enrollment clears, add Apple + Google providers and link the anonymous user to the new identity. Anonymous Sign-Ins toggle has been enabled in the Supabase dashboard; migrations have been applied to the live project.

### Phase F.0 — Supabase client wiring (added this round)

The first iOS-side step of Phase F. Schema and SDK already in place from the prior round; this round wires the Swift app to actually talk to the Supabase project.

**Cache strategy decision: in-memory.** Three options weighed (pure online / in-memory / SwiftData). Picked **in-memory** for Phase 1: `TimelineStore` keeps its `@Observable` shape and gets a `repository` dependency + `load()` method. Trade-off: cold launch shows ~200ms loading state and offline writes fail with a toast — both acceptable for two TestFlight users who are almost always online. SwiftData stays parked until offline pain becomes real (one repository abstraction is the seam to swap behind later).

**`Config.xcconfig` pattern.** `apps/ios/DailyCadence/Config.xcconfig` (gitignored) holds `SUPABASE_URL` + `SUPABASE_ANON_KEY`. `Config.example.xcconfig` is committed as a template for fresh clones. Note the `https:/$()/...` escape — xcconfig treats `//` as a comment, so URLs need the empty-interpolation trick. `.gitignore` extended with the explicit path.

**Static `Info.plist`.** Discovered that `INFOPLIST_KEY_<custom>` only injects Apple-recognized keys when `GENERATE_INFOPLIST_FILE = YES` (custom keys silently get dropped). Switched the app target to a real `apps/ios/DailyCadence/DailyCadence/Info.plist` containing `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` placeholders that interpolate at build time, alongside the standard `CFBundle*` keys. Added a `PBXFileSystemSynchronizedBuildFileExceptionSet` so the synchronized root group doesn't double-add `Info.plist` to the Resources phase (which would conflict with `INFOPLIST_FILE`).

**`Services/AppSupabase.swift`.** Singleton enum exposing `AppSupabase.client: SupabaseClient`. Reads `SupabaseURL` + `SupabaseAnonKey` from `Bundle.main.infoDictionary`, fails fast with a clear "copy Config.example.xcconfig → Config.xcconfig" error if missing.

**Verified at runtime:** `Bundle.main` reports `SupabaseURL = https://zmlxnujheofgtrkrogdq.supabase.co` and a 208-char `SupabaseAnonKey` (legacy anon JWT shape). Build clean. Either the legacy `eyJ...` JWT or the newer `sb_publishable_...` key works — both flow through the same `apikey` header.

### Bug fix — `MediaImporter.downscale` no longer upscales (added this round)

Caught while validating the test suite was green after the Phase F.0 wiring. Two related issues, one in source and one in test:

- **Source:** `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways: true` and `kCGImageSourceThumbnailMaxPixelSize: 1024` will UPSCALE a smaller source up to 1024 — the thumbnail API treats `maxPixelSize` as a literal target, not a ceiling. The doc-comment claimed "never upscaled" but the code didn't enforce it. Fix: read source pixel dims via `CGImageSourceCopyPropertiesAtIndex` and clamp `maxPixelSize` to `min(maxDimension, max(srcW, srcH))`. Falls back to original behavior when properties are unreadable. Real-world impact is small (callers always pass `maxDimension = 2048` and iPhone photos are always larger), but it matches the documented contract and protects future Phase F+ Storage thumbnail flows.
- **Test:** `MediaImporterTests.renderPNG(width:height:)` was using `UIGraphicsImageRenderer` at the simulator's natural 3× scale, so a "600×400" logical request emitted an 1800×1200 pixel PNG. Fixed by passing `UIGraphicsImageRendererFormat()` with `scale = 1` so logical = pixel.

Without the test fix the upscale-guard test was a false positive (the 1800×1200 source legitimately needed downscaling); without the source fix the contract was unenforced. Both went together.

### Phase F.0.1 — AuthStore + anonymous bootstrap (added this round)

The auth half of Phase F's iOS data layer. The app now actually signs in to Supabase on launch.

**`Services/AuthStore.swift`.** `@Observable` singleton mirroring the `ThemeStore` / `TimelineStore` pattern. On init it spawns a Task that listens to `AppSupabase.client.auth.authStateChanges`. The SDK's stream emits an `.initialSession` event first carrying whatever's in Keychain. Exposes `currentUserId: UUID?`, `isReady: Bool` (false until first event resolved), and `lastError: String?`. Three branches:

- Valid stored session → apply, mark ready.
- **Expired stored session → wait.** The SDK's auto-refresh fires `.tokenRefreshed` (success) or `.signedOut` (refresh-token also dead). We don't apply the expired session, don't set `isReady` yet — the follow-up event resolves the state.
- No session → `signInAnonymously()`. The resulting `.signedIn` event flows back through the same stream and applies the new session.

Also handles `.signedOut` / `.userDeleted` by re-running `signInAnonymously()` so the app stays usable when the server tombstones an anon user (anon users can have a TTL).

**`AppSupabase` opts into the next-major-version SDK semantics** via `emitLocalSessionAsInitialSession: true`. The legacy default refreshes the stored session *before* emitting `.initialSession`, which masks the expired-session case. The new behavior emits whatever's in Keychain immediately and lets us check `session.isExpired` ourselves — strictly more honest, and one less migration to do later.

**`DailyCadenceApp.init`.** A bare `_ = AuthStore.shared` reference kicks off the bootstrap — first access creates the singleton, which spawns the listener task. Doesn't gate UI; the timeline still renders `MockNotes.today` while auth resolves in the background. (NotesRepository wiring will need `isReady` later.)

**`SettingsScreen` — new Account section.** Sits between Appearance and About. Shows "Loading…" until `isReady` flips, then the active user's UUID in monospaced text. If anonymous sign-in fails (network down, anon-auth toggle off in dashboard, etc.), an Error row appears in `Color.DS.workout` (warm-red brand tone). Footer text explains this is dev mode and Apple/Google land after enrollment.

**Verified by build (138/138 unit tests still pass).** Live anon sign-in tested manually by Jon — confirm via Settings → Account showing a UUID.

### Phase F.0.2 — NotesRepository + live TimelineStore (added this round)

The data half of Phase F's iOS layer. The Today timeline now reads from Supabase on launch, and the editor's Save button persists in the background.

**`Services/NotesRepository.swift`.** A new singleton repository over the `notes` and `note_types` tables. Surface: `fetchAll(userId:) async throws -> [MockNote]`, `insert(_:userId:) async throws -> UUID?` (returns the server-canonical id), `delete(id:) async throws` (soft-delete via `deleted_at = now()`). Internally caches `note_types` slug↔id lookups (loaded once on first call) so notes can store the right `type_id` FK while iOS keeps using its `NoteType` slug enum at the call site.

**Body + structured_data JSON shapes.** Three private DTO types — `BodyBlockDTO` (paragraph + media block kinds, `kind` discriminator per the schema vocab), `StructuredDataDTO` (stat/list/quote variants), `TitleStyleDTO` (`fontId` / `colorId`). The `body` JSONB array is `[{"kind":"paragraph","text":"..."},...]`; `structured_data` is `null` for `.text` and `.media` content, populated for `.stat` / `.list` / `.quote`. Unknown `body` block kinds default to `paragraph` on decode so admin-panel-added kinds don't crash old clients.

**`TimelineStore` is now live.** New shape:
- `load(userId:) async` — fetch + replace `notes`. Idempotent; flips `hasLoaded` on success. Keeps the existing in-memory list on failure (better cold-start UX offline).
- `add(_:)` and `delete(noteId:)` stay synchronous to callers — they update the in-memory list immediately and spawn an internal `Task` to persist. On insert success the optimistic UUID is swapped for the server-canonical one. On insert failure the optimistic row is reverted; on delete failure we don't revert (user already saw the note disappear) but `lastError` surfaces for diagnostics.
- `lastError: String?` exposed for future toast UI.

**Load trigger.** `RootView` adds `.task(id: AuthStore.shared.currentUserId)` — fires when the anon-auth bootstrap settles `currentUserId` from nil → uuid, guarded by `hasLoaded` so it's once-per-launch.

**MockNote tweak.** Added `id: UUID = UUID()` as the first init param so the repository can construct `MockNote` values with server-supplied UUIDs. Existing call sites unchanged (default param). Same-build callers required a clean rebuild because the init's symbol mangling changed even though source-level call shape didn't.

**Design system note: discriminator vocab in code now matches the schema.** `kind` for JSONB shape discriminators (block kinds, structured-data variants); `type` reserved for note category (`NoteType`). DTOs follow.

### Phase F.0.3a — MockNote.occurredAt as source of truth (added this round)

Pure refactor — invisible in the UI, foundational for date navigation. Replaced `MockNote.time: String` (display string like "8:00 AM") with `occurredAt: Date?` as the stored property. `time` becomes a computed display getter (`h:mm a` formatted from `occurredAt`, or `"—"` when nil/evergreen).

**Why now.** Phase F.0.3b's day filtering needs a real `Date` to compute `[startOfDay, startOfNextDay)` ranges and compare against `notes.occurred_at: timestamptz`. The previous parse/format hack (parse "8:00 AM" + splice today's date) only worked for today and was locale-fragile. With `occurredAt` as a real Date, encode/decode through `NotesRepository` becomes trivial — pass the Date through unchanged.

**Ripples.**
- `MockNotes.today` seed + `MockNotes.skeletonPlaceholders` use a new `todayAt(_:_:)` helper that constructs today's local-day Date at given hour+minute (so previews and skeletons always look "current" regardless of when the app launches).
- Both editors (`NoteEditorScreen`, `MediaNoteEditorScreen`) stamp `Date.now` directly instead of formatting + parsing display strings.
- `NotesRepository.encodeForInsert` / `decode` use the Date directly. Removed `parseDisplayTime` / `formatDisplayTime` + the shared `displayTimeStyle` formatter.
- `TimelineStore.persistAdd` constructs the canonical-id swap MockNote with `occurredAt: note.occurredAt`.
- ~30 test sites batch-replaced via `sed s/time: "[^"]*"/occurredAt: .now/`. Component-level previews (`KeepCard`, `KeepGrid`) updated to use `MockNotes.todayAt(h, m)` so the visual rhythm of "varied times across a day" survives.

138/138 tests still green after the refactor.

### Phase F.0.3b — Date navigation on Today (added this round)

The user-visible feature. The Today screen is now per-day: chevrons / tap / swipe / "Today" pill all work, both editors honor the selected day, and the fetch is scoped to the day's `[startOfDay, startOfNextDay)` window.

**`NotesRepository.fetchForDay(userId:, day:)`** replaces `fetchAll`. Filters by `occurred_at >= startOfDay AND occurred_at < startOfNextDay` in the user's local calendar (`Calendar.current`). Evergreen notes (`occurred_at IS NULL`) are excluded — they live in a separate "Notes" surface (Phase F+).

**`TimelineStore.selectedDate`** is the new source of truth for "which day is showing." Defaults to today's `startOfDay`. Mutations:
- `selectDate(_:)` — switch to a normalized day; clears `notes` immediately + flips `hasLoaded` to `false` (skeleton shows on day-switch, matching cold-launch behavior).
- `goToToday()` — convenience for the "Today" pill.
- `shiftSelectedDate(byDays:)` — used by chevrons + swipe.
- `isViewingToday` — computed; drives the "Today" pill's visibility.

**`RootView` load trigger** got a composite `TimelineLoadKey` id (`{userId, selectedDate}`). SwiftUI restarts the `.task` whenever either changes, so the timeline re-fetches on auth transitions AND day changes. `hasLoaded` still guards same-id re-fires.

**Header redesign in `TimelineScreen`.** Two-row layout:
- **Top row:** TODAY / YESTERDAY / TOMORROW / weekday caption on the leading edge; Board sub-mode menu (Board view only) + gear on the trailing edge.
- **Bottom row:** chevron + big serif date title + chevron. Chevrons (32×44 hit targets, `fg2` ink) center cleanly on the 28pt title now that the small caption isn't stacked above the title inside the same HStack. Tap the date title → `DatePickerSheet` (graphical, `.medium` detent).
- "Today" pill below the navigator when not on today (sage capsule with `arrow.uturn.backward` glyph). Animated entry/exit with `.opacity.combined(.move(.top))`.

**Loading state — thin top progress bar (`DesignSystem/Components/LoadingBar.swift`).** While `TimelineStore.load(...)` is in flight, a 2pt sage indeterminate bar overlays the top of the screen. The custom slide animation (a 35%-width segment travelling left→right with `.linear` `.repeatForever`) gives the modern Safari/Mail loading affordance without taking layout space. Replaces the prior redacted-skeleton approach, which flashed in/out on every short day-switch fetch and felt distracting. Empty days still show `emptyState` — same UI whether loading or confirmed-empty — so the layout doesn't reorganize when the bar appears or disappears. `MockNotes.skeletonPlaceholders` and the `.redacted(.placeholder)` wiring were removed.

**`DatePickerSheet`** (new file) — wraps `DatePicker(.graphical)`, sage tint, Cancel + Done toolbar, `.medium` detent. Future dates unbounded.

**Swipe gesture on the ScrollView** — `simultaneousGesture(DragGesture)` with strict horizontal-dominance guard (`abs(dx) > abs(dy) * 1.5 && abs(dx) > 60`) so vertical scroll keeps working. Direction maps to `shiftSelectedDate(byDays: ±1)`.

**Editor date+time picker.** `DatePicker(.compact)` row at the bottom of `NoteEditorScreen` form (and the same shape in `MediaNoteEditorScreen`). Bound to `draft.occurredAt` (text editor) or local `@State` (media editor). Default value: `TimelineStore.selectedDate` spliced with the current wall-clock time-of-day — so notes saved while viewing a past day land at a believable position in that day's chronology. User picks override the default.

**`Calendar` tab unchanged** — it stays the surface for browsing by month/year. The Today date nav is for adjacent-day navigation; the Calendar tab is for the archive.

### Phase F.1.0 — Tap-to-edit (added this round)

The "view + edit a note" milestone. Modern instant-edit pattern (Apple Notes / Keep / Bear / Notion / Drafts) — no separate view-only mode; the timeline cards already serve the read-back use case.

**Card tap**: text cards (`.text` content variant) gain an `onTap: (() -> Void)?` callback wired through `NoteCard`, `KeepCard`, `CardsBoardView`, and `StackedBoardView` (collapsed + expanded sections). The TimelineScreen passes `tapHandler(for:)` which returns nil for non-text variants, leaving them non-tappable for now. Media-card taps still go to `MediaViewerScreen` via the existing internal `mediaScaffold` gesture.

**Editor in edit mode**: `NoteEditorScreen(editing: MockNote? = nil)`. New behaviors when `editing != nil`:
- Pre-populates a **per-instance `NoteDraftStore`** from the note (so opening a note for edit doesn't trample the singleton's in-progress new-note draft, and vice versa).
- Type picker collapses to the chip — the user already committed to a type.
- Save button reads "Done" instead of "Save".
- Save calls `TimelineStore.shared.update(_:)` instead of `add(_:)`.
- Nav title shows the note's date (`Apr 27` style) — Apple Notes pattern.
- **Per-mode dismissal** via `didCommit` / `didDiscard` flags + `.onDisappear`: drag-to-dismiss in edit mode autosaves; in create mode it preserves the recoverable draft (existing behavior).
- **Cancel-with-confirmation**: dirty-vs-editing check compares title / body / type / background / titleStyle / occurredAt against the original note. Confirmation alert reads "Discard changes?" instead of "Discard draft?".

**Toolbar actions menu** (edit mode only): an `ellipsis.circle` button next to Done opens a Menu with **Pin/Unpin** (toggles `PinStore`) and **Delete** (arms a confirmation alert — same Apple-pattern centered alert as the timeline's long-press Delete). Pin status reads through `PinStore.shared.isPinned(_:)` so the label flips live without re-rendering.

**Optimistic update path**:
- `NotesRepository.update(_:userId:)` — UPDATE query with the same encoder as insert; skips media notes pending Storage upload (Phase F+).
- `TimelineStore.update(_:)` — replaces the in-memory note immediately; spawns a background Task to persist; on failure, reverts to the previous version and surfaces `lastError`.

**`NoteDraftStore.populate(from:)`** — clears + re-populates draft state from a note's content. Today only `.text` content fully round-trips (title, body blocks, type, background, titleStyle, occurredAt). `.stat` / `.list` / `.quote` populate the title only as a fallback so the user can at least re-type or re-categorize; the structured fields aren't editable yet (no editor for those variants today either). `.media` is filtered out at `requestEdit` so populate is never called for it.

**Where we lead the pack vs Apple Notes / Keep:**
- Type re-categorization in the same edit (chip row).
- Per-note photo background + opacity editable in same surface.
- `occurredAt` picker for re-timing — most apps only show created/modified passively.

### Phase F.1.1a — Media-note Storage upload pipeline (added this round)

The persistence half of media notes. Photos and videos now survive relaunch via Supabase Storage. The compression half (HEIC + HEVC + dual-size + 60s cap) ships separately as F.1.1b — splitting kept this milestone testable end-to-end without bundling the encoding pipeline rewrite.

**`Services/MediaStorage.swift`** — provider-agnostic abstraction. `MediaStorage` protocol with `upload(_:contentType:userId:filename:)`, `signedURL(for:ttlSeconds:)`, `delete(_:)`. `MediaRef { provider, path }` is the durable opaque pointer that goes into `body jsonb` — never a URL (URLs expire). Today's impl is `SupabaseStorageImpl` writing to the `note-media` bucket; the migration to R2 (when egress crosses ~$200/mo) is a one-file swap because each ref carries its provider id and `MediaStorageProvider.impl(for: ref)` dispatches per-ref.

**`Services/MediaResolver.swift`** — resolves refs to bytes with two cache layers:
1. **Signed URL cache** (`urlCache: [MediaRef: (URL, fetchedAt)]`) — 50-min TTL, 10-min buffer below Supabase's 1-hour signed-URL expiry.
2. **`URLCache.shared`** (HTTP-level) — bumped to 50 MB memory + 200 MB disk on init. Survives relaunch. Cached responses serve when the URL is identical (which it is during the URL cache window).

**`MediaPayload` extended.** `data: Data` is now `data: Data?` (nil for fetched-from-server payloads); new `ref: MediaRef?` + `posterRef: MediaRef?` fields hold storage pointers. Editor flow stays the same shape — newly imported payloads have data populated, refs nil; uploaded payloads have refs populated; fetched payloads have refs only.

**`BodyBlockDTO.media` schema rewritten.** New shape:
```json
{ "kind": "media", "mediaKind": "image" | "video",
  "aspect": 1.5, "caption": "…", "size": "medium",
  "ref": {"provider":"supabase","path":"…"},
  "posterRef": {"provider":"supabase","path":"…"} }
```
Standalone media notes serialize as a `body` with one media block + null `structured_data`. Inline media blocks in text bodies use the same shape with `size` set. Decoder reconstructs `MediaPayload` with `data: nil` and refs populated; renderers lazy-fetch through `MediaResolver`.

**`NotesRepository.encodeForInsert` is now `async`.** Walks the note's content, uploads any `MediaPayload` whose `ref` is nil (newly-attached media), assembles the body with refs filled in, then INSERTs/UPDATEs the row. Idempotent on update — already-uploaded refs aren't re-uploaded.

**Card rendering**: `KeepCard.mediaScaffold` and `NoteCard.mediaScaffold` now branch — inline `posterImage` first (fast path), then `ResolvedMediaPoster` fallback when bytes are nil but refs exist. Soft taupe placeholder while loading.

**`MediaViewerScreen`** — fullscreen viewer now branches on `media.data`. Inline bytes use the existing `ImagePinchZoomView`; nil bytes route through `ResolvedFullscreenImage`. Video playback prefers signed URL (streams via `AVPlayer(url:)`) over downloading the full asset to a temp file when the ref exists.

**`ResolvedMediaPoster` + `ResolvedFullscreenImage`** (new design system components) — handle the loading state with `.task(id:)` triggers and soft placeholders. F.1.1c will add an `NSCache` decoded-image layer on top so re-decode-per-scroll goes away.

**Phase F.1.1 split:**
- **F.1.1a (this round)**: persistence end-to-end. Bytes are still JPEG (existing MediaImporter output). No 60s cap enforced. No dual-size yet.
- **F.1.1b (next)**: HEIC + HEVC + dual-size + 60s cap. Pure optimization on top of the persistence layer.
- **F.1.1c (later)**: NSCache decoded images + adjacent-day pre-fetch. Pure perf polish.

138/138 unit tests still passing.

### Phase F.1.1b — Compression layer (added this round)

Pure optimization on top of F.1.1a's persistence pipeline. No schema migration needed — the body JSONB shape gained `thumbnailRef` (already optional + new clients tolerate older shapes).

**Images: HEIC + dual-size.**
- `MediaImporter.encodeHEIC(_:quality:)` — `CGImageDestination` + `UTType.heic` + `kCGImageDestinationLossyCompressionQuality`. ~50% smaller than JPEG at perceptually-equivalent quality.
- `imagePayload(from:)` now produces both:
  - **Full** at `mediaNoteMaxDimension: 2048px` (HEIC q=0.85, ~150-300 KB typical)
  - **Thumbnail** at `mediaNoteThumbnailDimension: 600px` (HEIC q=0.7, ~30-60 KB)
- Cards render the thumbnail; fullscreen viewer renders the full. **5-10× egress reduction** on grid views since most user time is spent scanning cards.

**Videos: HEVC + 60s cap.**
- `reencodeHEVC(asset:)` — `AVAssetExportSession` with `AVAssetExportPresetHEVC1920x1080` and the iOS 18+ async `export(to:as:)` API. ~50% smaller than H.264 at same perceived quality.
- Length cap enforced at import: videos longer than `videoMaxDurationSeconds: 60` throw `ImportError.videoTooLong(seconds:)`. The editor surfaces a clear error ("That video is X seconds long. Videos must be 60 seconds or shorter for now — a trim tool is coming soon.") and drops the picked item so the empty-state picker shows again.
- HEVC export fallback: if re-encode fails for any reason (rare codec edge cases), the original bytes ship instead of failing the import outright.

**MediaPayload + schema.**
- `MediaPayload` gained `thumbnailData: Data?` (image small bytes, in-memory) + `thumbnailRef: MediaRef?` (image small ref, post-upload). Sibling to the existing `posterData`/`posterRef` for video.
- `BodyBlockDTO.media` schema gained an optional `thumbnailRef`. Old rows without it still decode; new rows for image notes always include it.
- `NotesRepository.encodeMediaBlock` uploads the thumbnail too (image-only) with a `-thumb.heic` suffixed filename. Same-bucket per-user folder.

**Resolver + cards.**
- `MediaResolver.posterBytes(for:)` is now kind-aware: image dispatches to `thumbnailData` → `thumbnailRef` → fall back to full `data`/`ref`; video dispatches to `posterData` → `posterRef`.
- `KeepCard.mediaPosterImage` and `NoteCard.mediaPosterImage` mirror the dispatch — kind-aware preference of thumbnail over full asset for images.

**File extensions / content types updated** in the uploader: images now upload as `*.heic` with `image/heic`; videos upload as `*.mp4` with `video/mp4` (HEVC inside MP4 container, the standard transport). Thumbnails use `*-thumb.heic`. Posters keep `*-poster.jpg`.

**Pre-F.1.1b notes still work** — fetched payloads with no `thumbnailRef` fall through to the `ref` (full asset) in the resolver. No backfill needed.

138/138 unit tests still passing.

### Phase F.1.1b' — Video trim sheet (added this round)

Replaces the over-60s rejection path with a proper Apple Photos-style trim flow. Picked clips longer than `videoMaxDurationSeconds` (60 s) now route through `VideoTrimSheet` instead of failing the import.

**`MediaImporter` reshape.** `makePayload(from:)` no longer returns a bare `MediaPayload` — it returns `ImportResult` (`.payload(MediaPayload)` or `.needsTrim(VideoTrimSource)`). The over-cap branch writes the picker bytes to a temp file and hands the URL to the caller via `VideoTrimSource` (Identifiable, drives `.sheet(item:)`). Confirm runs a new `makeTrimmedVideoPayload(source:range:)` which reuses the existing HEVC 1080p export with `AVAssetExportSession.timeRange = range`, regenerates the poster from the trim's start frame, and unlinks the temp file. Cancel calls `discardTrimSource(_:)` for the same cleanup. `ImportError.videoTooLong` is gone — its only remaining sibling, `.exportFailed`, surfaces if the trimmed export itself fails.

**`Features/MediaTrim/VideoTrimSheet.swift`** (new, ~430 LOC). Apple Photos pattern adapted to DailyCadence's sage palette:
- **Bare `AVPlayerLayer`** wrapped via `UIViewRepresentable` (we don't want `AVKit.VideoPlayer`'s built-in chrome during trim). Muted by default — preview audio in public would be a surprise.
- **Filmstrip**: 14 evenly-spaced frames generated via `AVAssetImageGenerator` across the source's full duration; `bg2` placeholder while frames generate (decorative; trim still works).
- **Three drag zones** over the bar: left handle (shrinks from start), right handle (shrinks from end), middle band (slides the window as a unit — essential when the desired slice is in the middle of a long clip). 1 s minimum, 60 s maximum.
- **Looping playback** within the trim window: a boundary observer at `endSeconds` seeks back to `startSeconds` and resumes. Re-registered on each play so handle drags during pause are honored.
- **Playhead**: 2 pt white bar inside the window, 30 Hz periodic time observer during playback; snaps to the dragged handle's time during scrubs.
- **Duration label**: "0:43 of 1:00 max" + monospaced "0:12 – 0:55" timestamps.
- **Cancel / Save toolbar**. Save fires `onConfirm(CMTimeRange)`; the editor catches it and runs `makeTrimmedVideoPayload`.

**Both editor surfaces wired.** `MediaNoteEditorScreen` (standalone media-note flow) and `NoteEditorScreen` (inline attachment flow inside text notes) both:
- Switch on `ImportResult` after `MediaImporter.makePayload(from:)`.
- Drive a `.sheet(item: $trimSource)` that presents `VideoTrimSheet`.
- Run the trimmed export off the main task; show the loading placeholder during export (typically <2 s on modern hardware for a 60 s clip).
- Surface `.exportFailed` errors inline below the picker / strip.

**Build + tests still green.**

**Load-time + gesture fixes (round 2, same session):** initial test surfaced two real issues — a 1:10 ProRes clip took ~60 s to reach the trim sheet and the handles were "very sensitive." Three fixes:

1. **`PhotosPicker(preferredItemEncoding: .current)`** at all four video-capable call sites ([MediaNoteEditorScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/NoteEditor/MediaNoteEditorScreen.swift), [NoteEditorScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/NoteEditor/NoteEditorScreen.swift), [TimelineScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/Timeline/TimelineScreen.swift)). The default `.automatic` policy transcodes ProRes / ProRAW to H.264 before handoff — multi-minute server-side render. `.current` returns the original bytes. **Single biggest win — picker → trim sheet went from ~60 s to ~1.8 s on a 475 MB ProRes clip.**
2. **`VideoFile: Transferable` with `FileRepresentation`** instead of `loadTransferable(type: Data.self)`. The `Data` path materializes the whole asset in RAM; for a 1+ GB ProRes that's minutes of stall (or jetsam). The file path is a fast disk-to-disk copy.
3. **Drag-gesture sensitivity bug.** `DragGesture.value.translation` is *cumulative since drag start*, not delta-since-last-tick. v1 did `start = start + translation/pps` every onChanged, so the handle accelerated at 2× finger speed. Fix: capture `dragInitialStart` on first tick, compute `start = dragInitialStart + translation/pps`. Same for end handle and middle-band slide.
4. **"Doesn't stop when I stop" bug.** v1 wrapped each scrub-seek in `Task { await player.seek(...) }`. Tasks queued, awaited sequentially, kept resolving long after the finger lifted. Fix: fire-and-forget `player.seek(...)` — AVPlayer dedups internally. Scrub uses `toleranceAfter: .positiveInfinity` (snap to nearest keyframe, fast); precise seeks (drag end, play boundary) keep `toleranceAfter: .zero`.

Filmstrip also got smaller `maximumSize` (200 → 120 px) and `tolerance: .positiveInfinity` (snap to keyframe). Frames now publish to UI as they generate (~30 ms each on ProRes after the fix), and the strip renders fixed slots so per-frame width stays stable while loading.

### Phase F.1.1b'.zoom — Apple Photos zoom + drag-dismiss for image and video (added this round)

Replaces the prior `.fullScreenCover` slide-up presentation with an Apple Photos-style matched-geometry zoom that's identical for both photos and videos. Architecture is custom (manual frame interpolation) because SwiftUI's `.navigationTransition(.zoom)` snapshots the destination — the live state-driven visuals went black mid-transition. `matchedGeometryEffect` was tried second; the viewer slid in from the side and the close-back rendered in the wrong z-layer.

**Open / close architecture.** [Models/MediaTapHandler.swift](apps/ios/DailyCadence/DailyCadence/Models/MediaTapHandler.swift) (new) bundles the tap callback, an `activeID`/`visibleID` split (the former drives card opacity gating during the close, the latter the matched-geo trigger), and a `CardFrameKey: PreferenceKey` collecting each card's image-area frame in global coords. `RootView` lifts the viewer state up so the overlay's z-order is above the TabBar (which lives in `safeAreaInset` at root level): owns `presentedMedia`, `hidingMedia` (kept rendered during the close via a deferred `Task.sleep(for: .milliseconds(510))`), `openProgress: CGFloat = 0`, and `sourceFrames: [UUID: CGRect]`. The viewer is mounted via `.overlay { ... .transition(.identity) }` so SwiftUI's default appearance transition doesn't fight the manual frame interpolation.

**Animation timing.** `.smooth(duration: 0.5)` symmetric on both directions (open and close). Earlier iterations used `.spring(response: 0.55, dampingFraction: 0.92)` and the open consistently felt faster than the close — the spring's settle/oscillation profile was asymmetric in perception even though the physics were identical. Switching to a duration-based curve eliminated the asymmetry. The deferred-clear was tightened from 680 ms to 510 ms to match.

**Constant 10pt corner radius.** Tried interpolating from 10pt (source-card) to 0pt (fullscreen) via a custom `AnimatableCornerClip: ViewModifier, Animatable` modifier; never visibly animated despite multiple variants (linear math, explicit `.animation(_:value:)`, transaction wrap). Root cause was likely SwiftUI's animation system not propagating through `let`-passed parameters into a custom modifier's `animatableData` the way it does for built-in modifiers like `.frame`. Switched to constant 10pt — matches the source card so the close-handoff has no corner-shape pop, and the slight rounding at fullscreen edges matches Apple Photos' own behavior.

**Reusable envelope.** Refactored from a monolithic `MediaViewerScreen` + private `ImagePinchZoomView` into three files:
- [Features/MediaViewer/MediaViewerScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/MediaViewer/MediaViewerScreen.swift) — shared envelope. Owns matched-geo zoom interpolation, corner clip, drag-dismiss visual effect (`.scaleEffect(dismissScale).offset(dismissOffset)` applied at outer level so both content kinds inherit it identically), and chrome (close button + caption).
- [Features/MediaViewer/ImageMediaContent.swift](apps/ios/DailyCadence/DailyCadence/Features/MediaViewer/ImageMediaContent.swift) — image specifics. Pinch-zoom 1×–5×, double-tap toggle, pan-when-zoomed, drag-down dismiss at scale 1. Writes dismiss state via `@Binding` to the envelope.
- [Features/MediaViewer/VideoMediaContent.swift](apps/ios/DailyCadence/DailyCadence/Features/MediaViewer/VideoMediaContent.swift) — video specifics.

**Photos-parity for video** required three tricks:
1. **Poster handoff during zoom.** Sync-decoded `posterData` in `init` shows the poster image immediately so the open-zoom has visible content from frame one (matches what the source card was showing). Crossfades to the live `AVPlayerViewController` once `currentItem.status == .readyToPlay` (polled at ~30 fps inside `.task`). Without this, the user sees a `ProgressView` spinner being zoomed for the first ~150 ms while AVPlayer loads.
2. **AVKit-coexisting drag-dismiss.** `AVPlayerViewController` is wrapped via `UIViewControllerRepresentable` with a `UIPanGestureRecognizer` attached to the controller's view. Delegate returns `true` from `shouldRecognizeSimultaneouslyWith` (coexists with all of AVKit's internal gestures — scrubber, tap-to-toggle-controls, etc.) and only returns `true` from `gestureRecognizerShouldBegin` when the initial velocity is vertical-dominant downward. Horizontal scrubs and taps fall through to AVKit untouched; vertical drags claim our recognizer for dismiss.
3. **Auto-pause on dismiss.** `isDismissing` flips synchronously when the viewer's `performDismiss` runs (X button, drag-commit, fallback). `VideoMediaContent` observes via `.onChange` and calls `player?.pause()` immediately so audio doesn't bleed through the 510 ms close animation.

The previous WIP entry in `docs/FEATURES.md` was rewritten to describe the shipped behavior; the `project_zoom_transition_wip.md` memory entry is removed (the architecture is in code, the bugs are fixed).

**Files touched:** [MediaViewerScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/MediaViewer/MediaViewerScreen.swift), [ImageMediaContent.swift](apps/ios/DailyCadence/DailyCadence/Features/MediaViewer/ImageMediaContent.swift) (new), [VideoMediaContent.swift](apps/ios/DailyCadence/DailyCadence/Features/MediaViewer/VideoMediaContent.swift) (new), [MediaTapHandler.swift](apps/ios/DailyCadence/DailyCadence/Models/MediaTapHandler.swift) (new), [RootView.swift](apps/ios/DailyCadence/DailyCadence/Navigation/RootView.swift), [TimelineScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/Timeline/TimelineScreen.swift), [CardsBoardView.swift](apps/ios/DailyCadence/DailyCadence/Features/Timeline/CardsBoardView.swift), [StackedBoardView.swift](apps/ios/DailyCadence/DailyCadence/Features/Timeline/StackedBoardView.swift), [KeepCard.swift](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/KeepCard.swift), [NoteCard.swift](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/NoteCard.swift), [ResolvedMediaImage.swift](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/ResolvedMediaImage.swift).

### Phase F.1.1b'.camera — Camera capture from the FAB (added this round)

Adds a third FAB menu item, **Take Photo or Video**, that presents the iOS camera directly in-app. Previously the FAB only had `Text Note` + `Photo or Video` (library); a fresh camera capture meant leaving DailyCadence to the system Camera app and re-entering through the photo library. Camera-captured assets now flow through the same import → trim → editor pipeline as picker selections.

**[Features/MediaCapture/CameraPicker.swift](apps/ios/DailyCadence/DailyCadence/Features/MediaCapture/CameraPicker.swift)** (new). `UIViewControllerRepresentable` over `UIImagePickerController(.camera)`. `mediaTypes = [UTType.image, UTType.movie]` so the native UI exposes the photo↔video mode switcher. The delegate copies the captured video URL out of the picker's temp scope into our app temp dir before reporting back, since the picker invalidates its own URL on dismiss. `UIImagePickerController` is API-marked deprecated in name only — Apple still ships it as the canonical camera surface (Mail and Notes both use it); the modern alternative `PHPickerViewController` is library-only.

**[MediaImporter.swift](apps/ios/DailyCadence/DailyCadence/Services/MediaImporter.swift)** gains two thin adapters: `makePayload(fromCameraImage: UIImage)` (encodes to JPEG q=0.92, hands to the existing `imagePayload(from:)`) and `makePayload(fromCameraVideoURL: URL)` (forwards directly to the existing `videoImportResult(from:)` pipeline). The video adapter inherits the trim-sheet hand-off for free — captures over the 60 s cap route to `VideoTrimSheet` automatically, same UX as picker imports.

**[MediaNoteEditorScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/NoteEditor/MediaNoteEditorScreen.swift)** refactor. Replaces `init(initialItem: PhotosPickerItem?)` with `init(initialMedia: InitialMedia?)` where `InitialMedia` is a nested enum: `.pickerItem(PhotosPickerItem)`, `.cameraImage(UIImage)`, `.cameraVideoURL(URL)`. The editor's `.task` switches on the case and calls the right `MediaImporter` adapter; everything downstream (trim sheet, crop, payload state, save) is shared. `.onChange(of: pickerItem)` continues to drive the in-editor Replace flow (picker-only — replacing-via-camera is a future iteration).

**[TimelineScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/Timeline/TimelineScreen.swift)** adds the camera menu item, `@State isCameraPresented`, and a `pendingCapture: InitialMedia?` slot that holds the selected source between picker/camera dismissal and editor presentation. Camera UI uses `.fullScreenCover` (modal full-screen is the right surface — sheet doesn't work for `UIImagePickerController(.camera)`).

**[Info.plist](apps/ios/DailyCadence/DailyCadence/Info.plist)** gains `NSCameraUsageDescription` + `NSMicrophoneUsageDescription`. Microphone is required for video audio; without the key, capturing a video crashes on AVCaptureDevice authorization.

**Inline-text-note attachment flow** (`NoteEditorScreen`'s `+image` toolbar action) is unchanged — it stays picker-only for now. Camera-attach-to-text-note is a follow-up if the FAB → media note path proves it; the architectural pieces (CameraPicker, importer adapters, InitialMedia) are reusable.

**Build clean.** Camera doesn't run in the simulator (no hardware), so functional verification needs a physical device; the simulator covers the picker, editor, trim, and import paths and those stay green.

### Phase F.1.2.bugbash — Six known-bug fixes in one round (added this round)

Knocked out the bugs Jon flagged on 2026-04-27, in impact order (data corruption → wrong UI state → polish):

**Bug 5 — Intro paragraph text duplicated below inline image (regression of Phase E.5.18b).** [save() in NoteEditorScreen](apps/ios/DailyCadence/DailyCadence/Features/NoteEditor/NoteEditorScreen.swift) intentionally strips empty trailing paragraphs to avoid persisting phantom blank rows in card rendering — but [populate(from:) in NoteDraftStore](apps/ios/DailyCadence/DailyCadence/Services/NoteDraftStore.swift) didn't re-add one when loading a saved note for edit. Result: a media-bearing note whose trailer was stripped on save reloads with body `[paragraph, media]`; both `message.get` and `trailerMessage.get` resolve to the same single paragraph block; both TextEditor widgets render identical text. Fix: new `ensureMediaParagraphInvariant()` helper on `NoteDraftStore` runs after `populate` assigns the body — same algorithm as `insertMedia`'s padding (ensure leading + distinct trailing when `hasMedia`). Empty trailer is editor-only; next save strips it again. The Phase E.5.18b regression test only covered fresh-draft inserts; added 3 new tests covering the populate path: trailing-missing, leading-missing, text-only-no-padding-needed.

**Bug 1 — Past-event note doesn't insert in correct timeline position until app refresh.** [TimelineStore.add(_:)](apps/ios/DailyCadence/DailyCadence/Services/TimelineStore.swift) appended without re-sorting; the next refresh fetched server-side-sorted rows, masking the bug. Fix: new private `sortByOccurredAtAscending()` runs after `add` and `update` (the latter so editing a note's `occurredAt` repositions it). Sort key matches `repository.fetchForDay`'s `order("occurred_at", ascending: true)`. Swift's sort is stable so notes that share a timestamp keep their insertion order. Two regression tests: past-time insert lands in front; update with new earlier time repositions to front.

**Bug 3a — Inline media in text notes renders blank in Board cards.** [InlineMediaBlockView.posterImage()](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/InlineMediaBlockView.swift) only checked `posterData` then `data` — both are nil for fetched-from-server media (the row's `MediaBlockDTO` carries refs only). Once a saved note reloaded from Supabase, the inline-block render fell through to a `Color.DS.bg2` empty box. Fix: kept the synchronous inline-bytes fast path (renamed `inlinePosterImage()`, kind-aware preference chain matching `MediaResolver.posterBytes`: image → thumbnail → full; video → poster), and fell back to `ResolvedMediaPoster` for fetched payloads (`ref` / `posterRef` / `thumbnailRef` set, no inline bytes). Same component standalone-media cards already use.

**Bug 3c — Inline media tap skips the zoom transition.** Tapping an inline image in a text-note Board card opened the viewer via legacy `.fullScreenCover` (slide-up), bypassing the F.1.1b'.zoom matched-geo zoom that standalone-media cards now use. Fix: `InlineMediaBlockView` accepts optional `mediaTapHandler: MediaTapHandler? = nil` and `blockId: UUID? = nil`. When both set (`KeepCard.bodyBlockView` passes them through), the block applies `MatchedGeometryModifier` to publish its frame under the BLOCK's UUID (distinct from the note's UUID, so each inline image gets its own matched-geo source) and routes taps to `handler.onTap(payload, blockId)`. When unset (preview surfaces, editor's strip), falls through to `.fullScreenCover` unchanged.

**Bug 2 — Timeline time-label wraps for "10:38 AM"-style times.** [TimelineItem](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/TimelineItem.swift) sized the time column at 44pt — fits 7-char "9:02 AM" but overflows 8-char "10:38 AM" / "12:59 PM". Bumped to 56pt + `.lineLimit(1)` so wrap is impossible even under future copy changes.

**Bug 4 — Settings → Note Types row's "6 customized" wraps to 2 lines.** Adding pets brought the overlapping-dots stack from 7 to 8 dots, eating ~12pt of horizontal slack. The "6 customized" detail wrapped because the cell didn't budget for an 8-dot stack + label + spacer + detail + chevron on smaller phones. Fix: `.lineLimit(1)` + `.fixedSize(horizontal: true, vertical: false)` on the trailing detail label so it keeps its natural width; the leading "Note Types" label can compress (it never needs to in practice — 10 chars fits comfortably).

Tests: 84/84 passing (+5 this round — the three populate-path tests for Bug 5 and the two sort tests for Bug 1). Build clean.

### Phase F.1.2.pets — Pets note type (added this round)

Adds a 7th system note type for pet-related logs (vet visits, walks, feeding, meds, weight). New `NoteType.pets` case + `pawprint.fill` SF Symbol + `Color.DS.blush` / `blushSoft` pigment pair (chosen over honey since honey is reserved for the pin status indicator and would visually collide on a pinned pets card; blush was already declared in the design system as a "companion bright" alongside periwinkle and honey, previously unused as a category pigment).

**iOS** — single-file change in [NoteType.swift](apps/ios/DailyCadence/DailyCadence/Models/NoteType.swift): new case + 4 switch arms (`title` / `defaultColor` / `softColor` / `systemImage`). Every other surface auto-handles the new case because they iterate `NoteType.allCases` (NoteTypePickerScreen, SettingsScreen, TypeChip, StackedBoardView, TimelineScreen group/stack sections) or key by `rawValue` (`NoteTypeStyleStore` user overrides). The Swift compiler verified there were no other exhaustive switches over `NoteType` to update.

**Database** — [supabase/migrations/20260427000005_add_pets_note_type.sql](supabase/migrations/20260427000005_add_pets_note_type.sql) (new): single `INSERT INTO note_types` row with slug=`pets` so `NotesRepository`'s slug→id cache resolves it. `color_hex = #F2C9C4` mirrors blush's light-mode value (the dark-mode value resolves client-side via the dynamic color token; the DB stores a single hex for non-iOS clients). `on conflict do nothing` keeps the migration idempotent. **Run via `supabase db push` or paste into Supabase SQL editor** — Jon's project hasn't auto-applied the new migration yet at the time of this commit.

**`structured_data_schema`** is empty `{"fields": []}` for now, matching workout/meal/sleep — pet-specific fields (pet name, weight, vet info) are a future iteration via UPDATE, no migration needed.

Tests: 79/79 still passing. Manual verification: type picker in Settings → Note Types now shows Pets with paw icon + blush dot; FAB → Text Note → type picker likewise.

### Known bugs / polish TODO

Quality issues to address — separate from the feature roadmap below.

- **Inline media on Timeline rail (Bug 3b — design decision pending).** `MockNote.timelineMessage` flattens paragraph blocks to a single AttributedString and **intentionally** drops media — the original call was that the dense Timeline rail favors text-only summaries, with the Board view as the medium-rich surface (per FEATURES.md line 264). Jon flagged the missing media on Timeline at 2026-04-27 — needs a decision: keep the Timeline-favors-text design, or render inline media there too (would require `NoteCard` to walk the body block-by-block like `KeepCard` does, plus the matched-geo handler plumbing if we want zoom on Timeline taps too).

### Phase F.1.2.refresh — Three quick polish items (added this round)

Knocked out the three items in Jon's "tackle in order" list:

**Copy refresh — FAB menu + Settings appearance.** FAB items renamed for warmer in-brand voice: "Text Note" → "Write a thought", "Photo or Video" → "Add from Photos", "Take Photo or Video" → "Snap something". Settings → Appearance: "Primary color" → "Theme color". Internal `ThemeStore` / `PrimaryPaletteRepository` naming unchanged.

**Edit caption on existing media notes.** Long-press a media card → "Edit caption" entry in the contextMenu opens a lightweight `.medium`-detent sheet ([CaptionEditSheet.swift](apps/ios/DailyCadence/DailyCadence/Features/NoteEditor/CaptionEditSheet.swift)) with a multi-line TextField (3–10 lines) + Cancel / Save toolbar. Save reconstructs the `MockNote` with an updated `MediaPayload.caption` and routes through `TimelineStore.update` — same optimistic-in-memory + background-persist flow the rest of the app uses. Empty-string saves clear the caption (treated as `nil`). The card-level callback chain follows the same pattern as `onRequestDelete`: `KeepCard` / `NoteCard` accept `onRequestEditCaption`, `CardsBoardView` and `StackedBoardView` (3 levels: outer + `CollapsedStackCell` + `ExpandedColumnSection`) thread it through, and [TimelineScreen](apps/ios/DailyCadence/DailyCadence/Features/Timeline/TimelineScreen.swift) owns the `@State editingCaptionNoteId` + sheet presentation + the `saveCaption(noteId:newCaption:)` reconstruction. ContextMenu order: Pin → Edit caption → Delete. Only surfaces when `isMediaNote` (text variants don't carry captions).

**Note-type picker scaling (combo A+B).** Replaces the editor's previous horizontal-scroll chip row (which became a hunt at 7+ types and didn't scale to custom user types) with a defer-the-decision + searchable sheet pattern.
- **A. Defer.** Editor opens straight to writing — only a single chip shows the current type near the title field. The user never has to interact with a type picker just to start typing.
- **B. Searchable sheet.** Tap the chip → [NoteTypePickerSheet.swift](apps/ios/DailyCadence/DailyCadence/Features/NoteEditor/NoteTypePickerSheet.swift) (`.medium` / `.large` detents) presents a search field + 2-column `LazyVGrid` of all `NoteType.textEditorPickable`. Type to filter live (case-insensitive `contains` on the type's display name). Tap a cell → commits + dismisses. Cancel keeps the current selection.

Removed the obsolete `typePickerExpanded: Bool` state + the resume-draft-aware init logic that derived its default. The new picker scales arbitrarily — works at 7 types or 70 — so future system types (book, recipe, etc.) and custom user types can land without changing the UI.

Build clean, 84/84 tests still passing.

### Phase F.1.2.weekstrip — Today screen week-strip indicator (added this round)

Minimal motivational indicator slotted between the date header and the Timeline / Board view toggle on the Today screen. Shows the current week as 7 columns (S M T W T F S, locale-aware first-day-of-week via `Calendar.current.veryShortWeekdaySymbols`). Each column has a small dot below the letter: filled sage when that day has at least one note, hollow ring when empty. Today's column gets a subtle sage-tinted ring; the user's currently-selected day gets a sage-soft pill background. Tapping any column navigates the timeline to that day via `TimelineStore.shared.selectDate(_:)` — the strip doubles as week-level navigation.

**Data layer.** New [NotesRepository.fetchDaysWithNotes(userId:weekContaining:)](apps/ios/DailyCadence/DailyCadence/Services/NotesRepository.swift) — single bulk query selecting only `occurred_at`, returning `Set<Date>` (normalized to `startOfDay`). Cheap query; tiny payload even for heavy loggers.

**Cache layer.** New [WeekStripStore](apps/ios/DailyCadence/DailyCadence/Services/WeekStripStore.swift) (`@Observable @MainActor`) singleton holds `daysWithNotes` for the currently-loaded week. `load(userId:day:)` short-circuits when called for the same week (idempotent — fires from `RootView`'s existing `.task(id:)` alongside `TimelineStore.load`). Optimistic updates from `TimelineStore.add` / `update` / `delete` mutate the in-memory set immediately so the strip's dot fills the moment the user saves a note (same-week mutations only — cross-week changes pick up on the next week refetch).

**View layer.** New [WeekStripView](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/WeekStripView.swift) — pure presentational, takes `[Date]` + `selectedDay` + `Set<Date> filledDays` + `onTap`. Sized ~36pt tall. `WeekStripView.days(forWeekContaining:)` is the convenience builder. Slotted into `TimelineScreen.header` after the (conditional) `todayPill` row.

**Lifecycle hooks.** `TimelineStore.add(_:)` calls `WeekStripStore.shared.noteAdded(occurredAt:)`. `TimelineStore.update(_:)` computes the old day's remaining-count locally (excluding the just-swapped note) and calls `noteUpdated(oldOccurredAt:newOccurredAt:oldDayRemaining:)` so a moved note empties its old day's dot only when it was the last note there. `TimelineStore.delete(noteId:)` mirrors via `noteRemoved(occurredAt:remainingForDay:)`. Persist-failure reverts don't currently round-trip back to the strip — minor edge case; the next week-change refetches authoritative state.

**FEATURES.md** updated with the new component description.

Build clean, 84/84 tests passing.

### Phase F.1.2.book — Book note type (added this round)

Adds an 8th system note type for reading logs. Use case: "I read 2 chapters of X tonight — jot down thoughts and a quick summary." Same shape as the pets type from earlier this round but with structured-data fields populated for the future renderer.

**iOS** — single-file change in [NoteType.swift](apps/ios/DailyCadence/DailyCadence/Models/NoteType.swift): new `book` case + 4 switch arms (`title` / `defaultColor` / `softColor` / `systemImage`). Icon is `book.closed.fill`. Pigment is the new `Color.DS.book` / `Color.DS.bookSoft` pair — coffee-brown light (#6B4F3A) / muted warm tan dark (#A38971), reads as scholarly / quiet, distinct from meal's amber and workout's terracotta at small dot sizes. Tokens added to [Tokens/Colors.swift](apps/ios/DailyCadence/DailyCadence/DesignSystem/Tokens/Colors.swift) alongside the existing semantic note-type pigments.

**Database** — [supabase/migrations/20260427000006_add_book_note_type.sql](supabase/migrations/20260427000006_add_book_note_type.sql): single `INSERT` row with `structured_data_schema` populated for four optional fields:
- `title` — book title (string)
- `author` — book author (string)
- `progress` — free-form ("Ch 3–5", "p. 122–187") so the user isn't constrained to one format
- `is_finished` — toggle for marking a book complete

Schema is reserved-but-not-yet-rendered. The future structured-data renderer (captured in Phase F+ TODO) will surface these as light scaffolding above the free-form body — book notes are still primarily about free-writing thoughts; the fields are guides, not a cage. Existing clients without the renderer ignore the schema and edit the body normally.

**Run via `supabase db push` or paste into the SQL editor** before saving a book-typed note — until the row exists, `NotesRepository.insert` throws `unknownNoteTypeSlug("book")`.

Build clean, 84/84 tests passing.

### Phase F.1.2.zoomdrag — Drag-to-dismiss coord-space fix (added this round)

Drag-down-to-dismiss on `MediaViewerScreen` was broken for photos — image duplicated, shook violently, split into two copies drifting opposite directions, screen flickered. Severity scaled with timeline card count. Bug had been live since the matched-geo zoom shipped (Phase F.1.1b'.zoom) and survived three fix attempts that all targeted a (wrong) re-render-cascade theory: `MediaTapHandler: Equatable` (a12d9b2), moving `sourceFrames` to a non-observed `CardFrameStore` singleton (3aa2480), and wrapping gesture writes in `withTransaction(disablesAnimations: true)` (2e21e4d). None helped because the bug wasn't in re-render frequency.

**The diagnostic we missed for three sessions:** drag-to-dismiss was always working fine for **video**. Both image and video write to the SAME drag-dismiss bindings on `MediaViewerScreen`, traverse the SAME envelope, hit the SAME @State. If the bug were in bindings/cascade/state, it would affect both. The image-only failure pointed straight at the one thing that's different: SwiftUI `DragGesture` (image) vs UIKit `UIPanGestureRecognizer` (video).

**Root cause.** `DragGesture()` defaults to `coordinateSpace: .local` — translation reported in the modified view's own frame. The image was being `.scaleEffect`'d (1.0 → 0.7) and `.offset`'d by the gesture's own writes; as the view shrunk and shifted under the finger, the gesture's local coordinate space shifted with it. `value.translation` became a moving target, oscillating each gesture event. That oscillation fed the next `dismissOffset` write — positive feedback loop at ~60 Hz. The visible "two images splitting left/right" was the renderer painting both oscillating "solutions" within a single frame as the rapid back-and-forth resolved. UIKit `UIPanGestureRecognizer.translation(in:)` reports absolute pixel deltas of the touch since the gesture started, immune to any transform applied to the view after — which is why video never had the bug.

**iOS** — one-line change in [ImageMediaContent.swift](apps/ios/DailyCadence/DailyCadence/Features/MediaViewer/ImageMediaContent.swift): `DragGesture()` → `DragGesture(minimumDistance: 10, coordinateSpace: .global)`. Pinch-zoom + pan-while-zoomed unaffected (different gesture; the panning math runs in local `offset` state which is stable when zoomed-and-panning).

**Lesson** captured in feedback memory `feedback_debug_enumerate_working_paths.md`: when a fix theory has failed twice, stop iterating on the theory and instead enumerate adjacent paths that work. The contrast between working and broken siblings constrains the search far better than another variation on the same hypothesis. The "video drag works" fact lived in Jon's head, not in the WIP memory file — which is why three sessions kept refining the wrong hypothesis. The WIP memory has been updated to capture both the resolution and the meta-lesson.

### Phase F.1.2.exifdate — Capture-date metadata overlay in the viewer (added this round)

When viewing a photo or video full-screen, the user now sees the moment the asset was captured (e.g., "Apr 27, 2026 at 8:42 PM") below the close button in the same gradient zone as the caption — distinct from the note's `occurredAt` timestamp (which is when the note was logged, not when the moment happened). For library imports, the date comes from EXIF / asset metadata; for camera captures, it's `Date()` at the shutter press.

**iOS — model.** New optional `capturedAt: Date?` field on [MediaPayload](apps/ios/DailyCadence/DailyCadence/Models/Media.swift). Defaults to `nil` so existing call sites and notes saved before this round don't render fake dates.

**iOS — extraction.** [MediaImporter](apps/ios/DailyCadence/DailyCadence/Services/MediaImporter.swift):
- `extractCaptureDate(from data: Data)` reads EXIF `DateTimeOriginal` via `CGImageSourceCopyPropertiesAtIndex` → `kCGImagePropertyExifDictionary`. Format `yyyy:MM:dd HH:mm:ss` parsed with POSIX locale + current timezone — pragmatic Phase 1 approach, correct in the common case (user views photos in the same TZ they were taken in), slightly off when traveling. Apple Photos does similar.
- `imagePayload(from:capturedAtOverride:)` — library imports extract from source bytes (the downscale path strips EXIF, so reading must happen before re-encode); camera captures pass `Date()` via the override since `UIImage.jpegData()` doesn't carry metadata.
- `videoCreationDate(asset:)` loads `AVAsset.creationDate` for video imports. Trim path preserves the original capture date through `VideoTrimSource` — trimming a clip doesn't change when it was recorded.

**iOS — persistence.** [NotesRepository.MediaBlockDTO](apps/ios/DailyCadence/DailyCadence/Services/NotesRepository.swift) gains `capturedAt: Date?` in the body JSONB shape. `decodeIfPresent` / `encodeIfPresent` both directions, no SQL migration needed — JSONB tolerates new optional fields. Old notes without the field decode with `capturedAt = nil`.

**iOS — propagation.** Three reconstruction sites that build a fresh `MediaPayload` from an existing one now forward `capturedAt`: `MediaNoteEditorScreen.commit` (crop + final save), `NoteEditorScreen.confirmCrop` (inline crop), `TimelineScreen.saveCaption` (caption edit).

**iOS — viewer chrome.** [MediaViewerScreen.bottomChrome](apps/ios/DailyCadence/DailyCadence/Features/MediaViewer/MediaViewerScreen.swift) renders the date as 12pt sans `white.opacity(0.85)`, leading-aligned, sharing the existing gradient with the caption. Caption stays centered; date sits below it (or alone in the gradient when no caption). When neither is present, the gradient is suppressed entirely so a metadata-less screenshot gets a clean unobstructed bottom. Date format: `Date.formatted(date: .abbreviated, time: .shortened)` — locale-aware ("Apr 27, 2026 at 8:42 PM" in en-US).

**Tests** — `MediaPayloadTests.capturedAtPreserved` verifies init storage + nil-default. Existing 87 tests pass unchanged (the new field is optional with default nil, so no constructor-site signature breaks).

**Out of scope this round** — location overlay, capturedAt editing UI, time-zone embedding. The Phase F+ TODO entry stays open for those follow-ons.

### Phase F.1.2.midnight — Day rollover at midnight (added this round)

Before this round: with the app open across midnight, the date header stayed "Today · Saturday" instead of flipping to "Yesterday · Saturday," the Today pill didn't surface, and the week strip's today ring didn't move. The bug: `Calendar.current.isDateInToday(_:)` reads `Date()` each invocation but isn't observed by SwiftUI — when no `@Observable` property changes, no view body re-runs, and the relative-date checks stay frozen at last-render time.

**iOS — store.** [TimelineStore](apps/ios/DailyCadence/DailyCadence/Services/TimelineStore.swift):
- New `currentDay: Date` property (observed via the class-level `@Observable` macro). Source of truth for "what is today's local-calendar day."
- `init` subscribes to `UIApplication.significantTimeChangeNotification` — Apple's canonical signal for day rollover, time-zone change, DST shift, and manual clock changes. Same notification Calendar / Reminders / Stocks consume. Singleton lives forever, so the closure-based observer is never removed (no deinit ever runs).
- `refreshCurrentDay()` is idempotent: compares stored day to `startOfDay(.now)`, no-ops on equality, otherwise wraps the write in `withAnimation(.smooth(duration: 0.5))` so every observer crossfades / slides instead of snapping.
- `isViewingToday` compares `selectedDate == currentDay` (was: `isDateInToday(selectedDate)`).
- **selectedDate is not auto-advanced.** The user explicitly chose a day; midnight shouldn't yank them. The Today pill becomes their explicit way back to today.

**iOS — app lifecycle.** [RootView](apps/ios/DailyCadence/DailyCadence/Navigation/RootView.swift) observes `@Environment(\.scenePhase)` and calls `TimelineStore.shared.refreshCurrentDay()` on every `.active` transition. Belt-and-suspenders for the suspended-across-midnight case (iOS may not deliver the system notification reliably across long suspension). The handler is idempotent so the foreground re-check is free when nothing changed.

**iOS — consumers.** Three consumers stopped calling `Calendar.current.isDateInToday(_:)` and now compare against `currentDay`:
- [TimelineScreen.dayOfWeek](apps/ios/DailyCadence/DailyCadence/Features/Timeline/TimelineScreen.swift) — relative-day labels ("Today · Monday" / "Yesterday · Monday" / "Tomorrow · Monday") use `date == today` / `date == cal.date(byAdding: .day, value: -1, to: today)` etc.
- [WeekStripView.column(for:)](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/WeekStripView.swift) — accepts `currentDay: Date` as a new init parameter; `isToday` is `cal.isDate(day, inSameDayAs: currentDay)`. TimelineScreen's `weekStrip` builder forwards `TimelineStore.shared.currentDay`.
- `TimelineStore.isViewingToday` itself.

**The animation flourish.** [WeekStripView](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/WeekStripView.swift) — the today-column ring is wrapped in `matchedGeometryEffect(id: "today-ring", in: namespace)`. When midnight rolls over within the displayed week (e.g., Mon → Tue), SwiftUI **slides** the sage ring between adjacent columns instead of fading out + fading in — looks like the today marker is physically walking forward. When the new today is outside the displayed week (cross-week rollover, e.g., user is viewing last week's Saturday and midnight ticks to Sunday of the new week), the ring just fades out — there's no destination column in the rendered view to slide to.

**Per Jon's edge-case request.** The cross-week rollover behaves correctly: if the user is viewing a date in the previous week (e.g., last Saturday) and midnight advances `currentDay` to a date outside the displayed week, the today indicator simply disappears from the strip. The user's selectedDate is preserved; they can navigate back to today via the Today pill.

**Tests** — `TimelineStoreTests` gains 3 cases: `currentDayInitialisedToStartOfToday`, `isViewingTodayDerivesFromCurrentDay`, `refreshCurrentDayIsIdempotent`. All 87 tests pass.

### Phase F.1.2.weekstrip.dates — Week strip date column + dot bump (added this round)

The week strip's dot was 6pt, getting visually lost against the 11pt letter and the pill chrome — a small detail but the dot is the strip's personality (the "did I write today" affordance). Bumped to 9pt (frame 8→11pt for proportional padding) so it holds its own.

Added a day-of-month number row between the letter and the dot — three-row layout matching Apple Calendar's week-strip pattern. Each column now reads (top to bottom): weekday letter (10pt, bold for today) / day number (13pt, semibold for today) / 9pt dot. `.monospacedDigit()` on the number so single-digit days (1-9) and double-digit (10-31) don't shift the column center as the week walks. VStack spacing tightened from 6pt → 4pt to keep the three rows reading as one column.

Strip is ~14pt taller now. Trade is fair — the strip is the at-a-glance navigator and earns the height for at-a-glance day numbers. Today still reads first via the letter+number bold treatment + the existing sage ring.

### Phase F.1.2.captionfix — Edit Caption double-placeholder (added this round)

Pre-existing bug from Phase F.1.2.refresh's caption-edit sheet: both a custom `Text("Add a caption…")` overlay AND the `TextField`'s built-in placeholder ("Caption" — passed as the title parameter) rendered simultaneously when the field was empty, producing visible overlap. Deleted the custom overlay + the wrapping ZStack and used the built-in TextField placeholder with the design copy "Add a caption…". One less moving part; SwiftUI's default placeholder color is fine.

### Phase F.1.2.bgcache — Decoded image-background cache (added this round)

Tight follow-on to F.1.2.daycache (above). The day-cache eliminated the empty-state flash on day-switch, but the image-background card still flickered a beat after returning to a day — the post-refetch `hasLoaded = true` cascaded through `TimelineScreen.body`, which observed `isLoadingNotes`, which forced all `KeepCard`s to rebuild (their closure parameters defeat SwiftUI's Equatable optimization). Each rebuild called `Image(uiImage: UIImage(data: imageData))` — re-decoding the JPEG even though the bytes were unchanged. Sub-perceptible per render but visible when stacked under the cascade.

**The fix.** Skip the re-decode entirely. New [BackgroundImageCache](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/BackgroundImageCache.swift) singleton wraps `NSCache<NSString, UIImage>`. Cards call `BackgroundImageCache.shared.image(forKey: cacheKey, data:)`; the cache decodes once on first hit and returns the cached `UIImage` on every subsequent render. `NSCache` auto-evicts under memory pressure — no manual size management.

**Cache keys.** `MockNote.ImageBackground` gains `cacheKey: String?` populated in `fetchBackground` from the `backgrounds.id.uuidString` (immutable per row — each `backgrounds` row's `image_url` never changes; on edit we INSERT a new row rather than UPDATE, so a given key always resolves to the same bytes forever). `MockNote.Background.image(...)` and `NoteBackgroundStyle.image(...)` both gained the field as a passthrough.

**Client-side images.** Editor preview path (just-picked image, not yet uploaded) carries `cacheKey: nil` and bypasses the cache via direct decode. The editor session is short enough (user picks → tweaks opacity → saves in seconds) that the lack of caching is invisible. After save and refetch, the saved background gets a populated cacheKey and benefits going forward.

**Pattern.** This is the canonical iOS approach — Apple's UIKit uses NSCache extensively, every major image library (SDWebImage / Kingfisher / Nuke) implements the same shape, SwiftUI's `AsyncImage` does it internally for URL-based images. Not hacky.

**Render sites updated**: NoteCard line 376 (Timeline standalone-media path), KeepCard line 228 (Board), NoteEditorScreen line 292 (canvas preview) + line 328 (18pt toolbar `🖼` icon thumb). The shape change to `NoteBackgroundStyle.image(data:opacity:cacheKey:)` rippled into 1 test which I updated.

90/90 tests pass.

### Phase F.1.2.daycache — Per-day note cache (added this round)

Pre-this-round, navigating between days cleared `notes` to `[]` and forced a fresh fetch on every `selectDate`. Returning to a previously-viewed day showed the empty state for the ~300-500 ms the fetch took before notes reappeared. Visible "blank → cards" flash on every back-navigation.

**The fix.** [TimelineStore](apps/ios/DailyCadence/DailyCadence/Services/TimelineStore.swift) gains a `notesByDay: [Date: [MockNote]]` in-memory cache keyed by `startOfDay`. On `selectDate`:
- Cache hit → `notes = cached` immediately (no empty flash).
- Cache miss → `notes = []` (same as before — first visit to a day shows the empty state briefly).

**Cache is a render hint, not a fetch-skip.** Per Jon's clarification: `hasLoaded` stays false on hydration, so RootView's `.task(id:)` still fires the background refetch. The user sees cached cards instantly + a thin loading bar at the top while the fetch happens in the background — Apple Mail / News pattern.

**Surgical merge replaces full-array swap.** Switched `load()` from `notes = fetched` to a new `mergeFetched(_:)` helper that:
- **Removes** notes whose ids no longer exist on the server (deleted from another device, etc.)
- **Updates in place** notes whose ids match — overwrites with the server's version so any field changes propagate. SwiftUI's `ForEach` keeps view identity by id, so unchanged-rendered-output updates are graceful.
- **Appends** notes that exist on the server but not yet locally, then re-sorts to land them in chronological position.

On a cold load (notes was empty), this collapses to "append everything and sort" — identical effective output to the prior `notes = fetched` for the empty-start case, just routed through the same code path.

**Cache invalidation on mutations.** `add` / `update` / `delete` mirror into `notesByDay[selectedDate]` so subsequent navigations see the latest state. Cross-day cases (rare — user creates a note dated for a different day, or edits a note's `occurredAt` to move it across days) invalidate the destination day's cache so the moved note appears on next visit there.

**Future hooks.** `clearDayCache()` exists but isn't wired yet — it's intended for the auth-change path so user A's cached days don't bleed into user B's session when real Sign in with Apple ships. Today's anon-only flow doesn't need it.

**Race guard.** Day-switch during an in-flight fetch is handled: the fetch result still warms `notesByDay[fetchedDay]` (so a future return to that day benefits) but only updates `notes` if `selectedDate` still matches the fetched day at completion time.

**Tests** — `TimelineStoreTests` gains `dayCacheRehydratesNotesOnReturn` (cache HIT after round-trip, hasLoaded stays false) and `clearDayCacheDropsAllEntries` (clear contract). 90/90 pass.

### Phase F.1.2.inlinevideo — First-tap inline video playback (added this round)

Tapping a video poster in a card now starts muted inline playback (plays once from start), instead of jumping straight to the fullscreen viewer. Tap during playback opens fullscreen with audio. When the single playback finishes, the card resets to its initial state (poster + play button overlay). Closes the last open item from the F.1.1b' media UX bundle.

**iOS — new component.** [InlineVideoPlayer](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/InlineVideoPlayer.swift) — minimal `UIViewRepresentable` over an `AVPlayerLayer`-backed view. Distinct from `VideoMediaContent` (the fullscreen viewer): no AVKit chrome, no drag-dismiss, no scrubber, just muted single-shot playback. `actionAtItemEnd = .pause` so the player stops at the last frame; the card sees the `AVPlayerItemDidPlayToEndTime` notification and flips `isInlinePlaying` to false. The `dismantleUIView` hook pauses the player and removes the observer when SwiftUI hides the view (card setting state false, or `.onDisappear` on scroll-out).

**iOS — URL resolution.** `InlineVideoPlayer.resolveURL(for:)` static helper returns a `Source { url, isTempFile }` struct. Prefers a streaming signed URL when the payload has a `ref` (saves writing the full video to disk); falls back to a temp file from inline `data` for newly imported clips that haven't uploaded yet. The `isTempFile` flag drives caller-side cleanup.

**Card wiring** — same pattern in three places: [NoteCard](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/NoteCard.swift), [KeepCard](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/KeepCard.swift), [InlineMediaBlockView](apps/ios/DailyCadence/DailyCadence/DesignSystem/Components/InlineMediaBlockView.swift). Each card gets three `@State` properties (`isInlinePlaying`, `inlineVideoURL`, `inlineVideoIsTempFile`) plus `startInlineVideo` / `stopInlineVideo` helpers. Tap behavior:

- Image media: unchanged (single tap → fullscreen).
- Video media, not playing: `startInlineVideo` (resolve URL async → set state → render `InlineVideoPlayer`).
- Video media, playing: `stopInlineVideo` (release the player) → fire `mediaTapHandler.onTap` to open fullscreen.

`.onDisappear { stopInlineVideo() }` on the media row releases the player when the card scrolls out — important for memory and battery, especially on the Board view where many cards are off-screen.

**Why stop inline before fullscreen.** The fullscreen viewer creates its own `AVPlayer` with audio enabled. If the inline player kept running while the viewer's player started, the user would hear the same audio twice (or worse, see frame stutter from two decoders against the same source). Stopping inline first is the cheap, correct fix.

**Out of scope.** Autoplay-in-view (Instagram pattern), looping, scroll-aware play-pause based on visible-fraction, in-card scrubber. The `InlineVideoPlayer` is intentionally minimal — these are easy to add later if the UX warrants it.

Build clean, 88 tests pass.

### Phase F.1.2.swatchpersist — Swatch (color) background persistence (added this round)

Closes the bg-persistence story: `MockNote.Background.color(swatchId:)` now round-trips alongside `.image(...)`. Pre-this-round, picking a swatch background still vanished on relaunch because last round's `encodeBackground` returned nil for the `.color` case (deferred as a separate F+ TODO; this is that follow-on).

**Encode side.** Find-or-INSERT pattern in [NotesRepository.encodeBackground](apps/ios/DailyCadence/DailyCadence/Services/NotesRepository.swift):
- New `fetchBackgroundIdForSwatch(swatchId:userId:)` — `SELECT id FROM backgrounds WHERE user_id = $1 AND kind = 'color' AND swatch_id = $2 ORDER BY created_at LIMIT 1`. Returns nil if the user has never picked this swatch before; otherwise returns the existing row's id.
- If a hit: just plumb the id into `notes.background_id`, no INSERT.
- If a miss: INSERT a per-user `backgrounds` row (`kind='color'`, `swatch_id` set, opacity 1.0), use the new id.

Most users re-pick the same handful of swatches, so the cache hit rate is high in practice — typical pattern is "INSERT once per swatch per user, then SELECT for every subsequent save with that swatch."

**Decode side.** Existing `fetchBackground(id:)` switched from a single-kind guard to a `switch row.kind` so both `image` and `color` rows resolve. Color rows pull `swatch_id` directly from the row and return `.color(swatchId:)` — the iOS palette repository renders the actual color from the design-system swatch JSON, so the row only needs to remember the swatch id.

**Schema.** No migration — the `backgrounds.swatch_id text` column has existed since the original `20260427000001_notes_init.sql`. This round just started using it.

**Future enhancement (still TODO)** — in-memory `swatchId → backgrounds.id` cache to skip the SELECT after the first hit per session. Phase 1 lookups are 1 row each, RLS-scoped to the user, so the cost is in noise — revisit only if profiling shows the SELECT in a hot path.

Build clean, 88 tests pass.

### Phase F.1.2.bgpersist — Image-background persistence (added this round)

Per-note image backgrounds now survive app relaunch. Pre-this-round, `notes.background_id` was hardcoded `nil` on insert; if you picked a photo background and reopened the app, the photo was gone. Photo cards reverted to whatever swatch (or no) background, losing the user's curation.

**Storage layer.** [`SupabaseStorageImpl`](apps/ios/DailyCadence/DailyCadence/Services/MediaStorage.swift) parameterized by bucket via init — was hardcoded to `note-media`, now takes `bucket: String` so backgrounds and media share the upload/sign/delete plumbing against different buckets. New `MediaStorageProvider.backgrounds` static instance binds to `note-backgrounds` (created in `20260427000002_storage_buckets.sql` with full RLS already in place — no migration needed). `MediaStorageProvider.current` continues binding to `note-media` for media-note bytes.

**Encode side.** New `encodeBackground(_:userId:)` in [NotesRepository](apps/ios/DailyCadence/DailyCadence/Services/NotesRepository.swift):
- `nil` background → returns `nil` (no row created)
- `.color(swatchId)` → returns `nil` for now — swatch ↔ `backgrounds` resolution is a separate F+ TODO that requires either seeding library rows for design-system swatches or doing inline INSERTs per swatch encountered. Swatch backgrounds remain session-only.
- `.image(let img)` → uploads bytes via the backgrounds storage impl (filename `{uuid}.jpg`, JPEG content type — `BackgroundPickerView` already downscales the picked photo to JPEG q=0.85 via `MediaImporter.downscale`), then INSERTs a `backgrounds` row with `kind='image'`, `image_url` = bucket-relative path, `opacity` from the payload. Returns the new row's id, which `encodeForInsert` plumbs into `NoteRowInsert.background_id`.

**Decode side.** New `fetchBackground(id:)` in NotesRepository:
- SELECTs the `backgrounds` row by id
- For `kind='image'`: reconstructs a `MediaRef(provider: "supabase", path: row.image_url)`, gets a 50-min signed URL via the backgrounds storage impl, downloads bytes via `URLSession.shared`, returns `MockNote.Background.image(ImageBackground(imageData: data, opacity: row.opacity))`
- For `kind='color'`: returns `nil` (swatch resolver TODO)
- Failures (network error, missing row, decode failure) are caught + logged + return `nil` so a broken background never takes down the whole note

`decode(_:)` is now `async` so `fetchBackground` can run inline — a per-row Storage fetch is required for any note that has an image background. `fetchForDay` switched from `rows.compactMap(decode(_:))` to a serial `for row in rows` loop with `await decode(row)`. Serial is fine for typical day loads (5-15 notes, mostly without backgrounds); revisit with `withTaskGroup` if heavy-bg usage causes load latency.

**Update path** uses the same `encodeForInsert` so editing a note also re-runs the bg encode. **Known inefficiency**: every save re-uploads the bg bytes since `MockNote.ImageBackground` doesn't carry a ref. The old `backgrounds` row + Storage object become orphans. A future GC sweep + a `ref` field on `ImageBackground` to skip re-upload when bytes haven't changed are deferred to Phase F+.

**Schema-side.** No SQL migration — `notes.background_id` FK and the `backgrounds` table both exist from the original `20260427000001_notes_init.sql`. The bucket and its RLS exist from `20260427000002_storage_buckets.sql`. This round was 100% iOS code wiring up plumbing that already existed.

Build clean, 88 tests pass.

### Phase F.1.2.scrolledge — Reverted, deferred for restructure (this round)

Tried twice, reverted both — captured here so the next attempt doesn't repeat the same dead ends.

**Attempt 1: iOS 26 `.scrollEdgeEffectStyle(.soft, for: .top)`** (commit 3140bef). Compiled but produced no visible effect. Apple's declarative API for soft-fade was added at WWDC25 specifically for this pattern, but it requires a visible toolbar's chrome to project from. TimelineScreen explicitly hides the navigation bar (`.toolbar(.hidden, for: .navigationBar)`) for its custom date header, so there's no toolbar to anchor the effect.

**Attempt 2: Manual `LinearGradient` overlay** (commit 1e0a613). The standard pre-iOS-26 fallback for custom-header designs. Worked syntactically but produced visibly broken UI: the gradient painted OVER the static date header at `scrollOffset == 0` because it sits at `alignment: .top` of the ScrollView unconditionally — bisecting "April 27" and the Today pill before any scrolling happens. Just making the gradient taller wouldn't fix it; it'd still cover the header at rest.

**Why both failed: structural, not stylistic.** The chrome (date row + week strip) lives INSIDE the scrolling content. There's nothing meaningful to fade because the chrome IS what scrolls. Apple Calendar / Reminders / Mail don't have this problem because their date / category title sits OUTSIDE the scroll, pinned at the top, with content scrolling under it via the system's toolbar-backed soft fade.

**The proper fix (deferred).** Pin the date row + week strip outside the ScrollView using `.safeAreaInset(edge: .top)`, layer an `.ultraThinMaterial` backdrop on the pinned chrome so cards softly blur underneath as they scroll up. This is the iOS-native answer and removes the underlying structural issue. Captured in the Phase F+ TODO below with full design context.

**Reverted by**: removing the gradient overlay from [TimelineScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/Timeline/TimelineScreen.swift). Today screen returns to scrolling cleanly off the top edge (hard cut, no fade) until the chrome-pinning refactor lands.

### Phase F.1.2.recipe — Recipe note type (added this round)

Adds a 9th system note type for recipe screenshots and tags. Use case: "I want to save this dish I saw on Instagram so I can find it later." Snap a screenshot, optionally add the dish title, food type ("Korean," "Italian"), and a few tags ("spicy," "weeknight," "date-night"). Future cross-note search will use the tags + food_type to surface "all my Korean recipes" or "all my spicy weeknight ideas."

**iOS** — single-file changes in [NoteType.swift](apps/ios/DailyCadence/DailyCadence/Models/NoteType.swift): new `recipe` case + 4 switch arms. Icon is `frying.pan.fill` — distinct from meal's `fork.knife` (which evokes eating, not cooking). Pigment is the new `Color.DS.recipe` / `Color.DS.recipeSoft` pair — paprika red (#CC462D light / #E16E50 dark). Tokens added to [Tokens/Colors.swift](apps/ios/DailyCadence/DailyCadence/DesignSystem/Tokens/Colors.swift) alongside the existing semantic note-type pigments. The color choice is deliberately a confident red (not meal's amber-yellow, not workout's terracotta-brown) so the three "warm" food/effort types stay individually identifiable at small dot sizes.

**Database** — [supabase/migrations/20260428000001_add_recipe_note_type.sql](supabase/migrations/20260428000001_add_recipe_note_type.sql): single `INSERT` row with `structured_data_schema` populated for four optional fields:
- `title`       — recipe name (string)
- `food_type`   — broad category, free-form so users aren't enum-constrained ("Korean", "Italian", "Dessert")
- `tags`        — `string[]`, free-form ("spicy", "weeknight", "soup")
- `is_favorite` — toggle for starring recipes worth re-making

Schema is reserved-but-not-yet-rendered. Future structured-data renderer (captured in Phase F+ TODO) will surface these as scaffolding above the free-form body. The body remains the primary surface — recipe notes are about screenshot + thoughts; the fields are there for searchability, not as a form to fill out.

**Run via `supabase db push` or paste into the SQL editor** before saving a recipe-typed note — until the row exists, `NotesRepository.insert` throws `unknownNoteTypeSlug("recipe")`.

Build clean, all 88 tests pass.

### Phase F.1.2.appicon — Brand app icon + per-theme alternates (added this round)

Two pieces in one round:

**1. Brand icon installed** — sage tile (`#5A7B6D`) with the Manrope-ExtraBold opening-quote glyph (`\u{201C}`), 1.03× tile size, ink-centered. Replaces the empty Xcode-default AppIcon set. Renders at 1024×1024 (Asset Catalog auto-derives all device sizes). Solid square — no rounded corners, no transparency — iOS clips its own continuous-corner mask at render time, so providing pre-rounded corners would compound visibly.

**2. Per-theme alternates** — 7 additional icon variants (one per primary theme: Blush, Coral, Mulberry, Taupe, Lavender, Storm, Teal) registered as Asset Catalog alternates via `ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES` (set in both Debug + Release configs in `project.pbxproj`). User picks via Settings → App Icon → 8-cell grid, current selection ringed in sage. Tap calls `UIApplication.setAlternateIconName(_:)` — iOS shows its own "DailyCadence has changed icons" confirmation alert.

**Glyph color rule**: warm taupe (`#EAE6E1`) on darker tiles for brand-consistent off-white. Two exceptions:
- **Blush** uses pure white (`#FFFFFF`) — taupe was muddy against the cool pink.
- **Taupe theme** uses ink (`#2C2620`) — taupe-on-taupe would blend.

**Render pipeline** — pure Core Graphics + Core Text (`/tmp/render-app-icons.swift`). First attempt used SwiftUI `ImageRenderer` but it hangs in a Swift script context (needs an NSApplication runloop the script can't easily provide). CG version registers Manrope.ttf via `CTFontManagerRegisterFontsForURL`, fills tile, draws the glyph ink-centered via `CTLineGetImageBounds`. No optical-center nudge needed in the CG version (SwiftUI Text positions by typographic bounds which leaves quote-mark ink visually high — that's why the in-app `DailyCadenceLogomark` applies a 0.185em downward offset; CG with ink-centered bounds doesn't need it).

**Files**:
- [Models/AppIconChoice.swift](apps/ios/DailyCadence/DailyCadence/Models/AppIconChoice.swift) — enum mapping primary theme id ↔ alternate icon name + display name + tile/glyph colors for the picker preview rendering.
- [Features/Settings/AppIconPickerScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/Settings/AppIconPickerScreen.swift) — picker UI + `ThemeIconPreview` view that re-renders the same shape at any size for the picker thumbnails (no `UIImage(named:)` fetch — alternate-icon assets aren't exposed via that API).
- [Services/AppPreferencesStore.swift](apps/ios/DailyCadence/DailyCadence/Services/AppPreferencesStore.swift) — adds `iconSyncPromptDismissed: Bool` for the future theme-change → icon-suggest prompt's "Don't ask again" persistence.
- [Features/Settings/SettingsScreen.swift](apps/ios/DailyCadence/DailyCadence/Features/Settings/SettingsScreen.swift) — adds `AppIconRow` + `NavigationLink` in the Appearance section.

**Phase 4 not shipped this round** — captured as a TODO below: theme-change → icon-suggest prompt with three buttons (Update | Not now | Don't ask again). The picker is fully usable manually without it.

### Phase F+ feature TODO (designed-for, not-built)

Captured here so a fresh session can pick up the roadmap. Each line corresponds to schema fields that are reserved but unused.

- **Sign in with Apple — critical path to TestFlight.** Apple Developer enrollment cleared 2026-04-28 — this is now the next blocker. Steps:
  1. **Apple Developer web** (developer.apple.com) — Identifiers → click `com.jonsung.DailyCadence` → enable the **Sign in with Apple** capability checkbox → Save. Then create a new **Services ID** (e.g., `com.jonsung.DailyCadence.signin`) → enable Sign in with Apple → configure with the App ID's primary domain. Then Keys → "+" → register a key with **Sign in with Apple** enabled → download the `.p8` file (one-time download, save to 1Password). Note the Key ID + Team ID.
  2. **Supabase dashboard** → Authentication → Providers → **Apple** → enable → paste Services ID, Team ID, Key ID, .p8 contents. Save.
  3. **Xcode** — DailyCadence target → Signing & Capabilities → "+" Capability → **Sign in with Apple**.
  4. **iOS code** — `import AuthenticationServices`. Build a `SignInWithAppleButton` in Settings → Account section. Wire to `ASAuthorizationAppleIDProvider().createRequest()` with `.fullName, .email` scopes. On success, take the `identityToken` from the credential and call `AppSupabase.client.auth.signInWithIdToken(provider: .apple, idToken: tokenString, nonce: nonce)`. **Anon-link path** (critical — preserves existing notes): if `AuthStore.currentUserId` exists from anonymous bootstrap, use the link-identity flow (`auth.linkIdentity(...)`) instead of a fresh sign-in so the anon user's notes carry over to the new Apple-backed identity.
  5. **AuthStore extensions** — add `signInWithApple(...) async throws` method that handles the link-vs-fresh decision internally. Update `lastError` on failure.
  6. **Settings UI** — under "Account" section, replace/augment the "User ID" row with "Sign in with Apple" button (when anon) or "Signed in as: jon@example.com / Sign Out" (when Apple-linked).
  7. **Test paths**: cold launch as anon → sign in with Apple → notes preserved. Sign out → cold launch → app shows sign-in prompt or anon-rebootstrap (decide UX). New device, sign in with Apple → notes appear from server (RLS already scopes by `auth.uid()`).

  Once SIWA is shipped + verified on simulator + a real device, we can finally do the first TestFlight upload (also captured below).

- **Phase F.1.2.appicon Phase 4 — theme-change → icon-suggest prompt (alert with "Don't ask again").** The picker (Settings → App Icon) ships fully functional in the previous round. This is the convenience layer that auto-suggests an icon update when the user picks a new theme color in Settings → Appearance → Theme color. Implementation:
  - Hook into theme changes — easiest spot is `PrimaryColorPickerScreen.swift` where the user actually commits a new primary swatch (NOT in `ThemeStore` itself, which would also fire on programmatic / launch-time selections we don't want to prompt for).
  - On commit, check `AppPreferencesStore.shared.iconSyncPromptDismissed` (already wired) — if true, skip silently.
  - Also skip if the matching icon (`AppIconChoice(rawValue: themeId)`) is already installed (`UIApplication.shared.alternateIconName == matchingChoice.alternateIconName`) — no point asking when there's nothing to change.
  - Otherwise, show a SwiftUI `.alert(...)` with title like "Update app icon to match \(themeName)?" and three actions: **"Update"** (calls `setAlternateIconName(matchingChoice.alternateIconName)`), **"Not now"** (no-op), **"Don't ask again"** (sets `iconSyncPromptDismissed = true`). Use `Alert.Button.default/.cancel/.destructive` for visual hierarchy.
  - Also flip the Settings → App Icon → "Ask when theme color changes" toggle's behavior so it controls the SAME `iconSyncPromptDismissed` flag (already wired in the picker — verify the flow end-to-end).
  - Test path: change theme → prompt fires → tap Update → iOS confirmation alert → icon updates. Change theme again → tap "Don't ask again" → flip to a different theme → no prompt. Toggle the "Ask when theme color changes" switch on → next theme change prompts again.

- **TestFlight first build + Eunji invite.** Gated on Sign in with Apple landing (since the build needs to ship with real auth, not just anon). Steps once SIWA works: Xcode → Product → Destination "Any iOS Device" → Product → Archive → Organizer → Distribute App → App Store Connect → Upload. First upload triggers a ~10-30 min automated review; once it passes, the build appears in App Store Connect → TestFlight. Eunji's already invited (accepted the team invite per 2026-04-28 session); she'll see the build appear in her TestFlight app once Jon adds it to the Internal Testing group. Privacy manifest (`PrivacyInfo.xcprivacy`) is also needed before upload — Apple flags missing manifests since iOS 17.4. ~10-line file declaring `NSPrivacyAccessedAPITypes` for the few "required reason" APIs the project touches (file timestamps, UserDefaults, system boot time, disk space — the usual suspects).

- ~~**Media-note Storage upload pipeline**~~ — Shipped Phase F.1.1a (`e79e152`). Standalone media notes encode via `NotesRepository.encodeMediaBlock` (uploads bytes to the `note-media` Storage bucket, returns `MediaRef`s in the body block DTO). Decode reconstructs `MediaPayload` with refs populated and inline bytes nil; `MediaResolver` lazy-fetches via signed URL. Inline media inside text notes uses the same path. Round-trip verified by inspection 2026-04-28.
- ~~**Image-background Storage upload**~~ — Shipped Phase F.1.2.bgpersist (see entry above). Image backgrounds round-trip through `note-backgrounds` bucket + `backgrounds` table. Library / cross-note reuse aspect (each upload INSERTs a `backgrounds` row that the user's library carries forward + browse / re-pick UI) is still open as a follow-on — needs a Settings → Backgrounds Library screen + a `BackgroundLibraryStore` to surface saved backgrounds for re-use across notes.

- **Image-background polish: blur + scheme-adapt overlay (maybe).** Two additions to the photo-background editor that make it feel more like the iOS Lock Screen wallpaper picker. Captured here as "maybe" — could ship together as one round, or skip if the basic photo bg ends up reading well enough.
    - **Blur slider** — 0 to ~30pt radius with live preview. Apple Lock Screen pattern. Implementation: `Image(...).blur(radius: imgBg.blurRadius)` after `.scaledToFill()`. UI is a `Slider` underneath the existing opacity slider in [BackgroundPickerView](apps/ios/DailyCadence/DailyCadence/Features/NoteEditor/BackgroundPickerView.swift).
    - **"Adapt to mode" toggle** — single toggle that, when ON, layers a scheme-aware overlay so a single photo reads right in both light and dark mode. Dark mode: `Color.black.opacity(0.20)` overlay (subdues the photo against the dark surface). Light mode: `Color.white.opacity(0.10)` overlay (softens it). Opinionated defaults; can promote to a slider if finer control matters. Implementation: `.overlay(imgBg.schemeAdapt ? schemeOverlay : Color.clear)` reading `@Environment(\.colorScheme)`.
    - **Model.** `MockNote.ImageBackground` gains `blurRadius: Double` (default 0) and `schemeAdapt: Bool` (default false). Both nil/false = current behavior.
    - **Persistence.** Add two columns to `backgrounds` table — `blur_radius double NOT NULL DEFAULT 0` + `scheme_adapt boolean NOT NULL DEFAULT false`. New SQL migration. Update `BackgroundRow` + `BackgroundRowInsert` + `encodeBackground` + `fetchBackground` to round-trip the new fields. Existing rows get the defaults via `NOT NULL DEFAULT`, no backfill needed.
    - **Out of scope (later if needed):** per-mode independent opacity values (let user set light/dark opacity separately); custom overlay color (let user pick the tint); blur depth-effect (Vision framework — Apple's "subject elevation").
    - **Where the cards apply this**: NoteCard + KeepCard background-rendering paths + the editor canvas. Three sites; pattern is the same modifier chain at each.
- ~~**Swatch-background `background_id` resolution**~~ — Shipped Phase F.1.2.swatchpersist (see entry above). Find-or-INSERT pattern keyed by `(user_id, kind='color', swatch_id)`; per-user rows reuse across notes for the same swatch. The original-schema seeded system rows for "common palette swatches" are NOT used by this implementation — turns out per-user rows are simpler (no system-vs-user lookup logic) and the storage cost is trivial. The seeded rows can be removed in a future cleanup migration if desired.
- **AttributedString per-run styling round-trip** — gated on the Phase E.2 polish (custom `fontId` / `colorId` AttributedStringKeys). Phase F.0.2 paragraphs serialize as plain text (`String(attr.characters)`), losing per-run font + color choices on save. The body JSONB schema accommodates extension via a `runs: [...]` array on each paragraph block — no DB migration needed when E.2 polish lands.
- **MockNote → Note rename + `occurredAt: Date` refactor** — replace `time: String` with `occurredAt: Date?` as the source of truth, with `time` as a computed display getter. Eliminates the locale-symmetric round-trip in `NotesRepository.parseDisplayTime`, makes evergreen notes (NULL occurred_at) representable, and aligns the iOS model name with the persisted entity.
- **Recently Deleted UI** — list soft-deleted notes; per-note Restore / Delete forever; bulk "Empty Recently Deleted." Schedule-driven hard-delete via `pg_cron` after 30 days.
- **Reschedule action menu + indicator** — "Push to..." date picker on uncompleted notes; creates new note with `rescheduled_from_id` set, marks original `cancelled_at = now()`. Indicator: small SF Symbol (`arrow.uturn.forward.circle` candidate) on cancelled rows; tap reveals "Moved to [date]" with link to successor.
- **Evergreen toggle in editor** — date/time picker gains a "Clear" / "No date" option; clearing sets `occurred_at = NULL`. Notes display "No date" in time column. Evergreen notes appear in a separate "Notes" surface (not the dated timeline).
- **Reminders / push notifications** — Apple Push Notification service via APNs (requires the Phase F+ thin Next.js backend; can't fire from iOS app alone). Per-note `notification_offsets int[]` set in editor; account-level defaults via future `user_settings` table.
- **Smart natural-language time parsing** — detect "I ate breakfast at 8 AM" / "Coffee date with wife at 11 AM" / "Finish homework by 8 PM" in the title, auto-set `occurred_at` and reminder offsets per account defaults. App-side feature; doesn't change schema.
- **Sharing UI — per-note share/invite** — invite collaborators by Apple ID / email; recipient sees a pending invite, accepts → role=viewer goes to "Shared with me," role=editor goes to main timeline. "Leave" action flips own row to status='left'.
- **Sharing UI — shared groups** — create group, invite members, members accept/decline/leave. Tagging a note with a group auto-shares to all accepted members. Only group owner can invite.
- **Custom user types** — admin panel (or in-app form) for creating new types: slug, color, icon/emoji, structured_data_schema. INSERT into `note_types` with `created_by_user_id = self`. Visible only to creator.
- **Admin-managed system types** — admin panel for managing system types (rows where `created_by_user_id IS NULL`). Initial system types ship via the migration; admin panel adds/edits without app updates.
- **Custom user backgrounds** — image upload to `note-backgrounds` Storage bucket, INSERT into `backgrounds` with `user_id = self`. Saved at account level, reusable across notes. Editing a library entry propagates to all notes using it.
- **Body-level checkboxes** — new block kind in `body jsonb`: `{kind: 'checkbox', text: '...', checked: false}` alongside `paragraph` and `media`. Toggleable inline. Apple Notes / Notion pattern.
- **Realtime cross-device sync** — Supabase Realtime channels on the `notes` table; iOS app subscribes to `user_id = auth.uid()` filter, applies remote changes to local state. Useful when both phone and iPad are open at once.
- **Structured-data field schemas** — populate the `structured_data_schema` jsonb on system types (workout: exercises with sets/reps/weight; mood: rating slider; sleep: hours-slept + wake count). Pure UPDATE statements, no migration.
- **`user_settings` table** — account-level preferences: default reminder offsets, default note type, theme override, etc. Migration when first preference ships.
- ~~**Edit caption on existing media notes**~~ — Shipped (Phase F.1.2.refresh). See entry above.
- **Per-note-type editing UI (rename + icon picker, in addition to color)** — Settings → Note Types currently lets the user pick a color override per type via [TextColorPickerScreen](apps/ios/DailyCadence/DailyCadence/Features/Settings/NoteTypePickerScreen.swift) (despite the misleading name — it's a color picker for note types, not text color). Expand into a full `NoteTypeEditScreen` with three editable fields per type: (1) display name (text field — currently hardcoded in `NoteType.title`), (2) icon (picker showing the SF Symbol catalog for note-type-appropriate symbols, **plus** an emoji input alternative — Jon explicitly wants emoji as a fallback for users who can't find the right symbol), (3) color (existing palette picker). Storage: `NoteTypeStyleStore` already keyed by `rawValue`, extend it to store a `NoteTypeOverrides` struct (name + iconName + swatchId) instead of just `swatchId`. Schema-side, the `note_types` table already has `display_name`, `icon`, `color_hex`, `structured_data_schema` columns; user overrides could write to per-user rows (`created_by_user_id = self`) instead of mutating the system row, OR live in a new `user_note_type_overrides` table. Rename `TextColorPickerScreen` → `NoteTypeEditScreen` while we're there. SF Symbol catalog for the picker: Apple ships `SFSymbolEffect` listing on macOS but iOS apps typically use a curated subset — start with ~30–50 SF Symbols that read as note categories (heart, dumbbell, fork.knife, moon, figure.walk, pawprint, photo, book, leaf, cup, etc.) plus the emoji fallback.
- ~~**Rename "Primary color" in Settings → Appearance**~~ — Shipped as "Theme color" (Phase F.1.2.refresh).
- ~~**`pets` note type with paw icon**~~ — Shipped (Phase F.1.2.pets). See entry above.
- ~~**`book` note type for reading logs**~~ — Shipped (Phase F.1.2.book). See entry above. The structured-data fields renderer that surfaces `title` / `author` / `progress` / `is_finished` is still a separate Phase F+ task (covers all types with populated schemas, not just book).
- ~~**`recipe` note type with screenshot + tags.**~~ Shipped Phase F.1.2.recipe (see entry above). The future structured-data renderer that surfaces `title` / `food_type` / `tags` / `is_favorite` is still a separate Phase F+ task (covers all types with populated schemas, not just recipe).
- **Real-time cross-note search with multi-level filters.** Cross-cutting feature. Use case (driven by recipes but applies to all notes): search for "Korean" → results, then within those, filter by tag "spicy" → narrows live, no "Search" button press. UX shape: search field at the top of the timeline / library / dedicated search screen; results update on each keystroke; chips below the field show active filters (note type, tag, food type) the user can stack. Schema additions needed: `tags text[]` column on `notes` (or a `note_tags` join table — text[] is simpler and supports GIN index for fast `&&` queries). `notes.search_text` generated column for full-text search across title + body? OR Postgres `to_tsvector` with a GIN index on the fly. Phase 1 can ship with `ILIKE '%query%'` against `title || body` — slower but no schema change beyond tags.
- ~~**FAB menu copy refresh**~~ — Shipped (Phase F.1.2.refresh). Final picks: "Write a thought" / "Add from Photos" / "Snap something".
- **User profile: avatar + first/last name.** Currently auth is anonymous (Phase F.0.1) and there's no profile UI. New `profiles` table (one-row-per-user, `id uuid PK references auth.users(id)`, `first_name text`, `last_name text`, `avatar_ref MediaRef?`). Storage: new `avatars` bucket (public read for the user's own row, RLS like `note-media`). Settings → Profile section with image picker (reuse `CameraPicker` + `PhotosPicker`) + two text fields. Read-through via a `ProfileStore` `@Observable`. Required before Sign in with Apple / Google ship — those provide the name as a one-shot at first sign-in, which we should write into `profiles` then.
- **Image viewer: capture metadata overlay — location portion.** Date/time portion shipped Phase F.1.2.exifdate (see entry above). Remaining: GPS location overlay alongside the date. At first import per session, prompt the user with an opt-in toggle ("Save location with photos? You can change this later in Settings"). Default off. When on, store `latitude`/`longitude` in EXIF passthrough OR in a dedicated `media.location point` column. Reverse-geocode on demand for display. Settings → Privacy (new section) toggle to globally enable/disable location storage. Camera-capture path needs `Info.plist` `NSLocationWhenInUseUsageDescription` since `UIImagePickerController` doesn't carry GPS by default.

- **`sleep` type — bedtime + wake-time UX with "lingering until completed" affordance.** The `sleep` system note type currently logs as a single timestamp like every other note, but a sleep entry is *inherently* a window: the user wants to log "I went to bed at 10pm, woke up at 6am." This is a sleep-specific UX on top of the broader Time-window notes work below — they should land together (or sleep first, since it's the most concrete use case).
    - **Editor UX.** When the type picker is set to `sleep`, swap the single date/time row for a two-row layout: "Bedtime" (defaults to current time-of-day) + "Wake time" (defaults to bedtime + 8 hours OR empty). Both pickers `.compact` style. Mirror this in `MediaNoteEditorScreen` if media is allowed on sleep notes (probably not Phase 1).
    - **The "log right now, don't know wake yet" case.** Common scenario: user logs sleep right when going to bed but doesn't yet know when they'll wake. Wake-time picker gets a third state alongside the timestamp options: **"I'll log it tomorrow"** (actual wake) and **"Planned wake at..."** (intended wake — drives a future reminder). Concrete UI: a small SegmentedPicker at the top of the wake-time row — `Now-ish` / `Planned` / `Skip`. `Skip` leaves wake_at NULL.
    - **Lingering "complete this" card.** When a sleep note has `bedtime IS NOT NULL AND wake_at IS NULL`, surface a soft-inverted card on the *next day's* timeline (above the regular notes for that day) prompting "Last night's sleep — what time did you wake?" Tap → opens the editor with the sleep note pre-loaded, focus on the wake-time field. Dismissible (X) — sets wake_at to a sentinel ("declined to log") so the prompt doesn't reappear; we can still display "—" in the duration field. Card should fade out from the timeline once wake_at is set.
    - **Schema.** Reuses the broader Time-window notes work below — `notes.ended_at timestamptz NULL` + `MockNote.endedAt: Date?`. Sleep adds nothing schema-side. A future enhancement could add a sleep-specific `structured_data_schema` field for "quality" (1-5 stars) or "wakeups" (count) — but that's separate.
    - **Edge case — multi-night persistence.** If the user logs bedtime tonight but doesn't set a wake-time for several days, the lingering card stays on each subsequent day (every "next day" until resolved). After ~3 days unresolved, auto-dismiss the lingering card (it's no longer actionable; the user clearly didn't track this one).
    - **Reminders integration (deferred).** When `Planned wake` is set, a future reminders/push-notification system could fire ~15 min before that time saying "Time to wake up — log it when you're up." Gated on the existing reminders/APNs TODO + Apple Developer enrollment.
    - **Why this is its own TODO** vs. just a sleep-flavored variant of "time-window notes": the sleep flow has a unique three-state wake picker + the lingering-card pattern that doesn't apply to other window notes (working 9-5 doesn't need a "log when you finish" reminder). The window-notes TODO captures the *base* (timeline render, nesting, schema); this one captures *sleep's specific layered UX on top*.

- **Time-window notes (start + end).** Currently `MockNote.occurredAt: Date` is a single timestamp. Use case: "I slept 10pm–6am" / "Worked 9am–5pm" / "Movie 8pm–10:30pm." Schema: add optional `endedAt: Date?` to `MockNote` and `notes.ended_at timestamptz NULL` to the table. Editor picks both start + end via a duration toggle in the date/time picker. **Two open design problems** that need decisions before building:
    - **Timeline render.** The rail is a vertical chronological list with one dot per note. A window note needs to show both endpoints AND the elapsed span. Candidates: (a) two dots on the rail connected by a thicker rail segment, with the card hanging off the start; (b) a vertical capsule / pill bar to the LEFT of the rail spanning start→end with the card to the right; (c) a single dot at start with a small "→ 6:00 AM" trailing label inside the time column. Apple Calendar's day-view shows windows as full-height blocks but doesn't translate well to a rail. Prefer (b) — visual span communicates duration intuitively without competing with the rail's chronological dots.
    - **Nested notes within a window.** Use case: "Worked 9am–5pm" + "Jimmy Johns 12pm" should clearly show the lunch happened DURING work. Three approaches: (1) **implicit visual association** — render lunch normally on the rail; the work-note's left-side capsule (option b above) extends behind both, visually grouping them. No data-model change. Probably the right Phase 1. (2) **indented child cards** — Apple Notes folder pattern, lunch renders inset under work. Requires parent-child concept on the model (`parent_note_id`?), heavier UX, harder to reorder. (3) **automatic time-overlap detection** — render anything whose `occurredAt` falls inside another note's window with a subtle "tucked in" treatment (smaller card / lighter bg). Pure presentation, no model change. Recommend exploring (1)+(3) as a combo: capsule shows the span, time-overlap detection styles the contained notes lightly to reinforce the visual grouping. Board view is the easy case — just render "10:00 PM – 6:00 AM" as the time label, no nesting needed (Board cards are spatial, not chronological).
    - **Editor UX.** Date/time picker in [NoteEditorScreen](apps/ios/DailyCadence/DailyCadence/Features/NoteEditor/NoteEditorScreen.swift) gains a "Set duration" toggle. Off → single time (current). On → reveals end-time picker, defaults to start + 1 hour. "Sleep" type might want to default duration on; rest default off.

- **Scroll-edge soft-fade (Apple Messages pattern) — needs structural refactor first.** Two attempts in 2026-04-28 round both reverted (Phase F.1.2.scrolledge entry above has the full postmortem). Root cause: the date row + week strip live INSIDE the TimelineScreen ScrollView, so there's nothing meaningful to fade — the chrome IS what scrolls. The proper fix is **pin the chrome outside the scroll**: wrap the date row + week strip in `.safeAreaInset(edge: .top)` at the screen level so they're always-visible at top, then put `.ultraThinMaterial` as the pinned chrome's background so cards softly blur behind it as they scroll up. This is what Apple Calendar / Reminders / Mail do — pinned title bar, content scrolls under it, system handles the fade. After this restructure, iOS 26's `.scrollEdgeEffectStyle(.soft, for: .top)` would also work if we re-introduced a transparent toolbar instead of the safeAreaInset (alternative path, more nav-bar-flavored). DO NOT attempt the manual `LinearGradient` overlay again — it bisects the static chrome at scrollOffset == 0. Files affected: TimelineScreen.swift (extract `dateRow` + `weekStrip` from inside the ScrollView). Test paths: scroll the cards under the pinned chrome, verify the material blur reads correctly; verify the LoadingBar overlay still renders above everything.
- ~~**Today page: minimal week strip indicator**~~ — Shipped (Phase F.1.2.weekstrip). See entry above.
- ~~**Note type picker — scaling beyond ~7 types**~~ — Shipped as combo A+B (Phase F.1.2.refresh). Original brainstorm preserved below for future reference / re-evaluation if A+B doesn't land:
    - **A. Defer the type decision.** Editor opens with no visible picker; default type is `.general` (or last-used). Type chip shown as a discreet button in the toolbar / navbar; tap to change. The user just starts writing. **Tradeoff:** users who want to commit early have one extra tap; users who don't can ignore type entirely until save. **Closest to Apple Notes' folder-implicit model.**
    - **B. Searchable type picker sheet.** Replace the horizontal scroll with a single chip showing the current type. Tap → presents a small `.presentationDetent(.medium)` sheet with a search field at the top and a 2-column grid of all types (icon + name). Type to filter; tap to commit. **Tradeoff:** scales arbitrarily — works at 7 types or 70. Slight friction (sheet) vs. inline chips for the common case. **Notion / Bear pattern.**
    - **C. Inferred type from content.** As the user types title/body, run a lightweight keyword classifier (`"breakfast"` → meal, `"ran 5k"` → workout, `"chapter 3"` → book) and surface a single suggestion chip ("Looks like Workout — switch?"). Default stays `.general` until accepted. **Tradeoff:** delightful when right, annoying when wrong; needs some tuning. Pairs well with the captured "smart natural-language time parsing" TODO (same parsing pass).
    - **D. Frequency-sorted chips with overflow.** Show 4–5 chips ordered by user's recent usage; trailing "More…" chip opens the full list as a sheet (option B). **Tradeoff:** fits the existing UI shape but adapts; persists per-user usage counts (UserDefaults sufficient). **Spotlight / launchpad pattern.**
    - **E. Two-tier — Primary vs. Other.** Five "primary" types (user-configurable in Settings → Note Types) are always-visible chips; the rest live behind a single "Other…" chip. **Tradeoff:** requires a new settings preference + UI for choosing primaries; harder to discover lesser-used types.
    
    **Recommendation:** combine **A + B**. Editor opens to writing immediately (no picker), with the current type as a small chip near the title field. Tap the chip → searchable sheet (option B) for explicit selection. Adds C as a Phase 2 enhancement once we have the parsing pass for time. This honors Jon's "free flow no disruption" goal without sacrificing power-user workflow. Same picker UI handles N types so it scales to custom user types automatically.

### Phase F.2 — Real auth: Sign in with Apple + Google + onboarding (added this round)

The dev-mode anonymous bootstrap is gone. New users land on a real onboarding screen and pick a provider; existing anonymous Keychain sessions still load gracefully so they're not forced into a re-sign on next launch.

**Apple — native ID-token flow.** `Services/AppleSignInNonce.swift` generates a random raw nonce + its SHA-256 hex; the hashed half goes to Apple in the authorization request, the raw half to Supabase via `auth.signInWithIdToken(provider: .apple, idToken:, nonce:)`. Supabase re-hashes raw and matches against the ID token's `nonce` claim — replay-protection. We use the **native** flow, not OAuth, so no Services ID / client secret JWT was needed on Apple's side; just the App ID with the "Sign in with Apple" capability enabled and the bundle ID added to Supabase's "Authorized Client IDs" field. Xcode capability + entitlements file (`DailyCadence.entitlements`) added.

**Google — Supabase OAuth + ASWebAuthenticationSession.** Supabase Swift SDK's `auth.signInWithOAuth(provider:redirectTo:)` overload wraps `ASWebAuthenticationSession` end-to-end (presents the system browser sheet, listens for the redirect, exchanges the code, returns the session). Required infra: Google Cloud Console **Web application** OAuth client (NOT iOS — Supabase does the server-side exchange), redirect URI = `https://zmlxnujheofgtrkrogdq.supabase.co/auth/v1/callback`. App registers the `com.jonsung.dailycadence://login-callback` custom scheme via `Info.plist` `CFBundleURLTypes`; Supabase's Auth → URL Configuration allowlist contains the same. No GoogleSignIn SDK — kept the dependency footprint flat.

**Account-collision strategy (Pattern A + B + C, agreed upfront).**
- **A. Auto-link by verified email** — Supabase's default behavior; when both providers report the same verified email, identities merge to one user. Free win for the common case.
- **B. Manual `linkIdentity()` API** — toggled ON in Supabase Auth → Sign In / Up → "Allow manual linking" so a Settings → Account "Connect Apple/Google" button can attach a second provider to an existing session. UI for this is *not* shipped this round — the toggle is on so the API is available when we wire the UI.
- **C. Last-used-provider memory at the sign-in screen** — *not* shipped this round either. We only have two providers and the OnboardingScreen surfaces both equally (Apple on top per HIG); the last-used nudge becomes useful when there are 3+ providers or when account-collision starts biting in practice.

**`OnboardingScreen` — gated sign-in surface.** `Features/Onboarding/OnboardingScreen.swift`. Logo + tagline + two buttons (Apple, Google). Errors render inline below the buttons; user-cancelled is silent (`ASAuthorizationError.canceled` for Apple, `ASWebAuthenticationSessionError.canceledLogin` for Google). `RootView` shows it whenever `AuthStore.isReady && currentUserId == nil`; otherwise routes to the timeline.

**Brand-correct, scheme-aware buttons.** Apple: `SignInWithAppleButton` with `.black` style on light, `.white` on dark (system component, never wrong). Google: bundled the official 4-color G logo as a vector imageset (`Assets.xcassets/GoogleG.imageset/google-g.svg`) so it stays sharp at any scale; light = white background + dark text + subtle border, dark = `#1F1F1F` background + white text + faint border, both per Google's brand guidelines. Same height + corner radius as Apple's button so they read as a pair.

**Bootstrap rewrite — no more auto-anon.** `AuthStore.bootstrap()` no longer calls `signInAnonymously()` when there's no Keychain session — it just sets `isReady = true` with `currentUserId = nil` so RootView swaps in the OnboardingScreen. Existing dev-era anon sessions still load as `.initialSession` and continue to work; they don't get force-signed-out. `signedOut` / `userDeleted` events also stop the anon retry loop.

**Settings → Account redesign.** Replaced the dev-mode "User ID" UUID display with a real "Signed in as" row showing `email` (or `Guest · {short-id}` for any leftover anon sessions). Added a destructive-style **Sign Out** button that calls `AuthStore.signOut()` → emits `.signedOut` → RootView swaps to OnboardingScreen.

**One-time data migration: anon → Apple account (jonsung89@gmail.com).** Migrated 19 active + 5 deleted notes + 22 storage objects (102 MB across `note-media` HEIC/MP4/MOV) + 4 image backgrounds (813 kB in `note-backgrounds`) from anon `c621f238-…` to the new Apple `d9d71ad5-…`. Three layers had to flip together: (1) `notes.user_id` + `notes.body` JSONB media-ref paths, (2) the `backgrounds` table's `user_id` + `image_url` column, (3) Storage objects in both buckets. **Key gotcha learned:** `UPDATE storage.objects SET name = ...` only renames the metadata row; the underlying S3 blob is keyed by the original path, so signed URLs return 404 after a metadata-only rename. The correct primitive is Supabase's `storage.from(bucket).move()` API (or `POST /storage/v1/object/move` REST endpoint) which renames metadata AND copies+deletes the S3 object atomically. Final fix: SQL to reverse desynced metadata back to source prefix, then a Node script using built-in `fetch` against the storage REST API with the service-role key to call `move()` for each file. Memory entry [`feedback_migration_read_constants_from_source.md`](memory/feedback_migration_read_constants_from_source.md) captures this so future migration work doesn't repeat the mistake.

**Default View picker — Menu-based row.** `Settings → Today → Default view` was a `Picker` whose collapsed display rendered the icon + title with system-tight spacing — visibly different from the dropdown menu's standard Label spacing. Tried iOS 17+ `currentValueLabel:` parameter first; built clean but iOS ignored it inside an inset-grouped list. Final fix: rebuilt as `Menu { Picker } label: { ... }`, where the menu's button label is a hand-laid `HStack(spacing: 8)` with the icon + title + manual chevron. Menu items inside still use `Label`. Two states are now visually consistent.

### Tests (79/79 passing — +3 this round)
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
- `NoteTypeStyleStoreTests` (6) — empty default state, persistence across instances, nil/empty-string clears override, stale id resolves to nil at read time, reset-all clears every override
- **`BoardLayoutModeTests` (3)** — declared case order (.stacked / .grouped / .free), every case has non-empty title + SF Symbol
- **`AppleSignInNonceTests` (4)** — `hashed` equals SHA-256 of `raw`, raw is requested length, consecutive nonces differ, hashed is 64 hex chars

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

**TestFlight 1.0 (1) live (2026-04-29).** Jon + wife installed via internal-tester group. Now collecting real-use feedback; iterations land as 1.0 (2), (3), etc. Bumped build numbers each upload.

**Phase F.2 (real auth) — bundle complete; Pattern B account-linking UI in Settings deferred.** Sign in with Apple + Google + onboarding sign-in + Sign Out shipped + verified at runtime. Supabase manual-linking toggle ON in dashboard so the API is available; just no Settings UI calling `auth.linkIdentity(...)` yet. Lands when Apple-relay edge cases bite (rare for our 2-tester scenario).

**Phase F.3 (account deletion) — bundle complete.** Edge Function deployed at `https://zmlxnujheofgtrkrogdq.supabase.co/functions/v1/delete-account`; Verify-JWT-with-legacy-secret toggle OFF (we do JWT verification inside the function via `auth.getUser()`, gateway-level legacy check rejected real user JWTs). DeleteAccountConfirmationScreen pushed from Settings → Danger Zone, requires typing the user's email to enable the destructive button.

**Phase F.4 (onboarding flow + profile editor + journal illustrations) — bundle complete.** Six-page flow (Welcome / Profile / Theme & Icon / Note Types / Reminders / Done), gated by `AppPreferencesStore.hasCompletedOnboarding || !auth.hasName`. Profile photo upload via PhotosPicker → circular crop (`PhotoCropView(circular: true)`) → Storage; `ProfileImageCache` two-layer cache (NSCache UIImage + signed URL within 50min TTL) so Settings opens with the avatar instant after first load. Journal-pen illustration vocabulary captured in memory.

**Phase F.1.1b' (media UX polish) — bundle complete.** Video trim sheet (over-60s rejection → trim flow), Apple Photos zoom + drag-dismiss for both image and video, camera capture from FAB, and inline video playback in cards (Phase F.1.2.inlinevideo) all shipped. Timeline media-width design call still pending — design decision more than build work.

**Phase F (Supabase persistence) — text/stat/list/quote + media + image-background round-trips live; run-styling still deferred.** `AppSupabase.client` + `AuthStore` + `NotesRepository` + the wired `TimelineStore` are all in place. After Phase F.2 the app no longer auto-signs in anonymously; users land on `OnboardingScreen` and pick a provider. Open Phase F+ persistence work in the Phase F+ TODO section: swatch-background-id resolution, AttributedString per-run styling round-trip (gated on Phase E.2 polish).

Other open follow-ups (unchanged from prior rounds): per-block focused TextEditors (mid-paragraph image insertion — currently the model supports it but UI ships intro/attachments/outro three-zone layout), drag-to-reorder blocks, inline text formatting (bold/italic/underline/strikethrough), auto-bullet + checkboxes in text notes, auto-scroll the cards grid when dragging near a viewport edge.

---

## 🧭 Next (Phase 1 roadmap, rough order)

_Audited 2026-04-29. TestFlight internal shipped 🎉. Next blockers are App Store submission items (privacy policy, App Privacy questionnaire, support URL) + Phase F+ schema-ready features the user can request at any time._

**Critical path → App Store / external TestFlight:**

1. **Privacy Policy** — required for App Store review, external TestFlight, AND Google OAuth verification. Hand-write a 1-page version specific to DailyCadence (data we collect: email from Apple/Google, note content, optional photos/videos in Supabase Storage; no tracking, no third-party SDKs except Supabase). Host on Vercel / GitHub Pages / similar. ~30 min including hosting.
2. **Support URL** — single page with a contact email. Same hosting as privacy policy.
3. **App Privacy questionnaire** in App Store Connect — ~15 min. Categories: Identifiers (email, linked to user, app functionality), User Content (photos/videos + other content, linked, app functionality). No tracking.
4. **iPad icon variants OR drop iPad target** — TestFlight upload showed warning "missing 152×152 alternates for iPad". Options: (a) generate iPad sizes via the icon-rendering script and add to Info.plist `CFBundleAlternateIcons`, OR (b) change `TARGETED_DEVICE_FAMILY` to iPhone-only (`1` not `1,2`) since the Phase 1 UX is iPhone-shaped anyway. Recommended: (b).
5. **Pattern B account-linking UI** — Settings → Account "Connect Apple/Google" button calling `auth.linkIdentity(provider:)`. Toggle's already enabled in Supabase. Not strictly required for App Store but improves the Apple-relay edge case.
6. **App Store submission** — first review takes 24-72 hours.

**Real-use TestFlight feedback (track here as it lands):**

- _(none yet — Jon + wife just installed)_

**Phase F+ feature TODO (schema-ready, UI not built — full list in `memory/project_phase_f.md`):**

- **Image-background Storage upload pipeline** — currently inline `Data?`; needs `MediaRef`-style backfill mirroring F.1.1a, plus the `backgrounds` library entry.
- **Swatch `background_id` linking** — color backgrounds aren't persisted yet; resolve through `backgrounds` table FK so the lib entry is reusable across notes.
- **AttributedString per-run styling round-trip** — body jsonb encode/decode for inline runs; gated on Phase E.2 polish below.
- **Recently Deleted UI** — list/restore/empty for `deleted_at IS NOT NULL`; `pg_cron` hard-delete after 30 days.
- **Reschedule action menu + indicator** — push-to-date using `cancelled_at` + `rescheduled_from_id`.
- **Evergreen toggle in editor** — clear time → `occurred_at = NULL`; separate "Notes" surface for evergreen rows.
- **Per-day note-count dots** in the date picker.
- **Custom user types / custom user backgrounds** — INSERT into `note_types` / `backgrounds` with `created_by_user_id = self`.
- **Body-level checkboxes** — new block kind `{kind: 'checkbox', text, checked}`.
- **Note detail page** — full-screen drill-in surface (full reschedule audit, full collaborator list, edit-history slot).
- **`user_settings` table** — account-level prefs (default reminder offsets, default note type, tier).
- **Realtime cross-device sync** — Supabase Realtime channel filtered by `user_id`.
- **Sharing UI** (per-note + shared-groups) — schema in place, no UI.
- **Push notifications scheduling** — onboarding pre-permission shipped; scheduling needs an Edge Function or Next.js for APNs (no client-side scheduling for "haven't logged in N days" prompts).
- **Profile photo cleanup** — when user replaces their photo, the old Storage object orphans (current cache invalidates the path but the blob lingers). Add a pg_cron sweep or a delete-on-upload step in `ProfilePhotoPickerState.commitCrop`.

**Customization polish (optional, queue-as-needed):**

- **Phase B.2 polish** — extend per-type color overrides to `NoteType.softColor` so KeepCard fill tints + TypeChip unselected icon circles also pick up the user's chosen color.
- **Phase E.2 polish** — custom `AttributedStringKey` (`fontId` / `colorId`) for per-run app metadata round-trip + cursor-aware toolbar chip highlight.
- **Phase F — Remote config pipeline** — host `palettes.json` / `primary-palettes.json` / `fonts.json` on Supabase Storage; client fetch + cache + bundle fallback.
- **App Icon Phase 4** — auto-prompt on theme change with "Don't ask again." Dismissal flag + Settings re-enable toggle already shipped; missing piece is the observer that fires the prompt when `ThemeStore.primary` changes.

**Editor follow-ups (still in flight):**

- Per-block focused TextEditors for mid-paragraph image insertion
- Drag-to-reorder blocks within a note body
- Inline text formatting (bold/italic/underline/strikethrough) in note body
- Auto-bullet + checkboxes in text notes
- Auto-scroll the cards grid when dragging near a viewport edge

**Beyond MVP (Phase 1.x / Phase 2):**

- Exercise tracking (`exercises`, `workout_logs` tables) + Swift Charts progression view
- Calendar view (wireframe Screen 6) — replace `CalendarScreen` placeholder
- Dashboard widgets (wireframe Screen 7) — replace `DashboardScreen` placeholder

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
