import Foundation
@_spi(Testing) import SnapshotKitTesting
import TestHostSupport
import Testing
import UIKit

/// Covers the quiescence mechanism and the comparison harness that measured it.
///
/// The mechanism is **not** the default and is not expected to become one: run
/// against all 260 references in `both` mode it declared settled *earlier* than
/// the pixel digest on 11 settle phases, every one of them a `Loaded_*` case
/// whose content arrives late. See `AGENTS.md` for the result. These tests keep
/// the harness honest so the experiment can be re-run after a toolchain change
/// rather than re-derived.
@MainActor
struct SnapshotQuiescenceTests {
    @Test(arguments: [
        (value: String?.none, expected: SnapshotSettleMechanism.pixel),
        (value: "pixel", expected: .pixel),
        (value: "quiescence", expected: .quiescence),
        (value: "QUIESCENCE", expected: .quiescence),
        (value: "both", expected: .both),
        // An unrecognized value falls back to the mechanism the references were
        // recorded under rather than silently opting into the experiment.
        (value: "nonsense", expected: .pixel),
        (value: "", expected: .pixel),
    ])
    func mechanismParsesFromAnEnvironmentValue(
        value: String?,
        expected: SnapshotSettleMechanism,
    ) {
        #expect(SnapshotSettleMechanism.parse(value) == expected)
    }

    @Test func idleCounterCountsTheRunLoopGoingIdle() async {
        let counter = RunLoopIdleCounter()
        counter.start()
        defer { counter.stop() }
        #expect(counter.idleCount == 0)

        // Suspending frees the main actor, so the run loop reaches
        // `beforeWaiting` — the property the settle loop reads.
        try? await Task.sleep(for: .milliseconds(60))
        #expect(counter.idleCount > 0)
    }

    @Test func stoppingTheIdleCounterIsIdempotentAndHaltsCounting() async {
        let counter = RunLoopIdleCounter()
        counter.start()
        try? await Task.sleep(for: .milliseconds(30))
        counter.stop()
        counter.stop()
        let afterStop = counter.idleCount
        try? await Task.sleep(for: .milliseconds(30))
        #expect(counter.idleCount == afterStop)
    }

    @Test func restartingReplacesRatherThanDoublesTheObserver() async {
        let counter = RunLoopIdleCounter()
        counter.start()
        counter.start()
        defer { counter.stop() }
        try? await Task.sleep(for: .milliseconds(50))
        let single = RunLoopIdleCounter()
        single.start()
        defer { single.stop() }
        try? await Task.sleep(for: .milliseconds(50))
        // A doubled observer would count each idle twice. Compare growth rates
        // over the same window rather than absolute counts, which depend on how
        // many times the loop happened to sleep.
        let restarted = counter.idleCount
        let baseline = single.idleCount
        #expect(restarted < baseline * 3)
    }

    @Test func pendingLayoutIsSeenAnywhereInTheSubtree() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let child = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        let grandchild = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        child.addSubview(grandchild)
        root.addSubview(child)
        root.layoutIfNeeded()
        CATransaction.flush()

        // The case that matters is depth: a dirty layer far from the root is
        // exactly what a root-only flag check would miss.
        grandchild.layer.setNeedsLayout()
        #expect(root.layer.hasPendingWork())
    }

    @Test func aRunningAnimationCountsAsPendingWork() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        view.layoutIfNeeded()
        CATransaction.flush()

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 5
        view.layer.add(animation, forKey: "fade")
        #expect(view.layer.hasPendingWork())
    }

    /// `both` runs the experiment; it must not decide anything.
    ///
    /// The two mechanisms keep separate observed-change flags, and only the one
    /// holding the verdict feeds the `.timedOut` / `.starved` choice. When they
    /// shared a flag, quiescence flapping could return `.timedOut` for content
    /// the digest never saw change — failing a capture that `pixel` alone would
    /// have kept retrying, which is precisely the experiment altering the thing
    /// it exists to measure.
    ///
    /// Static content on a budget too short to prove stability is the case that
    /// separates them: `pixel` must reach `.settled`, and it must do so under
    /// every mechanism.
    @Test(arguments: [
        SnapshotSettleMechanism.pixel,
        .both,
    ])
    func staticContentSettlesRegardlessOfMechanism(
        mechanism: SnapshotSettleMechanism,
    ) async throws {
        try waitFor { hostKeyWindow() != nil }
        let window = try #require(hostKeyWindow())
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        view.backgroundColor = .systemTeal
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let outcome = await settleContent(
            view,
            named: "\(#function)-\(mechanism.rawValue)",
            minDuration: 0,
            maxDuration: 0.1,
            mechanism: mechanism,
        )
        #expect(outcome == .settled, "\(mechanism.rawValue) changed the verdict")
    }

    @Test func settleComparisonIsOnlyReportedInBothMode() {
        for mechanism in [SnapshotSettleMechanism.pixel, .quiescence] {
            #expect(
                SnapshotSettleReporting.line(
                    identifier: "case",
                    mechanism: mechanism,
                    passes: 4,
                    disagreements: [],
                ) == nil,
            )
        }
    }

    /// Asks for the payload rather than calling `report(...)`, which would print a
    /// `SNAPSHOT_SETTLE` line for a capture that never happened.
    @Test func settleComparisonCountsTheDangerousDirectionSeparately() throws {
        let json = try #require(SnapshotSettleReporting.line(
            identifier: "case_dark",
            mechanism: .both,
            passes: 18,
            disagreements: [
                SettleDisagreement(pass: 3, quiescenceWasEarlier: false),
                SettleDisagreement(pass: 8, quiescenceWasEarlier: true),
                SettleDisagreement(pass: 9, quiescenceWasEarlier: true),
            ],
        ))
        let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let line = try #require(decoded)
        #expect(line["passes"] as? Int == 18)
        #expect(line["disagreements"] as? Int == 3)
        // Only the "quiescence said settled first" direction can change what a
        // capture records, so it is counted on its own.
        #expect(line["quiescenceEarlier"] as? Int == 2)
        #expect(line["firstEarlyPass"] as? Int == 8)
    }
}
