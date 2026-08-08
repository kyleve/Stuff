import Foundation
import RegionKit

/// Every persisted value needed to build an annual audit report, captured by a
/// store in one logical read. Production's `SwiftDataStore` fetches these
/// tables through one actor-confined read context; lightweight stores inherit
/// the composable `WhereStore` default.
public struct YearAuditRecords: Hashable, Sendable {
    public let samples: [LocationSample]
    public let manualDays: [DayPresence]
    public let evidence: [Evidence]
    public let trackedRegions: Set<Region>

    public init(
        samples: [LocationSample],
        manualDays: [DayPresence],
        evidence: [Evidence],
        trackedRegions: Set<Region>,
    ) {
        self.samples = samples.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id.uuidString < $1.id.uuidString
        }
        self.manualDays = manualDays.sorted { $0.day < $1.day }
        self.evidence = evidence.sorted {
            if $0.capturedAt != $1.capturedAt { return $0.capturedAt < $1.capturedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        self.trackedRegions = trackedRegions
    }
}

/// A raw location sample paired with the region assigned by the report's
/// captured attribution policy.
public struct YearAuditAttributedSample: Hashable, Sendable {
    public let sample: LocationSample
    public let region: Region

    public init(sample: LocationSample, region: Region) {
        self.sample = sample
        self.region = region
    }
}

/// The auditable reasons a finalized day appears in an annual report. A day
/// can carry several bases (for example GPS plus an additive manual backfill).
public enum YearAuditDayBasis: Hashable, Sendable {
    case gps
    case manualCoordinate
    case evidenceDerivedCoordinate
    case additiveManualEntry
    case authoritativeManualOverride
}

/// A consistent annual snapshot: the finalized jurisdiction-day report and
/// all source records used to explain it. `timeZone` is captured because raw
/// GPS instants do not persist the device's historical time zone; every day in
/// this value was bucketed using this one reporting time zone.
public struct YearAuditReport: Hashable, Sendable {
    public let report: YearReport
    public let samples: [YearAuditAttributedSample]
    public let manualDays: [DayPresence]
    public let evidence: [Evidence]
    public let trackedRegions: [Region]
    public let timeZone: TimeZone
    public let regionDataSources: [RegionDataSource]

    public init(
        report: YearReport,
        samples: [YearAuditAttributedSample],
        manualDays: [DayPresence],
        evidence: [Evidence],
        trackedRegions: [Region],
        timeZone: TimeZone,
        regionDataSources: [RegionDataSource],
    ) {
        self.report = report
        self.samples = samples.sorted {
            if $0.sample.timestamp != $1.sample.timestamp {
                return $0.sample.timestamp < $1.sample.timestamp
            }
            return $0.sample.id.uuidString < $1.sample.id.uuidString
        }
        self.manualDays = manualDays.sorted { $0.day < $1.day }
        self.evidence = evidence.sorted {
            if $0.capturedAt != $1.capturedAt { return $0.capturedAt < $1.capturedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        self.trackedRegions = trackedRegions
        self.timeZone = timeZone
        self.regionDataSources = regionDataSources
    }

    /// The source categories supporting the finalized presence on `day`.
    /// Authoritative manual entries remain explicit even though their regions
    /// replace the coordinates' attribution in `report`.
    public func bases(on day: CalendarDay, calendar: Calendar) -> Set<YearAuditDayBasis> {
        var result: Set<YearAuditDayBasis> = []
        for attributed in samples
            where CalendarDay(from: attributed.sample.timestamp, in: calendar) == day
        {
            switch attributed.sample.source {
                case .gpsVisit, .gpsSignificantChange:
                    result.insert(.gps)
                case .manual:
                    result.insert(.manualCoordinate)
                case .evidenceImplied:
                    result.insert(.evidenceDerivedCoordinate)
            }
        }
        for manual in manualDays where manual.day == day {
            result
                .insert(manual
                    .isAuthoritative ? .authoritativeManualOverride : .additiveManualEntry)
        }
        return result
    }
}
