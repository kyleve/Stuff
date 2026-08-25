import Foundation

public struct ReadsbPollingTiming: Equatable, Sendable {
    public let intervalSeconds: Double
    public let metadataFailure: AircraftSourceFailure?

    public init(intervalSeconds: Double, metadataFailure: AircraftSourceFailure?) {
        precondition((0.5 ... 10).contains(intervalSeconds))
        self.intervalSeconds = intervalSeconds
        self.metadataFailure = metadataFailure
    }
}

public struct ReadsbSource: AircraftObservationSource, CustomStringConvertible,
    CustomDebugStringConvertible
{
    private let configuration: ReadsbConfiguration
    private let transport: any HTTPTransport
    private let decodingWorker: AircraftDecodingWorker
    private let dateProvider: any DateProvider

    public init(
        configuration: ReadsbConfiguration,
        transport: any HTTPTransport,
        decoder: ADSBExchangeV2Decoder,
        dateProvider: any DateProvider,
    ) {
        self.configuration = configuration
        self.transport = transport
        decodingWorker = AircraftDecodingWorker(decoder: decoder)
        self.dateProvider = dateProvider
    }

    public var description: String {
        "<ReadsbSource configuration=<redacted>>"
    }

    public var debugDescription: String {
        description
    }

    public func snapshot(for query: AircraftQuery) async throws -> AircraftSnapshot {
        do {
            let response = try await transport.response(for: makeAircraftRequest())
            let fetchedAt = dateProvider.now()
            try SourceHTTPValidation.validate(response, source: .readsb, receivedAt: fetchedAt)
            let snapshot = try await decodingWorker.decodeReadsbSnapshot(
                response.data,
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

    /// Receiver metadata is best-effort: every failure is returned alongside
    /// the one-second fallback so the aircraft feed can remain usable without
    /// pretending metadata succeeded.
    public func recommendedPollingTiming() async throws -> ReadsbPollingTiming {
        do {
            let response = try await transport.response(for: makeReceiverRequest())
            let receivedAt = dateProvider.now()
            try SourceHTTPValidation.validate(response, source: .readsb, receivedAt: receivedAt)
            let metadata = try JSONDecoder().decode(ReadsbReceiverDTO.self, from: response.data)
            let refresh = min(10, max(0.5, metadata.refresh?.value ?? 1))
            return ReadsbPollingTiming(intervalSeconds: refresh, metadataFailure: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AircraftSourceFailure {
            return ReadsbPollingTiming(intervalSeconds: 1, metadataFailure: error)
        } catch let error as HTTPTransportFailure {
            return ReadsbPollingTiming(
                intervalSeconds: 1,
                metadataFailure: .transport(error.category),
            )
        } catch {
            return ReadsbPollingTiming(intervalSeconds: 1, metadataFailure: .decoding)
        }
    }

    public func makeAircraftRequest() -> HTTPRequest {
        HTTPRequest(
            method: .get,
            url: configuration.aircraftJSONURL,
            headers: [.accept: "application/json"],
            body: nil,
            timeoutSeconds: 3,
        )
    }

    public func makeReceiverRequest() throws -> HTTPRequest {
        try HTTPRequest(
            method: .get,
            url: ReadsbURLValidator.receiverJSONURL(
                for: configuration.aircraftJSONURL,
            ),
            headers: [.accept: "application/json"],
            body: nil,
            timeoutSeconds: 3,
        )
    }
}

private struct ReadsbReceiverDTO: Decodable {
    let refresh: ReadsbFlexibleDouble?
}

private struct ReadsbFlexibleDouble: Decodable {
    let value: Double

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedValue: Double
        if let double = try? container.decode(Double.self) {
            decodedValue = double
        } else if let string = try? container.decode(String.self), let double = Double(string) {
            decodedValue = double
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected numeric receiver refresh",
                ),
            )
        }
        guard decodedValue.isFinite else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected finite receiver refresh",
            )
        }
        value = decodedValue
    }
}
