import Foundation

/// Persisted generation bookkeeping for the dismissible recording-configuration warning.
public struct RecordingConfigurationWarningRegistration: Equatable, Sendable {
    public private(set) var generation: Int
    public private(set) var acknowledgedGeneration: Int?
    public private(set) var wasWarningConditionActive: Bool?

    public init(
        generation: Int = 0,
        acknowledgedGeneration: Int? = nil,
        wasWarningConditionActive: Bool? = nil,
    ) {
        precondition(generation >= 0, "A warning generation cannot be negative.")
        precondition(
            acknowledgedGeneration.map { $0 <= generation } ?? true,
            "A warning cannot acknowledge a future generation.",
        )
        self.generation = generation
        self.acknowledgedGeneration = acknowledgedGeneration
        self.wasWarningConditionActive = wasWarningConditionActive
    }

    public var requiresWarning: Bool {
        wasWarningConditionActive == true && acknowledgedGeneration != generation
    }

    /// Register the latest relevant settings tuple, advancing only when it re-enters the warning
    /// condition. Persisting the previous condition prevents a steady bad state from becoming a
    /// new generation on every launch.
    public mutating func register(isWarningConditionActive: Bool) {
        if isWarningConditionActive, wasWarningConditionActive != true {
            generation += 1
        }
        wasWarningConditionActive = isWarningConditionActive
    }

    public mutating func acknowledgeCurrentGeneration() {
        guard requiresWarning else { return }
        acknowledgedGeneration = generation
    }
}
