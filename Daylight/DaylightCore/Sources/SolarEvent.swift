import Foundation

public struct SolarEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case sunrise, sunset }
    public struct ID: Codable, Hashable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int
        public let kind: Kind
        public var storageKey: String {
            "\(year)-\(month)-\(day)-\(kind.rawValue)"
        }
    }

    public let id: ID
    public let date: Date
    public init(id: ID, date: Date) {
        self.id = id; self.date = date
    }
}
