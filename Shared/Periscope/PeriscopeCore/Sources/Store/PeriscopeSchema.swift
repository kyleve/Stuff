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
    #Index<SDLogEvent>(
        [\.date],
        [\.sequence],
        [\.severity],
        [\.eventName],
        [\.sessionID],
        [\.spanID],
        [\.spanExitMode],
        [\.externalID],
    )

    var eventID: UUID
    var date: Date
    /// Store-assigned monotonic insertion order — breaks ties between
    /// events in the same millisecond so "newest first" stays stable, and
    /// indexed so a live viewer's incremental `LogQuery.afterSequence`
    /// cursor ("everything appended since I last looked") is a range seek.
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
    /// Set on span begin/end events so a span's pair resolves in one fetch.
    var spanID: UUID?
    /// `SpanExit.Mode.rawValue` on span-ended events — queryable, so the
    /// viewer can filter "everything that failed/expired/orphaned".
    var spanExitMode: String?
    /// The emitting function/file (`#function`/`#fileID`), when captured.
    var callFunction: String?
    var callFileID: String?
    /// The event's associated-object identifier (`LogEvent.externalID`),
    /// indexed so "every event about this object" is one query.
    var externalID: String?
    var scopes: [SDLogScope]
    var tags: [SDLogTag]

    @Relationship(deleteRule: .cascade, inverse: \SDLogAttachment.event)
    var attachments: [SDLogAttachment]

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
        spanID: UUID?,
        spanExitMode: String?,
        callFunction: String?,
        callFileID: String?,
        externalID: String?,
        scopes: [SDLogScope],
        tags: [SDLogTag],
        attachments: [SDLogAttachment],
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
        self.spanID = spanID
        self.spanExitMode = spanExitMode
        self.callFunction = callFunction
        self.callFileID = callFileID
        self.externalID = externalID
        self.scopes = scopes
        self.tags = tags
        self.attachments = attachments
    }
}

/// One attachment blob, cascade-deleted with its event. The bytes use
/// external storage so screenshots and payloads live beside the database.
@Model
final class SDLogAttachment {
    var name: String
    var contentType: String
    /// Position within the event's attachments (relationships are
    /// unordered).
    var index: Int
    @Attribute(.externalStorage) var data: Data
    var event: SDLogEvent?

    init(name: String, contentType: String, index: Int, data: Data) {
        self.name = name
        self.contentType = contentType
        self.index = index
        self.data = data
    }
}

/// One row per distinct key/value tag pair, shared by every event carrying
/// it — tag queries resolve through this relationship.
@Model
final class SDLogTag {
    #Index<SDLogTag>([\.pair])

    var key: String
    /// The `LogTagValue` discriminator (string/int/double/bool/encoded),
    /// so typed values round-trip as themselves.
    var valueKind: String
    /// The value's canonical string form.
    var value: String
    /// Key, kind, and value joined — a single indexed column so tag
    /// predicates stay one comparison (see `LogTag.pair`).
    var pair: String

    @Relationship(inverse: \SDLogEvent.tags)
    var events: [SDLogEvent]

    init(tag: LogTag) {
        key = tag.key.rawValue
        valueKind = tag.value.kind
        value = tag.value.stringValue
        pair = tag.pair
        events = []
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
        [
            SDLogEvent.self,
            SDLogScope.self,
            SDLogSession.self,
            SDLogTag.self,
            SDLogAttachment.self,
        ]
    }
}
