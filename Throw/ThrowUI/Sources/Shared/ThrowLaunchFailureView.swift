import SFSafeSymbols
import SwiftUI

struct ThrowLaunchFailureView: View {
    let failure: ThrowSessionLaunchFailure
    let retry: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .settingsFailureTitle),
                systemSymbol: .exclamationmarkTriangleFill,
            )
            .foregroundStyle(.secondary)
        } description: {
            Text(verbatim: failure.detail)
        } actions: {
            Button(
                String(localized: .commonRetry),
                systemSymbol: .arrowCounterclockwise,
                action: retry,
            )
        }
    }
}
