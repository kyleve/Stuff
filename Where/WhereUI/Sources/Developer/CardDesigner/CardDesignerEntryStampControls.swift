#if DEBUG
    import SwiftUI

    struct CardDesignerEntryStampControls: View {
        @Binding var stamp: CardDesignerConfiguration.EntryStamp

        var body: some View {
            CardDesignerCGFloatControl(
                title: .cardDesignerStampSize,
                value: $stamp.size,
                range: 32 ... 140,
                step: 1,
            )
            CardDesignerDoubleControl(
                title: .cardDesignerRotation,
                value: $stamp.rotationDegrees,
                range: -30 ... 30,
                step: 1,
            )
            DisclosureGroup(String(localized: .cardDesignerOuterRing)) {
                CardDesignerDoubleControl(
                    title: .cardDesignerOpacity,
                    value: $stamp.outerRing.opacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerLineWidthFraction,
                    value: $stamp.outerRing.lineWidthFraction,
                    range: 0 ... 0.1,
                    step: 0.001,
                )
            }
            DisclosureGroup(String(localized: .cardDesignerInnerRing)) {
                CardDesignerDoubleControl(
                    title: .cardDesignerOpacity,
                    value: $stamp.innerRing.opacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerLineWidthFraction,
                    value: $stamp.innerRing.lineWidthFraction,
                    range: 0 ... 0.1,
                    step: 0.001,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerDashLength,
                    value: $stamp.innerRing.dashLengthFraction,
                    range: 0 ... 0.2,
                    step: 0.005,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerDashSpacing,
                    value: $stamp.innerRing.dashSpacingFraction,
                    range: 0 ... 0.2,
                    step: 0.005,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerInsetFraction,
                    value: $stamp.innerRing.insetFraction,
                    range: 0 ... 0.4,
                    step: 0.01,
                )
            }
            DisclosureGroup(String(localized: .cardDesignerStampContent)) {
                CardDesignerCGFloatControl(
                    title: .cardDesignerSpacingFraction,
                    value: $stamp.content.spacingFraction,
                    range: 0 ... 0.2,
                    step: 0.005,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerArtworkWidth,
                    value: $stamp.content.artworkExtent.width,
                    range: 0.1 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerArtworkHeight,
                    value: $stamp.content.artworkExtent.height,
                    range: 0.1 ... 1,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerOpacity,
                    value: $stamp.content.opacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerFractionalTypographyControls(
                    title: .cardDesignerSymbolTypography,
                    typography: $stamp.content.symbolFont,
                )
                CardDesignerFractionalTypographyControls(
                    title: .cardDesignerYearTypography,
                    typography: $stamp.content.yearFont,
                )
            }
            Toggle(String(localized: .cardDesignerShowArc), isOn: $stamp.showsArc)
            if stamp.showsArc {
                DisclosureGroup(String(localized: .cardDesignerArc)) {
                    CardDesignerCGFloatControl(
                        title: .cardDesignerRadiusFraction,
                        value: $stamp.arc.radiusFraction,
                        range: 0.1 ... 0.6,
                        step: 0.01,
                    )
                    CardDesignerDoubleControl(
                        title: .cardDesignerOpacity,
                        value: $stamp.arc.opacity,
                        range: 0 ... 1,
                        step: 0.01,
                    )
                    CardDesignerDoubleControl(
                        title: .cardDesignerMaximumSweep,
                        value: $stamp.arc.maximumSweepDegrees,
                        range: 0 ... 360,
                        step: 1,
                    )
                    CardDesignerDoubleControl(
                        title: .cardDesignerSweepPerCharacter,
                        value: $stamp.arc.sweepDegreesPerCharacter,
                        range: 1 ... 30,
                        step: 0.5,
                    )
                    CardDesignerFractionalTypographyControls(
                        title: .cardDesignerArcTypography,
                        typography: $stamp.arc.font,
                    )
                }
            }
        }
    }

    #Preview {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            Section {
                CardDesignerEntryStampControls(stamp: $configuration.regular.entryStamp)
            }
        }
    }
#endif
