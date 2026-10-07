import Foundation

public struct ImageScore: Codable, Equatable, Sendable {
    public let overall: Float
    public let isUtility: Bool
    public init(overall: Float, isUtility: Bool) {
        self.overall = overall; self.isUtility = isUtility
    }
}
