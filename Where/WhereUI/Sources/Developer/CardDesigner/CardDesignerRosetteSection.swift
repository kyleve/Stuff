#if DEBUG
    import SwiftUI

    struct CardDesignerRosetteSection: View {
        @Binding var rosette: CardDesignerConfiguration.Rosette
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerCGFloatControl(
                    title: .cardDesignerWobble,
                    value: $rosette.wobble,
                    range: 0 ... 12,
                    step: 0.5,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerLineWidth,
                    value: $rosette.lineWidth,
                    range: 0 ... 6,
                    step: 0.25,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerPrimaryRingSpacing,
                    value: $rosette.primaryRingSpacing,
                    range: 4 ... 40,
                    step: 0.5,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerSecondaryRingSpacing,
                    value: $rosette.secondaryRingSpacing,
                    range: 4 ... 40,
                    step: 0.5,
                )
            } header: {
                CardDesignerSectionHeader(
                    title: .cardDesignerRosettes,
                    reset: reset,
                )
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerRosetteSection(rosette: $card.rosette, reset: {}) }
    }
#endif
