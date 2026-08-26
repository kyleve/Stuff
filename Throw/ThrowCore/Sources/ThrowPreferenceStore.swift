import Foundation

public enum FlightLabelMode: String, CaseIterable, Codable, Hashable, Sendable {
    case marksOnly = "marks-only"
    case callsigns
    case adaptive
}

public enum ObserverLocationMode: String, CaseIterable, Codable, Hashable, Sendable {
    case gps
    case manual
}

public struct ConfirmedObserverLocation: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let position: ObserverPosition
    public let horizontalAccuracyMeters: Double?
    public let confirmedAt: Date

    public init(
        position: ObserverPosition,
        horizontalAccuracyMeters: Double?,
        confirmedAt: Date,
    ) throws {
        if let horizontalAccuracyMeters {
            guard horizontalAccuracyMeters.isFinite, horizontalAccuracyMeters >= 0 else {
                throw ThrowValidationError.outOfRange(
                    field: "horizontalAccuracy",
                    closedRange: 0 ... Double.greatestFiniteMagnitude,
                )
            }
        }
        self.position = position
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.confirmedAt = confirmedAt
    }

    public var description: String {
        "<ConfirmedObserverLocation position=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

/// Preferences shared by every projection experience.
public struct ThrowGlobalPreferences: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let locationMode: ObserverLocationMode
    public let confirmedLocation: ConfirmedObserverLocation?
    public let calibration: ProjectionCalibration
    public let intensityPercent: Double
    public let quietSchedule: QuietSchedule

    public init(
        locationMode: ObserverLocationMode,
        confirmedLocation: ConfirmedObserverLocation?,
        calibration: ProjectionCalibration,
        intensityPercent: Double,
        quietSchedule: QuietSchedule,
    ) throws {
        guard intensityPercent.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "intensity")
        }
        guard (20.0 ... 100.0).contains(intensityPercent) else {
            throw ThrowValidationError.outOfRange(field: "intensity", closedRange: 20 ... 100)
        }
        self.locationMode = locationMode
        self.confirmedLocation = confirmedLocation
        self.calibration = calibration
        self.intensityPercent = intensityPercent
        self.quietSchedule = quietSchedule
    }

    public var description: String {
        "<ThrowGlobalPreferences sensitive-values=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

/// Preferences owned by the Air & Space experience.
public struct AirAndSpacePreferences: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let selectedSource: AircraftSourceConfiguration?
    public let validatedSource: AircraftSourceConfiguration?
    public let mapViewport: MapViewport
    public let mapCenters: MapCenterPreferences
    public let skyViewport: SkyViewport
    public let selectedProjectionMode: ProjectionMode?
    public let flightsEnabled: Bool
    public let airlineAccentsEnabled: Bool
    public let geography: GeographyPreferences
    public let labelMode: FlightLabelMode
    public let includeGroundAircraft: Bool
    public let markSizePercent: Double

    public init(
        selectedSource: AircraftSourceConfiguration?,
        validatedSource: AircraftSourceConfiguration?,
        mapViewport: MapViewport,
        mapCenters: MapCenterPreferences,
        skyViewport: SkyViewport,
        selectedProjectionMode: ProjectionMode?,
        flightsEnabled: Bool,
        airlineAccentsEnabled: Bool,
        geography: GeographyPreferences,
        labelMode: FlightLabelMode,
        includeGroundAircraft: Bool,
        markSizePercent: Double,
    ) throws {
        guard markSizePercent.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "markSize")
        }
        guard (50.0 ... 200.0).contains(markSizePercent) else {
            throw ThrowValidationError.outOfRange(field: "markSize", closedRange: 50 ... 200)
        }
        self.selectedSource = selectedSource
        self.validatedSource = validatedSource
        self.mapViewport = mapViewport
        self.mapCenters = mapCenters
        self.skyViewport = skyViewport
        self.selectedProjectionMode = selectedProjectionMode
        self.flightsEnabled = flightsEnabled
        self.airlineAccentsEnabled = airlineAccentsEnabled
        self.geography = geography
        self.labelMode = labelMode
        self.includeGroundAircraft = includeGroundAircraft
        self.markSizePercent = markSizePercent
    }

    public var isConfigured: Bool {
        guard let selectedSource else { return false }
        return validatedSource == selectedSource && selectedProjectionMode != nil
    }

    public var description: String {
        "<AirAndSpacePreferences sensitive-values=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

/// Throw's version-two preference model, grouped by global and experience ownership.
public struct ThrowPreferences: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static var defaultValue: ThrowPreferences {
        do {
            let global = try ThrowGlobalPreferences(
                locationMode: .gps,
                confirmedLocation: nil,
                calibration: .defaultValue,
                intensityPercent: 100,
                quietSchedule: .disabled,
            )
            let airAndSpace = try AirAndSpacePreferences(
                selectedSource: nil,
                validatedSource: nil,
                mapViewport: .defaultValue,
                mapCenters: .defaultValue,
                skyViewport: .defaultValue,
                selectedProjectionMode: nil,
                flightsEnabled: true,
                airlineAccentsEnabled: true,
                geography: .defaultValue,
                labelMode: .adaptive,
                includeGroundAircraft: false,
                markSizePercent: 100,
            )
            let playlist = try ProjectionPlaylist(
                entries: [],
                automaticRotationEnabled: false,
                selectedExperienceID: nil,
                configuredExperienceIDs: [],
                catalog: .standard,
            )
            return try ThrowPreferences(
                setupCompleted: false,
                global: global,
                playlist: playlist,
                airAndSpace: airAndSpace,
            )
        } catch {
            preconditionFailure("Throw's default preferences must be valid: \(error)")
        }
    }

    public let setupCompleted: Bool
    public let global: ThrowGlobalPreferences
    public let playlist: ProjectionPlaylist
    public let airAndSpace: AirAndSpacePreferences

    public init(
        setupCompleted: Bool,
        global: ThrowGlobalPreferences,
        playlist: ProjectionPlaylist,
        airAndSpace: AirAndSpacePreferences,
    ) throws {
        let configuredExperienceIDs: Set<ProjectionExperienceID> = airAndSpace.isConfigured
            ? [.airAndSpace]
            : []
        let validatedPlaylist = try ProjectionPlaylist(
            entries: playlist.entries,
            automaticRotationEnabled: playlist.automaticRotationEnabled,
            selectedExperienceID: playlist.selectedExperienceID,
            configuredExperienceIDs: configuredExperienceIDs,
            catalog: .standard,
        )
        if setupCompleted {
            guard global.confirmedLocation != nil,
                  airAndSpace.isConfigured,
                  validatedPlaylist.selectedExperienceID == .airAndSpace
            else {
                throw ThrowValidationError.invalidPreferencePayload
            }
        }
        self.setupCompleted = setupCompleted
        self.global = global
        self.playlist = validatedPlaylist
        self.airAndSpace = airAndSpace
    }

    /// Compatibility initializer while presentation call sites move to nested settings.
    public init(
        setupCompleted: Bool,
        selectedSource: AircraftSourceConfiguration?,
        validatedSource: AircraftSourceConfiguration?,
        locationMode: ObserverLocationMode,
        confirmedLocation: ConfirmedObserverLocation?,
        calibration: ProjectionCalibration,
        mapViewport: MapViewport,
        mapCenters: MapCenterPreferences,
        skyViewport: SkyViewport,
        selectedProjectionMode: ProjectionMode?,
        flightsEnabled: Bool,
        airlineAccentsEnabled: Bool,
        geography: GeographyPreferences,
        labelMode: FlightLabelMode,
        includeGroundAircraft: Bool,
        markSizePercent: Double,
        intensityPercent: Double,
        quietSchedule: QuietSchedule,
    ) throws {
        let global = try ThrowGlobalPreferences(
            locationMode: locationMode,
            confirmedLocation: confirmedLocation,
            calibration: calibration,
            intensityPercent: intensityPercent,
            quietSchedule: quietSchedule,
        )
        let airAndSpace = try AirAndSpacePreferences(
            selectedSource: selectedSource,
            validatedSource: validatedSource,
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            selectedProjectionMode: selectedProjectionMode,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
            markSizePercent: markSizePercent,
        )
        let entries = airAndSpace.isConfigured
            ? [
                ProjectionPlaylistEntry(
                    experienceID: .airAndSpace,
                    dwellDuration: .defaultValue,
                ),
            ]
            : []
        let playlist = try ProjectionPlaylist(
            entries: entries,
            automaticRotationEnabled: false,
            selectedExperienceID: airAndSpace.isConfigured ? .airAndSpace : nil,
            configuredExperienceIDs: airAndSpace.isConfigured ? [.airAndSpace] : [],
            catalog: .standard,
        )
        try self.init(
            setupCompleted: setupCompleted,
            global: global,
            playlist: playlist,
            airAndSpace: airAndSpace,
        )
    }

    public var selectedSource: AircraftSourceConfiguration? {
        airAndSpace.selectedSource
    }

    public var validatedSource: AircraftSourceConfiguration? {
        airAndSpace.validatedSource
    }

    public var locationMode: ObserverLocationMode {
        global.locationMode
    }

    public var confirmedLocation: ConfirmedObserverLocation? {
        global.confirmedLocation
    }

    public var calibration: ProjectionCalibration {
        global.calibration
    }

    public var mapViewport: MapViewport {
        airAndSpace.mapViewport
    }

    public var mapCenters: MapCenterPreferences {
        airAndSpace.mapCenters
    }

    public var skyViewport: SkyViewport {
        airAndSpace.skyViewport
    }

    public var selectedProjectionMode: ProjectionMode? {
        airAndSpace.selectedProjectionMode
    }

    public var flightsEnabled: Bool {
        airAndSpace.flightsEnabled
    }

    public var airlineAccentsEnabled: Bool {
        airAndSpace.airlineAccentsEnabled
    }

    public var geography: GeographyPreferences {
        airAndSpace.geography
    }

    public var labelMode: FlightLabelMode {
        airAndSpace.labelMode
    }

    public var includeGroundAircraft: Bool {
        airAndSpace.includeGroundAircraft
    }

    public var markSizePercent: Double {
        airAndSpace.markSizePercent
    }

    public var intensityPercent: Double {
        global.intensityPercent
    }

    public var quietSchedule: QuietSchedule {
        global.quietSchedule
    }

    public var description: String {
        "<ThrowPreferences sensitive-values=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public enum ThrowPreferenceStoreError: Error, Equatable, Sendable {
    case invalidPayload
}

public protocol ThrowPreferenceStore: Sendable {
    func load() async throws -> ThrowPreferences
    func save(_ preferences: ThrowPreferences) async throws
}

public actor UserDefaultsThrowPreferenceStore: ThrowPreferenceStore {
    private static let storageKey = "Throw.preferences.v1"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    public func load() throws -> ThrowPreferences {
        guard let value = userDefaults.object(forKey: Self.storageKey) else {
            return .defaultValue
        }
        guard let data = value as? Data else {
            throw ThrowPreferenceStoreError.invalidPayload
        }
        return try ThrowPreferencesCodec.decode(data)
    }

    public func save(_ preferences: ThrowPreferences) throws {
        try userDefaults.set(ThrowPreferencesCodec.encode(preferences), forKey: Self.storageKey)
    }
}

/// A property-list round-tripping fake for tests and previews; it rejects the
/// same corrupt shapes as the production store without touching UserDefaults.
public actor MemoryThrowPreferenceStore: ThrowPreferenceStore {
    private var data: Data

    public init(initialValue: ThrowPreferences) throws {
        data = try ThrowPreferencesCodec.encode(initialValue)
    }

    public func load() throws -> ThrowPreferences {
        try ThrowPreferencesCodec.decode(data)
    }

    public func save(_ preferences: ThrowPreferences) throws {
        data = try ThrowPreferencesCodec.encode(preferences)
    }
}

enum ThrowPreferencesCodec {
    static func encode(_ preferences: ThrowPreferences) throws -> Data {
        do {
            return try PropertyListEncoder().encode(Storage(preferences))
        } catch {
            throw ThrowPreferenceStoreError.invalidPayload
        }
    }

    static func decode(_ data: Data) throws -> ThrowPreferences {
        do {
            return try PropertyListDecoder().decode(Storage.self, from: data).preferences()
        } catch {
            throw ThrowPreferenceStoreError.invalidPayload
        }
    }

    private struct Storage: Codable {
        let version: Int
        let setupCompleted: Bool

        let global: GlobalStorage?
        let playlist: PlaylistStorage?
        let airAndSpace: AirAndSpaceStorage?

        // Version-one fields. Keep them decodable while the storage key remains stable.
        let selectedSource: SourceStorage?
        let validatedSource: SourceStorage?
        let locationMode: String?
        let confirmedLocation: LocationStorage?
        let calibration: CalibrationStorage?
        let mapRadius: Double?
        let mapCenters: [MapCenterStorage]?
        let skyMinimumElevation: Double?
        let selectedProjectionMode: String?
        let flightsEnabled: Bool?
        let airlineAccentsEnabled: Bool?
        let geography: GeographyStorage?
        let labelMode: String?
        let includeGroundAircraft: Bool?
        let markSizePercent: Double?
        let intensityPercent: Double?
        let quietInterval: QuietStorage?

        init(_ preferences: ThrowPreferences) {
            version = 2
            setupCompleted = preferences.setupCompleted
            global = GlobalStorage(preferences.global)
            playlist = PlaylistStorage(preferences.playlist)
            airAndSpace = AirAndSpaceStorage(preferences.airAndSpace)
            selectedSource = nil
            validatedSource = nil
            locationMode = nil
            confirmedLocation = nil
            calibration = nil
            mapRadius = nil
            mapCenters = nil
            skyMinimumElevation = nil
            selectedProjectionMode = nil
            flightsEnabled = nil
            airlineAccentsEnabled = nil
            geography = nil
            labelMode = nil
            includeGroundAircraft = nil
            markSizePercent = nil
            intensityPercent = nil
            quietInterval = nil
        }

        func preferences() throws -> ThrowPreferences {
            switch version {
                case 1:
                    try versionOnePreferences()
                case 2:
                    try versionTwoPreferences()
                default:
                    throw ThrowPreferenceStoreError.invalidPayload
            }
        }

        private func versionTwoPreferences() throws -> ThrowPreferences {
            guard let global, let playlist, let airAndSpace else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            let globalPreferences = try global.value()
            let airAndSpacePreferences = try airAndSpace.value()
            let configuredIDs: Set<ProjectionExperienceID> = airAndSpacePreferences.isConfigured
                ? [.airAndSpace]
                : []
            let projectionPlaylist = try playlist.value(configuredExperienceIDs: configuredIDs)
            return try ThrowPreferences(
                setupCompleted: setupCompleted,
                global: globalPreferences,
                playlist: projectionPlaylist,
                airAndSpace: airAndSpacePreferences,
            )
        }

        private func versionOnePreferences() throws -> ThrowPreferences {
            guard let locationMode,
                  let locationMode = ObserverLocationMode(rawValue: locationMode),
                  let calibration,
                  let mapRadius,
                  let skyMinimumElevation,
                  let flightsEnabled,
                  let labelMode,
                  let labelMode = FlightLabelMode(rawValue: labelMode),
                  let includeGroundAircraft,
                  let markSizePercent,
                  let intensityPercent
            else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            let selectedMode: ProjectionMode?
            if let selectedProjectionMode {
                guard let mode = ProjectionMode(rawValue: selectedProjectionMode) else {
                    throw ThrowPreferenceStoreError.invalidPayload
                }
                selectedMode = mode
            } else {
                selectedMode = nil
            }
            let schedule: QuietSchedule = if let quietInterval {
                try quietInterval.schedule()
            } else {
                .disabled
            }
            let globalPreferences = try ThrowGlobalPreferences(
                locationMode: locationMode,
                confirmedLocation: confirmedLocation?.location(),
                calibration: calibration.value(),
                intensityPercent: intensityPercent,
                quietSchedule: schedule,
            )
            let airAndSpacePreferences = try AirAndSpacePreferences(
                selectedSource: selectedSource?.configuration(),
                validatedSource: validatedSource?.configuration(),
                mapViewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
                mapCenters: MapCenterPreferences(
                    profiles: (mapCenters ?? []).map { try $0.value() },
                ),
                skyViewport: SkyViewport(
                    minimumElevation: ElevationAngle(degrees: skyMinimumElevation),
                ),
                selectedProjectionMode: selectedMode,
                flightsEnabled: flightsEnabled,
                airlineAccentsEnabled: airlineAccentsEnabled ?? true,
                geography: geography?.value() ?? .defaultValue,
                labelMode: labelMode,
                includeGroundAircraft: includeGroundAircraft,
                markSizePercent: markSizePercent,
            )
            let entries = airAndSpacePreferences.isConfigured
                ? [
                    ProjectionPlaylistEntry(
                        experienceID: .airAndSpace,
                        dwellDuration: .defaultValue,
                    ),
                ]
                : []
            let playlist = try ProjectionPlaylist(
                entries: entries,
                automaticRotationEnabled: false,
                selectedExperienceID: airAndSpacePreferences.isConfigured ? .airAndSpace : nil,
                configuredExperienceIDs: airAndSpacePreferences.isConfigured
                    ? [.airAndSpace]
                    : [],
                catalog: .standard,
            )
            return try ThrowPreferences(
                setupCompleted: setupCompleted,
                global: globalPreferences,
                playlist: playlist,
                airAndSpace: airAndSpacePreferences,
            )
        }
    }

    private struct GlobalStorage: Codable {
        let locationMode: String
        let confirmedLocation: LocationStorage?
        let calibration: CalibrationStorage
        let intensityPercent: Double
        let quietInterval: QuietStorage?

        init(_ preferences: ThrowGlobalPreferences) {
            locationMode = preferences.locationMode.rawValue
            confirmedLocation = preferences.confirmedLocation.map(LocationStorage.init)
            calibration = CalibrationStorage(preferences.calibration)
            intensityPercent = preferences.intensityPercent
            quietInterval = preferences.quietSchedule.interval.map(QuietStorage.init)
        }

        func value() throws -> ThrowGlobalPreferences {
            guard let locationMode = ObserverLocationMode(rawValue: locationMode) else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            let schedule: QuietSchedule = if let quietInterval {
                try quietInterval.schedule()
            } else {
                .disabled
            }
            return try ThrowGlobalPreferences(
                locationMode: locationMode,
                confirmedLocation: confirmedLocation?.location(),
                calibration: calibration.value(),
                intensityPercent: intensityPercent,
                quietSchedule: schedule,
            )
        }
    }

    private struct AirAndSpaceStorage: Codable {
        let selectedSource: SourceStorage?
        let validatedSource: SourceStorage?
        let mapRadius: Double
        let mapCenters: [MapCenterStorage]
        let skyMinimumElevation: Double
        let selectedProjectionMode: String?
        let flightsEnabled: Bool
        let airlineAccentsEnabled: Bool?
        let geography: GeographyStorage?
        let labelMode: String
        let includeGroundAircraft: Bool
        let markSizePercent: Double

        init(_ preferences: AirAndSpacePreferences) {
            selectedSource = preferences.selectedSource.map(SourceStorage.init)
            validatedSource = preferences.validatedSource.map(SourceStorage.init)
            mapRadius = preferences.mapViewport.radius.value
            mapCenters = preferences.mapCenters.profiles.map(MapCenterStorage.init)
            skyMinimumElevation = preferences.skyViewport.minimumElevation.degrees
            selectedProjectionMode = preferences.selectedProjectionMode?.rawValue
            flightsEnabled = preferences.flightsEnabled
            airlineAccentsEnabled = preferences.airlineAccentsEnabled
            geography = GeographyStorage(preferences.geography)
            labelMode = preferences.labelMode.rawValue
            includeGroundAircraft = preferences.includeGroundAircraft
            markSizePercent = preferences.markSizePercent
        }

        func value() throws -> AirAndSpacePreferences {
            guard let labelMode = FlightLabelMode(rawValue: labelMode) else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            let selectedMode: ProjectionMode?
            if let selectedProjectionMode {
                guard let mode = ProjectionMode(rawValue: selectedProjectionMode) else {
                    throw ThrowPreferenceStoreError.invalidPayload
                }
                selectedMode = mode
            } else {
                selectedMode = nil
            }
            return try AirAndSpacePreferences(
                selectedSource: selectedSource?.configuration(),
                validatedSource: validatedSource?.configuration(),
                mapViewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
                mapCenters: MapCenterPreferences(profiles: mapCenters.map { try $0.value() }),
                skyViewport: SkyViewport(
                    minimumElevation: ElevationAngle(degrees: skyMinimumElevation),
                ),
                selectedProjectionMode: selectedMode,
                flightsEnabled: flightsEnabled,
                airlineAccentsEnabled: airlineAccentsEnabled ?? true,
                geography: geography?.value() ?? .defaultValue,
                labelMode: labelMode,
                includeGroundAircraft: includeGroundAircraft,
                markSizePercent: markSizePercent,
            )
        }
    }

    private struct PlaylistStorage: Codable {
        let entries: [PlaylistEntryStorage]
        let automaticRotationEnabled: Bool
        let selectedExperienceID: String?

        init(_ playlist: ProjectionPlaylist) {
            entries = playlist.entries.map(PlaylistEntryStorage.init)
            automaticRotationEnabled = playlist.automaticRotationEnabled
            selectedExperienceID = playlist.selectedExperienceID?.rawValue
        }

        func value(
            configuredExperienceIDs: Set<ProjectionExperienceID>,
        ) throws -> ProjectionPlaylist {
            let selectedID = selectedExperienceID.map(ProjectionExperienceID.init(rawValue:))
            return try ProjectionPlaylist(
                entries: entries.map { try $0.value() },
                automaticRotationEnabled: automaticRotationEnabled,
                selectedExperienceID: selectedID,
                configuredExperienceIDs: configuredExperienceIDs,
                catalog: .standard,
            )
        }
    }

    private struct PlaylistEntryStorage: Codable {
        let experienceID: String
        let dwellSeconds: Int

        init(_ entry: ProjectionPlaylistEntry) {
            experienceID = entry.experienceID.rawValue
            dwellSeconds = entry.dwellDuration.seconds
        }

        func value() throws -> ProjectionPlaylistEntry {
            try ProjectionPlaylistEntry(
                experienceID: ProjectionExperienceID(rawValue: experienceID),
                dwellDuration: ProjectionDwellDuration(seconds: dwellSeconds),
            )
        }
    }

    private struct MapCenterStorage: Codable {
        let latitudeBand: Int
        let longitudeBand: Int
        let latitude: Double
        let longitude: Double

        init(_ profile: MapCenterProfile) {
            latitudeBand = profile.regionID.latitudeBand
            longitudeBand = profile.regionID.longitudeBand
            latitude = profile.center.latitude
            longitude = profile.center.longitude
        }

        func value() throws -> MapCenterProfile {
            try MapCenterProfile(
                regionID: MapRegionID(
                    latitudeBand: latitudeBand,
                    longitudeBand: longitudeBand,
                ),
                center: GeoCoordinate(latitude: latitude, longitude: longitude),
            )
        }
    }

    private struct GeographyStorage: Codable {
        let isEnabled: Bool
        let intensityPercent: Double

        init(_ preferences: GeographyPreferences) {
            isEnabled = preferences.isEnabled
            intensityPercent = preferences.intensityPercent
        }

        func value() throws -> GeographyPreferences {
            try GeographyPreferences(
                isEnabled: isEnabled,
                intensityPercent: intensityPercent,
            )
        }
    }

    private struct SourceStorage: Codable {
        let kind: String
        let readsbURL: String?
        let cadenceSeconds: Int?
        let credentialID: String?

        init(_ source: AircraftSourceConfiguration) {
            switch source {
                case .adsbLol:
                    kind = AircraftSourceKind.adsbLol.rawValue
                    readsbURL = nil
                    cadenceSeconds = nil
                    credentialID = nil
                case let .readsb(configuration):
                    kind = AircraftSourceKind.readsb.rawValue
                    readsbURL = configuration.aircraftJSONURL.absoluteString
                    cadenceSeconds = nil
                    credentialID = nil
                case let .adsbExchangeRapidAPI(configuration):
                    kind = AircraftSourceKind.adsbExchangeRapidAPI.rawValue
                    readsbURL = nil
                    cadenceSeconds = configuration.pollingInterval.seconds
                    credentialID = configuration.credentialID.rawValue
                case let .flightradar24(configuration):
                    kind = AircraftSourceKind.flightradar24.rawValue
                    readsbURL = nil
                    cadenceSeconds = configuration.pollingInterval.seconds
                    credentialID = configuration.credentialID.rawValue
            }
        }

        func configuration() throws -> AircraftSourceConfiguration {
            guard let sourceKind = AircraftSourceKind(rawValue: kind) else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            switch sourceKind {
                case .adsbLol:
                    guard readsbURL == nil, cadenceSeconds == nil, credentialID == nil else {
                        throw ThrowPreferenceStoreError.invalidPayload
                    }
                    return .adsbLol
                case .readsb:
                    guard let readsbURL, let url = URL(string: readsbURL),
                          cadenceSeconds == nil, credentialID == nil
                    else {
                        throw ThrowPreferenceStoreError.invalidPayload
                    }
                    return try .readsb(ReadsbConfiguration(aircraftJSONURL: url))
                case .adsbExchangeRapidAPI:
                    guard readsbURL == nil, let cadenceSeconds, let credentialID else {
                        throw ThrowPreferenceStoreError.invalidPayload
                    }
                    return try .adsbExchangeRapidAPI(
                        ADSBExchangeConfiguration(
                            pollingInterval: PollingInterval(seconds: cadenceSeconds),
                            credentialID: AircraftCredentialID(rawValue: credentialID),
                        ),
                    )
                case .flightradar24:
                    guard readsbURL == nil, let cadenceSeconds, let credentialID else {
                        throw ThrowPreferenceStoreError.invalidPayload
                    }
                    return try .flightradar24(
                        Flightradar24Configuration(
                            pollingInterval: PollingInterval(seconds: cadenceSeconds),
                            credentialID: AircraftCredentialID(rawValue: credentialID),
                        ),
                    )
            }
        }
    }

    private struct LocationStorage: Codable {
        let latitude: Double
        let longitude: Double
        let altitudeFeet: Double
        let horizontalAccuracyMeters: Double?
        let confirmedAt: Date

        init(_ location: ConfirmedObserverLocation) {
            latitude = location.position.coordinate.latitude
            longitude = location.position.coordinate.longitude
            altitudeFeet = location.position.altitude.feet
            horizontalAccuracyMeters = location.horizontalAccuracyMeters
            confirmedAt = location.confirmedAt
        }

        func location() throws -> ConfirmedObserverLocation {
            try ConfirmedObserverLocation(
                position: ObserverPosition(
                    coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                    altitude: Altitude(feet: altitudeFeet),
                ),
                horizontalAccuracyMeters: horizontalAccuracyMeters,
                confirmedAt: confirmedAt,
            )
        }
    }

    private struct CalibrationStorage: Codable {
        let topBearing: Double
        let rotation: Int
        let flipHorizontal: Bool
        let flipVertical: Bool
        let safeInsetFraction: Double
        let verified: Bool

        init(_ calibration: ProjectionCalibration) {
            topBearing = calibration.screenTopBearing.degrees
            rotation = calibration.rotation.rawValue
            flipHorizontal = calibration.flipHorizontal
            flipVertical = calibration.flipVertical
            safeInsetFraction = calibration.safeInsetFraction
            verified = calibration.verifiedOnExternalDisplay
        }

        func value() throws -> ProjectionCalibration {
            guard let rotation = ScreenRotation(rawValue: rotation) else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            return try ProjectionCalibration(
                screenTopBearing: Bearing(degrees: topBearing),
                rotation: rotation,
                flipHorizontal: flipHorizontal,
                flipVertical: flipVertical,
                safeInsetFraction: safeInsetFraction,
                verifiedOnExternalDisplay: verified,
            )
        }
    }

    private struct QuietStorage: Codable {
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int

        init(_ interval: DailyQuietInterval) {
            startHour = interval.start.hour
            startMinute = interval.start.minute
            endHour = interval.end.hour
            endMinute = interval.end.minute
        }

        func schedule() throws -> QuietSchedule {
            try QuietSchedule(
                start: LocalTime(hour: startHour, minute: startMinute),
                end: LocalTime(hour: endHour, minute: endMinute),
            )
        }
    }
}
