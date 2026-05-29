import Testing
@testable import WhereUI

/// Verifies the WhereUI string catalog is actually wired up (lookups resolve to
/// English values, not raw keys), that plural variations are honored, and that
/// years are formatted without a grouping separator.
struct StringsTests {
    @Test func simpleKeysResolveToCatalogValues() {
        #expect(Strings.primaryTitle == "Where")
        #expect(Strings.tabElsewhere == "Elsewhere")
        #expect(Strings.loadErrorTitle == "Couldn't load your year")
    }

    @Test func dayCountUsesPluralVariations() {
        #expect(Strings.dayCount(1) == "1 day")
        #expect(Strings.dayCount(5) == "5 days")
    }

    @Test func dayUnitUsesPluralVariations() {
        #expect(Strings.dayUnit(1) == "day")
        #expect(Strings.dayUnit(2) == "days")
    }

    @Test func yearsAreFormattedWithoutGroupingSeparator() {
        #expect(Strings.timelineTitle(year: 2026) == "Timeline · 2026")
        #expect(Strings.settingsDataErase(year: 2026) == "Erase 2026 data")
    }

    @Test func interpolatedStringsSubstituteArguments() {
        #expect(Strings.primaryEmptyTitle(year: 2024) == "No travels logged for 2024")
        #expect(Strings.primaryHeaderSubtitle(count: 1) == "1 day on the map so far")
        #expect(Strings.primaryHeaderSubtitle(count: 12) == "12 days on the map so far")
    }
}
