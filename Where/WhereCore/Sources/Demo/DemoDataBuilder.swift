import Foundation
import RegionKit

/// Builds the dataset the app's demo mode runs on: a plausible year of living
/// in New York with a few California trips, written into whatever services it
/// is handed.
///
/// It exists to make an *empty* app demonstrable, so it deliberately produces
/// the messy shapes a real year has rather than a clean one — GPS gaps, days
/// backfilled by hand afterwards, and a couple of corrected attributions — so
/// that the calendar, the year report, and the Resolve tab all have something
/// true to show. Everything is bound to the **current** year and stops at
/// `now`: a demo entered in March shows a March-shaped year, not a full one.
///
/// The script is derived from the year, so entering demo mode twice in a day
/// produces the same data. Trip and gap placement is proportional to the part
/// of the year that has elapsed, so the shape holds up whether it's February
/// or December.
///
/// Note strings on the manual entries are deliberately plain English literals
/// rather than catalog lookups: they stand in for what a user typed, the same
/// as the coordinates stand in for where they went, and neither is app chrome.
public struct DemoDataBuilder: Sendable {
    /// Where the demo user lives. Coordinates verified to fall inside the
    /// bundled polygons (the same set `NewYorkHeavyYearTests` pins).
    private static let newYorkPlaces = [
        Coordinate(latitude: 40.7128, longitude: -74.0060), // Manhattan
        Coordinate(latitude: 40.6782, longitude: -73.9442), // Brooklyn
        Coordinate(latitude: 40.7891, longitude: -73.1350), // Long Island
    ]

    /// Where the demo user travels.
    private static let californiaPlaces = [
        Coordinate(latitude: 37.7749, longitude: -122.4194), // San Francisco
        Coordinate(latitude: 34.0522, longitude: -118.2437), // Los Angeles
    ]

    /// The tracked set the demo commits, in pick order. Two regions rather
    /// than the default four: the point is a legible year, and every day in
    /// the script belongs to one of these.
    private static let primaryRegions = [
        PrimaryRegion(
            region: .newYork,
            appearance: RegionAppearance(color: .indigo, emoji: "🗽", symbolName: "building.2"),
            order: 0,
        ),
        PrimaryRegion(
            region: .california,
            appearance: RegionAppearance(color: .orange, emoji: "🌉", symbolName: "sun.max"),
            order: 1,
        ),
    ]

    private let now: Date
    private let calendar: Calendar

    /// - Parameters:
    ///   - now: the instant the demo year runs up to — its last day, and the
    ///     year every date is placed in.
    ///   - calendar: the calendar the days are laid out in. Must be the one
    ///     the reading side aggregates with (Gregorian, current time zone), or
    ///     the seeded days land in different buckets than they're read from.
    public init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    /// Write the demo year into `services`: the tracked regions, then the
    /// year's GPS, then the manual backfills and corrections layered over it.
    ///
    /// Ordered deliberately — the tracked regions first, so attribution is
    /// scoped to New York and California before any sample is read back, and
    /// the GPS in one bulk transaction, so the widget snapshot and issue scan
    /// are reconciled once rather than per day.
    public func seed(into services: WhereServices) async throws {
        try await services.setPrimaryRegions(Self.primaryRegions)

        let script = makeScript()
        try await services.journal.ingest(script.samples)
        for entry in script.backfills {
            try await services.journal.addManualDay(
                date: entry.date,
                regions: entry.regions,
                audit: entry.audit,
            )
        }
        for entry in script.corrections {
            try await services.journal.overrideDay(
                date: entry.date,
                regions: entry.regions,
                audit: entry.audit,
            )
        }
    }

    // MARK: - The script

    /// What one day of the demo year looks like. An enum rather than a set of
    /// flags, because a day is exactly one of these — GPS-covered at home,
    /// away, in transit, missing, or corrected after the fact.
    private enum DayKind {
        /// A normal day at home, covered by GPS.
        case home
        /// A day on a trip, covered by GPS.
        case away
        /// A travel day: GPS in both regions, so the day counts for both.
        case travel
        /// No GPS at all, filled in by hand afterwards.
        case backfilled
        /// No GPS and never filled in — the gaps the Resolve tab surfaces.
        case missing
        /// GPS says home, but the user corrected the day to California.
        case corrected
    }

    /// A manual day the script writes after the GPS.
    private struct ManualEntry {
        let date: Date
        let regions: Set<Region>
        let audit: ManualEntryAudit
    }

    private struct Script {
        var samples: [LocationSample] = []
        var backfills: [ManualEntry] = []
        var corrections: [ManualEntry] = []
    }

    private func makeScript() -> Script {
        let elapsedDays = dayOfYear(for: now)
        guard elapsedDays > 0 else { return Script() }

        let kinds = dayKinds(elapsedDays: elapsedDays)
        var random = SeededRandom(seed: UInt64(year(of: now)))
        var script = Script()

        for day in 1 ... elapsedDays {
            let kind = kinds[day] ?? .home
            guard let date = date(dayOfYear: day) else { continue }
            switch kind {
                case .home, .corrected:
                    script.samples += samples(on: date, in: Self.newYorkPlaces, using: &random)
                case .away:
                    script.samples += samples(on: date, in: Self.californiaPlaces, using: &random)
                case .travel:
                    // Morning at home, evening at the destination: one day, two
                    // regions, which is exactly the case a day-count audit has
                    // to get right.
                    script.samples.append(sample(
                        on: date,
                        hour: 7,
                        at: Self.newYorkPlaces[0],
                        source: .gpsVisit,
                        using: &random,
                    ))
                    script.samples.append(sample(
                        on: date,
                        hour: 21,
                        at: Self.californiaPlaces[0],
                        source: .gpsSignificantChange,
                        using: &random,
                    ))
                case .backfilled, .missing:
                    break
            }

            switch kind {
                case .backfilled:
                    script.backfills.append(ManualEntry(
                        date: date,
                        regions: [.newYork],
                        audit: audit(
                            recordedAt: date.addingTimeInterval(4 * 24 * 60 * 60),
                            note: "Phone was off — added from my calendar.",
                        ),
                    ))
                case .corrected:
                    script.corrections.append(ManualEntry(
                        date: date,
                        regions: [.california],
                        audit: audit(
                            recordedAt: date.addingTimeInterval(2 * 24 * 60 * 60),
                            note: "Red-eye out — the day belongs to California.",
                        ),
                    ))
                case .home, .away, .travel, .missing:
                    break
            }
        }
        return script
    }

