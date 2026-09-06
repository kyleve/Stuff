import Foundation

/// The accepted observer location state shown by the controller.
public enum LocationHealth: Equatable, Sendable {
    case missing
    case locating
    case offeredBest(
        accuracyMeters: Double,
        observedAt: Date,
        hasStaleConfirmedLocation: Bool,
    )
    case confirmed(accuracyMeters: Double, acceptedAt: Date)
    case stale(accuracyMeters: Double, acceptedAt: Date)
    case failed
}
