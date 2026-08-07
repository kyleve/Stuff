#if DEBUG
    import SwiftUI

    struct CardDesignerSecurityPrintControls: View {
        let title: LocalizedStringResource
        @Binding var securityPrint: CardDesignerConfiguration.SecurityPrint

        var body: some View {
            DisclosureGroup {
                CardDesignerDoubleControl(
                    title: .cardDesignerWhiteMix,
                    value: $securityPrint.whiteMix,
                    range: 0 ... 1,
                    step: 0.01,
                )
                Picker(
                    String(localized: .cardDesignerBlendMode),
                    selection: $securityPrint.blendMode,
                ) {
                    ForEach(CardDesignerBlendMode.allCases, id: \.self) { blendMode in
                        Text(blendMode.localizedName).tag(blendMode)
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
                CardDesignerSecurityPrintControls(
                    title: .cardDesignerDarkInk,
                    securityPrint: $configuration.shared.darkSecurityPrint,
                )
            }
        }
    }
#endif
