import SFSafeSymbols
import ThrowCore

/// Localized, UI-only metadata for one compile-time projection experience.
struct ProjectionExperiencePresentation {
    let id: ProjectionExperienceID

    var name: String {
        if id == .airAndSpace { return String(localized: .experienceAirAndSpace) }
        if id == .transit { return String(localized: .experienceTransit) }
        return String(localized: .experienceUnknown)
    }

    var description: String {
        if id == .airAndSpace { return String(localized: .experienceAirAndSpaceDescription) }
        if id == .transit { return String(localized: .experienceTransitDescription) }
        return String(localized: .experienceUnknownDescription)
    }

    var visibleContentLabel: String {
        switch ProjectionExperienceCatalog.standard[id]?.visibleContentKind {
            case .aircraft: String(localized: .dashboardAircraftVisible)
            case .vehicles: String(localized: .viewsVehiclesVisible)
            case .objects, nil: String(localized: .viewsContentVisible)
        }
    }

    var symbol: SFSymbol {
        if id == .airAndSpace { return .airplane }
        if id == .transit { return .tramFill }
        return .rectangleStack
    }
}
