import Foundation
import UIKit

/// Retains a bounded tail of the existing settle samples for an opt-in CI probe.
/// Encoding, file I/O, and pixel comparisons happen after the settle verdict.
@MainActor
@_spi(Testing) public final class SnapshotSettleTrace {
    private struct Frame {
        let pass: Int
        let seconds: TimeInterval
        let image: UIImage
    }

    private struct SavedFrame: Encodable {
        let pass: Int
        let seconds: TimeInterval
        let filename: String
        let identicalToPreviousSample: Bool?
    }

    private struct Manifest: Encodable {
        let identifier: String
        let outcome: String
        let passes: Int
        let retainedFrameLimit: Int
        let frames: [SavedFrame]
    }

    /// Only the most recent samples survive; a long or large capture cannot
    /// retain an unbounded image history.
    private static let retainedFrameLimit = 16
    private let directory: URL
    private let identifier: String
    private var frames: [Frame] = []

    public init(directory: URL, identifier: String) {
        self.directory = directory
        self.identifier = identifier
    }

    public static func fromEnvironment(identifier: String) -> SnapshotSettleTrace? {
        guard let path = ProcessInfo.processInfo.environment["SNAPSHOT_SETTLE_TRACE_DIR"],
              !path.isEmpty
        else { return nil }
        return SnapshotSettleTrace(directory: URL(fileURLWithPath: path), identifier: identifier)
    }

    public func record(image: UIImage?, pass: Int, seconds: TimeInterval) {
        guard let image else { return }
        frames.append(Frame(pass: pass, seconds: seconds, image: image))
        if frames.count > Self.retainedFrameLimit {
            frames.removeFirst()
        }
    }

    /// Writes PNGs, raw-sample equality, and normalized pixel deltas without
    /// emitting the ordinary capture timing or reference-diff report channels.
    public func write(outcome: SettleOutcome, passes: Int) throws -> URL {
        let output = directory.appendingPathComponent("settle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var savedFrames: [SavedFrame] = []
        var differences: [String] = []
        var previousURL: URL?
        var previousSample: Data?
        for frame in frames {
            let filename = String(format: "%04d.png", frame.pass)
            let url = output.appendingPathComponent(filename)
            guard let png = frame.image.pngData() else {
                throw SnapshotRenderingError.pngEncodingFailed(name: identifier)
            }
            try png.write(to: url)
            let sample = frame.image.cgImage?.dataProvider?.data as Data?
            savedFrames.append(SavedFrame(
                pass: frame.pass,
                seconds: frame.seconds,
                filename: filename,
                identicalToPreviousSample: previousSample.map { $0 == sample },
            ))
            if let previousURL,
               let difference = SnapshotDiffReporting.line(
                   describing: compareAgainstReference(capturedPNG: png, referenceURL: previousURL),
                   identifier: "\(identifier) pass \(frame.pass)",
                   reference: previousURL,
               )
            {
                differences.append(difference)
            }
            previousURL = url
            previousSample = sample
        }
        try differences.joined(separator: "\n")
            .write(
                to: output.appendingPathComponent("diffs.jsonl"),
                atomically: true,
                encoding: .utf8,
            )
        let manifest = Manifest(
            identifier: identifier,
            outcome: String(describing: outcome),
            passes: passes,
            retainedFrameLimit: Self.retainedFrameLimit,
            frames: savedFrames,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestURL = output.appendingPathComponent("manifest.json")
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifestURL
    }
}
