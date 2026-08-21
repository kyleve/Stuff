import RegionKit
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct LocationCardRankingStackTests {
    @Test func holdsPendingMovementUntilTheTriggeredKeyframesRun() {
        let presentation = LocationCardsPresentationModel(
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
            year: 2026,
        )
        let stack = LocationCardRankingStack(
            spacing: 12,
            presentation: presentation,
            motion: .standard,
        ) {
            EmptyView()
        }
        let pending = LocationCardsPresentationModel.OvertakeMovement(
            sequence: 1,
            fromOrder: [.california, .newYork],
            toOrder: [.newYork, .california],
            phase: .pending,
        )
        let released = LocationCardsPresentationModel.OvertakeMovement(
            sequence: 1,
            fromOrder: [.california, .newYork],
            toOrder: [.newYork, .california],
            phase: .released(.standard),
        )
        let reduced = LocationCardsPresentationModel.OvertakeMovement(
            sequence: 1,
            fromOrder: [.california, .newYork],
            toOrder: [.newYork, .california],
            phase: .released(.reducedMotion),
        )

        #expect(stack.resolvedProgress(
            keyframeProgress: 0.4,
            movement: nil,
        ) == 1)
        #expect(stack.resolvedProgress(
            keyframeProgress: 0.4,
            movement: pending,
        ) == 0)
        #expect(stack.resolvedProgress(
            keyframeProgress: 0.4,
            movement: released,
        ) == 0.4)
        #expect(stack.resolvedProgress(
            keyframeProgress: 0.4,
            movement: reduced,
        ) == 0)
    }
}
