import SFSafeSymbols
import WhereCore

extension RegionSymbol {
    /// The availability-checked SF Symbol rendered for this persisted value.
    public var sfSymbol: SFSymbol {
        switch self {
            case .mappinCircleFill: .mappinCircleFill
            case .locationFill: .locationFill
            case .mapFill: .mapFill
            case .flagFill: .flagFill
            case .houseFill: .houseFill
            case .building2: .building2
            case .building2Fill: .building2Fill
            case .buildingColumnsFill: .buildingColumnsFill
            case .tentFill: .tentFill
            case .sunMax: .sunMax
            case .sunMaxFill: .sunMaxFill
            case .moonStarsFill: .moonStarsFill
            case .cloudFill: .cloudFill
            case .snowflake: .snowflake
            case .leafFill: .leafFill
            case .treeFill: .treeFill
            case .mountain2Fill: .mountain2Fill
            case .waterWaves: .waterWaves
            case .airplane: .airplane
            case .carFill: .carFill
            case .tramFill: .tramFill
            case .sailboatFill: .sailboatFill
            case .starFill: .starFill
            case .heartFill: .heartFill
            case .flameFill: .flameFill
            case .boltFill: .boltFill
            case .globeAmericasFill: .globeAmericasFill
            case .beachUmbrellaFill: .beachUmbrellaFill
            case .cameraFill: .cameraFill
            case .sparkles: .sparkles
            case .locationMagnifyingglass: .locationMagnifyingglass
        }
    }
}
