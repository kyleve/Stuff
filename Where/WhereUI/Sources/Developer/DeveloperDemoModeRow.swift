#if DEBUG
    import SFSafeSymbols
    import SwiftUI
    import WhereCore

    /// Opens the one-shot demo configuration for the next process launch.
    struct DeveloperDemoModeRow: View {
        @Bindable var controller: WhereDeveloperLaunchController
        let action: () -> Void

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            let menu = stylesheet.developerOverlay.menu
            Button(action: action) {
                Label {
                    VStack(alignment: .leading, spacing: menu.subtitleSpacing) {
                        Text(String(localized: .developerDemoNextLaunch))
                        if case let .demo(configuration) = controller.nextLaunch {
                            Text(summary(for: configuration))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemSymbol: .playRectangleOnRectangle)
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
            .accessibilityInputLabels([String(localized: .developerDemoNextLaunch)])
        }

        private func summary(for configuration: DemoDataBuilder.Configuration) -> String {
            guard !configuration.issueCategories.isEmpty else {
                return String(localized: .developerDemoCleanBaseline)
            }
            return WhereFormat.resolutionCategoryList(configuration.issueCategories)
        }
    }

    #Preview {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
