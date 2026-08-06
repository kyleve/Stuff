import Foundation
import RegionKit
import WhereCore

/// Formatting and presentation helpers that compose Xcode's generated String
/// Catalog symbols (`LocalizedStringResource`) with runtime values — counts,
/// years, region names, enum cases.
///
/// Simple one-to-one strings are referenced through their generated symbols
/// directly at the call site (`Text(.tabYear)`, `String(localized: .commonOk)`);
/// only strings that need composition, pluralization, a `switch`, or non-catalog
/// number/coordinate formatting live here. Every catalog lookup below goes
/// through a generated symbol, so a removed or renamed key is a compile error.
enum WhereFormat {
    // MARK: Numbers & measurements (non-catalog)

    /// Year without a grouping separator ("2026", not "2,026").
    static func yearText(_ year: Int) -> String {
        year.formatted(.number.grouping(.never))
    }

    /// A "37.77490, -122.41940"-style coordinate label. No catalog entry is
    /// needed; the number style is locale-driven, like `driftThresholdLabel`.
    static func auditCoordinate(latitude: Double, longitude: Double) -> String {
        let lat = latitude.formatted(.number.precision(.fractionLength(5)))
        let lon = longitude.formatted(.number.precision(.fractionLength(5)))
        return "\(lat), \(lon)"
    }

    /// A localized "10 km"-style label for a drift-threshold preset, kept in
    /// kilometers (`.asProvided`, no conversion). Locale-driven, no catalog entry.
    static func driftThresholdLabel(kilometers: Int) -> String {
        Measurement(value: Double(kilometers), unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    // MARK: Counts

    /// "1 day" / "5 days" — with the count rendered.
    static func dayCount(_ count: Int) -> String {
        String(localized: .commonDayCount(count))
    }

    /// "day" / "days" — the bare unit, when the count is shown separately.
    static func dayUnit(_ count: Int) -> String {
        count == 1 ? String(localized: .commonDay) : String(localized: .commonDays)
    }

    static func elsewhereCardSubtitle(regions: Int) -> String {
        String(localized: .locationsElsewhereSubtitle(regions))
    }

    static func missingBannerCompact(count: Int) -> String {
        count == 1
            ? String(localized: .missingBannerCompactOne)
            : String(localized: .missingBannerCompactOther(count))
    }

    static func manualRangeFooter(count: Int) -> String {
        String(localized: .manualRangeFooter(count))
    }

    static func locationForecastEstimate(region: Region, days: Int) -> AttributedString {
        AttributedString(localized: .locationForecastEstimate(
            region.localizedName,
            dayCount(days),
        ))
    }

    static func locationForecastElapsed(days: Int) -> String {
        String(localized: .locationForecastElapsed(dayCount(days)))
    }

    static func locationForecastBasis(yearToDateDays: Int) -> String {
        String(localized: .locationForecastBasis(dayCount(yearToDateDays)))
    }

    static func locationForecastPlan(through day: CalendarDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = day.startOfDay(in: calendar)
        return String(localized: .locationForecastPlan(
            date.formatted(.dateTime.month(.wide).day().year()),
        ))
    }

    static func settingsBackupImportedMessage(
        samples: Int,
        evidence: Int,
        manualDays: Int,
        dismissedIssues: Int,
        trackedRegions: Int,
    ) -> String {
        String(localized: .settingsBackupImportedMessage(
            samples,
            evidence,
            manualDays,
            dismissedIssues,
            trackedRegions,
        ))
    }

    /// Result of a manual "Find issues now" scan — the current unresolved count,
    /// worded as present state (0 / 1 / many explicit, no catalog plural rule).
    static func settingsFindIssuesResult(count: Int) -> String {
        switch count {
            case 0: String(localized: .settingsFindIssuesResultNone)
            case 1: String(localized: .settingsFindIssuesResultOne)
            default: String(localized: .settingsFindIssuesResultMany(count))
        }
    }

    // MARK: Years

    static func primaryEmptyTitle(year: Int) -> String {
        String(localized: .primaryEmptyTitle(yearText(year)))
    }

    static func primaryElsewhereOnlyDescription(count: Int) -> String {
        String(localized: .primaryElsewhereOnlyDescription(count))
    }

    static func secondaryHeader(year: Int) -> String {
        String(localized: .secondaryHeader(yearText(year)))
    }

    static func settingsDataErase(year: Int) -> String {
        String(localized: .settingsDataErase(yearText(year)))
    }

    static func settingsDataConfirmMessage(year: Int) -> String {
        String(localized: .settingsDataConfirmMessage(yearText(year)))
    }

    static func settingsDataFooter(year: Int) -> String {
        String(localized: .settingsDataFooter(yearText(year)))
    }

    static func calendarTitle(year: Int) -> String {
        String(localized: .calendarTitle(yearText(year)))
    }

    static func calendarRegionTitle(region: Region, year: Int) -> String {
        String(localized: .calendarRegionTitle(region.localizedName, yearText(year)))
    }

    static func loggedDaysTitle(year: Int) -> String {
        String(localized: .loggedDaysTitle(yearText(year)))
    }

    static func evidenceListTitle(year: Int) -> String {
        String(localized: .evidenceListTitle(yearText(year)))
    }

    static func widgetYearTitle(year: Int) -> String {
        String(localized: .widgetYearTitle(yearText(year)))
    }

    // MARK: Regions

    static func secondaryRegionCurrent(regions: String) -> String {
        String(localized: .secondaryRegionCurrent(regions))
    }

    static func regionPickerSelectionCount(selected: Int, max: Int) -> String {
        String(localized: .regionPickerSelectionCount(selected, max))
    }

    static func regionPickerAtCapacity(max: Int) -> String {
        String(localized: .regionPickerAtCapacity(max))
    }

    static func regionCustomizeSubtitle(region: String) -> String {
        String(localized: .regionCustomizeSubtitle(region))
    }

    static func regionCustomizeStep(current: Int, total: Int) -> String {
        String(localized: .regionCustomizeStep(current, total))
    }

    static func regionColorAccessibility(_ token: RegionColorToken) -> String {
        String(localized: .regionCustomizeColorAccessibility(token.rawValue))
    }

    // MARK: Accessibility (composed)

    static func regionDaysAccessibility(region: String, days: Int) -> String {
        String(localized: .commonRegionDaysAccessibility(region, dayCount(days)))
    }

    static func calendarDayAccessibility(
        date: Date,
        regions: [Region],
        needsAttention: Bool,
        hasEvidence: Bool,
        isPlanned: Bool,
    ) -> String {
        var label = calendarDayBase(date: date, regions: regions, needsAttention: needsAttention)
        if isPlanned {
            label = String(localized: .calendarDayPlannedAccessibility(label))
        }
        guard hasEvidence else { return label }
        // Append the attachment cue so VoiceOver announces it after the day's
        // regions/status, e.g. "Monday, March 4, California, has evidence".
        return String(localized: .calendarDayHasEvidenceAccessibility(label))
    }

    private static func calendarDayBase(
        date: Date,
        regions: [Region],
        needsAttention: Bool,
    ) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if needsAttention {
            return String(localized: .calendarDayNeedsAttentionAccessibility(day))
        }
        if regions.isEmpty {
            return String(localized: .calendarDayEmptyAccessibility(day))
        }
        let names = regions.map(\.localizedName).joined(separator: ", ")
        return String(localized: .calendarDayAccessibility(day, names))
    }

    static func timelineRowAccessibility(region: String, range: String, days: Int) -> String {
        String(localized: .timelineRowAccessibility(region, range, dayCount(days)))
    }

    static func evidenceRowAccessibility(kind: EvidenceKind, date: Date) -> String {
        let day = date.formatted(.dateTime.month(.wide).day().year())
        return String(localized: .evidenceRowAccessibility(evidenceKind(kind), day))
    }

    // MARK: Evidence

    /// Human-readable name for an evidence kind. `.other` shows its
    /// user-supplied label when present, else a generic "Other".
    static func evidenceKind(_ kind: EvidenceKind) -> String {
        switch kind {
            case .planeTicket: String(localized: .evidenceKindPlaneTicket)
            case .boardingPass: String(localized: .evidenceKindBoardingPass)
            case .hotelReceipt: String(localized: .evidenceKindHotelReceipt)
            case .carRental: String(localized: .evidenceKindCarRental)
            case .rideshare: String(localized: .evidenceKindRideshare)
            case .photo: String(localized: .evidenceKindPhoto)
            case .document: String(localized: .evidenceKindDocument)
            case .email: String(localized: .evidenceKindEmail)
            case let .other(label):
                if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    label
                } else {
                    String(localized: .evidenceKindOther)
                }
        }
    }

