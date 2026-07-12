import Foundation
import RegionKit
import WhereCore

/// Formatting and presentation helpers that compose Xcode's generated String
/// Catalog symbols (`LocalizedStringResource`) with runtime values — counts,
/// years, region names, enum cases.
///
/// Simple one-to-one strings are referenced through their generated symbols
/// directly at the call site (`Text(.tabPrimary)`, `String(localized: .commonOk)`);
/// only strings that need composition, pluralization, a `switch`, or non-catalog
/// number/coordinate formatting live here. Every catalog lookup below goes
/// through a generated symbol, so a removed or renamed key is a compile error.
enum WhereFormat {
    // MARK: Numbers & measurements (non-catalog)

    /// Year without a grouping separator ("2026", not "2,026").
    static func year(_ year: Int) -> String {
        year.formatted(.number.grouping(.never))
    }

    /// A localized "10 km"-style label for a drift-threshold preset. Formatted
    /// through `Measurement` so the number and unit symbol localize, while
    /// staying in kilometers (`.asProvided`, no conversion to miles) — the
    /// presets are defined in km.
    static func driftThreshold(kilometers: Int) -> String {
        Measurement(value: Double(kilometers), unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    /// A "37.77490, -122.41940"-style coordinate label. The number style is
    /// locale-driven, so no catalog entry is needed.
    static func coordinate(latitude: Double, longitude: Double) -> String {
        let lat = latitude.formatted(.number.precision(.fractionLength(5)))
        let lon = longitude.formatted(.number.precision(.fractionLength(5)))
        return "\(lat), \(lon)"
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

    static func missingBannerCompact(count: Int) -> String {
        count == 1
            ? String(localized: .missingBannerCompactOne)
            : String(localized: .missingBannerCompactOther(count))
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
    ) -> String {
        let base = calendarDayBase(date: date, regions: regions, needsAttention: needsAttention)
        guard hasEvidence else { return base }
        // Append the attachment cue so VoiceOver announces it after the day's
        // regions/status, e.g. "Monday, March 4, California, has evidence".
        return String(localized: .calendarDayHasEvidenceAccessibility(base))
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
        return String(localized: .evidenceRowAccessibility(kind.displayName, day))
    }

    // MARK: Resolution

    static func resolutionSectionHeader(_ category: DataIssueCategory) -> String {
        switch category {
            case .missingDays: String(localized: .resolutionSectionMissingDays)
            case .borderDrift: String(localized: .resolutionSectionBorderDrift)
            case .abruptChange: String(localized: .resolutionSectionAbruptChange)
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
}
