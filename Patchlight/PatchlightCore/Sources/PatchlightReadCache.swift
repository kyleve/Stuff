import Foundation

public struct ReadSnapshotKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A read snapshot key must not be empty")
        self.rawValue = rawValue
    }

    public static let dashboard = ReadSnapshotKey(rawValue: "dashboard")

    public static func workspace(_ pullRequest: PullRequestID) -> ReadSnapshotKey {
        ReadSnapshotKey(rawValue: "workspace:\(pullRequest.storageKey)")
    }

    public static func repositoryPullRequests(_ repository: RepositoryID) -> ReadSnapshotKey {
        ReadSnapshotKey(rawValue: "repository:\(repository.rawValue):pull-requests")
    }
}

public struct StoredRead<Value: Sendable>: Sendable {
    public let value: Value
    public let refreshedAt: Date
    public let etag: String?

    public init(value: Value, refreshedAt: Date, etag: String?) {
        self.value = value
        self.refreshedAt = refreshedAt
        self.etag = etag
    }
}

/// Encrypts immutable read DTOs before they reach SwiftData.
public actor PatchlightReadCache {
    private let store: PatchlightStore
    private let cipher: VaultCipher

    init(store: PatchlightStore, cipher: VaultCipher) {
        self.store = store
        self.cipher = cipher
    }

    public func save(
        _ value: some Encodable & Sendable,
        key: ReadSnapshotKey,
        refreshedAt: Date,
        etag: String?,
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let ciphertext = try cipher.seal(encoder.encode(value))
        try await store.upsertReadSnapshot(EncryptedReadSnapshot(
            key: key.rawValue,
            payloadCiphertext: ciphertext,
            refreshedAt: refreshedAt,
            etag: etag,
        ))
    }

    public func load<Value: Decodable & Sendable>(
        _ type: Value.Type,
        key: ReadSnapshotKey,
    ) async throws -> StoredRead<Value>? {
        guard let snapshot = try await store.readSnapshot(key: key.rawValue) else { return nil }
        let plaintext = try cipher.open(snapshot.payloadCiphertext)
        do {
            return try StoredRead(
                value: JSONDecoder().decode(type, from: plaintext),
                refreshedAt: snapshot.refreshedAt,
                etag: snapshot.etag,
            )
        } catch {
            throw PatchlightReadCacheError.invalidPayload
        }
    }
}

public enum PatchlightReadCacheError: LocalizedError, Equatable, Sendable {
    case invalidPayload

    public var errorDescription: String? {
        "An encrypted GitHub read snapshot is invalid."
    }
}

public enum CachedReadSource: String, Codable, Sendable {
    case live = "L"
    case cache = "C"
}

public struct ReadFallbackReason: Hashable, Codable, Sendable {
    public enum Code: String, Codable, Sendable {
        case offline = "O"
        case reauthorizationRequired = "A"
        case rateLimited = "R"
        case refreshFailed = "F"
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

public struct CachedRead<Value: Sendable>: Sendable {
    public let value: Value
    public let source: CachedReadSource
    public let refreshedAt: Date
    public let fallbackReason: ReadFallbackReason?

    public init(
        value: Value,
        source: CachedReadSource,
        refreshedAt: Date,
        fallbackReason: ReadFallbackReason?,
    ) {
        self.value = value
        self.source = source
        self.refreshedAt = refreshedAt
        self.fallbackReason = fallbackReason
    }
}

/// Refreshes GitHub reads and falls back to encrypted local DTOs without ever
/// turning a failed refresh into a fresh-looking success.
public actor GitHubReadCoordinator {
    private let github: any GitHubReading
    private let cache: PatchlightReadCache
    private let now: @Sendable () -> Date

    public init(
        github: any GitHubReading,
        cache: PatchlightReadCache,
    ) {
        self.github = github
        self.cache = cache
        now = { Date() }
    }

    #if DEBUG
        @_spi(Testing)
        public init(
            github: any GitHubReading,
            cache: PatchlightReadCache,
            now: @escaping @Sendable () -> Date,
        ) {
            self.github = github
            self.cache = cache
            self.now = now
        }
    #endif

    public func dashboard() async throws -> CachedRead<ReviewDashboard> {
        let github = github
        return try await refresh(
            key: .dashboard,
            type: ReviewDashboard.self,
            operation: { try await github.dashboard() },
        )
    }

    public func workspace(
        for pullRequest: PullRequestID,
    ) async throws -> CachedRead<PullRequestWorkspace> {
        let github = github
        return try await refresh(
            key: .workspace(pullRequest),
            type: PullRequestWorkspace.self,
            operation: { try await github.workspace(for: pullRequest) },
        )
    }

    public func pullRequests(
        in repository: RepositoryID,
    ) async throws -> CachedRead<[PullRequestSummary]> {
        let github = github
        return try await refresh(
            key: .repositoryPullRequests(repository),
            type: [PullRequestSummary].self,
            operation: { try await github.pullRequests(in: repository) },
        )
    }

    private func refresh<Value: Codable & Sendable>(
        key: ReadSnapshotKey,
        type: Value.Type,
        operation: @Sendable () async throws -> Value,
    ) async throws -> CachedRead<Value> {
        do {
            let value = try await operation()
            let refreshedAt = now()
            try await cache.save(value, key: key, refreshedAt: refreshedAt, etag: nil)
            return CachedRead(
                value: value,
                source: .live,
                refreshedAt: refreshedAt,
                fallbackReason: nil,
            )
        } catch {
            guard let stored = try await cache.load(type, key: key) else { throw error }
            return CachedRead(
                value: stored.value,
                source: .cache,
                refreshedAt: stored.refreshedAt,
                fallbackReason: Self.fallbackReason(for: error),
            )
        }
    }

    private static func fallbackReason(for error: any Error) -> ReadFallbackReason {
        let code: ReadFallbackReason.Code = if let urlError = error as? URLError,
                                               [
                                                   .notConnectedToInternet,
                                                   .networkConnectionLost,
                                                   .cannotConnectToHost,
                                                   .cannotFindHost,
                                                   .timedOut,
                                               ].contains(urlError.code)
        {
            .offline
        } else if error as? GitHubAuthenticationError == .reauthorizationRequired ||
            error as? GitHubAPIError == .authenticationExpired
        {
            .reauthorizationRequired
        } else if case .rateLimited = error as? GitHubAPIError {
            .rateLimited
        } else {
            .refreshFailed
        }
        return ReadFallbackReason(code: code, message: error.localizedDescription)
    }
}
