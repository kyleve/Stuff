import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct VisibleProjectionTests {
    @Test func renderedProjectionRetainsOneCompleteTypedPublication() throws {
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let semanticFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        let generatedAt = Date(timeIntervalSince1970: 200)
        let observerPoint = ProjectionPoint(x: 0.4, y: 0.6)
        let output = try projectionTestAirOutput(
            semanticFrame: semanticFrame,
            observer: observer,
            generatedAt: generatedAt,
            revision: 3,
            observerPoint: observerPoint,
        )
        let lease = ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: 7),
        )

        let visible = try #require(VisibleProjection.rendered(
            activationLease: lease,
            output: output,
        ))

        #expect(visible.experienceID == .airAndSpace)
        #expect(visible.activationLease == lease)
        #expect(visible.semanticFrame == .airAndSpace(semanticFrame))
        #expect(visible.frame == output.frame)
        #expect(visible.observerPoint == observerPoint)
        #expect(visible.request?.context.observer == observer)
        #expect(visible.request?.revision.rawValue == 3)

        let cleared = visible.cleared(mode: .map, generatedAt: generatedAt)
        #expect(cleared.activationLease == lease)
        #expect(cleared.request == nil)
    }

    @Test func activationLeaseFromAnotherViewCannotWrapOutput() throws {
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let output = try projectionTestAirOutput(
            semanticFrame: .empty,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 100),
            revision: 1,
            observerPoint: nil,
        )
        let transitLease = ProjectionActivationLease(
            experienceID: .testing(.transit),
            generation: .init(rawValue: 1),
        )

        #expect(VisibleProjection.rendered(
            activationLease: transitLease,
            output: output,
        ) == nil)
    }

    @Test func leaseFreeWorkerOutputUsesTheDebugFixtureCase() throws {
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let output = try projectionTestAirOutput(
            semanticFrame: .empty,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 100),
            revision: 1,
            observerPoint: nil,
        )

        let visible = VisibleProjection.fixture(output: output)

        #expect(visible.activationLease == nil)
        #expect(visible.request == nil)
        #expect(visible.frame == output.frame)
    }
}
