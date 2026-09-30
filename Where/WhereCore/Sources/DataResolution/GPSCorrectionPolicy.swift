import Foundation

/// Conservative inference limits for GPS reviews. These values express product
/// policy. They do not establish arrival without supporting observations.
enum GPSCorrectionPolicy {
    /// Reject uncertainty circles too large to support motion or boundary cleanup.
    static let maximumHorizontalAccuracyMeters = 250.0

    enum Trajectory {
        /// Dense callbacks cannot serve as independent motion baselines.
        static let minimumAnchorInterval: TimeInterval = 60
        /// Longer gaps leave travel between the endpoints unknown.
        static let maximumLegInterval: TimeInterval = 2 * 60 * 60
        /// The accuracy-adjusted lower speed of each cruise leg must meet this limit.
        static let minimumCruiseSpeedKMH = 450.0
        static let maximumPlausibleSpeedKMH = 1500.0
        static let minimumCruiseDuration: TimeInterval = 3 * 60
        /// Reject fast movement that mostly loops near its starting point.
        static let minimumDirectProgressRatio = 0.75
        static let minimumTransitionSpeedKMH = 150.0
        /// Bound the takeoff and approach evidence attached to a cruise core.
        static let maximumTransitionDuration: TimeInterval = 30 * 60
        static let groundRadiusMeters = 2000.0
        static let maximumGroundSpeedKMH = 50.0
        /// Require observed ground dwell, rather than a single slow callback.
        static let minimumGroundDuration: TimeInterval = 10 * 60
        static let maximumGroundWindow: TimeInterval = 30 * 60
        static let maximumGroundGap: TimeInterval = 10 * 60
        static let sameObservationInterval: TimeInterval = 1
    }

    enum Boundary {
        /// Near-simultaneous callbacks do not independently bracket a drift sample.
        static let neighborExclusionInterval: TimeInterval = 1
        /// Both neighbors must describe a short, local visit near the same boundary.
        /// A longer gap can hide real travel that must remain uncorrected.
        static let maximumNeighborInterval: TimeInterval = 10 * 60
        static let maximumLocalSpeedKMH = 150.0
    }

    enum Review {
        /// Include adjacent-day evidence when a sample needs neighbors across midnight.
        static let contextPaddingInterval: TimeInterval = 24 * 60 * 60
    }

    enum Presentation {
        /// Silence makes a live notice stale. It never proves that a flight landed.
        static let liveFlightFreshnessInterval: TimeInterval = 30 * 60
        static let liveNoticeRetentionInterval: TimeInterval = 24 * 60 * 60
    }

    /// One meter per second is 3.6 kilometers per hour: 3,600 seconds / 1,000 meters.
    static func kilometersPerHour(fromMetersPerSecond speed: Double) -> Double {
        speed * 3.6
    }
}
