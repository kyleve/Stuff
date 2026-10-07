import Foundation

public protocol PhotosSaving: Sendable {
    func requestAccess() async -> Bool
    func save(
        originalURL: URL,
        rawURL: URL?,
        capturedAt: Date,
        recordIdentifier: @escaping @Sendable (String) async throws -> Void,
    ) async throws
        -> String
    func contains(assetIdentifier: String) async throws -> Bool
}
