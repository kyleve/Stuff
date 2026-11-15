import BroadwayUI
import SwiftUI

/// Resolves the preview surface and geometry inside its selected appearance scope.
struct AppIconPreviewPanel: View {
    let option: AppIconOption
    let containerSize: CGSize
    let previewMode: ColorScheme
    let appearanceToggles: Int
    let canApply: Bool
    let toggleAppearance: () -> Void
    let apply: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    private var appIcon: WhereStylesheet.AppIconStyle {
        stylesheet.appIcon
    }

    var body: some View {
        let iconSize = AppIconLayout.previewIconSize(containerSize: containerSize, style: appIcon)
        VStack(spacing: appIcon.panel.spacing) {
            Capsule()
                .fill(.secondary.opacity(appIcon.panel.grabberOpacity))
                .frame(
                    width: appIcon.panel.grabberSize.width,
                    height: appIcon.panel.grabberSize.height,
                )
                .padding(.top, appIcon.panel.grabberTopPadding)

            Button {
                toggleAppearance()
            } label: {
                previewIcon(size: iconSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.displayName)
            .accessibilityValue(
                previewMode == .dark
                    ? String(localized: .appIconAppearanceDark)
                    : String(localized: .appIconAppearanceLight),
            )
            .accessibilityHint(String(localized: .appIconAppearanceHint))

            VStack(spacing: appIcon.panel.textSpacing) {
                Text(option.displayName)
                    .font(.title3.weight(.semibold))
                Text(String(localized: .appIconAppearanceHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                apply()
            } label: {
                Text(String(localized: .appIconSet))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canApply)
        }
        .padding(.horizontal, appIcon.panel.horizontalPadding)
        .padding(.bottom, appIcon.panel.bottomPadding)
        .frame(maxWidth: .infinity)
        // The preview can invert the surrounding sheet's appearance.
        .foregroundStyle(Color(uiColor: .label))
        .environment(\.whereThemeSecondaryInk, nil)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: appIcon.panel.cornerRadius,
                topTrailingRadius: appIcon.panel.cornerRadius,
                style: .continuous,
            )
            .fill(appIcon.panel.background)
            .shadow(
                color: appIcon.panel.shadowColor,
                radius: appIcon.panel.shadowRadius,
                y: appIcon.panel.shadowOffsetY,
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The tappable preview icon. Tapping toggles light/dark, which crossfades
    /// the art and background while this plays a quick scale-down-then-bounce.
    /// Keyed off `appearanceToggles` so the bounce only fires on a real tap, not
    /// when the panel first opens.
    private func previewIcon(size: CGFloat) -> some View {
        AppIconImage(name: option.previewImageName, size: size)
            .keyframeAnimator(initialValue: 1.0, trigger: appearanceToggles) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.82, duration: 0.12)
                    SpringKeyframe(1.0, duration: 0.42, spring: .bouncy)
                }
            }
    }
}

#if DEBUG
    #Preview {
        if let option = AppIconCatalog.loadedOptions().first {
            AppIconPreviewPanel(
                option: option,
                containerSize: CGSize(width: 402, height: 874),
                previewMode: .dark,
                appearanceToggles: 0,
                canApply: true,
                toggleAppearance: {},
                apply: {},
            )
            .environment(\.colorScheme, .dark)
            .bMode(.dark)
            .whereBroadwayRoot()
        }
    }
#endif
