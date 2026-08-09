import CryptoKit
import Foundation
import RegionKit

/// A provisional current-year history derived from photo locations. It stays
/// entirely in memory until the user approves it during onboarding.
public struct PhotoHistoryDraft: Sendable {
    /// How an affected day should be committed.
    public enum DayDecision: Sendable, Equatable {
        /// Keep the photo samples and use their attributed regions.
        case included
        /// Do not import any photo samples from this day.
        case excluded
        /// Keep the photo samples, but authoritatively use these regions in the
        /// year report. The raw samples remain available for an audit/reset.
        case corrected(Set<Region>)
    }

    public let year: Int
    public let calendar: Calendar
    public let samples: [LocationSample]

    private let attributor: RegionAttributor
    private var decisions: [CalendarDay: DayDecision] = [:]

    public init(
        year: Int,
        calendar: Calendar,
        samples: [LocationSample],
        regions: [Region],
    ) {
        self.year = year
        self.calendar = calendar
        self.samples = samples.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id.uuidString < $1.id.uuidString
        }
        attributor = RegionAttributor(for: regions)
    }

    /// Calendar days represented by at least one candidate sample.
    public var affectedDays: [CalendarDay] {
        Array(Set(samples.map { CalendarDay(from: $0.timestamp, in: calendar) })).sorted()
    }

    public func decision(for day: CalendarDay) -> DayDecision {
        decisions[day] ?? .included
    }

    public var hasExcludedDays: Bool {
        decisions.values.contains(.excluded)
    }

    /// Restore every excluded day to its photo-derived attribution without
    /// disturbing corrections made to other days.
    public mutating func restoreExcludedDays() {
        decisions = decisions.filter { $0.value != .excluded }
    }

    /// Apply one decision to every candidate day in an inclusive range.
    public mutating func setDecision(
        _ decision: DayDecision,
        from start: CalendarDay,
        through end: CalendarDay,
    ) {
        guard start <= end else { return }
        for day in affectedDays where day >= start && day <= end {
            if decision == .included {
                decisions.removeValue(forKey: day)
            } else {
                decisions[day] = decision
            }
        }
    }

    /// The report rendered by the onboarding preview after applying all draft
    /// exclusions and authoritative corrections.
    public var report: YearReport {
        let included = samples.filter { sample in
            decision(for: CalendarDay(from: sample.timestamp, in: calendar)) != .excluded
        }
        let corrections = decisions.compactMap { day, decision -> DayPresence? in
            guard case let .corrected(regions) = decision else { return nil }
            return DayPresence(day: day, regions: regions, isAuthoritative: true, audit: nil)
        }
        return DayAggregator(calendar: calendar, timeZone: calendar.timeZone).report(
            for: year,
            samples: included,
            manualDays: corrections,
            attributor: attributor,
        )
    }

    /// Build the atomic payload persisted after the user approves the preview.
    /// Every authoritative correction carries the audit of that approval.
    public func approvedImport(audit: ManualEntryAudit) -> PhotoHistoryImport {
        let approvedSamples = samples.filter { sample in
            decision(for: CalendarDay(from: sample.timestamp, in: calendar)) != .excluded
        }
        let corrections = decisions.compactMap { day, decision -> DayPresence? in
            guard case let .corrected(regions) = decision else { return nil }
            return DayPresence(day: day, regions: regions, isAuthoritative: true, audit: audit)
        }
        return PhotoHistoryImport(samples: approvedSamples, corrections: corrections)
    }
}

/// Samples and authoritative day corrections saved as one photo-history import.
public struct PhotoHistoryImport: Sendable, Equatable {
    public let samples: [LocationSample]
    public let corrections: [DayPresence]

    public init(samples: [LocationSample], corrections: [DayPresence]) {
        self.samples = samples
        self.corrections = corrections
    }
}

/// Filters photo metadata using the onboarding's best-effort device-capture
/// policy and builds a provisional, editable history.
public struct PhotoHistoryPlanner: Sendable {
    public static let captureAddedTolerance: TimeInterval = 5 * 60

    public init() {}

    @concurrent
    public func makeDraft(
        assets: [PhotoLocationAsset],
        year: Int,
        regions: [Region],
        calendar: Calendar,
        now: Date,
    ) async throws -> PhotoHistoryDraft {
        let aggregator = DayAggregator(calendar: calendar, timeZone: calendar.timeZone)
        let yearInterval = aggregator.yearInterval(year: year)
        let end = min(yearInterval.end, now)
        let interval = DateInterval(start: yearInterval.start, end: end)
        var samplesByID: [UUID: LocationSample] = [:]
        samplesByID.reserveCapacity(assets.count)

        for asset in assets {
            try Task.checkCancellation()
            guard asset.source == .userLibrary,
                  asset.isHidden == false,
                  let capturedAt = asset.capturedAt,
                  let addedAt = asset.addedAt,
                  interval.contains(capturedAt),
                  abs(addedAt.timeIntervalSince(capturedAt)) <= Self.captureAddedTolerance,
                  let coordinate = asset.coordinate,
                  (-90.0 ... 90.0).contains(coordinate.latitude),
                  (-180.0 ... 180.0).contains(coordinate.longitude),
                  let accuracy = asset.horizontalAccuracy,
                  accuracy >= 0
            else { continue }

            let id = Self.sampleID(timestamp: capturedAt, coordinate: coordinate)
            samplesByID[id] = LocationSample(
                id: id,
                timestamp: capturedAt,
                coordinate: coordinate,
                horizontalAccuracy: accuracy,
                source: .photo,
            )
        }

        return PhotoHistoryDraft(
            year: year,
            calendar: calendar,
            samples: Array(samplesByID.values),
            regions: regions,
        )
    }

    /// Stable, privacy-preserving identity derived only from metadata Where
    /// persists. Multiple images at the same millisecond and coordinate collapse
    /// to one useful location sample, and Photos identifiers are never stored.
    private static func sampleID(timestamp: Date, coordinate: Coordinate) -> UUID {
        let milliseconds = Int64((timestamp.timeIntervalSince1970 * 1000).rounded())
        let latitude = Int64((coordinate.latitude * 10_000_000).rounded())
        let longitude = Int64((coordinate.longitude * 10_000_000).rounded())
        let input = Data("photo|\(milliseconds)|\(latitude)|\(longitude)".utf8)
        var bytes = Array(SHA256.hash(data: input).prefix(16))
        // RFC 9562 UUIDv8: application-defined payload plus the standard variant.
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            bytes[6],
            bytes[7],
            bytes[8],
            bytes[9],
            bytes[10],
            bytes[11],
            bytes[12],
            bytes[13],
            bytes[14],
            bytes[15],
        ))
    }
}
