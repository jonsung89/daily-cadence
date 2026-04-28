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

Two-row layout introduced in Phase F.0.3:

**Top row** — small caption + right-side controls.
- Day-of-week label: 11pt sans-bold uppercase, tracked, `fg2` color. Resolves to `TODAY` / `YESTERDAY` / `TOMORROW` for those three days; otherwise the full weekday name (`MONDAY`, etc.).
- Board sub-mode menu icon (Board view only) + gear icon (Settings shortcut) sit on the trailing edge.

**Bottom row** — date navigator.
- Left chevron (`chevron.left`) = previous day. Right chevron (`chevron.right`) = next day. 32×44pt hit targets, `fg2` ink.
- Date title between them: 28pt serif-bold, `-0.02em` tracking. Format: full month + day. Reflects `TimelineStore.shared.selectedDate`. Tappable — opens a **graphical `DatePicker` sheet** at `.medium` detent for jumping to any date (past or future; future-dated notes are reminders/todos per the schema design).

**"Today" pill**: appears below the navigator when `selectedDate` is not today's local-calendar day. Sage-tinted capsule with `arrow.uturn.backward` glyph + "Today" label. Tap returns to today.

**Swipe gesture**: a horizontal drag on the content area (≥60pt translation, dominant-horizontal motion: `|dx| > |dy| × 1.5`) advances/rewinds one day. Vertical scroll keeps working — the gesture only fires when motion is decisively horizontal.

### Week strip indicator (Phase F.1.2.weekstrip)

Minimal motivational indicator slotted between the date header and the view toggle. Renders the current week as 7 columns (locale-aware first-day-of-week from `Calendar.current.firstWeekday`).

