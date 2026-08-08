import RegionKit

/// One feature in the region-map legend: its display identity, optional tracked
/// region, and the number of polygon rings it draws.
struct RegionMapLegendGroup: Identifiable {
    let title: String
    let region: Region?
    var outlineCount: Int

    var id: String {
        title
    }
}
