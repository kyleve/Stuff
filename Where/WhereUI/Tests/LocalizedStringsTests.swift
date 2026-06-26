import Foundation
import StuffCore
import Testing
@testable import WhereUI

/// Verifies the WhereUI string catalog is actually wired up (deferred lookups
/// resolve to English values, not raw keys), that plural variations are
/// honored, and that years are formatted without a grouping separator.
struct LocalizedStringsTests {
    @Test func simpleKeysResolveToCatalogValues() {
        #expect(LocalizedStrings.Tabs.elsewhere.localized() == "Elsewhere")
        #expect(LocalizedStrings.Primary.title.localized() == "Where")
        #expect(LocalizedStrings.Common.loadErrorTitle.localized() == "Couldn't load your year")
        #expect(LocalizedStrings.Common.ok.localized() == "OK")
        #expect(LocalizedStrings.ManualEntry.saveErrorTitle.localized() == "Couldn't save that day")
        #expect(LocalizedStrings.Primary.elsewhereOnlyTitle
            .localized() == "Nothing in your headline spots")
    }

    @Test func explicitLocaleConfigResolvesAgainstThatLocale() {
        let english = LocalizationConfig(locale: Locale(identifier: "en"))
        #expect(LocalizedStrings.Tabs.primary.localized(english) == "Primary")
    }

    @Test func elsewhereOnlyDescriptionUsesPluralVariations() {
        #expect(
            LocalizedStrings.Primary.elsewhereOnlyDescription(count: 1).localized()
                ==
                "1 day logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
        )
        #expect(
            LocalizedStrings.Primary.elsewhereOnlyDescription(count: 9).localized()
                ==
                "9 days logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
        )
    }

    @Test func dayCountUsesPluralVariations() {
        #expect(LocalizedStrings.Common.dayCount(1).localized() == "1 day")
        #expect(LocalizedStrings.Common.dayCount(5).localized() == "5 days")
    }

    @Test func dayUnitUsesPluralVariations() {
        #expect(LocalizedStrings.Common.dayUnit(1).localized() == "day")
        #expect(LocalizedStrings.Common.dayUnit(2).localized() == "days")
    }

    @Test func yearsAreFormattedWithoutGroupingSeparator() {
        #expect(LocalizedStrings.Timeline.title(year: 2026).localized() == "Timeline · 2026")
        #expect(LocalizedStrings.Settings.Data.erase(year: 2026).localized() == "Erase 2026 data")
    }

    @Test func interpolatedStringsSubstituteArguments() {
        #expect(LocalizedStrings.Primary.emptyTitle(year: 2024)
            .localized() == "No travels logged for 2024")
    }

    @Test func missingBannerCompactUsesPluralVariations() {
        #expect(LocalizedStrings.MissingBanner.compact(count: 1)
            .localized() == "1 day needs a location")
        #expect(LocalizedStrings.MissingBanner.compact(count: 8)
            .localized() == "8 days need a location")
    }

    @Test func relabelStringsResolveToCatalogValues() {
        #expect(LocalizedStrings.Relabel.title.localized() == "Fix this day")
        #expect(LocalizedStrings.Relabel.regionsHeader.localized() == "Where were you?")
        #expect(LocalizedStrings.Relabel.reset.localized() == "Reset to GPS-detected location")
        #expect(LocalizedStrings.Secondary.Region.emptyTitle.localized() == "Nothing to fix")
        #expect(LocalizedStrings.Secondary.Region.current(regions: "California")
            .localized() == "Counts as California")
    }

    @Test func backupStringsResolveToCatalogValues() {
        #expect(LocalizedStrings.Settings.Backup.header.localized() == "Backup")
        #expect(LocalizedStrings.Settings.Backup.export.localized() == "Export data")
        #expect(LocalizedStrings.Settings.Backup.importData.localized() == "Import data")
        #expect(LocalizedStrings.Settings.Backup.merge.localized() == "Merge")
        #expect(LocalizedStrings.Settings.Backup.replace.localized() == "Replace all")
        #expect(LocalizedStrings.Settings.Backup.importedTitle.localized() == "Backup imported")
    }

    @Test func backupImportedMessageSubstitutesAllThreeCountsInOrder() {
        #expect(
            LocalizedStrings.Settings.Backup.importedMessage(samples: 3, evidence: 2, manualDays: 5)
                .localized()
                ==
                "Imported 3 location samples, 2 pieces of evidence, and 5 manual days.",
        )
    }

    @Test func debugSettingsStringsResolveToCatalogValues() {
        #expect(LocalizedStrings.Settings.Debug.header.localized() == "Developer")
        #expect(LocalizedStrings.Settings.Debug.logsLink.localized() == "Logs")
        #expect(LocalizedStrings.Settings.Debug.logsTitle.localized() == "Logs")
        #expect(LocalizedStrings.Settings.Debug.inspectorLink.localized() == "SwiftData Inspector")
        #expect(LocalizedStrings.Settings.Debug.inspectorTitle.localized() == "SwiftData")
        #expect(
            LocalizedStrings.Settings.Debug.footer.localized()
                == "On-device logs and data tools. Debug builds only.",
        )
    }
}
