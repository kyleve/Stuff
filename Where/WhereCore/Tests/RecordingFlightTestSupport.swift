import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Turns the existing synthetic physical traces into attributed recording observations. Controls
/// use real fixture timestamps; they never alter sample identities or manufacture a split device.
enum RecordingFlightTestSupport {
    enum Exclusion: CaseIterable { case sourceChoice, ignore, conflict }
    enum RestorationScenario: CaseIterable {
        case primary, other, primaryToOther, otherToPrimary

        var isPrimary: Bool {
            switch self {
                case .primary, .primaryToOther: true
                case .other, .otherToPrimary: false
            }
        }

        var changesPrimary: Bool {
            switch self {
                case .primary, .other: false
                case .primaryToOther, .otherToPrimary: true
            }
        }
    }

    struct Geography: RegionAttributing {
        let loadedRegions: [Region] = [.newYork]
        func region(at _: Coordinate) -> Region {
            .newYork
        }

        func distanceToBoundary(of _: Region, from _: Coordinate) -> Double? {
            nil
        }
    }

    static func reports(
        _ store: any WhereStore,
        catalog: any RegionAttributing,
        calendar: Calendar,
    ) -> ReportReader {
        ReportReader(
            store: store,
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            attributor: RegionAttributor(for: []),
            history: LocationHistoryReader(
                store: store,
                policy: RecordingChoiceTestSupport.policy,
                geography: HistoryRegionAttribution(catalog: catalog),
            ),
        )
    }

    static func coordinator(
        _ store: any WhereStore,
        reports: ReportReader,
        calendar: Calendar,
        now: Date,
    ) -> SampleCorrectionCoordinator {
        SampleCorrectionCoordinator(
            store: store,
            reports: reports,
            calendar: calendar,
            now: { now },
            onCommitted: {},
        )
    }

    static func samples(_ raw: [LocationSample], zone: TimeZone = .gmt) throws -> [LocationSample] {
        try raw.map { sample in
            try LocationSample(
                id: sample.id,
                timestamp: sample.timestamp,
                coordinate: sample.coordinate,
                horizontalAccuracy: sample.horizontalAccuracy,
                source: sample.source,
                recordingDeviceID: sample.recordingDeviceID,
                motion: sample.motion,
                recordingDay: .resolved(.init(observedAt: sample.timestamp, timeZone: zone)),
            )
        }
    }

    static func control(
        _ exclusion: Exclusion,
        within period: RecordingPeriod,
    ) throws -> [RecordingControl] {
        func choice(_ number: Int, deviceID: RecordingDeviceID) throws -> RecordingControl {
            try .source(.init(
                id: RecordingAssessmentTestSupport.decisionID(number),
                author: FlightTrajectoryFixtures.device,
                periods: [period],
                scope: .fixedPeriods,
                action: .select(deviceID),
                predecessors: [],
                version: RecordingEvidencePolicy.version,
            ))
        }
        switch exclusion {
            case .sourceChoice:
                return try [choice(950, deviceID: RecordingAssessmentTestSupport.second)]
            case .conflict:
                return try [
                    choice(950, deviceID: RecordingAssessmentTestSupport.second),
                    choice(951, deviceID: FlightTrajectoryFixtures.device),
                ]
            case .ignore:
                let until = try RecordingIgnoreDecision.Until(
                    day: CalendarDay(from: period.end, in: SampleCorrectionTestSupport.calendar),
                    timeZone: .gmt,
                )
                let ignoreID = RecordingIgnoreDecision.ID(
                    rawValue: RecordingAssessmentTestSupport.decisionID(952).rawValue,
                )
                // Production ignores run through a calendar end. A causal resume creates this
                // shorter excluded interval while preserving the real persisted control shape.
                return try [
                    .ignore(.init(
                        id: ignoreID,
                        author: FlightTrajectoryFixtures.device,
                        deviceID: FlightTrajectoryFixtures.device,
                        periods: [.init(start: period.start, end: until.end)],
                        change: .ignore(until),
                        predecessors: [],
                        version: RecordingEvidencePolicy.version,
                    )),
                    .ignore(.init(
                        id: .init(rawValue: RecordingAssessmentTestSupport.decisionID(954)
                            .rawValue),
                        author: FlightTrajectoryFixtures.device,
                        deviceID: FlightTrajectoryFixtures.device,
                        periods: [.init(start: period.end, end: until.end)],
                        change: .restoreEligibility,
                        predecessors: [ignoreID],
                        version: RecordingEvidencePolicy.version,
                    )),
                ]
        }
    }

    static func period(_ start: Double, _ end: Double) throws -> RecordingPeriod {
        try .init(
            start: FlightTrajectoryFixtures.date(minutes: start),
            end: FlightTrajectoryFixtures.date(minutes: end),
        )
    }

    static func projection(
        _ samples: [LocationSample],
        controls: [RecordingControl] = [],
        period: RecordingPeriod,
    ) throws -> LocationHistoryProjection {
        let observations = try samples.map { sample in
            try RecordingObservation(
                sample: sample,
                recordingDay: #require(sample.recordingDay),
                region: .california,
            )
        }
        let selected = try RecordingHistorySelection.resolve(
            observations: observations,
            controls: RecordingControlSelectionTestSupport.snapshot(controls),
            removals: [],
            within: period,
            version: RecordingEvidencePolicy.version,
        )
        return try .init(
            samples: selected.contributions.map {
                try .init(
                    sample: $0.sample,
                    regions: $0.geography.presence,
                    day: .recording(#require($0.recordingDay.day)),
                )
            },
            revisions: [],
            contract: .recording(selected),
        )
    }
}
