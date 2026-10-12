import Foundation
@_spi(Testing) import SnapshotKitTesting
import Testing
import UIKit

/// Covers the reference comparison that describes *how* a capture differs.
@MainActor
struct SnapshotReferenceDiffTests {
    @Test func identicalBytesShortCircuit() throws {
        let png = try #require(solidImage(.red, size: CGSize(width: 8, height: 8)).pngData())
        let url = try write(png, named: "identical.png")
        #expect(compareAgainstReference(capturedPNG: png, referenceURL: url) == .identicalBytes)
    }

    @Test func missingReferenceIsReportedRatherThanTreatedAsAMatch() throws {
        let png = try #require(solidImage(.red, size: CGSize(width: 4, height: 4)).pngData())
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).png")
        #expect(
            compareAgainstReference(capturedPNG: png, referenceURL: url) == .referenceMissing(url),
        )
    }

    @Test func differingSizesAreIncomparableRatherThanADiff() throws {
        let small = try #require(solidImage(.red, size: CGSize(width: 4, height: 4)).pngData())
        let large = try #require(solidImage(.red, size: CGSize(width: 8, height: 8)).pngData())
        let url = try write(large, named: "large.png")
        guard case let .incomparable(reason) = compareAgainstReference(
            capturedPNG: small,
            referenceURL: url,
        ) else {
            Issue.record("expected a size mismatch to be incomparable")
            return
        }
        #expect(reason.contains("sizes differ"))
    }

    @Test func magnitudeLocalizesTheChangedRegion() throws {
        let size = CGSize(width: 20, height: 20)
        let reference = try #require(solidImage(.black, size: size).pngData())
        let url = try write(reference, named: "region.png")
        // A 5x4 white patch at (3, 2) on an otherwise black field.
        let captured = try #require(
            solidImage(.black, size: size, patch: CGRect(x: 3, y: 2, width: 5, height: 4))
                .pngData(),
        )

        guard case let .differs(magnitude) = compareAgainstReference(
            capturedPNG: captured,
            referenceURL: url,
        ) else {
            Issue.record("expected a patched image to differ")
            return
        }
        #expect(magnitude.changedRegion == CGRect(x: 3, y: 2, width: 5, height: 4))
        #expect(magnitude.differingPixels == 20)
        #expect(magnitude.totalPixels == 400)
        #expect(magnitude.differingFraction == 0.05)
        // Black to white is the full range, which is what separates a moved
        // region from drifted antialiasing at the same pixel count.
        #expect(magnitude.maxChannelDelta == 255)
    }

    @Test func reportEmitsNothingForAByteIdenticalCapture() {
        #expect(
            SnapshotDiffReporting.line(
                describing: .identicalBytes,
                identifier: "same",
                reference: URL(fileURLWithPath: "/ref.png"),
            ) == nil,
        )
    }

    /// Asks for the payload rather than calling `report(...)`, which would *print*
    /// a `SNAPSHOT_DIFF` line — and `./test --review` recovers diffs by grepping
    /// those out of the run logs, so this fixture's imaginary reference would be
    /// listed among the real captures. It sorted to the top, too, since the
    /// numbers below are borrowed from a genuine regression.
    @Test(arguments: ["/refs/thing.case_dark.png", "/refs/other/thing.case_ax5.png"])
    func reportDescribesADifferenceAsJSON(referencePath: String) throws {
        let magnitude = SnapshotDiffMagnitude(
            differingPixels: 7430,
            totalPixels: 3_162_132,
            maxChannelDelta: 203,
            changedRegion: CGRect(x: 85, y: 2394, width: 1037, height: 144),
        )
        let json = try #require(
            SnapshotDiffReporting.line(
                describing: .differs(magnitude),
                identifier: "case_dark",
                reference: URL(fileURLWithPath: referencePath),
            ),
        )
        let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let line = try #require(decoded)
        #expect(line["id"] as? String == "case_dark")
        #expect(line["outcome"] as? String == "differs")
        #expect(line["differingPixels"] as? Int == 7430)
        #expect(line["maxChannelDelta"] as? Int == 203)
        #expect(line["region"] as? [Int] == [85, 2394, 1037, 144])
        // The path is what makes a diff attributable — seven suites here have an
        // `Empty` case, so the identifier alone names none of them.
        #expect(line["reference"] as? String == referencePath)
    }

    @Test(arguments: [
        (value: String?.none, expected: false),
        (value: "0", expected: false),
        (value: "no", expected: false),
        (value: "1", expected: true),
        (value: "true", expected: true),
    ])
    func environmentValueEnablesReporting(value: String?, expected: Bool) {
        #expect(SnapshotDiffReporting.isEnabled(forEnvironmentValue: value) == expected)
    }

    // MARK: - Support

    private func solidImage(_ color: UIColor, size: CGSize, patch: CGRect? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let patch {
                UIColor.white.setFill()
                context.fill(patch)
            }
        }
    }

    private func write(_ data: Data, named name: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SnapshotReferenceDiffTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
