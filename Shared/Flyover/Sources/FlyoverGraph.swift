import SwiftUI

struct FlyoverGraph<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>
    let layout: FlyoverLayoutResult<ScreenID>
    let renderPlan: FlyoverCanvasRenderPlan<ScreenID>
    let liveScreenIDs: Set<ScreenID>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(catalog.groups, id: \.id) { group in
                if let frame = layout.groupFrames[group.id] {
                    FlyoverGroupBackdrop(title: group.title, frame: frame)
                }
            }

            ForEach(layout.depthBands) { band in
                FlyoverDepthBandBackdrop(band: band)
            }

            FlyoverConnectorCanvas(catalog: catalog, layout: layout)

            FlyoverCanvasFrames(
                catalog: catalog,
                model: model,
                layout: layout,
                renderPlan: renderPlan,
                liveScreenIDs: liveScreenIDs,
            )
        }
        .frame(
            width: layout.canvasSize.width,
            height: layout.canvasSize.height,
            alignment: .topLeading,
        )
        .scaleEffect(model.zoom, anchor: .topLeading)
        .frame(
            width: layout.canvasSize.width * model.zoom,
            height: layout.canvasSize.height * model.zoom,
            alignment: .topLeading,
        )
    }
}

private struct FlyoverCanvasFrames<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>
    let layout: FlyoverLayoutResult<ScreenID>
    let renderPlan: FlyoverCanvasRenderPlan<ScreenID>
    let liveScreenIDs: Set<ScreenID>

    var body: some View {
        ForEach(catalog.screens, id: \.id) { screen in
            if let frame = layout.screenFrames[screen.id],
               renderPlan.shouldDisplay(frame)
            {
                FlyoverScreenFrame(
                    screen: screen,
                    catalog: catalog,
                    model: model,
                    rendersContent: liveScreenIDs.contains(screen.id),
                )
                .position(x: frame.midX, y: frame.midY)
            }
        }
    }
}

/// Draws navigation relationships as vector views without a graph-sized bitmap texture.
private struct FlyoverConnectorCanvas<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let layout: FlyoverLayoutResult<ScreenID>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(catalog.transitions.indices, id: \.self) { index in
                let transition = catalog.transitions[index]
                if let source = layout.screenFrames[transition.source],
                   let destination = layout.screenFrames[transition.destination]
                {
                    FlyoverConnector(
                        transition: transition,
                        source: source,
                        destination: destination,
                    )
                }
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A labeled visual boundary around one Flyover group.
private struct FlyoverGroupBackdrop: View {
    let title: String
    let frame: CGRect
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.group
        RoundedRectangle(cornerRadius: style.cornerRadius)
            .fill(style.fill.opacity(style.fillOpacity))
            .stroke(.quaternary, lineWidth: style.strokeWidth)
            .frame(width: frame.width, height: frame.height)
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(style.titleFont)
                    .padding(style.titlePadding)
            }
            .position(x: frame.midX, y: frame.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) screen group")
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif
