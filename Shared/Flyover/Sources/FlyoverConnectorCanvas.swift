import SwiftUI

/// Draws navigation relationships as vector views without a graph-sized bitmap texture.
struct FlyoverConnectorCanvas<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let layout: FlyoverLayoutResult<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(catalog.transitions.indices, id: \.self) { index in
                let transition = catalog.transitions[index]
                if let source = layout.screenFrames[transition.source],
                   let destination = layout.screenFrames[transition.destination]
                {
                    connector(transition, from: source, to: destination)
                }
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func connector(
        _ transition: FlyoverTransition<ScreenID>,
        from source: CGRect,
        to destination: CGRect,
    ) -> some View {
        let style = stylesheet.connector
        let geometry = FlyoverConnectorGeometry(
            source: source,
            destination: destination,
            style: style,
        )
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: geometry.start)
                path.addCurve(
                    to: geometry.end,
                    control1: geometry.firstControl,
                    control2: geometry.secondControl,
                )
            }
            .stroke(color(for: transition.kind), style: StrokeStyle(
                lineWidth: style.lineWidth,
                lineCap: .round,
                dash: transition.kind == .modal ? style.modalDash : [],
            ))
            Path { arrow in
                arrow.move(to: geometry.firstArrowPoint)
                arrow.addLine(to: geometry.end)
                arrow.addLine(to: geometry.secondArrowPoint)
            }
            .stroke(color(for: transition.kind), style: StrokeStyle(
                lineWidth: style.lineWidth,
                lineCap: .round,
                lineJoin: .round,
            ))
            Text(transition.label ?? transition.kind.title)
                .font(style.labelFont)
                .foregroundStyle(color(for: transition.kind))
                .fixedSize()
                .position(
                    x: geometry.midpoint.x,
                    y: geometry.midpoint.y - style.labelOffsetY,
                )
        }
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
