import SwiftUI

/// `WhereDatePicker` renders a deterministic stand-in under snapshot capture
/// (the live compact capsule's date format depends on the real-world date,
/// so no reference image containing it is stable across days) — the capture
/// handling stays inside the wrapper, not here.
struct ManualDayDatePickers: View {
    @Bindable var add: ManualDayView.AddFields

    var body: some View {
        switch add.dateSpan {
            case .singleDay:
                WhereDatePicker(
                    String(localized: .manualDay),
                    selection: $add.startDate,
                    latest: Date(),
                    displayedComponents: .date,
                )
            case .range:
                WhereDatePicker(
                    String(localized: .manualFrom),
                    selection: $add.startDate,
                    latest: Date(),
                    displayedComponents: .date,
                )
                WhereDatePicker(
                    String(localized: .manualThrough),
                    selection: $add.endDate,
                    earliest: add.startDate,
                    latest: Date(),
                    displayedComponents: .date,
                )
        }
    }
}

#if DEBUG
    #Preview("Add manual day") {
        NavigationStack {
            ManualDayView(
                report: PreviewSupport.loadedYearReportModel(),
                mode: .add(prefill: nil),
                showsCancelButton: true,
            )
        }
    }
#endif
