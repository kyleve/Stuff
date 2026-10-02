import Foundation

/// A verified requirement, or nil when verification failed. Missing metadata never permits data.
public struct WidgetCompatibilitySnapshot: Codable, Sendable, Hashable {
    public let requiredVersion: DataCompatibilityVersion?

    public init(requiredVersion: DataCompatibilityVersion?) {
        self.requiredVersion = requiredVersion
    }

    public var allowsData: Bool {
        guard let requiredVersion else { return false }
        return requiredVersion <= .current
    }
}
