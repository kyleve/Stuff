import RegionKit

/// Optional place labels. Region membership and day counts never depend on them.
protocol PlaceNaming: Sendable {
    func name(for coordinate: Coordinate) async -> String?
}
