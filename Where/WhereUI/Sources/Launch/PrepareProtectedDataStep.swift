import LifecycleKit

/// App-owned first-unlock barrier shared by headless and UI-driven launches.
/// Like onboarding, waiting on the user is not a measured work budget.
struct PrepareProtectedDataStep: LifecycleStep {
    let prepare: @MainActor () async throws -> Void
    let id = LaunchStepID.protectedData

    func run(_: Void, _: LifecycleStepContext) async throws {
        try await prepare()
        try Task.checkCancellation()
    }
}
