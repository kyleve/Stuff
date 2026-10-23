#if DEBUG
    import Foundation
    import PeriscopeCore
    import WhereCore

    /// Builds a fresh, empty sandbox on every onboarding attempt, using demo's side-effect-free
    /// services.
    @MainActor
    struct DeveloperOnboardingAssembler: WhereScopeAssembling {
        let installationContextStore: any InstallationRecordingContextStoring
        let now: @Sendable () -> Date

        func prepareLocation() {}

        func discoverRecordingDevices() async throws -> [RecordingDevice] {
            []
        }

        func makeServices() async throws -> WhereServices {
            try await WhereScope.makeInMemoryServices(
                installationContext: installationContextStore.resolve(),
                now: now,
            )
        }

        func makeLogStore() async throws -> PeriscopeStore? {
            nil
        }
    }
#endif
