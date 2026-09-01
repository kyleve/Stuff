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

    @Test func staleDeactivationCannotReleaseANewerSessionLease() async {
        let session = ThrowSession.fixture()
        session.isReconcilingDemand = true
        let oldLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        let replacementLease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 2),
        )

        await session.applyExperienceCoordinatorAction(.activate(
            lease: oldLease,
            role: .active,
        ))
        await session.applyExperienceCoordinatorAction(.activate(
            lease: replacementLease,
            role: .active,
        ))
        await session.applyExperienceCoordinatorAction(.deactivate(lease: oldLease))

        #expect(session.airAndSpaceActivation.activeLease == replacementLease)
    }

    @Test func runtimeUpdateWaitsForThePreparedFrameToFinishFadingIn() async {
        let session = ThrowSession.fixture()
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 1),
        )
        _ = session.airAndSpaceActivation.activate(lease)
        session.currentLayerFrame = nil
        session.currentSnapshot = nil
        session.projectionPresentationTransition = .fadingIn(
            targetLease: lease,
            bufferedTargetUpdate: nil,
        )
        let snapshot = AircraftSnapshot(
            source: .adsbLol,
            fetchedAt: session.dateProvider.now(),
            observations: [],
            decodingDiagnostics: .none,
        )
        let update = AirAndSpaceRuntimeUpdate(
            activationLease: lease,
            successfulActivationLease: lease,
            health: .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: 1,
            ),
            flightsFrame: nil,
            snapshot: snapshot,
            activePollingSignature: nil,
        )

        await session.applyAirAndSpaceUpdate(update)

        #expect(session.currentSnapshot == nil)
        let bufferedSnapshot = session.projectionPresentationTransition?
            .bufferedTargetUpdate?.snapshot
        #expect(bufferedSnapshot == snapshot)

        await session.finishProjectionPresentationTransition(to: lease)

        #expect(session.currentSnapshot == snapshot)
        #expect(session.projectionPresentationTransition?.targetLease == nil)
    }

    @Test func projectionAccessibilityUsesTheActiveExperienceCountMeaning() {
        let session = ThrowSession.fixture()
        session.experienceCoordinatorState = ProjectionExperienceCoordinatorState(
            activeExperienceID: .transit,
            requestedExperienceID: nil,
            prewarmingExperienceID: nil,
            isPaused: false,
            dwellEndsAt: nil,
            nextExperienceID: .airAndSpace,
            healthByExperience: [
                .transit: .healthy(
                    lastUpdate: session.dateProvider.now(),
                    visibleContentCount: 7,
                ),
            ],
            manualSelectionFailure: nil,
        )

        #expect(session.projectionAccessibilitySummary.contains("Transit"))
        #expect(session.projectionAccessibilitySummary.contains("7 Vehicles visible"))
        #expect(session.projectionAccessibilitySummary.contains("Aircraft visible") == false)
    }
}
