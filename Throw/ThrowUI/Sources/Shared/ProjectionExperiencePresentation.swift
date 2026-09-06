import SFSafeSymbols
import ThrowCore

/// Localized, UI-only metadata for one compile-time projection experience.
struct ProjectionExperiencePresentation {
    let id: ProjectionExperienceID

    var name: String {
        switch id {
            case .airAndSpace: String(localized: .experienceAirAndSpace)
            case .transit: String(localized: .experienceTransit)
            #if DEBUG
                case .testing: String(localized: .experienceUnknown)
            #endif
        }
    }

    var description: String {
        switch id {
            case .airAndSpace: String(localized: .experienceAirAndSpaceDescription)
            case .transit: String(localized: .experienceTransitDescription)
            #if DEBUG
                case .testing: String(localized: .experienceUnknownDescription)
            #endif
        }
    }

    var visibleContentLabel: String {
        switch ProjectionExperienceCatalog.standard[id]?.visibleContentKind {
            case .aircraft: String(localized: .dashboardAircraftVisible)
            case .vehicles: String(localized: .viewsVehiclesVisible)
            case .objects, nil: String(localized: .viewsContentVisible)
        }
    }

    var symbol: SFSymbol {
        switch id {
            case .airAndSpace: .airplane
            case .transit: .tramFill
            #if DEBUG
                case .testing: .rectangleStack
            #endif
        }
    }
}
