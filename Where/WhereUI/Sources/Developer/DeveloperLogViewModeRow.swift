import SFSafeSymbols
#if DEBUG
    import PeriscopeTools
    import SwiftUI

    /// The accordion's inline Log View Mode control.
    ///
    /// Unlike the surrounding tool buttons this mutates the injected inspector
    /// in place and intentionally leaves the menu open.
    struct DeveloperLogViewModeRow: View {
        @Bindable var inspector: PeriscopeInspector

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            Toggle(isOn: $inspector.isEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: menu.subtitleSpacing) {
                        Text(String(localized: .developerLogViewMode))
                        Text(String(localized: .developerLogViewModeFooter))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemSymbol: .viewfinder)
                        .frame(width: menu.iconWidth)
                }
            }
            .padding(.horizontal, menu.horizontalPadding)
            .padding(.vertical, menu.verticalPadding)
            .frame(minHeight: menu.minRowHeight)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: menu.cornerRadius),
            )
        }
    }

    #Preview {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
