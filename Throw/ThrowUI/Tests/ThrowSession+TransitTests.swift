import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionTransitTests {
    @Test func failedRemovalPersistenceRestoresTransitConfigurationAndPlaylist() async throws {
        let preferenceStore = TransitFailingPreferenceStore()
        let session = ThrowSession.fixture(
            preferenceStore: preferenceStore,
            credentialStore: MemoryAircraftCredentialStore(credentials: [:]),
        )
        let dwell = ProjectionDwellDuration.defaultValue
        let configuredTransit = session.transitPreferences.replacingConfiguration(
            .configured(cityID: .newYorkCity),
        )
        let configuredPlaylist = try ProjectionPlaylist(
            entries: [
                ProjectionPlaylistEntry(
                    runnableExperienceID: .airAndSpace,
                    dwellDuration: dwell,
                ),
                ProjectionPlaylistEntry(
                    runnableExperienceID: .transit,
                    dwellDuration: dwell,
                ),
            ],
            automaticRotationEnabled: true,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: [.airAndSpace, .transit],
            catalog: .standard,
        )
        session.replaceTransitPreferencesForTesting(
            configuredTransit,
            playlist: configuredPlaylist,
        )
        let previousTransit = session.transitPreferences
        let previousPlaylist = session.projectionPlaylist

        await session.removeTransit()

        #expect(session.transitPreferences == previousTransit)
        #expect(session.projectionPlaylist == previousPlaylist)
        #expect(session.postLaunchFailures(for: .settings).isEmpty == false)
    }
}

private actor TransitFailingPreferenceStore: ThrowPreferenceStore {
    func load() throws -> ThrowPreferences {
        .defaultValue
    }

    func save(_: ThrowPreferences) throws {
        throw ThrowPreferenceStoreError.invalidPayload
    }
}
