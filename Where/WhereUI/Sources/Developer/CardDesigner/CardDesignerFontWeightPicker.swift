#if DEBUG
    import SwiftUI

    struct CardDesignerFontWeightPicker: View {
        @Binding var selection: CardDesignerConfiguration.FontWeight

        var body: some View {
            Picker(String(localized: .cardDesignerWeight), selection: $selection) {
                ForEach(CardDesignerConfiguration.FontWeight.allCases, id: \.self) { weight in
                    Text(weight.localizedName).tag(weight)
                }
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerFontWeightPicker(selection: $card.regionNameTypography.weight) }
    }
#endif
