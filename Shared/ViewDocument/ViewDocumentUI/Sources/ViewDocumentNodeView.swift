import SwiftUI
import ViewDocumentCore

/// Type erasure is confined to the recursive document interpreter.
struct ViewDocumentNodeView: View {
    let node: ViewDocument.Node
    let assets: ViewDocumentAssets
    let appearance: ViewDocumentAppearance
    let policy: ViewDocumentView.Policy

    var body: some View {
        let styled = node.modifiers.reduce(content()) { view, modifier in
            modifier.applying(to: view, appearance: appearance)
        }
        let accessible = accessibility(styled)
        if let animation = node.animation {
            ViewDocumentAnimatedView(animation: animation, policy: policy, content: accessible)
        } else {
            accessible
        }
    }

    private func content() -> AnyView {
        switch node.content {
            case let .text(text): AnyView(Text(verbatim: text))
            case let .image(asset): AnyView(assets.images[asset]!.resizable().scaledToFit())
            case let .raster(descriptor): AnyView(ViewDocumentImage(
                    image: assets.images[descriptor.asset]!,
                    sizing: descriptor.sizing,
                ))
            case let .symbol(symbol): AnyView(assets.symbols[symbol]!)
            case let .shape(shape): AnyView(ViewDocumentShape(descriptor: shape))
            case let .spacer(minimum): AnyView(Spacer(minLength: minimum))
            case let .group(axis, alignment, spacing, children):
                AnyView(ViewDocumentGroupView(
                    axis: axis,
                    alignment: alignment,
                    spacing: spacing,
                    children: children,
                    assets: assets,
                    appearance: appearance,
                    policy: policy,
                ))
        }
    }

    private func accessibility(_ content: AnyView) -> AnyView {
        switch node.accessibility {
            case .automatic: content
            case .hidden: AnyView(content.accessibilityHidden(true))
            case let .label(label): AnyView(content.accessibilityLabel(Text(verbatim: label)))
            case .combine: AnyView(content.accessibilityElement(children: .combine))
            case .contain: AnyView(content.accessibilityElement(children: .contain))
        }
    }
}
