import Foundation

/// The decoded `POST /api/dashboard/get-aggregated-usage-events` response —
/// per-model usage for a date range. Token counts arrive as strings on the
/// wire, so they're modeled as `String` and exposed as `Int` via `totalTokens`.
///
/// Note: `totalCostCents` here is the dashboard's per-model compute measure,
/// which does **not** equal the billed on-demand figure in the usage summary —
/// Ledger uses it only for relative per-model **share**, never as spend.
public struct AggregatedUsage: Codable, Equatable, Sendable {
    public var aggregations: [ModelUsage]
    public var totalCostCents: Double

    public struct ModelUsage: Codable, Equatable, Sendable {
        public var modelIntent: String
        public var totalCents: Double
        public var tier: Int?
        public var inputTokens: String?
        public var outputTokens: String?
        public var cacheWriteTokens: String?
        public var cacheReadTokens: String?

        public init(
            modelIntent: String,
            totalCents: Double,
            tier: Int? = nil,
            inputTokens: String? = nil,
            outputTokens: String? = nil,
            cacheWriteTokens: String? = nil,
            cacheReadTokens: String? = nil,
        ) {
            self.modelIntent = modelIntent
            self.totalCents = totalCents
            self.tier = tier
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheWriteTokens = cacheWriteTokens
            self.cacheReadTokens = cacheReadTokens
        }

        /// Input + output + cache tokens, parsed from the wire strings.
        public var totalTokens: Int {
            [inputTokens, outputTokens, cacheWriteTokens, cacheReadTokens]
                .compactMap(\.self)
                .compactMap { Int($0) }
                .reduce(0, +)
        }
    }

    public init(aggregations: [ModelUsage], totalCostCents: Double) {
        self.aggregations = aggregations
        self.totalCostCents = totalCostCents
    }

    /// The top `limit` models by compute, each as a ``ModelShare`` (fraction of
    /// `totalCostCents`), highest first.
    public func topModels(limit: Int) -> [ModelShare] {
        let total = aggregations.reduce(0) { $0 + $1.totalCents }
        guard total > 0 else { return [] }
        return aggregations
            .sorted { $0.totalCents > $1.totalCents }
            .prefix(limit)
            .map { ModelShare(name: $0.modelIntent, fraction: $0.totalCents / total) }
    }
}

/// One model's relative share of the current cycle's usage (0...1). Deliberately
/// dollar-free — see the note on ``AggregatedUsage``.
public struct ModelShare: Equatable, Sendable, Identifiable {
    public var name: String
    public var fraction: Double

    public var id: String {
        name
    }

    public init(name: String, fraction: Double) {
        self.name = name
        self.fraction = fraction
    }
}
