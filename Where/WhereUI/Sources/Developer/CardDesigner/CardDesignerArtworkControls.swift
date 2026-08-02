#if DEBUG
    import SwiftUI

    struct CardDesignerArtworkControls: View {
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
#endif
