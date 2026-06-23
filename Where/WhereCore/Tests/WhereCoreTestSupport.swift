import Foundation

enum WhereCoreTestSupport {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static func calendar(timeZone: TimeZone = pacific) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
    }
}
