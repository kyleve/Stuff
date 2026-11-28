import SwiftUI

private struct PresenceSelection: ViewModifier {
    let isSelected: Bool
    let tint: Color
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        content
            .overlay {
                if isSelected {
                    PresenceSelectionOutline(tint: tint, cornerRadius: cornerRadius)
                }
            }
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct PresenceSelectionOutline: View {
    @Environment(\.stylesheet) private var stylesheet
    let tint: Color
    let cornerRadius: CGFloat?

    var body: some View {
        let style = stylesheet.adaptivePane.selection
        RoundedRectangle(cornerRadius: cornerRadius ?? style.cornerRadius)
            .strokeBorder(
                style.borderTint.apply(to: tint),
                lineWidth: style.borderWidth,
            )
            .allowsHitTesting(false)
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

#if DEBUG
    #Preview {
        Color.gray.frame(width: 100, height: 70).presenceSelection(true, tint: .blue)
            .whereBroadwayRoot()
    }
#endif
