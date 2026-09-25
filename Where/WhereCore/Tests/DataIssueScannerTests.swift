import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct DataIssueScannerTests {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
        ))!)
    }

    private static func time(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeServices(now: @escaping @Sendable () -> Date) throws -> WhereServices {
        let store = try SwiftDataStore.inMemory()
        return WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            aggregator: DayAggregator(calendar: Self.calendar, timeZone: Self.calendar.timeZone),
            now: now,
        )
    }

    private func makeScanner(
        store: SwiftDataStore,
        now: @escaping @Sendable () -> Date,
        scanInterval: TimeInterval = 3600,
    ) -> DataIssueScanner {
        let reader = ReportReader(
            store: store,
            aggregator: DayAggregator(calendar: Self.calendar, timeZone: Self.calendar.timeZone),
            attributor: RegionAttributor.shared,
        )
        return DataIssueScanner(
            reportReader: reader,
            attributor: RegionAttributor.shared,
            calendar: Self.calendar,
            now: now,
            scanInterval: scanInterval,
        )
    }

    private func makeReviewScanner(
        store: SwiftDataStore,
        now: @escaping @Sendable () -> Date,
        attributor: any RegionAttributing = SampleCorrectionTestSupport.attribution,
        detectors: [any DataIssueDetecting] = [],
        storeChanges: AsyncStream<Void> = AsyncStream { $0.finish() },
    ) -> DataIssueScanner {
        DataIssueScanner(
            reportReader: ReportReader(
                store: store,
                aggregator: SampleCorrectionTestSupport.aggregator,
                attributor: attributor,
            ),
            attributor: attributor,
            calendar: SampleCorrectionTestSupport.calendar,
            now: now,
            scanInterval: 3 * 60 * 60,
            detectors: detectors,
            storeChanges: storeChanges,
        )
    }

    @Test(arguments: [false, true])
    func dismissalRemovesReadyReviewWithItsIssue(isFlight: Bool) async throws {
        let store = try SwiftDataStore.inMemory()
        let samples = isFlight ? FlightTrajectoryFixtures.turningFlight().samples : [
            SampleCorrectionAssessmentFixtures.point(101, minutes: 0, longitude: -0.001),
            SampleCorrectionAssessmentFixtures.point(102, minutes: 5, longitude: 0.0005),
            SampleCorrectionAssessmentFixtures.point(103, minutes: 10, longitude: -0.001),
        ]
        try await store.perform {
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        let attributor: any RegionAttributing = isFlight
            ? SampleCorrectionTestSupport.attribution : SampleCorrectionAssessmentFixtures
            .Boundary()
        let scanner = makeReviewScanner(
            store: store,
            now: { FlightTrajectoryFixtures.date(minutes: 150) },
            attributor: attributor,
        )
        let initial = try await scanner.scan(
            year: 2026,
            primaryRegions: attributor.loadedRegions,
            driftThresholdMeters: 1000,
            force: true,
        )
        let issue = try #require(initial.issues.first)
        try #require(initial.reviews.first?.proposal != nil)
        try await store.perform { try await store.setIssueDismissed(true, id: issue.id) }
        let dismissed = try await scanner.scan(
            year: 2026,
            primaryRegions: attributor.loadedRegions,
            driftThresholdMeters: 1000,
            force: true,
        )
        #expect(dismissed.issues.isEmpty)
        #expect(dismissed.reviews.isEmpty)
        #expect(dismissed.nextReassessmentAt == nil)
    }

    @Test(arguments: [false, true])
    func dismissalRetainsInformationalFlightReviews(isCompleted: Bool) async throws {
        let store = try SwiftDataStore.inMemory()
        let trace = FlightTrajectoryFixtures.turningFlight()
        let now = isCompleted ? trace.readyAt : trace.lastCruiseAt
        let day = CalendarDay(from: now, in: SampleCorrectionTestSupport.calendar)
        let reviewID = DataIssueID.flightDay(day: day)
        try await store.perform {
            for sample in trace.samples where sample.timestamp <= now {
                try await store.add(sample: sample)
            }
            if isCompleted {
                try await store.setManualDay(DayPresence(
                    day: day,
                    regions: [.california],
                    isAuthoritative: true,
                ))
            }
            try await store.setIssueDismissed(true, id: reviewID)
        }
        let scanner = makeReviewScanner(store: store, now: { now })
        let scan = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: true,
        )
        #expect(scan.issues.isEmpty)
        let review = try #require(scan.reviews.first)
        #expect(review.id == reviewID)
        #expect(review.proposal == nil)
        #expect(review.isPending == !isCompleted)
    }

    @Test func scanPublishesPendingReviewsWithoutActionableGPSIssues() async throws {
        let store = try SwiftDataStore.inMemory()
        let now = FlightTrajectoryFixtures.date(minutes: 25)
        let samples = FlightTrajectoryFixtures.turningFlight().samples
            .filter { $0.timestamp <= now }
        try await store.perform {
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        let scanner = makeReviewScanner(store: store, now: { now })
        let first = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        let review = try #require(first.reviews.first)
        #expect(review.isPending)
        #expect(review.proposal == nil)
        #expect(review.flight?.progress == .flightLikely)
        #expect(first.issues.isEmpty)
        #expect(try await scanner.currentIssueCount(year: 2026, driftThresholdMeters: 1000) == 0)
        let repeated = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        // The issue count's independently ranked primary set can change the key;
        // the next call with this same key must publish one coherent result.
        let cached = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(cached.revision == repeated.revision)
        #expect(cached.reviews == repeated.reviews)
        #expect(cached.issues.map(\.id) == repeated.issues.map(\.id))
    }

    @Test func flightFreshnessDeadlineExpiresTheCacheBeforeTheScanInterval() async throws {
        let store = try SwiftDataStore.inMemory()
        let clock = MutableClock(FlightTrajectoryFixtures.date(minutes: 25))
        let samples = FlightTrajectoryFixtures.turningFlight().samples
            .filter { $0.timestamp <= clock.now }
        try await store.perform {
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        let scanner = makeReviewScanner(store: store, now: { clock.now })
        let first = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(first.nextReassessmentAt == FlightTrajectoryFixtures.date(minutes: 55))
        clock.advance(by: 1799)
        let beforeDeadline = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(beforeDeadline.revision == first.revision)
        clock.advance(by: 1)
        let expired = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(expired.revision != first.revision)
        let review = try #require(expired.reviews.first)
        #expect(review.flight?.progress == .awaitingArrival)
        #expect(review.isPending)
        #expect(review.proposal == nil)
        #expect(expired.issues.isEmpty)
    }

    @Test func midnightFlightReviewsOwnTheirTransitionBeforeAndAfterArrival() async throws {
        let store = try SwiftDataStore.inMemory()
        let unrelatedEarlier = CalendarDay(year: 2026, month: 1, day: 1)
        let unrelatedLater = CalendarDay(year: 2026, month: 1, day: 2)
        let departureDay = CalendarDay(year: 2026, month: 1, day: 4)
        let arrivalDay = CalendarDay(year: 2026, month: 1, day: 5)
        let unrelatedID = DataIssueID.abruptChange(earlier: unrelatedEarlier, later: unrelatedLater)
        let flightTransitionID = DataIssueID.abruptChange(earlier: departureDay, later: arrivalDay)
        let clock = MutableClock(FlightTrajectoryFixtures.date(minutes: 5768))
        // Grounded in California just before midnight, then sustained flight
        // over Other after midnight. The resulting day sets are disjoint.
        let samples = [
            FlightTrajectoryFixtures.sample(1, minutes: 5750, east: 0),
            FlightTrajectoryFixtures.sample(2, minutes: 5755, east: 0),
            FlightTrajectoryFixtures.sample(3, minutes: 5758, east: 0),
            FlightTrajectoryFixtures.sample(4, minutes: 5763, east: 75),
            FlightTrajectoryFixtures.sample(5, minutes: 5768, east: 150),
        ]
        try await store.perform {
            try await store.setManualDay(DayPresence(day: unrelatedEarlier, regions: [.newYork]))
            try await store.setManualDay(DayPresence(day: unrelatedLater, regions: [.canada]))
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        let reader = ReportReader(
            store: store,
            aggregator: SampleCorrectionTestSupport.aggregator,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        let report = try await reader.yearReport(for: 2026)
        let abruptChanges = AbruptLocationChangeDetector().detectIssues(
            in: DataIssueDetectorFixtures.input(days: report.days),
        )
        #expect(Set(abruptChanges.map(\.id)) == [unrelatedID, flightTransitionID])
        let scanner = makeReviewScanner(
            store: store,
            now: { clock.now },
            detectors: [AbruptLocationChangeDetector()],
        )
        let pending = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(Set(pending.reviews.map(\.day.day)) == [departureDay, arrivalDay])
        let allPending = pending.reviews.allSatisfy(\.isPending)
        #expect(allPending)
        #expect(pending.reviews.allSatisfy { $0.flight?.progress == .flightLikely })
        #expect(pending.issues.map(\.id) == [unrelatedID])

        clock.advance(by: 30 * 60)
        let stale = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        let allStillPending = stale.reviews.allSatisfy(\.isPending)
        #expect(allStillPending)
        #expect(stale.reviews.allSatisfy { $0.flight?.progress == .awaitingArrival })
        #expect(stale.issues.map(\.id) == [unrelatedID])

        // Late callbacks establish a real ten-minute ground dwell. Arrival
        // exposes the precise GPS edit without reviving a whole-day rewrite.
        try await store.perform {
            try await store.add(sample: FlightTrajectoryFixtures.sample(
                6,
                minutes: 5773,
                east: 150,
            ))
            try await store.add(sample: FlightTrajectoryFixtures.sample(
                7,
                minutes: 5778,
                east: 150,
            ))
        }
        await scanner.invalidate()
        let completed = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        let hasPendingReview = completed.reviews.contains(where: \.isPending)
        #expect(!hasPendingReview)
        #expect(completed.reviews.allSatisfy {
            $0.flight?
                .progress == .completed(arrivedAt: FlightTrajectoryFixtures.date(minutes: 5768))
        })
        #expect(Set(completed.issues.map(\.id)) == [unrelatedID, .flightDay(day: arrivalDay)])
        let proposal = try #require(completed.reviews.first { $0.day.day == arrivalDay }?.proposal)
        #expect(proposal.edits.map(\.sampleID) == [FlightTrajectoryFixtures.sampleID(4)])
    }

    @Test func driftOnlyReviewDoesNotSuppressAnAbruptTransition() async throws {
        let store = try SwiftDataStore.inMemory()
        let earlier = CalendarDay(year: 2026, month: 1, day: 1)
        let later = CalendarDay(year: 2026, month: 1, day: 2)
        let samples = [
            SampleCorrectionAssessmentFixtures.point(1, minutes: 1440, longitude: -0.001),
            SampleCorrectionAssessmentFixtures.point(2, minutes: 1445, longitude: 0.001),
            SampleCorrectionAssessmentFixtures.point(3, minutes: 1450, longitude: -0.001),
        ]
        try await store.perform {
            try await store.setManualDay(DayPresence(day: earlier, regions: [.newYork]))
            for sample in samples {
                try await store.add(sample: sample)
            }
        }
        let scanner = makeReviewScanner(
            store: store,
            now: { FlightTrajectoryFixtures.date(minutes: 1460) },
            attributor: SampleCorrectionAssessmentFixtures.Boundary(),
            detectors: [AbruptLocationChangeDetector()],
        )
        let result = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        let review = try #require(result.reviews.first)
        #expect(review.flights.isEmpty)
        #expect(review.proposal != nil)
        #expect(Set(result.issues.map(\.id)) == [
            .abruptChange(earlier: earlier, later: later),
            .borderDrift(day: later),
        ])
    }

    @Test func primaryRegionChangesInvalidateTheCoherentResultKey() async throws {
        let store = try SwiftDataStore.inMemory()
        let now = FlightTrajectoryFixtures.date(minutes: 25)
        let scanner = makeReviewScanner(store: store, now: { now })
        let first = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 1000,
            force: false,
        )
        let changed = try await scanner.scan(
            year: 2026,
            primaryRegions: [.newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(changed.revision != first.revision)
        let repeated = try await scanner.scan(
            year: 2026,
            primaryRegions: [.newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(repeated.revision == changed.revision)
    }

    @Test func aRawFixRefreshesReviewsWhenTheAggregateReportIsUnchanged() async throws {
        let store = try SwiftDataStore.inMemory()
        let now = FlightTrajectoryFixtures.date(minutes: 30)
        let trace = FlightTrajectoryFixtures.turningFlight()
        let initialSamples = trace.samples.filter {
            $0.timestamp <= FlightTrajectoryFixtures.date(minutes: 25)
        }
        try await store.perform {
            for sample in initialSamples {
                try await store.add(sample: sample)
            }
        }
        let scanner = makeReviewScanner(store: store, now: { now }, storeChanges: store.changes())
        let reader = ReportReader(
            store: store,
            aggregator: SampleCorrectionTestSupport.aggregator,
            attributor: SampleCorrectionTestSupport.attribution,
        )
        let beforeReport = try await reader.yearReport(for: 2026)
        let first = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        let denseFix = try #require(trace.samples.first { $0.id == trace.shortIntervalID })
        try await store.perform { try await store.add(sample: denseFix) }
        let afterReport = try await reader.yearReport(for: 2026)
        #expect(beforeReport.days == afterReport.days)
        #expect(beforeReport.totals == afterReport.totals)
        try await waitUntil {
            let scan = try await scanner.scan(
                year: 2026,
                primaryRegions: [.california, .newYork],
                driftThresholdMeters: 1000,
                force: false,
            )
            return scan.revision != first.revision
        }
        let refreshed = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(refreshed.revision != first.revision)
        #expect(refreshed.reviews.first?.flight?.lastObservationAt == denseFix.timestamp)
        #expect(refreshed.reviews.first?.flight?.lastObservationAt
            != first.reviews.first?.flight?.lastObservationAt)
    }

    @Test func invalidationDuringASuspendedReadCannotRepublishTheOldScan() async throws {
        let store = try SwiftDataStore.inMemory()
        let clock = MutableClock(FlightTrajectoryFixtures.date(minutes: 20))
        let trace = FlightTrajectoryFixtures.turningFlight()
        let initial = trace.samples.filter { $0.timestamp <= clock.now }
        try await store.perform {
            for sample in initial {
                try await store.add(sample: sample)
            }
        }
        let next = try #require(trace.samples
            .first { $0.timestamp == FlightTrajectoryFixtures.date(minutes: 25) })
        let (writerStarted, writerStartedContinuation) = AsyncStream.makeStream(of: Void.self)
        let (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
        let (scanStarted, scanStartedContinuation) = AsyncStream.makeStream(of: Void.self)
        defer {
            releaseContinuation.yield()
            releaseContinuation.finish()
            writerStartedContinuation.finish()
            scanStartedContinuation.finish()
        }
        let scanner = makeReviewScanner(store: store, now: {
            let captured = clock.now
            scanStartedContinuation.yield()
            return captured
        })
        let writer = Task {
            try await store.perform {
                try await store.add(sample: next)
                writerStartedContinuation.yield()
                writerStartedContinuation.finish()
                for await _ in release {
                    break
                }
            }
        }
        for await _ in writerStarted {
            break
        }
        let scan = Task {
            try await scanner.scan(
                year: 2026,
                primaryRegions: [.california, .newYork],
                driftThresholdMeters: 1000,
                force: false,
            )
        }
        for await _ in scanStarted {
            break
        }
        // The scanner captured 00:20 and then suspended behind the store's
        // exclusive writer. Actor ordering places this invalidation after its
        // revision capture; the committed fix only becomes visible afterward.
        clock.advance(by: 300)
        await scanner.invalidate()
        releaseContinuation.yield()
        releaseContinuation.finish()
        try await writer.value
        let result = try await scan.value
        let review = try #require(result.reviews.first)
        #expect(review.isPending)
        #expect(review.flight?.lastObservationAt == next.timestamp)
        #expect(review.flight?.progress == .flightLikely)
        let cached = try await scanner.scan(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 1000,
            force: false,
        )
        #expect(cached.revision == result.revision)
        #expect(cached.reviews == result.reviews)
    }

    /// The speed-based `FlightDayDetector` must ignore manual and
    /// evidence-implied samples: their timestamps are user-asserted, so a speed
    /// computed across them is meaningless. The exact coast-to-coast pattern
    /// that flags as GPS produces no flight issue when recorded as manual /
    /// evidence fixes (the scanner's `gpsSamplesByDay` filters them out).
    @Test func flightDetectionIgnoresManualAndEvidenceSamples() async throws {
        let store = try SwiftDataStore.inMemory()
        let fixedNow = Self.day(2026, 6, 15)
        let scanner = makeScanner(store: store, now: { fixedNow })

        let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781)
        let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790)
        let illinois = Coordinate(latitude: 40.29, longitude: -90.39)
        let colorado = Coordinate(latitude: 39.53, longitude: -106.16)
        let nevada = Coordinate(latitude: 38.68, longitude: -116.90)
        let evidence = SampleSource.evidenceImplied(id: UUID(), kind: .other(nil))
        let fixes: [(Int, Coordinate, SampleSource)] = [
            (8, jfk, .manual),
            (9, jfk, .manual),
            (12, jfk, .manual),
            (13, illinois, .manual),
            (14, colorado, .manual),
            (15, nevada, evidence),
            (17, sfo, .manual),
            (18, sfo, .manual),
        ]
        try await store.perform {
            for (hour, coordinate, source) in fixes {
                try await store.add(sample: LocationSample(
                    timestamp: Self.time(2026, 3, 15, hour),
                    coordinate: coordinate,
                    horizontalAccuracy: 20,
                    source: source,
                ))
            }
        }

        let issues = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 10000,
            force: true,
        )
        #expect(!issues.contains { $0.category == .flightDay })
    }

    @Test func issues_returnsSortedIssues() async throws {
        let fixedNow = Self.day(2026, 6, 15)
        let services = try makeServices(now: { fixedNow })
        let scanner = services.resolution

        let issues = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 10000,
            force: true,
        )
        #expect(!issues.isEmpty)
        #expect(issues.allSatisfy { $0.category == .missingDays })
    }

    @Test func issues_excludesDismissedKeys() async throws {
        let fixedNow = Self.day(2026, 6, 15)
        let services = try makeServices(now: { fixedNow })
        let scanner = services.resolution

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
            force: true,
        )
        guard let issue = first.first else {
            Issue.record("Expected at least one issue")
            return
        }

        try await services.journal.dismissIssue(id: issue.id)

        let second = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
            force: true,
        )
        #expect(second.allSatisfy { $0.id != issue.id })
    }

    /// Within the interval, a non-forced call serves the cached result even
    /// after the underlying dismissed set changes; once the interval elapses it
    /// recomputes and reflects the change. Dismissing one of the returned keys
    /// out from under the cache is the observable lever: a served cache still
    /// contains it, a recompute drops it.
    @Test func issues_throttleServesCacheUntilIntervalElapses() async throws {
        let clock = MutableClock(Self.day(2026, 6, 15))
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { clock.now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedID = try #require(first.first).id
        try await store.perform { try await store.setIssueDismissed(true, id: dismissedID) }

        // Within the interval: the cache is served, so the new dismissal is not
        // yet reflected.
        clock.advance(by: 30 * 60)
        let cached = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(cached.map(\.id) == first.map(\.id))
        #expect(cached.contains { $0.id == dismissedID })

        // Past the interval: recomputes and drops the dismissed issue.
        clock.advance(by: 4 * 60 * 60)
        let recomputed = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(!recomputed.contains { $0.id == dismissedID })
    }

    @Test func issues_forceRecomputesWithinInterval() async throws {
        let now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedID = try #require(first.first).id
        try await store.perform { try await store.setIssueDismissed(true, id: dismissedID) }

        // `force` ignores the throttle and reflects the dismissal immediately,
        // without advancing `now`.
        let forced = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
            force: true,
        )
        #expect(!forced.contains { $0.id == dismissedID })
    }

    @Test func issues_recomputesWhenThresholdChanges() async throws {
        let now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedID = try #require(first.first).id
        try await store.perform { try await store.setIssueDismissed(true, id: dismissedID) }

        // A different threshold is a cache-key miss, so it recomputes even
        // within the interval and without `force`.
        let differentThreshold = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 25000,
        )
        #expect(!differentThreshold.contains { $0.id == dismissedID })
    }

    /// A calendar-day rollover is a cache-key miss, so the scan recomputes even
    /// within `scanInterval` and without `force` — the missing-days backlog
    /// cutoff is day-relative, so a day that crosses it mid-throttle must show up
    /// without anyone tracking the rollover. Dismissing a returned key is the
    /// observable lever: a served cache still contains it, a recompute drops it.
    @Test func issues_recomputesWhenCalendarDayRollsOver() async throws {
        // 23:30 local, so a sub-`scanInterval` advance still crosses midnight.
        let clock = MutableClock(Self.day(2026, 6, 15).addingTimeInterval(23.5 * 60 * 60))
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { clock.now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedID = try #require(first.first).id
        try await store.perform { try await store.setIssueDismissed(true, id: dismissedID) }

        // 40 min later it is the next calendar day but still well inside the 1h
        // throttle, so only the day-key miss can drive the recompute that drops
        // the now-dismissed key.
        clock.advance(by: 40 * 60)
        let nextDay = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(!nextDay.contains { $0.id == dismissedID })
    }

    @Test func issues_recomputesWhenYearChanges() async throws {
        let now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { now })

        let currentYear = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        // A year switch is a cache-key miss: the second call must reflect 2025
        // (its missing range starts in Jan 2025), not the cached 2026 result.
        let pastYear = try await scanner.issues(
            year: 2025,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(currentYear.map(\.id) != pastYear.map(\.id))
        #expect(pastYear.contains { issue in
            guard case let .backfill(range) = issue.resolution else { return false }
            return range.start.year == 2025
        })
    }

    @Test func invalidate_forcesRecompute() async throws {
        let now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedID = try #require(first.first).id
        try await store.perform { try await store.setIssueDismissed(true, id: dismissedID) }

        await scanner.invalidate()

        // After invalidation the next call recomputes despite being within the
        // interval, so the dismissal is reflected.
        let afterInvalidate = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(!afterInvalidate.contains { $0.id == dismissedID })
    }

    /// The original bug's fix at the scanner level: a committed store change
    /// drops the cache *out-of-band* via the observed `store.changes()` stream,
    /// so a `force: false` reader stays honest even when no session is alive to
    /// force a rescan (a headless background ingest). Uses the real
    /// `WhereServices` assembly — which wires `storeChanges: store.changes()`
    /// into the scanner — so a severed subscription would fail this test.
    ///
    /// Dismissing a returned key is the observable lever: within the throttle
    /// interval the throttle would normally keep serving it (see
    /// `issues_throttleServesCacheUntilIntervalElapses`), but the dismissal's
    /// own commit pings `store.changes()`, so the next non-forced scan —
    /// `now` unchanged — recomputes and drops it.
    @Test func storeChangeSignalInvalidatesCacheForHeadlessReaders() async throws {
        let fixedNow = Self.day(2026, 6, 15)
        let services = try makeServices(now: { fixedNow })
        let scanner = services.resolution

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedID = try #require(first.first).id

        // Commit through the journal exactly as a headless write would; this
        // pings `store.changes()`, which the scanner observes asynchronously to
        // drop its cache. No `force`, no `invalidate()` call, `now` unchanged.
        try await services.journal.dismissIssue(id: dismissedID)

        try await waitUntil {
            let issues = try await scanner.issues(
                year: 2026,
                primaryRegions: [.california],
                driftThresholdMeters: 10000,
            )
            return !issues.contains { $0.id == dismissedID }
        }
    }
}

@Sendable
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @Sendable () async throws -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("waitUntil timed out")
}
