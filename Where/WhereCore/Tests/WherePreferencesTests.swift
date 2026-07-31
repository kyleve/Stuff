import Testing
@testable import WhereCore

struct WherePreferencesTests {
    @Test func newInstallationUsesTheSuppliedRecordingDefault() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())

        #expect(preferences.wantsTracking(defaultForNewInstallation: false) == false)
        #expect(preferences.wantsTracking(defaultForNewInstallation: true))
    }

    @Test func onboardedInstallationWithoutAnExplicitValueKeepsLegacyRecordingOn() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.hasOnboarded = true

        #expect(preferences.wantsTracking(defaultForNewInstallation: false))
    }

    @Test func explicitRecordingIntentWinsOverPlatformAndMigrationDefaults() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.hasOnboarded = true
        preferences.wantsTracking = false

        #expect(preferences.wantsTracking(defaultForNewInstallation: true) == false)
        #expect(preferences.wantsTracking(defaultForNewInstallation: false) == false)
    }
}
