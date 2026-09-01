import ThrowCore

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
