#if DEBUG
    import Foundation

    /// A ``SpendProvider`` that returns a scripted outcome instead of hitting
    /// the network — used by unit tests and SwiftUI previews. Lives in the
    /// module (behind `@_spi(Testing)` + `#if DEBUG`) so both callers share one
    /// double that conforms to the production protocol.
    @_spi(Testing)
    public struct ScriptedSpendProvider: SpendProvider {
        public enum Outcome: Sendable {
            case success(SpendResponse)
            case failure(SpendProviderError)
        }

        private let outcome: Outcome

        public init(_ outcome: Outcome) {
            self.outcome = outcome
        }

        /// Convenience: succeed with a single member for `email`.
        public init(member: MemberSpend) {
            outcome = .success(SpendResponse(teamMemberSpend: [member]))
        }

        public func fetchSpend(apiKey _: String) async throws -> SpendResponse {
            switch outcome {
                case let .success(response): response
                case let .failure(error): throw error
            }
        }
    }

    /// An in-memory ``KeychainStore`` — the real Keychain needs a signed,
    /// entitled host that hostless test processes and previews don't have.
    @_spi(Testing)
    public final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
        private let lock = NSLock()
        private var secret: String?
        /// When set, `read`/`write`/`remove` throw it — exercises the error path.
        private let failure: KeychainError?

        public init(secret: String? = nil, failure: KeychainError? = nil) {
            self.secret = secret
            self.failure = failure
        }

        public func read() throws -> String? {
            if let failure { throw failure }
            return lock.withLock { secret }
        }

        public func write(_ secret: String) throws {
            if let failure { throw failure }
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            lock.withLock { self.secret = trimmed.isEmpty ? nil : trimmed }
        }

        public func remove() throws {
            if let failure { throw failure }
            lock.withLock { secret = nil }
        }
    }
#endif
