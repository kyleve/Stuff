import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

/// Verifies the WhereUI localization is wired up end to end: that generated
/// String Catalog symbols resolve to their English catalog values (not raw
/// keys), that plural variations are honored, and that `WhereFormat` composes
/// symbols with runtime values correctly (grouping-free years, counts, region
/// names, enum switches).
struct WhereFormatTests {
    @Test func generatedSymbolsResolveToCatalogValues() {
        #expect(String(localized: .tabElsewhere) == "Elsewhere")
        #expect(String(localized: .commonLoadErrorTitle) == "Couldn't load your year")
        #expect(String(localized: .commonOk) == "OK")
        #expect(String(localized: .commonCancel) == "Cancel")
        #expect(String(localized: .manualSaveErrorTitle) == "Couldn't save that day")
        #expect(String(localized: .primaryElsewhereOnlyTitle) == "Nothing in your headline spots")
        #expect(String(localized: .primaryCalendar) == "Calendar")
        #expect(
            String(localized: .calendarUnavailableDescription)
                == "Your year data isn't available right now.",
        )
    }

    @Test func pluralElsewhereDescriptionHonorsVariations() {
        #expect(
            String(localized: .primaryElsewhereOnlyDescription(1))
                ==
                "1 day logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
        )
        #expect(
            String(localized: .primaryElsewhereOnlyDescription(9))
                ==
                "9 days logged this year, but none in a headline spot yet. Peek at the Elsewhere tab.",
        )
    }

    @Test func dayCountUsesPluralVariations() {
        #expect(WhereFormat.dayCount(1) == "1 day")
        #expect(WhereFormat.dayCount(5) == "5 days")
    }

    @Test func dayUnitUsesPluralVariations() {
        #expect(WhereFormat.dayUnit(1) == "day")
        #expect(WhereFormat.dayUnit(2) == "days")
    }

    @Test func missingBannerCompactUsesPluralVariations() {
        #expect(WhereFormat.missingBannerCompact(count: 1) == "1 day needs a location")
        #expect(WhereFormat.missingBannerCompact(count: 8) == "8 days need a location")
    }

    @Test func yearsAreFormattedWithoutGroupingSeparator() {
        #expect(WhereFormat.year(2026) == "2026")
        #expect(String(localized: .timelineTitle(WhereFormat.year(2026))) == "Timeline · 2026")
        #expect(String(localized: .calendarTitle(WhereFormat.year(2026))) == "Calendar · 2026")
        #expect(String(localized: .settingsDataErase(WhereFormat.year(2026))) == "Erase 2026 data")
    }

    @Test func calendarRegionTitleFormatsRegionAndGroupingFreeYear() {
        #expect(
            String(localized: .calendarRegionTitle(
                Region.california.localizedName,
                WhereFormat.year(2026),
            ))
                == "California · 2026",
        )
    }

    @Test func interpolatedSymbolsSubstituteArguments() {
        #expect(String(localized: .primaryEmptyTitle(WhereFormat.year(2024))) ==
            "No travels logged for 2024")
    }

    @Test func relabelSymbolsResolveToCatalogValues() {
        #expect(String(localized: .relabelTitle) == "Fix this day")
        #expect(String(localized: .relabelRegionsHeader) == "Where were you?")
        #expect(String(localized: .relabelReset) == "Reset to GPS-detected location")
        #expect(String(localized: .secondaryRegionEmptyTitle) == "Nothing to fix")
        #expect(String(localized: .secondaryRegionCurrent("California")) == "Counts as California")
    }

    @Test func backupSymbolsResolveToCatalogValues() {
        #expect(String(localized: .settingsBackupHeader) == "Backup")
        #expect(String(localized: .settingsBackupExport) == "Export data")
        #expect(String(localized: .settingsBackupImport) == "Import data")
        #expect(String(localized: .settingsBackupMerge) == "Merge")
        #expect(String(localized: .settingsBackupReplace) == "Replace all")
        #expect(String(localized: .settingsBackupImportedTitle) == "Backup imported")
    }

    @Test func backupImportedMessageSubstitutesAllCountsInOrder() {
        #expect(
            String(localized: .settingsBackupImportedMessage(3, 2, 5, 4))
                ==
                "Imported 3 location samples, 2 pieces of evidence, 5 manual days, and 4 dismissed issues.",
        )
    }

    @Test func evidenceSymbolsResolveToCatalogValues() {
        #expect(String(localized: .primaryEvidence) == "Evidence")
        #expect(String(localized: .evidenceEmptyTitle) == "No evidence yet")
        #expect(String(localized: .evidenceAdd) == "Add evidence")
        #expect(String(localized: .evidenceListTitle(WhereFormat.year(2026))) == "Evidence · 2026")
    }

    @Test func evidenceKindDisplayNamesResolve() {
        #expect(EvidenceKind.planeTicket.displayName == "Plane ticket")
        #expect(EvidenceKind.boardingPass.displayName == "Boarding pass")
        #expect(EvidenceKind.email.displayName == "Email")
        #expect(EvidenceKind.other("Ferry ticket").displayName == "Ferry ticket")
        #expect(EvidenceKind.other(nil).displayName == "Other")
    }

    @Test func calendarDayAccessibilityAppendsEvidenceCue() throws {
        let date = try #require(Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2026, month: 3, day: 4)))
        let withEvidence = WhereFormat.calendarDayAccessibility(
            date: date,
            regions: [.california],
            needsAttention: false,
            hasEvidence: true,
        )
        let without = WhereFormat.calendarDayAccessibility(
            date: date,
            regions: [.california],
            needsAttention: false,
            hasEvidence: false,
        )
        #expect(withEvidence.hasSuffix("has evidence"))
        #expect(!without.hasSuffix("has evidence"))
    }

    @Test func developerToolsSymbolsResolveToCatalogValues() {
        #expect(String(localized: .developerTitle) == "Developer")
        #expect(String(localized: .developerLogsLink) == "Logs")
        #expect(String(localized: .developerLogsTitle) == "Logs")
        #expect(String(localized: .developerInspectorLink) == "SwiftData Inspector")
        #expect(String(localized: .developerInspectorTitle) == "SwiftData")
        #expect(String(localized: .developerRegionMapLink) == "Region map")
        #expect(String(localized: .developerFooter) ==
            "On-device logs and data tools. Debug builds only.")
    }

    @Test func developerOverlayChromeSymbolsResolveToCatalogValues() {
        #expect(String(localized: .developerButtonLabel) == "Developer tools")
        #expect(String(localized: .developerClose) == "Close")
        #expect(String(localized: .developerExpand) == "Enter full screen")
        #expect(String(localized: .developerCollapse) == "Exit full screen")
    }

    @Test func regionMapStringsResolveToCatalogValues() {
        #expect(String(localized: .regionMapTitle) == "Region Map")
        #expect(String(localized: .regionMapKindPicker) == "Geometry")
        #expect(WhereFormat.regionMapKind(.attribution) == "Attribution")
        #expect(WhereFormat.regionMapKind(.source) == "Source")
        #expect(String(localized: .regionMapLegendHeader) == "Features")
        #expect(String(localized: .regionMapShowAll) == "Show all")
        #expect(String(localized: .regionMapMapAccessibility) == "Map of region boundaries")
        #expect(String(localized: .regionMapLoadErrorTitle) == "Couldn't load regions")
        #expect(String(localized: .regionMapEmptyTitle) == "No regions")
        #expect(String(localized: .regionMapEmptyDescription) ==
            "No region geometry was found in the bundle.")
        #expect(
            WhereFormat.regionMapKindFooter(.attribution)
                == "The simplified polygons the app uses to attribute coordinates today.",
        )
        #expect(
            WhereFormat.regionMapKindFooter(.source)
                ==
                "Every feature decoded straight from the bundled GeoJSON, at full authored fidelity.",
        )
    }
}
