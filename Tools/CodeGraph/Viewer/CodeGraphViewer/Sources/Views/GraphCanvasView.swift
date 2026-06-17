import CodeGraphModel
import SwiftUI

/// The interactive graph: a Canvas draws the edges, positioned chips draw the
/// nodes, and gestures pan / zoom / select / drag-to-pin on top.
struct GraphCanvasView: View {
    @Bindable var model: GraphViewModel

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gesturePan: CGSize = .zero
    @State private var dragStart: (id: String, point: CGPoint)?
    @State private var didFit = false

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
                content
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
            .onChange(of: model.graph) { _, _ in didFit = false }
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

    private var content: some View {
        ZStack(alignment: .topLeading) {
            edgeCanvas
                .allowsHitTesting(false)
            nodeLayer
        }
        .frame(
            width: model.canvasSize.width,
            height: model.canvasSize.height,
            alignment: .topLeading,
        )
    }

    private var edgeCanvas: some View {
        Canvas { context, _ in
            let selection = model.selection
            for edge in model.visibleEdges {
                guard
                    let from = model.positions[edge.source],
                    let to = model.positions[edge.target]
                else { continue }
                let incident = selection == nil || edge.source == selection || edge
                    .target == selection
                draw(edge: edge, from: from, to: to, emphasized: incident, in: context)
            }
        }
        .frame(width: model.canvasSize.width, height: model.canvasSize.height)
    }

    private func draw(
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
            drawArrowhead(from: from, to: to, color: base.opacity(0.7), in: context)
        }
    }

    private func drawArrowhead(
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

    private var nodeLayer: some View {
        ForEach(model.visibleNodes) { node in
            if let point = model.positions[node.id] {
                chip(for: node)
                    .position(point)
            }
        }
    }

    private func chip(for node: Node) -> some View {
        let selected = model.selection == node.id
        let dimmed = model.selection != nil && !selected && !isNeighbor(
            node.id,
            of: model.selection!,
        )
        return NodeChipView(
            node: node,
            isSelected: selected,
            isPinned: model.isPinned(node.id),
            memberCount: node.kind.isType ? model.memberCount(node.id) : 0,
            isExpanded: model.isExpanded(node.id),
            isDimmed: dimmed,
            onToggleExpand: { model.toggleExpanded(node.id) },
        )
        .onTapGesture { model.select(node.id) }
        .gesture(nodeDrag(node))
        .contextMenu { nodeMenu(node) }
    }

    @ViewBuilder
    private func nodeMenu(_ node: Node) -> some View {
        if node.kind.isType, model.memberCount(node.id) > 0 {
            Button(model.isExpanded(node.id) ? "Collapse members" : "Expand members") {
                model.toggleExpanded(node.id)
            }
        }
        if model.isPinned(node.id) {
            Button("Unpin") { model.unpin(node.id) }
        }
    }

    private func nodeDrag(_ node: Node) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStart?.id != node.id {
                    dragStart = (node.id, model.positions[node.id] ?? .zero)
                }
                model.drag(node.id, to: dragged(value))
            }
            .onEnded { value in
                model.endDrag(node.id, at: dragged(value))
                dragStart = nil
            }
    }

    private func dragged(_ value: DragGesture.Value) -> CGPoint {
        let start = dragStart?.point ?? .zero
        return CGPoint(
            x: start.x + value.translation.width / scale,
            y: start.y + value.translation.height / scale,
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

    private func isNeighbor(_ id: String, of selected: String) -> Bool {
        if id == selected { return true }
        for edge in model.outgoing(selected) where edge.target == id {
            return true
        }
        for edge in model.incoming(selected) where edge.source == id {
            return true
        }
        return false
    }

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
