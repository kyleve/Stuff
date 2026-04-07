import Testing
import WhereCore
import WhereData

@Test
func yearProgressControllerBuildsSnapshot() async throws {
    let controller = YearProgressController()
    let years = await controller.availableYears()
    let year = try #require(years.last)

    let snapshot = await controller.snapshot(for: year)

    #expect(snapshot.year == year)
    #expect(snapshot.primarySummaries.count == 2)
    #expect(snapshot.secondarySummaries.contains { $0.jurisdiction == .unknown })
    #expect(snapshot.primarySummaries.first { $0.jurisdiction == .newYork }?.totalDays == 3)
    #expect(snapshot.secondarySummaries.first { $0.jurisdiction == .unknown }?.totalDays == 0)
    #expect(snapshot.trackingStatus == .healthy)
    #expect(!snapshot.recentDays.isEmpty)
}
