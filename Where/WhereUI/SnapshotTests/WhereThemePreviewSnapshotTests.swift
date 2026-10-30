import SnapshotKit
import SnapshotKitTesting
import SwiftUI
import Testing
@testable import WhereUI

@MainActor
struct WhereThemePreviewSnapshotTests {
    @Test func seasonalDocuments() async throws {
        for example in WhereThemeExamples.allCases {
            let prepared = try example.prepare()
            await assertSnapshots(
                of: WhereThemePreview(theme: prepared),
                named: example.rawValue,
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPhone],
                    colorSchemes: [.light, .dark],
                    snapshotTypes: [
                        .standard,
                        .accessibility,
                    ],
                ),
            )
        }
    }
}
