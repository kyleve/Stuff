import Foundation

/// A bounded transform vocabulary with an explicit accessible, deterministic pose.
public struct ViewAnimationDescriptor: Codable, Hashable, Sendable {
    public var from: Pose
    public var to: Pose
    public var staticPose: Pose
    public var duration: Double
    public var delay: Double
    public var curve: Curve
    public var repetition: Repetition

    public init(
        from: Pose,
        to: Pose,
        staticPose: Pose,
        duration: Double,
        delay: Double,
        curve: Curve,
        repetition: Repetition,
    ) {
        self.from = from
        self.to = to
        self.staticPose = staticPose
        self.duration = duration
        self.delay = delay
        self.curve = curve
        self.repetition = repetition
    }

    public struct Pose: Codable, Hashable, Sendable {
        public var opacity: Double
        public var offsetX: Double
        public var offsetY: Double
        public var scaleX: Double
        public var scaleY: Double
        public var rotation: Double

        public init(
            opacity: Double,
            offsetX: Double,
            offsetY: Double,
            scaleX: Double,
            scaleY: Double,
            rotation: Double,
        ) {
            self.opacity = opacity
            self.offsetX = offsetX
            self.offsetY = offsetY
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.rotation = rotation
        }

        public static let identity = Self(
            opacity: 1,
            offsetX: 0,
            offsetY: 0,
            scaleX: 1,
            scaleY: 1,
            rotation: 0,
        )
    }

    public enum Curve: String, Codable, Hashable, Sendable {
        case linear, easeIn, easeOut, easeInOut
    }

    public enum Repetition: Codable, Hashable, Sendable {
        case once
        case count(Int, autoreverses: Bool)
        case forever(autoreverses: Bool)
    }
}
