import SwiftUI

struct ManualDaySavingSection: View {
    let isSaving: Bool

    var body: some View {
        if isSaving {
            Section {
                SavingStatusRow(text: String(localized: .manualSavingStatus))
            }
        }
    }
}

#if DEBUG
    #Preview("Manual entry") {
        ManualDayView.snapshotPreviews
    }
#endif
