import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// First-run choice between Where's two presentation identities.
struct OnboardingThemeSelectionView: View {
    let selection: WhereTheme
    let onSelect: (WhereTheme) -> Void
    let onContinue: () -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: stylesheet.spacing.xxxLarge) {
                    Spacer(minLength: 0)

                    OnboardingHeader(
                        title: String(localized: .onboardingThemeTitle),
                        detail: String(localized: .onboardingThemeDescription),
                    )

                    WhereThemePicker(selection: selection, onSelect: onSelect)

                    OnboardingAction(title: .onboardingContinue, action: onContinue)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.vertical, stylesheet.spacing.xxxLarge)
                .frame(maxWidth: stylesheet.onboarding.maxWidth, minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectHidden()
        }
    }
}

#if DEBUG
    private struct OnboardingThemeSelectionSnapshotRoot: View {
        @State var selection: WhereTheme
        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            ZStack {
                OnboardingBackground()

                OnboardingThemeSelectionView(
                    selection: selection,
                    onSelect: { selection = $0 },
                    onContinue: {},
                )
            }
        }
    }

    extension OnboardingThemeSelectionView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let configurations = [SnapshotConfiguration].fullContentScreenDefaults + [
                SnapshotConfiguration(layoutDirection: .rightToLeft, device: .iPhoneFullContent),
                SnapshotConfiguration(layoutDirection: .rightToLeft, device: .iPadFullContent),
            ]
            return [
                onboardingSnapshot(name: "Standard", configurations: configurations) {
                    OnboardingThemeSelectionSnapshotRoot(selection: .standard)
                },
                onboardingSnapshot(
                    name: "Alternate",
                    configurations: .fullContentPhoneLightDark,
                    theme: .alternate,
                ) {
                    OnboardingThemeSelectionSnapshotRoot(selection: .alternate)
                },
            ]
        }
    }

    #Preview {
        OnboardingThemeSelectionView.snapshotPreviews
    }
#endif
