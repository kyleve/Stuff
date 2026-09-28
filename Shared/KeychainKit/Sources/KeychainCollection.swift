import Foundation
import os
import Security

/// An append-only collection of independently synchronized secrets. Creating
/// different accounts never competes to replace one shared mutable item.
public protocol KeychainCollection: Sendable {
    func read(account: KeychainAccount) throws -> Data?
    func create(_ data: Data, account: KeychainAccount) throws
}

public struct KeychainAccount: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct SystemKeychainCollection: KeychainCollection {
    private let service: String
    private let accessibility: KeychainAccessibility
    private let synchronizesThroughICloud: Bool

    public init(
        service: String,
        accessibility: KeychainAccessibility,
        synchronizesThroughICloud: Bool,
    ) {
        self.service = service
        self.accessibility = accessibility
        self.synchronizesThroughICloud = synchronizesThroughICloud
    }

    public func read(account: KeychainAccount) throws -> Data? {
        try store(account: account).read()
    }

    public func create(_ data: Data, account: KeychainAccount) throws {
        try store(account: account).create(data)
    }

    private func store(account: KeychainAccount) -> SystemKeychainStore {
        SystemKeychainStore(
            service: service,
            account: account.rawValue,
            accessibility: accessibility,
            synchronizesThroughICloud: synchronizesThroughICloud,
        )
    }
}

@_spi(Testing)
public final class InMemoryKeychainCollection: KeychainCollection {
    private let items = OSAllocatedUnfairLock<[KeychainAccount: Data]>(initialState: [:])

    public init() {}

    public func read(account: KeychainAccount) -> Data? {
        items.withLock { $0[account] }
    }

    public func create(_ data: Data, account: KeychainAccount) throws {
        try items.withLock {
            guard $0[account] == nil else { throw KeychainError(status: errSecDuplicateItem) }
            $0[account] = data
        }
    }
}
