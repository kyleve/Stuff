import Foundation
import ImageDiffKit

/// How much a capture differs from its reference, in terms a reviewer can act on.
///
/// The pass/fail verdict belongs to swift-snapshot-testing; this describes the
/// *shape* of a delta beside it. "0.24% of pixels differ, max channel delta 203,
/// confined to a 1037x144 band" is a claim someone can sign off on or reject;
/// "does not match reference" is not.
@_spi(Testing) public struct SnapshotDiffMagnitude: Equatable, Sendable {
    /// Pixels whose RGB bytes differ at all.
    public let differingPixels: Int
    /// Pixels compared, so a reader doesn't need the image dimensions to scale
    /// `differingPixels`.
    public let totalPixels: Int
    /// The largest single-channel difference, 0-255. Separates "a whole region
    /// moved" (high) from "antialiasing drifted" (low) at the same pixel count.
    public let maxChannelDelta: Int
    /// The smallest pixel rect containing every differing pixel, top-left origin.
    /// A tight box localizes the change to a component; a full-frame box means
    /// something global moved.
    public let changedRegion: CGRect

    public var differingFraction: Double {
        totalPixels == 0 ? 0 : Double(differingPixels) / Double(totalPixels)
    }

    public init(
        differingPixels: Int,
        totalPixels: Int,
        maxChannelDelta: Int,
        changedRegion: CGRect,
    ) {
        self.differingPixels = differingPixels
        self.totalPixels = totalPixels
        self.maxChannelDelta = maxChannelDelta
        self.changedRegion = changedRegion
    }
}

/// The outcome of checking a capture against the reference on disk.
///
/// Modeled as one enum rather than an optional magnitude beside a `Bool`: "the
/// reference is missing", "the bytes are identical", and "here is how they
/// differ" are mutually exclusive, and only the last carries a magnitude.
@_spi(Testing) public enum SnapshotReferenceComparison: Equatable, Sendable {
    /// No reference at that path — a first recording, or a derived path that
    /// doesn't match where the library actually writes.
    case referenceMissing(URL)
    /// The captured PNG bytes equal the reference file's bytes exactly. The
    /// interesting case for cost: nothing needs decoding or comparing.
    case identicalBytes
    /// The bytes differ, with the delta described.
    case differs(SnapshotDiffMagnitude)
    /// The comparison couldn't be made — a size mismatch or an undecodable file.
    /// Reported rather than swallowed, so a broken reference can't read as "no
    /// difference found".
    case incomparable(reason: String)
}

/// Where swift-snapshot-testing keeps the reference for a capture.
///
/// This mirrors the library's own layout — `__Snapshots__/<test file base
/// name>/<test function>.<identifier>.png`, alongside the test source — because
/// nothing public exposes it. That makes it a coupling worth stating: if a
/// library update moves references, this returns
/// ``SnapshotReferenceComparison/referenceMissing(_:)`` for every capture rather
/// than silently reporting no differences, and `SnapshotReferenceDiffTests` pins
/// the shape against a real reference in this repo.
@_spi(Testing) public func snapshotReferenceURL(
    testFilePath: String,
    testName: String,
    identifier: String,
) -> URL {
    let testFile = URL(fileURLWithPath: testFilePath)
    // The library strips a trailing `()` from `#function`, so `year()` and the
    // `year` directory component agree.
    let function = testName.hasSuffix("()") ? String(testName.dropLast(2)) : testName
    return testFile
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent(testFile.deletingPathExtension().lastPathComponent)
        .appendingPathComponent("\(function).\(identifier).png")
}

/// Compares `capturedPNG` against the reference at `referenceURL`.
///
/// Byte equality is checked first and short-circuits: it is the common case when
/// a capture is deterministic, and it costs a file read rather than two image
/// decodes.
@_spi(Testing) public func compareAgainstReference(
    capturedPNG: Data,
    referenceURL: URL,
) -> SnapshotReferenceComparison {
    guard let referencePNG = try? Data(contentsOf: referenceURL) else {
        return .referenceMissing(referenceURL)
    }
    guard capturedPNG != referencePNG else { return .identicalBytes }
    do {
        let result = try ImageDiffEngine().compare(
            base: referencePNG,
            head: capturedPNG,
            options: .exact,
        )
        switch result {
            case let .dimensionMismatch(reference, capture):
                return .incomparable(
                    reason: """
                    sizes differ — reference is \(reference.width)x\(reference.height)px, \
                    capture is \(capture.width)x\(capture.height)px
                    """,
                )
            case let .comparable(metrics, _):
                return .differs(SnapshotDiffMagnitude(
                    differingPixels: metrics.changedPixels,
                    totalPixels: metrics.dimensions.pixelCount,
                    maxChannelDelta: Int(metrics.maximumChannelDelta),
                    changedRegion: metrics.changedBounds ?? .zero,
                ))
        }
    } catch let error as ImageDiffError {
        switch error {
            case .undecodable(.head):
                return .incomparable(reason: "the capture could not be decoded")
            case .undecodable(.base):
                return .incomparable(
                    reason: "the reference at \(referenceURL.path) could not be decoded",
                )
            case .pixelNormalizationFailed:
                return .incomparable(reason: "pixels could not be read for comparison")
            case .heatmapEncodingFailed:
                return .incomparable(reason: error.localizedDescription)
        }
    } catch {
        return .incomparable(reason: error.localizedDescription)
    }
}

