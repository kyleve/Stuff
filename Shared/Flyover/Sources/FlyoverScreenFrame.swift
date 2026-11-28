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
        VStack(spacing: 0) {
            FlyoverScreenHeader(screen: screen, model: model)

            FlyoverScreenViewport(screen: screen, model: model, rendersContent: rendersContent)

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
            FlyoverRenderPreviewButton { model.preview(screen) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(screen.title), preview paused")
    }
}

private struct FlyoverScreenViewport<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    let rendersContent: Bool
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.screen
        Group {
            if rendersContent {
                FlyoverScreenContent(screen: screen, model: model, isOverview: true)
            } else {
                FlyoverScreenPlaceholder(screen: screen, model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: style.contentMaximumHeight)
        .background(style.contentShade.opacity(style.contentShadeOpacity))
    }
}

private struct FlyoverRenderPreviewButton: View {
    let render: () -> Void
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        Button("Render Preview", systemSymbol: .playFill) {
            render()
        }
        .buttonStyle(.bordered)
        .controlSize(stylesheet.screen.placeholder.controlSize)
    }
}

/// The title and focus action at the top of a Flyover overview card.
private struct FlyoverScreenHeader<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        HStack {
            Text(screen.title)
                .font(stylesheet.screen.header.font)
                .lineLimit(1)
            Spacer()
            Button("Inspect \(screen.title)", systemSymbol: .arrowUpLeftAndArrowDownRight) {
                model.focus(screen)
            }
            .labelStyle(.iconOnly)
        }
        .padding(stylesheet.screen.header.padding)
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif
