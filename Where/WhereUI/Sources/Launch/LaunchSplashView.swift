import SnapshotKit
import SwiftUI

/// The Where launch screen shown for the whole launch: the user's selected app
/// icon, gently pulsing on an adaptive backdrop with a "radar ping" sonar sweep
/// behind it.
///
/// The backdrop follows the system light/dark mode (an adaptive
/// `systemBackground` with a subtle vignette), and the icon resolves its
/// matching light/dark preview art from the asset catalog via
/// `@Environment(\.colorScheme)`, so the splash reads correctly in either
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
    // Two distinct questions, deliberately not merged:
    // • `motionIsStatic` (Reduce Motion *or* capture) gates never-settling
    //   motion — the pulse — which must freeze in both cases.
    // • `isCapturingSnapshot` alone gates the wall-clock caption timer below:
    //   Reduce Motion users still get the caption (just without the fade), so
    //   the timer can't key off `motionIsStatic` — only a capture skips it.
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot
    @MotionIsStatic private var motionIsStatic
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.primaryAppIconName) private var primaryAppIconName
    @State private var pulsing = false
    @State private var showCaption: Bool

    private var splash: WhereStylesheet.Palette.Splash {
        stylesheet.palette.splash
    }

    /// What, if anything, the splash says beneath the icon.
    enum Caption {
        /// The launch's own: nothing at first, and a launch-neutral
        /// reassurance fading in only once the launch has run long.
        case slowLaunchReassurance
        /// Named work the user is waiting on, shown immediately — for a
        /// deliberate wait (building the demo's data) rather than a launch
        /// that happens to be slow. Nothing to fade in: the wait is expected,
        /// and saying so late would read as something having gone wrong.
        case work(title: String, subtitle: String)
    }

    private let caption: Caption

    /// Preview/test seam: when `nil`, the live selected icon is resolved from
    /// `UIApplication.shared.alternateIconName` in `body` (on the main actor).
    private let injectedPreviewImageName: String?

    /// - Parameters:
    ///   - caption: what to say beneath the icon. Defaults to the launch's own
    ///     slow-launch reassurance.
    ///   - previewShowsCaption: preview/test seam to render the slow-launch
    ///     caption immediately instead of waiting out the caption delay.
    ///     Ignored for `.work`, which is shown from the first frame anyway.
    init(
        caption: Caption = .slowLaunchReassurance,
        previewImageName: String? = nil,
        previewShowsCaption: Bool = false,
    ) {
        self.caption = caption
        injectedPreviewImageName = previewImageName
        switch caption {
            case .slowLaunchReassurance:
                _showCaption = State(initialValue: previewShowsCaption)
            case .work:
                _showCaption = State(initialValue: true)
        }
    }

    private var captionTitle: String {
        switch caption {
            case .slowLaunchReassurance: String(localized: .launchCaptionTitle)
            case let .work(title, _): title
        }
    }

    private var captionSubtitle: String {
        switch caption {
            case .slowLaunchReassurance: String(localized: .launchCaptionSubtitle)
            case let .work(_, subtitle): subtitle
        }
    }

    var body: some View {
        let imageName = injectedPreviewImageName ?? AppIconCatalog.liveSelectedPreviewImageName(
            primaryAppIconName: primaryAppIconName,
        )
        ZStack {
            LaunchSplashBackground(palette: splash)
            RadarPingBackground(tint: splash.iconGlow)
            LaunchSplashIcon(
                name: imageName,
                size: stylesheet.size.launchIcon,
                glow: splash.iconGlow,
                pulsing: $pulsing,
                motionIsStatic: motionIsStatic,
            )

            if showCaption {
                LaunchSplashCaptionPlacement(
                    title: captionTitle,
                    subtitle: captionSubtitle,
                    bottomInset: stylesheet.size.launchCaptionBottomInset,
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(splash.background)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            showCaption ? captionTitle : String(localized: .launchAccessibilityLabel),
        )
        .task {
            // A `.work` caption is already showing and never changes; only the
            // launch's own reassurance is on a timer.
            guard case .slowLaunchReassurance = caption else { return }
            // Under snapshot capture the caption must be deterministic — shown
            // iff the explicit `previewShowsCaption` seam says so — never a race
            // between this wall-clock timer and the capture's settle loop. Both
            // caption states have their own snapshot cases, so the timer adds
            // nothing there. (Reduce Motion alone doesn't suppress it: those
            // users still get the caption, just without the fade.)
            guard !isCapturingSnapshot else { return }
            try? await Task.sleep(for: stylesheet.launch.captionDelay)
            guard !Task.isCancelled else { return }
            withAnimation(stylesheet.launch.captionAnimation) { showCaption = true }
        }
    }
}

private struct LaunchSplashCaptionPlacement: View {
    let title: String
    let subtitle: String
    let bottomInset: CGFloat

    var body: some View {
        VStack {
            Spacer()
            LaunchSplashCaption(title: title, subtitle: subtitle)
                .padding(.bottom, bottomInset)
        }
        .transition(.opacity)
    }
}

/// The text below the icon — the slow-launch reassurance, or the named
/// work being waited on. The radar and pulsing icon already say "working",
/// so this is just text, pinned light since the backdrop is always dark.
private struct LaunchSplashCaption: View {
    let title: String
    let subtitle: String
    @Environment(\.stylesheet.spacing) private var spacing

    var body: some View {
        VStack(spacing: spacing.small) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, spacing.xxxLarge)
    }
}

