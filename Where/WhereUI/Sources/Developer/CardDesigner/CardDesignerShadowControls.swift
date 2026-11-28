#if DEBUG
    import SwiftUI

    struct CardDesignerShadowControls: View {
        let title: LocalizedStringResource
        @Binding var shadow: CardDesignerConfiguration.Shadow

        var body: some View {
            DisclosureGroup(String(localized: title)) {
                CardDesignerDoubleControl(
                    title: .cardDesignerOpacity,
                    value: $shadow.opacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerRadius,
                    value: $shadow.radius,
                    range: 0 ... 80,
                    step: 1,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerOffsetY,
                    value: $shadow.offsetY,
                    range: -20 ... 50,
                    step: 1,
                )
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerShadowControls(title: .cardDesignerGlow, shadow: $card.glow) }
    }
#endif
