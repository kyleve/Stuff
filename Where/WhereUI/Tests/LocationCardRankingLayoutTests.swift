import CoreGraphics
import RegionKit
import Testing
@testable import WhereUI

struct LocationCardRankingLayoutTests {
    private let california = LocationCardRankingLayout.MeasuredChild(
        region: .california,
        size: CGSize(width: 300, height: 100),
    )
    private let newYork = LocationCardRankingLayout.MeasuredChild(
        region: .newYork,
        size: CGSize(width: 280, height: 140),
    )

    @Test func interpolatesUnequalCardsIntoDestinationOrder() {
        let origins = LocationCardRankingLayout.interpolatedYOrigins(
            children: [newYork, california],
            spacing: 10,
            fromOrder: [.california, .newYork],
            toOrder: [.newYork, .california],
            progress: 0.5,
        )

        // Results stay aligned with the semantic child order: New York, then California.
        #expect(origins == [55, 75])
    }

    @Test func preservesExactEndpointsInBothDirections() {
        let forwardStart = LocationCardRankingLayout.interpolatedYOrigins(
            children: [newYork, california],
            spacing: 10,
            fromOrder: [.california, .newYork],
            toOrder: [.newYork, .california],
            progress: 0,
        )
        let forwardEnd = LocationCardRankingLayout.interpolatedYOrigins(
            children: [newYork, california],
            spacing: 10,
            fromOrder: [.california, .newYork],
            toOrder: [.newYork, .california],
            progress: 1,
        )
        let reverseStart = LocationCardRankingLayout.interpolatedYOrigins(
            children: [california, newYork],
            spacing: 10,
            fromOrder: [.newYork, .california],
            toOrder: [.california, .newYork],
            progress: 0,
        )
        let reverseEnd = LocationCardRankingLayout.interpolatedYOrigins(
            children: [california, newYork],
            spacing: 10,
            fromOrder: [.newYork, .california],
            toOrder: [.california, .newYork],
            progress: 1,
        )

        #expect(forwardStart == [110, 0])
        #expect(forwardEnd == [0, 150])
        #expect(reverseStart == [150, 0])
        #expect(reverseEnd == [0, 110])
    }

    @Test func appendsUnlistedChildrenInSemanticOrder() {
        let canada = LocationCardRankingLayout.MeasuredChild(
            region: .canada,
            size: CGSize(width: 260, height: 80),
        )
        let origins = LocationCardRankingLayout.interpolatedYOrigins(
            children: [newYork, california, canada],
            spacing: 10,
            fromOrder: [.california],
            toOrder: [.newYork],
            progress: 1,
        )

        #expect(origins == [0, 150, 260])
    }

    @Test func animatableDataChangesOnlyProgress() {
        var layout = LocationCardRankingLayout(
            spacing: 10,
            fromOrder: [.california, .newYork],
            toOrder: [.newYork, .california],
            progress: 0,
        )

        layout.animatableData = 0.5

        #expect(layout.progress == 0.5)
        #expect(layout.spacing == 10)
        #expect(layout.fromOrder == [.california, .newYork])
        #expect(layout.toOrder == [.newYork, .california])
    }
}
