import Foundation
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct SnapshotReferenceURLTests {
    @Test func referenceGroupsContainTheirSpecialTraitDirectory() throws {
        let group = try #require(SnapshotReferenceGroup(rawValue: "flat"))
        let url = snapshotReferenceURL(
            testFilePath: "/repo/ThingSnapshotTests.swift",
            testName: "thing()",
            identifier: "Loaded",
            configuration: SnapshotConfiguration(contrast: .increased),
            referenceGroup: group,
        )
        #expect(url.path == "/repo/__Snapshots__/ThingSnapshotTests/flat/other/thing.Loaded.png")
        let annotations = snapshotReferenceURL(
            testFilePath: "/repo/ThingSnapshotTests.swift",
            testName: "thing()",
            identifier: "Loaded",
            configuration: SnapshotConfiguration(
                contrast: .increased,
                snapshotType: .accessibility,
            ),
            referenceGroup: group,
        )
        #expect(annotations.path == "/repo/__Snapshots__/ThingSnapshotTests/flat/thing.Loaded.png")
    }

    @Test(arguments: ["thing()", "thing"])
    func ordinaryReferenceKeepsItsExistingPath(testName: String) {
        let url = snapshotReferenceURL(
            testFilePath: "/repo/Shared/Thing/SnapshotTests/ThingSnapshotTests.swift",
            testName: testName,
            identifier: "Loaded_iPhone_dark",
            configuration: SnapshotConfiguration(colorScheme: .dark, device: .iPhone),
        )
        #expect(url.path == """
        /repo/Shared/Thing/SnapshotTests/__Snapshots__/ThingSnapshotTests/thing.Loaded_iPhone_dark.png
        """)
    }

    @Test(arguments: SnapshotConfiguration.combinations(
        devices: [
            .component,
            .iPhone,
            .iPad,
            .iPhoneNotched,
            .iPhoneFullContent,
            .iPadFullContent,
            .iPadFullContent2D,
            .fullContent(name: "contrast", width: 321),
        ],
        colorSchemes: [.light, .dark],
    ))
    func appearanceFrameAndNamesDoNotChangeTheDirectory(configuration: SnapshotConfiguration) {
        var configuration = configuration
        configuration.name = "ax5_contrast_rtl_bold"
        let url = snapshotReferenceURL(
            testFilePath: "/repo/ThingSnapshotTests.swift",
            testName: "thing()",
            identifier: configuration.identifier,
            configuration: configuration,
        )
        #expect(url.deletingLastPathComponent().path == "/repo/__Snapshots__/ThingSnapshotTests")
        #expect(url.lastPathComponent == "thing.\(configuration.identifier).png")
    }

    @Test(arguments: otherConfigurations)
    func specialTraitsUseOtherDirectory(configuration: SnapshotConfiguration) {
        let url = snapshotReferenceURL(
            testFilePath: "/repo/ThingSnapshotTests.swift",
            testName: "thing()",
            identifier: configuration.identifier,
            configuration: configuration,
        )
        #expect(url.deletingLastPathComponent()
            .path == "/repo/__Snapshots__/ThingSnapshotTests/other")
        #expect(url.lastPathComponent == "thing.\(configuration.identifier).png")
    }

    @Test(arguments: otherConfigurations + [
        SnapshotConfiguration(),
        SnapshotConfiguration(colorScheme: .dark),
    ])
    func annotationsAlwaysStayAtTheTopLevel(configuration: SnapshotConfiguration) {
        var configuration = configuration
        configuration.snapshotType = .accessibility
        let url = snapshotReferenceURL(
            testFilePath: "/repo/ThingSnapshotTests.swift",
            testName: "thing()",
            identifier: configuration.identifier,
            configuration: configuration,
        )
        #expect(url.deletingLastPathComponent().path == "/repo/__Snapshots__/ThingSnapshotTests")
        #expect(url.lastPathComponent == "thing.\(configuration.identifier).png")
    }

    @Test(arguments: [
        SnapshotConfiguration(device: .iPhone),
        SnapshotConfiguration(dynamicType: .accessibility5, device: .iPhone),
        SnapshotConfiguration(device: .iPhone, snapshotType: .accessibility),
    ])
    func derivedPathFindsExistingReferences(configuration: SnapshotConfiguration) {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = snapshotReferenceURL(
            testFilePath: repository.appendingPathComponent(
                "Where/WhereUI/SnapshotTests/DataSettingsViewSnapshotTests.swift",
            ).path,
            testName: "data()",
            identifier: "Default_\(configuration.identifier)",
            configuration: configuration,
        )
        #expect(FileManager.default.fileExists(atPath: url.path), "Missing reference: \(url.path)")
    }

    @Test(arguments: [
        SnapshotConfiguration(),
        SnapshotConfiguration(contrast: .increased),
        SnapshotConfiguration(dynamicType: .accessibility5, snapshotType: .accessibility),
    ])
    func recordingComparisonAndReviewShareTheResolvedPath(
        configuration: SnapshotConfiguration,
    ) throws {
        let fixture = try SnapshotReferenceTestFixture()
        defer { fixture.remove() }
        // Exercise the library's sanitization as well as both directory levels.
        let testName = "a readable test()"
        let identifier = "Case / \(configuration.identifier)"
        let reference = snapshotReferenceURL(
            testFilePath: fixture.testFilePath,
            testName: testName,
            identifier: identifier,
            configuration: configuration,
        )
        let image = fixture.image(.red)
        let png = try #require(image.pngData())
        let directory = reference.deletingLastPathComponent().path

        let missing = verifySnapshot(
            of: image,
            as: .image(),
            named: identifier,
            record: .never,
            snapshotDirectory: directory,
            testName: testName,
        )
        #expect(missing?.contains("No reference was found on disk") == true)
        #expect(FileManager.default.fileExists(atPath: reference.path) == false)

        let recorded = verifySnapshot(
            of: image,
            as: .image(),
            named: identifier,
            record: .missing,
            snapshotDirectory: directory,
            testName: testName,
        )
        #expect(recorded?.contains("Automatically recorded snapshot") == true)
        #expect(try Data(contentsOf: reference) == png)
        #expect(compareAgainstReference(capturedPNG: png, referenceURL: reference) ==
            .identicalBytes)

        let matched = verifySnapshot(
            of: image,
            as: .image(),
            named: identifier,
            record: .never,
            snapshotDirectory: directory,
            testName: testName,
        )
        #expect(matched == nil)

        let changedImage = fixture.image(.blue)
        let mismatch = verifySnapshot(
            of: changedImage,
            as: .image(),
            named: identifier,
            record: .never,
            snapshotDirectory: directory,
            testName: testName,
        )
        #expect(mismatch?.contains("does not match reference") == true)
        #expect(try Data(contentsOf: reference) == png)
        let comparison = try compareAgainstReference(
            capturedPNG: #require(changedImage.pngData()),
            referenceURL: reference,
        )
        guard case .differs = comparison else {
            Issue.record("The review comparison must find the changed image at \(reference.path)")
            return
        }
        let report = try #require(SnapshotDiffReporting.line(
            describing: comparison,
            identifier: identifier,
            reference: reference,
        ))
        let payload = try #require(
            JSONSerialization.jsonObject(with: Data(report.utf8)) as? [String: Any],
        )
        #expect(payload["reference"] as? String == reference.path)
    }

    private static let otherConfigurations: [SnapshotConfiguration] = [
        .init(dynamicType: .xSmall),
        .init(dynamicType: .small),
        .init(dynamicType: .medium),
        .init(dynamicType: .xLarge),
        .init(dynamicType: .xxLarge),
        .init(dynamicType: .xxxLarge),
        .init(dynamicType: .accessibility1),
        .init(dynamicType: .accessibility2),
        .init(dynamicType: .accessibility3),
        .init(dynamicType: .accessibility4),
        .init(dynamicType: .accessibility5),
        .init(contrast: .increased),
        .init(layoutDirection: .rightToLeft),
        .init(legibilityWeight: .bold),
        .init(
            colorScheme: .dark,
            dynamicType: .accessibility5,
            contrast: .increased,
            layoutDirection: .rightToLeft,
            legibilityWeight: .bold,
            device: .iPadFullContent,
            name: "Combined",
        ),
    ]
}
