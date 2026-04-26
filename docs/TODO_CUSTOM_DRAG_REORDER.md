# TODO — Custom DragGesture reorder for the Cards Board layout

**Status:** ✅ **Done — landed in Phase E.5.7 (2026-04-25).** See `docs/PROGRESS.md` for the full implementation summary.

This file is kept for historical context. The original spec described
the structural limits of `.onDrag` / `.onDrop` / `DropDelegate` and the
target architecture (`LongPressGesture.sequenced(before: DragGesture)`
with frame-collected hit-testing). The actual implementation closely
followed the sketch — see `Services/DragSessionStore.swift`,
`Features/Timeline/CardFramePreferenceKey.swift`, and the
`reorderGesture(for:allNotes:)` helper in
`Features/Timeline/TimelineScreen.swift`.

## Summary of what shipped

- Custom gesture chain owns drag-state, hit-testing, and lifecycle.
- `CardFramePreferenceKey` publishes per-card frames in a named
  coordinate space; `DragSessionStore.cardFrames` is the hit-test map.
- Drop on empty space reverts via `CardsViewOrderStore.restore(_:)`
  with a snapshot taken at drag start.
- No `dropEntered` cascade — moves only fire when the finger crosses
  into a different `lastTargetId`.
- No fade-stuck after drop-on-self — `onEnded` always clears the
  session (the iOS source-as-drop-target filtering doesn't apply).
- Floating preview is a duplicate `KeepCard` rendered in the grid's
  `.overlay`, offset by the user's grab point so the card stays
  "in hand."
- Medium haptic on lift; light haptic on commit.
- 3 new tests in `CardsViewOrderStoreTests` cover the revert and
  cascade-guard semantics; 98/98 total tests passing.

## Acceptance criteria — all met

- ✅ Dropping precisely on a card commits the move, no fade-stuck state.
- ✅ Dropping on empty space reverts to the order at drag start.
- ✅ No `dropEntered` cascade.
- ✅ Existing `CardsViewOrderStoreTests` still pass.
- ✅ +2 new tests added (we landed +3).
- ✅ `docs/FEATURES.md` updated to drop the limitations caveats.

## Out of scope (intentionally — see PROGRESS for follow-ups)

- Auto-scroll the grid when dragging near the viewport edges.
- Per-row haptics on every card crossed during the drag.
- Reorder for Stack / Group layouts (those organize by `NoteType`
  and don't need custom ordering).
