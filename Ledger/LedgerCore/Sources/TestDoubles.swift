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
        private let events: [UsageEvent]
        /// When set, only `usageEvents` throws it — exercises the best-effort
        /// per-model path (the summary still succeeds).
        private let eventsFailure: DashboardError?

        public init(
            _ outcome: Outcome,
            events: [UsageEvent] = [],
            eventsFailure: DashboardError? = nil,
        ) {
            self.outcome = outcome
            self.events = events
            self.eventsFailure = eventsFailure
        }

        /// Convenience: a successful summary.
        public init(summary: UsageSummary) {
            outcome = .success(summary: summary)
            events = []
            eventsFailure = nil
        }

        public func usageSummary(token _: SessionToken) async throws -> UsageSummary {
            switch outcome {
                case let .success(summary): summary
                case let .failure(error): throw error
            }
        }

        public func usageEvents(
            startDate _: Date,
            endDate _: Date,
            page: Int,
            pageSize _: Int,
            token _: SessionToken,
        ) async throws -> UsageEventsPage {
            if let eventsFailure { throw eventsFailure }
            if case let .failure(error) = outcome { throw error }
            // All events on page 1; later pages are empty (single-page fixture).
            let display = page == 1 ? events : []
            return UsageEventsPage(usageEventsDisplay: display, totalUsageEventsCount: events.count)
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

    extension UsageSummary {
        /// A minimal summary for previews/tests.
        public static func fixture(
            onDemandCents: Int,
            membershipType: String = "pro",
            includedUsed: Int = 0,
            includedLimit: Int? = nil,
            autoPercentUsed: Double? = nil,
            apiPercentUsed: Double? = nil,
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
                        autoPercentUsed: autoPercentUsed,
                        apiPercentUsed: apiPercentUsed,
                    ),
                ),
            )
        }
    }

    public enum UsageEventFixture {
        /// Builds usage events from `[model: costCents]` pairs (one event each).
        public static func events(_ modelCents: KeyValuePairs<String, Double>) -> [UsageEvent] {
            modelCents.map { UsageEvent(model: $0.key, chargedCents: $0.value) }
        }
    }
#endif
