import Foundation
import UIKit

/// How the settle loop decides the content has stopped changing.
///
/// The pixel digest is the original and remains the default; quiescence is the
/// cheap alternative, and `both` runs them together to find out where they
/// disagree before either becomes the default.
@_spi(Testing) public enum SnapshotSettleMechanism: String, Sendable, CaseIterable {
    /// Re-render the view at quarter resolution each pass and compare bytes.
    /// Authoritative — it observes the thing the capture will record — and the
    /// expensive option, because `afterScreenUpdates: true` round-trips to the
    /// render server.
    case pixel
    /// Ask the main run loop and the layer tree whether anything is still
    /// pending. Costs a tree walk instead of a render.
    case quiescence
    /// Run both and report every disagreement, without changing the verdict:
    /// `pixel` still decides. The experiment mode.
    case both

    /// From `SNAPSHOT_SETTLE` (reaching the test process as
    /// `TEST_RUNNER_SNAPSHOT_SETTLE=…`), defaulting to ``pixel``.
    public static var fromEnvironment: Self {
        parse(ProcessInfo.processInfo.environment["SNAPSHOT_SETTLE"])
    }

    /// Split from the environment read so it is testable without mutating the
    /// process environment. An unrecognized value falls back to ``pixel`` — the
    /// conservative direction, since it is the mechanism the references were
    /// recorded under.
    public static func parse(_ value: String?) -> Self {
        guard let value, let mechanism = Self(rawValue: value.lowercased()) else { return .pixel }
        return mechanism
    }
}

/// Counts the main run loop reaching `beforeWaiting` — the point at which every
/// runnable main-queue job has drained, including the main-actor jobs that
/// SwiftUI `.task` bodies become.
///
/// Every `start` has a `stop`, per the repo's observation rule, and `stop` is
/// idempotent so a restart replaces rather than doubles. This is a
/// `CFRunLoopObserver` rather than a target/selector because the run loop offers
/// no notification for this; the handler is removed in `stop()`, which the settle
/// loop calls in a `defer`.
///
/// The handler holds `self` **weakly**, so forgetting `stop()` leaks only the
/// observer rather than immortalizing the counter — and a strong capture would
/// form a cycle through the stored observer that made `deinit` unreachable, i.e.
/// the one place that could otherwise clean up after a missed `stop()`.
@MainActor
@_spi(Testing) public final class RunLoopIdleCounter {
    private var observer: CFRunLoopObserver?
    public private(set) var idleCount = 0

    public init() {}

    public func start() {
        stop()
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0,
        ) { [weak self] _, _ in
            // The main run loop only runs on the main thread, which is where the
            // main actor lives, so this is that isolation rather than a hop.
            MainActor.assumeIsolated { self?.idleCount += 1 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    public func stop() {
        guard let observer else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = nil
    }

    // No `deinit` cleanup: it would have to read main-actor-isolated,
    // non-Sendable state from a nonisolated context. The weak capture above is
    // what makes that acceptable — a missed `stop()` leaves a registered observer
    // whose handler no-ops once the counter is gone, rather than keeping the
    // counter alive forever as a strong capture would.
}

extension CALayer {
    /// Whether anything in this layer subtree still has work outstanding —
    /// pending layout, pending display, or a running animation.
    ///
    /// Walked recursively rather than checked on the root because the case this
    /// has to catch is a SwiftUI update deep in the hosted tree, which never
    /// marks the root dirty. That is also this signal's known weakness: flags
    /// read *after* a commit has already flushed look clean even though the
    /// content changed that frame, which is why the pixel digest exists and why
    /// `both` mode is how quiescence earns the default.
    @MainActor
    @_spi(Testing) public func hasPendingWork() -> Bool {
        if needsLayout() || needsDisplay() { return true }
        if let keys = animationKeys(), !keys.isEmpty { return true }
        guard let sublayers else { return false }
        return sublayers.contains { $0.hasPendingWork() }
    }
}

/// A disagreement between the two mechanisms on one settle pass, recorded under
/// ``SnapshotSettleMechanism/both``.
///
/// Only one direction is dangerous: quiescence calling the content settled while
/// the pixels are still moving would capture a frame the reference never
/// recorded. The other direction only costs time.
@_spi(Testing) public struct SettleDisagreement: Equatable, Sendable {
    public let pass: Int
    /// `true` when quiescence said settled and the pixel digest said otherwise —
    /// the direction that would change what gets captured.
    public let quiescenceWasEarlier: Bool

    public init(pass: Int, quiescenceWasEarlier: Bool) {
        self.pass = pass
        self.quiescenceWasEarlier = quiescenceWasEarlier
    }
}

/// Emits one `SNAPSHOT_SETTLE` line per capture that ran in `both` mode, so a
/// full-suite run answers whether quiescence can replace the digest.
@_spi(Testing) public enum SnapshotSettleReporting {
    /// Prints the capture's `SNAPSHOT_SETTLE` line, and so belongs to the capture
    /// pipeline alone. Nothing aggregates this channel today — the `both`-mode
    /// experiment is read by hand — but the sibling channels are grepped out of the
    /// run logs, so a line printed from anywhere else is a row in a report.
    @discardableResult
    public static func report(
        identifier: String,
        mechanism: SnapshotSettleMechanism,
        passes: Int,
        disagreements: [SettleDisagreement],
    ) -> String? {
        guard let json = line(
            identifier: identifier,
            mechanism: mechanism,
            passes: passes,
            disagreements: disagreements,
        ) else { return nil }
        print("SNAPSHOT_SETTLE \(json)")
        return json
    }

    /// The JSON payload ``report(identifier:mechanism:passes:disagreements:)``
    /// would print, or `nil` outside `both` mode (or when the payload failed to
    /// encode, which says so on stdout). Split from `report` so the wire shape can
    /// be asserted without emitting a line — see the same split on
    /// ``SnapshotDiffReporting`` and ``SnapshotCaptureTiming``, where a test
    /// emitting one did reach a report.
    public static func line(
        identifier: String,
        mechanism: SnapshotSettleMechanism,
        passes: Int,
        disagreements: [SettleDisagreement],
    ) -> String? {
        guard mechanism == .both else { return nil }
        let early = disagreements.filter(\.quiescenceWasEarlier).count
        let payload = SnapshotSettleLine(
            id: identifier,
            passes: passes,
            disagreements: disagreements.count,
            quiescenceEarlier: early,
            firstEarlyPass: disagreements.first(where: \.quiescenceWasEarlier)?.pass,
        )
        guard let data = try? JSONEncoder.snapshotSettle.encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            print("SNAPSHOT_SETTLE_ERROR could not encode settle comparison for \(identifier)")
            return nil
        }
        return json
    }
}

private struct SnapshotSettleLine: Encodable {
    let id: String
    let passes: Int
    let disagreements: Int
    let quiescenceEarlier: Int
    var firstEarlyPass: Int?
}

extension JSONEncoder {
    fileprivate static let snapshotSettle: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}
