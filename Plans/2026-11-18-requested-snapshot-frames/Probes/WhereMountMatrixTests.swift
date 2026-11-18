import SnapshotKit
import Testing
@testable import WhereUI

@MainActor
struct WhereMountMatrixTests {
    @Test func compareSingleMounts() async throws {
        try await MountMatrix.run(
            bundle: "WhereUISnapshotTests",
            suites: [
                .init(
                    file: "FlightStatusBannerSnapshotTests.swift",
                    test: "flightStatusBanner()",
                    cases: FlightStatusBanner.snapshots,
                ),
                .init(
                    file: "TodayWidgetViewSnapshotTests.swift",
                    test: "todayWidget()",
                    cases: TodayWidgetView.snapshots,
                ),
                .init(
                    file: "YearTotalsWidgetViewSnapshotTests.swift",
                    test: "yearTotalsWidget()",
                    cases: YearTotalsWidgetView.snapshots,
                ),
                .init(
                    file: "TodayInlineAccessoryViewSnapshotTests.swift",
                    test: "todayInlineAccessory()",
                    cases: TodayInlineAccessoryView.snapshots,
                ),
                .init(
                    file: "TodayCircularAccessoryViewSnapshotTests.swift",
                    test: "todayCircularAccessory()",
                    cases: TodayCircularAccessoryView.snapshots,
                ),
                .init(
                    file: "YearTotalsRectangularAccessoryViewSnapshotTests.swift",
                    test: "yearTotalsRectangularAccessory()",
                    cases: YearTotalsRectangularAccessoryView.snapshots,
                ),
                .init(
                    file: "CalendarContentViewSnapshotTests.swift",
                    test: "calendarContent()",
                    cases: CalendarContentView.measuredSnapshots,
                ),
                .init(
                    file: "YearViewSnapshotTests.swift",
                    test: "year()",
                    cases: YearView.snapshots,
                ),
            ],
            sourcePath: #filePath,
        )
    }
}
