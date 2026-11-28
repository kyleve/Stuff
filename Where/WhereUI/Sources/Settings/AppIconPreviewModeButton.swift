import BroadwayCore
import SwiftUI

/// The tappable preview icon. Tapping toggles light/dark, which crossfades
/// the art and background while this plays a quick scale-down-then-bounce.
/// Keyed off `appearanceToggleTrigger` so the bounce only fires on a real tap, not
/// when the panel first opens.
struct AppIconPreviewModeButton: View {
    let option: AppIconOption
    let iconSize: CGFloat
    let previewMode: ColorScheme
    let appearanceToggleTrigger: EventTrigger
    let toggleAppearance: () -> Void

    var body: some View {
        Button {
            toggleAppearance()
        } label: {
            AppIconImage(name: option.previewImageName, size: iconSize)
                .keyframeAnimator(
                    initialValue: 1.0,
                    trigger: appearanceToggleTrigger,
                ) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(0.82, duration: 0.12)
                        SpringKeyframe(1.0, duration: 0.42, spring: .bouncy)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityValue(
            previewMode == .dark
                ? String(localized: .appIconAppearanceDark)
                : String(localized: .appIconAppearanceLight),
        )
        .accessibilityHint(String(localized: .appIconAppearanceHint))
    }
}

#if DEBUG
    #Preview { AppIconPreviewModeButtonPreview() }

    private struct AppIconPreviewModeButtonPreview: View {
        @State private var mode = ColorScheme.light
        @State private var trigger = EventTrigger()

        var body: some View {
            if let option = AppIconModel.preview().selectedOption {
                AppIconPreviewModeButton(
                    option: option,
                    iconSize: 160,
                    previewMode: mode,
                    appearanceToggleTrigger: trigger,
                ) {
                    trigger.fire()
                    mode = mode == .light ? .dark : .light
                }
                .environment(\.colorScheme, mode)
                .whereBroadwayRoot()
            }
        }
    }
#endif
