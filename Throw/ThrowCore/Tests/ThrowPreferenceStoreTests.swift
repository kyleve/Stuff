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
                ),
            ),
            .flightradar24(
                Flightradar24Configuration(
                    pollingInterval: PollingInterval(seconds: 300),
                ),
            ),
        ]
        for configuration in configurations {
            let preferences = try preferences(selectedSource: configuration)
            let data = try ThrowPreferencesCodec.encode(preferences)
            #expect(try ThrowPreferencesCodec.decode(data) == preferences)
        }
    }

    @Test func boundaryMapRegionRoundTripsThroughThePreferenceCodec() throws {
        let observer = try ObserverPosition(
            coordinate: GeoCoordinate(latitude: 90, longitude: 180),
            altitude: Altitude(feet: 20),
        )
        let preferences = try preferences(
            selectedSource: .adsbLol,
            observer: observer,
            mapCenter: GeoCoordinate(latitude: 89.5, longitude: 179.5),
        )

        let decoded = try ThrowPreferencesCodec.decode(
            ThrowPreferencesCodec.encode(preferences),
        )

        #expect(decoded == preferences)
        let profile = try #require(decoded.mapCenters.profiles.first)
        #expect(profile.regionID.latitudeBand == 89)
        #expect(profile.regionID.longitudeBand == -180)
    }

    @Test func corruptPayloadEntersRepairInsteadOfReturningDefaults() {
        #expect(throws: ThrowPreferenceStoreError.invalidPayload) {
            try ThrowPreferencesCodec.decode(Data("not a property list".utf8))
        }
    }

    @Test func writesVersionTwoNestedPreferencesUnderTheExistingCodec() throws {
        let propertyList = try propertyList(for: ThrowPreferencesCodec
            .encode(populatedPreferences()))

        #expect(propertyList["version"] as? Int == 2)
        #expect(propertyList["global"] != nil)
        #expect(propertyList["playlist"] != nil)
        #expect(propertyList["airAndSpace"] != nil)
        #expect(propertyList["locationMode"] == nil)
        #expect(propertyList["selectedSource"] == nil)
    }

    @Test func completeVersionOnePayloadMigratesWithoutOnboardingAgain() throws {
        let original = try populatedPreferences()
        let migrated = try ThrowPreferencesCodec.decode(versionOnePayload(from: original))

        #expect(migrated == original)
        #expect(migrated.setupCompleted)
        #expect(migrated.playlist.selectedExperienceID == .airAndSpace)
        #expect(migrated.playlist.entries == [
            ProjectionPlaylistEntry(
                experienceID: .airAndSpace,
                dwellDuration: .defaultValue,
            ),
        ])
        #expect(migrated.playlist.rotatesAutomatically == false)
    }

    @Test func incompleteVersionOnePayloadPreservesDraftAndHasNoConfiguredView() throws {
        let original = ThrowPreferences.defaultValue
        let migrated = try ThrowPreferencesCodec.decode(versionOnePayload(from: original))

        #expect(migrated == original)
        #expect(migrated.setupCompleted == false)
        #expect(migrated.playlist.entries.isEmpty)
        #expect(migrated.playlist.selectedExperienceID == nil)
    }

    @Test func corruptVersionTwoPlaylistEntersRepair() throws {
        let encoded = try ThrowPreferencesCodec.encode(populatedPreferences())
        var storage = try propertyList(for: encoded)
        var playlist = try #require(storage["playlist"] as? [String: Any])
        let entries = try #require(playlist["entries"] as? [[String: Any]])
        playlist["entries"] = entries + entries
        storage["playlist"] = playlist
        let corruptData = try PropertyListSerialization.data(
            fromPropertyList: storage,
            format: .binary,
            options: 0,
        )

        #expect(throws: ThrowPreferenceStoreError.invalidPayload) {
            try ThrowPreferencesCodec.decode(corruptData)
        }
    }

    @Test(arguments: ["", "   ", "unknown-experience"])
    func unknownPersistedPlaylistEntryEntersRepair(experienceID: String) throws {
        let encoded = try ThrowPreferencesCodec.encode(populatedPreferences())
        var storage = try propertyList(for: encoded)
        var playlist = try #require(storage["playlist"] as? [String: Any])
        var entries = try #require(playlist["entries"] as? [[String: Any]])
        entries[0]["experienceID"] = experienceID
        playlist["entries"] = entries
        storage["playlist"] = playlist
        let corruptData = try PropertyListSerialization.data(
            fromPropertyList: storage,
            format: .binary,
            options: 0,
        )

        #expect(throws: ThrowPreferenceStoreError.invalidPayload) {
            try ThrowPreferencesCodec.decode(corruptData)
        }
    }

    @Test(arguments: ["", "   ", "unknown-experience"])
    func unknownPersistedPlaylistSelectionEntersRepair(experienceID: String) throws {
        let encoded = try ThrowPreferencesCodec.encode(populatedPreferences())
        var storage = try propertyList(for: encoded)
        var playlist = try #require(storage["playlist"] as? [String: Any])
        playlist["selectedExperienceID"] = experienceID
        storage["playlist"] = playlist
        let corruptData = try PropertyListSerialization.data(
            fromPropertyList: storage,
            format: .binary,
            options: 0,
        )

        #expect(throws: ThrowPreferenceStoreError.invalidPayload) {
            try ThrowPreferencesCodec.decode(corruptData)
        }
    }

    @Test func payloadFromBeforeGeographyUsesTheNewDefault() throws {
        let legacyData = try versionOnePayload(
            from: populatedPreferences(),
            includeGeography: false,
        )

        let decoded = try ThrowPreferencesCodec.decode(legacyData)

        #expect(decoded.geography == .defaultValue)
    }

    @Test func payloadFromBeforeAirlineAccentsKeepsAccentsEnabled() throws {
        let legacyData = try versionOnePayload(
            from: populatedPreferences(),
            includeAirlineAccents: false,
        )

        #expect(try ThrowPreferencesCodec.decode(legacyData).airlineAccentsEnabled)
    }

    @Test func completedSetupPayloadRequiresAValidatedSourceLocationAndMode() throws {
        let encoded = try ThrowPreferencesCodec.encode(populatedPreferences())
        var storage = try propertyList(for: encoded)
        var global = try #require(storage["global"] as? [String: Any])
        var airAndSpace = try #require(storage["airAndSpace"] as? [String: Any])
        global.removeValue(forKey: "confirmedLocation")
        airAndSpace.removeValue(forKey: "validatedSource")
        airAndSpace.removeValue(forKey: "selectedProjectionMode")
        storage["global"] = global
        storage["airAndSpace"] = airAndSpace
        let invalidData = try PropertyListSerialization.data(
            fromPropertyList: storage,
            format: .binary,
            options: 0,
        )

        #expect(throws: ThrowPreferenceStoreError.invalidPayload) {
            try ThrowPreferencesCodec.decode(invalidData)
        }
    }

    @Test func completedSetupPayloadRejectsMismatchedSourceValidation() throws {
        let adsbLolStorage = try propertyList(
            for: ThrowPreferencesCodec.encode(preferences(selectedSource: .adsbLol)),
        )
        let rapidAPIStorage = try propertyList(
            for: ThrowPreferencesCodec.encode(populatedPreferences()),
        )
        var storage = adsbLolStorage
        var airAndSpace = try #require(storage["airAndSpace"] as? [String: Any])
        let rapidAPIAirAndSpace = try #require(
            rapidAPIStorage["airAndSpace"] as? [String: Any],
        )
        airAndSpace["validatedSource"] = rapidAPIAirAndSpace["validatedSource"]
        storage["airAndSpace"] = airAndSpace
        let invalidData = try PropertyListSerialization.data(
            fromPropertyList: storage,
            format: .binary,
            options: 0,
        )

        #expect(throws: ThrowPreferenceStoreError.invalidPayload) {
            try ThrowPreferencesCodec.decode(invalidData)
        }
    }

    @Test func persistedProviderCannotReferenceAnotherProvidersCredential() throws {
        let encoded = try ThrowPreferencesCodec.encode(populatedPreferences())
        var storage = try propertyList(for: encoded)
        var airAndSpace = try #require(storage["airAndSpace"] as? [String: Any])
        for key in ["selectedSource", "validatedSource"] {
            var source = try #require(airAndSpace[key] as? [String: Any])
            source["credentialID"] = AircraftCredentialID.flightradar24.rawValue
            airAndSpace[key] = source
        }
        storage["airAndSpace"] = airAndSpace
        let corruptData = try PropertyListSerialization.data(
            fromPropertyList: storage,
            format: .binary,
            options: 0,
        )

        #expect(throws: ThrowPreferenceStoreError.invalidPayload) {
            try ThrowPreferencesCodec.decode(corruptData)
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
        let setupState = ThrowSetupState.onboarding(
            ThrowOnboardingSetup(
                sourceSelection: .awaitingValidation(.readsb(readsb)),
                location: .confirmed(mode: .manual, location: location),
                projection: .selected(.map),
            ),
        )
        let preferences = try ThrowPreferences(
            setupState: setupState,
            global: ThrowGlobalPreferences(
                calibration: .defaultValue,
                intensityPercent: 100,
                quietSchedule: .disabled,
            ),
            playlist: ProjectionPlaylist(
                entries: [],
                automaticRotationEnabled: false,
                selectedExperienceID: nil,
                configuredExperienceIDs: setupState.configuredExperienceIDs,
                catalog: .standard,
            ),
            airAndSpace: AirAndSpacePreferences(
                mapViewport: .defaultValue,
                mapCenters: .defaultValue,
                skyViewport: .defaultValue,
                flightsEnabled: true,
                airlineAccentsEnabled: true,
                geography: .defaultValue,
                labelMode: .adaptive,
                includeGroundAircraft: false,
                markSizePercent: 100,
            ),
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
                ),
            ),
        )
    }

    private func preferences(
        selectedSource: AircraftSourceConfiguration,
    ) throws -> ThrowPreferences {
        let observer = try ThrowCoreFixture.observer()
        let mapCenter = try GeoCoordinate(latitude: 37.2, longitude: -121.7)
        return try preferences(
            selectedSource: selectedSource,
            observer: observer,
            mapCenter: mapCenter,
        )
    }

    private func preferences(
        selectedSource: AircraftSourceConfiguration,
        observer: ObserverPosition,
        mapCenter: GeoCoordinate,
    ) throws -> ThrowPreferences {
        let confirmedLocation = try ConfirmedObserverLocation(
            position: observer,
            horizontalAccuracyMeters: nil,
            confirmedAt: ThrowCoreFixture.date,
        )
        let setupState = ThrowSetupState.configured(
            ThrowConfiguredSetup(
                source: selectedSource,
                locationMode: .manual,
                confirmedLocation: confirmedLocation,
                projectionMode: .trueSky,
            ),
        )
        let global = try ThrowGlobalPreferences(
            calibration: ProjectionCalibration(
                screenTopBearing: Bearing(degrees: 123),
                rotation: .degrees90,
                flipHorizontal: true,
                flipVertical: false,
                safeInsetFraction: 0.1,
                verifiedOnExternalDisplay: true,
            ),
            intensityPercent: 50,
            quietSchedule: QuietSchedule(
                start: LocalTime(hour: 23, minute: 0),
                end: LocalTime(hour: 6, minute: 30),
            ),
        )
        let airAndSpace = try AirAndSpacePreferences(
            mapViewport: MapViewport(radius: NauticalMiles(value: 100)),
            mapCenters: MapCenterPreferences.defaultValue.setting(
                center: mapCenter,
                for: observer.coordinate,
            ),
            skyViewport: SkyViewport(minimumElevation: ElevationAngle(degrees: 20)),
            flightsEnabled: false,
            airlineAccentsEnabled: false,
            geography: GeographyPreferences(isEnabled: false, intensityPercent: 12),
            labelMode: .callsigns,
            includeGroundAircraft: true,
            markSizePercent: 150,
        )
        let playlist = try ProjectionPlaylist(
            entries: [
                ProjectionPlaylistEntry(
                    experienceID: .airAndSpace,
                    dwellDuration: .defaultValue,
                ),
            ],
            automaticRotationEnabled: false,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: setupState.configuredExperienceIDs,
            catalog: .standard,
        )
        return try ThrowPreferences(
            setupState: setupState,
            global: global,
            playlist: playlist,
            airAndSpace: airAndSpace,
        )
    }

    private func propertyList(for data: Data) throws -> [String: Any] {
        try #require(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil,
            ) as? [String: Any],
        )
    }

    /// Builds the exact flat format shipped before projection experiences.
    private func versionOnePayload(
        from preferences: ThrowPreferences,
        includeGeography: Bool = true,
        includeAirlineAccents: Bool = true,
    ) throws -> Data {
        let versionTwo = try propertyList(for: ThrowPreferencesCodec.encode(preferences))
        let global = try #require(versionTwo["global"] as? [String: Any])
        let airAndSpace = try #require(versionTwo["airAndSpace"] as? [String: Any])
        var versionOne: [String: Any] = try [
            "version": 1,
            "setupCompleted": preferences.setupCompleted,
            "locationMode": #require(global["locationMode"]),
            "calibration": #require(global["calibration"]),
            "mapRadius": #require(airAndSpace["mapRadius"]),
            "mapCenters": #require(airAndSpace["mapCenters"]),
            "skyMinimumElevation": #require(airAndSpace["skyMinimumElevation"]),
            "flightsEnabled": #require(airAndSpace["flightsEnabled"]),
            "labelMode": #require(airAndSpace["labelMode"]),
            "includeGroundAircraft": #require(airAndSpace["includeGroundAircraft"]),
            "markSizePercent": #require(airAndSpace["markSizePercent"]),
            "intensityPercent": #require(global["intensityPercent"]),
        ]
        copy("confirmedLocation", from: global, to: &versionOne)
        copy("quietInterval", from: global, to: &versionOne)
        copy("selectedSource", from: airAndSpace, to: &versionOne)
        copy("validatedSource", from: airAndSpace, to: &versionOne)
        copy("selectedProjectionMode", from: airAndSpace, to: &versionOne)
        if includeGeography {
            copy("geography", from: airAndSpace, to: &versionOne)
        }
        if includeAirlineAccents {
            copy("airlineAccentsEnabled", from: airAndSpace, to: &versionOne)
        }
        return try PropertyListSerialization.data(
            fromPropertyList: versionOne,
            format: .binary,
            options: 0,
        )
    }

    private func copy(
        _ key: String,
        from source: [String: Any],
        to destination: inout [String: Any],
    ) {
        if let value = source[key] {
            destination[key] = value
        }
    }
}
