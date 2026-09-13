import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct LocationWelcomeModelTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 10000)

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
            now: { Self.now },
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

    @Test(arguments: [true, false])
    func appearanceResetAllowsTheSameRegionToWelcomeAgainWhenEnabled(isEnabled: Bool) async throws {
        let fixture = try await fixture(region: .california)
        await fixture.model.resolve()
        fixture.model.dismiss()
        await fixture.model.resolve()
        #expect(fixture.model.presentation == nil)

        let report = YearReportModel(
            services: fixture.services,
            selectedYear: 2026,
            preferences: fixture.preferences,
        )
        report.showsLocationWelcome = isEnabled
        report.resetLocationWelcome()

        #expect(fixture.preferences.lastWelcomedRegion == nil)
        #expect(fixture.preferences.showsLocationWelcome == isEnabled)
        #expect(fixture.model.presentation == nil)

        await fixture.model.resolve()

        #expect(fixture.model.presentation == (isEnabled ? .init(
            region: .california,
            greeting: .first,
        ) : nil))
    }

    @Test func inactiveRecordingDoesNotPresent() async throws {
        let fixture = try fixtureWithoutRecording(region: .california)

        await fixture.model.resolve()
        #expect(fixture.model.presentation == nil)
    }

    @Test func disabledPreferenceDoesNotPresent() async throws {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        preferences.showsLocationWelcome = false
        let fixture = try await fixture(region: .california, preferences: preferences)

        await fixture.model.resolve()

        #expect(fixture.model.presentation == nil)
    }

    @Test func disabledDuringResolutionDoesNotPublishALateWelcome() async throws {
        let source = GatedCurrentLocationSource()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let services = try Self.services(locationSource: source)
        try await services.ingestor.authorizeRecording()
        let model = LocationWelcomeModel(
            services: services,
            preferences: preferences,
            now: { Self.now },
        )
        let task = Task { await model.resolve() }
        await source.waitUntilRequestCount(1)

        preferences.showsLocationWelcome = false
        try await source.resolveRequest(
            at: 0,
            with: Self.sample(region: .california),
        )
        await task.value

        #expect(model.presentation == nil)
    }

    @Test func cancelledResolutionDoesNotPublishALateRegion() async throws {
        let source = GatedCurrentLocationSource()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let services = try Self.services(locationSource: source)
        try await services.ingestor.authorizeRecording()
        let model = LocationWelcomeModel(
            services: services,
            preferences: preferences,
            now: { Self.now },
        )
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

    @Test func delayedAcquisitionShowsLocatingAccessory() async throws {
        let source = GatedCurrentLocationSource()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let services = try Self.services(locationSource: source)
        try await services.ingestor.authorizeRecording()
        let model = LocationWelcomeModel(
            services: services,
            preferences: preferences,
            now: { Self.now },
            findingDelay: .zero,
        )
        let task = Task { await model.resolve() }
        await source.waitUntilRequestCount(1)
        await waitUntil { model.accessory == .locating }

        #expect(model.state == .locating(showsProgress: true))

        task.cancel()
        await source.resolveRequest(at: 0, with: .unavailable(.cancellation))
        await task.value
    }

    @Test func preciseLocationFailureRequiresSettingsAction() async throws {
        let fixture = try await fixture(result: .unavailable(.preciseLocationDisabled))

        await fixture.model.resolve()

        #expect(fixture.model.accessory == .actionRequired(.preciseLocation))
    }

    @Test(arguments: [LocationAuthorizationStatus.denied, .restricted])
    func deniedOrRestrictedLocationRequiresSettingsAction(
        status: LocationAuthorizationStatus,
    ) async throws {
        let fixture = try await fixture(
            result: .unavailable(.authorizationUnavailable(status)),
        )

        await fixture.model.resolve()

        #expect(fixture.model.accessory == .actionRequired(.locationAccess))
    }

    @Test(
        arguments: [
            CurrentLocationResult.UnavailableReason.timeout,
            .providerFailure,
            .cancellation,
        ],
    )
    func transientFailuresReturnSilentlyToIdle(
        reason: CurrentLocationResult.UnavailableReason,
    ) async throws {
        let fixture = try await fixture(result: .unavailable(reason))

        await fixture.model.resolve()

        #expect(fixture.model.state == .idle)
    }

    @Test func newerResolutionWinsWhenRequestsFinishOutOfOrder() async throws {
        let source = GatedCurrentLocationSource()
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let services = try Self.services(locationSource: source)
        try await services.ingestor.authorizeRecording()
        let model = LocationWelcomeModel(
            services: services,
            preferences: preferences,
            now: { Self.now },
        )
        let first = Task { await model.resolve() }
        await source.waitUntilRequestCount(1)
        let second = Task { await model.resolve() }
        await source.waitUntilRequestCount(2)

        try await source.resolveRequest(at: 1, with: Self.sample(region: .newYork))
        await second.value
        try await source.resolveRequest(at: 0, with: Self.sample(region: .california))
        await first.value

        #expect(model.presentation == .init(region: .newYork, greeting: .first))
    }

    private func fixture(
        region: Region,
        preferences: WherePreferences = WherePreferences(store: InMemoryKeyValueStore()),
    ) async throws -> Fixture {
        let fixture = try fixtureWithoutRecording(region: region, preferences: preferences)
        try await fixture.services.ingestor.authorizeRecording()
        return fixture
    }

    private func fixture(result: CurrentLocationResult) async throws -> Fixture {
        let source = ScriptedLocationSource()
        source.setNextRequestedLocationResult(result)
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let services = try Self.services(locationSource: source)
        try await services.ingestor.authorizeRecording()
        return Fixture(
            model: LocationWelcomeModel(
                services: services,
                preferences: preferences,
                now: { Self.now },
            ),
            services: services,
            preferences: preferences,
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        while condition() == false {
            await Task.yield()
        }
    }

    private func fixtureWithoutRecording(
        region: Region,
        preferences: WherePreferences = WherePreferences(store: InMemoryKeyValueStore()),
    ) throws -> Fixture {
        let source = ScriptedLocationSource()
        try source.setNextRequestedLocation(Self.sample(region: region))
        let services = try Self.services(locationSource: source)
        return Fixture(
            model: LocationWelcomeModel(
                services: services,
                preferences: preferences,
                now: { Self.now },
            ),
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
            timestamp: now,
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
