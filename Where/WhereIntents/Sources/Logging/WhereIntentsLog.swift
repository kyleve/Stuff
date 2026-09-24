import PeriscopeCore
import WhereCore

/// Structured events for the Where App Intents surface. These run in the
/// app/intents process, which keeps `Periscope.shared` OSLog-only (no
/// persistent store of its own).
enum WhereIntentsLog: LogEvent {
    /// Names the intents surface's timed spans.
    ///
    /// `description` is spelled out because ``perform(_:)`` carries an intent
    /// token: reflection would render it `perform(WhereIntents.IntentName.logDay)`,
    /// a Swift-internal shape in a name the span tools group timings by.
    enum SpanName: Hashable, CustomStringConvertible {
        /// One intent's work — the read or write it delegates to WhereCore.
        /// Excludes the ``awaitServices`` wait, so a cold-start park doesn't
        /// read as a slow intent.
        case perform(IntentName)
        /// An intent parked in `IntentServices.current()` waiting for the launch
        /// to install the services stack. Only the *parking* path is spanned —
        /// once installed, resolution is a property read, and timing it on every
        /// invocation would bury the interesting case.
        case awaitServices

        var description: String {
            switch self {
                case let .perform(intent): "perform(\(intent.rawValue))"
                case .awaitServices: "awaitServices"
            }
        }
    }

    /// The intents whose work is timed, and how long each may take before its
    /// span raises an overdue warning. Budgets live here (not at the call site)
    /// so an intent's name and its expectation can't drift apart, mirroring
    /// `BudgetedLaunchStep` on the launch side.
    enum IntentName: String, Hashable, CaseIterable {
        case daysInRegion = "days-in-region"
        case daysInRegionSnippet = "days-in-region-snippet"
        case logDay = "log-day"
        case logTrip = "log-trip"
        case regionOnDate = "region-on-date"
        case todayRegions = "today-regions"

        /// Siri and Shortcuts hold the user waiting on `perform()`, so these are
        /// tight: a single year's aggregated read or a one-day write should be
        /// well under a second. A trip earns more slack because it backfills a
        /// range in one transaction.
        var budget: Duration {
            switch self {
                case .daysInRegion, .daysInRegionSnippet, .logDay, .regionOnDate, .todayRegions:
                    .seconds(2)
                case .logTrip:
                    .seconds(5)
            }
        }
    }

    /// The tracked regions were indexed into Spotlight.
    case spotlightIndexed(regionCount: Int)
    /// Indexing the tracked regions into Spotlight failed
    /// (degraded-but-handled: search integration is a nicety).
    case spotlightIndexFailed(description: String)
    /// Reading the optional widget-snapshot fast path failed; the intent falls
    /// back to its authoritative store report.
    case widgetSnapshotReadFailed(description: String)
    static let eventName = "WhereIntents"

    var level: LogLevel {
        switch self {
            case .spotlightIndexed:
                .info
            case .spotlightIndexFailed, .widgetSnapshotReadFailed:
                .warning
        }
    }

    var message: String {
        switch self {
            case let .spotlightIndexed(regionCount):
                "Indexed \(regionCount) region(s) for Spotlight"
            case let .spotlightIndexFailed(description):
                "Failed to index regions for Spotlight: \(description)"
            case let .widgetSnapshotReadFailed(description):
                "Failed to read the widget snapshot: \(description)"
        }
    }
}

extension WhereIntentsLog {
    /// The one logger the whole intents surface emits through. Derived once here
    /// rather than per type: every intent's span, the services wait, and the
    /// Spotlight events share this scope, and eight copies of the same
    /// derivation is eight chances for one of them to drift.
    static let logger = WhereLog.root(WhereIntentsLog.self)
}