- Each column: three rows top-to-bottom — single-letter weekday abbreviation (`Calendar.veryShortWeekdaySymbols` — "S M T W T F S" in en_US, 10pt), day-of-month number (13pt, `.monospacedDigit()` so 1-digit and 2-digit numbers don't shift the column center), 9pt dot.
- **Dot fill** — sage when the day has at least one non-deleted note, hollow ring (1pt `fg2` @ 0.4) otherwise.
- **Today** — column gets a 1pt sage-tinted ring around its 8pt rounded background. Phase F.1.2.midnight — when midnight rolls over within the displayed week (Mon → Tue, etc.), the ring **slides** between adjacent columns via `matchedGeometryEffect` instead of fading out / fading in. Cross-week rollovers (the new today is outside the displayed week) just fade the ring out — no destination to slide to. Driven by `TimelineStore.currentDay`, which updates from `UIApplication.significantTimeChangeNotification` and a `scenePhase == .active` re-check.
- **Selected day** — sage-soft pill background fills the column. Today + selected = pill + ring stacked.
- **Tappable** — tap a column → `TimelineStore.shared.selectDate(...)`. Doubles as week-level navigation alongside the chevrons.
- Sized ~36pt tall total. Padded 12pt horizontal so the columns spread across the screen evenly.

Backed by `WeekStripStore` (`@Observable @MainActor` singleton) which caches `daysWithNotes: Set<Date>` for the loaded week. `RootView`'s existing `.task(id:)` triggers `WeekStripStore.load(userId:day:)` alongside the regular timeline load — same-week navigations short-circuit; cross-week navigations refetch via `NotesRepository.fetchDaysWithNotes`. Optimistic in-memory updates fire from `TimelineStore.add` / `update` / `delete` so dot fills track live with no refetch.

### Loading state

While the day's notes are being fetched (initial app launch or any day-switch), a thin 2pt indeterminate progress bar overlays the very top of the screen. Sage-tinted, segment slides left → right, animated linearly with `.repeatForever`. The rest of the layout doesn't change — empty days show the same `emptyState` they show after a confirmed-empty load. Replaces the prior redacted-skeleton approach (which flashed in/out on every short fetch and felt noisy).

### View mode toggle

- Pill-style segmented control with **Timeline** + **Board** options.
- Order: the user's **default view leads** (default = Timeline → "Timeline | Board"; default = Board → "Board | Timeline"). Live-updates when the default changes in Settings.
- Active segment: filled `bg2`, warm-ink shadow. Inactive: `taupe` track.
- Initial value: `AppPreferencesStore.shared.defaultTodayView` (default `.timeline`).

### Pinned section (shared by Timeline + Board)

A **Pinned section** appears at the top of every Today view whenever any note is pinned. Section header is uppercase "PINNED" with a honey-yellow `pin.fill` glyph and a count. Layout per mode:
- **Timeline / Cards / Stack** — pinned cards render in a flat 2-col masonry. Drag-to-reorder is intentionally disabled in the pinned section (matches Apple Notes — pinned items keep chronological order; unpin + re-pin to rearrange).
- **Group** — pinned cards render in a horizontal scroll rail above the per-type rails, matching Group's all-rails visual rhythm.

**Duplication differs by mode** — a deliberate design choice:
- **Board** sub-modes (Cards / Stack / Group) feed `unpinnedNotes` into their content below the section, so a pinned note appears **once** (in the shelf only).
- **Timeline** feeds the full chronological list into the rail below, so a pinned note appears **twice** (shelf + natural time slot). Yanking pinned items out of the rail would distort the day's chronological shape, which is the timeline's whole point — the shelf is a quick-access shortcut, not a re-categorization.

Pinning is toggled either by **tapping the pin glyph** in the card's top-right corner (`pin` outline → `pin.fill` honey, idempotent), or via the card's **`.contextMenu`** (Pin / Unpin entry). Both surfaces flow through the same `PinStore.togglePin(_:)` call. The honey-yellow color is invariant across the design system (only token that doesn't light/dark-flip), giving the pinned state a stable universal cue regardless of theme or card tint.

**Discoverability hint** — a first-launch `TipKit` popover ("Pin or delete a card · Touch and hold any card to see options.") anchors to the Timeline / Board segmented toggle, so the long-press affordance is surfaced without permanent chrome. The tip auto-dismisses the first time the user actually uses Pin or Delete via the context menu (`CardActionsTip.userDidUseContextMenu` is donated from the Pin and Delete button actions in `KeepCard.contextMenu`). No nag — once you've used it, you never see it again, on any device after iCloud syncs the TipKit datastore.

### Timeline view

- Optional **Pinned section** (see above) sits above the rail when any note is pinned.
- Vertical rail of `NoteCard`s connected by a sage-dotted line.
- Each row: time column on left + dot/rail + card on right.
- `lineStyle` per row: `belowDotOnly` for the first row, `aboveDotOnly` for the last, `full` for middle, `dotOnly` if there's only one note.
- Cards sit in single-column at full row width.
- Empty state: sun-horizon SF Symbol + "Nothing yet" + "Tap + to add the first note of your day."

### Board view

All three sub-layouts share the same **Pinned section** at the top (see "Pinned section" above). Below the shelf, each sub-mode renders the unpinned subset.

Three sub-layouts, picked from a **top-right toolbar Menu** that only appears when Board is selected (Phase E.5.13 — Apple Files / Photos pattern). The Menu's icon reflects the active sub-mode (`square.grid.2x2` for Cards, `square.stack.3d.up` for Stack, `rectangle.grid.2x2.fill` for Group) so the user has a glance-level cue of which layout is current; opening the Menu shows all three options with a checkmark on the active one. **Cards is the default and listed first**:

#### Cards (default)

- 2-column shortest-column-first masonry — pure SwiftUI via the iOS 16+ `Layout` protocol (`MasonryLayout`).
- 12pt gap between cards (column gap = row gap), 12pt outer horizontal padding.
- Each card uses its **intrinsic** height — short cards don't inflate to fill column space.
- Card max height capped at 480pt.
- **Drag-to-reorder:** long-press any card → drag → drop on a target card.
  - **Drag side:** SwiftUI's `.draggable(NoteDragPayload(id:))` — routes through iOS's system drag (`UIDragInteraction`). The system owns long-press initiation, haptic, lift animation, the floating drag preview, and cancel-on-empty-space.
  - **Drop side:** `.onDrop(of: [.data], delegate: CardsReorderDropDelegate(...))`. The legacy delegate API is used (instead of `.dropDestination`) specifically so `dropUpdated` can return `DropProposal(operation: .move)` — that's the only way in SwiftUI to suppress the system's default green `+` "copy" badge on the drag preview. Reorder is a move, not an add.
  - Drop on a card: the dragged card lands at that card's slot — target (and anything between) shifts toward where the dragged card came from. Symmetric in both directions: backward drag (later → earlier) places source before target; forward drag (earlier → later) places source after target. Surrounding cards reflow to the new packed positions in a single animated layout pass.
  - Drop on empty space: drag is cancelled, no order change.
  - Because `.draggable` participates in UIKit's gesture arbitration (not SwiftUI's), the parent `ScrollView`'s pan recognizer continues to work from any touch start, including over a card.
  - `KeepCard`'s built-in `.contextMenu` (Pin / Delete) coexists with `.draggable`: tap-and-hold-without-drift opens the menu; tap-and-hold-then-drag begins a reorder. Standard iOS disambiguation, no manual gesture coordination.
  - Reorder writes the final item order to `CardsViewOrderStore` (via `move(_:onto:in:)`) so the Reset-order pill and subsequent renders stay in sync.
- **Reset order:** when the user has any custom ordering, a small `↺ Reset order` pill appears at the top-right of the Board area. Tap → animated revert to chronological order.
- New notes added after a manual reorder always land at the **end** of the custom order (never injected into the middle of a hand-curated layout).

#### Stack

- Per-`NoteType` overlapping-card stacks in a 2-col masonry.
- Shares the same 12pt column/row gutter as Cards mode.
- Default top card is the newest of that type; older cards peek above (each layer 4pt down from the one above it, 0.04 smaller, 0.16 more faded).
- A total-count badge sits in the stack's upper-right corner when the group has more than 1 note.
- Tap a stack → unfurls vertically inside its column with `matchedGeometryEffect(id:in:properties: .position)` for smooth in-place expansion. Other column unaffected.
- Only one stack open at a time; switching collapses the previous.
- Single-card "stacks" are non-interactive (the card is the whole content).
- Expanded view has a "Collapse ↑" pill anchored bottom-right below the newest card.
- **Double-tap anywhere in the expanded section collapses it** (Phase E.5.9) — quick shortcut alongside the pill. Works on cards and on the gaps between them; single taps on inner views (e.g., a media card opening the fullscreen viewer) still pass through.

#### Group

- One section per `NoteType`, with a type-colored dot + uppercase header + count.
- Each section is a **horizontal scroll rail** (Phase E.5.11) — Apple Music / App Store rail pattern. Cards are uniform-width (~55% of the viewport via iOS 17's `.containerRelativeFrame(.horizontal)`) so two fit per screen with a peek of the third (visual affordance for "more to swipe"). `.scrollTargetBehavior(.viewAligned)` snaps flicks to card boundaries.
- Card heights stay intrinsic per card (capped at `KeepCard.maxHeight`); section height = tallest card in the rail.
- Empty types are filtered (no hollow headers).

### Per-card actions (Pin / Delete)

**Owns:** `DesignSystem/Components/PinButton.swift`, the pin overlay + `.contextMenu` on `KeepCard.swift` and `NoteCard.swift`, and the `.confirmationDialog` on `TimelineScreen.swift`

Every card surfaces actions through two parallel paths (Phase E.5.15 — modeled on Google Keep + Apple Notes):

- **Pin glyph as status indicator** (Phase E.5.16 refinement) — appears in the top-right corner of a card **only when that card is pinned** (Apple Notes / Mail flag / iMessage pinned-conversation pattern). Tapping the visible glyph unpins. Unpinned cards show no glyph at all, keeping the surface visually quiet for the common case. Glyph is honey-yellow `pin.fill`; on media cards a thin `.ultraThinMaterial` backdrop circle sits behind it for readability.
- **Long-press menu** is the path to **pin** an unpinned card (Pin entry) and to access **Delete**. Across all Board sub-modes the menu comes from SwiftUI's `.contextMenu` on `KeepCard`. Unpin is also available there in addition to the glyph tap.

**Cards-mode gesture model.** A single SwiftUI surface owns both interactions:
- Hold + start moving → `.draggable` initiates a system drag for reorder.
- Hold + stay still → `.contextMenu` opens.

iOS arbitrates between the two automatically — the same Apple Photos / Files pattern, expressed in SwiftUI primitives.

**Delete confirmation.** Selecting Delete arms `pendingDeleteId` on `TimelineScreen`, which presents an `.alert("Delete this note?" / "This can't be undone.")` (centered modal — Apple's pattern for irreversible single-item destruction; see Notes / Photos / Calendar / Reminders). Buttons: destructive **Delete** + cancel **Keep**. Confirmation animates the row out via `withAnimation(.easeOut(0.2))` while `TimelineStore.delete(noteId:)` removes the note (and `PinStore.forget(_:)` clears any ghost pin reference). Cancel just clears `pendingDeleteId` and dismisses.

### FAB (floating action button)

**Owns:** `DesignSystem/Components/FAB.swift` + the menu wiring inside `TimelineScreen`

- 56pt sage circle, white plus icon (24pt semibold), level-2 shadow.
- Anchored bottom-trailing of the screen, 16pt above the tab bar, 20pt from the right edge.
- Tap opens a SwiftUI `Menu` (popover anchored to the FAB). Items in visual top-to-bottom order (most-frequent first to minimize thumb travel):
  - **Text Note** → opens `NoteEditorScreen`.
  - **Photo or Video** → opens `PhotosPicker` (filter `.any(of: [.images, .videos])`, `preferredItemEncoding: .current` to skip Apple's H.264 transcode for ProRes / ProRAW); on selection, presents `MediaNoteEditorScreen` with the picked item wrapped in `InitialMedia.pickerItem(...)`.
  - **Take Photo or Video** (Phase F.1.1b'.camera) → presents `CameraPicker` (a `UIViewControllerRepresentable` over `UIImagePickerController(.camera)`) full-screen. On capture, the result wraps into `InitialMedia.cameraImage(UIImage)` for stills or `InitialMedia.cameraVideoURL(URL)` for clips and the same `MediaNoteEditorScreen` opens. Captured videos route through the same `MediaImporter.videoImportResult` pipeline as picker imports — including the trim sheet for >60 s captures. Permissions: `NSCameraUsageDescription` + `NSMicrophoneUsageDescription` in `Info.plist`.
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

### Type picker (top of editor) — Phase F.1.2.picker

**Defer the decision + searchable sheet** (combo A+B from the captured TODO discussion). The editor opens straight to writing — the type is represented by a single chip near the title field showing the current selection. The user never has to interact with a type picker just to start typing.

- Default selected type: `.general` (neutral, warm-gray pigment, generic note icon — quick notes don't get implicitly tagged).
- Tap the chip → presents `NoteTypePickerSheet` (`.medium` / `.large` detents) with a search field at the top + 2-column grid of all `NoteType.textEditorPickable` (`.media` excluded — auto-tagged on bare-media saves).
- Type to filter live — `title.lowercased().contains(query.lowercased())` against the type's display name.
- Tap a grid cell → commits the selection + dismisses. Cancel via toolbar dismisses without changing.
- Scales to N types without changing the UI — handles the existing 7 system types, future custom user types, and any new system types added via migration.

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
- **Backed by a `[TextBlock]` body** (Phase E.5.18). The editor's TextEditor reads/writes the first paragraph block via a `NoteDraftStore.message` bridge. Inserting a photo via the toolbar's `+image` icon appends a media block (with default `MediaBlockSize.medium`) plus a fresh trailing paragraph — the model supports interleaving paragraphs with media in any order; the Phase 1 editor UI just appends new attachments after the typed paragraph (mid-paragraph insertion is a future iteration).

### Attachments strip (inline media in text notes)

Phase E.5.18 / E.5.18a. When the user taps the `+image` icon in the StyleToolbar, the iOS PhotosPicker opens (`.any(of: [.images, .videos])`); the selected asset is imported via `MediaImporter`. **For images, a crop sheet** (`PhotoCropView`) is presented with freeform + aspect-preset chips before the cropped payload is added to `draft.body` as a `TextBlock.media` (Phase E.5.18a). Videos skip cropping and insert directly. The strip below the message editor renders one `InlineMediaBlockView` per media block, sized by `MediaBlockSize.widthFraction` (Small ~45% / Medium ~75% / Large 100%).

- **Tap a thumbnail in the editor** → opens the fullscreen `MediaViewerScreen` viewer (Phase E.5.18a — pinch-zoom for images, AVPlayer for videos). Same behavior as cards.
- **Long-press a thumbnail in the editor** → `.contextMenu` opens with a size `Picker` (Small / Medium / Large) and a destructive **Remove** entry. Apple Notes / Photos pattern. Picking a size mutates the block's size in `NoteDraftStore.resizeMediaBlock(id:to:)`; Remove drops the block via `NoteDraftStore.removeBlock(id:)`. If removal would empty the body, an empty paragraph is restored so the editor keeps a cursor target.
- Errors during import surface inline below the strip ("Couldn't load that file…") so the user knows without a disruptive alert.
- Saved blocks survive `TimelineStore.add` round-trip — the test suite covers paragraph + media interleaving.

### Trailing TextEditor (type after the images)

Phase E.5.18a. `NoteDraftStore.insertMedia(...)` maintains the structural invariant `[firstParagraph?, media*, trailingParagraph]` — every inline media block sits between the first and last paragraph. When the body has any media, the editor renders a **second TextEditor below the attachments strip** bound to `NoteDraftStore.trailerMessage` (the last paragraph). This is the "type after the images" affordance: write some intro text → attach a photo → keep typing in the new editor below the photo.

- Hidden when the body has no media (one TextEditor handles the only paragraph).
- Style toolbar applies to whichever paragraph is currently focused — first or last — by routing the `transformAttributes(in:)` call via `transformActiveBody`.
- Mid-paragraph media insertion (full per-block focused TextEditors) is intentionally deferred — the data model supports it; the UI ships the simpler "intro / attachments / outro" three-zone editor for now.

### Card rendering of inline media (Board view)

`KeepCard` walks the `.text` content's body block-by-block: paragraphs render as `Text(AttributedString)`, media blocks render via `InlineMediaBlockView` at the user's chosen size (centered for Small / Medium, full-width for Large). Tapping a media block in a card opens `MediaViewerScreen` full-screen (pinch-zoom for images, AVPlayer for videos). On the Timeline (`NoteCard`), inline media is intentionally *not* rendered — `MockNote.timelineMessage` flattens paragraph blocks to a single AttributedString and skips media (the dense rail favors text-only summaries; the full block layout is the Board view's job).

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

- Three sections: **None** (slash-swatch), **Photo** (PhotosPicker + opacity slider + Replace / Edit crop / Remove when set), **Color** (palette tabs + adaptive swatch grid).
- Photo and Color are mutually exclusive.
- Opacity slider: 0.1 to 1.0, sage-tinted.
- **Photo import (Phase D.2.2)** — picking a photo downscales it to 1024px max longest edge (JPEG q=0.85) so the stored bytes stay small, then auto-launches the same `PhotoCropView` media notes use for cropping (full Free / 1:1 / 4:3 / 3:4 / 16:9 / 9:16 aspect chips). Cancel from the auto-crop keeps the uncropped picked photo. **Edit crop** re-opens the same sheet against the current bytes for refinement. The cropped bytes replace `ImageBackground.imageData`; cards still render `.scaledToFill().clipped()` against those bytes — no render-time transform.

### Background row in editor (deprecated path)

The dedicated "Background" row was removed when the toolbar got a `🖼` icon (Phase E.2.2). The icon is the only entry point now.

### Edit existing note (Phase F.1.0)

Tapping a text card on the timeline opens `NoteEditorScreen` in **edit mode**, pre-populated with the note's data. Modern instant-edit pattern — no separate view-only mode (the cards already are the read view). Mode-specific behaviors:

- **Save button** reads "Done"; calls `TimelineStore.update(_:)` (optimistic in-memory swap + background `NotesRepository.update`; reverts on failure).
- **Drag-to-dismiss autosaves** — Apple Notes pattern. Different from create mode, where drag-to-dismiss preserves the draft for cross-session recovery.
- **Cancel** triggers a "Discard changes?" alert when any of title / body / type / background / titleStyle / occurredAt differ from the original note; otherwise dismisses immediately.
- **Toolbar actions menu** (`ellipsis.circle`): Pin/Unpin toggle + Delete (arms the standard centered-alert delete confirmation).
- **Per-instance `NoteDraftStore`** so opening a note for edit doesn't trample any in-progress new-note draft (and vice versa). The shared singleton remains the create-mode store.
- **Nav title** shows the note's `occurredAt` formatted as `Apr 27`.
- **Type picker** opens collapsed (the user already committed); user can still expand to re-categorize.

**Tap targets**: only text-content cards (`.text` variant). Stat / list / quote / media notes are non-tappable for now (no editor for stat/list/quote variants exists yet; media uses a different flow). Media cards retain their existing tap-to-fullscreen via `MediaViewerScreen`.

### Date + time row (Phase F.0.3)

A compact `DatePicker(.compact)` row sits at the bottom of the form, between the body content and the toolbar. Layout: `🕐 Time ........ [picker]`. Tapping the picker opens iOS's standard popover with a calendar grid + time wheels.

- **Default value:** `TimelineStore.selectedDate` spliced with the current wall-clock time-of-day. So when you tap FAB while viewing today, it defaults to right-now; when you've navigated to a past day and tap FAB, it defaults to that day at the current time-of-day so the new note lands at a believable position in that day's chronology.
- **User picks override the default** — once the picker is touched, `draft.occurredAt` is the source of truth on save. `draft.clear()` resets it to `nil` so the next session re-defaults.
- **Range:** unbounded. Future dates are valid (those notes appear in the timeline as reminders/todos per the schema). If/when the timeline gains a "Today" filter or there's UX to distinguish "what happened" vs "what's planned," the picker may grow a constraint.
- **Same row in `MediaNoteEditorScreen`** — visually identical, except its `occurredAt` lives in local `@State` rather than the shared draft store (media notes don't persist drafts).

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

Sheet presented from the FAB menu's **Photo or Video** path. Single-purpose — no rich-text apparatus, no type picker. Always saves with `NoteType.media` (Phase E.5.10), so all bare media notes auto-collect into the Media section in Group / Stack views.

### Layout

- Nav: Cancel / Save. Title: "New media note".
- Content: media preview at top → Replace / Remove → Caption field.

### Photo flow

- Selected image is loaded via `MediaImporter.makePayload(from:)` → decodes via `UIImage`, computes aspect ratio.
- Preview displays a `PhotoCropView` for cropping (see [Photo crop tool](#photo-crop-tool)).
- Save commits the user's crop into a fresh `MediaPayload`, then attaches the optional caption.

### Video flow

- All video-capable `PhotosPicker` / `.photosPicker` call sites use **`preferredItemEncoding: .current`**. The default `.automatic` policy transcodes ProRes / ProRAW to H.264 before handoff (multi-minute server-side render); `.current` returns raw bytes — picker → ready typically <2 s for a 1 GB+ ProRes clip.
- The picker hands back a `VideoFile: Transferable` (file-based, copies via `FileRepresentation`) — never `Data`. ProRes assets can be 1+ GB and the `Data` path materializes the whole thing in RAM.
- `MediaImporter.videoImportResult(from url:)` opens an `AVURLAsset`, loads `.duration` + first track's `naturalSize` + `preferredTransform` for aspect ratio.
- **Under-cap clips** (≤ 60 s): generates a first-frame poster JPEG, re-encodes to **HEVC 1080p** via `AVAssetExportSession` (~50% smaller than H.264), cleans up the temp file, returns `.payload(MediaPayload)`.
- **Over-cap clips** (> 60 s): skips the upfront poster (saves a ProRes frame decode), returns `.needsTrim(VideoTrimSource)` — the [Video trim sheet](#video-trim-sheet) takes over.
- Preview is read-only — poster image with `.ultraThinMaterial` play button overlay; tap opens the same `MediaViewerScreen` used from the timeline.
- Save attaches caption + saves with the encoded video bytes + generated poster.

### Video trim sheet

**Owns:** `Features/MediaTrim/VideoTrimSheet.swift`

Shown automatically when the user picks a video longer than `MediaImporter.videoMaxDurationSeconds` (60 s). Apple Photos pattern adapted to DailyCadence's sage palette.

- **Preview**: `AVPlayerLayer` (bare — no `AVKit.VideoPlayer` chrome). Tap to play / pause; preview audio is muted by default. Playback loops within the trim window — a boundary observer at the end seeks back to start and resumes.
- **Filmstrip**: 14 evenly-spaced frames generated via `AVAssetImageGenerator` across the full source duration. Empty `bg2` block while frames generate (decorative; trim still works without them).
- **Range selection**: dual sage handles + sage border around the trim window. **Three drag zones**:
  - Left handle: shrinks the window from the start (1 s minimum, 60 s maximum — past the cap, the right handle is pulled in).
  - Right handle: shrinks the window from the end (same constraints, mirrored).
  - Middle band: slides the window as a unit (essential when the desired slice is in the middle of a long clip).
- **Playhead**: 2 pt white bar inside the window, animated via a 30 Hz periodic time observer during playback; snaps to the dragged handle's time during scrubs.
- **Duration label**: "0:43 of 1:00 max" plus current `start – end` timestamps (mm:ss, monospaced digits).
- **Toolbar**: Cancel / Save. Save disabled if window is shorter than 1 s.
- **Export**: confirm calls `MediaImporter.makeTrimmedVideoPayload(source:range:)` — sets `AVAssetExportSession.timeRange` and re-runs the same HEVC 1080p export, plus regenerates the poster from the new start frame. Cancel calls `MediaImporter.discardTrimSource(_:)` which removes the temp source file.

### MediaImporter return shape

- `MediaImporter.makePayload(from:)` returns an `ImportResult` enum: `.payload(MediaPayload)` for normal flow, or `.needsTrim(VideoTrimSource)` for over-cap videos. Both editor surfaces (`MediaNoteEditorScreen`, `NoteEditorScreen`) handle both cases.
- `VideoTrimSource` carries the temp file URL + duration + aspect + first-frame poster — the trim sheet's input. Cleanup is owned by the trim path: `makeTrimmedVideoPayload` cleans up on success, `discardTrimSource` on cancel.

### Caption

- Single-line label "Caption" (12pt label) → 1...4 line `TextField` with rounded `bg2` background.
- Whitespace-trimmed at save; empty → `nil`.

### No draft store for media

- Media notes don't use `NoteDraftStore`. The asset itself is the substance — forcing a re-pick on accidental dismiss is less disruptive than re-typing a long text body.

---

## Photo crop tool

**Owns:** `Features/MediaCrop/PhotoCropView.swift`

Photos.app-style. Built into the media editor.

- **Image** lays out at scale-to-fit inside the canvas (`imageRect`), then receives the user's pinch + pan transform → `displayedImageRect`.
- **Crop rectangle** floats in canvas coordinates. Initially fills the visible image.
- **Four corner handles** — white L-shapes, 18×18 visual / 36×36 hit target. Visible glyph is offset 9pt inward from the corner so it stays inside the rect (and inside the canvas) even when the crop equals the image bounds. Drag to resize.
  - **Free** mode: resize freely.
  - Aspect-locked modes (1:1 / 4:3 / 3:4 / 16:9 / 9:16): resize maintains the locked aspect by anchoring on the corner opposite the dragged handle.
- **Pinch (two-finger) on the canvas** — zooms the image in place around its center. Range 1×–5×. Offset re-clamps on every scale change so the displayed image always covers the base `imageRect`.
- **Drag (single-finger) inside the crop rect** — pans the *image* under the rect (Apple Photos pattern: the rect is fixed, the image moves). Translation is clamped against the current scale so the displayed image always covers the base rect.
- **Aspect chips row** — Free / 1:1 / 4:3 / 3:4 / 16:9 / 9:16. Selecting one resets zoom + pan and snaps the rect to that ratio centered inside the base image rect (matches Apple Photos: changing aspect is a clean state).
- **Dimmed exterior** — eo-fill `Canvas` paints `black @ 0.55` over the canvas with a hole punched at the crop rect.
- **Rule-of-thirds guides** — two horizontal + two vertical white lines at 1/3 / 2/3 inside the crop rect at 0.4 opacity.
- **Minimum crop dimension** — 60pt in canvas coords.
- **Commit** maps the canvas-space crop rect back to image pixel coordinates via `displayedImageRect` (which folds in pinch + pan); clamps; calls `CGImage.cropping(to:)`; encodes JPEG at 0.9 quality. At zoom = 1× / offset = 0 this collapses to the original `imageSize / imageRect.size` mapping.
- **Orientation normalization** — `UIImage.normalizedUp()` redraws non-`.up`-oriented inputs (iPhone portrait photos arrive as `.right`) so the cropped output lands in visible coordinates rather than raw rotated pixel space. Wrapped in `autoreleasepool` so the intermediate render buffer drains synchronously — without it, a 48 MP iPhone Pro photo holds two ~187 MB bitmaps live during the redraw and gets jetsamed on memory-constrained devices.

---

## Media viewer

**Owns:** `Features/MediaViewer/{MediaViewerScreen, ImageMediaContent, VideoMediaContent}.swift`

Full-screen viewer presented as a `RootView` overlay (so the underlying timeline keeps rendering through the backdrop fade), opened with an Apple Photos-style matched-geometry zoom from the source card. Falls back to `.fullScreenCover` for surfaces without a tap handler (previews, non-Timeline screens).

### Open / close zoom (Phase F.1.1b'.zoom)

- Cards publish their image-area frame via `CardFrameKey`; on tap, `RootView` snapshots that frame onto `PresentedMedia` and animates `openProgress` from 0 (content at source-card frame) to 1 (content at fullscreen-fitted frame). The viewer interpolates `.frame` + `.position` between the two each render.
- Animation: `.smooth(duration: 0.5)` symmetric on both directions; the close keeps the overlay rendered for 510 ms via a deferred-clear `hidingMedia` slot so the close runs above the TabBar layer.
- Constant 10pt corner radius matches the source card so the close-handoff has no corner-shape pop.
- Source-card opacity gates on `MatchedGeometryModifier.visibleID` (covers `presentedMedia ?? hidingMedia`) so the card stays invisible across the entire close.

### Shared viewer envelope

`MediaViewerScreen` is a thin shared envelope that handles zoom interpolation, corner clip, drag-dismiss visual effect (`.scaleEffect(dismissScale).offset(dismissOffset)` applied at outer level), and chrome — the kind-specific content lives in `ImageMediaContent` / `VideoMediaContent`. Both write drag-dismiss state into bindings owned by the envelope so the visual effect is identical for image and video.

- Top-trailing close button (X in `.ultraThinMaterial` 36pt circle).
- **Caption** (when present) — bottom gradient overlay (`.clear → .black @ 0.45`), white sans 15pt, 24pt horizontal padding, multiline-centered.
- **Capture date** (when present) — same gradient zone as the caption, leading-aligned below it, white sans 12pt @ 0.85 opacity, locale-aware format (`Date.formatted(date: .abbreviated, time: .shortened)` — "Apr 27, 2026 at 8:42 PM" in en-US). Sourced from EXIF `DateTimeOriginal` for image library imports, `Date()` for camera captures (UIImage.jpegData strips EXIF), `AVAsset.creationDate` for videos. **Distinct from the note's `occurredAt`** — `occurredAt` is when the user logged the note; `capturedAt` is when the moment happened. Photos taken weeks ago and added to today's timeline still display their true capture date.
- Bottom gradient is suppressed entirely when neither caption nor capturedAt is present (metadata-less screenshot → clean unobstructed bottom).
- Status bar hidden during the viewer.

### Image content (`ImageMediaContent`)

- Pinch to zoom 1×–5×, double-tap to toggle 1×↔2.5×, pan-when-zoomed.
- **Drag-down to dismiss** at scale 1: image follows finger (vertical + horizontal), backdrop fades proportionally over 200pt, scales toward 0.7×. Commit threshold: translation > 120pt OR predicted velocity > 600pt. Below threshold, springs back via `.spring(response: 0.35, dampingFraction: 0.85)`.
- The `DragGesture` uses `.global` coordinate space (not the SwiftUI default `.local`). The gesture's own writes drive `.scaleEffect` + `.offset` on the same view, so a `.local` space would shift under the finger and `value.translation` would oscillate — a positive feedback loop manifesting as violent shake / image splitting. `.global` reports translation in stable window coords. Ports must replicate this — the video equivalent uses `UIPanGestureRecognizer.translation(in:)` which is naturally screen-stable.
- Thumbnail bytes (~80 KB HEIC) are sync-decoded in `init` so the very first zoom-in frame paints; full-resolution decode runs in `.task` and swaps in when ready.

### Video content (`VideoMediaContent`)

- **Poster handoff during zoom** — `posterData` is sync-decoded in `init` and shown immediately so the open zoom has visible content from frame one (matches what the source card was showing). Crossfades to the live `AVPlayerViewController` once `currentItem.status == .readyToPlay` (polled at ~30 fps).
- AVKit chrome: scrubber, play/pause, mute, AirPlay (`showsPlaybackControls = true`, `videoGravity = .resizeAspect`).
- **AVKit-coexisting drag-dismiss** — `UIPanGestureRecognizer` attached to the player view via `UIViewControllerRepresentable`. Delegate returns `true` from `shouldRecognizeSimultaneouslyWith` (coexists with all of AVKit's gestures) and only returns `true` from `gestureRecognizerShouldBegin` when initial velocity is vertical-dominant downward — so horizontal scrubs and taps fall through to AVKit untouched. Same translation/velocity thresholds as image.
- **Auto-pause on dismiss** — `isDismissing` flips when the viewer's `performDismiss` runs (X button, drag-commit, or fallback). `.onChange` pauses the player synchronously so audio doesn't bleed through the close animation.
- **Bytes path** — Phase F.1.1: signed URL via `MediaResolver` for fetched videos (`media.ref` set), or temp-file write at `temporaryDirectory/dc-video-<UUID>.mov` for newly-imported inline bytes. Temp file cleaned up in `onDisappear`.

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
- **Note Types** — `NavigationLink` to `NoteTypePickerScreen`. Row preview: 7 overlapping circles colored by current per-type colors + summary string ("Default" / "1 customized" / "N customized").
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
- 10 note-type pairs: `workout`/`workoutSoft`, `meal`/`mealSoft`, `sleep`/`sleepSoft`, `mood`/`moodSoft`, `activity`/`activitySoft`, plus `general` using `warmGray`/`taupe`, `media` using `periwinkle`/`periwinkleSoft`, `pets` using `blush`/`blushSoft`, `book` using `book`/`bookSoft` (coffee-brown), and `recipe` using `recipe`/`recipeSoft` (paprika red).
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
| `Segmented.swift` | Reusable pill segmented control (Timeline/Board, primary view picker). The Cards/Stack/Group sub-picker moved into a toolbar Menu in Phase E.5.13. |
| `TabBar.swift` | Custom 5-column bottom navigation. |
| `TypeBadge.swift` | 10pt colored dot + 11pt uppercase type label (rendered in `type.color`) + optional time in mono `fg2`. Phase E.5.14 bump from 8pt/10pt-grey for stronger type signal on Timeline cards. |
| `PinButton.swift` | 13pt `pin` / `pin.fill` SF Symbol in honey-yellow with 32pt hit area. (Phase E.5.15 introduced; E.5.16 made it a status indicator — only shown on pinned cards. Tapping the visible glyph unpins.) The unpinned-state visual is retained for any future read-only contexts. |
| `InlineMediaBlockView.swift` | Inline photo/video block (Phase E.5.18) used by KeepCard and NoteEditorScreen's attachments strip. Sizes via `MediaBlockSize.widthFraction` (~45% / ~75% / 100%); `isInteractive` toggle controls whether tapping opens fullscreen (cards) or is suppressed for a parent Menu (editor). |
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

- Ten cases: `general` (text-note default, neutral), `workout`, `meal`, `sleep`, `mood`, `activity`, `pets` (Phase F.1.2.pets — pet-related logs; pawprint icon, blush pigment), `book` (Phase F.1.2.book — reading logs; book.closed.fill icon, coffee-brown pigment; structured-data schema reserved for `title`/`author`/`progress`/`is_finished`), `recipe` (Phase F.1.2.recipe — recipe screenshots + tags; frying.pan.fill icon, paprika-red pigment; structured-data schema reserved for `title`/`food_type`/`tags`/`is_favorite`), `media` (auto-assigned to bare photo/video notes; Phase E.5.10).
- Each has a title, default pigment + soft color, and a SF Symbol placeholder. Color/icon overrides via `NoteTypeStyleStore` flow into all card visuals.
- `NoteType.textEditorPickable` returns `allCases` minus `.media` — used by the text-note editor's type picker so a text note can't accidentally be tagged Media. Settings → Note Types and Group / Stack views still use `allCases`, so Media participates in color overrides and section rendering like any other type.

### MediaPayload

- `kind: .image | .video`, `data: Data`, `posterData: Data?` (videos only), `aspectRatio: CGFloat` (clamped 0.4...2.5 to keep the masonry sane), `caption: String?` (whitespace-trimmed, empty → nil).
- `capturedAt: Date?` (Phase F.1.2.exifdate) — wall-clock moment the asset was captured. Image library imports populate from EXIF `DateTimeOriginal`; camera captures use `Date()` at shutter; video uses `AVAsset.creationDate`. `nil` for assets without metadata (screenshots, edited exports) and for notes saved before this field landed. Surfaced in `MediaViewerScreen`'s bottom chrome.
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
| `PinStore` | in-memory | session | Set of pinned note ids (Phase E.5.15). Drives the "Pinned" section at the top of Timeline + every Board sub-mode, plus the visible pin glyph on each card. |

Repository services (read-only) for JSON-backed catalogs:

- `FontRepository` (`fonts.json`): 7 user-pickable fonts.
- `PaletteRepository` (`palettes.json`): 4 palettes × 6 swatches (Neutral / Pastel / Bold / Bright).
- `PrimaryPaletteRepository` (`primary-palettes.json`): 8 primary themes.

---

## Out of scope (Phase 1)

These are deferred. When porting, don't rebuild them on Android either — match the Phase-1 surface so we keep platforms in step.

- Camera capture (UIImagePickerController + `NSCameraUsageDescription`).
- Inline text formatting toggles (bold / italic / underline / strikethrough).
- Auto-bullet on `-` and Apple-Notes-style checkboxes inside text notes.
- Inline image attachments inside text notes (recommend Apple-Notes-style flow when this lands).
- Real Calendar / Progress / Library tabs (placeholders only in Phase 1).
- Supabase auth + persistence wiring.
- Drag-to-reorder on Stack and Group Board layouts (only Cards layout is reorderable in Phase 1).
- Backdating a note (the editor stamps `Date.now` only).

---

*This file is maintained by hand. If something here disagrees with the iOS code, the iOS code wins — file an issue and update this doc.*
