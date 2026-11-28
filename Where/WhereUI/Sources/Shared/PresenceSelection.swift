import SwiftUI

private struct PresenceSelection: ViewModifier {
    let isSelected: Bool
    let tint: Color
    let cornerRadius: CGFloat?
    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        content
            .overlay {
                if isSelected {
                    let style = stylesheet.adaptivePane.selection
                    RoundedRectangle(cornerRadius: cornerRadius ?? style.cornerRadius)
                        .strokeBorder(
                            style.borderTint.apply(to: tint),
                            lineWidth: style.borderWidth,
                        )
                        .allowsHitTesting(false)
                }
            }
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension View {
    func presenceSelection(
        _ isSelected: Bool,
        tint: Color,
        cornerRadius: CGFloat? = nil,
    ) -> some View {
        modifier(PresenceSelection(isSelected: isSelected, tint: tint, cornerRadius: cornerRadius))
    }
}
