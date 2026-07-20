import LifecycleKit
import SwiftUI

/// The UI shown when a launch step throws. Describes the failure and offers a
/// retry that resumes the runner from the step that failed.
public struct LifecycleFailureView: View {
    private let failure: LifecycleFailure
    private let retry: () -> Void

    public init(failure: LifecycleFailure, retry: @escaping () -> Void) {
        self.failure = failure
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "failure.launch.title", bundle: .module),
                systemImage: "exclamationmark.triangle",
            )
        } description: {
            Text(failure.error.localizedDescription)
        } actions: {
            Button(String(localized: "failure.launch.retry", bundle: .module), action: retry)
                .buttonStyle(.borderedProminent)
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
        ) {}
    }
#endif
