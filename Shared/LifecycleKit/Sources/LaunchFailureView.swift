import SwiftUI

/// The UI shown when a launch step throws. Describes the failure and offers a
/// retry that resumes the launcher from the step that failed.
public struct LaunchFailureView: View {
    private let failure: LaunchFailure
    private let retry: () -> Void

    public init(failure: LaunchFailure, retry: @escaping () -> Void) {
        self.failure = failure
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label("Couldn't finish launching", systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.error.localizedDescription)
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

#if DEBUG
    #Preview {
        LaunchFailureView(
            failure: LaunchFailure(
                stepID: "open-store",
                error: URLError(.notConnectedToInternet),
            ),
        ) {}
    }
#endif
