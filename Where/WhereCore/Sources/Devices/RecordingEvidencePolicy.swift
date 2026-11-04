import Foundation

/// Initial conservative assessment policy. This version identifies pure assessment only;
/// defining it does not initialize or advance a dataset's required major.
public enum RecordingEvidencePolicy {
    public static let version = DataSemanticsVersion(major: 1, minor: 0, patch: 0)

    /// Coarser positions remain raw evidence but cannot establish movement or stationary dwell.
    public static let maximumAccuracyMeters = 250.0
    /// Dense callbacks do not independently corroborate movement or stationary dwell.
    public static let minimumAnchorInterval: TimeInterval = 60
    /// Do not connect observations across longer recording gaps.
    public static let maximumObservationGap: TimeInterval = 30 * 60
    /// Activity uses at most this much adjacent evidence on either side of an assessed period.
    public static let contextPadding: TimeInterval = 30 * 60
    /// An isolated point remains assessable without extending its position across a gap.
    public static let pointSupport: TimeInterval = 1
    /// Three independent positions and ten minutes are required for movement evidence.
    public static let minimumObservationCount = 3
    public static let minimumMovingDuration: TimeInterval = 10 * 60
    /// Lower-bound displacement after both endpoint accuracy radii must exceed one kilometer.
    public static let minimumMovingDisplacementMeters = 1000.0
    /// At least two independent, accuracy-adjusted advances corroborate movement. One distant
    /// endpoint after repeated home fixes cannot select a device automatically.
    public static let minimumMovingLegs = 2
    public static let minimumMovingLegDisplacementMeters = 250.0
    /// Reject jumps faster than the existing flight policy's plausible upper speed.
    public static let maximumPlausibleSpeedMetersPerSecond = 1500.0 / 3.6
    /// A moving track must make net progress rather than oscillate around one position.
    public static let minimumProgressRatio = 0.65
    /// Positive stationary evidence spans twenty minutes with independently separated fixes.
    public static let minimumStationaryDuration: TimeInterval = 20 * 60
    public static let stationaryRadiusMeters = 150.0
    /// The user's place corroborates stationary evidence within this radius plus measurement error.
    public static let placeRadiusMeters = 150.0
    /// Unresolved geography alone is not a conflict. Separate uncertainty circles must exceed this.
    public static let divergentTrackDistanceMeters = 2000.0
}
