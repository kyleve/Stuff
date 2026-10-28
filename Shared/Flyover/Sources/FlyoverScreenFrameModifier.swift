import SwiftUI

/// Shared card surface for one Flyover overview frame.
struct FlyoverScreenFrameModifier: ViewModifier {
    @Environment(\.flyoverStylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet.screen
        content
            .background(style.background)
            .clipShape(.rect(cornerRadius: style.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .stroke(.quaternary, lineWidth: style.borderWidth)
            }
            .shadow(
                color: style.shadow.color.opacity(style.shadow.opacity),
                radius: style.shadow.radius,
                y: style.shadow.offsetY,
            )
    }
}

extension View {
    func flyoverScreenFrame() -> some View {
        modifier(FlyoverScreenFrameModifier())
    }
}
