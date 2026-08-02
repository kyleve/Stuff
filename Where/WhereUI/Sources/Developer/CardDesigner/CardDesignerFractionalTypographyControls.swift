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
                Picker(String(localized: .cardDesignerWeight), selection: $typography.weight) {
                    ForEach(CardDesignerConfiguration.FontWeight.allCases, id: \.self) { weight in
                        Text(weight.localizedName).tag(weight)
                    }
                }
                Picker(String(localized: .cardDesignerDesign), selection: $typography.design) {
                    ForEach(CardDesignerConfiguration.FontDesign.allCases, id: \.self) { design in
                        Text(design.localizedName).tag(design)
                    }
                }
            } label: {
                Text(title)
            }
        }
    }
#endif
