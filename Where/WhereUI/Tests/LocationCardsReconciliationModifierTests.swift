import Observation
import RegionKit
import SwiftUI
import TestHostSupport
import Testing
import UIKit
import WhereCore
@testable import WhereUI

@MainActor
struct LocationCardsReconciliationModifierTests {
    @Test func releasesWithMotionChangedWhileTheGateIsPending() async throws {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let baseline = [
            RegionDays(region: .california, days: 100),
            RegionDays(region: .newYork, days: 99),
        ]
        preferences.setLastSeenLocationDayCounts([
            .california: 100,
            .newYork: 99,
        ], in: 2026)
        let presentation = LocationCardsPresentationModel(
            preferences: preferences,
            year: 2026,
        )
        presentation.updateReconciliationTarget(.init(
            counts: baseline,
            year: 2026,
            isVisible: true,
        ))
        let probe = LiveMotionProbeState(current: baseline)
        let host = UIHostingController(
            rootView: LiveMotionProbe(
                state: probe,
                presentation: presentation,
            ),
        )

        try await show(host) { _ in
            let overtake = [
                RegionDays(region: .newYork, days: 101),
                RegionDays(region: .california, days: 100),
            ]
            let target = LocationCardsPresentationModel.ReconciliationID(
                counts: overtake,
                year: 2026,
                isVisible: true,
            )
            probe.current = overtake
            try await waitUntil { presentation.willOvertake(target) }

            probe.motion = .reducedMotion
            try await waitUntil { presentation.latestOvertake != nil }

            let event = try #require(presentation.latestOvertake)
            #expect(event.motion == .reducedMotion)
            #expect(presentation.overtakeMovement == nil)
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: @MainActor () -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while condition() == false {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw TestHostError("Timed out waiting for the Location-card condition.")
            }
            await Task.yield()
        }
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
            motion: .standard,
        )
        let completingProbe = WaitProbe()
        let cancellingProbe = WaitProbe()
        let completingWaiter = Task {
            completingProbe.markStarted()
            try await modifier.waitForReleasedOvertakeToFinish()
            completingProbe.didFinish = true
        }
        let cancellingWaiter = Task {
            cancellingProbe.markStarted()
            try await modifier.waitForReleasedOvertakeToFinish()
            cancellingProbe.didFinish = true
        }

        await completingProbe.waitUntilStarted()
        await cancellingProbe.waitUntilStarted()
        #expect(completingProbe.didFinish == false)

        cancellingWaiter.cancel()
        await #expect(throws: CancellationError.self) {
            try await cancellingWaiter.value
        }
        #expect(cancellingProbe.didFinish == false)
        #expect(presentation.overtakeMovement?.sequence == event.sequence)

        presentation.finishOvertakeMovement(sequence: event.sequence)
        try await completingWaiter.value
        #expect(completingProbe.didFinish)
    }

    @MainActor
    @Observable
    final class LiveMotionProbeState {
        var current: [RegionDays]
        var motion = WhereStylesheet.LocationCardStackStyle.OvertakeMotion.standard

        init(current: [RegionDays]) {
            self.current = current
        }
    }

    private struct LiveMotionProbe: View {
        let state: LiveMotionProbeState
        let presentation: LocationCardsPresentationModel

        var body: some View {
            Color.clear
                .reconcilesLocationCards(
                    current: state.current,
                    year: 2026,
                    isVisible: true,
                    presentation: presentation,
                    motion: state.motion,
                )
        }
    }

    @MainActor
    private final class WaitProbe {
        var didFinish = false
        private var didStart = false
        private var startContinuation: CheckedContinuation<Void, Never>?

        func markStarted() {
            guard didStart == false else { return }
            didStart = true
            startContinuation?.resume()
            startContinuation = nil
        }

        func waitUntilStarted() async {
            guard didStart == false else { return }
            await withCheckedContinuation { continuation in
                if didStart {
                    continuation.resume()
                } else {
                    startContinuation = continuation
                }
            }
        }
    }
}
