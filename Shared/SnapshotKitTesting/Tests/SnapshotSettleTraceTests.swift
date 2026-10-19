import Foundation
@_spi(Testing) import SnapshotKitTesting
import Testing
import UIKit

/// Guards diagnostic retention and pixel evidence without emitting capture report rows.
@MainActor
struct SnapshotSettleTraceTests {
    @Test func retainsOnlyTheLatestSamplesAndWritesAfterTheVerdict() throws {
        let directory = temporaryDirectory()
        let trace = SnapshotSettleTrace(directory: directory, identifier: "bounded")
        let image = sampleImage(patch: false)
        for pass in 1 ... 20 {
            trace.record(image: image, pass: pass, seconds: Double(pass) / 10)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        let manifestURL = try trace.write(outcome: .timedOut(budget: 7), passes: 20)
        defer { removeDirectory(directory) }
        let manifest = try readManifest(manifestURL)
        let frames = try #require(manifest["frames"] as? [[String: Any]])
        #expect(manifest["identifier"] as? String == "bounded")
        #expect(manifest["outcome"] as? String == "timedOut(budget: 7.0)")
        #expect(manifest["passes"] as? Int == 20)
        #expect(frames.count == 16)
        #expect(frames.first?["pass"] as? Int == 5)
        #expect(frames.first?["seconds"] as? Double == 0.5)
        #expect(frames.last?["pass"] as? Int == 20)
        let files = try FileManager.default
            .contentsOfDirectory(atPath: manifestURL.deletingLastPathComponent().path)
        #expect(files.count(where: { $0.hasSuffix(".png") }) == 16)
    }

    @Test func savesUnchangedSamplesAndLocalizesOneChannelUnitOfDrift() throws {
        let directory = temporaryDirectory()
        let trace = SnapshotSettleTrace(directory: directory, identifier: "drift")
        let original = sampleImage(patch: false)
        trace.record(image: original, pass: 1, seconds: 0.1)
        trace.record(image: original, pass: 2, seconds: 0.2)
        trace.record(image: sampleImage(patch: true), pass: 3, seconds: 0.3)
        let manifestURL = try trace.write(outcome: .settled, passes: 3)
        defer { removeDirectory(directory) }
        let manifest = try readManifest(manifestURL)
        let frames = try #require(manifest["frames"] as? [[String: Any]])
        #expect(frames[0]["identicalToPreviousSample"] == nil)
        #expect(frames[1]["identicalToPreviousSample"] as? Bool == true)
        #expect(frames[2]["identicalToPreviousSample"] as? Bool == false)

        let output = manifestURL.deletingLastPathComponent()
        let saved = try Data(contentsOf: output.appendingPathComponent("0001.png"))
        #expect(saved == original.pngData())
        let lines = try String(
            contentsOf: output.appendingPathComponent("diffs.jsonl"),
            encoding: .utf8,
        )
        .split(separator: "\n")
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        let difference = try #require(JSONSerialization
            .jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(difference["differingPixels"] as? Int == 1)
        #expect(difference["maxChannelDelta"] as? Int == 1)
        #expect(difference["region"] as? [Int] == [3, 2, 1, 1])
    }

    @Test func preservesAnOutcomeWhenNoFrameCanBeSampled() throws {
        let directory = temporaryDirectory()
        let trace = SnapshotSettleTrace(directory: directory, identifier: "empty")
        trace.record(image: nil, pass: 1, seconds: 0.1)
        let manifestURL = try trace.write(outcome: .starved(passes: 1, cap: 0.2), passes: 1)
        defer { removeDirectory(directory) }
        let manifest = try readManifest(manifestURL)
        #expect(manifest["outcome"] as? String == "starved(passes: 1, cap: 0.2)")
        #expect(manifest["passes"] as? Int == 1)
        #expect((manifest["frames"] as? [Any])?.isEmpty == true)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotSettleTraceTests-\(UUID().uuidString)")
    }

    private func removeDirectory(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record(error)
        }
    }

    private func readManifest(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func sampleImage(patch: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
            .image { context in
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                if patch {
                    UIColor(white: 1 / 255, alpha: 1).setFill()
                    context.fill(CGRect(x: 3, y: 2, width: 1, height: 1))
                }
            }
    }
}
