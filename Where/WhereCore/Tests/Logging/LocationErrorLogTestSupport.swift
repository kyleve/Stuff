import Foundation
import PeriscopeCore
import Testing

func verifyLocationErrorEvent<Event: LogEvent>(
    _ event: Event,
    name: String,
    message: String,
    level: LogLevel,
    original: NSError,
    externalID: String?,
    sourceLocation: SourceLocation = #_sourceLocation,
) throws {
    #expect(Event.eventName == name, sourceLocation: sourceLocation)
    #expect(Event.eventVersion == 2, sourceLocation: sourceLocation)
    #expect(event.message == message, sourceLocation: sourceLocation)
    #expect(event.level == level, sourceLocation: sourceLocation)
    #expect(event.externalID == externalID, sourceLocation: sourceLocation)
    #expect(
        event.classifiedFields.contains(.restricted(
            key: LogFieldKey("error"),
            kind: .errorDetails,
        )),
        sourceLocation: sourceLocation,
    )
    #expect(event.classifiedFields.allSatisfy {
        if case .restricted = $0 { return true }
        return false
    }, sourceLocation: sourceLocation)

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(Event.self, from: data)
    #expect(decoded.message == message, sourceLocation: sourceLocation)
    let payload = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any],
        sourceLocation: sourceLocation,
    )
    #expect(payload["description"] == nil, sourceLocation: sourceLocation)
    let error = try #require(payload["error"] as? [String: Any], sourceLocation: sourceLocation)
    let snapshot = try JSONDecoder().decode(
        LogError.self,
        from: JSONSerialization.data(withJSONObject: error),
    )
    #expect(snapshot == LogError(capturing: original), sourceLocation: sourceLocation)
}
