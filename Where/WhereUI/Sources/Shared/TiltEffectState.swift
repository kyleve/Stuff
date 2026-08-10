import CoreGraphics

/// One resolved device pose shared by the card's tilt-reactive finish layers.
/// It selects the deterministic fallback before live motion is available and
/// clamps every axis before a renderer turns the pose into visual travel.
@MainActor
struct TiltEffectState: Equatable {
    let roll: Double
    let pitch: Double
    let usesStaticPose: Bool

    init(
        tilt: TiltProvider?,
        staticRoll: Double,
        staticPitch: Double,
        motionIsStatic: Bool,
    ) {
        let usesStaticPose = motionIsStatic || tilt?.hasLiveSample != true
        self.init(
            roll: usesStaticPose ? staticRoll : tilt?.roll ?? staticRoll,
            pitch: usesStaticPose ? staticPitch : tilt?.pitch ?? staticPitch,
            usesStaticPose: usesStaticPose,
        )
    }

    init(roll: Double, pitch: Double, usesStaticPose: Bool = false) {
        self.roll = Self.clamp(roll)
        self.pitch = Self.clamp(pitch)
        self.usesStaticPose = usesStaticPose
    }

    /// A normalized light vector where positive height points down the screen.
    /// `travel` lets each finish layer tune its response without changing the
    /// shared sensor or the other surfaces that consume it.
    func lightDirection(travel: Double) -> CGSize {
        CGSize(
            width: CGFloat(Self.clamp(roll * travel)),
            height: CGFloat(Self.clamp(-pitch * travel)),
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}
