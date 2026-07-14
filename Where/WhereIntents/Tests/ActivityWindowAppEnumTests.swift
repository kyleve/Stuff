import Testing
import WhereCore
@testable import WhereIntents

/// `ActivityWindowAppEnum` round-trips losslessly with `RecentActivityWindow`.
struct ActivityWindowAppEnumTests {
    @Test func roundTripsEveryWindow() {
        for window in RecentActivityWindow.allCases {
            #expect(ActivityWindowAppEnum(window).window == window)
        }
    }

    @Test func coversEveryDomainCase() {
        let mapped = Set(ActivityWindowAppEnum.allCases.map(\.window))
        #expect(mapped == Set(RecentActivityWindow.allCases))
    }
}
