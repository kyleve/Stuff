import SFSafeSymbols
import SwiftUI

struct PlanningLoadFailureSection: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Section {
            Label(
                message,
                systemSymbol: .exclamationmarkTriangleFill,
            )
            .foregroundStyle(.red)
            Button(String(localized: .commonRetry)) {
                retry()
            }
        }
    }
}

#if DEBUG
    #Preview("Itinerary") {
        PlannedStaysView(report: PreviewSupport.itineraryYearReportModel())
    }
#endif
