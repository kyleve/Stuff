#if DEBUG
    import BroadwayUI
    import RegionKit
    import SFSafeSymbols
    import SnapshotKit
    import SwiftUI
    import WhereCore

    struct CardDesignerStudioView: View {
        let model: CardDesignerModel

        @State private var variant = CardDesignerConfiguration.Variant.regular
        @State private var previewColorScheme: ColorScheme?
        @State private var previewRegion = Region.newYork
        @State private var previewColor = RegionColorToken.indigo
        @State private var previewDays = 128
        @State private var previewYear = 2026
        @State private var isConfirmingResetAll = false
        @State private var tilt = TiltProvider()
        /// The user can override the preview mode; this seeds that runtime selection.
        @Environment(\.colorScheme) private var systemColorScheme
        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            @Bindable var model = model
            VStack(spacing: 0) {
                CardDesignerPreview(
                    configuration: model.configuration,
                    variant: variant,
                    colorScheme: previewColorScheme ?? systemColorScheme,
                    region: previewRegion,
                    color: previewColor,
                    days: previewDays,
                    year: previewYear,
                    tilt: tilt,
                )
                .padding()
                .background(.background)

                Divider()

                Form {
                    CardDesignerPreviewSection(
                        variant: $variant,
                        previewColorScheme: $previewColorScheme,
                        previewRegion: $previewRegion,
                        previewColor: $previewColor,
                        previewDays: $previewDays,
                        previewYear: $previewYear,
                        appliesToApp: $model.appliesToApp,
                    )

                    switch variant {
                        case .regular:
                            CardDesignerVariantControls(
                                card: $model.configuration.regular,
                                reset: { model.reset($0, variant: .regular) },
                            )
                        case .compact:
                            CardDesignerVariantControls(
                                card: $model.configuration.compact,
                                reset: { model.reset($0, variant: .compact) },
                            )
                    }

                    CardDesignerSharedControls(
                        shared: $model.configuration.shared,
                        reset: model.resetShared,
                    )
                    CardDesignerExportSection(configuration: model.configuration)
                }
            }
            .navigationTitle(String(localized: .cardDesignerTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CardDesignerResetMenu(
                        resetVariant: { model.reset(variant) },
                        resetShared: model.resetShared,
                        confirmResetAll: { isConfirmingResetAll = true },
                    )
                }
            }
            .confirmationDialog(
                String(localized: .cardDesignerResetAllTitle),
                isPresented: $isConfirmingResetAll,
                titleVisibility: .visible,
            ) {
                Button(String(localized: .cardDesignerResetAll), role: .destructive) {
                    model.resetAll()
                }
                Button(String(localized: .commonCancel), role: .cancel) {}
            } message: {
                Text(String(localized: .cardDesignerResetAllMessage))
            }
            .alert(
                String(localized: .cardDesignerPersistenceErrorTitle),
                isPresented: $model.isShowingPersistenceError,
                presenting: model.persistenceError,
            ) { _ in
                Button(String(localized: .commonOk), role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .preferredColorScheme(previewColorScheme)
            .onAppear {
                previewColorScheme = previewColorScheme ?? systemColorScheme
            }
            .observesTilt(tilt, enabled: stylesheet.card[variant.style].surface.usesReflection)
        }
    }

    extension CardDesignerStudioView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    CardDesignerStudioView(
                        model: CardDesignerModel(configuration: .standard),
                    )
                }
            }
        }
    }

    #Preview {
        CardDesignerStudioView.snapshotPreviews
    }

    extension CardDesignerStudioView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            CardDesignerStudioView.self,
            title: "Card Designer Studio",
        ) { _ in
            CardDesignerStudioView(model: CardDesignerModel(configuration: .standard))
        }
    }

    private struct CardDesignerResetMenu: View {
        let resetVariant: () -> Void
        let resetShared: () -> Void
        let confirmResetAll: () -> Void

        var body: some View {
            Menu {
                Button(String(localized: .cardDesignerResetVariant)) {
                    resetVariant()
                }
                Button(
                    String(localized: .cardDesignerResetShared),
                    action: resetShared,
                )
                Button(String(localized: .cardDesignerResetAll), role: .destructive) {
                    confirmResetAll()
                }
            } label: {
                Label(
                    String(localized: .cardDesignerReset),
                    systemSymbol: .arrowCounterclockwise,
                )
            }
        }
    }

    private struct CardDesignerPreview: View {
        let configuration: CardDesignerConfiguration
        let variant: CardDesignerConfiguration.Variant
        let colorScheme: ColorScheme
        let region: Region
        let color: RegionColorToken
        let days: Int
        let year: Int
        let tilt: TiltProvider
        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            GlassEffectContainer(spacing: 16) {
                CardDesignerPreviewButton(
                    region: region,
                    days: days,
                    year: year,
                    variant: variant,
                    tilt: tilt,
                    previewStyle: previewStyle,
                    cardStyle: cardStyle,
                )
            }
            .environment(\.cardDesignerConfiguration, configuration)
            .environment(\.colorScheme, colorScheme)
            .bMode(.init(colorScheme))
        }

        private var cardStyle: WhereStylesheet.CardStyle {
            configuration.resolve(over: stylesheet.card, colorScheme: colorScheme)[variant.style]
        }

        private var previewStyle: RegionStyle {
            let fallback = RegionAppearanceCatalog.defaultAppearance(for: region)
            return RegionStyle(
                symbol: fallback.symbolName.sfSymbol,
                emoji: fallback.emoji,
                tint: color.color,
            )
        }
    }

    #Preview("Card") {
        @Previewable @State var tilt = TiltProvider()
        CardDesignerPreview(
            configuration: .standard,
            variant: .regular,
            colorScheme: .light,
            region: .newYork,
            color: .indigo,
            days: 128,
            year: 2026,
            tilt: tilt,
        )
        .padding()
        .whereBroadwayRoot()
    }

    private struct CardDesignerPreviewButton: View {
        let region: Region
        let days: Int
        let year: Int
        let variant: CardDesignerConfiguration.Variant
        let tilt: TiltProvider
        let previewStyle: RegionStyle
        let cardStyle: WhereStylesheet.CardStyle

        var body: some View {
            Button(action: {}) {
                RegionSummaryCard(
                    regionDays: RegionDays(region: region, days: days),
                    caption: String(localized: .cardDesignerPreviewCaption),
                    variant: variant.style,
                    interactive: true,
                    year: year,
                    tilt: tilt,
                    styleOverride: previewStyle,
                )
            }
            .buttonStyle(cardStyle.buttonStyle(tint: previewStyle.tint))
        }
    }

    private struct CardDesignerVariantControls: View {
        @Binding var card: CardDesignerConfiguration.Card
        let reset: (CardDesignerModel.Section) -> Void

        var body: some View {
            CardDesignerCardGeometrySection(card: $card, reset: { reset(.card) })

            CardDesignerTypographySection(card: $card, reset: { reset(.typography) })

            CardDesignerStampSection(stamp: $card.entryStamp, reset: { reset(.entryStamp) })

            CardDesignerArtworkSection(card: $card, reset: { reset(.regionArtwork) })

            if card.usesRegionShape {
                CardDesignerMicroprintSection(
                    border: $card.regionShape.securityBorder,
                    reset: { reset(.microprint) },
                )
            }

            CardDesignerRosetteSection(rosette: $card.rosette, reset: { reset(.rosettes) })

            CardDesignerSheenSection(sheen: $card.sheen, reset: { reset(.sheen) })

            CardDesignerShadowsSection(card: $card, reset: { reset(.shadows) })
        }
    }

    #Preview("VariantControls") {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            CardDesignerVariantControls(card: $configuration.regular, reset: { _ in })
        }
    }

    private struct CardDesignerMicroprintSection: View {
        @Binding var border: CardDesignerConfiguration.SecurityBorder
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerMicroprintControls(border: $border)
            } header: {
                CardDesignerSectionHeader(
                    title: .cardDesignerMicroprint,
                    reset: { reset() },
                )
            }
        }
    }

    #Preview("MicroprintSection") {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerMicroprintSection(border: $card.regionShape.securityBorder, reset: {}) }
    }

    private struct CardDesignerShadowsSection: View {
        @Binding var card: CardDesignerConfiguration.Card
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerShadowControls(title: .cardDesignerGlow, shadow: $card.glow)
                CardDesignerShadowControls(title: .cardDesignerLift, shadow: $card.lift)
            } header: {
                CardDesignerSectionHeader(
                    title: .cardDesignerShadows,
                    reset: { reset() },
                )
            }
        }
    }

    #Preview("ShadowsSection") {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerShadowsSection(card: $card, reset: {}) }
    }

    private struct CardDesignerStampSection: View {
        @Binding var stamp: CardDesignerConfiguration.EntryStamp
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerEntryStampControls(stamp: $stamp)
            } header: {
                CardDesignerSectionHeader(
                    title: .cardDesignerEntryStamp,
                    reset: { reset() },
                )
            }
        }
    }

    #Preview("StampSection") {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerStampSection(stamp: $card.entryStamp, reset: {}) }
    }

    private struct CardDesignerEntryStampControls: View {
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
            CardDesignerOuterRingControls(outerRing: $stamp.outerRing)
            CardDesignerInnerRingControls(innerRing: $stamp.innerRing)
            CardDesignerStampContentControls(content: $stamp.content)
            Toggle(String(localized: .cardDesignerShowArc), isOn: $stamp.showsArc)
            if stamp.showsArc {
                CardDesignerArcControls(arc: $stamp.arc)
            }
        }
    }

    #Preview("EntryStampControls") {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            Section {
                CardDesignerEntryStampControls(stamp: $configuration.regular.entryStamp)
            }
        }
    }

    private struct CardDesignerOuterRingControls: View {
        @Binding var outerRing: CardDesignerConfiguration.Ring

        var body: some View {
            DisclosureGroup(String(localized: .cardDesignerOuterRing)) {
                CardDesignerDoubleControl(
                    title: .cardDesignerOpacity,
                    value: $outerRing.opacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerLineWidthFraction,
                    value: $outerRing.lineWidthFraction,
                    range: 0 ... 0.1,
                    step: 0.001,
                )
            }
        }
    }

    #Preview("OuterRingControls") {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerOuterRingControls(outerRing: $card.entryStamp.outerRing) }
    }

    private struct CardDesignerArtworkSection: View {
        @Binding var card: CardDesignerConfiguration.Card
        let reset: () -> Void

        var body: some View {
            Section {
                CardDesignerArtworkControls(
                    usesRegionShape: $card.usesRegionShape,
                    regionShape: $card.regionShape,
                )
            } header: {
                CardDesignerSectionHeader(
                    title: .cardDesignerRegionArtwork,
                    reset: { reset() },
                )
            }
        }
    }

    #Preview("ArtworkSection") {
        @Previewable @State var card = CardDesignerConfiguration.standard.regular
        Form { CardDesignerArtworkSection(card: $card, reset: {}) }
    }

    private struct CardDesignerArtworkControls: View {
        @Binding var usesRegionShape: Bool
        @Binding var regionShape: CardDesignerConfiguration.RegionShape

        var body: some View {
            Toggle(String(localized: .cardDesignerUseRegionOutline), isOn: $usesRegionShape)
            if usesRegionShape {
                CardDesignerArtworkLayerControls(
                    title: .cardDesignerWatermark,
                    artwork: $regionShape.watermark,
                )
                CardDesignerArtworkLayerControls(
                    title: .cardDesignerStampArtwork,
                    artwork: $regionShape.stamp,
                )
            }
        }
    }

    #Preview("ArtworkControls") {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            Section {
                CardDesignerArtworkControls(
                    usesRegionShape: $configuration.regular.usesRegionShape,
                    regionShape: $configuration.regular.regionShape,
                )
            }
        }
    }
#endif
