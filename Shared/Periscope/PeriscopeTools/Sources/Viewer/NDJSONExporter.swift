import Foundation
import PeriscopeCore

/// Renders stored events as NDJSON (one JSON object per line, oldest first)
/// for attaching to bug reports. Structured payloads embed as nested JSON;
/// keys are sorted so output is deterministic.
enum NDJSONExporter {
    private static let timestampFormat = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
    )

    /// `events` newest first (as queried); the export reads chronologically.
    static func export(events: [StoredLogEvent], scopes: [ScopeID: LogScope]) -> String {
        events.reversed()
            .map { line(for: $0, scopes: scopes) }
            .joined(separator: "\n")
    }

    static func line(for event: StoredLogEvent, scopes: [ScopeID: LogScope]) -> String {
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
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys],
        ) else {
            // Every value above is a JSON-safe type; failing to serialize is
            // a programmer error.
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

    /// The primary scope's path (root → leaf), e.g. `"app/photos/album-1"`
    /// — exports join with `"/"` where display surfaces use `" / "`.
    static func scopePath(for event: StoredLogEvent, scopes: [ScopeID: LogScope]) -> String {
        guard let primary = event.primaryScope else { return "" }
        return LogScope.ancestry(of: primary) { scopes[$0] }
            .map(\.name)
            .joined(separator: "/")
    }
}
