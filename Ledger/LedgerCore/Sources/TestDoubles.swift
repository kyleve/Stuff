#if DEBUG
    import Foundation

    /// A ``DashboardProvider`` that returns scripted results instead of hitting
    /// the network — used by unit tests and SwiftUI previews. Lives in the
    /// module (behind `@_spi(Testing)` + `#if DEBUG`) so both callers share one
    /// double that conforms to the production protocol.
    @_spi(Testing)
    public struct ScriptedDashboardProvider: DashboardProvider {
        public enum Outcome: Sendable {
            case success(summary: UsageSummary)
            case failure(DashboardError)
        }

        private let outcome: Outcome
        private let aggregated: AggregatedUsage
        /// When set, only `aggregatedUsage` throws it — exercises the
        /// best-effort per-model path (summary/invoices still succeed).
        private let aggregatedFailure: DashboardError?

        public init(
            _ outcome: Outcome,
            aggregated: AggregatedUsage = AggregatedUsage(aggregations: [], totalCostCents: 0),
            aggregatedFailure: DashboardError? = nil,
        ) {
            self.outcome = outcome
            self.aggregated = aggregated
            self.aggregatedFailure = aggregatedFailure
        }

        /// Convenience: a successful summary.
        public init(summary: UsageSummary) {
            outcome = .success(summary: summary)
            aggregated = AggregatedUsage(aggregations: [], totalCostCents: 0)
            aggregatedFailure = nil
        }

        public func usageSummary(token _: SessionToken) async throws -> UsageSummary {
            switch outcome {
                case let .success(summary): summary
                case let .failure(error): throw error
            }
        }

        public func aggregatedUsage(
            startDate _: Date,
            endDate _: Date,
            token _: SessionToken,
        ) async throws -> AggregatedUsage {
            if let aggregatedFailure { throw aggregatedFailure }
            if case let .failure(error) = outcome { throw error }
            return aggregated
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
            totalPercentUsed: Double? = nil,
            messages: [String] = [],
            cycleStart: String = "2026-07-04T18:16:08.000Z",
            cycleEnd: String = "2026-08-04T18:16:08.000Z",
        ) -> UsageSummary {
            var summary = UsageSummary(
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
                        totalPercentUsed: totalPercentUsed,
                    ),
                ),
            )
            summary.autoModelSelectedDisplayMessage = messages.first
            summary.namedModelSelectedDisplayMessage = messages.count > 1 ? messages[1] : nil
            return summary
        }
    }

    extension AggregatedUsage {
        /// A per-model aggregation from `[model: costCents]` pairs.
        public static func fixture(_ modelCents: KeyValuePairs<String, Double>) -> AggregatedUsage {
            let models = modelCents.map { ModelUsage(modelIntent: $0.key, totalCents: $0.value) }
            return AggregatedUsage(
                aggregations: models,
                totalCostCents: models.reduce(0) { $0 + $1.totalCents },
            )
        }
    }
#endif
