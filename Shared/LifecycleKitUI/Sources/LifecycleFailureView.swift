import LifecycleKit
import SwiftUI

/// The UI shown when a launch step throws. Describes the failure. Terminal by
/// design — there is no retry, so the recovery is relaunching the app.
public struct LifecycleFailureView: View {
    private let failure: LifecycleFailure

    public init(failure: LifecycleFailure) {
        self.failure = failure
    }

    public var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "failure.launch.title", bundle: .module),
                systemImage: "exclamationmark.triangle",
            )
        } description: {
            Text(failure.error.localizedDescription)
        }
    }
}

#if DEBUG
    #Preview {
        LifecycleFailureView(
            failure: LifecycleFailure(
                stepID: "open-store",
                error: URLError(.notConnectedToInternet),
            ),
        )
    }
#endif
