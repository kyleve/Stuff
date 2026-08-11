import SnapshotKit
import SwiftUI

/// The single folio cover shown while Where launches or prepares a new world.
///
/// The W-and-meridian seal resolves once, with a controlled ceremonial reveal;
/// there is no ambient pulse, radar, or invented progress. A launch-neutral
/// reassurance and the system activity indicator appear only after a genuinely
/// slow launch. Named work, such as preparing the demo, is identified from its
/// first frame.
struct LaunchSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot
    @MotionIsStatic private var motionIsStatic
    @Environment(\.stylesheet) private var stylesheet
    @State private var sealRevealed = false
    @State private var showCaption: Bool

    /// What, if anything, the splash says beneath the seal.
    enum Caption {
        /// Nothing at first, then a launch-neutral reassurance if launch lingers.
        case slowLaunchReassurance
        /// Named work the user is waiting on, shown immediately.
        case work(title: String, subtitle: String)
    }

    private let caption: Caption

    init(
        caption: Caption = .slowLaunchReassurance,
        previewShowsCaption: Bool = false,
    ) {
        self.caption = caption
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

    private var brand: WhereStylesheet.Palette.Brand {
        stylesheet.palette.brand
    }

    private var isSealVisible: Bool {
        motionIsStatic || sealRevealed
    }

    var body: some View {
        ZStack {
            launchCover

            VStack(spacing: stylesheet.spacing.xxLarge) {
                Text(String(localized: .launchPrivateRecord))
                    .font(.caption2.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(brand.brass)

                WhereSeal(tint: brand.brass)
                    .frame(width: stylesheet.launch.sealSize)

                VStack(spacing: stylesheet.spacing.xSmall) {
                    Text(verbatim: "WHERE")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .tracking(4)
                    Text(String(localized: .launchTimeAndPlace))
                        .font(.caption2.weight(.medium))
                        .tracking(2)
                        .foregroundStyle(brand.onMidnight.opacity(0.68))
                }
                .foregroundStyle(brand.onMidnight)
            }
            .opacity(isSealVisible ? 1 : 0)
            .scaleEffect(isSealVisible ? 1 : 0.96)

            if showCaption {
                VStack {
                    Spacer()
                    captionView
                        .padding(.bottom, stylesheet.size.launchCaptionBottomInset)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(brand.midnight)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            showCaption ? captionTitle : String(localized: .launchAccessibilityLabel),
        )
        .task {
            guard !motionIsStatic else { return }
            withAnimation(stylesheet.motion.ceremonial) {
                sealRevealed = true
            }
        }
        .task {
            guard case .slowLaunchReassurance = caption else { return }
            guard !isCapturingSnapshot else { return }
            try? await Task.sleep(for: stylesheet.launch.captionDelay)
            guard !Task.isCancelled else { return }
            if reduceMotion {
                showCaption = true
            } else {
                withAnimation(stylesheet.motion.captionFade) { showCaption = true }
            }
        }
    }

    private var launchCover: some View {
        ZStack {
            LinearGradient(
                colors: [
                    brand.midnight.mix(with: brand.mineral, by: 0.08, in: .perceptual),
                    brand.midnight,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )

            RoundedRectangle(cornerRadius: stylesheet.launch.coverCornerRadius)
                .stroke(brand.brass.opacity(0.28), lineWidth: 1)
                .padding(stylesheet.launch.coverInset)

            RoundedRectangle(cornerRadius: stylesheet.launch.coverCornerRadius - 5)
                .stroke(brand.brass.opacity(0.1), lineWidth: 0.75)
                .padding(stylesheet.launch.coverInset + 8)
        }
        .accessibilityHidden(true)
    }

    private var captionView: some View {
        VStack(spacing: stylesheet.spacing.medium) {
            SystemActivityIndicator(tint: brand.onMidnight)
            Text(captionTitle)
                .font(.headline)
            Text(captionSubtitle)
                .font(.subheadline)
                .foregroundStyle(brand.onMidnight.opacity(0.68))
        }
        .foregroundStyle(brand.onMidnight)
        .multilineTextAlignment(.center)
        .padding(.horizontal, stylesheet.spacing.xxxLarge)
    }
}

#if DEBUG
    extension LaunchSplashView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .phoneLightDark) {
                LaunchSplashView()
            }
            whereSnapshot(name: "SlowLaunchCaption", configurations: .phoneLightDark) {
                LaunchSplashView(previewShowsCaption: true)
            }
            whereSnapshot(name: "WorkCaption", configurations: .phoneLightDark) {
                LaunchSplashView(
                    caption: .work(
                        title: String(localized: .demoBuildingTitle),
                        subtitle: String(localized: .demoBuildingSubtitle),
                    ),
                )
            }
        }
    }

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
