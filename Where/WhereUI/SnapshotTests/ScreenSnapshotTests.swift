@_spi(Testing) import LogKit
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

    @Test func flightDayDetail() async {
        await assertSnapshots(of: FlightDayDetailView.self)
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
            LogViewer(configuration: LogViewerConfiguration(
                store: Self.frozenLogStore(),
                title: "Logs",
            ))
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

    /// A frozen log buffer for the viewer snapshot — fixed entries with
    /// timestamps pinned around `PreviewSupport.referenceNow` — rather than the
    /// live shared `WhereLog` buffer, whose wall-clock timestamps and
    /// run-dependent lines made the image nondeterministic. Seeded through the
    /// production `LogStore` via its `@_spi(Testing)` record seam.
    private static func frozenLogStore() -> LogStore {
        struct FrozenLine {
            let level: LogLevel
            let category: WhereLog.Category
            let message: String
            /// Seconds before `referenceNow` this line was "logged".
            let age: TimeInterval
        }
        let lines = [
            FrozenLine(
                level: .info,
                category: .launch,
                message: "Launch sequence completed in 412ms.",
                age: 347,
            ),
            FrozenLine(
                level: .debug,
                category: .swiftDataStore,
                message: "Committed 3 day records in one transaction.",
                age: 289,
            ),
            FrozenLine(
                level: .notice,
                category: .regionAttribution,
                message: "Rebuilt the attributor for 4 tracked regions.",
                age: 214,
            ),
            FrozenLine(
                level: .warning,
                category: .locationIngestor,
                message: "Skipped a sample with poor horizontal accuracy (312m).",
                age: 158,
            ),
            FrozenLine(
                level: .error,
                category: .backupService,
                message: "Backup export failed: the archive directory is unwritable.",
                age: 96,
            ),
            FrozenLine(
                level: .info,
                category: .session,
                message: "Year report refreshed for 2026.",
                age: 41,
            ),
        ]
        let store = LogStore()
        for line in lines {
            store.record(LogEntry(
                date: PreviewSupport.referenceNow.addingTimeInterval(-line.age),
                level: line.level,
                subsystem: WhereLog.subsystem,
                category: line.category.rawValue,
                message: line.message,
            ))
        }
        return store
    }
}
