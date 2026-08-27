import Foundation
@_spi(Testing) import SnapshotKitTesting
import Testing
import UIKit

/// Covers the reference comparison that describes *how* a capture differs.
///
/// The reference-path derivation mirrors swift-snapshot-testing's own layout,
/// which nothing public exposes, so it is pinned against a reference that
/// actually exists in this repo — if the library ever moves them, that test
/// fails rather than every capture quietly reporting "reference missing".
@MainActor
struct SnapshotReferenceDiffTests {
    @Test func referencePathMatchesTheLibraryLayout() {
        let url = snapshotReferenceURL(
            testFilePath: "/repo/Shared/Thing/SnapshotTests/ThingSnapshotTests.swift",
            testName: "thing()",
            identifier: "Loaded_iPhone_dark",
        )
        #expect(url.path == """
        /repo/Shared/Thing/SnapshotTests/__Snapshots__/ThingSnapshotTests/thing.Loaded_iPhone_dark.png
        """)
    }

    @Test func referencePathToleratesATestNameWithoutParentheses() {
        // `#function` supplies `thing()`, but a caller passing a bare name must
        // not produce a `thing().identifier.png` path.
        let url = snapshotReferenceURL(
            testFilePath: "/repo/T/Tests/TSnapshotTests.swift",
            testName: "thing",
            identifier: "iPhone",
        )
        #expect(url.lastPathComponent == "thing.iPhone.png")
    }

    @Test func referencePathSanitizesNamesLikeTheComparisonLibrary() {
        let url = snapshotReferenceURL(
            testFilePath: "/repo/T/Tests/TSnapshotTests.swift",
            testName: "flight activity()",
            identifier: "adsb.lol Source_iPhone",
        )
        #expect(url.lastPathComponent == "flight-activity.adsb-lol-Source_iPhone.png")
    }

    /// The derivation above is only useful if it lands on a real file. This
    /// repo's own Inspector reference is the fixture.
    @Test func derivedPathFindsAnActualReferenceInThisRepo() {
        let url = snapshotReferenceURL(
            testFilePath: inspectorTestFilePath,
            testName: "inspectorSurfaces()",
            identifier: "SwiftData_iPhone",
        )
        #expect(
            FileManager.default.fileExists(atPath: url.path),
            """
            Derived reference path does not exist: \(url.path). \
            swift-snapshot-testing's reference layout has moved, so every capture \
            would report `referenceMissing` instead of comparing.
            """,
        )
    }

    @Test func derivedPathFindsAReferenceWithASanitizedIdentifier() {
        let url = snapshotReferenceURL(
            testFilePath: throwProjectionTestFilePath,
            testName: "projectionSurface()",
            identifier: "Flight Activity Map_16x9",
        )
        #expect(
            FileManager.default.fileExists(atPath: url.path),
            "Derived sanitized reference path does not exist: \(url.path)",
        )
    }

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
    @Test func reportDescribesADifferenceAsJSON() throws {
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
                reference: URL(fileURLWithPath: "/refs/thing.case_dark.png"),
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
        #expect(line["reference"] as? String == "/refs/thing.case_dark.png")
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

    /// This file's sibling path to the Inspector suite, derived from
    /// `#filePath` so it survives the repo moving.
    private var inspectorTestFilePath: String {
        URL(fileURLWithPath: #filePath)
            // .../Shared/SnapshotKitTesting/Tests/ -> .../Shared/
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Inspector/SnapshotTests")
            .appendingPathComponent("InspectorSnapshotTests.swift")
            .path
    }

    private var throwProjectionTestFilePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Throw/ThrowUI/SnapshotTests")
            .appendingPathComponent("ProjectionSurfaceSnapshotTests.swift")
            .path
    }

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
