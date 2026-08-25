import Foundation

/// Converts provider metadata into stable, provider-neutral projection semantics.
public struct AircraftVisualClassifier: Sendable {
    private static let regionalAndBusinessJets: Set<String> = [
        "C25A",
        "C25B",
        "C25C",
        "C510",
        "C525",
        "C550",
        "C560",
        "C56X",
        "C680",
        "C700",
        "C750",
        "CL30",
        "CL35",
        "CL60",
        "CRJ1",
        "CRJ2",
        "CRJ7",
        "CRJ9",
        "CRJX",
        "E135",
        "E145",
        "E170",
        "E190",
        "E195",
        "E50P",
        "E55P",
        "E75L",
        "E75S",
        "F2TH",
        "F900",
        "FA7X",
        "FA8X",
        "GLEX",
        "GL5T",
        "GL6T",
        "GL7T",
        "GLF4",
        "GLF5",
        "GLF6",
        "LJ31",
        "LJ35",
        "LJ40",
        "LJ45",
        "LJ60",
        "LJ70",
        "LJ75",
        "P300",
    ]

    private let catalog: AircraftTypeCatalog

    public init(catalog: AircraftTypeCatalog) {
        self.catalog = catalog
    }

    public func descriptor(for observation: AircraftObservation) -> AircraftGlyphDescriptor {
        descriptor(for: observation, activity: .overflight)
    }

    public func descriptor(
        for observation: AircraftObservation,
        activity: FlightActivity,
    ) -> AircraftGlyphDescriptor {
        AircraftGlyphDescriptor(
            family: family(
                designator: observation.aircraftType,
                emitterCategory: observation.emitterCategory,
            ),
            brand: AirlineBrand.identify(callsign: observation.callsign),
            isGrounded: observation.airborneState == .ground,
            activity: activity,
        )
    }

    public func family(
        designator: AircraftTypeDesignator?,
        emitterCategory: AircraftEmitterCategory?,
    ) -> AircraftVisualFamily {
        if let designator, let characteristics = catalog.characteristics(for: designator) {
            let airframe = characteristics.airframeCode
            let engine = characteristics.engineCode
            if ["H", "G", "T"].contains(airframe) {
                return emitterCategory.map { $0 == .rotorcraft ? .helicopter : .unknown }
                    ?? .helicopter
            }
            if ["L", "A", "S"].contains(airframe), ["P", "T", "E"].contains(engine) {
                return emitterCategory == .rotorcraft ? .unknown : .propeller
            }
            if engine == "J" {
                if emitterCategory == .rotorcraft { return .unknown }
                if Self.regionalAndBusinessJets.contains(designator.rawValue) {
                    return .regionalBusinessJet
                }
                switch characteristics.wakeCategory {
                    case .heavy, .superHeavy: return .heavyJet
                    case .medium: return .airliner
                    case .light: return .regionalBusinessJet
                    case nil: break
                }
            }
        }

        return switch emitterCategory {
            case .rotorcraft: .helicopter
            case .heavy: .heavyJet
            case .large, .highVortexLarge: .airliner
            case .light, .small, .highPerformance: .regionalBusinessJet
            case .noInformation, .glider, .lighterThanAir, .parachutist, .ultralight,
                 .unmanned, .spaceVehicle, .emergencySurface, .serviceSurface,
                 .pointObstacle, nil: .unknown
        }
    }
}
