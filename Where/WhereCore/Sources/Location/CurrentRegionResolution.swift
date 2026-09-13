import RegionKit

/// The confidence-gated result of resolving the device's current tracked region.
public enum CurrentRegionResolution: Sendable, Equatable {
    /// Why a live fix did not produce a confident tracked-region decision.
    public enum UnavailableReason: Sendable, Equatable {
        case recordingInactive
        case location(CurrentLocationResult.UnavailableReason)
        case invalidFix
        case staleFix
        case excessiveUncertainty
        case boundaryUncertainty
        case outsideTrackedRegions
    }

    case resolved(Region)
    case unavailable(UnavailableReason)
}
