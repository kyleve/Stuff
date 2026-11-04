import Foundation
import Security
@_spi(Testing) @testable import WhereCore

@MainActor
enum RecordingIdentityTestSupport {
    static func identity(creation: InstallationRecordingIdentity.Creation = .initial)
        -> InstallationRecordingIdentity
    {
        InstallationRecordingIdentity(
            deviceID: RecordingDeviceID(rawValue: UUID()),
            registeredAt: Date(timeIntervalSinceReferenceDate: 1234),
            creation: creation,
        )
    }

    static func attributes(_ identity: InstallationRecordingIdentity) throws -> [String: Any] {
        try [
            kSecValueData as String: JSONEncoder().encode(identity),
            kSecAttrGeneric as String: Data(identity.deviceID.rawValue.uuidString.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
    }

    final class Client: RecordingIdentityKeychainClient {
        var result: RecordingIdentityKeychainRead
        private(set) var readQueries: [[String: Any]] = []
        private(set) var additions: [[String: Any]] = []
        private(set) var updates: [[String: Any]] = []
        var writeStatus: OSStatus = errSecSuccess

        init(result: RecordingIdentityKeychainRead) {
            self.result = result
        }

        func copyMatching(_ query: [String: Any]) -> RecordingIdentityKeychainRead {
            readQueries.append(query)
            return result
        }

        func add(_ attributes: [String: Any]) -> OSStatus {
            additions.append(attributes)
            return writeStatus
        }

        func update(_ query: [String: Any], attributes _: [String: Any]) -> OSStatus {
            updates.append(query)
            return writeStatus
        }
    }
}
