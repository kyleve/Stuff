import SwiftUI

/// Draws navigation relationships in bounded tiles, retaining graph coordinates for every route.
struct FlyoverConnectorCanvas<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let layout: FlyoverLayoutResult<ScreenID>
    let renderPlan: FlyoverCanvasRenderPlan<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let tiles = FlyoverConnectorTilePlan(canvasSize: layout.canvasSize).tiles
            .filter { renderPlan.shouldDisplay($0.frame) }

        ZStack(alignment: .topLeading) {
            ForEach(tiles) { tile in
                canvas(in: tile.frame)
                    .frame(width: tile.frame.width, height: tile.frame.height)
                    .clipped(antialiased: false)
                    .position(x: tile.frame.midX, y: tile.frame.midY)
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func canvas(in frame: CGRect) -> some View {
        Canvas { context, _ in
            // Keep one coordinate system so curves, dash phases, and labels
            // continue unchanged across tile edges.
            context.translateBy(x: -frame.minX, y: -frame.minY)
            for transition in catalog.transitions {
                guard
                    let source = layout.screenFrames[transition.source],
                    let destination = layout.screenFrames[transition.destination]
                else {
                    continue
                }
                draw(
                    transition,
                    from: source,
                    to: destination,
                    context: &context,
                )
            }
        }
    }

    private func draw(
        _ transition: FlyoverTransition<ScreenID>,
        from source: CGRect,
        to destination: CGRect,
        context: inout GraphicsContext,
    ) {
        let style = stylesheet.connector
        let geometry = FlyoverConnectorGeometry(
            source: source,
            destination: destination,
            style: style,
        )
        var path = Path()
        path.move(to: geometry.start)
        path.addCurve(
            to: geometry.end,
            control1: geometry.firstControl,
            control2: geometry.secondControl,
        )
        let strokeStyle = StrokeStyle(
            lineWidth: style.lineWidth,
            lineCap: .round,
            dash: transition.kind == .modal ? style.modalDash : [],
        )
        context.stroke(path, with: .color(color(for: transition.kind)), style: strokeStyle)

        var arrow = Path()
        arrow.move(to: geometry.firstArrowPoint)
        arrow.addLine(to: geometry.end)
        arrow.addLine(to: geometry.secondArrowPoint)
        context.stroke(
            arrow,
            with: .color(color(for: transition.kind)),
            style: StrokeStyle(
                lineWidth: style.lineWidth,
                lineCap: .round,
                lineJoin: .round,
            ),
        )

        let title = transition.label ?? transition.kind.title
        let label = context.resolve(
            Text(title)
                .font(style.labelFont)
                .foregroundStyle(color(for: transition.kind)),
        )
        context.draw(
            label,
            at: CGPoint(
                x: geometry.midpoint.x,
                y: geometry.midpoint.y - style.labelOffsetY,
            ),
        )
    }

    private func color(for kind: FlyoverTransition<ScreenID>.Kind) -> Color {
        switch kind {
            case .push: stylesheet.connector.pushColor
            case .modal: stylesheet.connector.modalColor
        }
    }
}

extension FlyoverTransition.Kind {
    fileprivate var title: String {
        switch self {
            case .push: "Push"
            case .modal: "Modal"
        }
    }
}
