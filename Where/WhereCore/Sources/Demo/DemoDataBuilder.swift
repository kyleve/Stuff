import Foundation
import RegionKit

/// Builds the dataset the app's demo mode runs on: a plausible year of living
/// in New York with a few California trips, written into whatever services it
/// is handed.
///
/// It exists to make an *empty* app demonstrable, so it deliberately produces
/// the messy shapes a real year has rather than a clean one — days backfilled
/// by hand after the phone was off, a couple of corrected attributions, and a
/// few recent days still unlogged — so that the calendar, the year report, and
/// the Resolve tab all have something true to show. Everything is bound to the
/// **current** year and stops at `now`: a demo entered in March shows a
/// March-shaped year, not a full one.
///
/// The script is derived from the year, so entering demo mode twice in a day
/// produces the same data. Every feature is sized against how much of the year
/// has *elapsed* rather than against the calendar, so the shape holds wherever
/// it's entered: New York keeps roughly four days in five, California always
/// appears, and the outstanding issues stay few and recent. (Fixed sizes are
/// what made an early-January demo read as mostly-unlogged, and a February one
/// as mostly-California.)
///
/// Note strings on the manual entries are deliberately plain English literals
/// rather than catalog lookups: they stand in for what a user typed, the same
/// as the coordinates stand in for where they went, and neither is app chrome.
public struct DemoDataBuilder: Sendable {
    /// Selects which unresolved issue workflows the generated year demonstrates.
    public struct Configuration: Codable, Equatable, Sendable {
        public let issueCategories: Set<DataIssueCategory>

        public init(issueCategories: Set<DataIssueCategory>) {
            self.issueCategories = issueCategories
        }

        /// The one-tap onboarding demo's established shape.
        public static let standard = Configuration(issueCategories: [.missingDays])

        /// A developer showcase containing every Resolve workflow.
        public static let allIssues =
            Configuration(issueCategories: Set(DataIssueCategory.allCases))
    }

    /// Where the demo user lives. Coordinates verified to fall inside the
    /// bundled polygons (the same set `NewYorkHeavyYearTests` pins).
    private static let newYorkPlaces = [
        Coordinate(latitude: 40.7128, longitude: -74.0060), // Manhattan
        Coordinate(latitude: 40.6782, longitude: -73.9442), // Brooklyn
        Coordinate(latitude: 40.7891, longitude: -73.1350), // Long Island
    ]

