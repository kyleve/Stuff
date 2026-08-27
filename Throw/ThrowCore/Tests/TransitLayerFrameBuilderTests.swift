import Testing
@testable import ThrowCore

struct TransitLayerFrameBuilderTests {
    @Test func networkDeduplicatesSharedRouteShapes() throws {
        let frame = try TransitLayerFrameBuilder().networkFrame(
            schedule: TransitFixture.schedule(),
        )
        #expect(frame.lines.count == 1)
        let style = frame.lines[0].style
        #expect(style.routeID.rawValue == "A")
    }

    @Test func routeOnlyUsesColoredTrainDotWithoutStationMarks() throws {
        var estimator = TransitPositionEstimator()
        let estimates = try estimator.estimates(
            snapshots: [TransitFixture.snapshot()],
            schedule: TransitFixture.schedule(),
            at: ThrowCoreFixture.date,
        )
        let frame = TransitLayerFrameBuilder().vehiclesFrame(
            estimates: estimates,
            labelMode: .routeOnly,
            fetchedAt: ThrowCoreFixture.date,
            availability: .current,
        )
        #expect(frame.marks.count == 1)
        let mark = try #require(frame.marks.first)
        #expect(mark.label == nil)
        #expect(mark.transitMotion != nil)
        guard case .vehicle = mark.element else {
            Issue.record("Expected a typed transit vehicle mark")
            return
        }
    }
}
