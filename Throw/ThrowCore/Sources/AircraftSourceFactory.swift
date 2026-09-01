import Foundation

public struct ConfiguredAircraftSource: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let source: any AircraftObservationSource
    public let baseCadence: AircraftPollingCadence
    public let metadataWarning: AircraftSourceFailure?

    public init(
        source: any AircraftObservationSource,
        baseCadence: AircraftPollingCadence,
        metadataWarning: AircraftSourceFailure?,
    ) {
        self.source = source
        self.baseCadence = baseCadence
        self.metadataWarning = metadataWarning
    }

    public var description: String {
        "<ConfiguredAircraftSource source=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public protocol AircraftSourceProducing: Sendable {
    func makeSource(
        configuration: AircraftSourceConfiguration,
    ) async throws -> ConfiguredAircraftSource
}

public struct AircraftSourceFactory: AircraftSourceProducing {
    private let cloudTransport: any HTTPTransport
    private let localTransport: any HTTPTransport
    private let credentialStore: any AircraftCredentialStore
    private let dateProvider: any DateProvider

    public init(
        cloudTransport: any HTTPTransport,
        localTransport: any HTTPTransport,
        credentialStore: any AircraftCredentialStore,
        dateProvider: any DateProvider,
    ) {
        self.cloudTransport = cloudTransport
        self.localTransport = localTransport
        self.credentialStore = credentialStore
        self.dateProvider = dateProvider
    }

    public func makeSource(
        configuration: AircraftSourceConfiguration,
    ) async throws -> ConfiguredAircraftSource {
        let decoder = ADSBExchangeV2Decoder()
        switch configuration {
            case .adsbLol:
                return try ConfiguredAircraftSource(
                    source: AdsBLolSource(
                        transport: cloudTransport,
                        decoder: decoder,
                        dateProvider: dateProvider,
                    ),
                    baseCadence: AircraftPollingCadence(duration: .seconds(10)),
                    metadataWarning: nil,
                )
            case let .readsb(readsbConfiguration):
                let source = ReadsbSource(
                    configuration: readsbConfiguration,
                    transport: localTransport,
                    decoder: decoder,
                    dateProvider: dateProvider,
                )
                let timing = try await source.recommendedPollingTiming()
                return try ConfiguredAircraftSource(
                    source: source,
                    baseCadence: AircraftPollingCadence(
                        duration: .seconds(timing.intervalSeconds),
                    ),
                    metadataWarning: timing.metadataFailure,
                )
            case let .adsbExchangeRapidAPI(rapidConfiguration):
                guard let credential = try await credentialStore.credential(
                    for: .rapidAPI,
                ) else {
                    throw AircraftSourceFailure.missingCredential
                }
                return try ConfiguredAircraftSource(
                    source: ADSBExchangeRapidAPISource(
                        transport: cloudTransport,
                        decoder: decoder,
                        credential: credential,
                        dateProvider: dateProvider,
                    ),
                    baseCadence: AircraftPollingCadence(
                        duration: rapidConfiguration.pollingInterval.duration,
                    ),
                    metadataWarning: nil,
                )
            case let .flightradar24(configuration):
                guard let credential = try await credentialStore.credential(
                    for: .flightradar24,
                ) else {
                    throw AircraftSourceFailure.missingCredential
                }
                return try ConfiguredAircraftSource(
                    source: Flightradar24Source(
                        transport: cloudTransport,
                        decoder: Flightradar24Decoder(),
                        credential: credential,
                        dateProvider: dateProvider,
                    ),
                    baseCadence: AircraftPollingCadence(
                        duration: configuration.pollingInterval.duration,
                    ),
                    metadataWarning: nil,
                )
        }
    }
}
