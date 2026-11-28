import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

struct FlightSaveStatus: View {
    let model: FlightReviewModel

    var body: some View {
        switch model.saveState {
            case .idle, .applied:
                EmptyView()
            case .applying:
                Section { SavingStatusRow(text: String(localized: .manualSavingStatus)) }
            case .refreshed:
                Section {
                    Label(
                        String(localized: .flightReviewRefreshed),
                        systemSymbol: .arrowClockwise,
                    )
                }
            case .pointApplied:
                Section {
                    Label(
                        String(localized: .flightReviewPointUpdated),
                        systemSymbol: .checkmarkCircle,
                    )
                }
            case let .failed(message):
                Section {
                    Label(message, systemSymbol: .exclamationmarkTriangle)
                }
        }
    }
}

#if DEBUG
    #Preview { FlightDayDetailView.snapshotPreviews }
#endif
