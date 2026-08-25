import Foundation

public enum FlightRouteResolution: Equatable, Sendable {
    case noRequestNeeded
    case completed(hasNewRoutes: Bool)
}

/// Keeps route enrichment off the projection hot path and bounds provider traffic.
public actor FlightRouteResolver {
    private struct Entry {
        let route: FlightRoute?
        let expiresAt: Date
    }

    private static let positiveLifetime: TimeInterval = 6 * 60 * 60
    private static let negativeLifetime: TimeInterval = 60 * 60

    private let source: any FlightRouteSource
    private var entries: [FlightCallsign: Entry] = [:]

    public init(source: any FlightRouteSource) {
        self.source = source
    }

    public func cachedRoutes(
        for observations: [AircraftObservation],
        at date: Date,
    ) -> [FlightCallsign: FlightRoute] {
        removeExpiredEntries(at: date)
        let callsigns = Set(observations.compactMap { observation in
            observation.callsign.flatMap(FlightCallsign.init(rawValue:))
        })
        return entries.reduce(into: [:]) { routes, item in
            guard callsigns.contains(item.key), let route = item.value.route else { return }
            routes[item.key] = route
        }
    }

    @discardableResult
    public func resolveMissing(
        for observations: [AircraftObservation],
        at date: Date,
    ) async throws -> FlightRouteResolution {
        removeExpiredEntries(at: date)
        var seen: Set<FlightCallsign> = []
        let queries = observations.compactMap { observation -> FlightRouteQuery? in
            guard let callsign = observation.callsign.flatMap(FlightCallsign.init(rawValue:)),
                  entries[callsign] == nil,
                  seen.insert(callsign).inserted
            else { return nil }
            return FlightRouteQuery(callsign: callsign, coordinate: observation.coordinate)
        }
        .prefix(AdsBLolFlightRouteSource.maximumBatchSize)
        guard queries.isEmpty == false else { return .noRequestNeeded }

        let queryArray = Array(queries)
        let routes = try await source.routes(for: queryArray)
        try Task.checkCancellation()
        let queriedCallsigns = Set(queryArray.map(\.callsign))
        for callsign in queriedCallsigns {
            let route = routes[callsign]
            entries[callsign] = Entry(
                route: route,
                expiresAt: date.addingTimeInterval(
                    route == nil ? Self.negativeLifetime : Self.positiveLifetime,
                ),
            )
        }
        return .completed(hasNewRoutes: routes.isEmpty == false)
    }

    private func removeExpiredEntries(at date: Date) {
        entries = entries.filter { $0.value.expiresAt > date }
    }
}
