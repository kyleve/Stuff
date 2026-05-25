import Foundation

/// A simple planar polygon used for offline region attribution.
///
/// `vertices` is the exterior ring. Holes aren't modeled because the bundled
/// simplified region polygons don't use them. Point-in-polygon is the
/// standard even-odd ray-cast on lat/lng treated as planar (x = longitude,
/// y = latitude). This is accurate enough at the scale of US states / EU /
/// Canada and is fully deterministic for snapshot tests.
struct GeoPolygon: Hashable {
    let vertices: [Coordinate]

    func contains(_ coordinate: Coordinate) -> Bool {
        let n = vertices.count
        guard n >= 3 else { return false }
        let py = coordinate.latitude
        let px = coordinate.longitude
        var inside = false
        var j = n - 1
        for i in 0 ..< n {
            let yi = vertices[i].latitude
            let xi = vertices[i].longitude
            let yj = vertices[j].latitude
            let xj = vertices[j].longitude
            if (yi > py) != (yj > py) {
                let t = (py - yi) / (yj - yi)
                let xIntersect = xi + t * (xj - xi)
                if px < xIntersect {
                    inside.toggle()
                }
            }
            j = i
        }
        return inside
    }
}
