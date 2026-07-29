import Foundation

/// A phase of a single image capture, as attributed by ``SnapshotCaptureTiming``.
///
/// The cases are the pipeline's own steps in the order they run, so a timing
/// line reads as a walk through `renderSnapshotImage`. `settle`-shaped work
/// appears under three separate keys rather than one: the intrinsic-sizing
/// probe runs its own settle before the capture's, and a case's
/// `onReadyToSnapshot` hook is followed by a second one, so folding all three
/// together would hide which of them a slow case is actually paying for.
@_spi(Testing) public enum SnapshotCapturePhase: String, Sendable, CaseIterable {
    /// Hosting and settling the throwaway probe that measures `.intrinsic` /
    /// `.fullContent` content. Zero for `.fixed` sizing, which is most captures.
    case intrinsicMeasure
    /// Attaching the capture wrapper to the host root and laying it out — the
    /// real UIKit appearance transition, so SwiftUI `onAppear` / `.task` start.
    case host
    /// The content settle phase.
    case settle
    /// A case's `onReadyToSnapshot` hook plus the re-settle of its effects.
    case hook
    /// `AccessibilitySnapshotViewController.parseAccessibility()` and the
    /// re-layout at the size it resolves. Zero for non-accessibility captures.
    case accessibilityParse
    /// Draining in-flight animation completions before the capture.
    case drain
    /// The capture itself, through `tileAndStitchImage`.
    case tileStitch
    /// Encoding the capture to PNG and decoding it back, so the comparison sees
    /// the same bytes that reach disk.
    case pngRoundTrip
    /// `assertSnapshot` — decoding the reference, and comparing against it.
    case compare
}

/// Attributes a single capture's wall time across ``SnapshotCapturePhase``,
/// emitting one line per capture when `SNAPSHOT_TIMING` is set.
///
/// This exists because per-*test* durations (which the `.xcresult` already
/// carries, and `./profile` already reports) can't answer where a capture's
/// time goes: one test is one `SnapshotProviding` covering up to ten
/// configurations, so a slow suite says nothing about whether the cost is
/// settling, rendering, or comparing. The output is a line per image, which
/// `./test --timings` aggregates.
///
/// Deliberately a plain main-actor object passed down the call chain rather
/// than an ambient global: captures are serialized by ``SnapshotCaptureLock``
/// today, but a global recorder would silently mis-attribute the moment that
/// changes, and the repo's composition rule is to inject rather than re-resolve.
///
/// Disabled is the default and costs a `Bool` check per phase — the recorder is
/// still constructed and threaded through, so an instrumented run and a normal
/// run take the same code path.
@MainActor
@_spi(Testing) public final class SnapshotCaptureTiming {
    /// Whether the pipeline should emit timing lines, from `SNAPSHOT_TIMING`
    /// (reaching the test process as `TEST_RUNNER_SNAPSHOT_TIMING=1` on an
    /// xcodebuild command line — the same forwarding `SNAPSHOT_RECORD` uses).
    ///
    /// Any value other than `0`/`false`/empty enables it, so `=1`, `=yes`, and
    /// `=true` all work rather than only the one spelling.
    public static var isEnabledByEnvironment: Bool {
        isEnabled(forEnvironmentValue: ProcessInfo.processInfo.environment["SNAPSHOT_TIMING"])
    }

    /// The parsing half of ``isEnabledByEnvironment``, split out so it is
    /// testable without mutating the process environment.
    public static func isEnabled(forEnvironmentValue value: String?) -> Bool {
        guard let value else { return false }
        return !["", "0", "false", "no"].contains(value.lowercased())
    }

    private let identifier: String
    private let isEnabled: Bool
    private let clock = ContinuousClock()
    private let start: ContinuousClock.Instant
    private var durations: [SnapshotCapturePhase: TimeInterval] = [:]
    private var settlePasses = 0
    private var tiles = 0
    private var pixels = 0

    public init(identifier: String, isEnabled: Bool) {
        self.identifier = identifier
        self.isEnabled = isEnabled
        start = clock.now
    }

