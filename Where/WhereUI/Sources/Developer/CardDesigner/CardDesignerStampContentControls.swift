#if DEBUG
    import SwiftUI

    struct CardDesignerStampContentControls: View {
        @Binding var content: CardDesignerConfiguration.StampContent

        var body: some View {
            DisclosureGroup(String(localized: .cardDesignerStampContent)) {
                CardDesignerCGFloatControl(
                    title: .cardDesignerSpacingFraction,
                    value: $content.spacingFraction,
                    range: 0 ... 0.2,
                    step: 0.005,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerArtworkWidth,
                    value: $content.artworkExtent.width,
                    range: 0.1 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerArtworkHeight,
                    value: $content.artworkExtent.height,
                    range: 0.1 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerOpacity,
                    value: $content.opacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerFractionalTypographyControls(
                    title: .cardDesignerSymbolTypography,
                    typography: $content.symbolFont,
                )
                CardDesignerFractionalTypographyControls(
                    title: .cardDesignerYearTypography,
                    typography: $content.yearFont,
                )
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerStampContentControls(content: $card.entryStamp.content) }
    }
#endif
