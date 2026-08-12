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

                    Image(systemName: "square.3.layers.3d")
                        .font(stylesheet.typography.onboardingIcon)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    VStack(spacing: stylesheet.spacing.large) {
                        Text(.onboardingThemeTitle)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(.onboardingThemeDescription)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    WhereThemePicker(selection: selection, onSelect: onSelect)

                    Button(action: onContinue) {
                        Text(.onboardingContinue)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.vertical, stylesheet.spacing.xxxLarge)
                .frame(maxWidth: 720, minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

#if DEBUG
    private struct OnboardingThemeSelectionSnapshotRoot: View {
        @State var selection: WhereTheme
        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        stylesheet.palette.onboarding.backgroundTop,
                        stylesheet.palette.onboarding.backgroundBottom,
                    ],
                    startPoint: .top,
                    endPoint: .bottom,
                )
                .ignoresSafeArea()

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
            let configurations = [SnapshotConfiguration].screenDefaults + [
                SnapshotConfiguration(layoutDirection: .rightToLeft, device: .iPhone),
                SnapshotConfiguration(layoutDirection: .rightToLeft, device: .iPad),
            ]
            return [
                whereSnapshot(name: "Standard", configurations: configurations) {
                    OnboardingThemeSelectionSnapshotRoot(selection: .standard)
                },
                whereSnapshot(name: "Alternate", configurations: configurations) {
                    OnboardingThemeSelectionSnapshotRoot(selection: .alternate)
                },
            ]
        }
    }

    #Preview {
        OnboardingThemeSelectionView.snapshotPreviews
    }
#endif
