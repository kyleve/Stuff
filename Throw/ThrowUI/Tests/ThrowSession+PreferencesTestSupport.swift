import ThrowCore

actor SuspendingThrowPreferenceStore: ThrowPreferenceStore {
    private var preferences: ThrowPreferences
    private var savedPreferences: [ThrowPreferences] = []
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
}
