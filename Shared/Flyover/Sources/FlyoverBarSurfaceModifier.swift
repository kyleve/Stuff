import SwiftUI

/// Shared material surface for Flyover's global and focused control bars.
struct FlyoverBarSurfaceModifier: ViewModifier {
    @Environment(\.flyoverStylesheet) private var stylesheet

    func body(content: Content) -> some View {
        content
            .controlSize(stylesheet.controlBar.controlSize)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
    }
}

extension View {
    func flyoverBarSurface() -> some View {
        modifier(FlyoverBarSurfaceModifier())
    }
}
