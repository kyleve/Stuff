/// One valid relationship between a selected aircraft source and its validation state.
public enum AircraftSourceSelection: Equatable, Sendable {
    case unconfigured
    case awaitingValidation(AircraftSourceConfiguration)
    case configured(AircraftSourceConfiguration)

    public init(
        selectedSource: AircraftSourceConfiguration?,
        validatedSource: AircraftSourceConfiguration?,
    ) throws {
        switch (selectedSource, validatedSource) {
            case (nil, nil):
                self = .unconfigured
            case let (selected?, nil):
                self = .awaitingValidation(selected)
            case let (selected?, validated?) where selected == validated:
                self = .configured(selected)
            case (nil, .some), (.some, .some):
                throw ThrowValidationError.invalidPreferencePayload
        }
    }

    public var selectedSource: AircraftSourceConfiguration? {
        switch self {
            case .unconfigured:
                nil
            case let .awaitingValidation(configuration),
                 let .configured(configuration):
                configuration
        }
    }

    public var validatedSource: AircraftSourceConfiguration? {
        switch self {
            case .unconfigured, .awaitingValidation:
                nil
            case let .configured(configuration):
                configuration
        }
    }

    public var configuredSource: AircraftSourceConfiguration? {
        switch self {
            case .unconfigured, .awaitingValidation:
                nil
            case let .configured(configuration):
                configuration
        }
    }

    public var isConfigured: Bool {
        configuredSource != nil
    }
}
