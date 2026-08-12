import SwiftUI

extension View {
    /// Adds Liquid Glass only when the active component style asks for it.
    /// Theme selection stays in the stylesheet; customer-facing views keep one
    /// hierarchy and consume the resolved material decision.
    @ViewBuilder
    func optionalGlassSurface(
        _ isEnabled: Bool,
        tint: Color,
        in shape: some Shape,
    ) -> some View {
        if isEnabled {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            self
        }
    }
}
