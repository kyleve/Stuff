public enum TaxJurisdiction: Codable, Sendable, Hashable {
    case state(USState)
    case unknown

    public static let california = Self.state(.california)
    public static let newYork = Self.state(.newYork)

    public var displayName: String {
        switch self {
            case let .state(state):
                state.displayName
            case .unknown:
                "Unknown"
        }
    }

    public var abbreviation: String {
        switch self {
            case let .state(state):
                state.rawValue
            case .unknown:
                "UNK"
        }
    }

    public var countsTowardTaxDay: Bool {
        self != .unknown
    }

    public var usState: USState? {
        switch self {
            case let .state(state):
                state
            case .unknown:
                nil
        }
    }
}