/// A subtle vignette — a touch lighter at the center, falling to black — so
/// the icon and rings have some depth instead of floating on flat black.
private struct LaunchSplashBackground: View {
    let palette: WhereStylesheet.Palette.Splash

    var body: some View {
        RadialGradient(
            colors: [palette.vignetteCenter, palette.vignetteEdge],
            center: .center,
            startRadius: 0,
            endRadius: 520,
        )
        .ignoresSafeArea()
    }
}

private struct LaunchSplashIcon: View {
    let name: String
    let size: CGFloat
    let glow: Color
    @Binding var pulsing: Bool
    let motionIsStatic: Bool

    var body: some View {
        let cornerRadius = size * AppIconImage.cornerRadiusRatio
        AppIconImage(name: name, size: size, bordered: false)
            .scaleEffect(pulsing ? 1.1 : 1)
            .background {
                LaunchSplashGlow(radius: cornerRadius, glow: glow, pulsing: pulsing)
            }
            .onAppear {
                guard !motionIsStatic else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

private struct LaunchSplashGlow: View {
    let radius: CGFloat
    let glow: Color
    let pulsing: Bool

    var body: some View {
        // A soft brand-tinted glow that breathes with the pulse.
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(glow)
            .blur(radius: 44)
            .opacity(pulsing ? 0.55 : 0.3)
            .scaleEffect(pulsing ? 1.3 : 0.85)
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
            whereSnapshot(name: "WorkCaption", configurations: .phoneLightDark) {
                LaunchSplashView(
                    caption: .work(
                        title: String(localized: .demoBuildingTitle),
                        subtitle: String(localized: .demoBuildingSubtitle),
                    ),
                    previewImageName: "AppIconClassic",
                )
            }
        }
    }

    // The cutsheet covers the color-mode variation (which changes the rendered
    // icon art) and each caption: absent, the slow-launch reassurance, and
    // named work (demo mode's interstitial, shown from the first frame).
    // Reduce Motion isn't shown: it's a read-only environment value that can't
    // be set via `.environment`, and at rest the animated splash looks
    // identical to its motion-pinned frame.
    #Preview {
        LaunchSplashView.snapshotPreviews
    }
#endif

#if DEBUG
    extension LaunchSplashView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            LaunchSplashView.self,
            title: "Launch",
            navigationContainer: .none,
        )
    }
#endif
