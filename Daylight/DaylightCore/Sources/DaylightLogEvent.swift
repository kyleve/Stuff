import PeriscopeCore

public struct DaylightLogEvent: LogEvent {
    public static let eventName = "Daylight"
    public enum Operation: String, Codable,
        Sendable { case capture, photos, selection, publishing, recovery }
    public let operation: Operation
    public let message: String
    public init(operation: Operation, message: String) {
        self.operation = operation; self.message = message
    }
}
