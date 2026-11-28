#if DEBUG
    import SwiftUI

    struct CardDesignerArcControls: View {
        @Binding var arc: CardDesignerConfiguration.Arc

        var body: some View {
            DisclosureGroup(String(localized: .cardDesignerArc)) {
                CardDesignerCGFloatControl(
                    title: .cardDesignerRadiusFraction,
                    value: $arc.radiusFraction,
                    range: 0.1 ... 0.6,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerOpacity,
                    value: $arc.opacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerMaximumSweep,
                    value: $arc.maximumSweepDegrees,
                    range: 0 ... 360,
                    step: 1,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerSweepPerCharacter,
                    value: $arc.sweepDegreesPerCharacter,
                    range: 1 ... 30,
                    step: 0.5,
                )
                CardDesignerFractionalTypographyControls(
                    title: .cardDesignerArcTypography,
                    typography: $arc.font,
                )
            }
        }
    }

    #Preview {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerArcControls(arc: $card.entryStamp.arc) }
    }
#endif
