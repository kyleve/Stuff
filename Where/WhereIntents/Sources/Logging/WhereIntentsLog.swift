import PeriscopeCore
import WhereCore

/// Structured events and spans for the Where App Intents surface.
@LogScope("WhereIntents")
enum WhereIntentsLog {
    enum SpanName: Hashable, CustomStringConvertible {
        case perform(IntentName)
        case awaitServices

        var description: String {
            switch self {
                case let .perform(intent): "perform(\(intent.rawValue))"
                case .awaitServices: "awaitServices"
            }
        }
    }

    enum IntentName: String, Hashable, CaseIterable {
        case daysInRegion = "days-in-region"
        case daysInRegionSnippet = "days-in-region-snippet"
        case logDay = "log-day"
        case logTrip = "log-trip"
        case regionOnDate = "region-on-date"
        case todayRegions = "today-regions"

        var budget: Duration {
            switch self {
                case .daysInRegion, .daysInRegionSnippet, .logDay, .regionOnDate, .todayRegions:
                    .seconds(2)
                case .logTrip:
                    .seconds(5)
            }
        }
    }

    @LogEvent("spotlight-indexed")
    struct SpotlightIndexed {
        @LogField("region_count", exposure: .restricted, kind: .count)
        var regionCount: Int
        var message: String {
            "Indexed \(regionCount) region(s) for Spotlight"
        }
    }

    @LogEvent("spotlight-index-failed", level: .warning)
    struct SpotlightIndexFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to index regions for Spotlight: \(description)"
        }
    }
}

extension WhereIntentsLog {
    static let logger = WhereLog.root(WhereIntentsLog.self)
}
