import Foundation

/// The user-selected cadence for automatic backups. A scheduled date is the
/// earliest eligible time; the system may run the work later.
public enum AutomaticBackupInterval: String, CaseIterable, Codable, Sendable {
    case daily
    case weekly
    case monthly

    public func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        let component = switch self {
            case .daily: DateComponents(day: 1)
            case .weekly: DateComponents(day: 7)
            case .monthly: DateComponents(month: 1)
        }
        return calendar.date(byAdding: component, to: date) ?? date
    }
}
