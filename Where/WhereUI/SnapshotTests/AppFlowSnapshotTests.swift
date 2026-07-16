import RegionKit
import SnapshotKitTesting
import SwiftDataInspector
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

/// Image snapshots for the app-flow surfaces: launch splash, onboarding, the
/// root scene, and the DEBUG SwiftData inspector (recorded against a live,
/// seeded in-memory store).
@MainActor
@Suite(.snapshots(record: .missing))
struct AppFlowSnapshotTests {
    @Test func launchSplash() async {
        await assertSnapshots(of: LaunchSplashView.self)
    }

    @Test func onboarding() async {
        await assertSnapshots(of: OnboardingView.self)
    }

    @Test func root() async {
        await assertSnapshots(of: RootView.self)
    }

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
