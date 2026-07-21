import RegionKit
import SnapshotKitTesting
import SwiftDataInspector
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

/// Image snapshot for the DEBUG generic `SwiftDataInspector` surface (a
/// third-party `SwiftDataInspector` view, so no WhereUI `SnapshotProviding`
/// conformance — the inline overload is used), recorded against a live, seeded
/// in-memory store.
@MainActor
@Suite(.snapshots(record: .missing))
struct SwiftDataInspectorSnapshotTests {
    @Test func swiftDataInspector() async throws {
        let services = PreviewSupport.previewServices()
        // Seed one real row so the inspector renders live content, not an empty
        // store (mirrors SwiftDataInspectorWiringTests).
        try await services.journal.addManualDay(
            date: Date(timeIntervalSince1970: 1_770_000_000),
            regions: [.california],
            audit: nil,
        )
        let session = WhereSession(services: services)
        let configuration = try #require(session.swiftDataInspectorConfiguration)
        let view = NavigationStack {
            SwiftDataInspectorView(configuration: configuration)
        }
        .whereBroadwayRoot()
        await assertSnapshots(
            of: view,
            named: "SwiftDataInspector",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPhone],
                colorSchemes: [.light, .dark],
            ),
        )
    }
}
