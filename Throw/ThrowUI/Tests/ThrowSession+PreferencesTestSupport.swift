import ThrowCore

@MainActor
final class PreferenceFlushCompletionProbe {
    private(set) var isComplete = false

    func complete() {
        isComplete = true
    }
}

actor PreferenceMutationGate {
    private var suspensionContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            precondition(
                suspensionContinuation == nil,
                "Only one preference mutation can wait at the gate",
            )
            suspensionContinuation = continuation
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilSuspended() async {
        guard suspensionContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        suspensionContinuation?.resume()
        suspensionContinuation = nil
    }
}

actor SuspendingAircraftCredentialStore: AircraftCredentialStore {
    private var credentials: [AircraftCredentialID: AircraftCredential]
    private var saveStarted = false
    private var saveStartedContinuation: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?

    init(credentials: [AircraftCredentialID: AircraftCredential]) {
        self.credentials = credentials
    }

    func state(for id: AircraftCredentialID) -> CredentialState {
        guard let credential = credentials[id] else { return .missing }
        return .saved(lastFour: credential.lastFour)
    }

    func credential(for id: AircraftCredentialID) -> AircraftCredential? {
        credentials[id]
    }

    func save(_ credential: AircraftCredential, for id: AircraftCredentialID) async {
        saveStarted = true
        saveStartedContinuation?.resume()
        saveStartedContinuation = nil
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
        }
        credentials[id] = credential
    }

    func delete(_ id: AircraftCredentialID) {
        credentials[id] = nil
    }

    func waitForSaveToStart() async {
        guard saveStarted == false else { return }
        await withCheckedContinuation { continuation in
            saveStartedContinuation = continuation
        }
    }

    func resumeSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

actor SuspendingThrowPreferenceStore: ThrowPreferenceStore {
    private var preferences: ThrowPreferences
    private var savedPreferences: [ThrowPreferences] = []
    private var saveCallCount = 0
    private var firstSaveStarted = false
    private var firstSaveStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?

    init(initialValue: ThrowPreferences = .defaultValue) {
        preferences = initialValue
    }

    func load() -> ThrowPreferences {
        preferences
    }

    func save(_ preferences: ThrowPreferences) async {
        saveCallCount += 1
        if firstSaveStarted == false {
            firstSaveStarted = true
            firstSaveStartedContinuation?.resume()
            firstSaveStartedContinuation = nil
            await withCheckedContinuation { continuation in
                firstSaveContinuation = continuation
            }
        }
        self.preferences = preferences
        savedPreferences.append(preferences)
    }

    func waitForFirstSaveToStart() async {
        guard firstSaveStarted == false else { return }
        await withCheckedContinuation { continuation in
            firstSaveStartedContinuation = continuation
        }
    }

    func resumeFirstSave() {
        firstSaveContinuation?.resume()
        firstSaveContinuation = nil
    }

    func savedIntensityPercents() -> [Double] {
        savedPreferences.map(\.intensityPercent)
    }

    func savedMapRadii() -> [Double] {
        savedPreferences.map(\.mapViewport.radius.value)
    }

    func startedSaveCount() -> Int {
        saveCallCount
    }
}

enum SwitchableThrowPreferenceStoreFailure: Error {
    case save
}

actor SwitchableThrowPreferenceStore: ThrowPreferenceStore {
    private var preferences: ThrowPreferences
    private var failsSave: Bool

    init(
        initialValue: ThrowPreferences = .defaultValue,
        failsSave: Bool,
    ) {
        preferences = initialValue
        self.failsSave = failsSave
    }

    func load() -> ThrowPreferences {
        preferences
    }

    func save(_ preferences: ThrowPreferences) throws {
        guard failsSave == false else {
            throw SwitchableThrowPreferenceStoreFailure.save
        }
        self.preferences = preferences
    }

    func setFailsSave(_ failsSave: Bool) {
        self.failsSave = failsSave
    }
}
