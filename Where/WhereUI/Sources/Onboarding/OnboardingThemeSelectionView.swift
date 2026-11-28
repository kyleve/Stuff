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

                    Image(systemSymbol: .square3Layers3d)
                        .font(stylesheet.typography.onboardingIcon)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    OnboardingHeading(
                        title: Text(.onboardingThemeTitle),
                        description: Text(.onboardingThemeDescription),
                    )

                    WhereThemePicker(selection: selection, onSelect: onSelect)

                    OnboardingThemeContinueButton(action: onContinue)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.vertical, stylesheet.spacing.xxxLarge)
                .frame(minHeight: geometry.size.height)
                .whereContentRoot()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct OnboardingThemeContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(.onboardingContinue)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

#if DEBUG
    private struct OnboardingThemeSelectionSnapshotRoot: View {
        @State var selection: WhereTheme

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
            // Selection is supplied and specimen artwork preserves layout. Load it
            // before final settling, which still covers publication into mounted cards.
            let cache = PreviewSupport.snapshotArtworkCache
            let configurations = [SnapshotConfiguration]
                .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                    SnapshotConfiguration(contrast: .increased, device: .iPhoneFullContent),
                    SnapshotConfiguration(device: .iPadFullContent),
                    SnapshotConfiguration(device: .iPadFullContent, snapshotType: .accessibility),
                    // Keep the wider-column wrapping and picker placement at AX5.
                    SnapshotConfiguration(dynamicType: .accessibility5, device: .iPadFullContent),
                ]
            return [
                whereSnapshot(
                    name: "Standard",
                    configurations: configurations,
                    measurementReadiness: .immediate,
                    prepareForCapture: {
                        await PreviewSupport.loadCardArtwork(for: [.california], cache: cache)
                    },
                ) {
                    OnboardingThemeSelectionSnapshotRoot(selection: .standard)
                        .environment(\.regionOutlinePathCache, cache)
                },
                whereSnapshot(
                    name: "Alternate",
                    configurations: .fullContentPhoneLightDark,
                    theme: .alternate,
                    measurementReadiness: .immediate,
                    prepareForCapture: {
                        await PreviewSupport.loadCardArtwork(for: [.california], cache: cache)
                    },
                ) {
                    OnboardingThemeSelectionSnapshotRoot(selection: .alternate)
                        .environment(\.regionOutlinePathCache, cache)
                },
            ]
        }
    }

    #Preview {
        OnboardingThemeSelectionView.snapshotPreviews
    }
#endif
