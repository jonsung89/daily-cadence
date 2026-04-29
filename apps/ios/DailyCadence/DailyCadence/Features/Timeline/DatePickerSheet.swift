import SwiftUI

/// Graphical date picker sheet — Phase F.0.3's "jump to any date"
/// affordance. Presented from `TimelineScreen` when the user taps the
/// header date column.
///
/// Wraps SwiftUI's `DatePicker(.graphical)` style so we get the native
/// month-grid calendar (matching Apple Calendar / Reminders / Photos
/// pickers). Future dates are unbounded — schema design treats forward-
/// dated entries as reminders/todos, so navigating ahead is a feature.
///
/// The sheet auto-dismisses on selection. The host owns the dismiss
/// closure so it can also clear any state it cares about (idempotent —
/// also called when the user drags down to dismiss).
struct DatePickerSheet: View {
    @State private var picked: Date
    let onSelect: (Date) -> Void
    let onDismiss: () -> Void

    init(selection: Date, onSelect: @escaping (Date) -> Void, onDismiss: @escaping () -> Void) {
        self._picked = State(initialValue: selection)
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Date",
                    selection: $picked,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(Color.DS.sage)
                .padding(.horizontal, 8)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .background(Color.DS.bg1)
            .navigationTitle("Pick a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSelect(picked) }
                        .fontWeight(.semibold)
                        .tint(Color.DS.sageDeep)
                }
            }
        }
    }
}

#Preview {
    DatePickerSheet(
        selection: .now,
        onSelect: { _ in },
        onDismiss: { }
    )
}
