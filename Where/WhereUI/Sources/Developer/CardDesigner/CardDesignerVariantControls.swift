#if DEBUG
    import SwiftUI

    struct CardDesignerVariantControls: View {
        @Binding var card: CardDesignerConfiguration.Card
        let reset: (CardDesignerModel.Section) -> Void

        var body: some View {
            Group {
                Section {
                    CardDesignerCGFloatControl(
                        title: .cardDesignerCornerRadius,
                        value: $card.cornerRadius,
                        range: 0 ... 60,
                        step: 1,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerPadding,
                        value: $card.padding,
                        range: 0 ... 40,
                        step: 1,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerContentSpacing,
                        value: $card.contentSpacing,
                        range: 0 ... 30,
                        step: 1,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerProgressHeight,
                        value: $card.progressBarHeight,
                        range: 1 ... 20,
                        step: 0.5,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerFallbackWatermarkSize,
                        value: $card.watermarkFontSize,
                        range: 40 ... 240,
                        step: 1,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerWatermarkOffsetX,
                        value: $card.watermarkOffset.x,
                        range: -80 ... 80,
                        step: 1,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerWatermarkOffsetY,
                        value: $card.watermarkOffset.y,
                        range: -80 ... 80,
                        step: 1,
                    )
                } header: {
                    CardDesignerSectionHeader(title: .cardDesignerCard, reset: { reset(.card) })
                }

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
                        reset: { reset(.typography) },
                    )
                }

                Section {
                    CardDesignerEntryStampControls(stamp: $card.entryStamp)
                } header: {
                    CardDesignerSectionHeader(
                        title: .cardDesignerEntryStamp,
                        reset: { reset(.entryStamp) },
                    )
                }

                Section {
                    CardDesignerArtworkControls(
                        usesRegionShape: $card.usesRegionShape,
                        regionShape: $card.regionShape,
                    )
                } header: {
                    CardDesignerSectionHeader(
                        title: .cardDesignerRegionArtwork,
                        reset: { reset(.regionArtwork) },
                    )
                }

                if card.usesRegionShape {
                    Section {
                        CardDesignerMicroprintControls(border: $card.regionShape.securityBorder)
                    } header: {
                        CardDesignerSectionHeader(
                            title: .cardDesignerMicroprint,
                            reset: { reset(.microprint) },
                        )
                    }
                }

                Section {
                    CardDesignerCGFloatControl(
                        title: .cardDesignerWobble,
                        value: $card.rosette.wobble,
                        range: 0 ... 12,
                        step: 0.5,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerLineWidth,
                        value: $card.rosette.lineWidth,
                        range: 0 ... 6,
                        step: 0.25,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerPrimaryRingSpacing,
                        value: $card.rosette.primaryRingSpacing,
                        range: 4 ... 40,
                        step: 0.5,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerSecondaryRingSpacing,
                        value: $card.rosette.secondaryRingSpacing,
                        range: 4 ... 40,
                        step: 0.5,
                    )
                } header: {
                    CardDesignerSectionHeader(
                        title: .cardDesignerRosettes,
                        reset: { reset(.rosettes) },
                    )
                }

                Section {
                    CardDesignerDoubleControl(
                        title: .cardDesignerIntensity,
                        value: $card.sheen.intensity,
                        range: 0 ... 1,
                        step: 0.01,
                    )
                    CardDesignerDoubleControl(
                        title: .cardDesignerStaticGlint,
                        value: $card.sheen.staticGlintIntensity,
                        range: 0 ... 1,
                        step: 0.01,
                    )
                    CardDesignerDoubleControl(
                        title: .cardDesignerStaticRoll,
                        value: $card.sheen.staticRoll,
                        range: -1 ... 1,
                        step: 0.05,
                    )
                    CardDesignerDoubleControl(
                        title: .cardDesignerStaticPitch,
                        value: $card.sheen.staticPitch,
                        range: -1 ... 1,
                        step: 0.05,
                    )
                } header: {
                    CardDesignerSectionHeader(title: .cardDesignerSheen, reset: { reset(.sheen) })
                }

                Section {
                    DisclosureGroup(String(localized: .cardDesignerGlow)) {
                        CardDesignerDoubleControl(
                            title: .cardDesignerOpacity,
                            value: $card.glow.opacity,
                            range: 0 ... 1,
                            step: 0.01,
                        )
                        CardDesignerCGFloatControl(
                            title: .cardDesignerRadius,
                            value: $card.glow.radius,
                            range: 0 ... 80,
                            step: 1,
                        )
                        CardDesignerCGFloatControl(
                            title: .cardDesignerOffsetY,
                            value: $card.glow.offsetY,
                            range: -20 ... 50,
                            step: 1,
                        )
                    }
                    DisclosureGroup(String(localized: .cardDesignerLift)) {
                        CardDesignerDoubleControl(
                            title: .cardDesignerOpacity,
                            value: $card.lift.opacity,
                            range: 0 ... 1,
                            step: 0.01,
                        )
                        CardDesignerCGFloatControl(
                            title: .cardDesignerRadius,
                            value: $card.lift.radius,
                            range: 0 ... 80,
                            step: 1,
                        )
                        CardDesignerCGFloatControl(
                            title: .cardDesignerOffsetY,
                            value: $card.lift.offsetY,
                            range: -20 ... 50,
                            step: 1,
                        )
                    }
                } header: {
                    CardDesignerSectionHeader(
                        title: .cardDesignerShadows,
                        reset: { reset(.shadows) },
                    )
                }
            }
        }
    }

    #Preview {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            CardDesignerVariantControls(card: $configuration.regular, reset: { _ in })
        }
    }
#endif
