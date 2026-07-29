import Foundation
@_spi(Testing) import SnapshotKitTesting
import Testing

/// Covers the phase recorder that attributes a capture's wall time. The
/// pipeline's own numbers are only as trustworthy as this accounting, so the
/// accumulation and the emitted shape are pinned here rather than eyeballed in
/// a log.
@MainActor
struct SnapshotCaptureTimingTests {
    @Test func disabledRecorderEmitsNothing() {
        let timing = SnapshotCaptureTiming(identifier: "disabled", isEnabled: false)
        timing.measure(.settle) {}
        timing.addSettlePasses(3)
        #expect(timing.line() == nil)
    }

    @Test func measuredPhaseIsAttributedToItsOwnKey() throws {
        let timing = SnapshotCaptureTiming(identifier: "one-phase", isEnabled: true)
        timing.measure(.tileStitch) { spin(for: .milliseconds(30)) }

        let line = try decodedLine(from: timing)
        #expect(line.id == "one-phase")
        #expect(line.phases.keys.sorted() == ["tileStitch"])
        let measured = try #require(line.phases["tileStitch"])
        #expect(measured >= 0.02)
        // The phase can't exceed the capture it is part of.
        #expect(measured <= line.total)
    }

    @Test func repeatedPhaseAccumulatesIntoOneKey() throws {
        let timing = SnapshotCaptureTiming(identifier: "repeated", isEnabled: true)
        for _ in 0 ..< 3 {
            timing.measure(.settle) { spin(for: .milliseconds(20)) }
        }

        let line = try decodedLine(from: timing)
        #expect(line.phases.keys.sorted() == ["settle"])
        // Three 20ms spins land in one key rather than overwriting each other —
        // the property that makes the intrinsic probe's settle and the capture's
        // settle both visible instead of only the last one.
        #expect(try #require(line.phases["settle"]) >= 0.06)
    }

    @Test func asyncAndSyncPhasesBothRecord() async throws {
        let timing = SnapshotCaptureTiming(identifier: "mixed", isEnabled: true)
        timing.measure(.host) { spin(for: .milliseconds(10)) }
        await timing.measure(.hook) { try? await Task.sleep(for: .milliseconds(20)) }

        let line = try decodedLine(from: timing)
        #expect(line.phases.keys.sorted() == ["hook", "host"])
    }

    @Test func settlePassesAccumulateAndCaptureShapeIsReported() throws {
        let timing = SnapshotCaptureTiming(identifier: "shape", isEnabled: true)
        timing.addSettlePasses(4)
        timing.addSettlePasses(3)
        timing.recordCaptureShape(tiles: 2, pixels: 1_234_567)

        let line = try decodedLine(from: timing)
        #expect(line.settlePasses == 7)
        #expect(line.tiles == 2)
        #expect(line.pixels == 1_234_567)
    }

    @Test func unmeasuredPhasesAreAbsentRatherThanZero() throws {
        let timing = SnapshotCaptureTiming(identifier: "sparse", isEnabled: true)
        timing.measure(.compare) {}

        let line = try decodedLine(from: timing)
        // An absent key and a zero are different claims: `accessibilityParse`
        // not running at all is not the same as running for no time.
        #expect(line.phases["accessibilityParse"] == nil)
    }

    @Test(arguments: [
        (value: String?.none, expected: false),
        (value: "", expected: false),
        (value: "0", expected: false),
        (value: "false", expected: false),
        (value: "FALSE", expected: false),
        (value: "no", expected: false),
        (value: "1", expected: true),
        (value: "yes", expected: true),
        (value: "true", expected: true),
    ])
    func environmentValueEnablesTiming(value: String?, expected: Bool) {
        #expect(SnapshotCaptureTiming.isEnabled(forEnvironmentValue: value) == expected)
    }

    /// The emitted line, decoded. Mirrors the private wire struct rather than
    /// sharing it: the aggregator in `./test` parses the same JSON from a log,
    /// so decoding it independently is what actually pins the format.
    private struct Line: Decodable {
        let id: String
        let phases: [String: Double]
        let settlePasses: Int
        let tiles: Int
        let pixels: Int
        let total: Double
    }

    /// Asks for the payload rather than calling `emit()`, which would print a
    /// `SNAPSHOT_TIMING` line. `./test --timings` aggregates those out of the run
    /// log, so emitting here counted each fixture below as a capture that
    /// happened — five of them, with invented phase totals, in any run that
    /// included this bundle.
    private func decodedLine(from timing: SnapshotCaptureTiming) throws -> Line {
        let json = try #require(timing.line())
        return try JSONDecoder().decode(Line.self, from: Data(json.utf8))
    }

    /// Busy-waits so a synchronous phase has measurable duration. Deliberately
    /// not `Thread.sleep`: these assertions are lower bounds on elapsed time, and
    /// spinning keeps the phase on this thread the way real synchronous phases
    /// (layout, rendering, PNG encoding) are.
    private func spin(for duration: Duration) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: duration)
        while clock.now < deadline {}
    }
}
