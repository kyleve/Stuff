import Foundation

public struct AdsBLolSource: AircraftObservationSource, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static let baseURL = URL(string: "https://api.adsb.lol")!

    private let transport: any HTTPTransport
    private let decodingWorker: AircraftDecodingWorker
    private let dateProvider: any DateProvider

    public init(
        transport: any HTTPTransport,
        decoder: ADSBExchangeV2Decoder,
        dateProvider: any DateProvider,
    ) {
        self.transport = transport
        decodingWorker = AircraftDecodingWorker(decoder: decoder)
        self.dateProvider = dateProvider
    }

    public var description: String {
        "<AdsBLolSource configuration=<redacted>>"
    }

    public var debugDescription: String {
        description
    }

    public func snapshot(for query: AircraftQuery) async throws -> AircraftSnapshot {
        let request = try makeRequest(for: query)
        do {
            let response = try await transport.response(for: request)
            let fetchedAt = dateProvider.now()
            try SourceHTTPValidation.validate(
                response,
                source: .adsbLol,
                receivedAt: fetchedAt,
            )
            let snapshot = try await decodingWorker.decodeCloudSnapshot(
                response.data,
                source: .adsbLol,
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
        let latitude = CloudAircraftQuery.pathComponent(for: plan.coarseCenter.latitude)
        let longitude = CloudAircraftQuery.pathComponent(for: plan.coarseCenter.longitude)
        let radius = String(Int(plan.transmittedRadius.value))
        guard let url = URL(
            string: "/v2/point/\(latitude)/\(longitude)/\(radius)",
            relativeTo: Self.baseURL,
        )?.absoluteURL else {
            throw AircraftSourceFailure.invalidConfiguration
        }
        return HTTPRequest(
            method: .get,
            url: url,
            headers: [.accept: "application/json"],
            timeoutSeconds: 8,
        )
    }
}
