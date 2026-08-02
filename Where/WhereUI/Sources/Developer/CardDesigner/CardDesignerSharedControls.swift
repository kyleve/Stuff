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
#endif
