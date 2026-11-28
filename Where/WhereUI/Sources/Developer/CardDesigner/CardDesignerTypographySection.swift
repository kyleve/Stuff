#if DEBUG
    import SwiftUI

    struct CardDesignerTypographySection: View {
        @Binding var card: CardDesignerConfiguration.Card
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerTypographyControls(
                    title: .cardDesignerRegionName,
                    typography: $card.regionNameTypography,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerTracking,
                    value: $card.regionNameTracking,
                    range: -5 ... 10,
                    step: 0.1,
                )
                CardDesignerTypographyControls(
                    title: .cardDesignerHeroNumber,
                    typography: $card.heroNumberTypography,
                )
                CardDesignerTypographyControls(
                    title: .cardDesignerDayUnit,
                    typography: $card.dayUnitTypography,
                )
            } header: {
                CardDesignerSectionHeader(
                    title: .cardDesignerTypography,
                    reset: { reset() },
                )
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerTypographySection(card: $card, reset: {}) }
    }

    private struct CardDesignerTypographyControls: View {
        let title: LocalizedStringResource
        @Binding var typography: CardDesignerConfiguration.Typography

        var body: some View {
            DisclosureGroup {
                CardDesignerSizeModePicker(selection: $typography.sizeMode)
                if typography.sizeMode == .fixed {
                    CardDesignerCGFloatControl(
                        title: .cardDesignerPointSize,
                        value: $typography.fixedSize,
                        range: 8 ... 72,
                        step: 0.5,
                    )
                } else {
                    CardDesignerTextStylePicker(selection: $typography.textStyle)
                }
                CardDesignerFontWeightPicker(selection: $typography.weight)
                CardDesignerFontDesignPicker(selection: $typography.design)
            } label: {
                Text(title)
            }
        }
    }

    #Preview("TypographyControls") {
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

    private struct CardDesignerSizeModePicker: View {
        @Binding var selection: CardDesignerConfiguration.SizeMode

        var body: some View {
            Picker(String(localized: .cardDesignerSizeMode), selection: $selection) {
                ForEach(CardDesignerConfiguration.SizeMode.allCases, id: \.self) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
        }
    }

    #Preview("SizeModePicker") {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerSizeModePicker(selection: $card.regionNameTypography.sizeMode) }
    }

    private struct CardDesignerTextStylePicker: View {
        @Binding var selection: CardDesignerConfiguration.TextStyle

        var body: some View {
            Picker(
                String(localized: .cardDesignerTextStyle),
                selection: $selection,
            ) {
                ForEach(CardDesignerConfiguration.TextStyle.allCases, id: \.self) { style in
                    Text(style.localizedName).tag(style)
                }
            }
        }
    }

    #Preview("TextStylePicker") {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerTextStylePicker(selection: $card.regionNameTypography.textStyle) }
    }
#endif
