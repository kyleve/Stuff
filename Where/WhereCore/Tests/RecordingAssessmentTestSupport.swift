import Foundation
import RegionKit
@testable import WhereCore

enum RecordingAssessmentTestSupport {
    static func observation(
        deviceID: RecordingDeviceID = first,
        seconds: Double,
        latitude: Double = 37,
        longitude: Double = -122,
        accuracy: Double = 10,
        region: Region? = .california,
        assignment: RecordingDayAssignment? = nil,
        timeZone: TimeZone = .gmt,
        sampleID: UUID = UUID(),
    ) throws -> RecordingObservation {
        try RecordingObservation(
            sample: LocationSample(
                id: sampleID,
                timestamp: time(seconds),
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                horizontalAccuracy: accuracy,
                source: .gpsSignificantChange,
                recordingDeviceID: deviceID,
                recordingDay: nil,
            ),
            recordingDay: assignment ?? .resolved(.init(
                observedAt: time(seconds),
                timeZone: timeZone,
            )),
            region: region,
        )
    }

    static func track(
        deviceID: RecordingDeviceID = first,
        longitude: Double = -122,
        moving: Bool,
        region: Region? = .california,
    ) throws -> [RecordingObservation] {
        try (0 ... 2).map { index in
            try observation(
                deviceID: deviceID,
                seconds: Double(index) * 600,
                longitude: longitude + (moving ? Double(index) * 0.02 : 0),
                region: region,
            )
        }
    }

    static let first =
        RecordingDeviceID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
    static let second =
        RecordingDeviceID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!)
    static let version = DataSemanticsVersion(major: 1, minor: 0, patch: 0)

    static func time(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    static func period(_ start: Double, _ end: Double) throws -> RecordingPeriod {
        try RecordingPeriod(start: time(start), end: time(end))
    }

    static func decisionID(_ value: Int) -> HistoryDecision.ID {
        .init(rawValue: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!)
    }

    static func decision(
        _ value: Int,
        start: Double = 0,
        end: Double = 100,
        action: HistoryDecision.Action = .select(first),
        predecessors: Set<HistoryDecision.ID> = [],
        version: DataSemanticsVersion = version,
    ) throws -> HistoryDecision {
        try HistoryDecision(
            id: decisionID(value),
            author: first,
            periods: [period(start, end)],
            scope: .fixedPeriods,
            action: action,
            predecessors: predecessors,
            version: version,
        )
    }
}
