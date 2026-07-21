import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `CalendarView`; the matrix (including the full-year
/// full-content capture) is declared via `SnapshotProviding` in
/// `CalendarView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct CalendarViewSnapshotTests {
    @Test func calendar() async {
        await assertSnapshots(of: CalendarView.self)
    }
}
