#if DEBUG
    import SwiftUI

    struct CardDesignerTypographyControls: View {
        let title: LocalizedStringResource
        @Binding var typography: CardDesignerConfiguration.Typography

        var body: some View {
            DisclosureGroup {
                Picker(String(localized: .cardDesignerSizeMode), selection: $typography.sizeMode) {
                    ForEach(CardDesignerConfiguration.SizeMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                if typography.sizeMode == .fixed {
                    CardDesignerCGFloatControl(
                        title: .cardDesignerPointSize,
                        value: $typography.fixedSize,
                        range: 8 ... 72,
                        step: 0.5,
                    )
                } else {
                    Picker(
                        String(localized: .cardDesignerTextStyle),
                        selection: $typography.textStyle,
                    ) {
                        ForEach(CardDesignerConfiguration.TextStyle.allCases, id: \.self) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                }
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

    #Preview {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            Section {
                CardDesignerTypographyControls(
                    title: .cardDesignerRegionName,
                    typography: $configuration.regular.regionNameTypography,
                )
            }
        }
    }
#endif
