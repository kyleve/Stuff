#if DEBUG
    import SwiftUI

    /// One navigation action in the developer overlay's accordion.
    struct DeveloperToolMenuButton: View {
        let destination: DeveloperDestination
        let action: () -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            Button(action: action) {
                Label(destination.title, systemSymbol: destination.systemSymbol)
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
            .accessibilityInputLabels([destination.title])
        }
    }

    #Preview {
        DeveloperToolMenuButton(destination: .tool(.regionMap), action: {})
            .padding()
            .whereBroadwayRoot()
    }
#endif
