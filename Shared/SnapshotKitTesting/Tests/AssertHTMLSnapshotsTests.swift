@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct AssertHTMLSnapshotsTests {
    @Test func batchReloadsDocumentsAndResetsViewportAndAppearance() async throws {
        let phone = SnapshotConfiguration(
            layoutTraits: .phonePortrait,
            device: .fullContent(name: "phone", width: 120, minimumHeight: 60),
        )
        let tablet = SnapshotConfiguration(
            colorScheme: .dark,
            layoutTraits: .tabletPortrait,
            device: .fullContent(name: "tablet", width: 240, minimumHeight: 80),
        )
        let viewport = #"<meta name="viewport" content="width=device-width, initial-scale=1">"#
        let documents = [
            HTMLSnapshotDocument(
                html: """
                \(viewport)<style>body {margin:0;height:260px;background:lime}</style>
                <img alt="">
                """,
                name: "Tall",
                configurations: [phone],
            ),
            HTMLSnapshotDocument(
                html: """
                \(viewport)<style>:root {color-scheme:light dark; background:light-dark(red,blue)}
                body {margin:0}</style>
                """,
                name: "Short",
                configurations: [tablet, phone],
            ),
        ]
        let source: StaticString = "/tmp/SnapshotKitFixtureProbes/HTMLBatch.swift"
        let testName = UUID().uuidString
        try await withKnownIssue("Recording temporary references reports an issue for each image") {
            try await assertHTMLSnapshots(
                of: documents,
                record: .all,
                file: source,
                testName: testName,
            )
        } matching: { issue in
            issue.comments
                .contains {
                    $0.rawValue.hasPrefix("Record mode is on. Automatically recorded snapshot:")
                }
        }

        let scale = try #require(hostKeyWindow()).traitCollection.displayScale
        func checkImage(
            _ name: String,
            _ configuration: SnapshotConfiguration,
            size: CGSize,
        ) throws -> PixelSample {
            let url = snapshotReferenceURL(
                testFilePath: "\(source)",
                testName: testName,
                identifier: "\(name)_\(configuration.identifier)",
                configuration: configuration,
            )
            let image = try #require(UIImage(contentsOfFile: url.path))
            try FileManager.default.removeItem(at: url)
            let bitmap = try #require(image.cgImage)
            #expect(CGFloat(bitmap.width) == size.width * scale)
            #expect(CGFloat(bitmap.height) == size.height * scale)
            return image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        }
        let tall = try checkImage("Tall", phone, size: CGSize(width: 120, height: 260))
        #expect(tall.green > 0.9 && tall.red < 0.1)
        let dark = try checkImage("Short", tablet, size: CGSize(width: 240, height: 80))
        #expect(dark.blue > 0.9 && dark.red < 0.1)
        let light = try checkImage("Short", phone, size: CGSize(width: 120, height: 60))
        #expect(light.red > 0.9 && light.blue < 0.1)
    }

    @Test func rejectsFixedAndAccessibilityCaptures() async {
        for configuration in [
            SnapshotConfiguration(device: .iPhone),
            SnapshotConfiguration(device: .iPhoneFullContent, snapshotType: .accessibility),
        ] {
            await #expect(throws: (any Error).self) {
                try await loadHTMLSnapshotImage("<p>Fixture</p>", configuration: configuration)
            }
        }
    }

    @Test func cancelledCaptureDoesNotLoadWebKit() async {
        let task = Task {
            try await loadHTMLSnapshotImage(
                "<p>Fixture</p>",
                configuration: .init(device: .iPhoneFullContent),
            )
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
