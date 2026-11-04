import Foundation
import Security

/// Security-framework seam for identity storage. The production client and fault-injection
/// client use the same calls; the store owns status interpretation and payload validation.
@_spi(Testing)
@MainActor
public protocol RecordingIdentityKeychainClient {
    func copyMatching(_ query: [String: Any]) -> RecordingIdentityKeychainRead
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
}

@_spi(Testing)
public struct RecordingIdentityKeychainRead {
    public let status: OSStatus
    public let attributes: [String: Any]?

    public init(status: OSStatus, attributes: [String: Any]?) {
        self.status = status
        self.attributes = attributes
    }
}

@MainActor
struct SystemRecordingIdentityKeychainClient: RecordingIdentityKeychainClient {
    func copyMatching(_ query: [String: Any]) -> RecordingIdentityKeychainRead {
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        return RecordingIdentityKeychainRead(status: status, attributes: value as? [String: Any])
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
}
