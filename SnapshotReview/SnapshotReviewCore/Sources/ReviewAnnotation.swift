import Foundation

/// A note or task against one image revision; nil point means the whole image.
public struct ReviewAnnotation: Codable, Equatable, Identifiable, Sendable {
    public struct ID: Codable, Hashable, Sendable {
        public let value: UUID
        public init() {
            value = UUID()
        }
    }

    public enum Status: String, Codable, CaseIterable, Sendable {
        case note
        case open
        case resolved
    }

    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x; self.y = y
        }

        public var isValid: Bool {
            x.isFinite && y.isFinite && (0 ... 1).contains(x) && (0 ... 1).contains(y)
        }
    }

    public var id: ID
    public var text: String
    public var status: Status
    public var point: Point?
    public var fingerprint: String
    public var createdAt: Date
    public var editedAt: Date

    public init(text: String, status: Status, point: Point?, fingerprint: String, date: Date) {
        id = ID()
        self.text = text
        self.status = status
        self.point = point
        self.fingerprint = fingerprint
        createdAt = date
        editedAt = date
    }
}
