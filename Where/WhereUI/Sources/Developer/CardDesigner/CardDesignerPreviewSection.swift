#if DEBUG
    import RegionKit
    import SnapshotKit
    import SwiftUI
    import WhereCore

    struct CardDesignerPreviewSection: View {
        @Binding var variant: CardDesignerConfiguration.Variant
        @Binding var previewColorScheme: ColorScheme?
        @Binding var previewRegion: Region
        @Binding var previewColor: RegionColorToken
        @Binding var previewDays: Int
        @Binding var previewYear: Int
        @Binding var appliesToApp: Bool

        var body: some View {
            Section {
                CardDesignerVariantPicker(selection: $variant)

                CardDesignerAppearancePicker(selection: $previewColorScheme)

                CardDesignerRegionPicker(selection: $previewRegion)

                CardDesignerColorPicker(selection: $previewColor)

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
                    isOn: $appliesToApp,
                )
            } header: {
                Text(String(localized: .cardDesignerPreview))
            } footer: {
                Text(String(localized: .cardDesignerApplyFooter))
            }
        }
    }

    private struct CardDesignerVariantPicker: View {
        @Binding var selection: CardDesignerConfiguration.Variant

        var body: some View {
            Picker(String(localized: .cardDesignerVariant), selection: $selection) {
                ForEach(
                    CardDesignerConfiguration.Variant.allCases,
                    id: \.self,
                ) { variant in
                    Text(variant.localizedName).tag(variant)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private struct CardDesignerAppearancePicker: View {
        @Binding var selection: ColorScheme?

        var body: some View {
            Picker(
                String(localized: .cardDesignerAppearance),
                selection: $selection,
            ) {
                Text(String(localized: .cardDesignerLight))
                    .tag(ColorScheme.light as ColorScheme?)
                Text(String(localized: .cardDesignerDark))
                    .tag(ColorScheme.dark as ColorScheme?)
            }
            .pickerStyle(.segmented)
        }
    }

    private struct CardDesignerRegionPicker: View {
        @Binding var selection: Region

        var body: some View {
            Picker(String(localized: .cardDesignerRegion), selection: $selection) {
                ForEach(RegionCatalog.shared.all, id: \.self) { region in
                    Text(region.localizedName).tag(region)
                }
            }
        }
    }

    private struct CardDesignerColorPicker: View {
        @Binding var selection: RegionColorToken

        var body: some View {
            Picker(String(localized: .cardDesignerColor), selection: $selection) {
                ForEach(RegionAppearanceCatalog.colors, id: \.self) { color in
                    Label {
                        Text(WhereFormat.regionColorAccessibility(color))
                    } icon: {
                        Circle().fill(color.color)
                    }
                    .tag(color)
                }
            }
        }
    }

    #Preview { CardDesignerStudioView.snapshotPreviews }
#endif
