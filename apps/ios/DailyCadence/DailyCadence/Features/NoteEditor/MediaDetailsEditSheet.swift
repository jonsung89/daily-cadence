import SwiftUI

/// Phase F.1.2.caption — lightweight sheet for editing the caption and
/// occurred-at timestamp of an existing media note. Reuses neither
/// `MediaNoteEditorScreen` (which owns the full create flow including
/// media replace + crop + import pipeline) nor `NoteEditorScreen`
/// (text-note editor) — the only things editable here are the caption
/// string and the timestamp. Keeping the surface focused matches the
/// long-press-menu entry point.
///
/// Presents as a `.medium` detent sheet with a multi-line caption
/// TextField, a date+time row matching the create-flow editor, and
/// Cancel / Save toolbar. On save, hands the new caption + occurredAt
/// back via the `onSave` closure; the caller reconstructs the
/// `MockNote` and forwards to `TimelineStore.update`. On cancel,
/// dismisses without persisting.
///
/// Renamed from `CaptionEditSheet` when the date+time field landed —
/// caption was the only editable field through TestFlight 1.0 (1).
struct MediaDetailsEditSheet: View {
    /// Initial caption — pre-fills the TextField. `nil` is treated as
    /// empty so the placeholder shows.
    let initialCaption: String?
    /// Initial occurred-at — pre-fills the date+time picker. `nil`
    /// (rare; legacy notes without an explicit timestamp) defaults to
    /// "today + now" in the binding.
    let initialOccurredAt: Date?
    /// Capture moment from the underlying `MediaPayload`. Used only to
    /// drive the relative-time hint under the picker — when the
    /// current draft equals this value, render "X days ago" / etc.
    /// `nil` when the media has no metadata (screenshots, edited
    /// exports, legacy notes saved before EXIF extraction shipped).
    let initialCapturedAt: Date?
    /// Fires once on Save with the trimmed caption (or `nil` if cleared)
    /// and the picker's selected timestamp. Caller is responsible for
    /// the round-trip through `TimelineStore.update`.
    let onSave: (String?, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftCaption: String
    @State private var draftOccurredAt: Date

    init(
        initialCaption: String?,
        initialOccurredAt: Date?,
        initialCapturedAt: Date?,
        onSave: @escaping (String?, Date) -> Void
    ) {
        self.initialCaption = initialCaption
        self.initialOccurredAt = initialOccurredAt
        self.initialCapturedAt = initialCapturedAt
        self.onSave = onSave
        self._draftCaption = State(initialValue: initialCaption ?? "")
        self._draftOccurredAt = State(initialValue: initialOccurredAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField(
                    "Add a caption…",
                    text: $draftCaption,
                    axis: .vertical
                )
                .font(.DS.sans(size: 16, weight: .regular))
                .foregroundStyle(Color.DS.ink)
                .lineLimit(3...10)
                .textFieldStyle(.plain)

                Divider()
                    .background(Color.DS.border1)

                occurredAtRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.DS.bg1)
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = draftCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed, draftOccurredAt)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(Color.DS.sageDeep)
                    // No disabled state — saving an empty caption is
                    // valid (clears it). User can also Cancel for "no
                    // change."
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Date+time row matching the create-flow editors so the two
    /// surfaces feel consistent. When the draft still equals the
    /// underlying media's `capturedAt`, a relative-time hint
    /// surfaces below the picker — same logic as
    /// `MediaNoteEditorScreen.relativeTimeHint`.
    private var occurredAtRow: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.DS.fg2)
                Text("Time")
                    .font(.DS.body)
                    .foregroundStyle(Color.DS.ink)
                Spacer(minLength: 8)
                DatePicker(
                    "Time",
                    selection: $draftOccurredAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }
            if let hint = relativeTimeHint {
                Text(hint)
                    .font(.DS.caption)
                    .foregroundStyle(Color.DS.fg2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: relativeTimeHint)
    }

    /// Friendly "X days ago" / "yesterday" annotation under the time
    /// picker. Visible only while the draft picker still equals the
    /// note's underlying `capturedAt` AND the gap from now is at
    /// least 60 seconds (suppresses the hint for media captured
    /// essentially "now"). User edits to the picker break the
    /// equality check and hide the hint.
    private var relativeTimeHint: String? {
        guard let capturedAt = initialCapturedAt,
              draftOccurredAt == capturedAt
        else { return nil }
        let delta = abs(capturedAt.timeIntervalSinceNow)
        guard delta >= 60 else { return nil }
        return capturedAt.formatted(.relative(presentation: .named))
    }
}

#Preview("With caption + relative hint") {
    let capturedThreeDaysAgo = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
    return Text("Long press a card")
        .sheet(isPresented: .constant(true)) {
            MediaDetailsEditSheet(
                initialCaption: "Sunset at the lake, peaceful day",
                initialOccurredAt: capturedThreeDaysAgo,
                initialCapturedAt: capturedThreeDaysAgo,
                onSave: { _, _ in }
            )
        }
}

#Preview("Empty, no metadata") {
    Text("Long press a card")
        .sheet(isPresented: .constant(true)) {
            MediaDetailsEditSheet(
                initialCaption: nil,
                initialOccurredAt: .now,
                initialCapturedAt: nil,
                onSave: { _, _ in }
            )
        }
}
