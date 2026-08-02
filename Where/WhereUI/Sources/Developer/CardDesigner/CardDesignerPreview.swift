#if DEBUG
    import RegionKit
    import SwiftUI
    import WhereCore

    struct CardDesignerPreview: View {
        let configuration: CardDesignerConfiguration
        let variant: CardDesignerConfiguration.Variant
        let colorScheme: ColorScheme
        let region: Region
        let color: RegionColorToken
        let days: Int
        let year: Int
        let tilt: TiltProvider

        var body: some View {
            GlassEffectContainer(spacing: 16) {
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
                .buttonStyle(.plain)
            }
            .environment(\.cardDesignerConfiguration, configuration)
            .environment(\.colorScheme, colorScheme)
        }

        private var previewStyle: RegionStyle {
            let fallback = RegionAppearanceCatalog.defaultAppearance(for: region)
            return RegionStyle(
                symbolName: fallback.symbolName,
                emoji: fallback.emoji,
                tint: color.color,
            )
        }
    }

    #Preview {
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
#endif
