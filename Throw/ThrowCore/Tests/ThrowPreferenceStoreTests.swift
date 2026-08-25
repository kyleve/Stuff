import Foundation
import Testing
@testable import ThrowCore

struct ThrowPreferenceStoreTests {
    @Test func memoryStoreRoundTripsValidatedSettings() async throws {
        let preferences = try populatedPreferences()
        let store = try MemoryThrowPreferenceStore(initialValue: .defaultValue)
        try await store.save(preferences)
        #expect(try await store.load() == preferences)
    }

    @Test func allSourceConfigurationShapesRoundTrip() throws {
        let readsbURL = try #require(URL(string: "http://receiver.local/data/aircraft.json"))
        let configurations: [AircraftSourceConfiguration] = try [
            .adsbLol,
            .readsb(ReadsbConfiguration(aircraftJSONURL: readsbURL)),
            .adsbExchangeRapidAPI(
                ADSBExchangeConfiguration(
                    pollingInterval: PollingInterval(seconds: 60),
                    credentialID: .rapidAPI,
                ),
            ),
        ]
        for configuration in configurations {
            let preferences = try preferences(selectedSource: configuration)
            let data = try ThrowPreferencesCodec.encode(preferences)
            #expect(try ThrowPreferencesCodec.decode(data) == preferences)
        }
    }

