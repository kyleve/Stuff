#if DEBUG
    import Foundation

    /// A ``DashboardProvider`` that returns scripted results instead of hitting
    /// the network — used by unit tests and SwiftUI previews. Lives in the
    /// module (behind `@_spi(Testing)` + `#if DEBUG`) so both callers share one
    /// double that conforms to the production protocol.
    @_spi(Testing)
    public struct ScriptedDashboardProvider: DashboardProvider {
        public enum Outcome: Sendable {
            case success(summary: UsageSummary, invoiceCentsByMonth: [Int: Int])
            case failure(DashboardError)
        }

        private let outcome: Outcome

        public init(_ outcome: Outcome) {
            self.outcome = outcome
        }

        /// Convenience: a successful summary with no prior-month invoices.
        public init(summary: UsageSummary) {
            outcome = .success(summary: summary, invoiceCentsByMonth: [:])
        }

        public func usageSummary(token _: SessionToken) async throws -> UsageSummary {
            switch outcome {
                case let .success(summary, _): summary
                case let .failure(error): throw error
            }
        }

        public func monthlyInvoice(
            month: Int,
            year _: Int,
            token _: SessionToken,
        ) async throws -> MonthlyInvoice {
            switch outcome {
                case let .success(_, invoiceCentsByMonth):
                    let cents = invoiceCentsByMonth[month] ?? 0
                    return MonthlyInvoice(items: cents == 0 ? nil : [.init(
                        description: "m\(month)",
                        cents: cents,
                    )])
                case let .failure(error):
                    throw error
            }
        }
    }

    /// A ``SessionTokenSource`` that returns a fixed token (or none), so
    /// auto-detection is testable without reading a real `state.vscdb`.
    @_spi(Testing)
    public struct StubTokenSource: SessionTokenSource {
        private let token: SessionToken?
        public init(token: SessionToken?) {
            self.token = token
        }

        public func currentToken() -> SessionToken? {
            token
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

    extension UsageSummary {
        /// A minimal summary for previews/tests.
        public static func fixture(
            onDemandCents: Int,
            membershipType: String = "pro",
            includedUsed: Int = 0,
            includedLimit: Int? = nil,
            cycleStart: String = "2026-07-04T18:16:08.000Z",
            cycleEnd: String = "2026-08-04T18:16:08.000Z",
        ) -> UsageSummary {
            UsageSummary(
                billingCycleStart: cycleStart,
                billingCycleEnd: cycleEnd,
                membershipType: membershipType,
                individualUsage: .init(
                    onDemand: .init(enabled: true, used: onDemandCents, limit: nil, remaining: nil),
                    plan: .init(
                        enabled: true,
                        used: includedUsed,
                        limit: includedLimit,
                        remaining: nil,
                        breakdown: nil,
                    ),
                ),
            )
        }
    }
#endif
