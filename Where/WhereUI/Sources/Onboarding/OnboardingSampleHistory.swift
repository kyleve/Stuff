import Foundation
import RegionKit
import WhereCore

/// Fixed illustrative history; never persisted or interpreted as the user's data.
enum OnboardingSampleHistory {
    static let regions: [Region] = [.california, .newYork]
    static let calendar = Calendar(identifier: .gregorian)
    static let days: [DayPresence] = (1 ... 9).flatMap { month in
        (1 ... 20).map { day in
            DayPresence(
                day: CalendarDay(year: 2026, month: month, day: day),
                regions: [month < 6 ? .california : .newYork],
            )
        }
    }
}
