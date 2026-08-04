import Foundation
import PeriscopeCore

/// Renders stored events as NDJSON (one JSON object per line, oldest first)
/// for attaching to bug reports, headed by one `"record": "session"` line
/// per referenced session so the reader can join each event's `session` to
/// the build it ran on. Structured payloads embed as nested JSON; keys are
/// sorted so output is deterministic.
enum NDJSONExporter {
    private static let timestampFormat = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
    )

    /// `events` newest first (as queried); the export reads chronologically.
    /// `sessions` supplies the header lines — only those the events
    /// reference export, oldest first. `ambient` resolves
    /// ``StoredLogEvent/ambientSnapshotID`` — one row serves many events,
    /// so the caller looks them up once.
    static func export(
        events: [StoredLogEvent],
        scopes: [ScopeID: LogScope],
        sessions: [LogSession],
        ambient: [UUID: AmbientSnapshot],
    ) -> String {
        let referenced = Set(events.map(\.sessionID))
        let sessionLines = sessions
            .filter { referenced.contains($0.id) }
            .sorted { $0.startedAt < $1.startedAt }
            .map(line(for:))
        let eventLines = events.reversed()
            .map { line(for: $0, scopes: scopes, ambient: ambient) }
        return (sessionLines + eventLines).joined(separator: "\n")
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
