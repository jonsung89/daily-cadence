# DailyCadence — Progress

**Last updated:** 2026-04-25 (Phase E.5.4 — segmented toggle leads with the user's chosen default)
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

Nothing active — Phase E.5.3 (scroll-aware FAB) landed. Open follow-ups: pinch-to-zoom in the crop tool, inline text formatting (bold/italic/underline/strikethrough), auto-bullet + checkboxes in text notes, inline attachments in text notes.

---

## 🧭 Next (Phase 1 roadmap, rough order)

**Customization phases** (from the earlier design discussion):

- **Phase B.2 polish (optional)** — extend overrides to `NoteType.softColor` so KeepCard fill tints + TypeChip icon circles match the user's chosen color, not just dots/borders/icons. ~½ round if/when the visual mismatch becomes annoying.
- **Phase D.2.2 — Interactive crop UX for image backgrounds.** Pan/zoom inside a fixed-aspect frame; store offset+scale on `ImageBackground`; cards apply the same transform on render. Plus image downscaling on import (1024px max) so memory doesn't balloon when many notes are persisted. *1–2 rounds.*
- **Phase E.2 polish (optional)** — custom `AttributedStringKey` (`fontId` / `colorId`) so the message's per-run app metadata round-trips through the document and the toolbar's chip highlight reflects whatever run the cursor is in (not just the most recent tap). Currently the chip highlight is mirrored from `@State` and goes stale when the user moves the cursor.
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
