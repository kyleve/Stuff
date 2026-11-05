import Foundation
@testable import WhereCore

enum RecordingControlEditTestSupport {
    enum Kind: CaseIterable { case ignore, place, calendar }

    static func edit(_ kind: Kind, removes: Bool) throws -> RecordingControlEdit {
        let periods = try [RecordingAssessmentTestSupport.period(0, 86400)]
        switch kind {
            case .ignore:
                return try .ignore(
                    deviceID: RecordingControlsTestSupport.device,
                    periods: periods,
                    change: removes ? .restoreEligibility : .ignore(.init(
                        day: .init(year: 2001, month: 1, day: 1),
                        timeZone: .gmt,
                    )),
                )
            case .place:
                return .place(
                    placeID: RecordingControlsTestSupport.placeID,
                    periods: periods,
                    action: removes ? .remove : .set(
                        kind: .regularHome,
                        coordinate: .init(latitude: 37, longitude: -122),
                    ),
                )
            case .calendar:
                return try .calendar(
                    deviceID: RecordingControlsTestSupport.device,
                    periods: periods,
                    action: removes ? .withdraw : .establish(.init(
                        timeZone: .gmt,
                        secondsFromGMT: 0,
                    )),
                )
        }
    }

    static func coordinator(store: any WhereStore) -> RecordingControlEditCoordinator {
        .init(
            store: store,
            policy: RecordingChoiceTestSupport.policy,
            author: RecordingChoiceTestSupport.author,
            onCommitted: {},
        )
    }
}
