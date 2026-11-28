import SwiftUI

struct ElsewhereRetryButton: View {
    let retry: () -> Void

    var body: some View {
        Button(String(localized: .commonRetry)) { retry() }
            .buttonStyle(.bordered)
    }
}

#if DEBUG
    #Preview("Visited regions") {
        ElsewhereView.snapshotPreviews
    }
#endif
