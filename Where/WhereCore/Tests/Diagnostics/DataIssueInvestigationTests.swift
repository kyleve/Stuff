import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct DataIssueInvestigationTests {
    @Test func copiedCruiseReplayReproducesAFlightCorrectionWithoutApplyingIt() throws {
        let day = CalendarDay(year: 2026, month: 7, day: 14)
        let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781)
        let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790)
        let presence = DayPresence(day: day, regions: [.newYork, .other, .california])
        let samples = [
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 8, jfk),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 8.5, jfk),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 12, jfk),
            DataIssueDetectorFixtures.gpsSample(
                day: day,
                hoursAfterStart: 13.5,
                Coordinate(latitude: 40.29, longitude: -90.39),
            ),
            DataIssueDetectorFixtures.gpsSample(
                day: day,
                hoursAfterStart: 15,
                Coordinate(latitude: 39.53, longitude: -106.16),
            ),
            DataIssueDetectorFixtures.gpsSample(
                day: day,
                hoursAfterStart: 16.5,
                Coordinate(latitude: 38.68, longitude: -116.90),
            ),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 17.5, sfo),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 18, sfo),
        ]
        let input = DataIssueDetectorFixtures.input(days: [presence], daySamples: [day: samples])
        let captured = DataIssueInvestigation(
            capturedAt: input.now,
            input: input,
            dismissedIssueIDs: [],
        )
        let issue = try #require(captured.replay(category: .flightDay).first)
        guard case let .correctFlightDay(original, keep, removed, peak) = issue.resolution else {
            Issue.record("Expected a proposed flight correction")
            return
        }
        #expect(original == presence)
        #expect(keep == [.newYork, .california])
        #expect(removed == [.other])
        #expect(peak > 300)
        #expect(captured.input.report.days.first { $0.day == day } == presence)
        #expect(captured.input.daySamples.samples(on: day) == samples)
    }

    @Test func copiedDriftReplayPreservesStoreDismissalsAndScannerCache() async throws {
        let calendar = WhereCoreTestSupport.calendar()
        let day = CalendarDay(year: 2026, month: 3, day: 1)
        let now = day.startOfDay(in: calendar).addingTimeInterval(12 * 3600)
        let store = try SwiftDataStore.inMemory()
        let reader = ReportReader(
            store: store,
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            attributor: RegionAttributor.shared,
        )
        let sample = LocationSample(
            timestamp: now,
            coordinate: Coordinate(latitude: 39.5296, longitude: -119.8138),
            horizontalAccuracy: 20,
            source: .gpsVisit,
        )
        try await store.perform { try await store.add(sample: sample) }
        let scanner = DataIssueScanner(
            reportReader: reader,
            attributor: RegionAttributor.shared,
            calendar: calendar,
            now: { now },
        )
        _ = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 50000,
        )
        let cacheBefore = await scanner.diagnosticState
        let initial = try await reader.investigation(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 50000,
            now: now,
        )
        let drift = try #require(initial.replay(category: .borderDrift).first)
        try await store.perform { try await store.setIssueDismissed(true, id: drift.id) }
        let captured = try await reader.investigation(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 50000,
            now: now,
        )
        let reportBefore = try await reader.yearReport(for: 2026)

        #expect(captured.replay(category: .borderDrift).map(\.id) == [drift.id])
        #expect(captured.replay(category: .flightDay).isEmpty)
        #expect(captured.dismissedIssueIDs == [drift.id])
        #expect(try await reader.yearReport(for: 2026) == reportBefore)
        #expect(try await reader.dismissedIssueIDs() == [drift.id])
        #expect(await scanner.diagnosticState == cacheBefore)

        try await store.perform { try await store.setManualDay(DayPresence(
            day: day,
            regions: [.california],
            isAuthoritative: true,
        )) }
        let later = try await reader.investigation(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 50000,
            now: now,
        )
        #expect(later.replay(category: .borderDrift).isEmpty)
        #expect(captured.replay(category: .borderDrift).map(\.id) == [drift.id])
        #expect(captured.input.daySamples.samples(on: day) == [sample])
    }

    @Test func copiedFlightReplayDistinguishesFlightFromCorrectableAttribution() {
        let day = CalendarDay(year: 2026, month: 7, day: 14)
        let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781)
        let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790)
        let chicago = Coordinate(latitude: 41.8781, longitude: -87.6298)
        let samples = [
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 8, jfk),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 9, jfk),
            DataIssueDetectorFixtures.gpsSample(
                day: day,
                hoursAfterStart: 11,
                Coordinate(latitude: 39.53, longitude: -106.16),
            ),
            DataIssueDetectorFixtures.gpsSample(
                day: day,
                hoursAfterStart: 12.5,
                Coordinate(latitude: 38.68, longitude: -116.90),
            ),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 14, chicago),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 15, chicago),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 16, chicago),
            DataIssueDetectorFixtures.gpsSample(day: day, hoursAfterStart: 19, sfo),
        ]
        let input = DataIssueDetectorFixtures.input(
            days: [DayPresence(day: day, regions: [.newYork, .other, .california])],
            daySamples: [day: samples],
        )
        let captured = DataIssueInvestigation(
            capturedAt: input.now,
            input: input,
            dismissedIssueIDs: [],
        )
        #expect(captured.replay(category: .flightDay).isEmpty)
        #expect(captured.input.daySamples.samples(on: day).count == 8)
        #expect(captured.input.attributor.region(at: chicago) == .other)
    }
}
