import Foundation
import os
import RegionKit

/// The year's passive GPS fixes, grouped by `CalendarDay` **lazily**: the
/// grouping is built once, on first access, and memoized. A scan whose
/// detectors never consult it pays nothing, and the result is reused across
/// detectors. Built from the samples the scanner already read for the year's
/// report (see `ReportReader.dataIssueReads(for:)`), so it adds no extra store
/// read — only the speed-based `FlightDayDetector` currently needs per-fix
/// timestamps, and even it only forces the grouping when it runs.
///
/// Only `.gpsVisit` / `.gpsSignificantChange` fixes are kept — manual and
/// evidence-implied samples carry user-asserted timestamps that would produce
/// meaningless speeds — and each day's fixes are timestamp-sorted, so a
/// speed-based detector can walk consecutive fixes.
public final class DaySamples: Sendable {
    private let rawSamples: [LocationSample]
    private let calendar: Calendar
    /// `nil` until the first `samples(on:)`; the grouped/filtered/sorted map
    /// thereafter. Locked so the type is safely `Sendable` and the grouping
    /// runs at most once.
    private let cache: OSAllocatedUnfairLock<[CalendarDay: [LocationSample]]?>

    public init(samples: [LocationSample], calendar: Calendar) {
        rawSamples = samples
        self.calendar = calendar
        cache = OSAllocatedUnfairLock(initialState: nil)
    }

    /// The GPS fixes recorded on `day`, timestamp-sorted (empty when none).
    /// Forces (and memoizes) the grouping on first access.
    public func samples(on day: CalendarDay) -> [LocationSample] {
        grouped()[day] ?? []
    }

    private func grouped() -> [CalendarDay: [LocationSample]] {
        cache.withLock { stored in
            if let stored { return stored }
            let built = Self.group(rawSamples, calendar: calendar)
            stored = built
            return built
        }
    }

    private static func group(
        _ samples: [LocationSample],
        calendar: Calendar,
    ) -> [CalendarDay: [LocationSample]] {
        var byDay: [CalendarDay: [LocationSample]] = [:]
        for sample in samples {
            switch sample.source {
                case .gpsVisit, .gpsSignificantChange:
                    byDay[CalendarDay(from: sample.timestamp, in: calendar), default: []]
                        .append(sample)
                case .manual, .evidenceImplied:
                    continue
            }
        }
        return byDay.mapValues { $0.sorted { $0.timestamp < $1.timestamp } }
    }
}
