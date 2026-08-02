#if DEBUG
    import Inspector
    import SwiftUI

    /// The accordion's next-launch Inspector control.
    ///
    /// Latching or clearing the preference never changes the current process
    /// runtime. A selected state stays visible as the row's subtitle and makes
    /// the same control the cancellation action.
    struct DeveloperInspectorModeRow: View {
        @Bindable var controller: InspectorModeController

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            Button(action: toggleNextLaunch) {
                Label {
                    VStack(alignment: .leading, spacing: menu.subtitleSpacing) {
                        Text(title)
                        if controller.nextLaunch == .inspector {
                            Text(String(localized: .developerInspectorNextLaunchSelected))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemName: systemImage)
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

        private var title: String {
            switch controller.nextLaunch {
                case .regularApplication:
                    String(localized: .developerEnterInspectorNextLaunch)
                case .inspector:
                    String(localized: .developerCancelInspectorNextLaunch)
            }
        }

        private var systemImage: String {
            switch controller.nextLaunch {
                case .regularApplication: "wrench.and.screwdriver"
                case .inspector: "xmark.circle"
            }
        }

        private func toggleNextLaunch() {
            switch controller.nextLaunch {
                case .regularApplication:
                    controller.enterInspectorOnNextLaunch()
                case .inspector:
                    controller.useRegularApplicationOnNextLaunch()
            }
        }
    }

    #Preview {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
