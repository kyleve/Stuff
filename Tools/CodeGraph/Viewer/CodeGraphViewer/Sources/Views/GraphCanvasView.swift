import CodeGraphModel
import SwiftUI

/// Transient, view-local drag state shared by the node layer (which moves the
/// dragged chip) and the edge overlay (which redraws its incident edges live).
/// Kept off the model so a drag never rewrites `positions` per tick — only the
/// dragged chip and its handful of incident edges re-render, not the whole graph.
@Observable
final class CanvasDragState {
    var nodeID: String?
    var point: CGPoint = .zero
}

/// The interactive graph: a static edge `Canvas`, a live overlay for the dragged
/// node's edges, and positioned chips on top, with gestures to pan / zoom /
/// select / drag-to-pin. The layers are split so an in-flight node drag only
/// re-renders the dragged chip and its incident edges — everything else stays put.
struct GraphCanvasView: View {
    @Bindable var model: GraphViewModel

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gesturePan: CGSize = .zero
    @State private var didFit = false
    @State private var drag = CanvasDragState()

    private var liveScale: CGFloat {
        scale * gestureZoom
    }

    private var liveOffset: CGSize {
        CGSize(width: offset.width + gesturePan.width, height: offset.height + gesturePan.height)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                background
                content(viewport: geo.size)
                    .scaleEffect(liveScale)
                    .offset(liveOffset)
            }
            .clipped()
            .simultaneousGesture(zoomGesture)
            .overlay(alignment: .top) { settlingIndicator }
            .overlay(alignment: .bottomTrailing) { ZoomControls(
                scale: $scale,
                onFit: { fit(in: geo.size) },
            ) }
            .overlay(alignment: .bottomLeading) { legend }
            .onChange(of: model.positions.isEmpty) { _, isEmpty in
                if !isEmpty, !didFit {
                    fit(in: geo.size)
                    didFit = true
                }
            }
            .onChange(of: model.graph.generatedAt) { _, _ in didFit = false }
        }
    }

    private var background: some View {
        Rectangle()
            .fill(Color(uiColor: .systemBackground))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { model.select(nil) }
            .gesture(panGesture)
    }

    private func content(viewport: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            StaticEdgeLayer(model: model, drag: drag)
                .allowsHitTesting(false)
            DraggedEdgeLayer(model: model, drag: drag)
                .allowsHitTesting(false)
            NodeLayer(model: model, drag: drag, viewport: viewport, scale: scale, offset: offset)
        }
        .frame(
            width: model.canvasSize.width,
            height: model.canvasSize.height,
            alignment: .topLeading,
        )
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureZoom) { value, state, _ in state = value.magnification }
            .onEnded { value in scale = clamp(scale * value.magnification) }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($gesturePan) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.15), 3.0)
    }

    private func fit(in viewport: CGSize) {
        let points = Array(model.positions.values)
        guard !points.isEmpty else { return }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!
        let pad: CGFloat = 100
        let boxWidth = max(maxX - minX, 1) + pad
        let boxHeight = max(maxY - minY, 1) + pad
        let fitted = clamp(min(viewport.width / boxWidth, viewport.height / boxHeight))
        let boxCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let canvasCenter = CGPoint(x: model.canvasSize.width / 2, y: model.canvasSize.height / 2)
        scale = fitted
        offset = CGSize(
            width: viewport.width / 2 - (canvasCenter.x + (boxCenter.x - canvasCenter.x) * fitted),
            height: viewport
                .height / 2 - (canvasCenter.y + (boxCenter.y - canvasCenter.y) * fitted),
        )
    }

    @ViewBuilder
    private var settlingIndicator: some View {
        if model.isLayingOut {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Settling \(model.visibleNodes.count) nodes…")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 10)
        }
    }

    private var legend: some View {
        Text("\(model.visibleNodes.count) nodes · \(model.visibleEdges.count) edges")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(12)
    }
}

// MARK: - Edge layers

/// Every visible edge except those touching the node being dragged (drawn live
/// by `DraggedEdgeLayer`). Reads `drag.nodeID` but never `drag.point`, so it
/// stays frozen for the whole drag and only redraws at its start and end.
private struct StaticEdgeLayer: View {
    let model: GraphViewModel
    let drag: CanvasDragState

