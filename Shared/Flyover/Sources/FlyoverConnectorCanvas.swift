import SwiftUI

/// Draws push and modal navigation relationships behind Flyover cards.
struct FlyoverConnectorCanvas<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let layout: FlyoverLayoutResult<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

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
