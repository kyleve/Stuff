import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct ProjectionFrameRequestTests {
    @Test func typedRequestKeepsSemanticRevisionAndGeometryContextTogether() throws {
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let semanticFrame = projectionTestAirFrame(
            observedAt: Date(timeIntervalSince1970: 100),
        )
        let output = try projectionTestAirOutput(
            semanticFrame: semanticFrame,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 200),
            revision: 3,
            observerPoint: ProjectionPoint(x: 0.4, y: 0.6),
        )

        guard case let .airAndSpace(request) = output.request else {
            Issue.record("An Air & Space request must keep its typed case")
            return
        }
        #expect(request.input.frame == semanticFrame)
        #expect(request.context.observer == observer)
        #expect(request.revision.rawValue == 3)
        #expect(output.request.flightsFrame?.observedAt == semanticFrame.flights?.observedAt)
    }
}
