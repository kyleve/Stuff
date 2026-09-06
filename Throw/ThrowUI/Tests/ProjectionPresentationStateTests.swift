import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct ProjectionPresentationStateTests {
    @Test func activeCoordinatorRejectsVisibleProjectionFromAnotherView() throws {
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let transitOutput = try projectionTestTransitOutput(
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 100),
            revision: 1,
        )
        let transit = try #require(VisibleProjection.rendered(
            activationLease: ProjectionActivationLease(
                experienceID: .testing(.transit),
                generation: .init(rawValue: 1),
            ),
            output: transitOutput,
        ))

        let state = ProjectionPresentationState.committing(
            coordinator: projectionTestCoordinator(activeExperienceID: .airAndSpace),
            visible: transit,
        )

        #expect(state == nil)
    }

    @Test func coordinatorIdentityCannotMoveAheadOfVisibleProjection() {
        let state = ProjectionPresentationState.initial(
            coordinator: projectionTestCoordinator(activeExperienceID: .airAndSpace),
            preferredExperienceID: .airAndSpace,
            mode: .map,
            generatedAt: Date(timeIntervalSince1970: 100),
        )

        let replacement = state.updatingCoordinator(
            projectionTestCoordinator(activeExperienceID: .transit),
        )

        #expect(replacement == nil)
    }
}
