import Foundation
@testable import WhereCore

enum RecordingCalendarRecoveryTestSupport {
    struct Transition {
        let zoneIdentifier: String
        let instant: String
        let beforeOffset: Int
        let afterOffset: Int
        let beforeDay: CalendarDay
        let afterDay: CalendarDay
    }

    static let transitions: [Transition] = [
        .init(
            zoneIdentifier: "America/New_York",
            instant: "2026-03-08T07:00:00Z",
            beforeOffset: -18000,
            afterOffset: -14400,
            beforeDay: .init(year: 2026, month: 3, day: 8),
            afterDay: .init(
                year: 2026,
                month: 3,
                day: 8,
            ),
        ),
        .init(
            zoneIdentifier: "America/New_York",
            instant: "2026-11-01T06:00:00Z",
            beforeOffset: -14400,
            afterOffset: -18000,
            beforeDay: .init(year: 2026, month: 11, day: 1),
            afterDay: .init(
                year: 2026,
                month: 11,
                day: 1,
            ),
        ),
        .init(
            zoneIdentifier: "Pacific/Apia",
            instant: "2011-12-30T10:00:00Z",
            beforeOffset: -36000,
            afterOffset: 50400,
            beforeDay: .init(year: 2011, month: 12, day: 29),
            afterDay: .init(
                year: 2011,
                month: 12,
                day: 31,
            ),
        ),
        .init(
            zoneIdentifier: "Asia/Kathmandu",
            instant: "1985-12-31T18:30:00Z",
            beforeOffset: 19800,
            afterOffset: 20700,
            beforeDay: .init(year: 1985, month: 12, day: 31),
            afterDay: .init(
                year: 1986,
                month: 1,
                day: 1,
            ),
        ),
        .init(
            zoneIdentifier: "Europe/Moscow",
            instant: "2014-10-25T22:00:00Z",
            beforeOffset: 14400,
            afterOffset: 10800,
            beforeDay: .init(year: 2014, month: 10, day: 26),
            afterDay: .init(
                year: 2014,
                month: 10,
                day: 26,
            ),
        ),
    ]
}
