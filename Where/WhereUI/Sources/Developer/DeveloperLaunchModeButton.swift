#if DEBUG
    import SFSafeSymbols
    import SwiftUI

    #Preview { DeveloperOverlayPreview(presentation: .menu) }

    struct DeveloperLaunchModeButton: View {
        let title: String
        let subtitle: String?
        let systemSymbol: SFSymbol
        let action: () -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            Button(action: action) {
                Label {
                    VStack(alignment: .leading, spacing: menu.subtitleSpacing) {
                        Text(title)
                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemSymbol: systemSymbol)
                        .frame(width: menu.iconWidth)
                }
                .padding(.horizontal, menu.horizontalPadding)
                .padding(.vertical, menu.verticalPadding)
                .frame(minHeight: menu.minRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: menu.cornerRadius),
            )
            .accessibilityInputLabels([title])
        }
    }
#endif
