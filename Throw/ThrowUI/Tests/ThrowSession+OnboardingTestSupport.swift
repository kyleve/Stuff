import ThrowCore

actor OnboardingRacePreferenceStore: ThrowPreferenceStore {
    private var preferences: ThrowPreferences
    private var savedPreferences: [ThrowPreferences] = []
    private var saveCount = 0
    private var secondSaveStartedContinuation: CheckedContinuation<Void, Never>?
    private var secondSaveContinuation: CheckedContinuation<Void, Never>?

    init(initialValue: ThrowPreferences = .defaultValue) {
        preferences = initialValue
    }

    func load() -> ThrowPreferences {
        preferences
    }

    func save(_ preferences: ThrowPreferences) async {
        saveCount += 1
        if saveCount == 2 {
            secondSaveStartedContinuation?.resume()
            secondSaveStartedContinuation = nil
            await withCheckedContinuation { continuation in
                secondSaveContinuation = continuation
            }
        }
        self.preferences = preferences
        savedPreferences.append(preferences)
    }

    func waitForSecondSaveToStart() async {
        guard saveCount < 2 else { return }
        await withCheckedContinuation { continuation in
            secondSaveStartedContinuation = continuation
        }
    }

    func resumeSecondSave() {
        secondSaveContinuation?.resume()
        secondSaveContinuation = nil
    }

    func persistedPreferences() -> ThrowPreferences {
        preferences
    }

    func savedIntensityPercents() -> [Double] {
        savedPreferences.map(\.intensityPercent)
    }
}
