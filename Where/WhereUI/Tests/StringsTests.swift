import RegionKit
import Testing
import WhereCore
@testable import WhereUI

/// Verifies the WhereUI string catalog is actually wired up (lookups resolve to
/// English values, not raw keys), that plural variations are honored, and that
/// years are formatted without a grouping separator.
struct StringsTests {
    @Test func simpleKeysResolveToCatalogValues() {
        #expect(Strings.tabElsewhere == "Elsewhere")
        #expect(Strings.loadErrorTitle == "Couldn't load your year")
        #expect(Strings.commonOK == "OK")
        #expect(Strings.manualSaveErrorTitle == "Couldn't save that day")
        #expect(Strings.primaryElsewhereOnlyTitle == "Nothing in your headline spots")
    }

    @Test func elsewhereOnlyDescriptionUsesPluralVariations() {
        #expect(
            Strings.primaryElsewhereOnlyDescription(count: 1)
                ==
                "1 day logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
        )
        #expect(
            Strings.primaryElsewhereOnlyDescription(count: 9)
                ==
                "9 days logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
        )
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
        #expect(Strings.calendarTitle(year: 2026) == "Calendar · 2026")
        #expect(Strings.settingsDataErase(year: 2026) == "Erase 2026 data")
    }

    @Test func calendarStringsResolveToCatalogValues() {
        #expect(Strings.primaryCalendar == "Calendar")
        #expect(Strings
            .calendarUnavailableDescription == "Your year data isn't available right now.")
    }

    @Test func calendarRegionTitleFormatsRegionAndGroupingFreeYear() {
        #expect(Strings.calendarRegionTitle(region: .california, year: 2026) == "California · 2026")
    }

    @Test func interpolatedStringsSubstituteArguments() {
        #expect(Strings.primaryEmptyTitle(year: 2024) == "No travels logged for 2024")
    }

    @Test func missingBannerCompactUsesPluralVariations() {
        #expect(Strings.missingBannerCompact(count: 1) == "1 day needs a location")
        #expect(Strings.missingBannerCompact(count: 8) == "8 days need a location")
    }

    @Test func relabelStringsResolveToCatalogValues() {
        #expect(Strings.relabelTitle == "Fix this day")
        #expect(Strings.relabelRegionsHeader == "Where were you?")
        #expect(Strings.relabelReset == "Reset to GPS-detected location")
        #expect(Strings.secondaryRegionEmptyTitle == "Nothing to fix")
        #expect(Strings.secondaryRegionCurrent(regions: "California") == "Counts as California")
    }

    @Test func backupStringsResolveToCatalogValues() {
        #expect(Strings.settingsBackupHeader == "Backup")
        #expect(Strings.settingsBackupExport == "Export data")
        #expect(Strings.settingsBackupImport == "Import data")
        #expect(Strings.settingsBackupMerge == "Merge")
        #expect(Strings.settingsBackupReplace == "Replace all")
        #expect(Strings.settingsBackupImportedTitle == "Backup imported")
    }

    @Test func backupImportedMessageSubstitutesAllCountsInOrder() {
        #expect(
            Strings.settingsBackupImportedMessage(
                samples: 3,
                evidence: 2,
                manualDays: 5,
                dismissedIssues: 4,
            )
                ==
                "Imported 3 location samples, 2 pieces of evidence, 5 manual days, and 4 dismissed issues.",
        )
    }

    @Test func debugSettingsStringsResolveToCatalogValues() {
        #expect(Strings.settingsDebugHeader == "Developer")
        #expect(Strings.settingsDebugLogsLink == "Logs")
        #expect(Strings.settingsDebugLogsTitle == "Logs")
        #expect(Strings.settingsDebugInspectorLink == "SwiftData Inspector")
        #expect(Strings.settingsDebugInspectorTitle == "SwiftData")
        #expect(Strings.settingsDebugRegionMapLink == "Region map")
        #expect(
            Strings.settingsDebugFooter
                == "On-device logs and data tools. Debug builds only.",
        )
    }

    @Test func regionMapStringsResolveToCatalogValues() {
        #expect(Strings.regionMapTitle == "Region Map")
        #expect(Strings.regionMapKindPicker == "Geometry")
        #expect(Strings.regionMapKind(.attribution) == "Attribution")
        #expect(Strings.regionMapKind(.source) == "Source")
        #expect(Strings.regionMapLegendHeader == "Features")
        #expect(Strings.regionMapShowAll == "Show all")
        #expect(Strings.regionMapMapAccessibility == "Map of region boundaries")
        #expect(Strings.regionMapLoadErrorTitle == "Couldn't load regions")
        #expect(Strings.regionMapEmptyTitle == "No regions")
        #expect(
            Strings.regionMapEmptyDescription == "No region geometry was found in the bundle.",
        )
        #expect(
            Strings.regionMapKindFooter(.attribution)
                == "The simplified polygons the app uses to attribute coordinates today.",
        )
        #expect(
            Strings.regionMapKindFooter(.source)
                ==
                "Every feature decoded straight from the bundled GeoJSON, at full authored fidelity.",
        )
    }
}
