import Foundation
@testable import ThrowCore

struct FixedDateProvider: DateProvider {
    let date: Date

    func now() -> Date {
        date
    }
}

enum ScriptedHTTPOutcome {
    case response(HTTPResponse)
    case failure(HTTPTransportFailure)
}

actor ScriptedHTTPTransport: HTTPTransport {
    private var outcomes: [ScriptedHTTPOutcome]
    private var requests: [HTTPRequest] = []

    init(outcomes: [ScriptedHTTPOutcome]) {
        self.outcomes = outcomes
    }

    func response(for request: HTTPRequest) throws -> HTTPResponse {
        requests.append(request)
        guard outcomes.isEmpty == false else {
            throw HTTPTransportFailure(category: .other)
        }
        switch outcomes.removeFirst() {
            case let .response(response): return response
            case let .failure(failure): throw failure
        }
    }

    func recordedRequests() -> [HTTPRequest] {
        requests
    }
}

enum ThrowCoreFixture {
    static let date = Date(timeIntervalSince1970: 1_700_000_000)

    static func observer(
        latitude: Double = 37,
        longitude: Double = -122,
        altitudeFeet: Double = 20,
    ) throws -> ObserverPosition {
        try ObserverPosition(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            altitude: Altitude(feet: altitudeFeet),
        )
    }

    static func mapQuery(
        radius: Double = 50,
        includeGround: Bool = false,
    ) throws -> AircraftQuery {
        try AircraftQuery(
            observer: observer(),
            viewport: .map(MapViewport(radius: NauticalMiles(value: radius))),
            includeGroundAircraft: includeGround,
        )
    }

    static func skyQuery(minimumElevation: Double = 0) throws -> AircraftQuery {
        try AircraftQuery(
            observer: observer(),
            viewport: .trueSky(
                SkyViewport(minimumElevation: ElevationAngle(degrees: minimumElevation)),
            ),
            includeGroundAircraft: true,
        )
    }

    static func observation(
        latitude: Double = 37.01,
        longitude: Double = -122,
        altitudeFeet: Double? = 10000,
        state: AircraftAirborneState = .airborne,
        positionAge: TimeInterval = 0,
        source: AircraftSourceKind = .adsbLol,
        callsign: String? = "THROW1",
        groundSpeedKnots: Double = 360,
        groundTrackDegrees: Double? = 90,
        verticalRateFeetPerMinute: Double? = 600,
        aircraftType: String? = "B738",
        emitterCategory: AircraftEmitterCategory? = .large,
    ) throws -> AircraftObservation {
        try AircraftObservation(
            id: AircraftID(kind: .icao, rawValue: "abc123"),
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            geometricAltitude: altitudeFeet.map { try Altitude(feet: $0) },
            barometricAltitude: nil,
            airborneState: state,
            groundTrack: groundTrackDegrees.map(Bearing.init(degrees:)),
            trueHeading: nil,
            magneticHeading: nil,
            groundSpeedKnots: groundSpeedKnots,
            verticalRateFeetPerMinute: verticalRateFeetPerMinute,
            callsign: callsign,
            registration: "N123TH",
            aircraftType: aircraftType.flatMap(AircraftTypeDesignator.init(rawValue:)),
            emitterCategory: emitterCategory,
            messageObservedAt: date.addingTimeInterval(-positionAge),
            positionObservedAt: date.addingTimeInterval(-positionAge),
            fetchedAt: date,
            metadata: AircraftObservationMetadata(
                source: source,
                positionSource: "adsb_icao",
                messageCount: 42,
            ),
        )
    }

    static func adsbEnvelope(aircraftJSON: String) -> Data {
        Data("{\"now\":1700000000000,\"ac\":[\(aircraftJSON)]}".utf8)
    }

    static func response(
        statusCode: Int = 200,
        headers: [String: String] = [:],
        data: Data,
    ) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, headers: headers, data: data)
    }
}
