import SnapshotKit
import SwiftUI

/// Concentric "sonar" rings that expand outward from the center and fade as
/// they grow, staggered so a new ring sets off before the previous one
/// dissolves. Driven by a `TimelineView` clock and drawn in a `Canvas`, so
/// there's no per-ring view state to keep in sync; pausing the clock (static
/// motion — see ``MotionIsStatic``) renders a single static frame of
/// staggered rings.
///
/// Snapshot captures additionally pin the phase to a constant — a paused
/// `TimelineView` still reports the wall-clock pause time, which would leak
/// run-dependent ring radii/opacities into the image.
struct RadarPingBackground: View {
    @MotionIsStatic private var motionIsStatic
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    var tint: Color = .white

    private let ringCount = 4
    private let period: Double = 3.6
    private let minRadius: CGFloat = 56
    private let maxOpacity: Double = 0.32

    var body: some View {
        // `motionIsStatic` pauses the clock (no ticks under Reduce Motion or
        // capture); `isCapturingSnapshot` additionally pins the phase, since a
        // paused `TimelineView` still reports its wall-clock pause instant —
        // which would leak run-dependent ring radii/opacities into the capture.
        TimelineView(.animation(paused: motionIsStatic)) { timeline in
            Canvas { context, size in
                let now = timeline.radarPhaseClock(capturingSnapshot: isCapturingSnapshot)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = max(size.width, size.height) * 0.75
                for index in 0 ..< ringCount {
                    let phase = ringPhase(now: now, index: index)
                    let radius = minRadius + (maxRadius - minRadius) * phase
                    let opacity = (1 - phase) * maxOpacity
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2,
                    )
                    let circle = Circle().path(in: rect)
                    context.fill(circle, with: .color(tint.opacity(opacity * 0.12)))
                    context.stroke(circle, with: .color(tint.opacity(opacity)), lineWidth: 1.5)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Each ring's progress through one expand-and-fade cycle, in `0..<1`,
    /// offset by its index so the rings are evenly spaced around the loop.
    private func ringPhase(now: Double, index: Int) -> Double {
        let raw = now / period + Double(index) / Double(ringCount)
        return raw - raw.rounded(.down)
    }
}

extension TimelineViewDefaultContext {
    /// The radar rings' animation-phase clock: the wall-clock time normally, or
    /// a pinned constant under snapshot capture so the rings freeze at a
    /// deterministic phase (see `RadarPingBackground`).
    fileprivate func radarPhaseClock(capturingSnapshot: Bool) -> Double {
        capturingSnapshot ? 0 : date.timeIntervalSinceReferenceDate
    }
}

#if DEBUG
    #Preview("Radar sweep") {
        LaunchSplashView(previewImageName: "AppIconClassic").whereBroadwayRoot()
    }
#endif
