import Foundation

/// An immutable lower bound independent of reset/Replace generations and live recording grants.
public struct DataCompatibilityRequirement: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let version: DataCompatibilityVersion

    public init(id: UUID, version: DataCompatibilityVersion) {
        self.id = id
        self.version = version
    }
}
