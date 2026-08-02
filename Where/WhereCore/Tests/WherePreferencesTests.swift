import Testing
@testable import WhereCore

struct WherePreferencesTests {
    @Test func recordingChoiceConfirmationIsPersistedAndReset() {
        let store = InMemoryKeyValueStore()
        let preferences = WherePreferences(store: store)
        #expect(preferences.hasConfirmedRecordingChoice == false)

        preferences.hasConfirmedRecordingChoice = true
        let relaunched = WherePreferences(store: store)
        #expect(relaunched.hasConfirmedRecordingChoice)

        relaunched.reset()
        #expect(relaunched.hasConfirmedRecordingChoice == false)
    }
}
