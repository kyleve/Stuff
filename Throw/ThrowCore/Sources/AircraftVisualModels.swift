import Foundation

/// The six silhouettes that Throw can draw without relying on color.
public enum AircraftVisualFamily: String, CaseIterable, Hashable, Sendable {
    case heavyJet = "heavy-jet"
    case airliner
    case regionalBusinessJet = "regional-business-jet"
    case propeller
    case helicopter
    case unknown

    public var sizeMultiplier: Double {
        switch self {
            case .heavyJet: 1.15
            case .airliner: 1
            case .regionalBusinessJet: 0.95
            case .propeller: 0.9
            case .helicopter: 0.95
            case .unknown: 1
        }
    }
}

/// A carrier with a deliberately curated, logo-free color accent.
public enum AirlineBrand: String, CaseIterable, Hashable, Sendable {
    case alaska = "ASA"
    case allegiant = "AAY"
    case american = "AAL"
    case airCanada = "ACA"
    case aeromexico = "AMX"
    case avelo = "VXP"
    case breeze = "MXY"
    case delta = "DAL"
    case frontier = "FFT"
    case flair = "FLE"
    case hawaiian = "HAL"
    case jetBlue = "JBU"
    case porter = "POE"
    case southwest = "SWA"
    case spirit = "NKS"
    case sunCountry = "SCX"
    case airTransat = "TSC"
    case united = "UAL"
    case westJet = "WJA"
    case volaris = "VOI"
    case vivaAerobus = "VIV"
    case fedEx = "FDX"
    case ups = "UPS"

    public static func identify(callsign: String?) -> AirlineBrand? {
        guard let callsign else { return nil }
        let normalized = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count >= 3 else { return nil }
        return AirlineBrand(rawValue: String(normalized.prefix(3)))
    }
}

/// Provider-neutral visual semantics carried into the projection renderer.
public struct AircraftGlyphDescriptor: Hashable, Sendable {
    public let family: AircraftVisualFamily
    public let brand: AirlineBrand?
    public let isGrounded: Bool

    public init(family: AircraftVisualFamily, brand: AirlineBrand?, isGrounded: Bool) {
        self.family = family
        self.brand = brand
        self.isGrounded = isGrounded
    }

    public static let unknownAirborne = AircraftGlyphDescriptor(
        family: .unknown,
        brand: nil,
        isGrounded: false,
    )
}
