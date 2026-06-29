import Foundation

public enum DataIssueCategory: Sendable, Hashable, CaseIterable {
    case missingDays
    case borderDrift
    case abruptChange
}

/// Closed set of fix shapes. The UI switches on this, so a new detector that
/// reuses a shape needs no UI change; a genuinely new fix shape adds a case
/// (the compiler then flags the UI switch).
public enum IssueResolution: Sendable, Hashable {
    case backfill(MissingDayRange)
    case relabelDay(day: DayPresence, suggestedRegions: Set<Region>, approximateMeters: Double?)
    case markTravelDay(earlier: DayPresence, later: DayPresence, suggestedRegions: Set<Region>)
}

public enum DataIssueID: Hashable, Sendable {
    case missingDays(start: Date)
    case borderDrift(date: Date)
    case abruptChange(earlier: Date, later: Date)

    /// Stable, device-independent key for persisted dismissal and `ForEach`.
    public var storageKey: String {
        switch self {
            case let .missingDays(start):
                "missingDays:\(Self.dayKey(start))"
            case let .borderDrift(date):
                "borderDrift:\(Self.dayKey(date))"
            case let .abruptChange(earlier, later):
                "abruptChange:\(Self.dayKey(earlier)):\(Self.dayKey(later))"
        }
    }

    private static func dayKey(_ date: Date) -> String {
        String(format: "%.0f", date.timeIntervalSince1970)
    }
}

public protocol DataIssue: Identifiable, Sendable where ID == DataIssueID {
    var id: DataIssueID { get }
    var category: DataIssueCategory { get }
    var sortKey: Date { get }
    var isDismissible: Bool { get }
    var resolution: IssueResolution { get }
}

public enum DriftThreshold: Int, CaseIterable, Sendable, Hashable {
    case km1 = 1000
    case km5 = 5000
    case km10 = 10000
    case km25 = 25000
    case km50 = 50000

    public var meters: Double {
        Double(rawValue)
    }

    public static let `default` = DriftThreshold.km1
}
