import Foundation

/// A stable, storable SF Symbol identifier offered for a region's appearance.
///
/// Raw values are persisted in SwiftData, CloudKit, widget snapshots, and
/// backups. Keep existing values stable and append new cases when the picker
/// gains another symbol.
public enum RegionSymbol: String, CaseIterable, Codable, Hashable, Sendable {
    case mappinCircleFill = "mappin.circle.fill"
    case locationFill = "location.fill"
    case mapFill = "map.fill"
    case flagFill = "flag.fill"
    case houseFill = "house.fill"
    case building2 = "building.2"
    case building2Fill = "building.2.fill"
    case buildingColumnsFill = "building.columns.fill"
    case tentFill = "tent.fill"
    case sunMax = "sun.max"
    case sunMaxFill = "sun.max.fill"
    case moonStarsFill = "moon.stars.fill"
    case cloudFill = "cloud.fill"
    case snowflake
    case leafFill = "leaf.fill"
    case treeFill = "tree.fill"
    case mountain2Fill = "mountain.2.fill"
    case waterWaves = "water.waves"
    case airplane
    case carFill = "car.fill"
    case tramFill = "tram.fill"
    case sailboatFill = "sailboat.fill"
    case starFill = "star.fill"
    case heartFill = "heart.fill"
    case flameFill = "flame.fill"
    case boltFill = "bolt.fill"
    case globeAmericasFill = "globe.americas.fill"
    case beachUmbrellaFill = "beach.umbrella.fill"
    case cameraFill = "camera.fill"
    case sparkles
    case locationMagnifyingglass = "location.magnifyingglass"
}
