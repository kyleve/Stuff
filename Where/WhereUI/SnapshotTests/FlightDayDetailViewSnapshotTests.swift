import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `FlightDayDetailView`; the matrix is declared via
/// `SnapshotProviding` in `FlightDayDetailView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct FlightDayDetailViewSnapshotTests {
    @Test func flightDayDetail() async {
        await assertSnapshots(of: FlightDayDetailView.self)
    }
}
