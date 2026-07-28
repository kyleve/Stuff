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
        [\.ambientSnapshotID],
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
    /// The ambient state the event was stamped with (see
    /// ``SDAmbientSnapshot``), or `nil` when no ambient source had reported
    /// anything yet. Indexed so "everything that happened while offline" is
    /// one query.
    var ambientSnapshotID: UUID?
    /// Set on span begin/end events so a span's pair resolves in one fetch.
    var spanID: UUID?
    /// `SpanExit.Mode.rawValue` on span-ended events — queryable, so the
    /// viewer can filter "everything that failed/expired/orphaned".
    var spanExitMode: String?
    /// `SpanRelaunchPolicy.rawValue` on span-*began* events, so the next
    /// launch's orphan sweep can honor the policy from a column instead of
    /// decoding every unmatched began's payload. Optional so rows written
    /// before the column existed take SwiftData's lightweight migration; the
    /// sweep falls back to their payload.
    var spanRelaunchPolicy: String?
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
        ambientSnapshotID: UUID?,
        spanID: UUID?,
        spanExitMode: String?,
        spanRelaunchPolicy: String?,
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
        self.ambientSnapshotID = ambientSnapshotID
        self.spanID = spanID
        self.spanExitMode = spanExitMode
        self.spanRelaunchPolicy = spanRelaunchPolicy
        self.callFunction = callFunction
        self.callFileID = callFileID
        self.externalID = externalID
        self.scopes = scopes
        self.tags = tags
        self.attachments = attachments
    }

    /// ``spanRelaunchPolicy`` as its enum, or `nil` when the row carries no
    /// policy — it isn't a span began, or it was written before the column
    /// existed — or names one this build doesn't recognize. The orphan sweep
    /// reads the payload only in those cases.
    var declaredRelaunchPolicy: SpanRelaunchPolicy? {
        spanRelaunchPolicy.flatMap(SpanRelaunchPolicy.init(rawValue:))
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
    /// `LogSessionAttributeKey.rawValue` → value (commit, configuration,
    /// optimization level). Optional so rows written before the column
    /// existed take SwiftData's lightweight migration; `nil` reads back as
    /// "this build couldn't name itself".
    var attributes: [String: String]?

    init(session: LogSession) {
        sessionID = session.id
        startedAt = session.startedAt
        appVersion = session.appVersion
        buildNumber = session.buildNumber
        osVersion = session.osVersion
        deviceModel = session.deviceModel
        // Injective (`LogSessionAttributeKey` wraps its raw value), so
        // neither direction can collide into a duplicate key.
        attributes = Dictionary(
            uniqueKeysWithValues: session.attributes.map { ($0.key.rawValue, $0.value) },
        )
    }

    var toValue: LogSession {
        LogSession(
            id: sessionID,
            startedAt: startedAt,
            appVersion: appVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: deviceModel,
            attributes: Dictionary(
                uniqueKeysWithValues: (attributes ?? [:])
                    .map { (LogSessionAttributeKey($0.key), $0.value) },
            ),
        )
    }
}

/// One row per distinct ambient state (see `AmbientSnapshot`), referenced by
/// every event stamped with it — the ambient counterpart to `SDLogSession`.
///
/// Events point at it with a plain `ambientSnapshotID` rather than a
/// relationship, matching how they reference their session: the write path
/// stays free of relationship bookkeeping, and one row serves the whole run
/// of events that shared that state.
@Model
final class SDAmbientSnapshot {
    #Index<SDAmbientSnapshot>([\.snapshotID])

    @Attribute(.unique) var snapshotID: UUID
    /// `AmbientKind.rawValue` → value. A dictionary rather than a JSON blob
    /// so reading a snapshot back has no decode step, and therefore no
    /// failure mode to swallow.
    var values: [String: String]
    /// When this state was first persisted. A snapshot row is written once
    /// and referenced thereafter, so this is also when the state began.
    var firstSeenAt: Date

    init(snapshot: AmbientSnapshot, firstSeenAt: Date) {
        snapshotID = snapshot.id
        // Both maps are injective (`AmbientKind` wraps its raw value), so
        // neither direction can collide into a duplicate key.
        values = Dictionary(
            uniqueKeysWithValues: snapshot.values.map { ($0.key.rawValue, $0.value) },
        )
        self.firstSeenAt = firstSeenAt
    }

    var toValue: AmbientSnapshot {
        AmbientSnapshot(
            id: snapshotID,
            values: Dictionary(
                uniqueKeysWithValues: values.map { (AmbientKind($0.key), $0.value) },
            ),
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
            SDAmbientSnapshot.self,
        ]
    }
}