/// Emits one `SNAPSHOT_DIFF` line per capture whose bytes don't match its
/// reference, for `./test --review` to aggregate.
///
/// Gated on `SNAPSHOT_DIFF` (reaching the test process as
/// `TEST_RUNNER_SNAPSHOT_DIFF=1`) because the pixel walk costs real time on a
/// capture that differs, and a normal run shouldn't pay it. `./test` turns it on
/// for snapshot runs.
@_spi(Testing) public enum SnapshotDiffReporting {
    public static var isEnabledByEnvironment: Bool {
        isEnabled(forEnvironmentValue: ProcessInfo.processInfo.environment["SNAPSHOT_DIFF"])
    }

    /// Split from the environment read so it is testable without mutating the
    /// process environment.
    public static func isEnabled(forEnvironmentValue value: String?) -> Bool {
        guard let value else { return false }
        return !["", "0", "false", "no"].contains(value.lowercased())
    }

    /// Prints the `SNAPSHOT_DIFF` line describing `comparison`, unless it is a
    /// byte-for-byte match, which is the silent success case.
    ///
    /// **Only the capture pipeline may call this.** `./test --review` recovers
    /// diffs by grepping `SNAPSHOT_DIFF` out of the run logs, so anything that
    /// prints one appears in the report as a real differing capture — with no way
    /// for a reader to tell it apart. Tests that need the payload ask
    /// ``line(describing:identifier:reference:)`` for it instead.
    @discardableResult
    public static func report(
        _ comparison: SnapshotReferenceComparison,
        identifier: String,
        reference: URL,
    ) -> String? {
        guard let json = line(
            describing: comparison,
            identifier: identifier,
            reference: reference,
        ) else { return nil }
        print("SNAPSHOT_DIFF \(json)")
        return json
    }

    /// The JSON payload ``report(_:identifier:reference:)`` would print for
    /// `comparison`, or `nil` when there is nothing to report — a byte-identical
    /// capture, or a payload that failed to encode (which says so on stdout
    /// rather than passing for "no difference found").
    ///
    /// Split from `report` so the wire shape can be asserted without *emitting* a
    /// line. It used to be one function, and this module's own reporting test
    /// consequently printed a `SNAPSHOT_DIFF` line for a reference that does not
    /// exist — which `./test --review` then listed among the real captures, at the
    /// top, because the fixture borrowed its numbers from a genuine regression.
    public static func line(
        describing comparison: SnapshotReferenceComparison,
        identifier: String,
        reference: URL,
    ) -> String? {
        // The identifier alone doesn't locate a diff — seven suites in this repo
        // declare an `Empty` case, so `Empty_iPhone` names a reference in none of
        // them in particular. The path does.
        let path = reference.path
        let line: SnapshotDiffLine? = switch comparison {
            case .identicalBytes:
                nil
            case let .referenceMissing(url):
                SnapshotDiffLine(id: identifier, outcome: "referenceMissing", reference: url.path)
            case let .incomparable(reason):
                SnapshotDiffLine(
                    id: identifier,
                    outcome: "incomparable",
                    reference: path,
                    detail: reason,
                )
            case let .differs(magnitude):
                SnapshotDiffLine(
                    id: identifier,
                    outcome: "differs",
                    reference: path,
                    differingPixels: magnitude.differingPixels,
                    totalPixels: magnitude.totalPixels,
                    differingFraction: (magnitude.differingFraction * 1_000_000).rounded() / 1e6,
                    maxChannelDelta: magnitude.maxChannelDelta,
                    region: [
                        Int(magnitude.changedRegion.minX),
                        Int(magnitude.changedRegion.minY),
                        Int(magnitude.changedRegion.width),
                        Int(magnitude.changedRegion.height),
                    ],
                )
        }
        guard let line else { return nil }
        guard let data = try? JSONEncoder.snapshotDiff.encode(line),
              let json = String(data: data, encoding: .utf8)
        else {
            print("SNAPSHOT_DIFF_ERROR could not encode diff for \(identifier)")
            return nil
        }
        return json
    }
}

/// The wire shape of one `SNAPSHOT_DIFF` line.
private struct SnapshotDiffLine: Encodable {
    let id: String
    let outcome: String
    var reference: String?
    var detail: String?
    var differingPixels: Int?
    var totalPixels: Int?
    var differingFraction: Double?
    var maxChannelDelta: Int?
    var region: [Int]?
}

extension JSONEncoder {
    fileprivate static let snapshotDiff: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}
