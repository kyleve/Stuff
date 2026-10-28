import Foundation
import SnapshotKit

/// The environment-selected patience applied to snapshot settle ceilings.
///
/// The multiplier deliberately affects only maximum durations: it gives slow
/// runners longer to finish genuinely moving content without changing when a
/// stable capture succeeds.
@_spi(Testing) public struct SnapshotSettleTimeoutPolicy: Equatable, Sendable {
    public static let environmentKey = "SNAPSHOT_SETTLE_TIMEOUT_MULTIPLIER"

    public let multiplier: Double

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
    ) throws -> Self {
        try parse(environment[environmentKey])
    }

    /// Parses the environment value without mutating process-global state.
    public static func parse(_ value: String?) throws -> Self {
        guard let value else {
            return Self(multiplier: 1)
        }
        guard let multiplier = Double(value),
              multiplier.isFinite,
              (1 ... 4).contains(multiplier)
        else {
            throw SnapshotRenderingError.invalidSettleTimeoutMultiplier(value: value)
        }
        return Self(multiplier: multiplier)
    }

    public func maximumDuration(for settle: SnapshotSettle) -> TimeInterval {
        let baseDuration = switch settle {
            case .settled, .immediate:
                2.5
            case let .settledAtLeast(minDuration):
                max(2.5, minDuration + 2.5)
        }
        return baseDuration * multiplier
    }
}
