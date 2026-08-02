#if DEBUG
    import RegionKit
    import SnapshotKit
    import SwiftUI
    import WhereCore

    struct CardDesignerStudioView: View {
        let model: CardDesignerModel

        @State private var variant = CardDesignerConfiguration.Variant.regular
        @State private var previewColorScheme = ColorScheme.light
        @State private var previewRegion = Region.newYork
        @State private var previewColor = RegionColorToken.indigo
        @State private var previewDays = 128
        @State private var previewYear = 2026
        @State private var isConfirmingResetAll = false
        @State private var tilt = TiltProvider()

        var body: some View {
            @Bindable var model = model
            VStack(spacing: 0) {
                CardDesignerPreview(
                    configuration: model.configuration,
                    variant: variant,
                    colorScheme: previewColorScheme,
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
                    Section {
                        Picker(String(localized: .cardDesignerVariant), selection: $variant) {
                            ForEach(
                                CardDesignerConfiguration.Variant.allCases,
                                id: \.self,
                            ) { variant in
                                Text(variant.localizedName).tag(variant)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker(
                            String(localized: .cardDesignerAppearance),
                            selection: $previewColorScheme,
                        ) {
                            Text(String(localized: .cardDesignerLight)).tag(ColorScheme.light)
                            Text(String(localized: .cardDesignerDark)).tag(ColorScheme.dark)
                        }
                        .pickerStyle(.segmented)

                        Picker(String(localized: .cardDesignerRegion), selection: $previewRegion) {
                            ForEach(RegionCatalog.shared.all, id: \.self) { region in
                                Text(region.localizedName).tag(region)
                            }
                        }

                        Picker(String(localized: .cardDesignerColor), selection: $previewColor) {
                            ForEach(RegionAppearanceCatalog.colors, id: \.self) { color in
                                Label {
                                    Text(WhereFormat.regionColorAccessibility(color))
                                } icon: {
                                    Circle().fill(color.color)
                                }
                                .tag(color)
                            }
                        }

                        Stepper(
                            String(localized: .cardDesignerDays(previewDays)),
                            value: $previewDays,
                            in: 0 ... 366,
                        )
                        Stepper(
                            String(localized: .cardDesignerYear(previewYear)),
                            value: $previewYear,
                            in: 1900 ... 2200,
                        )
                        Toggle(
                            String(localized: .cardDesignerApplyToApp),
                            isOn: $model.appliesToApp,
                        )
                    } header: {
                        Text(String(localized: .cardDesignerPreview))
                    } footer: {
                        Text(String(localized: .cardDesignerApplyFooter))
                    }

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
                    Menu(
                        String(localized: .cardDesignerReset),
                        systemImage: "arrow.counterclockwise",
                    ) {
                        Button(String(localized: .cardDesignerResetVariant)) {
                            model.reset(variant)
                        }
                        Button(
                            String(localized: .cardDesignerResetShared),
                            action: model.resetShared,
                        )
                        Button(String(localized: .cardDesignerResetAll), role: .destructive) {
                            isConfirmingResetAll = true
                        }
                    }
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
            .onAppear { tilt.start() }
            .onDisappear { tilt.stop() }
        }
    }

    extension CardDesignerStudioView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .phoneLightDark) {
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
#endif
