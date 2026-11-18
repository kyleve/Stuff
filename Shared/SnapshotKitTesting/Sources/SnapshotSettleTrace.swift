import Foundation
import UIKit

/// Why the renderer requests a stability proof. These are diagnostic identities.
@_spi(Testing) public enum SnapshotSettleReason: String, Codable, Sendable {
    case measurement
    case content
    case nativeInsets
    case postAction
    case scrollReset
    case accessibilityPreparation
    case standalone
}

struct SnapshotCaptureTraceID {
    let rawValue = UUID()
}

/// Observations only: no value in this recorder participates in the verdict.
/// The standard settle record buffers all passes and encodes once after the loop exits.
@MainActor
@_spi(Testing) public final class SnapshotSettleTrace {
    /// A read-only walk of the view subtree at a settlement boundary.
    public struct PendingLayout: Encodable, Sendable {
        public let viewCount: Int
        public let dirtyCount: Int
        public let examples: [String]

        @MainActor public init(in root: UIView) {
            var visited = 0
            var dirty = 0
            var examples: [String] = []
            var path: [Int] = []

            func visit(_ view: UIView) {
                visited += 1
                if view.layer.needsLayout() {
                    dirty += 1
                    if examples.count < 5 {
                        let location = (["root"] + path.map(String.init)).joined(separator: "/")
                        let viewClass = String(describing: type(of: view)).prefix { $0 != "<" }
                        examples.append("\(location) \(viewClass.prefix(120))")
                    }
                }
                for (index, child) in view.subviews.enumerated() {
                    path.append(index)
                    visit(child)
                    path.removeLast()
                }
            }

            visit(root)
            viewCount = visited
            dirtyCount = dirty
            self.examples = examples
        }
    }

    public struct Pass: Codable, Sendable {
        public let index: Int
        public let sampleAt: Double
        public let sleepRequested: Double
        public let sleepActual: Double
        public let layout: Double
        public let render: Double
        public let pixelCheck: Double
        public let event: SnapshotPixelStability.Event?
        public let pixelStable: Bool?
        public let stable: Bool
        public let floorMet: Bool

        public init(
            index: Int,
            sampleAt: Double,
            sleepRequested: Double,
            sleepActual: Double,
            layout: Double,
            render: Double,
            pixelCheck: Double,
            event: SnapshotPixelStability.Event?,
            pixelStable: Bool?,
            stable: Bool,
            floorMet: Bool,
        ) {
            self.index = index
            self.sampleAt = sampleAt
            self.sleepRequested = sleepRequested
            self.sleepActual = sleepActual
            self.layout = layout
            self.render = render
            self.pixelCheck = pixelCheck
            self.event = event
            self.pixelStable = pixelStable
            self.stable = stable
            self.floorMet = floorMet
        }
    }

    private struct Record: Encodable {
        let version = 1
        let id: String
        let captureID: UUID
        let ordinal: Int
        let reason: SnapshotSettleReason
        let mechanism: String
        let captureOffset: Double
        let minimumDuration: Double
        let maximumDuration: Double
        let quietDuration: Double
        let elapsed: Double
        let outcome: String
        let passes: [Pass]
        let interruptedSleep: Double
    }

    private struct LayoutPass: Encodable {
        let id: String
        let captureID: UUID
        let ordinal: Int
        let reason: SnapshotSettleReason
        let pass: Int
        let afterLayout: PendingLayout
        let afterDraw: PendingLayout?
    }

    static let recordsPendingLayout = ProcessInfo.processInfo
        .environment["SNAPSHOT_TRACE_LAYOUT"] == "1"

    private let identifier: String
    private let captureID: SnapshotCaptureTraceID
    private let ordinal: Int
    private let reason: SnapshotSettleReason
    private let mechanism: SnapshotSettleMechanism
    private let captureOffset: Double
    private let minimumDuration: Double
    private let maximumDuration: Double
    private let start: ContinuousClock.Instant
    private var passes: [Pass] = []
    private var interruptedSleep = 0.0

    init(
        identifier: String,
        captureID: SnapshotCaptureTraceID,
        ordinal: Int,
        reason: SnapshotSettleReason,
        mechanism: SnapshotSettleMechanism,
        captureStart: ContinuousClock.Instant,
        start: ContinuousClock.Instant,
        minimumDuration: Double,
        maximumDuration: Double,
    ) {
        self.identifier = identifier
        self.captureID = captureID
        self.ordinal = ordinal
        self.reason = reason
        self.mechanism = mechanism
        captureOffset = Self.seconds(captureStart.duration(to: start))
        self.start = start
        self.minimumDuration = minimumDuration
        self.maximumDuration = maximumDuration
    }

    public func append(_ pass: Pass) {
        passes.append(pass)
    }

    func recordInterruptedSleep(_ duration: Duration) {
        interruptedSleep = Self.seconds(duration)
    }

    /// Used by tests without printing synthetic rows into real profile logs.
    public func line(outcome: SettleOutcome) -> String? {
        let outcomeName = switch outcome {
            case .settled: "settled"
            case .skipped: "skipped"
            case .timedOut: "timedOut"
            case .starved: "starved"
            case .cancelled: "cancelled"
        }
        let record = Record(
            id: identifier,
            captureID: captureID.rawValue,
            ordinal: ordinal,
            reason: reason,
            mechanism: mechanism.rawValue,
            captureOffset: captureOffset,
            minimumDuration: minimumDuration,
            maximumDuration: maximumDuration,
            quietDuration: Self.seconds(SnapshotPixelStability.quietDuration),
            elapsed: Self.seconds(start.duration(to: .now)),
            outcome: outcomeName,
            passes: passes,
            interruptedSleep: interruptedSleep,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(record),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    /// A separate row keeps view paths out of the existing whole-call trace.
    func emitLayout(pass: Int, afterLayout: PendingLayout, afterDraw: PendingLayout?) {
        let row = LayoutPass(
            id: identifier,
            captureID: captureID.rawValue,
            ordinal: ordinal,
            reason: reason,
            pass: pass,
            afterLayout: afterLayout,
            afterDraw: afterDraw,
        )
        guard let data = try? JSONEncoder().encode(row) else {
            writeSnapshotDiagnostic(
                "SNAPSHOT_LAYOUT_TRACE_ERROR could not encode \(identifier) call \(ordinal) pass \(pass)",
            )
            return
        }
        writeSnapshotDiagnostic("SNAPSHOT_LAYOUT_TRACE " + String(decoding: data, as: UTF8.self))
    }

    func emit(outcome: SettleOutcome) {
        if let json = line(outcome: outcome) {
            writeSnapshotDiagnostic("SNAPSHOT_SETTLE_TRACE \(json)")
        } else {
            writeSnapshotDiagnostic(
                "SNAPSHOT_SETTLE_TRACE_ERROR could not encode \(identifier) call \(ordinal)",
            )
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
