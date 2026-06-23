import Foundation

/// A single captured log line. The facade builds one per call and appends it to
/// a ``LogStore``; the viewer renders these. `message` is already-rendered text
/// (see ``LogChannel`` for the privacy trade-off that implies).
public struct LogEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let date: Date
    public let level: LogLevel
    public let subsystem: String
    public let category: String
    public let message: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: LogLevel,
        subsystem: String,
        category: String,
        message: String,
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.message = message
    }
}
