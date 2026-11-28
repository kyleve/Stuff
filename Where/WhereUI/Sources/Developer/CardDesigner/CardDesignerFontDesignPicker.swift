#if DEBUG
    import SwiftUI

    struct CardDesignerFontDesignPicker: View {
        @Binding var selection: CardDesignerConfiguration.FontDesign

        var body: some View {
            Picker(String(localized: .cardDesignerDesign), selection: $selection) {
                ForEach(CardDesignerConfiguration.FontDesign.allCases, id: \.self) { design in
                    Text(design.localizedName).tag(design)
                }
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerFontDesignPicker(selection: $card.regionNameTypography.design) }
    }
#endif
