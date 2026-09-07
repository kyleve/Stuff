/// One source candidate that can be tested before it becomes active.
public enum AircraftSourceValidationDraft: Equatable, Sendable {
    case adsbLol
    case readsb(ReadsbConfiguration)
    case adsbExchangeRapidAPI(
        ADSBExchangeConfiguration,
        replacementCredential: AircraftCredential?,
    )
    case flightradar24(
        Flightradar24Configuration,
        replacementCredential: AircraftCredential?,
    )

    public init(configuration: AircraftSourceConfiguration) {
        switch configuration {
            case .adsbLol:
                self = .adsbLol
            case let .readsb(configuration):
                self = .readsb(configuration)
            case let .adsbExchangeRapidAPI(configuration):
                self = .adsbExchangeRapidAPI(
                    configuration,
                    replacementCredential: nil,
                )
            case let .flightradar24(configuration):
                self = .flightradar24(
                    configuration,
                    replacementCredential: nil,
                )
        }
    }

    public var configuration: AircraftSourceConfiguration {
        switch self {
            case .adsbLol:
                .adsbLol
            case let .readsb(configuration):
                .readsb(configuration)
            case let .adsbExchangeRapidAPI(configuration, _):
                .adsbExchangeRapidAPI(configuration)
            case let .flightradar24(configuration, _):
                .flightradar24(configuration)
        }
    }

    public var credentialReplacement: AircraftCredentialReplacement? {
        switch self {
            case .adsbLol, .readsb:
                nil
            case let .adsbExchangeRapidAPI(_, replacementCredential):
                replacementCredential.map {
                    AircraftCredentialReplacement(id: .rapidAPI, credential: $0)
                }
            case let .flightradar24(_, replacementCredential):
                replacementCredential.map {
                    AircraftCredentialReplacement(id: .flightradar24, credential: $0)
                }
        }
    }
}

/// A provider-owned credential replacement with its fixed Keychain identity.
public struct AircraftCredentialReplacement: Equatable, Sendable {
    public let id: AircraftCredentialID
    public let credential: AircraftCredential
}

/// A closed source candidate paired with the query used to test it.
public struct AircraftSourceValidationRequest: Equatable, Sendable {
    public let draft: AircraftSourceValidationDraft
    public let query: AircraftQuery

    public init(draft: AircraftSourceValidationDraft, query: AircraftQuery) {
        self.draft = draft
        self.query = query
    }
}
