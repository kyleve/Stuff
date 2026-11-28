import SwiftUI

/// A centered, full-area "working" state: the shared `AppIconActivityIndicator`
/// (the user's selected app icon breathing gently) above a caption. The single
/// loading treatment for whole-view waits — a first data load, an in-progress
/// scan, a summary generating — so they share one look and one accessibility
/// shape instead of each rebuilding a spinner-plus-label.
struct AppIconLoadingView: View {
    @Environment(\.primaryAppIconName) private var primaryAppIconName

    let caption: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.spacing.xxLarge) {
            AppIconActivityIndicator(primaryAppIconName: primaryAppIconName)
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
    }
}

#if DEBUG
    #Preview {
        AppIconLoadingView(caption: "Charting your year…")
    }
#endif

/// A calm "working" indicator that renders the user's selected app icon with a
/// gentle breathing pulse and a soft brand-tinted glow. A quieter cousin of the
/// launch splash's pulsing hero (`LaunchSplashView`): smaller, with a shallower
/// scale pulse, a softer glow, and none of the radar sweep — tuned for an
/// in-app wait rather than a full-screen launch.
///
/// Honors Reduce Motion: the pulse pins to a static frame. Snapshot captures
/// pin it the same way (see ``MotionIsStatic``).
struct AppIconActivityIndicator: View {
    @MotionIsStatic private var motionIsStatic
    @State private var pulsing = false

    /// Edge length of the rendered icon.
    let size: CGFloat

    /// Resolved once at construction — the live selected icon (matching the
    /// launch splash) or an injected name for previews/tests — so a re-render,
    /// e.g. the pulse animation toggling state, never re-reads and decodes the
    /// icon manifest.
    private let imageName: String

    @MainActor
    init(
        primaryAppIconName: String,
        size: CGFloat = 88,
        previewImageName: String? = nil,
    ) {
        self.size = size
        imageName = previewImageName ?? AppIconCatalog.liveSelectedPreviewImageName(
            primaryAppIconName: primaryAppIconName,
        )
    }

    var body: some View {
        let cornerRadius = size * AppIconImage.cornerRadiusRatio
        AppIconImage(name: imageName, size: size, bordered: false)
            .scaleEffect(pulsing ? 1.06 : 1)
            .background {
                // A soft brand-tinted glow that breathes with the pulse — the
                // splash's glow, dialed back (softer blur, lower peak opacity,
                // a shallower scale swing) so it reads as a quiet heartbeat.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor)
                    .blur(radius: 28)
                    .opacity(pulsing ? 0.32 : 0.16)
                    .scaleEffect(pulsing ? 1.18 : 0.9)
            }
            .onAppear {
                guard !motionIsStatic else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Light") {
        AppIconActivityIndicator(
            primaryAppIconName: "AppIcon",
            previewImageName: "AppIconClassic",
        )
        .environment(\.colorScheme, .light)
    }

    #Preview("Dark") {
        AppIconActivityIndicator(
            primaryAppIconName: "AppIcon",
            previewImageName: "AppIconClassic",
        )
        .environment(\.colorScheme, .dark)
    }
#endif
