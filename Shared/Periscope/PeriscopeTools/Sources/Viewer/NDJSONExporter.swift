import Foundation
import PeriscopeCore

/// Renders stored events as NDJSON (one JSON object per line, oldest first)
/// for attaching to bug reports, headed by one `"record": "session"` line
/// per referenced session so the reader can join each event's `session` to
/// the build it ran on. Structured payloads embed as nested JSON; keys are
/// sorted so output is deterministic.
public enum NDJSONExporter {
    /// Unfiltered export intentionally includes local-only data. Filtered export requires
    /// persisted permissions and never falls back to the raw payload.
    public enum Mode: Sendable {
        case unfiltered
        case filtered(LogExportPolicy)
    }

    private static let timestampFormat = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
    )

    /// `events` newest first (as queried); the export reads chronologically.
    /// `sessions` supplies the header lines — only those the events
    /// reference export, oldest first. `ambient` resolves
    /// ``StoredLogEvent/ambientSnapshotID`` — one row serves many events,
    /// so the caller looks them up once.
    public static func export(
        events: [StoredLogEvent],
        scopes: [ScopeID: LogScope],
        sessions: [LogSession],
        ambient: [UUID: AmbientSnapshot],
        mode: Mode,
    ) throws -> String {
        if case let .filtered(policy) = mode {
            let referenced = Set(events.filter { $0.exportMetadata != nil }.map(\.sessionID))
            let headers = try sessions.filter { referenced.contains($0.id) }
                .sorted { $0.startedAt < $1.startedAt }
                .compactMap { try filteredLine(for: $0, policy: policy) }
            let lines = try events.reversed().map { try filteredLine(
                for: $0,
                scopes: scopes,
                policy: policy,
            ) }
            return (headers + lines).joined(separator: "\n")
        }
        let referenced = Set(events.map(\.sessionID))
        let sessionLines = sessions
            .filter { referenced.contains($0.id) }
            .sorted { $0.startedAt < $1.startedAt }
            .map(line(for:))
        let eventLines = events.reversed()
            .map { line(for: $0, scopes: scopes, ambient: ambient) }
        return (sessionLines + eventLines).joined(separator: "\n")
    }

    private static func filteredLine(
        for session: LogSession,
        policy: LogExportPolicy,
    ) throws -> String? {
        guard policy.allows(LogContextExportRequirements.sessionID) else { return nil }
        var object: [String: JSONValue] = [
            "record": .string("session"),
            "session": .string(session.id.uuidString),
        ]
        if policy.allows(LogContextExportRequirements.sessionDetails) {
            object["startedAt"] = .string(session.startedAt.formatted(timestampFormat))
            object["appVersion"] = .string(session.appVersion)
            object["buildNumber"] = .string(session.buildNumber)
            object["osVersion"] = .string(session.osVersion)
            object["deviceModel"] = .string(session.deviceModel)
        }
        if policy.allows(LogContextExportRequirements.sessionAttributes),
           !session.attributes.isEmpty
        {
            object["attributes"] = .object(Dictionary(uniqueKeysWithValues: session.attributes.map {
                ($0.key.rawValue, .string($0.value))
            }))
        }
        return try serialized(.object(object))
    }

    private static func filteredLine(
        for event: StoredLogEvent,
        scopes: [ScopeID: LogScope],
        policy: LogExportPolicy,
    ) throws -> String {
        var object: [String: JSONValue] = [
            "level": .string(event.level.name),
            "severity": .int(event.level.severity),
            "event": .string(event.eventName),
            "version": .int(event.eventVersion),
            "message": .string(event.eventName),
        ]
        // Historical rows retain only known record metadata, even when all grants are enabled.
        guard event.exportMetadata != nil else { return try serialized(.object(object)) }
        object["payload"] = try event.exportedPayload(using: policy)
        if let callSite = event.callSite {
            object["function"] = .string(callSite.function)
            object["file"] = .string(callSite.fileID)
        }
        if policy.allows(LogContextExportRequirements.date) {
            object["date"] = .string(event.date.formatted(timestampFormat))
        }
        if policy.allows(LogContextExportRequirements.sessionID) {
            object["session"] = .string(event.sessionID.uuidString)
        }
        if policy.allows(LogContextExportRequirements.spanID), let span = event.spanID {
            object["span"] = .string(span.rawValue.uuidString)
        }
        if policy.allows(LogContextExportRequirements.externalID),
           let externalID = event.externalID
        {
            object["externalID"] = .string(externalID)
        }
        if policy.allows(LogContextExportRequirements.scopes) {
            let path = scopePath(for: event, scopes: scopes)
            if !path.isEmpty { object["scopePath"] = .string(path) }
        }
        if policy.allows(LogContextExportRequirements.tags), !event.tags.isEmpty {
            let data = try JSONSerialization
                .data(withJSONObject: Dictionary(uniqueKeysWithValues: event.tags.map {
                    ($0.key.rawValue, jsonValue(for: $0.value))
                }))
            object["tags"] = try JSONDecoder().decode(JSONValue.self, from: data)
        }
        // Rendered messages and folded ambient snapshots cannot retain nested field policies.
        // Neither is included in filtered exports, regardless of grants.
        return try serialized(.object(object))
    }

    private static func serialized(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try String(decoding: encoder.encode(value), as: UTF8.self)
    }

    /// One session's identity and build attribution — the line that makes
    /// an exported duration answerable ("which build, at which optimization
    /// level"), which the per-event `session` UUID alone can't.
    static func line(for session: LogSession) -> String {
        var object: [String: Any] = [
            "record": "session",
            "session": session.id.uuidString,
            "startedAt": session.startedAt.formatted(timestampFormat),
            "appVersion": session.appVersion,
            "buildNumber": session.buildNumber,
            "osVersion": session.osVersion,
            "deviceModel": session.deviceModel,
        ]
        if !session.attributes.isEmpty {
            object["attributes"] = Dictionary(
                uniqueKeysWithValues: session.attributes.map { ($0.key.rawValue, $0.value) },
            )
        }
        return serialized(object)
    }

    static func line(
        for event: StoredLogEvent,
        scopes: [ScopeID: LogScope],
        ambient: [UUID: AmbientSnapshot],
    ) -> String {
        var object: [String: Any] = [
            "date": event.date.formatted(timestampFormat),
            "level": event.level.name,
            "severity": event.level.severity,
            "event": event.eventName,
            "version": event.eventVersion,
            "message": event.message,
            "session": event.sessionID.uuidString,
        ]
        let path = scopePath(for: event, scopes: scopes)
        if !path.isEmpty {
            object["scopePath"] = path
        }
        if !event.tags.isEmpty {
            object["tags"] = Dictionary(
                uniqueKeysWithValues: event.tags
                    .map { ($0.key.rawValue, jsonValue(for: $0.value)) },
            )
        }
        if let span = event.spanID {
            object["span"] = span.rawValue.uuidString
        }
        if let exitMode = event.spanExitMode {
            object["spanExit"] = exitMode.rawValue
        }
        if let callSite = event.callSite {
            object["function"] = callSite.function
            object["file"] = callSite.fileID
        }
        if let externalID = event.externalID {
            object["externalID"] = externalID
        }
        if let snapshotID = event.ambientSnapshotID {
            if let snapshot = ambient[snapshotID] {
                object["ambient"] = Dictionary(
                    uniqueKeysWithValues: snapshot.values.map { kind, value in
                        (kind.rawValue, Dictionary(
                            uniqueKeysWithValues: value.map { ($0.key, jsonValue(for: $0.value)) },
                        ))
                    },
                )
            } else {
                // Retention only drops *unreferenced* snapshots, so a
                // referenced one going missing is a real inconsistency —
                // the export says so rather than reading as "no ambient
                // state was known".
                object["ambientError"] = "snapshot \(snapshotID.uuidString) not found"
            }
        }
        if !event.payload.isEmpty {
            if let payload = try? JSONSerialization.jsonObject(with: event.payload) {
                object["payload"] = payload
            } else {
                // Persisted payloads are JSONEncoder output, so this means
                // on-disk corruption — the export must say the payload
                // existed and didn't survive, not silently omit the key.
                object["payloadError"] = "unparseable (\(event.payload.count) bytes)"
            }
        }
        return serialized(object)
    }

    private static func serialized(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys],
        ) else {
            // Every value handed in is a JSON-safe type; failing to
            // serialize is a programmer error.
            assertionFailure("NDJSON line failed to serialize")
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A tag value as its native JSON type — numbers stay numbers, bools
    /// stay bools; an `.encoded` payload embeds as parsed JSON when it
    /// parses, its raw string otherwise.
    private static func jsonValue(for value: LogTagValue) -> Any {
        switch value {
            case let .string(string): string
            case let .int(int): int
            case let .double(double): double
            case let .bool(bool): bool
            case let .encoded(json):
                (try? JSONSerialization.jsonObject(
                    with: Data(json.utf8),
                    options: [.fragmentsAllowed],
                )) ?? json
        }
    }

    /// An ambient field as its native JSON type, so exported snapshots stay
    /// plain JSON objects.
    private static func jsonValue(for value: AmbientValue) -> Any {
        switch value {
            case let .string(string): string
            case let .int(int): int
            case let .double(double): double
            case let .bool(bool): bool
        }
    }

    /// The primary scope's path (root → leaf), e.g. `"app/photos/album-1"`
    /// — exports join with `"/"` where display surfaces use `" / "`.
    static func scopePath(for event: StoredLogEvent, scopes: [ScopeID: LogScope]) -> String {
        guard let primary = event.primaryScope else { return "" }
        return LogScope.ancestry(of: primary) { scopes[$0] }
            .map(\.name)
            .joined(separator: "/")
    }
}
