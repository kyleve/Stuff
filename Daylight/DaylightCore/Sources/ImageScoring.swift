import Foundation

public protocol ImageScoring: Sendable {
    func score(_ image: Data) async throws -> ImageScore
}
