import Foundation

/// Provider-neutral operations used by source setup without exposing concrete adapters.
public protocol AircraftSourceOperationServing: Sendable {
    func testConnection(
        request: AircraftSourceValidationRequest,
    ) async throws -> AircraftSnapshot

    func flightradar24Usage(
        period: Flightradar24UsagePeriod,
    ) async throws -> Flightradar24UsageReport
}

/// Keeps provider construction and capability dispatch inside ThrowCore.
public struct AircraftSourceService: AircraftSourceOperationServing {
    private let sourceFactory: any AircraftSourceProducing
    private let cloudTransport: any HTTPTransport
    private let credentialStore: any AircraftCredentialStore
    private let dateProvider: any DateProvider

    public init(
        sourceFactory: any AircraftSourceProducing,
        cloudTransport: any HTTPTransport,
        credentialStore: any AircraftCredentialStore,
        dateProvider: any DateProvider,
    ) {
        self.sourceFactory = sourceFactory
        self.cloudTransport = cloudTransport
        self.credentialStore = credentialStore
        self.dateProvider = dateProvider
    }

    public func testConnection(
        request: AircraftSourceValidationRequest,
    ) async throws -> AircraftSnapshot {
        switch request.draft {
            case .adsbLol, .readsb:
                let configured = try await sourceFactory.makeSource(
                    configuration: request.draft.configuration,
                )
                return try await configured.source.snapshot(for: request.query)
            case let .adsbExchangeRapidAPI(_, replacementCredential):
                let credential = try await credential(
                    replacement: replacementCredential,
                    id: .rapidAPI,
                )
                return try await ADSBExchangeRapidAPISource(
                    transport: cloudTransport,
                    decoder: ADSBExchangeV2Decoder(),
                    credential: credential,
                    dateProvider: dateProvider,
                ).credentialTestSnapshot(observer: request.query.observer)
            case let .flightradar24(_, replacementCredential):
                let credential = try await credential(
                    replacement: replacementCredential,
                    id: .flightradar24,
                )
                return try await Flightradar24Source(
                    transport: cloudTransport,
                    decoder: Flightradar24Decoder(),
                    credential: credential,
                    dateProvider: dateProvider,
                ).credentialTestSnapshot(observer: request.query.observer)
        }
    }

    public func flightradar24Usage(
        period: Flightradar24UsagePeriod,
    ) async throws -> Flightradar24UsageReport {
        let credential = try await credential(
            replacement: nil,
            id: .flightradar24,
        )
        return try await Flightradar24Source(
            transport: cloudTransport,
            decoder: Flightradar24Decoder(),
            credential: credential,
            dateProvider: dateProvider,
        ).usage(period: period)
    }

    private func credential(
        replacement: AircraftCredential?,
        id: AircraftCredentialID,
    ) async throws -> AircraftCredential {
        if let replacement {
            return replacement
        }
        guard let stored = try await credentialStore.credential(for: id) else {
            throw AircraftSourceFailure.missingCredential
        }
        return stored
    }
}
