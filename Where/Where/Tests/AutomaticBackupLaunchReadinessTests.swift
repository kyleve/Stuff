import Testing
@testable import Where

@MainActor
struct AutomaticBackupLaunchReadinessTests {
    @Test func onboardingOrFailedLaunchDoesNotParkTheBackgroundHandler() async throws {
        #expect(try await AutomaticBackupLaunchReadiness.wait { .unavailable } == false)
        #expect(try await AutomaticBackupLaunchReadiness.wait { .ready })
    }

    @Test func expirationStopsAWaitForLaunch() async {
        let operation = Task { try await AutomaticBackupLaunchReadiness.wait { .pending } }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
    }
}
