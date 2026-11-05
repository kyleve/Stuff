import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct IssueSearchModelTests {
    @Test func explicitSearchReportsHistoricalWorkAndPreservesRefreshFailure() async throws {
        let store = try TestStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 2)))
        let services = FlightReviewTestSupport.services(store: store, now: now)
        try await FlightReviewTestSupport.seed(into: store, includeArrival: true)
        let report = YearReportModel(
            services: services,
            selectedYear: 2028,
            preferences: makePreferences(),
            now: { now },
        )
        let search = IssueSearchModel(report: report)
        await search.scan()
        guard case let .complete(count) = search.state else {
            Issue.record("Expected a completed historical search")
            return
        }
        #expect(count == report.dataIssueCount)
        #expect(count > 0)
        #expect(report.correctionReviews.contains { $0.day.day.year == 2026 })
        await store.failSamples()
        await search.scan()
        guard case let .failed(error) = search.state else {
            Issue.record("A retained count must not become a successful search result")
            return
        }
        #expect(error is SampleReadFailure)
        #expect(report.dataIssueCount == count)
    }

    @Test(arguments: [false, true])
    func cancelledOrInvalidatedSearchCannotPublish(cancel: Bool) async throws {
        let store = try TestStore()
        let services = FlightReviewTestSupport.services(
            store: store,
            now: FlightReviewTestSupport.date(hour: 18),
        )
        let report = YearReportModel(
            services: services,
            selectedYear: 2026,
            preferences: makePreferences(),
        )
        let search = IssueSearchModel(report: report)
        let hold = ResolutionScanSuspension()
        await services.resolution.setBeforeHistoricalPublicationForTesting {
            await hold.suspendFirst()
        }
        let pending = Task { await search.scan() }
        try await CompatibilityLaunchFixture.waitUntil { hold.entered }
        if cancel { pending.cancel() } else { search.invalidate() }
        hold.resume()
        await pending.value
        guard case .idle = search.state else {
            Issue.record("An interrupted search must not publish a completed count")
            return
        }
    }
}
