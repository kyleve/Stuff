import SnapshotKitTesting
import Testing
@testable import WhereUI

@MainActor
struct CalendarContentViewSnapshotTests {
    @Test func calendarContentLightDark() async {
        await assertSnapshots(
            of: WhereLightDarkSnapshots<CalendarContentView>.self,
            testName: "calendarContent()",
        )
    }

    @Test func calendarContentExtended() async {
        await assertSnapshots(
            of: WhereExtendedSnapshots<CalendarContentView>.self,
            testName: "calendarContent()",
        )
    }
}

extension CalendarContentView: WhereThemeSnapshotGate {
    static var lightDarkCases: Set<String> {
        ["WithData", "YearOverview", "YearOverviewPlannedStays"]
    }
}
