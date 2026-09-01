import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct ProjectionFrameWorkerOutputTests {
    @Test func erasedBoundaryRejectsAFrameFromAnotherView() throws {
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let validOutput = try projectionTestAirOutput(
            semanticFrame: .empty,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 100),
            revision: 1,
            observerPoint: nil,
        )

        let invalidOutput = ProjectionFrameWorkerOutput(
            request: validOutput.request,
            render: .init(
                frame: .emptyTransit(generatedAt: Date(timeIntervalSince1970: 100)),
                geographyHealth: .idle,
                effects: [:],
                observerPoint: nil,
            ),
        )

        #expect(invalidOutput == nil)
    }

    @Test func validatedOutputCannotReplaceItsFrameWithAnotherView() throws {
        let observer = try projectionTestObserver(latitude: 37, longitude: -122)
        let output = try projectionTestAirOutput(
            semanticFrame: .empty,
            observer: observer,
            generatedAt: Date(timeIntervalSince1970: 100),
            revision: 1,
            observerPoint: nil,
        )
        guard case let .airAndSpace(airAndSpace) = output else {
            Issue.record("The fixture must produce Air & Space output")
            return
        }

        let replacement = airAndSpace.replacingFrame(
            .emptyTransit(generatedAt: Date(timeIntervalSince1970: 200)),
        )

        #expect(replacement == nil)
    }
}
