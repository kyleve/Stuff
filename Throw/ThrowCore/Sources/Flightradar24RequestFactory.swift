import Foundation

/// Number of billed FR24 live-position requests required for one Throw poll.
public enum Flightradar24RequestMultiplicity: Int, Equatable, Sendable {
    case single = 1
    case antimeridian = 2

    public static func livePosition(
        for query: AircraftQuery,
    ) throws -> Flightradar24RequestMultiplicity {
        let plan = try CloudAircraftQuery.plan(for: query)
        return PositionBoundsPlan(
            center: plan.coarseCenter,
            radius: plan.transmittedRadius,
        ).multiplicity
    }
}

/// A live-position query is either one valid bounds request or the two valid
/// hemisphere requests needed when its bounds cross the antimeridian.
enum Flightradar24PositionRequestPlan {
    case single(HTTPRequest)
    case antimeridian(
        westernHemisphere: HTTPRequest,
        easternHemisphere: HTTPRequest,
    )
}

/// Constructs authenticated FR24 requests while keeping geographic bounds valid.
struct Flightradar24RequestFactory {
    private let baseURL: URL
    private let credential: AircraftCredential

    init(baseURL: URL, credential: AircraftCredential) {
        self.baseURL = baseURL
        self.credential = credential
    }

    func livePositionPlan(
        for query: AircraftQuery,
    ) throws -> Flightradar24PositionRequestPlan {
        let plan = try CloudAircraftQuery.plan(for: query)
        return try positionPlan(
            center: plan.coarseCenter,
            radius: plan.transmittedRadius,
        )
    }

    func positionPlan(
        for query: AircraftQuery,
        radius: NauticalMiles,
    ) throws -> Flightradar24PositionRequestPlan {
        let plan = try CloudAircraftQuery.plan(for: query)
        return try positionPlan(center: plan.coarseCenter, radius: radius)
    }

    private func positionPlan(
        center: GeoCoordinate,
        radius: NauticalMiles,
    ) throws -> Flightradar24PositionRequestPlan {
        try positionRequestPlan(for: PositionBoundsPlan(
            center: center,
            radius: radius,
        ))
    }

    func usageRequest(period: Flightradar24UsagePeriod) throws -> HTTPRequest {
        var components = URLComponents(
            url: baseURL.appending(path: "usage"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [URLQueryItem(name: "period", value: period.rawValue)]
        guard let url = components?.url else { throw AircraftSourceFailure.invalidConfiguration }
        return request(url: url)
    }

    private func positionRequest(bounds: PositionBounds) throws -> HTTPRequest {
        var components = URLComponents(
            url: baseURL.appending(path: "live/flight-positions/full"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [URLQueryItem(name: "bounds", value: bounds.queryValue)]
        guard let url = components?.url else { throw AircraftSourceFailure.invalidConfiguration }
        return request(url: url)
    }

    private func request(url: URL) -> HTTPRequest {
        HTTPRequest(
            method: .get,
            url: url,
            headers: [
                .accept: "application/json",
                .acceptVersion: "v1",
                .authorization: "Bearer \(credential.authenticationHeaderValue)",
            ],
            timeoutSeconds: 8,
        )
    }

    private func positionRequestPlan(
        for boundsPlan: PositionBoundsPlan,
    ) throws -> Flightradar24PositionRequestPlan {
        switch boundsPlan {
            case let .single(bounds):
                try .single(positionRequest(bounds: bounds))
            case let .antimeridian(westernHemisphere, easternHemisphere):
                try .antimeridian(
                    westernHemisphere: positionRequest(bounds: westernHemisphere),
                    easternHemisphere: positionRequest(bounds: easternHemisphere),
                )
        }
    }
}

private enum PositionBoundsPlan {
    case single(PositionBounds)
    case antimeridian(
        westernHemisphere: PositionBounds,
        easternHemisphere: PositionBounds,
    )

    init(center: GeoCoordinate, radius: NauticalMiles) {
        let latitudeSpan = radius.value / 60
        let cosine = max(0.01, cos(center.latitude * .pi / 180))
        let longitudeSpan = min(180, radius.value / (60 * cosine))
        let north = min(90, center.latitude + latitudeSpan)
        let south = max(-90, center.latitude - latitudeSpan)
        guard longitudeSpan < 180 else {
            self = .single(PositionBounds(
                north: north,
                south: south,
                west: -180,
                east: 180,
            ))
            return
        }

        let rawWest = center.longitude - longitudeSpan
        let rawEast = center.longitude + longitudeSpan
        if rawWest < -180 {
            self = .antimeridian(
                westernHemisphere: PositionBounds(
                    north: north,
                    south: south,
                    west: -180,
                    east: rawEast,
                ),
                easternHemisphere: PositionBounds(
                    north: north,
                    south: south,
                    west: rawWest + 360,
                    east: 180,
                ),
            )
        } else if rawEast > 180 {
            self = .antimeridian(
                westernHemisphere: PositionBounds(
                    north: north,
                    south: south,
                    west: -180,
                    east: rawEast - 360,
                ),
                easternHemisphere: PositionBounds(
                    north: north,
                    south: south,
                    west: rawWest,
                    east: 180,
                ),
            )
        } else {
            self = .single(PositionBounds(
                north: north,
                south: south,
                west: rawWest,
                east: rawEast,
            ))
        }
    }

    var multiplicity: Flightradar24RequestMultiplicity {
        switch self {
            case .single: .single
            case .antimeridian: .antimeridian
        }
    }
}

private struct PositionBounds {
    let north: Double
    let south: Double
    let west: Double
    let east: Double

    init(north: Double, south: Double, west: Double, east: Double) {
        precondition((-90 ... 90).contains(north))
        precondition((-90 ... 90).contains(south))
        precondition((-180 ... 180).contains(west))
        precondition((-180 ... 180).contains(east))
        precondition(north >= south)
        precondition(east >= west)
        self.north = north
        self.south = south
        self.west = west
        self.east = east
    }

    var queryValue: String {
        [north, south, west, east]
            .map { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0) }
            .joined(separator: ",")
    }
}
