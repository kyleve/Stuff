import Foundation
import SwiftData

/// The SwiftData records behind `PeriscopeStore`. Internal — callers only
/// ever see value types (`StoredLogEvent`, `LogScope`, `LogSession`).
///
/// Events keep their scopes two ways on purpose: `orderedScopeIDs` preserves
/// the emission order (primary scope first) faithfully for display, while
/// the `scopes` relationship exists for predicate-based querying (scope and
/// subtree filters). Payloads persist as JSON keyed by `eventName` +
/// `eventVersion`, so old rows outlive their Swift types and degrade to raw
/// JSON instead of requiring schema migrations.
@Model
final class SDLogEvent {
    #Index<SDLogEvent>([\.date], [\.severity], [\.eventName], [\.sessionID])

    var eventID: UUID
    var date: Date
    /// Store-assigned monotonic insertion order — breaks ties between
    /// events in the same millisecond so "newest first" stays stable.
    var sequence: Int
    var severity: Int
    var levelName: String
    var eventName: String
    var eventVersion: Int
    var message: String
    /// The event's stored properties, JSON-encoded.
    var payload: Data
    /// Every scope the event references, primary first, in emission order.
    var orderedScopeIDs: [UUID]
    var sessionID: UUID
    var scopes: [SDLogScope]
    var tags: [SDLogTag]

    init(
        eventID: UUID,
        date: Date,
        sequence: Int,
        severity: Int,
        levelName: String,
        eventName: String,
        eventVersion: Int,
        message: String,
        payload: Data,
        orderedScopeIDs: [UUID],
        sessionID: UUID,
        scopes: [SDLogScope],
        tags: [SDLogTag],
    ) {
        self.eventID = eventID
        self.date = date
        self.sequence = sequence
        self.severity = severity
        self.levelName = levelName
        self.eventName = eventName
        self.eventVersion = eventVersion
        self.message = message
        self.payload = payload
        self.orderedScopeIDs = orderedScopeIDs
        self.sessionID = sessionID
        self.scopes = scopes
        self.tags = tags
    }
}

/// One row per distinct key/value tag pair, shared by every event carrying
/// it — tag queries resolve through this relationship.
@Model
final class SDLogTag {
    #Index<SDLogTag>([\.pair])

    var key: String
    var value: String
    /// `key` and `value` joined with a separator — a single indexed column
    /// so tag predicates stay one comparison.
    var pair: String

    @Relationship(inverse: \SDLogEvent.tags)
    var events: [SDLogEvent]

    init(key: String, value: String) {
        self.key = key
        self.value = value
        pair = Self.pairValue(key: key, value: value)
        events = []
    }

    static func pairValue(key: String, value: String) -> String {
        "\(key)\u{1F}\(value)"
    }
}

/// One scope row per deterministic `ScopeID` — shared across sessions, so
/// the hierarchy accumulates rather than duplicating per launch.
@Model
final class SDLogScope {
    #Index<SDLogScope>([\.scopeID])

    @Attribute(.unique) var scopeID: UUID
    var name: String
    var parentID: UUID?

    @Relationship(inverse: \SDLogEvent.scopes)
    var events: [SDLogEvent]

    init(scopeID: UUID, name: String, parentID: UUID?) {
        self.scopeID = scopeID
        self.name = name
        self.parentID = parentID
        events = []
    }
}

/// One row per app launch (see `LogSession`).
@Model
final class SDLogSession {
    #Index<SDLogSession>([\.startedAt])

    @Attribute(.unique) var sessionID: UUID
    var startedAt: Date
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var deviceModel: String

    init(session: LogSession) {
        sessionID = session.id
        startedAt = session.startedAt
        appVersion = session.appVersion
        buildNumber = session.buildNumber
        osVersion = session.osVersion
        deviceModel = session.deviceModel
    }

    var toValue: LogSession {
        LogSession(
            id: sessionID,
            startedAt: startedAt,
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: deviceModel,
        )
    }
}

enum PeriscopeSchema {
    static var models: [any PersistentModel.Type] {
        [SDLogEvent.self, SDLogScope.self, SDLogSession.self, SDLogTag.self]
    }
}
