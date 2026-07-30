import SwiftUI

/// Draws push and modal navigation relationships behind Flyover cards.
struct FlyoverConnectorCanvas<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let layout: FlyoverLayoutResult<ScreenID>

    var body: some View {
        Canvas { context, _ in
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
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(
        _ transition: FlyoverTransition<ScreenID>,
        from source: CGRect,
        to destination: CGRect,
        context: inout GraphicsContext,
    ) {
        let start = CGPoint(x: source.maxX, y: source.midY)
        let end = CGPoint(x: destination.minX, y: destination.midY)
        let controlOffset = max((end.x - start.x) * 0.45, 40)
        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + controlOffset, y: start.y),
            control2: CGPoint(x: end.x - controlOffset, y: end.y),
        )
        let style = StrokeStyle(
            lineWidth: 3,
            lineCap: .round,
            dash: transition.kind == .modal ? [12, 8] : [],
        )
        context.stroke(path, with: .color(color(for: transition.kind)), style: style)

        var arrow = Path()
        arrow.move(to: CGPoint(x: end.x - 12, y: end.y - 7))
        arrow.addLine(to: end)
        arrow.addLine(to: CGPoint(x: end.x - 12, y: end.y + 7))
        context.stroke(
            arrow,
            with: .color(color(for: transition.kind)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round),
        )

        let title = transition.label ?? transition.kind.title
        let label = context.resolve(
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(color(for: transition.kind)),
        )
        context.draw(
            label,
            at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 12),
        )
    }

    private func color(for kind: FlyoverTransition<ScreenID>.Kind) -> Color {
        switch kind {
            case .push: .blue
            case .modal: .purple
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
