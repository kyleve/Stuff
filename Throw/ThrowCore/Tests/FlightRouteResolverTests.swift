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

    @Test func providerFailureStartsCooldownWithoutNegativeCaching() async throws {
        let source = FailingFlightRouteSource()
        let resolver = FlightRouteResolver(source: source)
        let observation = try ThrowCoreFixture.observation(callsign: "THROW1")

        do {
            _ = try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date,
            )
            Issue.record("Expected the route provider to fail.")
        } catch {
            #expect(error as? FlightRouteLookupError == .provider)
        }
        #expect(
            try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date.addingTimeInterval(60),
            ) == .coolingDown,
        )
        #expect(await source.requestCount() == 1)

        do {
            _ = try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date.addingTimeInterval(301),
            )
            Issue.record("Expected a new provider attempt after the cooldown.")
        } catch {
            #expect(error as? FlightRouteLookupError == .provider)
        }
        #expect(await source.requestCount() == 2)
    }

    @Test func eachResolutionPassBoundsNewCallsignQueries() async throws {
        let source = RecordingFlightRouteSource(routes: [:])
        let resolver = FlightRouteResolver(source: source)
        let observations = try (0 ..< 20).map { index in
            try ThrowCoreFixture.observation(callsign: "THROW\(index)")
        }

        _ = try await resolver.resolveMissing(
            for: observations,
            at: ThrowCoreFixture.date,
        )

        #expect(await source.lastQueryCount() == 12)
    }
}

private actor RecordingFlightRouteSource: FlightRouteSource {
    private let routes: [FlightCallsign: FlightRoute]
    private var count = 0
    private var queryCount = 0

    init(routes: [FlightCallsign: FlightRoute]) {
        self.routes = routes
    }

    func routes(
        for queries: [FlightRouteQuery],
    ) -> [FlightCallsign: FlightRoute] {
        count += 1
        queryCount = queries.count
        return routes
    }

    func requestCount() -> Int {
        count
    }

    func lastQueryCount() -> Int {
        queryCount
    }
}

private actor FailingFlightRouteSource: FlightRouteSource {
    private var count = 0

    func routes(
        for _: [FlightRouteQuery],
    ) throws -> [FlightCallsign: FlightRoute] {
        count += 1
        throw FlightRouteLookupError.provider
    }

    func requestCount() -> Int {
        count
    }
}
