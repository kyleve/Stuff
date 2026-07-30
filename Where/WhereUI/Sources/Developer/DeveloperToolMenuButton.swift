#if DEBUG
    import SwiftUI

    /// One navigation action in the developer overlay's accordion.
    struct DeveloperToolMenuButton: View {
        let tool: DeveloperTool
        let action: () -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            Button(action: action) {
                Label(tool.title, systemImage: tool.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            .accessibilityInputLabels([tool.title])
        }
    }

    #Preview {
        DeveloperToolMenuButton(tool: .regionMap, action: {})
            .padding()
            .whereBroadwayRoot()
    }
#endif
