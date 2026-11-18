import Foundation
import ImageIO
import SnapshotKit

/// Opt-in observation of the normal assertions. Match by reviewed path because
/// identifiers such as "Loaded_iPhone" can occur in several independent suites.
@MainActor
enum SnapshotMountExperiment {
    enum Selection {
        case skip
        case capture(Request?)
    }

    private struct Settings {
        let arm: String
        let output: URL
        let references: [URL: String]
    }

    private static let settings = Result<Settings?, any Error> {
        let env = ProcessInfo.processInfo.environment
        let manifest = env["SNAPSHOT_MOUNT_MANIFEST"]
        let output = env["SNAPSHOT_MOUNT_OUTPUT"]
        let arm = env["SNAPSHOT_MOUNT_TRIAL"]
        if manifest == nil, output == nil, arm == nil { return nil }
        guard let manifest, let output, let arm,
              manifest.hasPrefix("/"), output.hasPrefix("/"),
              ["baseline", "retained", "early"].contains(arm)
        else { throw Failure.invalidSettings }

        // This file is in Shared/SnapshotKitTesting/Sources in the tested checkout.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOfFile: manifest, encoding: .utf8)
        var references: [URL: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let relative = line.trimmingCharacters(in: .whitespaces)
            if relative.isEmpty || relative.hasPrefix("#") { continue }
            let components = relative.split(separator: "/", omittingEmptySubsequences: false)
            guard components.contains("__Snapshots__"), !components.contains(".."),
                  !components.contains("."), !components.contains(""), relative.hasSuffix(".png")
            else { throw Failure.invalidPath(relative) }
            let path = root.appendingPathComponent(relative).standardizedFileURL
            guard references.updateValue(relative, forKey: path) == nil
            else { throw Failure.invalidPath(relative) }
        }
        guard !references.isEmpty else { throw Failure.invalidSettings }
        return Settings(arm: arm, output: URL(fileURLWithPath: output), references: references)
    }

    static func select(
        identifier: String,
        configuration: SnapshotConfiguration,
        group: SnapshotReferenceGroup?,
        file: StaticString,
        testName: String,
    ) throws -> Selection {
        guard let settings = try settings.get() else { return .capture(nil) }
        let reference = snapshotReferenceURL(
            testFilePath: file.description,
            testName: testName,
            identifier: identifier,
            configuration: configuration,
            referenceGroup: group,
        ).standardizedFileURL
        guard let relative = settings.references[reference] else { return .skip }
        return .capture(Request(arm: settings.arm, reference: relative, output: settings.output))
    }

    enum Failure: Error {
        case invalidSettings, invalidPath(String), missingCaptureEvidence(String), unreadablePixels
    }

    @MainActor
    final class Request {
        let arm: String
        let reference: String
        let output: URL
        private let clock = ContinuousClock()
        private let start = ContinuousClock.now
        private var duration: Duration = .zero
        private var captures: [Capture] = []

        private struct Capture: Encodable {
            let id: UUID
            let name: String
            let mountPath: String
            let wrapperMounts: Int
            let earlyContent: Bool
        }

        private struct Observation: Encodable {
            let reference: String
            let arm: String
            let seconds: Double
            let accepted: Bool
            let detail: String?
            let width: Int
            let height: Int
            let panels: Int
            let captures: [Capture]
        }

        init(arm: String, reference: String, output: URL) {
            self.arm = arm
            self.reference = reference
            self.output = output
        }

        func observe(_ timing: SnapshotCaptureTiming, named name: String) throws {
            guard let id = timing.captureID, let path = timing.mountPath,
                  let mounts = timing.wrapperMounts, let early = timing.earlyContent
            else { throw Failure.missingCaptureEvidence(name) }
            captures.append(Capture(
                id: id,
                name: name,
                mountPath: path,
                wrapperMounts: mounts,
                earlyContent: early,
            ))
        }

        func finishCapture() {
            duration = start.duration(to: clock.now)
        }

        func addComposition(since start: ContinuousClock.Instant) {
            duration += start.duration(to: clock.now)
        }

        func export(
            _ png: Data,
            reviewed: URL,
            panelFailure: SnapshotImageReference.ComparisonFailure?,
            panels: Int,
        ) throws {
            let original = try Data(contentsOf: reviewed)
            guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(
                      source,
                      0,
                      nil,
                  ) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int
            else { throw Failure.unreadablePixels }
            // Use the exact panel, metadata and whole-image comparison used by
            // verifySnapshot. Its recording and attachment paths are unnecessary here.
            let failure = SnapshotImageReference.strategy(panelFailure: panelFailure)
                .diffing.diffV2(original, png)?.0
            let observation = Observation(
                reference: reference,
                arm: arm,
                seconds: Double(duration.components.seconds) +
                    Double(duration.components.attoseconds) / 1e18,
                accepted: failure == nil,
                detail: failure,
                width: width,
                height: height,
                panels: panels,
                captures: captures,
            )
            let target = output.appendingPathComponent(reference)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            // An old output directory or a duplicate request must fail visibly.
            try png.write(to: target, options: .withoutOverwriting)
            let data = try JSONEncoder().encode(observation)
            try data.write(
                to: target.deletingPathExtension().appendingPathExtension("json"),
                options: .withoutOverwriting,
            )
        }
    }
}
