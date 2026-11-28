import MapKit
import RegionKit
import SwiftUI

struct RegionMapOverview: View {
    let data: RegionMapView.MapData
    let isLoading: Bool
    let selectedTitle: String?
    @Binding var cameraPosition: MapCameraPosition
    let color: (RegionOutline) -> Color
    let legendColor: (RegionMapLegendGroup) -> Color
    let select: (String?) -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: 0) {
            RegionOutlinesMap(
                geometry: data.geometry,
                selectedTitle: selectedTitle,
                frame: data.frame(for: selectedTitle),
                cameraPosition: $cameraPosition,
                color: color,
            )
            .frame(maxHeight: .infinity)
            .accessibilityLabel(String(localized: .regionMapMapAccessibility))
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            RegionMapLegend(
                kind: data.kind,
                groups: data.groups,
                selectedTitle: selectedTitle,
                color: legendColor,
                onSelect: select,
            )
            .frame(height: stylesheet.regionMap[.overview].height)
        }
    }
}

#if DEBUG
    #Preview { NavigationStack { RegionMapView() }.whereBroadwayRoot() }
#endif
