import Foundation
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

    @Test func evidenceStringsResolveToCatalogValues() {
        #expect(Strings.primaryEvidence == "Evidence")
        #expect(Strings.evidenceEmptyTitle == "No evidence yet")
        #expect(Strings.evidenceAdd == "Add evidence")
        #expect(Strings.evidenceListTitle(year: 2026) == "Evidence · 2026")
        #expect(Strings.commonCancel == "Cancel")
    }

    @Test func loggedDaysStringsResolveToCatalogValues() {
        #expect(Strings.primaryLoggedDays == "Logged days")
        #expect(Strings.loggedDaysTitle(year: 2026) == "Logged Days · 2026")
        #expect(Strings.loggedDaysAdd == "Log a day")
        #expect(Strings.loggedDaysEmptyTitle == "No logged days")
        #expect(Strings.loggedDaysKindLogged == "Logged")
        #expect(Strings.loggedDaysKindOverridden == "Overridden")
        #expect(Strings.settingsYearLabel == "Year")
    }

    @Test func evidenceKindDisplayNamesResolve() {
        #expect(Strings.evidenceKind(.planeTicket) == "Plane ticket")
        #expect(Strings.evidenceKind(.boardingPass) == "Boarding pass")
        #expect(Strings.evidenceKind(.email) == "Email")
        #expect(Strings.evidenceKind(.other("Ferry ticket")) == "Ferry ticket")
        #expect(Strings.evidenceKind(.other(nil)) == "Other")
    }

    @Test func calendarDayAccessibilityAppendsEvidenceCue() throws {
        let date = try #require(Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2026, month: 3, day: 4)))
        let withEvidence = Strings.calendarDayAccessibility(
            date: date,
            regions: [.california],
            needsAttention: false,
            hasEvidence: true,
        )
        let without = Strings.calendarDayAccessibility(
            date: date,
            regions: [.california],
            needsAttention: false,
            hasEvidence: false,
        )
        #expect(withEvidence.hasSuffix("has evidence"))
        #expect(!without.hasSuffix("has evidence"))
    }

    @Test func developerToolsStringsResolveToCatalogValues() {
        #expect(Strings.developerTitle == "Developer")
        #expect(Strings.developerLogsLink == "Logs")
        #expect(Strings.developerLogsTitle == "Logs")
        #expect(Strings.developerInspectorLink == "SwiftData Inspector")
        #expect(Strings.developerInspectorTitle == "SwiftData")
        #expect(Strings.developerRegionMapLink == "Region map")
        #expect(
            Strings.developerFooter
                == "On-device logs and data tools. Debug builds only.",
        )
    }

    @Test func developerOverlayChromeStringsResolveToCatalogValues() {
        #expect(Strings.developerButtonLabel == "Developer tools")
        #expect(Strings.developerClose == "Close")
        #expect(Strings.developerExpand == "Enter full screen")
        #expect(Strings.developerCollapse == "Exit full screen")
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
