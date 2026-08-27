import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionExperiencesTests {
    @Test func oneConfiguredViewKeepsAutomaticRotationDormant() {
        let session = ThrowSession.fixture()

        session.setAutomaticExperienceRotationEnabled(true)

        #expect(session.projectionPlaylist.automaticRotationEnabled)
        #expect(session.projectionPlaylist.rotatesAutomatically == false)
        #expect(session.experienceRotationHasControls == false)
    }

    @Test func dwellChangesStayWithinTheValidatedPlaylist() {
        let session = ThrowSession.fixture()

        session.setExperienceDwellDuration(seconds: 300, for: .airAndSpace)

        #expect(session.projectionPlaylist.entry(for: .airAndSpace)?.dwellDuration.seconds == 300)
    }

    @Test func rapidPlaylistChangesConvergeOnTheNewestCoordinatorValue() async {
        let session = ThrowSession.fixture()

        session.setExperienceDwellDuration(seconds: 300, for: .airAndSpace)
        let olderTask = session.playlistConfigurationTask
        session.setExperienceDwellDuration(seconds: 600, for: .airAndSpace)
        let latestTask = session.playlistConfigurationTask
        await latestTask?.value
        await olderTask?.value

        let coordinatorPlaylist = await session.experienceCoordinator.currentPlaylist()
        #expect(coordinatorPlaylist.entry(for: .airAndSpace)?.dwellDuration.seconds == 600)
        #expect(session.projectionPlaylist == coordinatorPlaylist)
    }

    @Test func projectionAccessibilityUsesTheActiveExperienceCountMeaning() {
        let session = ThrowSession.fixture()
        session.activeExperienceID = .transit
        session.experienceHealth[.transit] = .healthy(
            lastUpdate: session.dateProvider.now(),
            visibleContentCount: 7,
        )

        #expect(session.projectionAccessibilitySummary.contains("Transit"))
        #expect(session.projectionAccessibilitySummary.contains("7 Vehicles visible"))
        #expect(session.projectionAccessibilitySummary.contains("Aircraft visible") == false)
    }
}
