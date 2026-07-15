import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

/// Covers which manual entries each logged-days filter admits.
struct LoggedDaysFilterTests {
    private let additive = DayPresence(date: .now, in: .current, regions: [.california])
    private let authoritative = DayPresence(
        date: .now,
        in: .current,
        regions: [.newYork],
        isAuthoritative: true,
    )

    @Test func allAdmitsEveryEntry() {
        #expect(LoggedDaysFilter.all.matches(additive))
        #expect(LoggedDaysFilter.all.matches(authoritative))
    }

    @Test func loggedAdmitsOnlyAdditiveBackfills() {
        #expect(LoggedDaysFilter.logged.matches(additive))
        #expect(!LoggedDaysFilter.logged.matches(authoritative))
    }

    @Test func overriddenAdmitsOnlyAuthoritativeEntries() {
        #expect(!LoggedDaysFilter.overridden.matches(additive))
        #expect(LoggedDaysFilter.overridden.matches(authoritative))
    }
}
