# TODO — Custom DragGesture reorder for the Cards Board layout

**Status:** Open. Targeted for a future session.
**Estimated effort:** 1 focused round (3–5 hours of implementation + polish).
**Why:** The current `.onDrag` + `.onDrop` + `DropDelegate` plumbing is bumping
into iOS-native limits that no amount of patching cleanly resolves.

## Why we should do this

Phases E.4.8 → E.5.5 layered fixes on top of SwiftUI's drag-and-drop, but
three structural limitations remain:

1. **No "drag ended" callback.** SwiftUI's `.onDrag` doesn't tell us when a
   drag finishes if the drop landed outside any registered `.onDrop` view.
   When iOS filters the source as a drop target (which it does for
   "drop on self"), the entire drag ends without a SwiftUI callback,
   leaving our `DragSessionStore` state stale until the next drag starts.
   We patched this with an `endSession()` call at the start of each
   subsequent `.onDrag` (see Phase E.5.6), but the *current* drag still
   shows a stale fade until the user starts another one.

2. **`dropEntered` cascade.** With live reflow, cards animate into new
   positions during the drag. Because the user's finger is stationary in
   screen coordinates while the drop zones move, `dropEntered` fires on
   several different cards in succession, each triggering another move.
   We patched this with a `lastMoveTargetId` guard so we don't move
   *redundantly* to the same target, but a target *change* during the
   cascade can still produce the wrong final position.

3. **No cancel semantics.** The user can't cancel mid-drag — wherever
   the live reflow last placed the card is where it stays, even if they
   release on empty space (which any reasonable user reads as "cancel").

## What "good" looks like

A reorder UX that matches Google Keep web / Apple Photos library reorder:

- **Long-press** any card to enter a reorder gesture (haptic confirm).
- **Drag** the card with the system rendering the dragged preview at the
  finger.
- **Live reflow** of underlying cards as the finger moves, but driven by
  *our* hit-testing (not iOS's drop-target system), so cascades and
  filtered-source bugs go away.
- **Release on a card or in a gap** → commits the move.
- **Release outside the grid** (or hit the cancel boundary) → reverts to
  the original order.
- Dragged card fades while in transit; live target gets a sage outline;
  we keep the existing visual contract.

## Sketched architecture

- Wrap the gesture in a `LongPressGesture(minimumDuration: 0.4)
  .sequenced(before: DragGesture(coordinateSpace: .global))` chain.
  - `.first(true)` → fire haptic, capture source `id` + initial offset,
    snapshot `customOrder` for revert.
  - `.second(true, drag?)` → on each delta, hit-test the finger against
    each card's frame (via a `PreferenceKey`-published frame map) and
    update the order via `CardsViewOrderStore.shared.move(_:before:)`.
- **`onEnded`** → if the finger is over a valid card frame, commit; if
  it's over empty space, revert to the snapshot.
- Replace `.onDrag` / `.onDrop(of:delegate:)` / `NoteReorderDropDelegate`
  with the custom gesture. Keep `DragSessionStore` for the drag-state
  visuals (source fade, target outline) — the structure carries over.
- `MasonryLayout` already does shortest-column-first packing on every
  re-render; live reflow uses the same layout, so the visual stays
  consistent.

## Reference snippets we'd lean on

- `MasonryLayout.swift` for column packing.
- `CardsViewOrderStore.swift` for the order mutation surface.
- `DragSessionStore.swift` for shared drag state.
- The current `.contentShape(.dragPreview, _:)` modifier still applies
  if we want a rounded preview clip.

## Out of scope for this round

- Per-row haptics on every card crossed during the drag (just the
  initial long-press confirm + final commit).
- Auto-scroll the grid when the finger nears the top/bottom edge of
  the viewport during a drag (nice-to-have, schedule separately).
- Re-implementing reorder for Stack / Group layouts — those still
  organize by `NoteType` and don't need custom ordering.

## Acceptance criteria

- Dropping precisely on a card commits the move, no "fade stuck" state.
- Dropping on empty space reverts to the order at drag start.
- No `dropEntered` cascade visible in the layout (final position
  matches the last hover, not a chain of intermediate moves).
- Existing tests in `CardsViewOrderStoreTests` still pass (the order
  mutation surface is unchanged).
- Add at least 2 new tests covering "drop on empty reverts" and
  "drag-then-drop on card commits exactly once."
- FEATURES.md drag-to-reorder section updated to drop the "limitations"
  caveats this work resolves.

## When to do this

Pick up in a new session. Read PROGRESS.md (Phase E.5.6 should be the
last reorder phase) + this doc + the files listed above to get oriented
before writing code.
