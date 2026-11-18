import Foundation
@_spi(Testing) import SnapshotKitTesting
import Testing
import UIKit

@MainActor
struct SnapshotSettleTraceTests {
    @Test func disabledTimingDoesNotCreateTraceIdentityOrCalls() {
        let timing = SnapshotCaptureTiming(identifier: "disabled", isEnabled: false)
        var sampledClock = false
        func sampleClock() -> ContinuousClock.Instant {
            sampledClock = true
            return .now
        }
        #expect(timing.makeSettleTrace(
            reason: .content,
            mechanism: .pixel,
            start: sampleClock(),
            minimumDuration: 0.25,
            maximumDuration: 2.5,
        ) == nil)
        #expect(sampledClock == false)
        #expect(timing.line() == nil)
    }

    @Test func repeatedLabelsKeepDistinctOwnersAndContinuousCallOrdinals() throws {
        let first = SnapshotCaptureTiming(identifier: "same-label", isEnabled: true)
        let second = SnapshotCaptureTiming(identifier: "same-label", isEnabled: true)
        func row(_ owner: SnapshotCaptureTiming, reason: SnapshotSettleReason) throws -> TraceLine {
            let trace = try #require(owner.makeSettleTrace(
                reason: reason,
                mechanism: .pixel,
                start: .now,
                minimumDuration: 0.25,
                maximumDuration: 2.5,
            ))
            let text = try #require(trace.line(outcome: .timedOut(budget: 2.5)))
            return try JSONDecoder().decode(TraceLine.self, from: Data(text.utf8))
        }
        let failed = try row(first, reason: .measurement)
        let retried = try row(first, reason: .content)
        let duplicateLabel = try row(second, reason: .content)
        #expect(failed.version == 1)
        #expect(failed.captureID == retried.captureID)
        #expect(failed.captureID != duplicateLabel.captureID)
        let ordinals: [Int] = [failed.ordinal, retried.ordinal, duplicateLabel.ordinal]
        #expect(ordinals == [1, 2, 1])
        #expect(failed.reason == "measurement")
        #expect(failed.outcome == "timedOut")
        let summary = try captureLine(first)
        #expect(summary.captureID == failed.captureID)
        #expect(summary.settleCalls == 2)
    }

    @Test(arguments: [false, true])
    func tracingPreservesStaticAndChangingOutcomes(enabled: Bool) async throws {
        let timing = SnapshotCaptureTiming(identifier: "outcomes", isEnabled: enabled)
        let staticView = ScriptedSettleView { context, rect, _ in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(rect)
        }
        let stable = await settleContent(
            staticView,
            named: "static",
            minDuration: 0,
            maxDuration: 0.15,
            timing: timing,
            reason: .measurement,
        )
        #expect(stable == .settled)
        let changing = ScriptedSettleView { context, rect, pass in
            context.setFillColor((pass.isMultiple(of: 2) ? UIColor.red : UIColor.blue).cgColor)
            context.fill(rect)
        }
        let moving = await settleContent(
            changing,
            named: "moving",
            minDuration: 0,
            maxDuration: 0.15,
            timing: timing,
            reason: .content,
        )
        #expect(moving == .timedOut(budget: 0.15))
        if enabled {
            let summary = try captureLine(timing)
            #expect(summary.settleCalls == 2)
            #expect(summary.settlePasses == staticView.sampleCount + changing.sampleCount)
        }
    }

    @Test func cancellationRetainsAnUnfinishedCallWithoutInventingPasses() async throws {
        let timing = SnapshotCaptureTiming(identifier: "cancelled", isEnabled: true)
        let view = ScriptedSettleView { context, rect, _ in context.fill(rect) }
        let task = Task { await settleContent(view, named: "cancelled", timing: timing) }
        task.cancel()
        #expect(await task.value == .cancelled)
        let summary = try captureLine(timing)
        #expect(summary.settleCalls == 1)
        #expect(summary.settlePasses == 0)
        #expect(view.sampleCount == 0)
    }

    private struct TraceLine: Decodable {
        let version: Int
        let captureID: UUID
        let ordinal: Int
        let reason: String
        let outcome: String
    }

    private struct CaptureLine: Decodable {
        let captureID: UUID
        let settleCalls: Int
        let settlePasses: Int
    }

    private func captureLine(_ timing: SnapshotCaptureTiming) throws -> CaptureLine {
        let text = try #require(timing.line())
        return try JSONDecoder().decode(CaptureLine.self, from: Data(text.utf8))
    }
}
