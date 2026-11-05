import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers the standalone read path the controller (and, later, the reminder /
/// daily-summary reconcilers) delegate every report read to.
struct ReportReaderTests {
    private static func makeReader() throws -> (ReportReader, SwiftDataStore) {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = ReportReader(
            store: store,
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
            history: LocationHistoryReader(
                store: store,
                policy: .foundation,
                geography: HistoryRegionAttribution(),
            ),
        )
        return (reader, store)
    }

    @Test func yearReportAggregatesSamplesAndManualDays() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-10T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
                recordingDay: nil,
            ))
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-01T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.newYork],
            ))
        }

        let report = try await reader.yearReport(for: 2026)
        #expect(report.days.count == 2)
        #expect(report.totals == [.california: 1, .newYork: 1])
    }

    @Test func yearReportAppliesDeviceRecordingCutoffs() async throws {
        let (reader, store) = try Self.makeReader()
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-10T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .gpsVisit,
                recordingDeviceID: deviceID,
                recordingDay: nil,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-12T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 0,
                source: .gpsVisit,
                recordingDeviceID: deviceID,
                recordingDay: nil,
            ))
            try await store.addRecordingDeviceRemoval(RecordingDeviceRemoval(
                id: .init(
                    rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                ),
                deviceID: deviceID,
                removedAt: WhereCoreTestSupport.iso("2026-01-11T00:00:00-08:00"),
                removedByDeviceID: deviceID,
            ))
        }

        let report = try await reader.yearReport(for: 2026)

        #expect(report.days.count == 1)
        #expect(report.totals == [.california: 1])
    }

    @Test func manualDaysReturnsOnlyTheRequestedYear() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-01T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.newYork],
            ))
            // A day just before the requested year (Pacific) must be excluded.
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2025-12-31T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.california],
            ))
        }

        let days = try await reader.manualDays(inYear: 2026)
        #expect(days.count == 1)
        #expect(days.first?.regions == [.newYork])
    }

    @Test func locationsAndRepresentativeCoordinatesReadFromSamples() async throws {
        let (reader, store) = try Self.makeReader()
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
                coordinate: sf,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
                recordingDay: nil,
            ))
        }

        let locations = try await reader.locations(in: .california, year: 2026)
        #expect(!locations.isEmpty)

        let representative = try await reader.representativeCoordinates(for: 2026)
        #expect(representative[.california] != nil)
    }

    @Test func locationsReadSeveralRegionsAndOnlyTheRequestedYear() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 15,
                source: .gpsSignificantChange,
                recordingDay: nil,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-04-15T12:00:00-04:00"),
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 25,
                source: .gpsSignificantChange,
                recordingDay: nil,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2025-04-15T12:00:00-04:00"),
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 35,
                source: .gpsSignificantChange,
                recordingDay: nil,
            ))
        }

        let locations = try await reader.locations(
            in: [.california, .newYork],
            year: 2026,
        )

        #expect(locations[.california]?.flatMap(\.points).map(\.horizontalAccuracy) == [15])
        #expect(locations[.newYork]?.flatMap(\.points).map(\.horizontalAccuracy) == [25])
    }

    @Test func yearReportDetailsKeepsRawFixesThatDoNotChangeTheReport() async throws {
        let (reader, store) = try Self.makeReader()
        let first = LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 15,
            source: .gpsSignificantChange,
            recordingDay: nil,
        )
        let second = LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T13:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7751, longitude: -122.4196),
            horizontalAccuracy: 8,
            source: .gpsSignificantChange,
            recordingDay: nil,
        )
        try await store.perform {
            try await store.add(sample: first)
        }
        let before = try await reader.yearReportDetails(for: 2026)

        try await store.perform {
            try await store.add(sample: second)
        }
        let after = try await reader.yearReportDetails(for: 2026)

        #expect(after.report == before.report)
        #expect(before.primaryRegionLocations[.california]?.flatMap(\.points).count == 1)
        #expect(after.primaryRegionLocations[.california]?.flatMap(\.points).count == 2)
        #expect(after != before)
    }

    @Test func yearReportDetailsAppliesDeviceRecordingCutoffs() async throws {
        let (reader, store) = try Self.makeReader()
        let deviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-10T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 10,
                source: .gpsVisit,
                recordingDeviceID: deviceID,
                recordingDay: nil,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-01-12T12:00:00-08:00"),
                coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                horizontalAccuracy: 20,
                source: .gpsVisit,
                recordingDeviceID: deviceID,
                recordingDay: nil,
            ))
            try await store.addRecordingDeviceRemoval(RecordingDeviceRemoval(
                id: .init(
                    rawValue: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")),
                ),
                deviceID: deviceID,
                removedAt: WhereCoreTestSupport.iso("2026-01-11T00:00:00-08:00"),
                removedByDeviceID: deviceID,
            ))
        }

        let details = try await reader.yearReportDetails(for: 2026)

        #expect(details.report.days.count == 1)
        #expect(details.report.totals == [.california: 1])
        #expect(details.primaryRegionLocations[.california]?.flatMap(\.points).count == 1)
        #expect(details.primaryRegionLocations[.newYork] == nil)
        #expect(details.elsewhereInput.history.samples.count == 1)
        #expect(!details.elsewhereInput.hasVisits)
    }

    @Test func detailsReadConfiguredPrimaryMembershipAndAllItsLocations() async throws {
        let (reader, store) = try Self.makeReader()
        try await store.perform {
            try await store.setPrimaryRegions([
                PrimaryRegion(region: .california, appearance: nil, order: 0),
                PrimaryRegion(region: .newYork, appearance: nil, order: 1),
                PrimaryRegion(region: .canada, appearance: nil, order: 2),
            ])
            for coordinate in [
                Coordinate(latitude: 37.7749, longitude: -122.4194),
                Coordinate(latitude: 40.7128, longitude: -74.0060),
                Coordinate(latitude: 49.2827, longitude: -123.1207),
            ] {
                try await store.add(sample: LocationSample(
                    timestamp: WhereCoreTestSupport.iso("2026-06-01T12:00:00-07:00"),
                    coordinate: coordinate,
                    horizontalAccuracy: 10,
                    source: .gpsVisit,
                    recordingDay: nil,
                ))
            }
        }
        let details = try await reader.yearReportDetails(for: 2026)
        #expect(details.primaryRegions == [.california, .newYork, .canada])
        #expect(Set(details.primaryRegionLocations.keys) == details.primaryRegions)
        #expect(!details.elsewhereInput.hasVisits)
    }

    @Test func elsewhereResolutionExcludesRemovedDeviceSamples() async throws {
        let (reader, store) = try Self.makeReader()
        let device = RecordingDeviceID(rawValue: UUID())
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-06-01T12:00:00-07:00"),
                coordinate: ElsewhereTestSupport.vegas,
                horizontalAccuracy: 10,
                source: .gpsVisit,
                recordingDeviceID: device,
                recordingDay: nil,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-06-03T12:00:00-07:00"),
                coordinate: ElsewhereTestSupport.portland,
                horizontalAccuracy: 10,
                source: .gpsVisit,
                recordingDeviceID: device,
                recordingDay: nil,
            ))
            try await store.addRecordingDeviceRemoval(RecordingDeviceRemoval(
                id: .init(rawValue: UUID()),
                deviceID: device,
                removedAt: WhereCoreTestSupport.iso("2026-06-02T00:00:00-07:00"),
                removedByDeviceID: device,
            ))
        }
        let details = try await reader.yearReportDetails(for: 2026)
        let resolved = try await ElsewhereResolver(geography: HistoryRegionAttribution())
            .resolve(details.elsewhereInput)
        #expect(try resolved.regions.map(\.region) == [#require(Region(rawValue: "us-NV"))])
        #expect(resolved.regions.first?.days.count == 1)
        #expect(resolved.regions.first?.locations.flatMap(\.points).count == 1)
        #expect(details.report.totals == [.other: 1])
    }

    @Test func elsewhereCoordinatesAndCorrectionsShareTheReportSnapshot() async throws {
        let (reader, store) = try Self.makeReader()
        let first = ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas)
        try await store.perform { try await store.add(sample: first) }
        let before = try await reader.yearReportDetails(for: 2026)
        try await store.perform {
            try await store.add(sample: ElsewhereTestSupport.sample(ElsewhereTestSupport.portland))
        }
        let after = try await reader.yearReportDetails(for: 2026)
        #expect(before.report == after.report)
        #expect(before.elsewhereInput != after.elsewhereInput)
        #expect(try await ElsewhereResolver(geography: HistoryRegionAttribution())
            .resolve(after.elsewhereInput).regions.count == 2)
        #expect(try await reader.yearReport(for: 2026) == before.report)

        try await store.perform {
            try await store.addSampleAttributionRevision(SampleAttributionRevision(
                id: .init(rawValue: UUID()),
                sampleID: first.id,
                updatedAt: first.timestamp,
                replacementRegions: [],
            ))
        }
        let corrected = try await reader.yearReportDetails(for: 2026)
        let resolved = try await ElsewhereResolver(geography: HistoryRegionAttribution())
            .resolve(corrected.elsewhereInput)
        #expect(try resolved.regions.map(\.region) == [#require(Region(rawValue: "us-OR"))])
    }

    /// The scan's one-read bundle: `report`, `.other` day coordinates, and the
    /// GPS `daySamples` all come from a single year-samples read and stay
    /// consistent — and the GPS-only `daySamples` drops a manual coordinate.
    @Test func dataIssueReadsBuildsAllProjectionsFromOneRead() async throws {
        let (reader, store) = try Self.makeReader()
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194) // California
        let midOcean = Coordinate(latitude: 0, longitude: -160) // .other
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
                coordinate: sf,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
                recordingDay: nil,
            ))
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-16T12:00:00-07:00"),
                coordinate: midOcean,
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
                recordingDay: nil,
            ))
            // A manual coordinate must not feed the speed-based day samples.
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-15T18:00:00-07:00"),
                coordinate: sf,
                horizontalAccuracy: 0,
                source: .manual,
                recordingDay: nil,
            ))
        }

        let reads = try await reader.dataIssueReads(for: 2026)

        #expect(reads.report.totals[.california] == 1)
        #expect(reads.report.totals[.other] == 1)

        let march16 = CalendarDay(year: 2026, month: 3, day: 16)
        #expect(reads.otherDayCoordinates[march16]?.isEmpty == false)

        // March 15 had a GPS fix and a manual one; only the GPS fix is kept.
        let march15 = CalendarDay(year: 2026, month: 3, day: 15)
        let day15 = reads.daySamples.samples(on: march15)
        #expect(day15.count == 1)
        #expect(day15.first?.source == .gpsSignificantChange)
    }

    @Test func yearIntervalCoversTheRequestedYear() throws {
        let (reader, _) = try Self.makeReader()
        let interval = reader.yearInterval(year: 2026)
        #expect(WhereCoreTestSupport.calendar().component(.year, from: interval.start) == 2026)
    }

    @Test func recordingDateDrivesReportsMapsAndIssueReadsAcrossUTCYears() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let sample = try LocationHistoryReaderTestSupport.sample(
            seconds: 1800,
            zone: #require(TimeZone(secondsFromGMT: -3600)),
        )
        try await LocationHistoryReaderTestSupport.add([sample], to: store)
        let day = CalendarDay(year: 2000, month: 12, day: 31)
        for hours in [-12, 0, 14] {
            var calendar = LocationHistoryReaderTestSupport.calendar
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: hours * 3600))
            let reader = LocationHistoryReaderTestSupport.reports(store, calendar: calendar)
            let report = try await reader.yearReport(for: 2000)
            #expect(report.days.map(\.day) == [day])
            #expect(report.totals == [.california: 1])
            #expect(report.completeness.isComplete)
            #expect(try await reader.yearReport(for: 2001).totals.isEmpty)
            #expect(try await reader.locations(onDay: day)[.california]?
                .map(\.coordinate) == [sample.coordinate])
            #expect(try await reader.locations(in: .california, year: 2000).map(\.day) == [day])
            #expect(try await reader.representativeCoordinates(for: 2000)[.california] == sample
                .coordinate)
            #expect(try await reader.yearReportDetails(for: 2000).report == report)
            let issues = try await reader.dataIssueReads(for: 2000)
            #expect(issues.report == report)
            #expect(issues.daySamples.samples(on: day) == [sample])
        }
    }

    @Test func checkedExportSnapshotSurvivesAConflictReceivedBeforeDocumentGeneration(
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try LocationHistoryReaderTestSupport.competingTracks()
        try await LocationHistoryReaderTestSupport.add(samples.filter {
            $0.recordingDeviceID == LocationHistoryReaderTestSupport.first
        }, to: store)
        let reader = LocationHistoryReaderTestSupport.reports(store)
        let checked = try await reader.exportableYearReport(for: 2001)
        let checkedCSV = try await reader.exportableYearCSV(for: 2001)
        #expect(checked.totals == [.california: 1])
        #expect(checked.completeness.isComplete)

        // A document generator retains this checked value while later imports update the store.
        try await LocationHistoryReaderTestSupport.add(samples.filter {
            $0.recordingDeviceID == LocationHistoryReaderTestSupport.second
        }, to: store)
        let current = try await reader.yearReport(for: 2001)
        #expect(current.totals.isEmpty)
        #expect(!current.completeness.isComplete)
        await #expect(throws: UnresolvedHistoryError.self) {
            try await reader.exportableYearReport(for: 2001)
        }
        await #expect(throws: UnresolvedHistoryError.self) {
            try await reader.exportableYearCSV(for: 2001)
        }
        #expect(try HistoryReportCSV(report: checked) == checkedCSV)
        #expect(checked.totals == [.california: 1])
        #expect(checked.completeness.isComplete)
        #expect(try await store.allSamples().count == samples.count)
    }

    @Test func conflictsExcludeOnlyDisputedPresenceAndBlockTheAffectedExport() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try LocationHistoryReaderTestSupport.competingTracks()
        let later = try LocationHistoryReaderTestSupport.sample(seconds: 7200)
        try await LocationHistoryReaderTestSupport.add(samples + [later], to: store)
        let reader = LocationHistoryReaderTestSupport.reports(store)
        let report = try await reader.yearReport(for: 2001)
        let day = CalendarDay(year: 2001, month: 1, day: 1)
        #expect(report.totals == [.california: 1])
        #expect(report.completeness.affectedDays == [day])
        #expect(!report.completeness.isComplete)
        await #expect(throws: UnresolvedHistoryError.self) {
            try await reader.exportableYearReport(for: 2001)
        }
        #expect(try await reader.exportableYearReport(for: 2000).totals.isEmpty)
        #expect(try await reader.exportableYearCSV(for: 2000).data ==
            Data("calendar_day,region_id,region_name\r\n".utf8))
        let details = try await reader.yearReportDetails(for: 2001)
        let elsewhere = try await ElsewhereResolver(geography: HistoryRegionAttribution())
            .resolve(details.elsewhereInput)
        #expect(elsewhere.completeness == report.completeness)
        #expect(elsewhere.regions.isEmpty)
        try await store.perform {
            try await store.setManualDay(.init(
                day: day,
                regions: [.newYork],
                isAuthoritative: true,
            ))
        }
        let overlaid = try await reader.yearReport(for: 2001)
        #expect(overlaid.totals == [.newYork: 1])
        #expect(overlaid.completeness == report.completeness)
        #expect(try await store.allSamples().count == 7)
    }

    @Test func primaryChangesRegroupWithoutChangingSelectionAndChoicesAdmitLateSelectedFixes(
    ) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try LocationHistoryReaderTestSupport.competingTracks()
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        try await RecordingChoiceTestSupport.append(
            .source(RecordingAssessmentTestSupport.decision(920, end: 1201)),
            store: store,
        )
        let reader = LocationHistoryReaderTestSupport.reports(store)
        let original = try await reader.yearReportDetails(for: 2001)
        #expect(original.report.totals == [.california: 1])
        #expect(original.report.completeness.isComplete)
        try await store.perform {
            try await store.setPrimaryRegions([.init(region: .newYork, appearance: nil, order: 0)])
        }
        let regrouped = try await reader.yearReportDetails(for: 2001)
        #expect(regrouped.report.totals == [.other: 1])
        #expect(regrouped.elsewhereInput.history == original.elsewhereInput.history)
        #expect(regrouped.report.completeness == original.report.completeness)
        let elsewhere = try await ElsewhereResolver(geography: HistoryRegionAttribution())
            .resolve(regrouped.elsewhereInput)
        #expect(elsewhere.regions.map(\.region) == [.california])
        let late = try LocationHistoryReaderTestSupport.sample(seconds: 650)
        let other = try LocationHistoryReaderTestSupport.sample(
            seconds: 650,
            deviceID: LocationHistoryReaderTestSupport.second,
            longitude: -74,
        )
        try await LocationHistoryReaderTestSupport.add([late, other], to: store)
        let updated = try await reader.yearReportDetails(for: 2001)
        #expect(updated.report == regrouped.report)
        #expect(updated.elsewhereInput.history.rawSamples.contains(late))
        #expect(!updated.elsewhereInput.history.rawSamples.contains(other))
        #expect(try await reader.exportableYearReport(for: 2001) == updated.report)
    }

    @Test func adjacentYearReviewContextCannotBroadenReportIncompleteness() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let zone = try #require(TimeZone(secondsFromGMT: -18 * 3600))
        let samples = try [64500.0, 65400].map {
            try LocationHistoryReaderTestSupport.sample(seconds: $0, zone: zone)
        }
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        try await RecordingChoiceTestSupport.append(.source(RecordingAssessmentTestSupport.decision(
            940,
            start: 65100,
            end: 65220,
        )), store: store)
        try await RecordingChoiceTestSupport.append(.source(RecordingAssessmentTestSupport.decision(
            941,
            start: 65100,
            end: 65220,
            action: .select(LocationHistoryReaderTestSupport.second),
        )), store: store)
        let reader = LocationHistoryReaderTestSupport.reports(store)
        let previousYear = try await reader.yearReport(for: 2000)
        let reviewContext = try await reader.dataIssueReads(for: 2000)
        #expect(previousYear.completeness.isComplete)
        #expect(reviewContext.report == previousYear)
        let currentYear = try await reader.yearReport(for: 2001)
        #expect(currentYear.completeness.affectedDays == [.init(year: 2001, month: 1, day: 1)])
        #expect(!currentYear.completeness.isComplete)
    }
}
