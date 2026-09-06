import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct LocationWelcomeModelTests {
    @Test func firstResolvedRegionPresentsAFirstGreeting() async throws {
        let fixture = try await fixture(region: .california)

        await fixture.model.resolve()

        #expect(fixture.model.presentation == .init(region: .california, greeting: .first))
    }

    @Test func dismissalPersistsAndSuppressesTheSameRegion() async throws {
        let fixture = try await fixture(region: .california)
        await fixture.model.resolve()
        fixture.model.dismiss()

        let relaunched = LocationWelcomeModel(
            services: fixture.services,
            preferences: fixture.preferences,
        )
        await relaunched.resolve()

        #expect(fixture.preferences.lastWelcomedRegion == .california)
        #expect(relaunched.presentation == nil)
    }

    @Test func differentRegionPresentsAReturnGreeting() async throws {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.lastWelcomedRegion = .california
        let fixture = try await fixture(region: .newYork, preferences: preferences)

        await fixture.model.resolve()

        #expect(fixture.model.presentation == .init(region: .newYork, greeting: .returnVisit))
    }

    @Test func inactiveRecordingDoesNotPresent() async throws {
        let fixture = try fixtureWithoutRecording(region: .california)

        await fixture.model.resolve()
        #expect(fixture.model.presentation == nil)
    }

    @Test func cancelledResolutionDoesNotPublishALateRegion() async throws {
        let source = GatedCurrentLocationSource()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let services = try Self.services(locationSource: source)
        try await services.ingestor.authorizeRecording()
        let model = LocationWelcomeModel(services: services, preferences: preferences)
        let task = Task { await model.resolve() }
        await source.waitUntilRequestCount(1)

        task.cancel()
        try await source.resolveRequest(
            at: 0,
            with: Self.sample(region: .california),
        )
        await task.value

        #expect(model.presentation == nil)
    }

    private func fixture(
        region: Region,
        preferences: WherePreferences = WherePreferences(store: InMemoryKeyValueStore()),
    ) async throws -> Fixture {
        let fixture = try fixtureWithoutRecording(region: region, preferences: preferences)
        try await fixture.services.ingestor.authorizeRecording()
        return fixture
    }

    private func fixtureWithoutRecording(
        region: Region,
        preferences: WherePreferences = WherePreferences(store: InMemoryKeyValueStore()),
    ) throws -> Fixture {
        let source = ScriptedLocationSource()
        try source.setNextRequestedLocation(Self.sample(region: region))
        let services = try Self.services(locationSource: source)
        return Fixture(
            model: LocationWelcomeModel(services: services, preferences: preferences),
            services: services,
            preferences: preferences,
        )
    }

    private static func services(locationSource: any LocationSource) throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: locationSource,
        )
    }

    private static func sample(region: Region) throws -> LocationSample {
        let coordinates = [
            Region.california: Coordinate(latitude: 37.7749, longitude: -122.4194),
            Region.newYork: Coordinate(latitude: 40.7128, longitude: -74.0060),
        ]
        let coordinate = try #require(coordinates[region])
        return LocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 0),
            coordinate: coordinate,
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        )
    }

    private struct Fixture {
        let model: LocationWelcomeModel
        let services: WhereServices
        let preferences: WherePreferences
    }
}
