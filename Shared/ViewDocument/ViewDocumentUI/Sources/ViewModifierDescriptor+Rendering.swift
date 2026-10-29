import SwiftUI
import ViewDocumentCore

extension ViewModifierDescriptor {
    func applying(to view: AnyView, appearance: ViewDocumentAppearance) -> AnyView {
        switch self {
            case let .font(font): AnyView(view.font(font.font))
            case let .foreground(paint): AnyView(view.foregroundStyle(appearance.paint(paint)))
            case let .frame(width, height, alignment):
                AnyView(view.frame(
                    width: width.map(appearance.dimension),
                    height: height.map(appearance.dimension),
                    alignment: alignment.alignment,
                ))
            case let .padding(value): AnyView(view.padding(appearance.dimension(value)))
            case let .offset(x, y): AnyView(view.offset(x: x, y: y))
            case let .scale(x, y): AnyView(view.scaleEffect(x: x, y: y))
            case let .rotation(degrees): AnyView(view.rotationEffect(.degrees(degrees)))
            case let .opacity(value): AnyView(view.opacity(value))
            case let .clip(shape): AnyView(view.clipShape(ViewDocumentShape(descriptor: shape)))
            case let .background(shape, paint):
                AnyView(view
                    .background(ViewDocumentShape(descriptor: shape).fill(appearance.paint(paint))))
            case let .border(shape, paint, width):
                AnyView(view.overlay(ViewDocumentShape(descriptor: shape).stroke(
                    appearance.paint(paint),
                    lineWidth: width,
                )))
            case let .shadow(color, radius, x, y): AnyView(view.shadow(
                    color: appearance.color(color),
                    radius: radius,
                    x: x,
                    y: y,
                ))
            case let .blend(blend): AnyView(view.blendMode(blend.blendMode))
        }
    }
}
