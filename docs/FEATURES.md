# DailyCadence — Features & Behavior Spec

**This is the cross-platform behavioral source of truth.** The iOS app is the
reference implementation; when porting to Android (Phase 2+) or rebuilding
on web, this doc tells you what each surface does and how it should feel.
PROGRESS.md tracks *when* things shipped; this tracks *what they do*.

**Maintenance rule.** Update this doc in the **same change** as any
feature work that adds, removes, or changes user-visible behavior. If you
edit a screen or component, scan the section here and bring it in line.
Catching a doc/code drift later is much harder than keeping them in step.

> Convention: each section names the iOS file(s) that own the behavior.
> Numeric values (sizes, timings) are the iOS reference; ports should
> match unless platform conventions argue otherwise (e.g., Material
> elevation tokens vs. iOS shadows). Capture deviations explicitly.

---

## Table of contents

- [Global concerns](#global-concerns)
- [Navigation shell](#navigation-shell)
- [Today screen](#today-screen)
- [Note editor (text)](#note-editor-text)
- [Note editor (media)](#note-editor-media)
- [Photo crop tool](#photo-crop-tool)
- [Media viewer](#media-viewer)
- [Settings](#settings)
- [Design system primitives](#design-system-primitives)
- [Data model](#data-model)
- [Persistence stores](#persistence-stores)
- [Out of scope (Phase 1)](#out-of-scope-phase-1)

---

## Global concerns

### Theming
- Single user-pickable **primary color** (sage default + 7 alternates: blush, coral, mulberry, taupe, lavender, storm, teal). Drives FAB, active-tab indicator, accent buttons. Persisted to local prefs.
- All design-system color tokens are **dark-mode aware** via runtime trait checks. Light + dark palettes match the design system's `colors_and_type.css`.
- Per-note background customization: a swatch palette (Neutral / Pastel / Bold / Bright × 6 each) or a photo with adjustable opacity.
- Per-note-type **semantic color overrides** — user can repaint Workout / Meal / Sleep / Mood / Activity / General with any palette swatch from Settings → Note Types.

### Typography
- Sans display: **Inter** variable (bundled).
- Serif display: **Playfair Display** variable (bundled).
- Logomark: **Manrope ExtraBold 800** (bundled).
- User-pickable per-field fonts (title styling) from a JSON-backed registry: Inter, Playfair, New York, SF Rounded, Baskerville, American Typewriter, Noteworthy.
- Message body uses iOS 26 `AttributedString` per-character runs (font + foregroundColor + size).

### Spacing / radius / shadow
- 8pt grid (`s1`–`s9`).
- Card radius: 10pt (KeepCard / Board), 12pt (NoteCard / Timeline).
- Shadow tokens: 4 levels via `dsShadow(_:)`. Tint switches by color scheme (warm ink in light, pure black in dark).

### Voice / copy
- Sentence case in UI labels.
- Brand name is **DailyCadence** (one word) everywhere user-facing.
- Empty states are calm — no marketing exclamation points.

---

## Navigation shell

**Owns:** `Navigation/RootView.swift`, `Navigation/RootTab.swift`, `DesignSystem/Components/TabBar.swift`

- Five-tab bottom bar: **Today**, **Calendar**, **Progress**, **Library**, **Settings**.
- Custom tab bar (not iOS's `TabView`) with translucent cream backdrop, active sage-tinted dot indicator. 88pt tall.
- The first tab's label + icon **mirror the user's chosen default Today view** — if the user picked Board, the first tab reads **Board** with `square.grid.2x2`; otherwise **Timeline** with `list.bullet`. Updates live when the preference changes.
- Each feature screen owns its own `NavigationStack` so per-tab navigation history is independent (iOS standard).
- Root applies `.tint(Color.DS.sage)` to propagate the user's primary color to all SwiftUI controls.

---

## Today screen

**Owns:** `Features/Timeline/TimelineScreen.swift`

The day's notes, viewable as a Timeline rail or a Board grid.

### Header

- Day-of-week label: 11pt sans-bold uppercase, tracked, `fg2` color.
- Date title: 28pt serif-bold, `-0.02em` tracking. Format: full month + day.
- Top-right gear icon: settings shortcut (currently no-op; placeholder).

### View mode toggle

- Pill-style segmented control with **Timeline** + **Board** options.
- Order: the user's **default view leads** (default = Timeline → "Timeline | Board"; default = Board → "Board | Timeline"). Live-updates when the default changes in Settings.
- Active segment: filled `bg2`, warm-ink shadow. Inactive: `taupe` track.
- Initial value: `AppPreferencesStore.shared.defaultTodayView` (default `.timeline`).

### Timeline view

- Vertical rail of `NoteCard`s connected by a sage-dotted line.
- Each row: time column on left + dot/rail + card on right.
- `lineStyle` per row: `belowDotOnly` for the first row, `aboveDotOnly` for the last, `full` for middle, `dotOnly` if there's only one note.
- Cards sit in single-column at full row width.
- Empty state: sun-horizon SF Symbol + "Nothing yet" + "Tap + to add the first note of your day."

### Board view

Three sub-layouts in a segmented control below the main toggle. **Cards is the default and sits first**:

#### Cards (default)

- 2-column masonry via custom `MasonryLayout` (shortest-column-first packing).
- 12pt gap between cards (column gap = row gap), 12pt outer horizontal padding.
- Each card uses its **intrinsic** height — short cards don't inflate to fill column space.
- Card max height capped at 480pt.
- **Drag-to-reorder:** long-press any card → drag anywhere → drop.
  - Live reflow during drag — surrounding cards shift in real time as you pass over them (`DropDelegate.dropEntered` + cached drag id in `DragSessionStore`).
  - Drag-lift preview is rounded to match the card's 10pt corner radius (via `.contentShape(.dragPreview, _:)`).
  - Drop operation is **`.move`** (no green "+" copy badge).
- **Reset order:** when the user has any custom ordering, a small `↺ Reset order` pill appears at the top-right of the Board area. Tap → animated revert to chronological order.
- New notes added after a manual reorder always land at the **end** of the custom order (never injected into the middle of a hand-curated layout).

#### Stack

- Per-`NoteType` overlapping-card stacks in a 2-col masonry.
- Default top card is the newest of that type; older cards peek above (each layer 8pt up, 0.04 smaller, 0.16 more faded).
- `+N` badge on the bottom-right of the stack when the group has more than 3 notes.
- Tap a stack → unfurls vertically inside its column with `matchedGeometryEffect(id:in:properties: .position)` for smooth in-place expansion. Other column unaffected.
- Only one stack open at a time; switching collapses the previous.
- Single-card "stacks" are non-interactive (the card is the whole content).
- Expanded view has a "Collapse ↑" pill anchored bottom-right below the newest card.

#### Group

- `LazyVGrid` sections, one per `NoteType`, each with type-colored dot + uppercase header + count.
- Empty types are filtered (no hollow headers).
- Within each section, cards in a 2-col grid (no masonry).

### FAB (floating action button)

**Owns:** `DesignSystem/Components/FAB.swift` + the menu wiring inside `TimelineScreen`

- 56pt sage circle, white plus icon (24pt semibold), level-2 shadow.
- Anchored bottom-trailing of the screen, 16pt above the tab bar, 20pt from the right edge.
- Tap opens a SwiftUI `Menu` (popover anchored to the FAB):
  - **Text Note** → opens `NoteEditorScreen`.
  - **Photo or Video** → opens `PhotosPicker` (filter `.any(of: [.images, .videos])`); on selection, presents `MediaNoteEditorScreen` with the picked item.
- **Persistent — does not hide on scroll.** Bottom of the ScrollView reserves a 120pt buffer via `.contentMargins(.bottom, 120, for: .scrollContent)` so the last card never lands underneath the FAB. (Apple Mail / Reminders / Google Keep iOS pattern; we explicitly chose this over Material-style hide-on-scroll.)

---

## Note editor (text)

**Owns:** `Features/NoteEditor/NoteEditorScreen.swift`, `Features/NoteEditor/StyleToolbar.swift`, `Features/NoteEditor/BackgroundPickerView.swift`, `Services/NoteDraftStore.swift`

Sheet presented from the FAB menu's **Text Note** option.

### Layout

- Header: nav-bar-inline title.
  - "New note" when the draft is empty.
  - "Resume draft" when a draft exists from a prior accidentally-dismissed session.
- Cancel / Save in nav bar.
- Whole content is wrapped in a `ScrollView(.vertical)` with `.scrollDismissesKeyboard(.interactively)` so the canvas can be panned even when the keyboard is up.

### Type picker (top of editor)

- Default state on a fresh open: **expanded** showing all 6 `NoteType` chips. On a resumed-draft open: **collapsed** to the chosen chip.
- Tapping a chip selects it and collapses the row to just that chip.
- Tapping the collapsed chip re-expands the full row.
- Tapping any chip in expanded mode (including the currently-selected one) collapses.
- Default selected type: `.general` (neutral, warm-gray pigment, generic note icon — added so quick notes don't get implicitly tagged).

### Title field

- Single `TextField` with `axis: .vertical`, `lineLimit(1...)`. Wraps to as many lines as needed.
- Default font: Inter 22pt semibold, ink color.
- Live-styled with the user's chosen `titleStyle` (font + color overrides).
- Autofocused when the editor opens (unless restoring a draft with content).

### Message field

- `TextEditor(text: $attributedString, selection: $selection)` (iOS 26+) — rich-text editing.
- Per-character runs carry font, foregroundColor, and size attributes.
- `.scrollDisabled(true)` so it self-sizes; the parent ScrollView is the single source of vertical scroll.
- Placeholder ("What's on your mind?") overlay-rendered behind the editor; hides as soon as the message is non-empty.

### Style toolbar (compact icon bar above keyboard)

Pinned via `.safeAreaInset(edge: .bottom)`. Always visible.

- 56pt tall icon bar with four buttons; each shows a **live preview** of its current value:
  - **Aa** (Font) — rendered in the active font face. Tap → expands the Font panel (horizontal scrolling chips per `FontRepository` font, each chip rendered in its own face). Tap a chip = apply.
  - **●** (Color) — filled with the active swatch (slash-glyph for default). Tap → expands the Color panel (horizontal scrolling dots, all 24 swatches across the 4 palettes, "Default" first).
  - **↕** (Size) — two stacked `A` glyphs. Tap → expands a one-line hint and reveals the vertical size slider on the canvas right edge.
  - **🖼** (Background) — shows the current background swatch / photo thumb / tag-color dot. Tap → opens `BackgroundPickerView` sheet (no inline panel — too much UI for the bar).
- Tapping an icon toggles its panel; tapping a different icon swaps; one panel open at a time.
- Active button: filled `ink` capsule with `bg2` text. Inactive: `bg1` with thin border.
- Expanded panel header reads "FONT · TITLE" / "COLOR · MESSAGE" etc., based on focused field.
- Style operations target the **focused field**:
  - Title focused → mutate per-field `titleStyle` (uniform across the title).
  - Message focused → call `attributedString.transformAttributes(in: &selection)`. With a non-empty selection, attrs apply to that range. With a collapsed cursor, attrs become typing attributes — next characters typed inherit them.
- Vertical size slider:
  - Compact (30pt × 170pt) Instagram-Story-style on the right edge of the message canvas.
  - Visible only when the toolbar's Size panel is active.
  - 12...48pt range. Default 16pt. Pan-only (no pinch).

### Background picker

Sheet pushed from the toolbar's `🖼` icon.

- Three sections: **None** (slash-swatch), **Photo** (PhotosPicker + opacity slider when set + Replace/Remove), **Color** (palette tabs + adaptive swatch grid).
- Photo and Color are mutually exclusive.
- Opacity slider: 0.1 to 1.0, sage-tinted.

### Background row in editor (deprecated path)

The dedicated "Background" row was removed when the toolbar got a `🖼` icon (Phase E.2.2). The icon is the only entry point now.

### Live preview

- The editor's canvas tints with the user's chosen background at the same 0.333 opacity used by KeepCard (or the photo at chosen opacity). Tag-default tinting reflects the selected `NoteType.color`.

### Draft recovery

- All editor state lives on `NoteDraftStore.shared` (not local `@State`).
- **Save** → builds a `MockNote`, hands it to `TimelineStore`, calls `draft.clear()`.
- **Cancel** → if draft is non-empty, shows confirmation dialog ("Discard draft?" / "Keep Editing" / "Discard Draft"); if empty, dismisses immediately.
- **Drag-to-dismiss** (sheet swipe) → does NOT clear the draft. Re-opening the FAB shows the draft with "Resume draft" title.
- Three-path discard model:

  | Path | Clears? | Confirms? |
  | --- | --- | --- |
  | Save | yes | no — explicit commit |
  | Cancel | yes | yes (if non-empty) |
  | Drag-to-dismiss | no | no — recovery path |

- Scope: **in-memory only** (no UserDefaults persistence). Drafts don't survive app relaunch — Phase F follow-up.

---

## Note editor (media)

**Owns:** `Features/NoteEditor/MediaNoteEditorScreen.swift`, `Services/MediaImporter.swift`

Sheet presented from the FAB menu's **Photo or Video** path. Single-purpose — no rich-text apparatus. Always saves with `NoteType.general`.

### Layout

- Nav: Cancel / Save. Title: "New media note".
- Content: media preview at top → Replace / Remove → Caption field.

### Photo flow

- Selected image is loaded via `MediaImporter.makePayload(from:)` → decodes via `UIImage`, computes aspect ratio.
- Preview displays a `PhotoCropView` for cropping (see [Photo crop tool](#photo-crop-tool)).
- Save commits the user's crop into a fresh `MediaPayload`, then attaches the optional caption.

### Video flow

- Selected video is read via `MediaImporter.videoPayload` — writes bytes to a temp file, opens an `AVURLAsset`, loads first track's `naturalSize` + `preferredTransform` for aspect ratio, generates a first-frame poster JPEG via `AVAssetImageGenerator.image(at: .zero)`. Cleans up the temp file.
- Preview is read-only (no trim UX in Phase 1) — poster image with `.ultraThinMaterial` play button overlay.
- Save attaches caption + saves with the original video bytes + generated poster.

### Caption

- Single-line label "Caption" (12pt label) → 1...4 line `TextField` with rounded `bg2` background.
- Whitespace-trimmed at save; empty → `nil`.

### No draft store for media

- Media notes don't use `NoteDraftStore`. The asset itself is the substance — forcing a re-pick on accidental dismiss is less disruptive than re-typing a long text body.

---

## Photo crop tool

**Owns:** `Features/MediaCrop/PhotoCropView.swift`

Photos.app-style. Built into the media editor.

- **Image** is fixed at scale-to-fit inside the canvas. No pinch-to-zoom yet (deferred — see "out of scope").
- **Crop rectangle** floats in canvas coordinates. Initially fills the visible image.
- **Four corner handles** — white L-shapes, 18×18 visual / 36×36 hit target. Drag to resize.
  - **Free** mode: resize freely.
  - Aspect-locked modes (1:1 / 4:3 / 3:4 / 16:9 / 9:16): resize maintains the locked aspect by anchoring on the corner opposite the dragged handle.
- **Center drag** — invisible inset rectangle inside the crop frame, shrunk so it doesn't overlap corner hit zones. Drag to translate the frame.
- **Aspect chips row** — Free / 1:1 / 4:3 / 3:4 / 16:9 / 9:16. Selecting one snaps the rect to that ratio centered inside the visible image.
- **Dimmed exterior** — eo-fill `Canvas` paints `black @ 0.55` over the canvas with a hole punched at the crop rect.
- **Rule-of-thirds guides** — two horizontal + two vertical white lines at 1/3 / 2/3 inside the crop rect at 0.4 opacity.
- **Minimum crop dimension** — 60pt in canvas coords.
- **Commit** maps the canvas-space crop rect back to image pixel coordinates via `imageSize / imageRect.size` scale factor; clamps; calls `CGImage.cropping(to:)`; encodes JPEG at 0.9 quality.
- **Orientation normalization** — `UIImage.normalizedUp()` redraws non-`.up`-oriented inputs (iPhone portrait photos arrive as `.right`) so the cropped output lands in visible coordinates rather than raw rotated pixel space.

---

## Media viewer

**Owns:** `Features/MediaViewer/MediaViewerScreen.swift`

Full-screen viewer presented via `.fullScreenCover` when a media card is tapped.

- Black backdrop. Top-trailing close button (X in `.ultraThinMaterial` 36pt circle).
- **Image** — `ImagePinchZoomView`: iOS 17+ zoomable `ScrollView` with the image inside. Pinch + double-tap zoom built in. Image data decoded off-main via `Task.detached`.
- **Video** — Writes bytes to `temporaryDirectory/dc-video-<UUID>.mov`; wraps an `AVPlayer` in SwiftUI's `VideoPlayer`. Auto-plays on appear. Cleans up the temp file in `onDisappear`.
- **Caption** (when present) — bottom gradient overlay (`.clear → .black @ 0.45`), white sans 15pt, 24pt horizontal padding, multiline-centered.
- Status bar hidden during the viewer.

---

## Settings

**Owns:** `Features/Settings/SettingsScreen.swift`

`List` with `.insetGrouped` style on `bg1` background. Sections:

### Today

- **Default view** — `Picker` (Timeline / Board) bound to `AppPreferencesStore.shared.defaultTodayView`. Footer text: "Picks which view the Today tab opens in by default."
- Selection persists to `UserDefaults`. Affects:
  - The first bottom tab's label + icon.
  - The Today screen's initial `viewMode` on next open.
  - The order of segments in the Timeline | Board toggle (default leads).

### Appearance

- **Primary color** — `NavigationLink` to `PrimaryColorPickerScreen`. Row preview: trio of dots + theme name. Live-updates when changed.
- **Note Types** — `NavigationLink` to `NoteTypePickerScreen`. Row preview: 6 overlapping circles colored by current per-type colors + summary string ("Default" / "1 customized" / "N customized").
  - Detail screen lists all 6 types; tap any to push a `TextColorPickerScreen` to pick from any palette swatch or "Default."
  - "Reset all" action on the parent screen.

### About

- Version (read from `CFBundleShortVersionString`, monospaced).
- Build number (from `CFBundleVersion`, monospaced).
- No "coming soon" placeholders for unimplemented sections — empty is louder than a stub.

---

## Design system primitives

**Path:** `apps/ios/DailyCadence/DailyCadence/DesignSystem/`

### Colors (`Tokens/Colors.swift`)

- All tokens are `dynamicColor(light:dark:)` (UIColor trait-aware).
- Surface: `bg1` (cream / warm near-black), `bg2` (white / dark surface), `border1` / `border2`.
- Text: `ink` (warm dark / warm off-white), `fg2` (warm gray).
- Accents: `sage` / `sageDeep` / `sageSoft` (primary theme — computed through `ThemeStore`).
- 6 note-type pairs: `workout`/`workoutSoft`, `meal`/`mealSoft`, `sleep`/`sleepSoft`, `mood`/`moodSoft`, `activity`/`activitySoft`, plus `general` using `warmGray`/`taupe`.
- Brand neutrals: `cream`, `taupe`, `taupeDeep`, `warmGray`.
- Companion brights: `periwinkle`, `blush`, `honey`.

### Typography

- Tokens in `Tokens/Font+DS.swift` (e.g., `Font.DS.body`, `.h1`–`.h3`, `.serif(size:weight:)`, `.sans(size:weight:)`).
- Variable fonts registered at app init (and lazily on first DS access for SwiftUI Previews).

### Spacing / Radius / Shadow

- `Spacing.swift`: 8pt grid `s1 = 4pt` ... `s9 = 64pt`.
- `Radius.swift`: `sm` (6) / `md` (10) / `lg` (16) / `pill` (999).
- `Shadow.swift`: 4 levels via `.dsShadow(_:)`. Tints are warm ink in light mode, pure black in dark.

### Components

| File | Role |
| --- | --- |
| `FAB.swift` | 56pt sage floating action button. `FABAppearance` is the pure visual (used as the SwiftUI `Menu` label). |
| `KeepCard.swift` | Google Keep-style card on the Board. Two scaffolds: text (head + content) and full-bleed media (no head). Max height 480pt. |
| `KeepGrid.swift` + `MasonryLayout.swift` | 2-column masonry — custom `Layout` (shortest-column-first, 12pt gap). Replaces HStack-of-VStacks for tight column packing. |
| `NoteCard.swift` | Single-column card on the Timeline. Same dual scaffold (text vs full-bleed media). Max height 520pt. Level-1 shadow. |
| `NoteBackgroundStyle.swift` | UI-layer background enum (`.none / .color / .image`) — the cards' input. |
| `Segmented.swift` | Reusable pill segmented control (Timeline/Board, Cards/Stack/Group, etc.). |
| `TabBar.swift` | Custom 5-column bottom navigation. |
| `TypeBadge.swift` | Dot + uppercase type label + optional time. |
| `TypeChip.swift` | Note-type picker chip (icon + label, ink-filled when selected). |
| `TimelineItem.swift` | Time column + sage-dotted rail + trailing card slot for the Timeline view. |

### Brand

- `DailyCadenceLogomark` — sage/paleTaupe tile variants, Manrope-800 opening quote.
- `DailyCadenceWordmark` — Playfair Display 500. `.oneWord` is canonical.
- `DailyCadenceLogo` — combined mark + wordmark.

---

## Data model

**Owns:** `Models/`, `Features/Timeline/MockNotes.swift`

### MockNote

- `id: UUID` (auto), `time: String` ("9:30 AM"), `type: NoteType`, `content: Content`, `background: Background?`, `titleStyle: TextStyle?`.
- `kind: Kind` derived from content — `.text` / `.photo` / `.video`. Drives whether cards render the text scaffold or the full-bleed media scaffold.

### Content variants

- `.text(title: String, message: AttributedString?)` — title is plain `String`; message is rich text (Phase E.2). Phase 1 default.
- `.stat(title: String, value: String, sub: String?)` — e.g. "Slept / 7h 14m / Woke once".
- `.list(title: String, items: [String])` — checkbox-style list (display only in Phase 1; checkbox interaction is Phase 2+).
- `.quote(text: String)` — italicized serif quote card.
- `.media(MediaPayload)` — photo or video (Phase E.3).

### NoteType

- Six cases: `general` (default, neutral), `workout`, `meal`, `sleep`, `mood`, `activity`.
- Each has a title, default pigment + soft color, and a SF Symbol placeholder. Color/icon overrides via `NoteTypeStyleStore` flow into all card visuals.

### MediaPayload

- `kind: .image | .video`, `data: Data`, `posterData: Data?` (videos only), `aspectRatio: CGFloat` (clamped 0.4...2.5 to keep the masonry sane), `caption: String?` (whitespace-trimmed, empty → nil).
- Phase 1 stores bytes inline. Phase F+ moves to Supabase Storage URLs (case shape unchanged).

### TextStyle

- `fontId: String?` + `colorId: String?` — both optional. Empty `TextStyle()` collapses to `nil` at note-init time.
- Resolves through `FontRepository` and `PaletteRepository`. Stale ids gracefully resolve to `nil` (card falls back to default styling).

### Background

- `.color(swatchId: String)` or `.image(ImageBackground)` (`imageData` + clamped opacity).
- Resolved to a `NoteBackgroundStyle` (UI-layer enum) for card rendering.

---

## Persistence stores

All `@Observable` singletons. None hit Supabase yet — Phase F follow-up.

| Store | Backed by | Scope | Purpose |
| --- | --- | --- | --- |
| `TimelineStore` | in-memory (seeded with `MockNotes.today`) | session | Source of truth for the day's notes. `.add(_:)` is the editor-save path. |
| `ThemeStore` | UserDefaults | persistent | Selected primary color theme. |
| `NoteTypeStyleStore` | UserDefaults | persistent | Per-`NoteType` color overrides (Settings → Note Types). |
| `AppPreferencesStore` | UserDefaults | persistent | Behavioral defaults (e.g., `defaultTodayView`). |
| `NoteDraftStore` | in-memory | session | Recovers in-progress text-note edits across accidental sheet dismiss. |
| `CardsViewOrderStore` | in-memory | session | Custom note ordering for the Cards Board layout. |
| `DragSessionStore` | in-memory | per-drag | Caches the dragged note's id during a Cards-layout reorder so `dropEntered` can react synchronously. |

Repository services (read-only) for JSON-backed catalogs:

- `FontRepository` (`fonts.json`): 7 user-pickable fonts.
- `PaletteRepository` (`palettes.json`): 4 palettes × 6 swatches (Neutral / Pastel / Bold / Bright).
- `PrimaryPaletteRepository` (`primary-palettes.json`): 8 primary themes.

---

## Out of scope (Phase 1)

These are deferred. When porting, don't rebuild them on Android either — match the Phase-1 surface so we keep platforms in step.

- Camera capture (UIImagePickerController + `NSCameraUsageDescription`).
- Video trim / re-encode at import.
- Pinch-to-zoom on the photo crop tool (currently corner-resize + center-drag only).
- Inline text formatting toggles (bold / italic / underline / strikethrough).
- Auto-bullet on `-` and Apple-Notes-style checkboxes inside text notes.
- Inline image attachments inside text notes (recommend Apple-Notes-style flow when this lands).
- Real Calendar / Progress / Library tabs (placeholders only in Phase 1).
- Supabase auth + persistence wiring.
- Drag-to-reorder on Stack and Group Board layouts (only Cards layout is reorderable in Phase 1).
- Backdating a note (the editor stamps `Date.now` only).

---

*This file is maintained by hand. If something here disagrees with the iOS code, the iOS code wins — file an issue and update this doc.*
