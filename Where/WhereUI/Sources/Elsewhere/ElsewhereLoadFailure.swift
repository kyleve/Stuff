import SFSafeSymbols
import SwiftUI

struct ElsewhereLoadFailure<Retry: View>: View {
    let message: String
    @ViewBuilder let retry: () -> Retry

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .commonLoadErrorTitle),
                systemSymbol: .exclamationmarkIcloud,
            )
        } description: {
            Text(message)
        } actions: {
            retry()
        }
    }
}

#if DEBUG
    #Preview("Visited regions") {
        ElsewhereView.snapshotPreviews
    }
#endif
