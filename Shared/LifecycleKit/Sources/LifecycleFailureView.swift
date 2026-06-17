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
        // TODO: Localize LifecycleKit's user-facing strings ("Couldn't finish
        // launching", "Try Again", and any future ones). As string literals they
        // resolve against the main bundle, not this package; proper localization
        // needs a string catalog in this target read via `bundle: .module`.
        // Tracked as a LifecycleKit follow-up (PR #25).
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
        LifecycleFailureView(
            failure: LifecycleFailure(
                stepID: "open-store",
                error: URLError(.notConnectedToInternet),
            ),
        ) {}
    }
#endif
