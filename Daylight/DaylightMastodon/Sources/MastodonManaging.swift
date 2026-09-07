import Foundation

public protocol MastodonManaging: Sendable {
    func configuration() async -> MastodonSettings
    func connect(server: String, token: String) async throws -> MastodonSettings
    func update(
        enabled: Bool,
        visibility: MastodonSettings.Visibility,
        caption: String,
    ) async throws
}
