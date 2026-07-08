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
                uniqueKeysWithValues: event.tags.map { ($0.key.rawValue, $0.value) },
            )
        }
        if let span = event.spanID {
            object["span"] = span.rawValue.uuidString
        }
        if let exitMode = event.spanExitMode {
            object["spanExit"] = exitMode.rawValue
        }
        if !event.payload.isEmpty,
           let payload = try? JSONSerialization.jsonObject(with: event.payload)
        {
            object["payload"] = payload
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

    /// The primary scope's path (root → leaf), e.g. `"app/photos/album-1"`.
    static func scopePath(for event: StoredLogEvent, scopes: [ScopeID: LogScope]) -> String {
        guard let primary = event.primaryScope else { return "" }
        var names: [String] = []
        var next: ScopeID? = primary
        while let id = next, let scope = scopes[id] {
            names.append(scope.name)
            next = scope.parentID
        }
        return names.reversed().joined(separator: "/")
    }
}
