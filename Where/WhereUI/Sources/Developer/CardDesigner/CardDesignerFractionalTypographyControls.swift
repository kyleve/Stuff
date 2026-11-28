#if DEBUG
    import SwiftUI

    struct CardDesignerFractionalTypographyControls: View {
        let title: LocalizedStringResource
        @Binding var typography: CardDesignerConfiguration.FractionalTypography

        var body: some View {
            DisclosureGroup {
                CardDesignerCGFloatControl(
                    title: .cardDesignerSizeFraction,
                    value: $typography.sizeFraction,
                    range: 0.02 ... 0.6,
                    step: 0.01,
                )
                CardDesignerFontWeightPicker(selection: $typography.weight)
                CardDesignerFontDesignPicker(selection: $typography.design)
            } label: {
                Text(title)
            }
        }
    }

    #Preview {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            Section {
                CardDesignerFractionalTypographyControls(
                    title: .cardDesignerSymbolTypography,
                    typography: $configuration.regular.entryStamp.content.symbolFont,
                )
            }
        }
    }
#endif
