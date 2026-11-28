#if DEBUG
    import SwiftUI

    struct CardDesignerSharedControls: View {
        @Binding var shared: CardDesignerConfiguration.Shared
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerDoubleControl(
                    title: .cardDesignerWatermarkOpacity,
                    value: $shared.watermarkOpacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerGlassTintOpacity,
                    value: $shared.glassTintOpacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerNameOpacity,
                    value: $shared.nameOpacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerPrimaryRosetteOpacity,
                    value: $shared.primaryRosetteOpacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerSecondaryRosetteOpacity,
                    value: $shared.secondaryRosetteOpacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerSecurityPrintControls(
                    title: .cardDesignerLightInk,
                    securityPrint: $shared.lightSecurityPrint,
                )
                CardDesignerSecurityPrintControls(
                    title: .cardDesignerDarkInk,
                    securityPrint: $shared.darkSecurityPrint,
                )
            } header: {
                CardDesignerSectionHeader(title: .cardDesignerGlassAndInk, reset: reset)
            }
        }
    }

    #Preview {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            CardDesignerSharedControls(shared: $configuration.shared, reset: {})
        }
    }

    private struct CardDesignerSecurityPrintControls: View {
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
                CardDesignerBlendModePicker(selection: $securityPrint.blendMode)
            } label: {
                Text(title)
            }
        }
    }

    #Preview("SecurityPrintControls") {
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

    private struct CardDesignerBlendModePicker: View {
        @Binding var selection: CardDesignerBlendMode

        var body: some View {
            Picker(
                String(localized: .cardDesignerBlendMode),
                selection: $selection,
            ) {
                ForEach(CardDesignerBlendMode.allCases, id: \.self) { blendMode in
                    Text(blendMode.localizedName).tag(blendMode)
                }
            }
        }
    }

    #Preview("BlendModePicker") {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            CardDesignerBlendModePicker(selection: $configuration.shared.lightSecurityPrint
                .blendMode)
        }
    }
#endif
