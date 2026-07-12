import AppIntents
import WhereCore

/// The look-back window for the recent-activity summary intent, mirroring
/// `WhereCore.RecentActivityWindow` (rolling 24h / week / month, plus year so
/// far) as a Siri-resolvable menu. Round-trips losslessly with the domain enum.
public enum ActivityWindowAppEnum: String, AppEnum, CaseIterable {
    case day
    case week
    case month
    case yearToDate

    /// App Intents extracts this static metadata at build time, so both must be
    /// compile-time-constant literals (the framework localizes them through the
    /// app's App Intents string extraction, not this module's catalog).
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time Range")

    public static let caseDisplayRepresentations: [ActivityWindowAppEnum: DisplayRepresentation] = [
        .day: DisplayRepresentation(title: "Last 24 Hours"),
        .week: DisplayRepresentation(title: "Past Week"),
        .month: DisplayRepresentation(title: "Past Month"),
        .yearToDate: DisplayRepresentation(title: "Year So Far"),
    ]

    public init(_ window: RecentActivityWindow) {
        switch window {
            case .day: self = .day
            case .week: self = .week
            case .month: self = .month
            case .yearToDate: self = .yearToDate
        }
    }

    public var window: RecentActivityWindow {
        switch self {
            case .day: .day
            case .week: .week
            case .month: .month
            case .yearToDate: .yearToDate
        }
    }
}
