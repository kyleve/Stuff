import SnapshotKit
import SwiftUI

/// The Where launch screen shown for the whole launch: the user's selected app
/// icon, gently pulsing on a dark backdrop with a "radar ping" sonar sweep
/// behind it.
///
/// The icon respects the system color mode (the asset catalog resolves the
/// light/dark preview art from `@Environment(\.colorScheme)`) while always
/// sitting on a dark background, so the brand mark reads the same in either
/// appearance. When the runner reaches `.ready`, `RootView` removes this view
/// with a scale-up-and-fade transition that reveals the main UI — that motion
/// lives at the container seam, not here.
///
/// This one view spans every launch phase. The container keeps it on screen
/// from `.launching` through all the silent steps (it's only displaced by a
/// genuinely different surface — onboarding — or the final reveal), so rather
/// than swapping in a separate "migrating" screen, the splash simply fades a
/// reassurance caption in after it's lingered a beat. There's no second view to
/// reconcile and no remount, so the pulse and radar run uninterrupted.
///
/// The caption's copy is deliberately launch-neutral ("Getting things ready…")
/// — a slow launch may be a schema migration, a fresh install's very first
/// store creation (which routinely outlives the caption delay), or plain
/// slowness, and the splash can't tell which, so it never claims a specific
/// cause.
///
/// Honors Reduce Motion: the pulse and the sweeping rings are pinned to a
/// static frame, and the caption appears without a fade. Snapshot captures
/// likewise skip the pulse (see ``MotionIsStatic``), freeze the rings at a
/// canonical phase, and never start the slow-launch timer — whether the
/// caption is visible under capture is decided solely by the explicit
/// `previewShowsCaption` seam, never by how long the settle loop happens to
/// take — so the never-settling motion and the wall-clock reveal both render
/// deterministically.
struct LaunchSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Two distinct questions, deliberately not merged:
    // • `motionIsStatic` (Reduce Motion *or* capture) gates never-settling
    //   motion — the pulse — which must freeze in both cases.
    // • `isCapturingSnapshot` alone gates the wall-clock caption timer below:
    //   Reduce Motion users still get the caption (just without the fade), so
    //   the timer can't key off `motionIsStatic` — only a capture skips it.
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot
    @MotionIsStatic private var motionIsStatic
    @Environment(\.stylesheet) private var stylesheet
    @State private var pulsing = false
    @State private var showCaption: Bool

    private var splash: WhereStylesheet.Palette.Splash {
        stylesheet.palette.splash
    }

    /// How long the splash must linger before the "taking a moment" caption
    /// fades in, so a fast launch never flashes it.
    private static let captionDelay = Duration.milliseconds(500)

    /// Preview/test seam: when `nil`, the live selected icon is resolved from
    /// `UIApplication.shared.alternateIconName` in `body` (on the main actor).
    private let injectedPreviewImageName: String?

    /// - Parameter previewShowsCaption: preview/test seam to render the slow-
    ///   launch caption immediately instead of waiting out `captionDelay`.
    init(previewImageName: String? = nil, previewShowsCaption: Bool = false) {
        injectedPreviewImageName = previewImageName
        _showCaption = State(initialValue: previewShowsCaption)
    }

    var body: some View {
        let imageName = injectedPreviewImageName ?? AppIconCatalog.liveSelectedPreviewImageName()
        ZStack {
            background
            RadarPingBackground(tint: splash.iconGlow)
            icon(named: imageName)

            if showCaption {
                VStack {
                    Spacer()
                    caption
                        .padding(.bottom, stylesheet.size.launchCaptionBottomInset)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(splash.background)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            showCaption ? Strings.launchCaptionTitle : Strings.launchAccessibilityLabel,
        )
        .task {
            // Under snapshot capture the caption must be deterministic — shown
            // iff the explicit `previewShowsCaption` seam says so — never a race
            // between this wall-clock timer and the capture's settle loop. Both
            // caption states have their own snapshot cases, so the timer adds
            // nothing there. (Reduce Motion alone doesn't suppress it: those
            // users still get the caption, just without the fade.)
            guard !isCapturingSnapshot else { return }
            try? await Task.sleep(for: Self.captionDelay)
            guard !Task.isCancelled else { return }
            if reduceMotion {
                showCaption = true
            } else {
                withAnimation(stylesheet.motion.captionFade) { showCaption = true }
            }
        }
    }

    /// The reassurance shown below the icon once a launch runs long: the radar
    /// and pulsing icon already say "working", so this is just text, pinned
    /// light since the backdrop is always dark.
    private var caption: some View {
        VStack(spacing: stylesheet.spacing.small) {
            Text(Strings.launchCaptionTitle)
                .font(.headline)
            Text(Strings.launchCaptionSubtitle)
                .font(.subheadline)
                .foregroundStyle(splash.captionSecondary)
        }
        .foregroundStyle(splash.caption)
        .multilineTextAlignment(.center)
        .padding(.horizontal, stylesheet.spacing.xxxLarge)
    }

    /// A subtle vignette — a touch lighter at the center, falling to black — so
    /// the icon and rings have some depth instead of floating on flat black.
    private var background: some View {
        RadialGradient(
            colors: [splash.vignetteCenter, splash.vignetteEdge],
            center: .center,
            startRadius: 0,
            endRadius: 520,
        )
        .ignoresSafeArea()
    }

    private func icon(named name: String) -> some View {
        let cornerRadius = stylesheet.size.launchIcon * AppIconImage.cornerRadiusRatio
        return AppIconImage(name: name, size: stylesheet.size.launchIcon, bordered: false)
            .scaleEffect(pulsing ? 1.1 : 1)
            .background {
                // A soft brand-tinted glow that breathes with the pulse.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(splash.iconGlow)
                    .blur(radius: 44)
                    .opacity(pulsing ? 0.55 : 0.3)
                    .scaleEffect(pulsing ? 1.3 : 0.85)
            }
            .onAppear {
                guard !motionIsStatic else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

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
private struct RadarPingBackground: View {
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
    extension LaunchSplashView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .phoneLightDark) {
                LaunchSplashView(previewImageName: "AppIconClassic")
            }
            whereSnapshot(name: "SlowLaunchCaption", configurations: .phoneLightDark) {
                LaunchSplashView(previewImageName: "AppIconClassic", previewShowsCaption: true)
            }
        }
    }

    // The cutsheet covers the color-mode variation (which changes the rendered
    // icon art) and the slow-launch caption. Reduce Motion isn't shown: it's a
    // read-only environment value that can't be set via `.environment`, and at
    // rest the animated splash looks identical to its motion-pinned frame.
    #Preview {
        LaunchSplashView.snapshotPreviews
    }
#endif
