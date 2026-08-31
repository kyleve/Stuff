import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct LocationsPlanningModelTests {
    @Test func successfulClearRemovesTheActivePlan() async throws {
        let (forecasts, _) = try makeForecasts()
        try await forecasts.set(region: .newYork, through: Self.departureDate)
        let model = LocationsPlanningModel()

        await model.clear(using: forecasts.clear)

        #expect(forecasts.activePlannedStay == nil)
        #expect(model.isClearing == false)
        #expect(model.presentedFailure == nil)
    }

    @Test func failedClearPreservesThePlanAndPresentsTheFailure() async throws {
        let (forecasts, store) = try makeForecasts()
        try await forecasts.set(region: .newYork, through: Self.departureDate)
        await store.failPlannedStays()
        let model = LocationsPlanningModel()

        await model.clear(using: forecasts.clear)

        #expect(forecasts.activePlannedStay?.region == .newYork)
        #expect(model.isClearing == false)
        #expect(model.presentedFailure != nil)
        #expect(model.isShowingError)
    }

    @Test func dismissingTheFailureReturnsToIdle() async {
        let model = LocationsPlanningModel()
        let error = NSError(
            domain: "LocationsPlanningModelTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Clear failed"],
        )

        await model.clear { throw error }
        model.isShowingError = false

        #expect(model.presentedFailure == nil)
        #expect(model.isShowingError == false)
    }

    @Test func duplicateClearIsIgnoredWhileTheFirstIsRunning() async {
        let model = LocationsPlanningModel()
        var starts = 0
        var continuation: CheckedContinuation<Void, Never>?

        let firstClear = Task { @MainActor in
            await model.clear {
                starts += 1
                await withCheckedContinuation { continuation = $0 }
            }
        }
        while continuation == nil {
            await Task.yield()
        }

        await model.clear { starts += 1 }

        #expect(starts == 1)
        continuation?.resume()
        await firstClear.value
        #expect(model.isClearing == false)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static let now = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 15, hour: 12),
    )!

    private static let departureDate = calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 15),
    )!

    private func makeForecasts() throws -> (LocationForecastModel, TestStore) {
        let store = try TestStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            now: { Self.now },
        )
        return (
            LocationForecastModel(
                services: services,
                calendar: Self.calendar,
                now: { Self.now },
            ),
            store,
        )
    }
}
