import Foundation

public struct ADSBExchangeRapidAPISource: AircraftObservationSource, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let host = "adsbexchange-com1.p.rapidapi.com"
    public static let baseURL = URL(string: "https://adsbexchange-com1.p.rapidapi.com")!

    private let transport: any HTTPTransport
    private let decodingWorker: AircraftDecodingWorker
    private let credential: AircraftCredential
    private let dateProvider: any DateProvider

    public init(
        transport: any HTTPTransport,
        decoder: ADSBExchangeV2Decoder,
        credential: AircraftCredential,
        dateProvider: any DateProvider,
    ) {
        self.transport = transport
        decodingWorker = AircraftDecodingWorker(decoder: decoder)
        self.credential = credential
        self.dateProvider = dateProvider
    }

    public var description: String {
        "<ADSBExchangeRapidAPISource credential=<redacted>>"
    }

    public var debugDescription: String {
        description
    }

    public func snapshot(for query: AircraftQuery) async throws -> AircraftSnapshot {
        try await snapshot(for: query, request: makeRequest(for: query))
    }

    /// Performs the disclosed credential check using exactly one transmitted
    /// five-nautical-mile request rather than the live feed's padded radius.
    public func credentialTestSnapshot(
        observer: ObserverPosition,
    ) async throws -> AircraftSnapshot {
        let query = try AircraftQuery(
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 5))),
            includeGroundAircraft: false,
        )
        return try await snapshot(
            for: query,
            request: makeRequest(for: query, transmittedRadius: NauticalMiles(value: 5)),
        )
    }

    private func snapshot(
        for query: AircraftQuery,
        request: HTTPRequest,
    ) async throws -> AircraftSnapshot {
        do {
            let response = try await transport.response(for: request)
            let fetchedAt = dateProvider.now()
            try SourceHTTPValidation.validate(
                response,
                source: .adsbExchangeRapidAPI,
                receivedAt: fetchedAt,
            )
            let snapshot = try await decodingWorker.decodeCloudSnapshot(
                response.data,
                source: .adsbExchangeRapidAPI,
                fetchedAt: fetchedAt,
                query: query,
            )
            return AircraftSnapshot(
                source: snapshot.source,
                fetchedAt: snapshot.fetchedAt,
                observations: snapshot.observations,
                successfulHTTPStatus: response.statusCode,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AircraftSourceFailure {
            throw error
        } catch let error as HTTPTransportFailure {
            throw AircraftSourceFailure.transport(error.category)
        } catch is ADSBV2DecodingError {
            throw AircraftSourceFailure.decoding
        } catch {
            throw AircraftSourceFailure.decoding
        }
    }

    public func makeRequest(for query: AircraftQuery) throws -> HTTPRequest {
        let plan = try CloudAircraftQuery.plan(for: query)
        return try makeRequest(for: query, transmittedRadius: plan.transmittedRadius)
    }

    func makeCredentialTestRequest(observer: ObserverPosition) throws -> HTTPRequest {
        let query = try AircraftQuery(
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 5))),
            includeGroundAircraft: false,
        )
        return try makeRequest(for: query, transmittedRadius: NauticalMiles(value: 5))
    }

    private func makeRequest(
        for query: AircraftQuery,
        transmittedRadius: NauticalMiles,
    ) throws -> HTTPRequest {
        let plan = try CloudAircraftQuery.plan(for: query)
        let latitude = CloudAircraftQuery.pathComponent(for: plan.coarseCenter.latitude)
        let longitude = CloudAircraftQuery.pathComponent(for: plan.coarseCenter.longitude)
        let radius = String(Int(transmittedRadius.value))
        guard let url = URL(
            string: "/v2/lat/\(latitude)/lon/\(longitude)/dist/\(radius)/",
            relativeTo: Self.baseURL,
        )?.absoluteURL else {
            throw AircraftSourceFailure.invalidConfiguration
        }
        return HTTPRequest(
            method: .get,
            url: url,
            headers: [
                .accept: "application/json",
                .acceptEncoding: "gzip",
                .rapidAPIHost: Self.host,
                .rapidAPIKey: credential.authenticationHeaderValue,
            ],
            timeoutSeconds: 8,
        )
    }
}
