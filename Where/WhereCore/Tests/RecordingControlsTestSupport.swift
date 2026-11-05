import Foundation
import RegionKit
@testable import WhereCore

enum RecordingControlsTestSupport {
    static let device = RecordingAssessmentTestSupport.first
    static let otherDevice = RecordingAssessmentTestSupport.second
    static let version = RecordingAssessmentTestSupport.version
    static let placeID = RecordingPlace.ID(rawValue: device.rawValue)

    static func malformedPeriods() throws -> [RecordingPeriod] {
        let invalid = try JSONDecoder().decode(
            RecordingPeriod.self,
            from: Data(#"{"start":20,"end":10}"#.utf8),
        )
        return try [RecordingAssessmentTestSupport.period(0, 86400), invalid]
    }

    static func ignore(
        _ identity: Int,
        start: Double = 0,
        end: Double = 86400,
        change: RecordingIgnoreDecision.Change? = nil,
        deviceID: RecordingDeviceID = device,
        predecessors: Set<RecordingIgnoreDecision.ID> = [],
    ) throws -> RecordingIgnoreDecision {
        try .init(
            id: .init(rawValue: RecordingAssessmentTestSupport.decisionID(identity).rawValue),
            author: device,
            deviceID: deviceID,
            periods: [RecordingAssessmentTestSupport.period(
                start,
                end,
            )],
            change: change ?? .ignore(.init(
                day: .init(year: 2001, month: 1, day: 1),
                timeZone: .gmt,
            )),
            predecessors: predecessors,
            version: version,
        )
    }

    static func place(
        _ identity: Int,
        start: Double = 0,
        end: Double? = 100,
        placeID: RecordingPlace.ID = placeID,
        action: RecordingPlaceDecision.Action = .set(
            kind: .regularHome,
            coordinate: .init(latitude: 37, longitude: -122),
        ),
        predecessors: Set<RecordingPlaceDecision.ID> = [],
    ) throws -> RecordingPlaceDecision {
        try .init(
            id: .init(rawValue: RecordingAssessmentTestSupport.decisionID(identity).rawValue),
            author: device,
            placeID: placeID,
            validity: [RecordingInterval(
                start: RecordingAssessmentTestSupport.time(start),
                end: end.map(RecordingAssessmentTestSupport.time),
            )],
            action: action,
            predecessors: predecessors,
            version: version,
        )
    }

    static func calendar(
        _ identity: Int,
        start: Double = 0,
        end: Double = 100,
        action: RecordingCalendarDecision.Action,
        deviceID: RecordingDeviceID = device,
        predecessors: Set<RecordingCalendarDecision.ID> = [],
    ) throws -> RecordingCalendarDecision {
        try .init(
            id: .init(rawValue: RecordingAssessmentTestSupport.decisionID(identity).rawValue),
            author: device,
            deviceID: deviceID,
            periods: [RecordingAssessmentTestSupport.period(
                start,
                end,
            )],
            action: action,
            predecessors: predecessors,
            version: version,
        )
    }

    static func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }
}
