import SwiftUI

/// Keep the system label layout at ordinary sizes. Accessibility labels use the whole row width,
/// with their growing symbol above the text rather than inside a fixed-width icon slot.
struct DeveloperMenuLabelStyle: LabelStyle {
    @Environment(\.stylesheet) private var stylesheet

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let menu = stylesheet.developerOverlay.menu
        if menu.stacksLabelsAndControls {
            VStack(alignment: .leading, spacing: menu.subtitleSpacing) {
                configuration.icon
                configuration.title
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label(configuration)
                .labelStyle(.titleAndIcon)
        }
    }
}

#if DEBUG
    #Preview {
        DeveloperOverlayPreview(presentation: .menu, isPortholeEnabled: true, surface: .menuContent)
            .whereBroadwayRoot()
    }
#endif
