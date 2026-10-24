#if DEBUG
    import ThrowCore

    /// A deterministic launch suspension for app-shell lifecycle tests.
    @MainActor
    @_spi(Testing) public final class ThrowSessionLaunchTestHarness {
        public let session: ThrowSession

        private let preferenceStore: HarnessPreferenceStore

        private init(session: ThrowSession, preferenceStore: HarnessPreferenceStore) {
            self.session = session
            self.preferenceStore = preferenceStore
        }

        public static func configuredSuspended() -> ThrowSessionLaunchTestHarness {
            do {
                let preferences = try ThrowSession.fixture().makePreferences()
                let preferenceStore = HarnessPreferenceStore(preferences: preferences)
                let session = ThrowSession.launchFixture(
                    setupCompleted: true,
                    preferenceStore: preferenceStore,
                    credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
                )
                return ThrowSessionLaunchTestHarness(
                    session: session,
                    preferenceStore: preferenceStore,
                )
            } catch {
                preconditionFailure("The launch test harness must be valid: \(error)")
            }
        }

        public func waitForLoadToStart() async {
            await preferenceStore.waitForLoadToStart()
        }

        public func resumeLoad() async {
            await preferenceStore.resumeLoad()
        }

        public func loadCallCount() async -> Int {
            await preferenceStore.loadCallCount
        }
    }

    private actor HarnessPreferenceStore: ThrowPreferenceStore {
        private let preferences: ThrowPreferences
        private var loadContinuation: CheckedContinuation<Void, Never>?
        private var loadStartedContinuation: CheckedContinuation<Void, Never>?
        private(set) var loadCallCount = 0

        init(preferences: ThrowPreferences) {
            self.preferences = preferences
        }

        func load() async -> ThrowPreferences {
            loadCallCount += 1
            loadStartedContinuation?.resume()
            loadStartedContinuation = nil
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
            }
            return preferences
        }

        func save(_: ThrowPreferences) {}

        func waitForLoadToStart() async {
            guard loadCallCount == 0 else { return }
            await withCheckedContinuation { continuation in
                loadStartedContinuation = continuation
            }
        }

        func resumeLoad() {
            loadContinuation?.resume()
            loadContinuation = nil
        }
    }
#endif
