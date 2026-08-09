import Foundation
import StuffCore

/// Cancellable work owned by one signed-in GitHub account.
public actor PatchlightAccountWork {
    public struct ID: RawRepresentable, Hashable, Sendable {
        public let rawValue: UUID

        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }
    }

    private var tasks: [ID: Task<Void, Never>] = [:]

    public func register(_ task: Task<Void, Never>) -> ID {
        let id = ID(rawValue: UUID())
        tasks[id] = task
        return id
    }

    public func finish(_ id: ID) {
        tasks[id] = nil
    }

    public func cancelAll() async {
        let active = Array(tasks.values)
        tasks.removeAll()
        active.forEach { $0.cancel() }
        for task in active {
            await task.value
        }
    }
}

/// One complete signed-in world: store, encryption, cache, and cancellable work.
public actor PatchlightScope {
    public nonisolated let accountID: PatchlightAccountID
    public nonisolated let accountStore: PatchlightAccountStore
    public nonisolated let cache: EncryptedContentCache
    public nonisolated let work: PatchlightAccountWork

    private enum State {
        case active
        case signingOut
        case signedOut
    }

    private let rootURL: URL
    private let keyManager: AccountVaultKeyManager
    private var state = State.active

    private init(
        accountID: PatchlightAccountID,
        accountStore: PatchlightAccountStore,
        cache: EncryptedContentCache,
        work: PatchlightAccountWork,
        rootURL: URL,
        keyManager: AccountVaultKeyManager,
    ) {
        self.accountID = accountID
        self.accountStore = accountStore
        self.cache = cache
        self.work = work
        self.rootURL = rootURL
        self.keyManager = keyManager
    }

    public static func make(
        accountID: PatchlightAccountID,
        rootURL: URL,
        credentialStore: any CredentialStore,
        cacheCapacity: CacheCapacity,
    ) throws -> PatchlightScope {
        let accountRoot = rootURL.appendingPathComponent(
            String(accountID.rawValue),
            isDirectory: true,
        )
        try FileManager.default.createDirectory(
            at: accountRoot,
            withIntermediateDirectories: true,
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = accountRoot
        try mutableRoot.setResourceValues(values)

        let keyManager = AccountVaultKeyManager(
            accountID: accountID,
            credentialStore: credentialStore,
        )
        let cipher = try VaultCipher(keyData: keyManager.loadOrCreate())
        let store = try PatchlightStore.make(storage: .onDisk(
            accountRoot.appendingPathComponent("Patchlight.store", isDirectory: false),
        ))
        let cache = try EncryptedContentCache.make(
            directory: accountRoot.appendingPathComponent("Cache", isDirectory: true),
            cipher: cipher,
            index: store,
            capacity: cacheCapacity,
        )
        return PatchlightScope(
            accountID: accountID,
            accountStore: PatchlightAccountStore(store: store, cipher: cipher),
            cache: cache,
            work: PatchlightAccountWork(),
            rootURL: accountRoot,
            keyManager: keyManager,
        )
    }

    /// Cryptographic purge is ordered: cancel work, delete the vault key, then
    /// remove the now-unreadable account database/cache and GitHub credentials.
    public func signOut(removingGitHubCredentials removeCredentials: @Sendable () throws -> Void)
        async throws
    {
        switch state {
            case .signedOut:
                return
            case .signingOut:
                throw PatchlightSignOutError.alreadyInProgress
            case .active:
                state = .signingOut
        }

        await work.cancelAll()
        do {
            try keyManager.remove()
        } catch {
            state = .active
            throw error
        }

        do {
            if FileManager.default.fileExists(atPath: rootURL.path) {
                try FileManager.default.removeItem(at: rootURL)
            }
            try removeCredentials()
            state = .signedOut
        } catch {
            // The key is already gone: cryptographic purge succeeded even when
            // filesystem/token cleanup needs a subsequent recovery pass.
            state = .signedOut
            throw PatchlightSignOutError.cleanupFailed(error.localizedDescription)
        }
    }

    public static var defaultRootURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Patchlight", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
    }
}

public enum PatchlightSignOutError: LocalizedError, Equatable, Sendable {
    case alreadyInProgress
    case cleanupFailed(String)

    public var errorDescription: String? {
        switch self {
            case .alreadyInProgress:
                "GitHub sign-out is already in progress."
            case let .cleanupFailed(reason):
                "The vault key was deleted, but local sign-out cleanup failed: \(reason)"
        }
    }
}
