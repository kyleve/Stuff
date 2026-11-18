import Foundation

/// CloudKit assigns the user-record name within a container. Keep both parts of its identity.
public struct DataCompatibilityAccountID: Codable, Hashable, Sendable {
    public let containerIdentifier: String
    public let userRecordName: String

    public init(containerIdentifier: String, userRecordName: String) {
        self.containerIdentifier = containerIdentifier
        self.userRecordName = userRecordName
    }
}
