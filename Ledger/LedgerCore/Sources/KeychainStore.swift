import Foundation
import KeychainKit

/// A failure reading or writing the Keychain. Wraps the raw `OSStatus` so a
/// caller can log something actionable rather than swallowing the error.
public typealias KeychainError = KeychainKit.KeychainError

/// Stores a single secret string (a pasted Cursor session token) securely.
/// The seam is a protocol so tests use an in-memory fake — the real Keychain
/// isn't available in a hostless test process without a signed, entitled host.
public protocol KeychainStore: Sendable {
    /// The stored secret, or `nil` when nothing is stored. Throws
    /// ``KeychainError`` on an unexpected Keychain failure (a missing item is
    /// `nil`, not an error).
    func read() throws -> String?
    /// Stores `secret`, replacing any existing value. Passing an empty or
    /// whitespace-only string removes the item.
    func write(_ secret: String) throws
    /// Removes the stored secret, if any.
    func remove() throws
}

/// The production ``KeychainStore``: a generic-password item in the login
/// Keychain, keyed by `service`/`account`. Ledger isn't sandboxed (like the
/// old Foreman app), so it reaches the default login Keychain without a
/// keychain-access-group entitlement.
public struct SystemKeychainStore: KeychainStore {
    private let backing: KeychainKit.SystemKeychainStore

    /// Defaults to the app's bundle-style service and a fixed account name;
    /// there is only ever one secret (a pasted session token).
    public init(service: String = "com.stuff.ledger", account: String = "session-token") {
        backing = KeychainKit.SystemKeychainStore(
            service: service,
            account: account,
            accessibility: .whenUnlocked,
            synchronizesThroughICloud: false,
        )
    }

    public func read() throws -> String? {
        try backing.readString()
    }

    public func write(_ secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try remove()
            return
        }

        try backing.write(trimmed)
    }

    public func remove() throws {
        try backing.remove()
    }
}
