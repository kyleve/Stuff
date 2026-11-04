import Foundation

/// Evidence already selected by the history reader. Raw pings and upload times are not inputs.
public struct RecordingHistoryContribution: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case effectiveObservation
        case explicitSourceChoice
    }

    public let deviceID: RecordingDeviceID
    public let period: RecordingPeriod
    public let kind: Kind

    public init(deviceID: RecordingDeviceID, period: RecordingPeriod, kind: Kind) {
        self.deviceID = deviceID
        self.period = period
        self.kind = kind
    }
}

public enum DataCompatibilityUpgradeEligibility {
    /// Rolling elapsed-time window, measured from the evidence period, never its upload time.
    public static let contributionWindow: TimeInterval = 15 * 24 * 60 * 60

    public static func qualifies(
        deviceID: RecordingDeviceID,
        contributions: [RecordingHistoryContribution],
        now: Date,
    ) -> Bool {
        let earliest = now.addingTimeInterval(-contributionWindow)
        return contributions.contains {
            $0.deviceID == deviceID && $0.period.start <= now && $0.period.end > earliest
        }
    }
}
