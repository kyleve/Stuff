#if DEBUG
    import SwiftUI

    struct CardDesignerInnerRingControls: View {
        @Binding var innerRing: CardDesignerConfiguration.DashedRing

        var body: some View {
            DisclosureGroup(String(localized: .cardDesignerInnerRing)) {
                CardDesignerDoubleControl(
                    title: .cardDesignerOpacity,
                    value: $innerRing.opacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerLineWidthFraction,
                    value: $innerRing.lineWidthFraction,
                    range: 0 ... 0.1,
                    step: 0.001,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerDashLength,
                    value: $innerRing.dashLengthFraction,
                    range: 0 ... 0.2,
                    step: 0.005,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerDashSpacing,
                    value: $innerRing.dashSpacingFraction,
                    range: 0 ... 0.2,
                    step: 0.005,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerInsetFraction,
                    value: $innerRing.insetFraction,
                    range: 0 ... 0.4,
                    step: 0.01,
                )
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerInnerRingControls(innerRing: $card.entryStamp.innerRing) }
    }
#endif