    // MARK: Resolution

    static func resolutionSectionHeader(_ category: DataIssueCategory) -> String {
        switch category {
            case .missingDays: String(localized: .resolutionSectionMissingDays)
            case .borderDrift: String(localized: .resolutionSectionBorderDrift)
            case .abruptChange: String(localized: .resolutionSectionAbruptChange)
            case .flightDay: String(localized: .resolutionSectionFlightDay)
        }
    }

    static func driftRowSubtitle(region: String, distance: String) -> String {
        String(localized: .resolutionDriftSubtitle(region, distance))
    }

    static func resolutionAbruptRowTitle(earlier: Set<Region>, later: Set<Region>) -> String {
        let earlierNames = earlier.map(\.localizedName).sorted().joined(separator: ", ")
        let laterNames = later.map(\.localizedName).sorted().joined(separator: ", ")
        return String(localized: .resolutionAbruptRowTitle(earlierNames, laterNames))
    }

    static func resolutionFlightDetailExplanation(
        peakSpeedKMH: Double,
        removed: Set<Region>,
    ) -> String {
        let speed = Measurement(value: peakSpeedKMH, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .general))
        let removedNames = removed.map(\.localizedName).sorted().joined(separator: ", ")
        return String(localized: .resolutionFlightDetailExplanation(speed, removedNames))
    }

    static func resolutionFlightApply(regions: Set<Region>) -> String {
        let names = regions.map(\.localizedName).sorted().joined(separator: ", ")
        return String(localized: .resolutionFlightApply(names))
    }

    static func relabelReasonBorderDrift(region: String, distance: String?) -> String {
        if let distance {
            return String(localized: .relabelReasonBorderDriftDistance(distance, region))
        }
        return String(localized: .relabelReasonBorderDrift(region))
    }

    static func relabelReasonFlight(removed: Set<Region>) -> String {
        let removedNames = removed.map(\.localizedName).sorted().joined(separator: ", ")
        return String(localized: .relabelReasonFlight(removedNames))
    }

    // MARK: Region map (developer)

    static func regionMapKind(_ kind: RegionGeometryKind) -> String {
        switch kind {
            case .attribution: String(localized: .regionMapKindAttribution)
            case .source: String(localized: .regionMapKindSource)
        }
    }

    static func regionMapKindFooter(_ kind: RegionGeometryKind) -> String {
        switch kind {
            case .attribution: String(localized: .regionMapKindAttributionFooter)
            case .source: String(localized: .regionMapKindSourceFooter)
        }
    }

    // MARK: Recent activity

    static func recentActivityTitle(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day: String(localized: .recentActivityTitleDay)
            case .week: String(localized: .recentActivityTitleWeek)
            case .month: String(localized: .recentActivityTitleMonth)
            case .yearToDate: String(localized: .recentActivityTitleYearToDate)
        }
    }

    static func recentActivityWindowLabel(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day: String(localized: .recentActivityWindowDay)
            case .week: String(localized: .recentActivityWindowWeek)
            case .month: String(localized: .recentActivityWindowMonth)
            case .yearToDate: String(localized: .recentActivityWindowYearToDate)
        }
    }

    static func recentActivityFooter(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day: String(localized: .recentActivityFooterDay)
            case .week: String(localized: .recentActivityFooterWeek)
            case .month: String(localized: .recentActivityFooterMonth)
            case .yearToDate: String(localized: .recentActivityFooterYearToDate)
        }
    }

    static func recentActivityEmptyDescription(_ window: RecentActivityWindow) -> String {
        switch window {
            case .day: String(localized: .recentActivityEmptyDescriptionDay)
            case .week: String(localized: .recentActivityEmptyDescriptionWeek)
            case .month: String(localized: .recentActivityEmptyDescriptionMonth)
            case .yearToDate: String(localized: .recentActivityEmptyDescriptionYearToDate)
        }
    }

    static func recentActivityUnavailableMessage(
        _ reason: ActivitySummaryUnavailableReason,
    ) -> String {
        switch reason {
            case .deviceNotEligible:
                String(localized: .recentActivityUnavailableDeviceNotEligible)
            case .appleIntelligenceNotEnabled:
                String(localized: .recentActivityUnavailableAppleIntelligenceNotEnabled)
            case .modelNotReady:
                String(localized: .recentActivityUnavailableModelNotReady)
            case .unknown:
                String(localized: .recentActivityUnavailableUnknown)
        }
    }

    // MARK: About

    /// A build-metadata value, or a localized "Unknown" when the bundle doesn't
    /// carry one — so a blank row can never read as a real, empty value.
    static func aboutValue(_ value: String?) -> String {
        value ?? String(localized: .settingsAboutValueUnknown)
    }

    /// The commit the app was built from, flagged when the working tree had
    /// uncommitted changes so a developer build isn't mistaken for a
    /// reproducible one.
    static func aboutCommit(_ commit: BuildInfo.Commit?) -> String {
        guard let commit else { return String(localized: .settingsAboutValueUnknown) }
        return commit.isDirty
            ? String(localized: .settingsAboutCommitModified(commit.sha))
            : commit.sha
    }

    static func regionDataSourceRegionCount(_ count: Int) -> String {
        String(localized: .settingsAboutDataSourceRegionCount(count))
    }

    static func regionDataSourceFidelity(_ fidelity: RegionDataSource.Fidelity) -> String {
        switch fidelity {
            case .authoritative: String(localized: .settingsAboutDataSourceAuthoritative)
            case .approximate: String(localized: .settingsAboutDataSourceApproximate)
        }
    }

    static func regionDataSourceLicense(_ license: RegionDataSource.License) -> String {
        switch license {
            case let .publicDomain(rationale):
                String(localized: .settingsAboutDataSourcePublicDomain(rationale))
            case .originalWork:
                String(localized: .settingsAboutDataSourceOriginalWork)
        }
    }

    static func regionDataSourcePublisher(_ url: URL) -> String {
        String(localized: .settingsAboutDataSourcePublisherLink(linkHost(url)))
    }

    static func regionDataSourceObtainedFrom(_ url: URL) -> String {
        String(localized: .settingsAboutDataSourceObtainedFromLink(linkHost(url)))
    }

    /// A link's bare host ("census.gov"), so a data-source link names where it
    /// goes instead of reading as an unlabeled "Publisher". Falls back to the
    /// whole URL for anything without a host.
    private static func linkHost(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
