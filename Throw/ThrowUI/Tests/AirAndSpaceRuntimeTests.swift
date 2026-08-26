import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct AirAndSpaceRuntimeTests {
    @Test func validEmptyPollMakesFreshActivationReady() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let snapshot = AircraftSnapshot(source: .adsbLol, fetchedAt: date, observations: [])
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: FixedAircraftSourceFactory(snapshot: snapshot),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        let runtime = AirAndSpaceRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            routeResolver: FlightRouteResolver(source: EmptyFlightRouteSource()),
            routeLogger: DiscardingFlightRouteLogger(),
            dateProvider: FixtureDateProvider(date: date),
        )
        var updates = await runtime.stateUpdates().makeAsyncIterator()
        _ = await updates.next()
        let observer = try ObserverPosition(
            coordinate: GeoCoordinate(latitude: 37, longitude: -122),
            altitude: Altitude(feet: 0),
        )
        let query = try AircraftQuery(
            observer: observer,
            center: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            includeGroundAircraft: false,
        )

        await runtime.activate(
            configuration: .adsbLol,
            query: query,
            labelMode: .adaptive,
            activationGeneration: 42,
        )

        var ready: AirAndSpaceRuntimeUpdate?
        while let update = await updates.next() {
            if update.successfulActivationGeneration == 42 {
                ready = update
                break
            }
        }
        let update = try #require(ready)
        #expect(update.health == .healthy(lastUpdate: date, visibleContentCount: 0))
        #expect(update.layerFrame?.marks.isEmpty == true)
        #expect(update.experienceFrame.experienceID == .airAndSpace)
        #expect(update.activePollingSignature != nil)

        await runtime.deactivate(reporting: .idle)
    }
}

private struct FixedAircraftSourceFactory: AircraftSourceProducing {
    let snapshot: AircraftSnapshot

    func makeSource(
        configuration _: AircraftSourceConfiguration,
    ) async throws -> ConfiguredAircraftSource {
        ConfiguredAircraftSource(
            source: FixedAircraftSource(snapshot: snapshot),
            baseCadence: .seconds(300),
            metadataWarning: nil,
        )
    }
}

private struct FixedAircraftSource: AircraftObservationSource {
    let snapshot: AircraftSnapshot

    func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
        snapshot
    }
}

private struct LongAircraftPollingClock: AircraftPollingClock {
    let date: Date

    init(now: Date) {
        date = now
    }

    func now() async -> Date {
        date
    }

    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

private struct EmptyFlightRouteSource: FlightRouteSource {
    func routes(
        for _: [FlightRouteQuery],
    ) async throws -> [FlightCallsign: FlightRoute] {
        [:]
    }
}
