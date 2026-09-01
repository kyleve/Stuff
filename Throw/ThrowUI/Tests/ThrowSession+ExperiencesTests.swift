import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionExperiencesTests {
    @Test func blackCommitKeepsPreparedIdentityAndRevisionAheadOfBufferedInput() throws {
        let session = ThrowSession.fixture()
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let preparedFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        let bufferedFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 200),
        )
        let output = try projectionTestAirOutput(
            semanticFrame: preparedFrame,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 150),
            revision: 11,
            observerPoint: ProjectionPoint(x: 0.25, y: 0.75),
        )
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 4),
        )
        session.projectionPresentationState = .initial(
            coordinator: projectionTestCoordinator(activeExperienceID: .transit),
            preferredExperienceID: .transit,
            mode: .map,
            generatedAt: Date(timeIntervalSince1970: 50),
        )
        session.preparedProjection = try #require(VisibleProjection.rendered(
            activationLease: lease,
            output: output,
        ))
        session.replacePendingAirAndSpaceFrameForTesting(bufferedFrame)
        let bufferedUpdate = AirAndSpaceRuntimeUpdate(
            activationLease: lease,
            successfulActivationLease: lease,
            health: .healthy(
                lastUpdate: Date(timeIntervalSince1970: 200),
                visibleContentCount: 0,
            ),
            flightsFrame: bufferedFrame.flights,
            snapshot: nil,
            activePollingSignature: nil,
        )
        session.projectionPresentationTransition = .fadingOut(
            targetLease: lease,
            bufferedTargetUpdate: bufferedUpdate,
        )

        let committed = session.commitPreparedProjectionAtBlack(
            to: lease,
            coordinator: projectionTestCoordinator(activeExperienceID: .airAndSpace),
        )

        #expect(committed)
        #expect(session.activeExperienceID == .airAndSpace)
        #expect(session.visibleProjection.activationLease == lease)
        #expect(session.visibleProjection.semanticFrame == .airAndSpace(preparedFrame))
        #expect(session.visibleProjection.request?.revision.rawValue == 11)
        #expect(session.visibleProjection.request?.context.observer == observer)
        #expect(session.projectionFrame.generatedAt == Date(timeIntervalSince1970: 150))
        #expect(session.pendingAirAndSpaceFrame == bufferedFrame)
        #expect(session.projectionPresentationTransition?.bufferedTargetUpdate?.flightsFrame ==
            bufferedFrame.flights)
        #expect(session.preparedProjection == nil)
    }

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
        session.replacePendingAirAndSpaceFrameForTesting(.empty)
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
            semanticPreparationState: .ready,
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
        let coordinator = ProjectionExperienceCoordinatorState(
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
        session.projectionPresentationState = .initial(
            coordinator: coordinator,
            preferredExperienceID: .transit,
            mode: .map,
            generatedAt: session.dateProvider.now(),
        )

        #expect(session.projectionAccessibilitySummary.contains("Transit"))
        #expect(session.projectionAccessibilitySummary.contains("7 Vehicles visible"))
        #expect(session.projectionAccessibilitySummary.contains("Aircraft visible") == false)
    }
}