    /// Lay the year out day by day. Painted in passes — a baseline of days at
    /// home, then the trips over it, then the gaps, then the corrections — so
    /// overlapping windows resolve to the last pass rather than to whichever
    /// loop happened to run last.
    private func dayKinds(elapsedDays: Int) -> [Int: DayKind] {
        var kinds: [Int: DayKind] = [:]
        for day in 1 ... elapsedDays {
            kinds[day] = .home
        }

        func day(atFraction fraction: Double) -> Int {
            max(1, min(elapsedDays, Int((Double(elapsedDays) * fraction).rounded())))
        }

        // Three trips spread across the elapsed year, each bracketed by a
        // travel day in each direction.
        for (fraction, length) in [(0.18, 6), (0.47, 11), (0.78, 8)] {
            let start = day(atFraction: fraction)
            let end = min(elapsedDays, start + length)
            guard end > start + 1 else { continue }
            kinds[start] = .travel
            for middle in (start + 1) ..< end {
                kinds[middle] = .away
            }
            kinds[end] = .travel
        }

        // A week with the phone off: half reconstructed from a calendar, half
        // never filled in.
        let gapStart = day(atFraction: 0.33)
        for offset in 0 ..< 4 where gapStart + offset <= elapsedDays {
            kinds[gapStart + offset] = .backfilled
        }
        for offset in 4 ..< 7 where gapStart + offset <= elapsedDays {
            kinds[gapStart + offset] = .missing
        }

        // A recent couple of missing days, so the Resolve tab has something
        // current to offer rather than only ancient history.
        for offset in 4 ... 5 where elapsedDays - offset >= 1 {
            kinds[elapsedDays - offset] = .missing
        }

        // Two days the user corrected after the fact.
        for fraction in [0.62, 0.9] {
            let corrected = day(atFraction: fraction)
            if kinds[corrected] == .home {
                kinds[corrected] = .corrected
            }
        }
        return kinds
    }

    // MARK: - Samples

    /// One to three fixes across the day, the first as a visit and the rest as
    /// significant-change updates — the mix passive tracking actually
    /// produces.
    private func samples(
        on date: Date,
        in places: [Coordinate],
        using random: inout SeededRandom,
    ) -> [LocationSample] {
        let count = 1 + Int(random.next(upperBound: 3))
        return (0 ..< count).map { index in
            sample(
                on: date,
                hour: 8 + index * 5,
                at: places[Int(random.next(upperBound: UInt64(places.count)))],
                source: index == 0 ? .gpsVisit : .gpsSignificantChange,
                using: &random,
            )
        }
    }

    private func sample(
        on date: Date,
        hour: Int,
        at place: Coordinate,
        source: SampleSource,
        using random: inout SeededRandom,
    ) -> LocationSample {
        let coordinate = Coordinate(
            latitude: place.latitude + jitter(using: &random),
            longitude: place.longitude + jitter(using: &random),
        )
        let timestamp = calendar.date(byAdding: .hour, value: hour, to: date) ?? date
        return LocationSample(
            timestamp: timestamp,
            coordinate: coordinate,
            horizontalAccuracy: Double(10 + random.next(upperBound: 40)),
            source: source,
        )
    }

    /// A few hundred metres of wander around a place's anchor, so the map and
    /// the representative-coordinate math see a cloud rather than one pin —
    /// small enough that a point can't wander out of the region it anchors.
    private func jitter(using random: inout SeededRandom) -> Double {
        (Double(random.next(upperBound: 200)) - 100) / 20000
    }

    private func audit(recordedAt: Date, note: String) -> ManualEntryAudit {
        // No captured location: these entries are fabricated, and inventing a
        // "where I was when I typed this" fix would be a lie the audit trail
        // is specifically there not to tell.
        ManualEntryAudit(recordedAt: min(recordedAt, now), note: note, location: nil)
    }

    // MARK: - Dates

    private func year(of date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    private func dayOfYear(for date: Date) -> Int {
        calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    /// The start of `dayOfYear` in the demo's year. Counted forward from
    /// January 1 rather than built from a `DateComponents(day:)`, which means
    /// day-of-*month* and would only land right by way of overflow
    /// normalization.
    private func date(dayOfYear: Int) -> Date? {
        guard let startOfYear = calendar.date(from: DateComponents(
            year: year(of: now),
            month: 1,
            day: 1,
        )) else { return nil }
        return calendar.date(byAdding: .day, value: dayOfYear - 1, to: startOfYear)
    }
}

/// A deterministic SplitMix64 generator, so the demo year is the same every
/// time it is built within a given year. Not `RandomNumberGenerator` because
/// nothing here needs the protocol — the script only draws small bounded
/// values.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return (z ^ (z >> 31)) % upperBound
    }
}
