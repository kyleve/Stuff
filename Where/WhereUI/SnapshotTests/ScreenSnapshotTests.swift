import LogViewerUI
import SnapshotKitTesting
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

/// Image snapshots for the top-level WhereUI screens. Each screen declares its
/// matrix via `SnapshotProviding` (see `ScreenSnapshots.swift` in WhereUI), so a
/// test is a single `assertSnapshots(of:)` call; views without a conformance
/// (third-party `LogViewer`) use the inline overload.
@MainActor
@Suite(.snapshots(record: .missing))
struct ScreenSnapshotTests {
    @Test func primary() async {
        await assertSnapshots(of: PrimaryView.self)
    }

    @Test func secondary() async {
        await assertSnapshots(of: SecondaryView.self)
    }

    @Test func settings() async {
        await assertSnapshots(of: SettingsView.self)
    }

    @Test func resolution() async {
        await assertSnapshots(of: ResolutionView.self)
    }

    @Test func regionDays() async {
        await assertSnapshots(of: RegionDaysView.self)
    }

    @Test func regionMap() async {
        await assertSnapshots(of: RegionMapView.self)
    }

    @Test func dayRelabel() async {
        await assertSnapshots(of: DayRelabelView.self)
    }

    @Test func recentActivity() async {
        await assertSnapshots(of: RecentActivitySummaryView.self)
    }

    @Test func presenceTimeline() async {
        await assertSnapshots(of: PresenceTimelineView.self)
    }

    @Test func calendar() async {
        await assertSnapshots(of: CalendarView.self)
    }

    @Test func appIcon() async {
        await assertSnapshots(of: AppIconView.self)
    }

    @Test func loggedDays() async {
        await assertSnapshots(of: LoggedDaysView.self)
    }

    @Test func manualDay() async {
        await assertSnapshots(of: ManualDayView.self)
    }

    @Test func developerTools() async {
        await assertSnapshots(of: DeveloperToolsView.self)
    }

    @Test func developerOverlay() async {
        await assertSnapshots(of: DeveloperOverlay.self)
    }

    @Test func debugLogViewer() async {
        let viewer = NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: WhereLog.store, title: "Logs"))
        }
        .whereBroadwayRoot()
        await assertSnapshots(
            of: viewer,
            named: "DebugLogViewer",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPhone],
                colorSchemes: [.light, .dark],
            ),
        )
    }
}
