import SFSafeSymbols
import SwiftUI

/// A two-axis, pinch-zoomable graph of all registered screens.
struct FlyoverCanvasView<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>
    @State private var zoomAtGestureStart: Double?
    @State private var visibleRect = CGRect.zero
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let layout = FlyoverLayout(
            catalog: catalog,
            style: stylesheet.layout,
        ).resolve()
        let renderPlan = FlyoverCanvasRenderPlan(
            zoom: model.zoom,
            visibleRect: visibleRect,
            screenFrames: layout.screenFrames,
        )
        let liveScreenIDs: Set<ScreenID> = if model.focusedSelection != nil {
            []
        } else if let previewedScreenID = model.previewedScreenID {
            Set([previewedScreenID])
        } else {
            renderPlan.liveScreenIDs
        }
        let expectedPreviewLoads: Set<FlyoverPreviewReadiness<ScreenID>.LoadKey> = if model
            .hasAppliedInitialCanvasZoom
        {
            Set(catalog.screens.compactMap { screen in
                liveScreenIDs.contains(screen.id) ? model.previewLoadKey(for: screen) : nil
            })
        } else {
            []
        }

        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    ForEach(catalog.groups, id: \.id) { group in
                        if let frame = layout.groupFrames[group.id] {
                            FlyoverGroupBackdrop(title: group.title, frame: frame)
                        }
                    }

                    FlyoverConnectorCanvas(catalog: catalog, layout: layout)

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
                .simultaneousGesture(magnificationGesture)
            }
            .onScrollGeometryChange(for: CGRect.self) { geometry in
                geometry.visibleRect
            } action: { _, newValue in
                visibleRect = newValue
            }
            .overlay(alignment: .topTrailing) {
                Button("Fit All", systemSymbol: .arrowUpLeftAndArrowDownRight) {
                    fitAll(layout: layout, in: proxy.size)
                }
                .buttonStyle(.bordered)
                .controlSize(stylesheet.canvas.overlayControlSize)
                .fixedSize()
                .padding(stylesheet.canvas.overlayPadding)
            }
            .task {
                applyInitialWidthFit(layout: layout, in: proxy.size)
            }
            .task(id: expectedPreviewLoads) {
                model.previewReadiness.expect(expectedPreviewLoads)
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged(updateMagnification)
            .onEnded(endMagnification)
    }

    private func updateMagnification(_ value: MagnifyGesture.Value) {
        let initial = zoomAtGestureStart ?? model.zoom
        zoomAtGestureStart = initial
        model.zoom = min(max(initial * value.magnification, 0.15), 1.25)
    }

    private func endMagnification(_: MagnifyGesture.Value) {
        zoomAtGestureStart = nil
    }

    private func applyInitialWidthFit(
        layout: FlyoverLayoutResult<ScreenID>,
        in availableSize: CGSize,
    ) {
        model.applyInitialCanvasZoom(
            FlyoverCanvasZoomPlan(
                canvasSize: layout.canvasSize,
                availableSize: availableSize,
                edgeInset: stylesheet.canvas.framingInset,
            ).widthZoom,
        )
    }

    private func fitAll(layout: FlyoverLayoutResult<ScreenID>, in availableSize: CGSize) {
        model.zoom = FlyoverCanvasZoomPlan(
            canvasSize: layout.canvasSize,
            availableSize: availableSize,
            edgeInset: stylesheet.canvas.framingInset,
        ).allZoom
    }
}
