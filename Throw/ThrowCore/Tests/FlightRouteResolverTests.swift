import Testing
@testable import ThrowCore

struct FlightRouteResolverTests {
    @Test func resolvedRoutesAreCachedAcrossSnapshots() async throws {
        let callsign = try #require(FlightCallsign(rawValue: "THROW1"))
        let route = try FlightRoute(
            origin: #require(AirportCode(rawValue: "JFK")),
            destination: #require(AirportCode(rawValue: "SFO")),
        )
        let source = RecordingFlightRouteSource(routes: [callsign: route])
        let resolver = FlightRouteResolver(source: source)
        let observation = try ThrowCoreFixture.observation(callsign: callsign.rawValue)

        #expect(
            try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date,
            ) == .completed(hasNewRoutes: true),
        )
        #expect(
            await resolver.cachedRoutes(
                for: [observation],
                at: ThrowCoreFixture.date,
            )[callsign] == route,
        )
        #expect(
            try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date.addingTimeInterval(60),
            ) == .noRequestNeeded,
        )
        #expect(await source.requestCount() == 1)
    }

    @Test func unknownRoutesReceiveANegativeCacheEntry() async throws {
        let source = RecordingFlightRouteSource(routes: [:])
        let resolver = FlightRouteResolver(source: source)
        let observation = try ThrowCoreFixture.observation(callsign: "THROW1")

        #expect(
            try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date,
            ) == .completed(hasNewRoutes: false),
        )
        #expect(
            try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date.addingTimeInterval(60),
            ) == .noRequestNeeded,
        )
        #expect(await source.requestCount() == 1)
    }
}

private actor RecordingFlightRouteSource: FlightRouteSource {
    private let routes: [FlightCallsign: FlightRoute]
    private var count = 0

    init(routes: [FlightCallsign: FlightRoute]) {
        self.routes = routes
    }

    func routes(
        for _: [FlightRouteQuery],
    ) -> [FlightCallsign: FlightRoute] {
        count += 1
        return routes
    }

    func requestCount() -> Int {
        count
    }
}
