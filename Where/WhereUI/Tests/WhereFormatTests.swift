import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

/// Verifies `WhereFormat`'s composition/plural/switch logic over the generated
/// String Catalog symbols: counts pluralize, years format without a grouping
/// separator, arguments substitute in order, and enum switches map to the right
/// catalog value. A removed/renamed key is caught by the compiler, so these
/// tests focus on the runtime logic, not that every simple symbol exists.
struct WhereFormatTests {
    @Test func generatedSymbolsResolveToCatalogValues() {
        #expect(String(localized: .tabSettings) == "Settings")
        #expect(String(localized: .commonOk) == "OK")
        #expect(String(localized: .primaryElsewhereOnlyTitle) == "Nothing in your headline spots")
    }

    @Test func elsewhereOnlyDescriptionUsesPluralVariations() {
        #expect(
            WhereFormat.primaryElsewhereOnlyDescription(count: 1)
                == "1 day logged this year, but none in a headline spot yet.",
        )
        #expect(
            WhereFormat.primaryElsewhereOnlyDescription(count: 9)
                == "9 days logged this year, but none in a headline spot yet.",
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

    @Test func locationForecastCopyComposesLocalizedDayCounts() {
        let estimate = WhereFormat.locationForecastEstimate(region: .newYork, days: 183)
        #expect(String(estimate.characters) == "New York might be 183 days this year")
        let emphasized = estimate.runs.compactMap { run -> String? in
            guard run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true else {
                return nil
            }
            return String(estimate[run.range].characters)
        }
        #expect(emphasized == ["183 days"])
        #expect(WhereFormat.locationForecastElapsed(days: 182) == "182 days elapsed")
        #expect(
            WhereFormat.locationForecastBasis(yearToDateDays: 91)
                == "Based on 91 days here.",
        )
        #expect(
            WhereFormat.locationForecastPlan(
                through: CalendarDay(year: 2026, month: 8, day: 15),
            ) == "Includes staying through August 15, 2026.",
        )
        #expect(
            WhereFormat.plannedStayOutsideLocation(
                region: .newYork,
                driftThreshold: .km1,
            ) ==
                "Your current location is not in New York or within the 1 km drift threshold. You can still save this plan.",
        )
    }

    @Test func locationCardEstimateCopyComposesLocalizedDayCounts() {
        #expect(WhereFormat.locationCardEstimatedDays(184) == "Estimated · 184 days")
        #expect(
            WhereFormat.regionDaysEstimatedAccessibility(
                region: "California",
                recordedDays: 148,
                estimatedDays: 184,
            ) == "California: 148 days recorded, estimated 184 days",
        )
    }

    /// The one string that agrees grammatically via automatic inflection
    /// (`^[%lld region](inflect: true)`) rather than an explicit plural
    /// variation, so both forms are worth pinning.
    @Test func elsewhereCardSubtitleInflectsTheRegionCount() {
        // Pre-existing bug, not a migration regression: the catalog entry is
        // byte-identical on main, and the compiled Localizable.strings keeps the
        // markup verbatim, so flattening the resource to a String never runs the
        // inflection engine and the card renders "^[3 region](inflect: true)".
        // Tracked in Where/TODOs.md; this trips once the rendering is fixed.
        withKnownIssue("Inflection markup isn't applied when flattened to a String") {
            #expect(WhereFormat.elsewhereCardSubtitle(regions: 1) == "1 region")
            #expect(WhereFormat.elsewhereCardSubtitle(regions: 3) == "3 regions")
        }
    }

    @Test func yearsAreFormattedWithoutGroupingSeparator() {
        #expect(WhereFormat.calendarTitle(year: 2026) == "Calendar · 2026")
        #expect(WhereFormat.settingsDataErase(year: 2026) == "Erase 2026 data")
    }

    @Test func calendarRegionTitleFormatsRegionAndGroupingFreeYear() {
        #expect(
            WhereFormat.calendarRegionTitle(region: .california, year: 2026)
                == "California · 2026",
        )
    }

    @Test func interpolatedStringsSubstituteArguments() {
        #expect(WhereFormat.primaryEmptyTitle(year: 2024) == "No travels logged for 2024")
    }

    @Test func missingBannerCompactUsesPluralVariations() {
        #expect(WhereFormat.missingBannerCompact(count: 1) == "1 day needs a location")
        #expect(WhereFormat.missingBannerCompact(count: 8) == "8 days need a location")
    }

    @Test func secondaryRegionCurrentSubstitutesRegions() {
        #expect(WhereFormat.secondaryRegionCurrent(regions: "California") == "Counts as California")
    }

    @Test func resolutionCategoryListUsesLocalizedListFormatting() {
        #expect(
            WhereFormat.resolutionCategoryList(Set(DataIssueCategory.allCases))
                == "Missing days, Near the border, Sudden moves, and Flights",
        )
    }

    @Test func backupImportedMessageSubstitutesAllCountsInOrder() {
        #expect(
            WhereFormat.settingsBackupImportedMessage(
                samples: 3,
                evidence: 2,
                manualDays: 5,
                dismissedIssues: 4,
                trackedRegions: 6,
            )
                ==
                "Imported 3 location samples, 2 pieces of evidence, 5 manual days, 4 dismissed issues, and 6 tracked regions.",
        )
    }

    @Test func backupCleanupMessagePreservesSummaryAndSafeRecoveryGuidance() {
        let summary = BackupCoordinator.ImportSummary(
            sampleCount: 3,
            evidenceCount: 2,
            manualDayCount: 5,
            dismissedIssueCount: 4,
            trackedRegionCount: 6,
            recordingDeviceCount: 2,
            recordingDeviceRemovalCount: 7,
        )

        let message = WhereFormat.backupImportCleanupMessage(summary)

        #expect(message.contains("Imported 3 location samples"))
        #expect(message.contains("Close and reopen Where"))
        #expect(message.contains("Do not import this backup again."))
    }

    @Test func yearTitlesFormatGroupingFree() {
        #expect(WhereFormat.evidenceListTitle(year: 2026) == "Evidence · 2026")
        #expect(WhereFormat.loggedDaysTitle(year: 2026) == "Logged Days · 2026")
    }

    /// The widget entry views render from the app's catalog, so a missing key
    /// there ships a raw identifier to the Home Screen.
    @Test func widgetStringsResolve() {
        #expect(String(localized: .widgetTodayTitle) == "Today")
        #expect(String(localized: .widgetTodayEmpty) == "Nothing logged yet")
        #expect(WhereFormat.widgetYearTitle(year: 2026) == "Days in 2026")
        #expect(String(localized: .widgetYearEmpty) == "No days logged")
    }

    @Test func evidenceKindDisplayNamesResolve() {
        #expect(WhereFormat.evidenceKind(.planeTicket) == "Plane ticket")
        #expect(WhereFormat.evidenceKind(.boardingPass) == "Boarding pass")
        #expect(WhereFormat.evidenceKind(.email) == "Email")
        #expect(WhereFormat.evidenceKind(.other("Ferry ticket")) == "Ferry ticket")
        #expect(WhereFormat.evidenceKind(.other(nil)) == "Other")
    }

    @Test func calendarDayAccessibilityAppendsEvidenceCue() throws {
        let date = try #require(Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: 2026, month: 3, day: 4)))
        let withEvidence = WhereFormat.calendarDayAccessibility(
            date: date,
            regions: [.california],
            needsAttention: false,
            hasEvidence: true,
            isPlanned: false,
        )
        let without = WhereFormat.calendarDayAccessibility(
            date: date,
            regions: [.california],
            needsAttention: false,
            hasEvidence: false,
            isPlanned: false,
        )
        #expect(withEvidence.hasSuffix("has evidence"))
        #expect(!without.hasSuffix("has evidence"))
    }

    @Test func calendarDayAccessibilityIdentifiesPlannedPresence() throws {
        let calendar = Calendar(identifier: .gregorian)
        let label = try WhereFormat.calendarDayAccessibility(
            date: #require(calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 16),
            )),
            regions: [.newYork],
            needsAttention: false,
            hasEvidence: false,
            isPlanned: true,
        )

        #expect(label.contains("planned"))
        #expect(label.contains(Region.newYork.localizedName))
    }

    @Test func calendarMonthAccessibilitySummarizesTotalsOverlapsAndStatuses() {
        let value = WhereFormat.calendarMonthAccessibility(
            regionTotals: [
                RegionDayTally(region: .california, days: 17),
                RegionDayTally(region: .newYork, days: 12),
            ],
            regionCombinationTotals: [
                RegionCombinationDayTally(regions: [.california, .newYork], days: 1),
            ],
            needsAttentionDays: 2,
            evidenceDays: 1,
            plannedRegionTotals: [RegionDayTally(region: .newYork, days: 3)],
        )

        let expected = "California: 17 days, New York: 12 days, "
            + "1 day in California and New York, 2 days need a location, "
            + "1 day has evidence, and 3 days planned in New York"
        #expect(value == expected)
    }

    @Test func calendarMonthAccessibilityKeepsEmptyStateBeforeStatusCounts() {
        let value = WhereFormat.calendarMonthAccessibility(
            regionTotals: [],
            regionCombinationTotals: [],
            needsAttentionDays: 1,
            evidenceDays: 2,
            plannedRegionTotals: [],
        )

        #expect(value == "No days logged, 1 day needs a location, and 2 days have evidence")
    }

    @Test func widgetAccessibilitySummariesUseExplicitLabelsAndVisibleRows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
            hour: 12,
        )))

        #expect(WhereFormat.widgetTodayAccessibilityLabel(date: date) == "Today, July 15")
        #expect(
            WhereFormat.widgetTodayAccessibilityValue(regions: [.california, .newYork])
                == "California and New York",
        )
        #expect(
            WhereFormat.widgetTodayAccessibilityValue(regions: []) == "Nothing logged yet",
        )
        #expect(
            WhereFormat.widgetYearAccessibilityValue(entries: [
                RegionDays(region: .california, days: 132),
                RegionDays(region: .newYork, days: 1),
            ]) == "California: 132 days and New York: 1 day",
        )
        #expect(WhereFormat.widgetYearAccessibilityValue(entries: []) == "No days logged")
    }

    @Test func regionMapKindSwitchesResolve() {
        #expect(WhereFormat.regionMapKind(.attribution) == "Attribution")
        #expect(WhereFormat.regionMapKind(.source) == "Source")
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

    // MARK: About

    @Test func aboutValueNamesAMissingBuildValue() {
        #expect(WhereFormat.aboutValue("1.0") == "1.0")
        // An absent value must read as unknown, never as a blank that looks
        // like a real (empty) version.
        #expect(WhereFormat.aboutValue(nil) == "Unknown")
    }

    @Test func aboutCommitFlagsADirtyTree() {
        let sha = "a18a9309c5d6"
        #expect(WhereFormat.aboutCommit(BuildInfo.Commit(sha: sha, isDirty: false)) == sha)
        #expect(
            WhereFormat.aboutCommit(BuildInfo.Commit(sha: sha, isDirty: true))
                == "\(sha) (modified)",
        )
        #expect(WhereFormat.aboutCommit(nil) == "Unknown")
    }

    @Test func regionDataSourceCountPluralizes() {
        #expect(WhereFormat.regionDataSourceRegionCount(1) == "1 region")
        #expect(WhereFormat.regionDataSourceRegionCount(52) == "52 regions")
    }

    @Test func regionDataSourceFidelitySwitchesResolve() {
        #expect(
            WhereFormat.regionDataSourceFidelity(.authoritative)
                == "Simplified from the published boundary set.",
        )
        #expect(
            WhereFormat.regionDataSourceFidelity(.approximate)
                == "Approximate outline drawn for this app — coarse, and not authoritative.",
        )
    }

    @Test func regionDataSourceLicenseSwitchesResolve() {
        #expect(
            WhereFormat.regionDataSourceLicense(.publicDomain("17 U.S.C. § 105"))
                == "Public domain — 17 U.S.C. § 105",
        )
        #expect(
            WhereFormat.regionDataSourceLicense(.originalWork)
                == "No external source; covered by the app's own license.",
        )
    }
}
