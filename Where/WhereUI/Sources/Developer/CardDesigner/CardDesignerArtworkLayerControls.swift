#if DEBUG
    import SwiftUI

    struct CardDesignerArtworkLayerControls: View {
        let title: LocalizedStringResource
        @Binding var artwork: CardDesignerConfiguration.Artwork

        var body: some View {
            DisclosureGroup {
                CardDesignerCGFloatControl(
                    title: .cardDesignerCenterX,
                    value: $artwork.center.x,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerCenterY,
                    value: $artwork.center.y,
                    range: 0 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerExtentWidth,
                    value: $artwork.extent.width,
                    range: 0.1 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerExtentHeight,
                    value: $artwork.extent.height,
                    range: 0.1 ... 1,
                    step: 0.01,
                )
                CardDesignerCGFloatControl(
                    title: .cardDesignerScale,
                    value: $artwork.scale,
                    range: 0.1 ... 2,
                    step: 0.01,
                )
                CardDesignerDoubleControl(
                    title: .cardDesignerFillOpacity,
                    value: $artwork.fillOpacity,
                    range: 0 ... 1,
                    step: 0.01,
                )
                Toggle(String(localized: .cardDesignerShowStroke), isOn: $artwork.showsStroke)
                if artwork.showsStroke {
                    CardDesignerDoubleControl(
                        title: .cardDesignerStrokeOpacity,
                        value: $artwork.stroke.opacity,
                        range: 0 ... 1,
                        step: 0.01,
                    )
                    CardDesignerCGFloatControl(
                        title: .cardDesignerStrokeWidth,
                        value: $artwork.stroke.width,
                        range: 0 ... 6,
                        step: 0.1,
                    )
                }
            } label: {
                Text(title)
            }
        }
    }

    #Preview {
        @Previewable @State var configuration = CardDesignerConfiguration.standard
        Form {
            Section {
                CardDesignerArtworkLayerControls(
                    title: .cardDesignerWatermark,
                    artwork: $configuration.regular.regionShape.watermark,
                )
            }
        }
    }
#endif
