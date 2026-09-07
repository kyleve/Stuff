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
            ) == .completed(hasNewRoutes: true, hasMoreRequests: false),
        )
        #expect(
            await resolver.cachedResults(
                for: [observation],
                at: ThrowCoreFixture.date,
            )[callsign] == .route(route),
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
            ) == .completed(hasNewRoutes: false, hasMoreRequests: false),
        )
        #expect(
            try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date.addingTimeInterval(60),
            ) == .noRequestNeeded,
        )
        let callsign = try #require(FlightCallsign(rawValue: "THROW1"))
        #expect(
            await resolver.cachedResults(
                for: [observation],
                at: ThrowCoreFixture.date,
            )[callsign] == .unavailable,
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
        let callsign = try #require(FlightCallsign(rawValue: "THROW1"))
        #expect(
            await resolver.cachedResults(
                for: [observation],
                at: ThrowCoreFixture.date.addingTimeInterval(60),
            )[callsign] == nil,
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

    @Test func canceledResolutionCannotStartProviderCooldown() async throws {
        let source = CancellationRacingFlightRouteSource()
        let resolver = FlightRouteResolver(source: source)
        let observation = try ThrowCoreFixture.observation(callsign: "THROW1")
        let canceledResolution = Task {
            try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date,
            )
        }
        await source.waitForFirstRequest()

        canceledResolution.cancel()
        await source.releaseFirstRequest()

        do {
            _ = try await canceledResolution.value
            Issue.record("Expected route resolution cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error).")
        }
        #expect(
            try await resolver.resolveMissing(
                for: [observation],
                at: ThrowCoreFixture.date.addingTimeInterval(60),
            ) == .completed(hasNewRoutes: false, hasMoreRequests: false),
        )
        #expect(await source.requestCount() == 2)
    }

    @Test func eachResolutionPassBoundsNewCallsignQueries() async throws {
        let source = RecordingFlightRouteSource(routes: [:])
        let resolver = FlightRouteResolver(source: source)
        let observations = try (0 ..< 20).map { index in
            try ThrowCoreFixture.observation(callsign: "THROW\(index)")
        }

        #expect(try await resolver.resolveMissing(
            for: observations,
            at: ThrowCoreFixture.date,
        ) == .completed(hasNewRoutes: false, hasMoreRequests: true))

        #expect(await source.lastQueryCount() == 12)

        #expect(try await resolver.resolveMissing(
            for: observations,
            at: ThrowCoreFixture.date,
        ) == .completed(hasNewRoutes: false, hasMoreRequests: false))
        #expect(await source.lastQueryCount() == 8)
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

private actor CancellationRacingFlightRouteSource: FlightRouteSource {
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var count = 0

    func routes(
        for _: [FlightRouteQuery],
    ) async throws -> [FlightCallsign: FlightRoute] {
        count += 1
        guard count == 1 else { return [:] }
        let waiters = firstRequestWaiters
        firstRequestWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            firstRequestContinuation = continuation
        }
        throw FlightRouteLookupError.provider
    }

    func waitForFirstRequest() async {
        guard count == 0 else { return }
        await withCheckedContinuation { continuation in
            firstRequestWaiters.append(continuation)
        }
    }

    func releaseFirstRequest() {
        firstRequestContinuation?.resume()
        firstRequestContinuation = nil
    }

    func requestCount() -> Int {
        count
    }
}