    var body: some View {
        let draggingID = drag.nodeID
        let selection = model.selection
        let edges = model.visibleEdges
        let positions = model.positions
        Canvas { context, _ in
            for edge in edges where edge.source != draggingID && edge.target != draggingID {
                guard let from = positions[edge.source], let to = positions[edge.target] else {
                    continue
                }
                let emphasized = selection == nil || edge.source == selection || edge
                    .target == selection
                EdgeRenderer.draw(
                    edge: edge,
                    from: from,
                    to: to,
                    emphasized: emphasized,
                    in: context,
                )
            }
        }
        .frame(width: model.canvasSize.width, height: model.canvasSize.height)
    }
}

/// The dragged node's incident edges, redrawn each tick from the live drag
/// point. Neighbor endpoints are captured when the drag starts (they don't
/// move), so per-tick cost is O(incident edges), not O(all edges).
private struct DraggedEdgeLayer: View {
    let model: GraphViewModel
    let drag: CanvasDragState
    @State private var incident: [IncidentEdge] = []

    var body: some View {
        let point = drag.point
        let active = drag.nodeID != nil
        let selection = model.selection
        Canvas { context, _ in
            guard active else { return }
            for item in incident {
                let from = item.draggedIsSource ? point : item.neighbor
                let to = item.draggedIsSource ? item.neighbor : point
                let emphasized = selection == nil || item.edge.source == selection || item.edge
                    .target == selection
                EdgeRenderer.draw(
                    edge: item.edge,
                    from: from,
                    to: to,
                    emphasized: emphasized,
                    in: context,
                )
            }
        }
        .frame(width: model.canvasSize.width, height: model.canvasSize.height)
        .onChange(of: drag.nodeID) { _, id in
            incident = id.map(incidentEdges) ?? []
        }
    }

    private func incidentEdges(of id: String) -> [IncidentEdge] {
        model.visibleEdges.compactMap { edge in
            let draggedIsSource: Bool
            let neighborID: String
            if edge.source == id {
                draggedIsSource = true
                neighborID = edge.target
            } else if edge.target == id {
                draggedIsSource = false
                neighborID = edge.source
            } else {
                return nil
            }
            guard let neighbor = model.positions[neighborID] else { return nil }
            return IncidentEdge(edge: edge, neighbor: neighbor, draggedIsSource: draggedIsSource)
        }
    }
}

/// A visible edge touching the dragged node, with its (fixed) neighbor endpoint
/// captured at drag start so the overlay needn't touch `positions` per tick.
private struct IncidentEdge {
    let edge: GraphEdge
    let neighbor: CGPoint
    let draggedIsSource: Bool
}

private enum EdgeRenderer {
    static func draw(
        edge: GraphEdge,
        from: CGPoint,
        to: CGPoint,
        emphasized: Bool,
        in context: GraphicsContext,
    ) {
        let base = GraphStyle.color(for: edge.kind)
        let color = base.opacity(emphasized ? 0.7 : 0.08)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: GraphStyle.lineWidth(for: edge.kind),
                lineCap: .round,
                dash: GraphStyle.dash(for: edge.kind),
            ),
        )
        if emphasized {
            arrowhead(from: from, to: to, color: base.opacity(0.7), in: context)
        }
    }

    private static func arrowhead(
        from: CGPoint,
        to: CGPoint,
        color: Color,
        in context: GraphicsContext,
    ) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 28 else { return }
        let ux = dx / length
        let uy = dy / length
        // Back off the arrow so it sits at the target chip's edge, not under it.
        let tip = CGPoint(x: to.x - ux * 16, y: to.y - uy * 16)
        let size: CGFloat = 7
        let left = CGPoint(
            x: tip.x - ux * size - uy * size * 0.6,
            y: tip.y - uy * size + ux * size * 0.6,
        )
        let right = CGPoint(
            x: tip.x - ux * size + uy * size * 0.6,
            y: tip.y - uy * size - ux * size * 0.6,
        )
        var head = Path()
        head.move(to: tip)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}

// MARK: - Node layer

