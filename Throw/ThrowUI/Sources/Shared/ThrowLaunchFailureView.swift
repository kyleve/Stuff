import SFSafeSymbols
import SwiftUI

struct ThrowLaunchFailureView: View {
    let failure: ThrowSessionLaunchFailure
    let retry: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .launchFailureTitle),
                systemSymbol: .exclamationmarkTriangleFill,
            )
            .foregroundStyle(.secondary)
        } description: {
            Text(failure.userMessage)
        } actions: {
            Button(
                String(localized: .commonRetry),
                systemSymbol: .arrowCounterclockwise,
                action: retry,
            )
        }
    }
}
