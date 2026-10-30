import SnapshotKit
import SwiftUI
import WhereCore

/// The scrolling content shared by the bounded intro pager and full-content captures.
struct OnboardingIntroPage: View {
    let page: OnboardingPage
    let privacy: DiagnosticReportingConfiguration
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            VStack(spacing: stylesheet.onboarding.contentSpacing) {
                OnboardingHeader(title: page.title, detail: page.description)
                OnboardingIllustration(page: page.id, privacy: privacy)
            }
            .padding(.vertical, stylesheet.onboarding.padding)
            .frame(maxWidth: stylesheet.onboarding.maxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollEdgeEffectHidden()
    }
}

#if DEBUG
    extension OnboardingIntroPage: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            OnboardingPage.all.map { page in
                // Welcome carries the shared shell's broad matrix; other artwork
                // states retain focused text, annotation, direction, and tablet coverage.
                let configurations: [SnapshotConfiguration] = switch page.id {
                    case .welcome:
                        .fullContentScreenRepresentative
                    case .automatic, .privacy:
                        .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                            SnapshotConfiguration(device: .iPadFullContent),
                        ]
                }
                return onboardingThemeSnapshot(
                    name: String(describing: page.id),
                    configurations: configurations + [
                        SnapshotConfiguration(
                            layoutDirection: .rightToLeft,
                            device: .iPhoneFullContent,
                        ),
                    ],
                ) {
                    OnboardingIntroPage(page: page, privacy: .defaults(isDebugBuild: false))
                        .padding(.horizontal, WhereStylesheet.default.onboarding.padding)
                        .background(OnboardingBackground())
                }
            }
        }
    }

    #Preview { OnboardingIntroPage.snapshotPreviews }
#endif
