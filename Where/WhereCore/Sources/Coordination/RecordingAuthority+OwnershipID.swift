import Foundation

extension RecordingAuthority {
    /// Identifies one continuous grant of recording ownership.
    /// The legacy URL namespace stays shared with event records; APIs distinguish the roles.
    public struct OwnershipID: Hashable, Sendable, WhereStoreURLCodable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        /// Only the transition that creates the entity derives its identity from its event.
        init(eventID: EventID) {
            rawValue = eventID.rawValue
        }

        public var storeURL: URL {
            EventID(rawValue: rawValue).storeURL
        }

        public init?(storeURL: URL) {
            guard let eventID = EventID(storeURL: storeURL) else { return nil }
            rawValue = eventID.rawValue
        }
    }
}