    /// Times `body` into `phase`, accumulating when a phase runs more than once.
    public func measure<Output>(
        _ phase: SnapshotCapturePhase,
        _ body: () throws -> Output,
    ) rethrows -> Output {
        guard isEnabled else { return try body() }
        let began = clock.now
        defer { record(phase, since: began) }
        return try body()
    }

    /// The `async` counterpart of ``measure(_:_:)``. Separate rather than one
    /// generic over effects because the pipeline's phases are a mix of both, and
    /// an `async` overload can't wrap a synchronous call without suspending.
    public func measure<Output>(
        _ phase: SnapshotCapturePhase,
        _ body: () async throws -> Output,
    ) async rethrows -> Output {
        guard isEnabled else { return try await body() }
        let began = clock.now
        defer { record(phase, since: began) }
        return try await body()
    }

    /// Records how many render/quiescence passes the settle loops ran in total.
    /// Accumulated across phases, so a `.intrinsic` capture reports the probe's
    /// passes plus the capture's.
    public func addSettlePasses(_ count: Int) {
        guard isEnabled else { return }
        settlePasses += count
    }

    /// Records the shape of the captured image: how many tiles
    /// ``tileAndStitchImage(of:)`` needed, and the pixel count of the result.
    /// Both let the aggregator ask whether a phase's cost tracks image area.
    public func recordCaptureShape(tiles: Int, pixels: Int) {
        guard isEnabled else { return }
        self.tiles = tiles
        self.pixels = pixels
    }

    /// Prints the capture's `SNAPSHOT_TIMING` line. Call once, after the
    /// comparison, and **only from the capture pipeline**: `./test --timings`
    /// aggregates these by grepping them out of the run logs, so anything else
    /// that prints one is counted as a capture that happened.
    @discardableResult
    public func emit() -> String? {
        guard let json = line() else { return nil }
        print("SNAPSHOT_TIMING \(json)")
        return json
    }

    /// The JSON payload ``emit()`` would print, or `nil` when timing is disabled
    /// (or the payload failed to encode, which says so on stdout rather than
    /// passing for a capture that cost nothing).
    ///
    /// Split from `emit()` so the wire shape can be asserted without *emitting* a
    /// line. It used to be one function whose doc invited tests to call it "without
    /// capturing stdout" — which they did, and `./test --timings` then counted
    /// their fixtures as real captures, blending invented phase totals into the
    /// aggregate the suite's performance decisions are read off.
    public func line() -> String? {
        guard isEnabled else { return nil }
        let payload = SnapshotCaptureTimingLine(
            id: identifier,
            phases: durations.reduce(into: [:]) { $0[$1.key.rawValue] = rounded($1.value) },
            settlePasses: settlePasses,
            tiles: tiles,
            pixels: pixels,
            total: rounded(elapsed(since: start)),
        )
        guard let data = try? JSONEncoder.snapshotTiming.encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            // Emitting is diagnostic-only, but a silent drop would look like a
            // capture that cost nothing — say so instead.
            print("SNAPSHOT_TIMING_ERROR could not encode timing for \(identifier)")
            return nil
        }
        return json
    }

    private func record(_ phase: SnapshotCapturePhase, since began: ContinuousClock.Instant) {
        durations[phase, default: 0] += elapsed(since: began)
    }

    private func elapsed(since instant: ContinuousClock.Instant) -> TimeInterval {
        let duration = instant.duration(to: clock.now)
        return TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) / 1e18
    }

    /// Milliseconds are the resolution anything here is read at, and full
    /// binary doubles make the emitted line hard to scan by eye.
    private func rounded(_ seconds: TimeInterval) -> Double {
        (seconds * 1000).rounded() / 1000
    }
}

/// The wire shape of one `SNAPSHOT_TIMING` line. Synthesized `Codable`: this is
/// a diagnostic format read by `./test --timings`, not a persisted one.
private struct SnapshotCaptureTimingLine: Encodable {
    let id: String
    let phases: [String: Double]
    let settlePasses: Int
    let tiles: Int
    let pixels: Int
    let total: Double
}

extension JSONEncoder {
    /// Sorted keys so successive lines diff cleanly and the aggregator's output
    /// is stable run to run.
    fileprivate static let snapshotTiming: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}
