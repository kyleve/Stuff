import SwiftUI
import UIKit

/// The Where launch screen shown while the `LifecycleRunner` walks its steps:
/// the user's selected app icon, gently pulsing on a dark backdrop with a
/// "radar ping" sonar sweep behind it.
///
/// The icon respects the system color mode (the asset catalog resolves the
/// light/dark preview art from `@Environment(\.colorScheme)`) while always
/// sitting on a dark background, so the brand mark reads the same in either
/// appearance. When the runner reaches `.ready`, `RootView` removes this view
/// with a scale-up-and-fade transition that reveals the main UI — that motion
/// lives at the container seam, not here.
///
/// Honors Reduce Motion: the pulse and the sweeping rings are pinned to a
/// static frame so the screen is calm for motion-sensitive users.
struct LaunchSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    /// Preview/test seam: when `nil`, the live selected icon is resolved from
    /// `UIApplication.shared.alternateIconName` in `body` (on the main actor).
    private let injectedPreviewImageName: String?

    init(previewImageName: String? = nil) {
        injectedPreviewImageName = previewImageName
    }

    var body: some View {
        let imageName = injectedPreviewImageName ?? Self.liveSelectedPreviewImageName()
        ZStack {
            background
            RadarPingBackground(animated: !reduceMotion, tint: .accentColor)
            icon(named: imageName)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.launchAccessibilityLabel)
    }

    /// A subtle vignette — a touch lighter at the center, falling to black — so
    /// the icon and rings have some depth instead of floating on flat black.
    private var background: some View {
        RadialGradient(
            colors: [Color(white: 0.16), .black],
            center: .center,
            startRadius: 0,
            endRadius: 520,
        )
        .ignoresSafeArea()
    }

    private func icon(named name: String) -> some View {
        let cornerRadius = UIConstants.Size.launchIcon * 0.2237
        return AppIconImage(name: name, size: UIConstants.Size.launchIcon, bordered: false)
            .scaleEffect(pulsing ? 1.1 : 1)
            .background {
                // A soft brand-tinted glow that breathes with the pulse.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor)
                    .blur(radius: 44)
                    .opacity(pulsing ? 0.55 : 0.3)
                    .scaleEffect(pulsing ? 1.3 : 0.85)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }

    /// Resolve the preview-catalog image name of the currently selected icon,
    /// matching the live alternate icon against the manifest the same way the
    /// picker does, and falling back to the bundled "Classic" art.
    @MainActor private static func liveSelectedPreviewImageName() -> String {
        let options = (try? AppIconCatalog.load()) ?? []
        let selected = AppIconCatalog.selectedOption(
            in: options,
            current: UIApplication.shared.alternateIconName,
        )
        return selected?.previewImageName ?? "AppIconClassic"
    }
}

/// Concentric "sonar" rings that expand outward from the center and fade as
/// they grow, staggered so a new ring sets off before the previous one
/// dissolves. Driven by a `TimelineView` clock and drawn in a `Canvas`, so
/// there's no per-ring view state to keep in sync; pausing the clock (Reduce
/// Motion) renders a single static frame of staggered rings.
private struct RadarPingBackground: View {
    let animated: Bool
    var tint: Color = .white

    private let ringCount = 4
    private let period: Double = 3.6
    private let minRadius: CGFloat = 56
    private let maxOpacity: Double = 0.32

    var body: some View {
        TimelineView(.animation(paused: !animated)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
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

#if DEBUG
    // `accessibilityReduceMotion` is a read-only environment value, so the
    // motion-pinned variant can't be previewed via `.environment`; at rest the
    // animated splash looks identical to it anyway. These cover the color-mode
    // variation, which is what changes the rendered icon art.
    #Preview("Light") {
        LaunchSplashView(previewImageName: "AppIconClassic")
            .environment(\.colorScheme, .light)
    }

    #Preview("Dark") {
        LaunchSplashView(previewImageName: "AppIconClassic")
            .environment(\.colorScheme, .dark)
    }
#endif