/// The interactive chips. Reads `model` (positions, visible set, selection) but
/// never `drag`, so an in-flight drag — which only mutates `drag` — leaves this
/// layer and its O(N) culling untouched; just the dragged chip re-renders.
private struct NodeLayer: View {
    let model: GraphViewModel
    let drag: CanvasDragState
    let viewport: CGSize
    let scale: CGFloat
    let offset: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(culledNodes) { node in
                DraggableChip(node: node, model: model, drag: drag, scale: scale)
            }
        }
        .frame(
            width: model.canvasSize.width,
            height: model.canvasSize.height,
            alignment: .topLeading,
        )
    }

    /// Only the nodes whose positions fall inside the visible canvas rect (grown
    /// by a one-viewport margin) get instantiated as chips — so zooming in
    /// doesn't keep thousands of off-screen interactive views alive. Keyed to the
    /// committed `scale`/`offset` (not the live gesture values), so an in-flight
    /// pan/zoom just transforms the existing layer instead of re-culling.
    private var culledNodes: [Node] {
        guard viewport.width > 0, viewport.height > 0, scale > 0 else {
            return model.visibleNodes.filter { model.positions[$0.id] != nil }
        }
        let halfW = model.canvasSize.width / 2
        let halfH = model.canvasSize.height / 2
        let minX = halfW + (-offset.width - halfW) / scale - viewport.width / scale
        let maxX = halfW + (viewport.width - offset.width - halfW) / scale + viewport.width / scale
        let minY = halfH + (-offset.height - halfH) / scale - viewport.height / scale
        let maxY = halfH + (viewport.height - offset.height - halfH) / scale + viewport
            .height / scale
        return model.visibleNodes.filter { node in
            guard let point = model.positions[node.id] else { return false }
            return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }
}

/// One node chip. The live drag offset lives in this view's `@GestureState`, so
/// dragging moves only this chip — the parent node layer never re-evaluates.
/// The committed position lands on the model on drag end.
private struct DraggableChip: View {
    let node: Node
    let model: GraphViewModel
    let drag: CanvasDragState
    let scale: CGFloat
    @GestureState private var translation: CGSize = .zero

    var body: some View {
        let selected = model.selection == node.id
        let dimmed = model.selection != nil && !selected && !model.selectionNeighbors
            .contains(node.id)
        let base = model.positions[node.id] ?? .zero
        return NodeChipView(
            node: node,
            isSelected: selected,
            isPinned: model.isPinned(node.id),
            memberCount: node.kind.isType ? model.memberCount(node.id) : 0,
            isExpanded: model.isExpanded(node.id),
            isDimmed: dimmed,
            onToggleExpand: { model.toggleExpanded(node.id) },
        )
        // Skip rebuilding a chip's body (capsule, shadow, labels) when none of
        // its inputs changed — so a drag or settle animation only re-renders the
        // handful of chips that actually moved, not every visible node.
        .equatable()
        .position(base)
        .offset(x: translation.width / scale, y: translation.height / scale)
        .onTapGesture { model.select(node.id) }
        .gesture(dragGesture(base: base))
        .contextMenu { menu }
    }

    private func dragGesture(base: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($translation) { value, state, _ in state = value.translation }
            .onChanged { value in
                // Set the id once (it drives the static/overlay split); push the
                // live point every tick for the incident-edge overlay.
                if drag.nodeID != node.id { drag.nodeID = node.id }
                drag.point = location(of: value, base: base)
            }
            .onEnded { value in
                model.endDrag(node.id, at: location(of: value, base: base))
                drag.nodeID = nil
            }
    }

    /// Screen translation is in points; divide by the committed scale to convert
    /// to the content space `positions` lives in (no pinch happens mid-drag).
    private func location(of value: DragGesture.Value, base: CGPoint) -> CGPoint {
        CGPoint(
            x: base.x + value.translation.width / scale,
            y: base.y + value.translation.height / scale,
        )
    }

    @ViewBuilder
    private var menu: some View {
        Button("Focus on \(node.name)", systemImage: "scope") {
            model.focus(on: node.id)
        }
        if node.kind.isType, model.memberCount(node.id) > 0 {
            Button(model.isExpanded(node.id) ? "Collapse members" : "Expand members") {
                model.toggleExpanded(node.id)
            }
        }
        if model.isPinned(node.id) {
            Button("Unpin", systemImage: "pin.slash") { model.unpin(node.id) }
        }
    }
}

private struct ZoomControls: View {
    @Binding var scale: CGFloat
    let onFit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            button("plus.magnifyingglass") { scale = min(scale * 1.25, 3.0) }
            button("minus.magnifyingglass") { scale = max(scale / 1.25, 0.15) }
            button("arrow.up.left.and.arrow.down.right", action: onFit)
        }
        .padding(10)
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
