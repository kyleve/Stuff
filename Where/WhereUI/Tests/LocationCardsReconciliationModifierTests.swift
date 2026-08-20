import RegionKit
import SwiftUI
import Testing
import UIKit
import WhereCore
@testable import WhereUI

@MainActor
struct LocationCardsReconciliationModifierTests {
    @Test func hostsTheSharedReconciliationSurface() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let presentation = LocationCardsPresentationModel(preferences: preferences, year: 2026)
        let current = [RegionDays(region: .california, days: 10)]
        let controller = UIHostingController(
            rootView: Text("Probe")
                .reconcilesLocationCards(
                    current: current,
                    year: 2026,
                    isVisible: false,
                    presentation: presentation,
                ),
        )

        #expect(controller.view != nil)
        #expect(presentation.feedbackTrigger == 0)
    }

    @Test func waitsForActiveMovementAndPropagatesCancellation() async throws {
        let presentation = LocationCardsPresentationModel(
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
            year: 2026,
        )
        let baseline = [
            RegionDays(region: .california, days: 100),
            RegionDays(region: .newYork, days: 99),
        ]
        let overtake = [
            RegionDays(region: .newYork, days: 101),
            RegionDays(region: .california, days: 100),
        ]
        presentation.updateReconciliationTarget(.init(
            counts: baseline,
            year: 2026,
            isVisible: true,
        ))
        let target = LocationCardsPresentationModel.ReconciliationID(
            counts: overtake,
            year: 2026,
            isVisible: true,
        )
        presentation.updateReconciliationTarget(target)
        let event = try #require(presentation.reconcile(
            target,
            overtakeMotion: .standard,
        ))
        let modifier = LocationCardsReconciliationModifier(
            current: overtake,
            year: 2026,
            isVisible: true,
            presentation: presentation,
            motionOverride: .standard,
        )
        let completingProbe = WaitProbe()
        let cancellingProbe = WaitProbe()
        let completingWaiter = Task {
            completingProbe.didStart = true
            try await modifier.waitForReleasedOvertakeToFinish()
            completingProbe.didFinish = true
        }
        let cancellingWaiter = Task {
            cancellingProbe.didStart = true
            try await modifier.waitForReleasedOvertakeToFinish()
            cancellingProbe.didFinish = true
        }

        for _ in 0 ..< 100
            where !completingProbe.didStart || !cancellingProbe.didStart
        {
            await Task.yield()
        }
        #expect(completingProbe.didStart)
        #expect(cancellingProbe.didStart)
        #expect(!completingProbe.didFinish)

        cancellingWaiter.cancel()
        await #expect(throws: CancellationError.self) {
            try await cancellingWaiter.value
        }
        #expect(!cancellingProbe.didFinish)
        #expect(presentation.overtakeMovement?.sequence == event.sequence)

        presentation.finishOvertakeMovement(sequence: event.sequence)
        try await completingWaiter.value
        #expect(completingProbe.didFinish)
    }

    private final class WaitProbe {
        var didStart = false
        var didFinish = false
    }
}
