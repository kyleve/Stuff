#if DEBUG
    import SwiftUI

    struct CardDesignerSheenSection: View {
        @Binding var sheen: CardDesignerConfiguration.Sheen
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerDoubleControl(
                    title: .cardDesignerIntensity,
                    value: $sheen.intensity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerStaticGlint,
                    value: $sheen.staticGlintIntensity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerStaticRoll,
                    value: $sheen.staticRoll,
                    range: -1 ... 1,
                    step: 0.05,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerStaticPitch,
                    value: $sheen.staticPitch,
                    range: -1 ... 1,
                    step: 0.05,
                )
            } header: {
                CardDesignerSectionHeader(title: .cardDesignerSheen, reset: { reset() })
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerSheenSection(sheen: $card.sheen, reset: {}) }
    }
#endif