    @Test func corruptPayloadEntersRepairInsteadOfReturningDefaults() {
        #expect(throws: ThrowPreferenceStoreError.invalidPayload) {
            try ThrowPreferencesCodec.decode(Data("not a property list".utf8))
        }
    }

    @Test func payloadFromBeforeGeographyUsesTheNewDefault() throws {
        let encoded = try ThrowPreferencesCodec.encode(populatedPreferences())
        let propertyList = try PropertyListSerialization.propertyList(
            from: encoded,
            options: [],
            format: nil,
        )
        var storage = try #require(propertyList as? [String: Any])
        storage.removeValue(forKey: "geography")
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: storage,
            format: .binary,
            options: 0,
        )

        let decoded = try ThrowPreferencesCodec.decode(legacyData)

        #expect(decoded.geography == .defaultValue)
    }

    @Test func payloadFromBeforeAirlineAccentsKeepsAccentsEnabled() throws {
        let encoded = try ThrowPreferencesCodec.encode(populatedPreferences())
        let propertyList = try PropertyListSerialization.propertyList(
            from: encoded,
            options: [],
            format: nil,
        )
        var storage = try #require(propertyList as? [String: Any])
        storage.removeValue(forKey: "airlineAccentsEnabled")
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: storage,
            format: .binary,
            options: 0,
        )

        #expect(try ThrowPreferencesCodec.decode(legacyData).airlineAccentsEnabled)
    }

    @Test func completedSetupRequiresAValidatedSourceLocationAndMode() throws {
        let source = AircraftSourceConfiguration.adsbLol
        #expect(throws: ThrowValidationError.invalidPreferencePayload) {
            try ThrowPreferences(
                setupCompleted: true,
                selectedSource: source,
                validatedSource: nil,
                locationMode: .gps,
                confirmedLocation: nil,
                calibration: .defaultValue,
                mapViewport: .defaultValue,
                skyViewport: .defaultValue,
                selectedProjectionMode: nil,
                flightsEnabled: true,
                airlineAccentsEnabled: true,
                geography: .defaultValue,
                labelMode: .adaptive,
                includeGroundAircraft: false,
                markSizePercent: 100,
                intensityPercent: 100,
                quietSchedule: .disabled,
            )
        }
    }

    @Test func completedSetupRejectsASelectedSourceDifferentFromTheValidatedSource() throws {
        let observer = try ThrowCoreFixture.observer()
        #expect(throws: ThrowValidationError.invalidPreferencePayload) {
            try ThrowPreferences(
                setupCompleted: true,
                selectedSource: .adsbLol,
                validatedSource: .adsbExchangeRapidAPI(
                    ADSBExchangeConfiguration(
                        pollingInterval: PollingInterval.defaultValue,
                        credentialID: .rapidAPI,
                    ),
                ),
                locationMode: .gps,
                confirmedLocation: ConfirmedObserverLocation(
                    position: observer,
                    horizontalAccuracyMeters: 10,
                    confirmedAt: ThrowCoreFixture.date,
                ),
                calibration: .defaultValue,
                mapViewport: .defaultValue,
                skyViewport: .defaultValue,
                selectedProjectionMode: .map,
                flightsEnabled: true,
                airlineAccentsEnabled: true,
                geography: .defaultValue,
                labelMode: .adaptive,
                includeGroundAircraft: false,
                markSizePercent: 100,
                intensityPercent: 100,
                quietSchedule: .disabled,
            )
        }
    }

    @Test func persistenceHasNoAircraftOrCredentialFields() throws {
        let secret = "credential-sentinel"
        let callsign = "CALLSIGN-SENTINEL"
        let aircraftID = "AIRCRAFT-ID-SENTINEL"
        let data = try ThrowPreferencesCodec.encode(populatedPreferences())
        let rendered = String(decoding: data, as: UTF8.self)
        #expect(rendered.contains(secret) == false)
        #expect(rendered.contains(callsign) == false)
        #expect(rendered.contains(aircraftID) == false)
    }

    @Test func preferenceDescriptionsRedactConfirmedLocationAndReceiverURL() throws {
        let coordinateSentinel = "52.123456"
        let receiverSentinel = "preferences-do-not-leak.local"
        let location = try ConfirmedObserverLocation(
            position: ObserverPosition(
                coordinate: GeoCoordinate(latitude: 52.123456, longitude: 13.654321),
                altitude: Altitude(feet: 200),
            ),
            horizontalAccuracyMeters: 25,
            confirmedAt: ThrowCoreFixture.date,
        )
        let readsb = try ReadsbConfiguration(
            aircraftJSONURL: #require(
                URL(string: "http://\(receiverSentinel)/data/aircraft.json"),
            ),
        )
        let preferences = try ThrowPreferences(
            setupCompleted: false,
            selectedSource: .readsb(readsb),
            validatedSource: nil,
            locationMode: .manual,
            confirmedLocation: location,
            calibration: .defaultValue,
            mapViewport: .defaultValue,
            skyViewport: .defaultValue,
            selectedProjectionMode: .map,
            flightsEnabled: true,
            airlineAccentsEnabled: true,
            geography: .defaultValue,
            labelMode: .adaptive,
            includeGroundAircraft: false,
            markSizePercent: 100,
            intensityPercent: 100,
            quietSchedule: .disabled,
        )
        let renderings = [
            String(describing: location),
            String(reflecting: location),
            String(describing: readsb),
            String(reflecting: readsb),
            String(describing: preferences),
            String(reflecting: preferences),
        ]

        for rendering in renderings {
            #expect(rendering.contains(coordinateSentinel) == false)
            #expect(rendering.contains(receiverSentinel) == false)
        }
    }

    private func populatedPreferences() throws -> ThrowPreferences {
        try preferences(
            selectedSource: .adsbExchangeRapidAPI(
                ADSBExchangeConfiguration(
                    pollingInterval: PollingInterval(seconds: 60),
                    credentialID: .rapidAPI,
                ),
            ),
        )
    }

    private func preferences(
        selectedSource: AircraftSourceConfiguration,
    ) throws -> ThrowPreferences {
        let observer = try ThrowCoreFixture.observer()
        return try ThrowPreferences(
            setupCompleted: true,
            selectedSource: selectedSource,
            validatedSource: selectedSource,
            locationMode: .manual,
            confirmedLocation: ConfirmedObserverLocation(
                position: observer,
                horizontalAccuracyMeters: nil,
                confirmedAt: ThrowCoreFixture.date,
            ),
            calibration: ProjectionCalibration(
                screenTopBearing: Bearing(degrees: 123),
                rotation: .degrees90,
                flipHorizontal: true,
                flipVertical: false,
                safeInsetFraction: 0.1,
                verifiedOnExternalDisplay: true,
            ),
            mapViewport: MapViewport(radius: NauticalMiles(value: 100)),
            skyViewport: SkyViewport(minimumElevation: ElevationAngle(degrees: 20)),
            selectedProjectionMode: .trueSky,
            flightsEnabled: false,
            airlineAccentsEnabled: false,
            geography: GeographyPreferences(isEnabled: false, intensityPercent: 12),
            labelMode: .callsigns,
            includeGroundAircraft: true,
            markSizePercent: 150,
            intensityPercent: 50,
            quietSchedule: QuietSchedule(
                start: LocalTime(hour: 23, minute: 0),
                end: LocalTime(hour: 6, minute: 30),
            ),
        )
    }
}
