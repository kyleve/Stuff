import Foundation

public protocol ImageProcessing: Sendable {
    func render(_ original: Data, recipe: ImageRecipe) async throws -> Data
}
