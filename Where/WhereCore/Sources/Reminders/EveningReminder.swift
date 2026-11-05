import Foundation

/// The known work included in one day's evening notification. Future requests retain the
/// last assessed earlier-day count; they do not predict additional missing history.
public struct EveningReminder: Hashable, Sendable {
    public let day: CalendarDay
    public let remindsToLogDay: Bool
    public let missingDayCount: Int
    public let issueCount: Int

    public init(
        day: CalendarDay,
        remindsToLogDay: Bool,
        missingDayCount: Int,
        issueCount: Int,
    ) {
        precondition(missingDayCount >= 0 && issueCount >= 0)
        self.day = day
        self.remindsToLogDay = remindsToLogDay
        self.missingDayCount = missingDayCount
        self.issueCount = issueCount
    }

    var hasWork: Bool {
        remindsToLogDay || missingDayCount > 0 || issueCount > 0
    }

    var body: String {
        var sentences: [String] = []
        if remindsToLogDay { sentences.append(String(localized: .reminderNotificationBody)) }
        if missingDayCount > 0 {
            sentences.append(String(localized: .reminderNotificationMissingDays(missingDayCount)))
        }
        if issueCount > 0 {
            sentences.append(String(localized: .dataIssuesNotificationBody(issueCount)))
        }
        return sentences.joined(separator: "\n")
    }
}
