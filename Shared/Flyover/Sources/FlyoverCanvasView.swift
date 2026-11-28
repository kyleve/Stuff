import SFSafeSymbols
import SwiftUI

/// A two-axis, pinch-zoomable graph of all registered screens.
struct FlyoverCanvasView<ScreenID: Hashable>: View {
    private enum ZoomChangeBehavior {
        /// Adjust the scroll offset so the canvas point at the viewport center stays fixed.
        case preserveViewportCenter

        /// Skip the offset adjustment for the initial fit, keeping the top-leading origin visible.
        case preserveContentOrigin
    }

    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>
    @State private var zoomAtGestureStart: Double?
    @State private var zoomChangeBehavior = ZoomChangeBehavior.preserveViewportCenter
    @State private var scrollPosition = ScrollPosition()
    @State private var visibleRect = CGRect.zero
    @State private var settledLiveScreenIDs: Set<ScreenID> = []
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
        let desiredLiveScreenIDs: Set<ScreenID> = if model.focusedSelection != nil {
            []
        } else if let previewedScreenID = model.previewedScreenID {
            Set([previewedScreenID])
        } else {
            renderPlan.liveScreenIDs
        }
        let liveScreenIDs = model.previewedScreenID == nil
            ? settledLiveScreenIDs.intersection(desiredLiveScreenIDs)
            : desiredLiveScreenIDs
        let expectedPreviewLoads: Set<FlyoverPreviewReadiness<ScreenID>.LoadKey> = if model
            .hasAppliedInitialCanvasZoom
        {
            Set(catalog.screens.compactMap { screen in
                desiredLiveScreenIDs.contains(screen.id) ? model.previewLoadKey(for: screen) : nil
            })
        } else {
            []
        }

        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                FlyoverGraph(
                    catalog: catalog,
                    model: model,
                    layout: layout,
                    renderPlan: renderPlan,
                    liveScreenIDs: liveScreenIDs,
                )
                .simultaneousGesture(magnificationGesture)
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGRect.self) { geometry in
                geometry.visibleRect
            } action: { _, newValue in
                visibleRect = newValue
            }
            .onChange(of: renderPlan) { _, newPlan in
                settledLiveScreenIDs.formIntersection(newPlan.liveScreenIDs)
            }
            .onChange(of: model.zoom) { oldZoom, newZoom in
                switch zoomChangeBehavior {
                    case .preserveViewportCenter:
                        preserveViewportCenter(
                            layout: layout,
                            from: oldZoom,
                            to: newZoom,
                        )
                    case .preserveContentOrigin:
                        zoomChangeBehavior = .preserveViewportCenter
                }
            }
            .overlay(alignment: .topTrailing) {
                FlyoverFitAllButton { fitAll(layout: layout, in: proxy.size) }
            }
            .task {
                applyInitialGroupWidthFit(layout: layout, in: proxy.size)
            }
            .task(id: renderPlan) {
                // Pan and zoom change the viewport every frame. Keep surviving previews,
                // but construct replacements only after movement pauses for 200 ms.
                do {
                    try await model.waitForCanvasToSettle()
                } catch is CancellationError {
                    return
                } catch {
                    assertionFailure("Unexpected preview settling failure: \(error)")
                    return
                }
                settledLiveScreenIDs = renderPlan.liveScreenIDs
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

    private func preserveViewportCenter(
        layout: FlyoverLayoutResult<ScreenID>,
        from oldZoom: Double,
        to newZoom: Double,
    ) {
        guard visibleRect.isEmpty == false else {
            return
        }
        let plan = FlyoverCanvasZoomPlan(
            canvasSize: layout.canvasSize,
            availableSize: visibleRect.size,
            edgeInset: stylesheet.canvas.framingInset,
        )
        scrollPosition.scrollTo(
            point: plan.contentOffset(
                preservingViewportCenterIn: visibleRect,
                from: oldZoom,
                to: newZoom,
            ),
        )
    }

    private func applyInitialGroupWidthFit(
        layout: FlyoverLayoutResult<ScreenID>,
        in availableSize: CGSize,
    ) {
        guard model.hasAppliedInitialCanvasZoom == false else {
            return
        }
        let initialZoom = FlyoverCanvasZoomPlan(
            canvasSize: layout.initialCanvasSize,
            availableSize: availableSize,
            edgeInset: stylesheet.canvas.framingInset,
        ).widthZoom
        if initialZoom != model.zoom {
            zoomChangeBehavior = .preserveContentOrigin
        }
        model.applyInitialCanvasZoom(initialZoom)
    }

    private func fitAll(layout: FlyoverLayoutResult<ScreenID>, in availableSize: CGSize) {
        model.zoom = FlyoverCanvasZoomPlan(
            canvasSize: layout.canvasSize,
            availableSize: availableSize,
            edgeInset: stylesheet.canvas.framingInset,
        ).allZoom
    }
}

private struct FlyoverFitAllButton: View {
    let fit: () -> Void
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        Button("Fit All", systemSymbol: .arrowUpLeftAndArrowDownRight) {
            fit()
        }
        .buttonStyle(.bordered)
        .controlSize(stylesheet.canvas.overlayControlSize)
        .fixedSize()
        .padding(stylesheet.canvas.overlayPadding)
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif
