import SFSafeSymbols
import SwiftUI

struct EvidenceLoadFailure: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .evidenceFailedTitle),
                systemSymbol: .exclamationmarkIcloud,
            )
        } description: {
            Text(message)
        }
    }
}

#if DEBUG
    #Preview("Load failure") {
        EvidenceListView(
            report: PreviewSupport.loadedYearReportModel(),
            model: PreviewSupport.evidenceListModel(state: .failed("iCloud is unavailable.")),
        )
    }
#endif
