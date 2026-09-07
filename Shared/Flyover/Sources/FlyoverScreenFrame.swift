import SFSafeSymbols
import SwiftUI

/// One overview card containing an inert rendered screen and live local controls.
struct FlyoverScreenFrame<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>
    var rendersContent = true
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.screen
        VStack(spacing: 0) {
            FlyoverScreenHeader(screen: screen, model: model)

            Group {
                if rendersContent {
                    FlyoverScreenContent(screen: screen, model: model, isOverview: true)
                } else {
                    FlyoverScreenPlaceholder(screen: screen, model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: style.contentMaximumHeight)
            .background(style.contentShade.opacity(style.contentShadeOpacity))

            Divider()

            FlyoverScreenControls(screen: screen, model: model)

            FlyoverRouteSummary(screen: screen, catalog: catalog)
        }
        .frame(width: stylesheet.layout.cardSize.width)
        .frame(height: stylesheet.layout.cardSize.height)
        .flyoverScreenFrame()
    }
}

private struct FlyoverScreenPlaceholder<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.screen.placeholder
        VStack(spacing: style.spacing) {
            Image(systemSymbol: .viewfinder)
                .font(style.iconFont)
                .foregroundStyle(.secondary)
            Text(model.variant(for: screen).title)
                .font(style.titleFont)
            Text("Move this frame toward the center, render it here, or inspect it full-screen.")
                .font(style.messageFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: style.messageMaximumWidth)
            Button("Render Preview", systemSymbol: .playFill) {
                model.preview(screen)
            }
            .buttonStyle(.bordered)
            .controlSize(style.controlSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(screen.title), preview paused")
    }
}
