import Foundation

/// A durable test shot follows Photos recovery without ever entering the publishing pipeline.
public struct ManualCapture: Codable, Equatable, Sendable, Identifiable {
    public let id: CaptureSequence.Slot.ID
    public let date: Date

    public var state: State
    public enum State: Codable, Equatable, Sendable {
        case capturing, captured(CapturedImage), failed(String)
    }

    public init(date: Date) {
        id = .init(rawValue: UUID()); self.date = date; state = .capturing
    }
}
