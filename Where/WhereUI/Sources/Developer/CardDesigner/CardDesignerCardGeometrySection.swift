#if DEBUG
    import SwiftUI

    struct CardDesignerCardGeometrySection: View {
        @Binding var card: CardDesignerConfiguration.Card
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerCGFloatControl(
                    title: .cardDesignerCornerRadius,
                    value: $card.cornerRadius,
                    range: 0 ... 60,
                    step: 1,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerPadding,
                    value: $card.padding,
                    range: 0 ... 40,
                    step: 1,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerContentSpacing,
                    value: $card.contentSpacing,
                    range: 0 ... 30,
                    step: 1,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerProgressHeight,
                    value: $card.progressBarHeight,
                    range: 1 ... 20,
                    step: 0.5,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerFallbackWatermarkSize,
                    value: $card.watermarkFontSize,
                    range: 40 ... 240,
                    step: 1,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerWatermarkOffsetX,
                    value: $card.watermarkOffset.x,
                    range: -80 ... 80,
                    step: 1,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerWatermarkOffsetY,
                    value: $card.watermarkOffset.y,
                    range: -80 ... 80,
                    step: 1,
                )
            } header: {
                CardDesignerSectionHeader(title: .cardDesignerCard, reset: { reset() })
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerCardGeometrySection(card: $card, reset: {}) }
    }
#endif