    /// Where the demo user is "right now" — the fix a scripted location source
    /// should answer a one-shot request with, so today lands where the rest of
    /// the script says the user lives.
    public static var homeCoordinate: Coordinate {
        newYorkPlaces[0]
    }

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
            appearance: RegionAppearance(color: .indigo, emoji: "🗽", symbolName: .building2),
            order: 0,
        ),
        PrimaryRegion(
            region: .california,
            appearance: RegionAppearance(color: .orange, emoji: "🌉", symbolName: .sunMax),
            order: 1,
        ),
    ]

    private let now: Date
    private let calendar: Calendar
    private let configuration: Configuration

    /// - Parameters:
    ///   - now: the instant the demo year runs up to — its last day, and the
    ///     year every date is placed in.
    ///   - calendar: the calendar the days are laid out in. Must be the one
    ///     the reading side aggregates with (Gregorian, current time zone), or
    ///     the seeded days land in different buckets than they're read from.
    public init(now: Date, calendar: Calendar) {
        self.init(now: now, calendar: calendar, configuration: .standard)
    }

    /// Build a demo year containing exactly the requested issue categories.
    public init(now: Date, calendar: Calendar, configuration: Configuration) {
        self.now = now
        self.calendar = calendar
        self.configuration = configuration
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
        /// No GPS at all, filled in by hand afterwards — a lapse the user
        /// already dealt with, so it reads as history rather than a problem.
        case backfilled
        /// No GPS and not filled in: the outstanding issues the Resolve tab
        /// surfaces. Deliberately few and recent (see ``dayKinds(elapsedDays:)``).
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
        addConfiguredIssueFixtures(to: &script, elapsedDays: elapsedDays, using: &random)
        return script
    }

    /// How much of the elapsed year is spent away from home. Split across the
    /// trips, so the home/away balance reads the same in February as in
    /// December — the mistake a fixed trip length makes, where three
    /// fixed-length trips are most of a short year and a rounding error in a
    /// long one.
    private static let awayShareOfYear = 0.18

    /// The most days left unlogged, ever. Someone using the app deals with
    /// problems as they come up, so an honest year has a couple of loose ends
    /// rather than a backlog — and a demo that opens on a wall of them reads as
    /// a broken app, not a full one.
    private static let maximumUnloggedDays = 3

    /// How far back an unlogged day may be. Anything older would have been
    /// noticed and fixed by now, so old lapses appear as backfills instead.
    private static let unloggedWindow = 14

    /// Lay the year out day by day. Painted in passes — a baseline of days at
    /// home, then the trips over it, then the lapses, then the corrections — so
    /// overlapping windows resolve to the last pass rather than to whichever
    /// loop happened to run last.
    ///
    /// Everything is sized against `elapsedDays` rather than the calendar, so
    /// the *shape* holds wherever in the year the demo is entered: home is
    /// always roughly four days in five, both regions always appear, and the
    /// outstanding issues stay few and recent.
    private func dayKinds(elapsedDays: Int) -> [Int: DayKind] {
        var kinds: [Int: DayKind] = [:]
        for day in 1 ... elapsedDays {
            kinds[day] = .home
        }

        func day(atFraction fraction: Double) -> Int {
            max(1, min(elapsedDays, Int((Double(elapsedDays) * fraction).rounded())))
        }

        // Two trips, or three once the year is long enough to spread them over.
        // Fewer at a short span isn't a degradation — three separate trips
        // inside a fortnight would read as fiction.
        let tripStarts = elapsedDays >= 120 ? [0.18, 0.50, 0.82] : [0.25, 0.75]
        let tripLength = max(
            2,
            Int((Double(elapsedDays) * Self.awayShareOfYear / Double(tripStarts.count)).rounded()),
        )
        var previousReturn = 0
        for fraction in tripStarts {
            let start = day(atFraction: fraction)
            let end = start + tripLength
            // Leave at least a day at home between trips, and never run past
            // today — a trip clipped by "now" would read as one still underway.
            guard start > previousReturn + 1, end <= elapsedDays else { continue }
            kinds[start] = .travel
            for middle in (start + 1) ..< end {
                kinds[middle] = .away
            }
            kinds[end] = .travel
            previousReturn = end
        }

        // A stretch with the phone off, reconstructed at the time: fully
        // backfilled, so it shows the manual-entry trail without pretending
        // the user left a hole in their own records.
        if elapsedDays >= 30 {
            let start = day(atFraction: 0.38)
            let length = min(5, max(2, Int((Double(elapsedDays) * 0.015).rounded())))
            for offset in 0 ..< length where start + offset <= elapsedDays {
                if kinds[start + offset] == .home {
                    kinds[start + offset] = .backfilled
                }
            }
        }

        // The outstanding issues: a few recent days nothing was recorded for.
        // Only plain days at home are eligible, so a lapse never eats a trip's
        // travel day, and never today — which the app itself would fill in.
        if configuration.issueCategories.contains(.missingDays) {
            let unloggedCount = min(Self.maximumUnloggedDays, max(1, elapsedDays / 30))
            var unlogged = 0
            for offset in Self.unloggedDayOffsets where unlogged < unloggedCount {
                let candidate = elapsedDays - offset
                guard candidate >= 1, kinds[candidate] == .home else { continue }
                kinds[candidate] = .missing
                unlogged += 1
            }
        }

        // A day or two the user corrected after the fact.
        let correctionPoints = elapsedDays >= 60 ? [0.62, 0.9] : [0.62]
        for fraction in correctionPoints {
            let corrected = day(atFraction: fraction)
            if kinds[corrected] == .home {
                kinds[corrected] = .corrected
                // Keep the correction from manufacturing an abrupt-change
                // issue unless that category was explicitly requested.
                for neighbor in [corrected - 1, corrected + 1]
                    where kinds[neighbor] == .home
                {
                    kinds[neighbor] = .travel
                }
            }
        }
        return kinds
    }

    /// Layer deterministic detector fixtures over the plausible baseline.
    /// Each fixture owns complete days so categories remain independently selectable.
    private func addConfiguredIssueFixtures(
        to script: inout Script,
        elapsedDays: Int,
        using random: inout SeededRandom,
    ) {
        guard elapsedDays > 0 else { return }

        func allocatedDay(_ fraction: Double, minimum: Int) -> Int {
            max(minimum, min(elapsedDays, Int((Double(elapsedDays) * fraction).rounded())))
        }

        if configuration.issueCategories.contains(.abruptChange), elapsedDays >= 3 {
            let first = elapsedDays < 30 ? 2 : allocatedDay(0.30, minimum: 2)
            replaceDay(first, in: &script) { date in
                samples(on: date, in: Self.californiaPlaces, using: &random)
            }
            replaceDay(min(first + 1, elapsedDays), in: &script) { date in
                samples(on: date, in: Self.newYorkPlaces, using: &random)
            }
        }

        if configuration.issueCategories.contains(.borderDrift), elapsedDays >= 4 {
            let day = elapsedDays < 30 ? 4 : allocatedDay(0.44, minimum: 4)
            replaceDay(day, in: &script) { date in
                var samples = samples(on: date, in: Self.newYorkPlaces, using: &random)
                for point in Self.borderDriftCoordinates {
                    samples.append(sample(
                        on: date,
                        hour: 18 + samples.count,
                        at: point,
                        source: .gpsSignificantChange,
                        using: &random,
                        jittersCoordinate: false,
                    ))
                }
                return samples
            }
        }

        if configuration.issueCategories.contains(.flightDay), elapsedDays >= 5 {
            let day = elapsedDays < 30 ? 5 : allocatedDay(0.70, minimum: 5)
            replaceDay(day, in: &script) { date in
                Self.flightCoordinates.enumerated().map { index, coordinate in
                    sample(
                        on: date,
                        hour: 8 + index,
                        at: coordinate,
                        source: index == 0 ? .gpsVisit : .gpsSignificantChange,
                        using: &random,
                        jittersCoordinate: false,
                    )
                }
            }
        }

        // On a very short year the ordinary recent-gap allocator can collide
        // with the fixed detector fixtures. Reserve day one as the gap.
        if configuration.issueCategories.contains(.missingDays), elapsedDays < 30 {
            clear(dayOfYear: 1, in: &script)
        }
    }

    private static let borderDriftCoordinates = [
        Coordinate(latitude: 40.80015, longitude: -73.99439),
        Coordinate(latitude: 40.81084, longitude: -73.98805),
    ]

    private static let flightCoordinates = [
        Coordinate(latitude: 40.6413, longitude: -73.7781),
        Coordinate(latitude: 40.6413, longitude: -73.7781),
        Coordinate(latitude: 40.29, longitude: -90.39),
        Coordinate(latitude: 39.53, longitude: -106.16),
        Coordinate(latitude: 38.68, longitude: -116.90),
        Coordinate(latitude: 37.6213, longitude: -122.3790),
        Coordinate(latitude: 37.6213, longitude: -122.3790),
    ]

    private func replaceDay(
        _ dayOfYear: Int,
        in script: inout Script,
        with makeSamples: (Date) -> [LocationSample],
    ) {
        guard let date = date(dayOfYear: dayOfYear) else { return }
        clear(dayOfYear: dayOfYear, in: &script)
        script.samples.append(contentsOf: makeSamples(date))
    }

    private func clear(dayOfYear: Int, in script: inout Script) {
        guard let date = date(dayOfYear: dayOfYear) else { return }
        script.samples.removeAll { calendar.isDate($0.timestamp, inSameDayAs: date) }
        script.backfills.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
        script.corrections.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Days back from today to consider leaving unlogged, spaced first so the
    /// lapses read as separate slips rather than one long outage, then filling
    /// in from the rest of the window for a span too short to hold the spaced
    /// ones.
    private static let unloggedDayOffsets: [Int] = {
        let spaced = [2, 5, 9, 12]
        return spaced + (2 ... unloggedWindow - 1).filter { !spaced.contains($0) }
    }()

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
        jittersCoordinate: Bool = true,
    ) -> LocationSample {
        let coordinate = Coordinate(
            latitude: place.latitude + (jittersCoordinate ? jitter(using: &random) : 0),
            longitude: place.longitude + (jittersCoordinate ? jitter(using: &random) : 0),
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
