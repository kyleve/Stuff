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

public enum ObserverLocationSetupState: Equatable, Sendable {
    case unconfirmed(mode: ObserverLocationMode)
    case confirmed(mode: ObserverLocationMode, location: ConfirmedObserverLocation)
}

public enum ProjectionSetupState: Equatable, Sendable {
    case unselected
    case selected(ProjectionMode)
}

/// The setup values that can be incomplete while onboarding is in progress.
public struct ThrowOnboardingSetup: Equatable, Sendable {
    public let sourceSelection: AircraftSourceSelection
    public let location: ObserverLocationSetupState
    public let projection: ProjectionSetupState

    public init(
        sourceSelection: AircraftSourceSelection,
        location: ObserverLocationSetupState,
        projection: ProjectionSetupState,
    ) {
        self.sourceSelection = sourceSelection
        self.location = location
        self.projection = projection
    }
}

/// The required setup values for an operational Throw session.
public struct ThrowConfiguredSetup: Equatable, Sendable {
    public let source: AircraftSourceConfiguration
    public let locationMode: ObserverLocationMode
    public let confirmedLocation: ConfirmedObserverLocation
    public let projectionMode: ProjectionMode

    public init(
        source: AircraftSourceConfiguration,
        locationMode: ObserverLocationMode,
        confirmedLocation: ConfirmedObserverLocation,
        projectionMode: ProjectionMode,
    ) {
        self.source = source
        self.locationMode = locationMode
        self.confirmedLocation = confirmedLocation
        self.projectionMode = projectionMode
    }
}

/// The setup lifecycle. A configured value always contains every required input.
public enum ThrowSetupState: Equatable, Sendable {
    case onboarding(ThrowOnboardingSetup)
    case configured(ThrowConfiguredSetup)

    public static let defaultValue = ThrowSetupState.onboarding(
        ThrowOnboardingSetup(
            sourceSelection: .unconfigured,
            location: .unconfirmed(mode: .gps),
            projection: .unselected,
        ),
    )

    public var setupCompleted: Bool {
        if case .configured = self { true } else { false }
    }

    public var selectedSource: AircraftSourceConfiguration? {
        switch self {
            case let .onboarding(setup): setup.sourceSelection.selectedSource
            case let .configured(setup): setup.source
        }
    }

    public var validatedSource: AircraftSourceConfiguration? {
        switch self {
            case let .onboarding(setup): setup.sourceSelection.validatedSource
            case let .configured(setup): setup.source
        }
    }

    public var locationMode: ObserverLocationMode {
        switch self {
            case let .onboarding(setup):
                switch setup.location {
                    case let .unconfirmed(mode), let .confirmed(mode, _): mode
                }
            case let .configured(setup): setup.locationMode
        }
    }

    public var confirmedLocation: ConfirmedObserverLocation? {
        switch self {
            case let .onboarding(setup):
                if case let .confirmed(_, location) = setup.location { location } else { nil }
            case let .configured(setup): setup.confirmedLocation
        }
    }

    public var selectedProjectionMode: ProjectionMode? {
        switch self {
            case let .onboarding(setup):
                if case let .selected(mode) = setup.projection { mode } else { nil }
            case let .configured(setup): setup.projectionMode
        }
    }

    public var sourceSelection: AircraftSourceSelection {
        switch self {
            case let .onboarding(setup): setup.sourceSelection
            case let .configured(setup): .configured(setup.source)
        }
    }

    public var configuredExperienceIDs: Set<RunnableProjectionExperienceID> {
        airAndSpaceIsConfigured ? [.airAndSpace] : []
    }

    private var airAndSpaceIsConfigured: Bool {
        validatedSource != nil && selectedProjectionMode != nil
    }
}

/// Preferences shared by every projection experience.
public struct ThrowGlobalPreferences: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let calibration: ProjectionCalibration
    public let intensityPercent: Double
    public let quietSchedule: QuietSchedule

    public init(
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
        self.calibration = calibration
        self.intensityPercent = intensityPercent
        self.quietSchedule = quietSchedule
    }

    public func replacingCalibration(_ calibration: ProjectionCalibration) -> Self {
        Self(
            validatedCalibration: calibration,
            intensityPercent: intensityPercent,
            quietSchedule: quietSchedule,
        )
    }

    public func replacingIntensityPercent(_ intensityPercent: Double) throws -> Self {
        try Self(
            calibration: calibration,
            intensityPercent: intensityPercent,
            quietSchedule: quietSchedule,
        )
    }

    public func replacingQuietSchedule(_ quietSchedule: QuietSchedule) -> Self {
        Self(
            validatedCalibration: calibration,
            intensityPercent: intensityPercent,
            quietSchedule: quietSchedule,
        )
    }

    public var description: String {
        "<ThrowGlobalPreferences sensitive-values=<redacted>>"
    }

    public var debugDescription: String {
        description
    }

    private init(
        validatedCalibration calibration: ProjectionCalibration,
        intensityPercent: Double,
        quietSchedule: QuietSchedule,
    ) {
        self.calibration = calibration
        self.intensityPercent = intensityPercent
        self.quietSchedule = quietSchedule
    }
}

/// Preferences owned by the Air & Space experience.
public struct AirAndSpacePreferences: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let mapViewport: MapViewport
    public let mapCenters: MapCenterPreferences
    public let skyViewport: SkyViewport
    public let flightsEnabled: Bool
    public let airlineAccentsEnabled: Bool
    public let geography: GeographyPreferences
    public let labelMode: FlightLabelMode
    public let includeGroundAircraft: Bool
    public let markSizePercent: Double

    public init(
        mapViewport: MapViewport,
        mapCenters: MapCenterPreferences,
        skyViewport: SkyViewport,
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
        self.mapViewport = mapViewport
        self.mapCenters = mapCenters
        self.skyViewport = skyViewport
        self.flightsEnabled = flightsEnabled
        self.airlineAccentsEnabled = airlineAccentsEnabled
        self.geography = geography
        self.labelMode = labelMode
        self.includeGroundAircraft = includeGroundAircraft
        self.markSizePercent = markSizePercent
    }

    public func replacingMapViewport(_ mapViewport: MapViewport) -> Self {
        replacing(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
        )
    }

    public func replacingMapCenters(_ mapCenters: MapCenterPreferences) -> Self {
        replacing(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
        )
    }

    public func replacingSkyViewport(_ skyViewport: SkyViewport) -> Self {
        replacing(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
        )
    }

    public func replacingFlightsEnabled(_ flightsEnabled: Bool) -> Self {
        replacing(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
        )
    }

    public func replacingAirlineAccentsEnabled(_ airlineAccentsEnabled: Bool) -> Self {
        replacing(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
        )
    }

    public func replacingGeography(_ geography: GeographyPreferences) -> Self {
        replacing(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
        )
    }

    public func replacingLabelMode(_ labelMode: FlightLabelMode) -> Self {
        replacing(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
        )
    }

    public func replacingIncludeGroundAircraft(_ includeGroundAircraft: Bool) -> Self {
        replacing(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
        )
    }

    public func replacingMarkSizePercent(_ markSizePercent: Double) throws -> Self {
        try Self(
            mapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
            markSizePercent: markSizePercent,
        )
    }

    public var description: String {
        "<AirAndSpacePreferences sensitive-values=<redacted>>"
    }

    public var debugDescription: String {
        description
    }

    private func replacing(
        mapViewport: MapViewport,
        mapCenters: MapCenterPreferences,
        skyViewport: SkyViewport,
        flightsEnabled: Bool,
        airlineAccentsEnabled: Bool,
        geography: GeographyPreferences,
        labelMode: FlightLabelMode,
        includeGroundAircraft: Bool,
    ) -> Self {
        Self(
            validatedMapViewport: mapViewport,
            mapCenters: mapCenters,
            skyViewport: skyViewport,
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: geography,
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
            markSizePercent: markSizePercent,
        )
    }

    private init(
        validatedMapViewport mapViewport: MapViewport,
        mapCenters: MapCenterPreferences,
        skyViewport: SkyViewport,
        flightsEnabled: Bool,
        airlineAccentsEnabled: Bool,
        geography: GeographyPreferences,
        labelMode: FlightLabelMode,
        includeGroundAircraft: Bool,
        markSizePercent: Double,
    ) {
        self.mapViewport = mapViewport
        self.mapCenters = mapCenters
        self.skyViewport = skyViewport
        self.flightsEnabled = flightsEnabled
        self.airlineAccentsEnabled = airlineAccentsEnabled
        self.geography = geography
        self.labelMode = labelMode
        self.includeGroundAircraft = includeGroundAircraft
        self.markSizePercent = markSizePercent
    }
}

public enum TransitConfiguration: Equatable, Sendable {
    case unconfigured
    case configured(cityID: TransitCityID)

    public var cityID: TransitCityID? {
        switch self {
            case .unconfigured: nil
            case let .configured(cityID): cityID
        }
    }
}

/// Preferences owned by the Transit experience.
public struct TransitPreferences: Equatable, Sendable {
    public static let defaultValue: TransitPreferences = {
        do {
            return try TransitPreferences(
                configuration: .unconfigured,
                mapCenter: GeoCoordinate(latitude: 40.7128, longitude: -73.98),
                mapViewport: .defaultValue,
                labelMode: .routeOnly,
                geography: .defaultValue,
                markSizePercent: 100,
                networkIntensityPercent: 100,
            )
        } catch {
            preconditionFailure("Throw's default Transit preferences must be valid: \(error)")
        }
    }()

    public let configuration: TransitConfiguration
    public let mapCenter: GeoCoordinate
    public let mapViewport: TransitMapViewport
    public let labelMode: TransitLabelMode
    public let geography: GeographyPreferences
    public let markSizePercent: Double
    public let networkIntensityPercent: Double

    public init(
        configuration: TransitConfiguration,
        mapCenter: GeoCoordinate,
        mapViewport: TransitMapViewport,
        labelMode: TransitLabelMode,
        geography: GeographyPreferences,
        markSizePercent: Double,
        networkIntensityPercent: Double,
    ) throws {
        guard markSizePercent.isFinite, (50 ... 200).contains(markSizePercent),
              networkIntensityPercent.isFinite,
              (20 ... 100).contains(networkIntensityPercent)
        else {
            throw ThrowValidationError.invalidPreferencePayload
        }
        self.configuration = configuration
        self.mapCenter = mapCenter
        self.mapViewport = mapViewport
        self.labelMode = labelMode
        self.geography = geography
        self.markSizePercent = markSizePercent
        self.networkIntensityPercent = networkIntensityPercent
    }

    public func replacingConfiguration(_ configuration: TransitConfiguration) -> Self {
        replacing(
            configuration: configuration,
            mapCenter: mapCenter,
            mapViewport: mapViewport,
            labelMode: labelMode,
            geography: geography,
        )
    }

    public func replacingMapCenter(_ mapCenter: GeoCoordinate) -> Self {
        replacing(
            configuration: configuration,
            mapCenter: mapCenter,
            mapViewport: mapViewport,
            labelMode: labelMode,
            geography: geography,
        )
    }

    public func replacingMapViewport(_ mapViewport: TransitMapViewport) -> Self {
        replacing(
            configuration: configuration,
            mapCenter: mapCenter,
            mapViewport: mapViewport,
            labelMode: labelMode,
            geography: geography,
        )
    }

    public func replacingLabelMode(_ labelMode: TransitLabelMode) -> Self {
        replacing(
            configuration: configuration,
            mapCenter: mapCenter,
            mapViewport: mapViewport,
            labelMode: labelMode,
            geography: geography,
        )
    }

    public func replacingGeography(_ geography: GeographyPreferences) -> Self {
        replacing(
            configuration: configuration,
            mapCenter: mapCenter,
            mapViewport: mapViewport,
            labelMode: labelMode,
            geography: geography,
        )
    }

    public func replacingMarkSizePercent(_ markSizePercent: Double) throws -> Self {
        try Self(
            configuration: configuration,
            mapCenter: mapCenter,
            mapViewport: mapViewport,
            labelMode: labelMode,
            geography: geography,
            markSizePercent: markSizePercent,
            networkIntensityPercent: networkIntensityPercent,
        )
    }

    public func replacingNetworkIntensityPercent(
        _ networkIntensityPercent: Double,
    ) throws -> Self {
        try Self(
            configuration: configuration,
            mapCenter: mapCenter,
            mapViewport: mapViewport,
            labelMode: labelMode,
            geography: geography,
            markSizePercent: markSizePercent,
            networkIntensityPercent: networkIntensityPercent,
        )
    }

    public var isConfigured: Bool {
        configuration.cityID != nil
    }

    private func replacing(
        configuration: TransitConfiguration,
        mapCenter: GeoCoordinate,
        mapViewport: TransitMapViewport,
        labelMode: TransitLabelMode,
        geography: GeographyPreferences,
    ) -> Self {
        Self(
            validatedConfiguration: configuration,
            mapCenter: mapCenter,
            mapViewport: mapViewport,
            labelMode: labelMode,
            geography: geography,
            markSizePercent: markSizePercent,
            networkIntensityPercent: networkIntensityPercent,
        )
    }

    private init(
        validatedConfiguration configuration: TransitConfiguration,
        mapCenter: GeoCoordinate,
        mapViewport: TransitMapViewport,
        labelMode: TransitLabelMode,
        geography: GeographyPreferences,
        markSizePercent: Double,
        networkIntensityPercent: Double,
    ) {
        self.configuration = configuration
        self.mapCenter = mapCenter
        self.mapViewport = mapViewport
        self.labelMode = labelMode
        self.geography = geography
        self.markSizePercent = markSizePercent
        self.networkIntensityPercent = networkIntensityPercent
    }
}

/// Throw's version-four preference model, grouped by global and experience ownership.
public struct ThrowPreferences: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static var defaultValue: ThrowPreferences {
        do {
            let global = try ThrowGlobalPreferences(
                calibration: .defaultValue,
                intensityPercent: 100,
                quietSchedule: .disabled,
            )
            let airAndSpace = try AirAndSpacePreferences(
                mapViewport: .defaultValue,
                mapCenters: .defaultValue,
                skyViewport: .defaultValue,
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
                setupState: .defaultValue,
                global: global,
                playlist: playlist,
                airAndSpace: airAndSpace,
                transit: .defaultValue,
            )
        } catch {
            preconditionFailure("Throw's default preferences must be valid: \(error)")
        }
    }

    public let setupState: ThrowSetupState
    public let global: ThrowGlobalPreferences
    public let playlist: ProjectionPlaylist
    public let airAndSpace: AirAndSpacePreferences
    public let transit: TransitPreferences

    public var configuredExperienceIDs: Set<RunnableProjectionExperienceID> {
        var ids = setupState.configuredExperienceIDs
        if transit.isConfigured {
            ids.insert(.transit)
        }
        return ids
    }

    public var setupCompleted: Bool {
        setupState.setupCompleted
    }

    public var selectedSource: AircraftSourceConfiguration? {
        setupState.selectedSource
    }

    public var validatedSource: AircraftSourceConfiguration? {
        setupState.validatedSource
    }

    public var locationMode: ObserverLocationMode {
        setupState.locationMode
    }

    public var confirmedLocation: ConfirmedObserverLocation? {
        setupState.confirmedLocation
    }

    public var selectedProjectionMode: ProjectionMode? {
        setupState.selectedProjectionMode
    }

    public init(
        setupState: ThrowSetupState,
        global: ThrowGlobalPreferences,
        playlist: ProjectionPlaylist,
        airAndSpace: AirAndSpacePreferences,
        transit: TransitPreferences,
    ) throws {
        var configuredExperienceIDs = setupState.configuredExperienceIDs
        if transit.isConfigured {
            configuredExperienceIDs.insert(.transit)
        }
        let validatedPlaylist = try ProjectionPlaylist(
            entries: playlist.entries,
            automaticRotationEnabled: playlist.automaticRotationEnabled,
            selectedExperienceID: playlist.selectedRunnableExperienceID,
            configuredExperienceIDs: configuredExperienceIDs,
            catalog: .standard,
        )
        if setupState.setupCompleted {
            guard validatedPlaylist.entry(for: .airAndSpace) != nil,
                  validatedPlaylist.selectedRunnableExperienceID != nil
            else {
                throw ThrowValidationError.invalidPreferencePayload
            }
        }
        self.setupState = setupState
        self.global = global
        self.playlist = validatedPlaylist
        self.airAndSpace = airAndSpace
        self.transit = transit
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
        let transit: TransitStorage?

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
            version = 4
            setupCompleted = preferences.setupCompleted
            global = GlobalStorage(preferences)
            playlist = PlaylistStorage(preferences.playlist)
            airAndSpace = AirAndSpaceStorage(preferences)
            transit = TransitStorage(preferences.transit)
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
                case 3:
                    try versionThreePreferences()
                case 4:
                    try versionFourPreferences()
                default:
                    throw ThrowPreferenceStoreError.invalidPayload
            }
        }

        private func versionTwoPreferences() throws -> ThrowPreferences {
            guard let global, let playlist, let airAndSpace else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            let decodedGlobal = try global.value()
            let decodedAirAndSpace = try airAndSpace.value()
            let setupState = try setupState(
                sourceSelection: decodedAirAndSpace.sourceSelection,
                locationMode: decodedGlobal.locationMode,
                confirmedLocation: decodedGlobal.confirmedLocation,
                selectedProjectionMode: decodedAirAndSpace.selectedProjectionMode,
            )
            let configuredIDs = setupState.configuredExperienceIDs
            let projectionPlaylist = try playlist.value(configuredExperienceIDs: configuredIDs)
            return try ThrowPreferences(
                setupState: setupState,
                global: decodedGlobal.preferences,
                playlist: projectionPlaylist,
                airAndSpace: decodedAirAndSpace.preferences,
                transit: .defaultValue,
            )
        }

        private func versionThreePreferences() throws -> ThrowPreferences {
            guard let global, let playlist, let airAndSpace, let transit else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            let decodedGlobal = try global.value()
            let decodedAirAndSpace = try airAndSpace.value()
            let transitPreferences = try transit.versionThreeValue()
            let setupState = try setupState(
                sourceSelection: decodedAirAndSpace.sourceSelection,
                locationMode: decodedGlobal.locationMode,
                confirmedLocation: decodedGlobal.confirmedLocation,
                selectedProjectionMode: decodedAirAndSpace.selectedProjectionMode,
            )
            var configuredIDs = setupState.configuredExperienceIDs
            if transitPreferences.isConfigured {
                configuredIDs.insert(.transit)
            }
            let projectionPlaylist = try playlist.value(configuredExperienceIDs: configuredIDs)
            return try ThrowPreferences(
                setupState: setupState,
                global: decodedGlobal.preferences,
                playlist: projectionPlaylist,
                airAndSpace: decodedAirAndSpace.preferences,
                transit: transitPreferences,
            )
        }

        private func versionFourPreferences() throws -> ThrowPreferences {
            guard let global, let playlist, let airAndSpace, let transit else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            let decodedGlobal = try global.value()
            let decodedAirAndSpace = try airAndSpace.value()
            let transitPreferences = try transit.value()
            let setupState = try setupState(
                sourceSelection: decodedAirAndSpace.sourceSelection,
                locationMode: decodedGlobal.locationMode,
                confirmedLocation: decodedGlobal.confirmedLocation,
                selectedProjectionMode: decodedAirAndSpace.selectedProjectionMode,
            )
            var configuredIDs = setupState.configuredExperienceIDs
            if transitPreferences.isConfigured {
                configuredIDs.insert(.transit)
            }
            let projectionPlaylist = try playlist.value(configuredExperienceIDs: configuredIDs)
            return try ThrowPreferences(
                setupState: setupState,
                global: decodedGlobal.preferences,
                playlist: projectionPlaylist,
                airAndSpace: decodedAirAndSpace.preferences,
                transit: transitPreferences,
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
                calibration: calibration.value(),
                intensityPercent: intensityPercent,
                quietSchedule: schedule,
            )
            let sourceSelection = try AircraftSourceSelection(
                selectedSource: selectedSource?.configuration(),
                validatedSource: validatedSource?.configuration(),
            )
            let setupState = try setupState(
                sourceSelection: sourceSelection,
                locationMode: locationMode,
                confirmedLocation: confirmedLocation?.location(),
                selectedProjectionMode: selectedMode,
            )
            let airAndSpacePreferences = try AirAndSpacePreferences(
                mapViewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
                mapCenters: MapCenterPreferences(
                    profiles: (mapCenters ?? []).map { try $0.value() },
                ),
                skyViewport: SkyViewport(
                    minimumElevation: ElevationAngle(degrees: skyMinimumElevation),
                ),
                flightsEnabled: flightsEnabled,
                airlineAccentsEnabled: airlineAccentsEnabled ?? true,
                geography: geography?.value() ?? .defaultValue,
                labelMode: labelMode,
                includeGroundAircraft: includeGroundAircraft,
                markSizePercent: markSizePercent,
            )
            let entries = setupState.configuredExperienceIDs.contains(.airAndSpace)
                ? [
                    ProjectionPlaylistEntry(
                        runnableExperienceID: .airAndSpace,
                        dwellDuration: .defaultValue,
                    ),
                ]
                : []
            let playlist = try ProjectionPlaylist(
                entries: entries,
                automaticRotationEnabled: false,
                selectedExperienceID: setupState.configuredExperienceIDs.contains(.airAndSpace)
                    ? .airAndSpace
                    : nil,
                configuredExperienceIDs: setupState.configuredExperienceIDs,
                catalog: .standard,
            )
            return try ThrowPreferences(
                setupState: setupState,
                global: globalPreferences,
                playlist: playlist,
                airAndSpace: airAndSpacePreferences,
                transit: .defaultValue,
            )
        }

        private func setupState(
            sourceSelection: AircraftSourceSelection,
            locationMode: ObserverLocationMode,
            confirmedLocation: ConfirmedObserverLocation?,
            selectedProjectionMode: ProjectionMode?,
        ) throws -> ThrowSetupState {
            if setupCompleted {
                guard let source = sourceSelection.configuredSource,
                      let confirmedLocation,
                      let selectedProjectionMode
                else {
                    throw ThrowPreferenceStoreError.invalidPayload
                }
                return .configured(
                    ThrowConfiguredSetup(
                        source: source,
                        locationMode: locationMode,
                        confirmedLocation: confirmedLocation,
                        projectionMode: selectedProjectionMode,
                    ),
                )
            }
            let location: ObserverLocationSetupState = if let confirmedLocation {
                .confirmed(mode: locationMode, location: confirmedLocation)
            } else {
                .unconfirmed(mode: locationMode)
            }
            let projection = selectedProjectionMode.map(ProjectionSetupState.selected)
                ?? .unselected
            return .onboarding(
                ThrowOnboardingSetup(
                    sourceSelection: sourceSelection,
                    location: location,
                    projection: projection,
                ),
            )
        }
    }

    private struct DecodedGlobalPreferences {
        let locationMode: ObserverLocationMode
        let confirmedLocation: ConfirmedObserverLocation?
        let preferences: ThrowGlobalPreferences
    }

    private struct GlobalStorage: Codable {
        let locationMode: String
        let confirmedLocation: LocationStorage?
        let calibration: CalibrationStorage
        let intensityPercent: Double
        let quietInterval: QuietStorage?

        init(_ preferences: ThrowPreferences) {
            locationMode = preferences.locationMode.rawValue
            confirmedLocation = preferences.confirmedLocation.map(LocationStorage.init)
            calibration = CalibrationStorage(preferences.calibration)
            intensityPercent = preferences.intensityPercent
            quietInterval = preferences.quietSchedule.interval.map(QuietStorage.init)
        }

        func value() throws -> DecodedGlobalPreferences {
            guard let locationMode = ObserverLocationMode(rawValue: locationMode) else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            let schedule: QuietSchedule = if let quietInterval {
                try quietInterval.schedule()
            } else {
                .disabled
            }
            return try DecodedGlobalPreferences(
                locationMode: locationMode,
                confirmedLocation: confirmedLocation?.location(),
                preferences: ThrowGlobalPreferences(
                    calibration: calibration.value(),
                    intensityPercent: intensityPercent,
                    quietSchedule: schedule,
                ),
            )
        }
    }

    private struct DecodedAirAndSpacePreferences {
        let sourceSelection: AircraftSourceSelection
        let selectedProjectionMode: ProjectionMode?
        let preferences: AirAndSpacePreferences
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

        init(_ preferences: ThrowPreferences) {
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

        func value() throws -> DecodedAirAndSpacePreferences {
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
            let sourceSelection = try AircraftSourceSelection(
                selectedSource: selectedSource?.configuration(),
                validatedSource: validatedSource?.configuration(),
            )
            return try DecodedAirAndSpacePreferences(
                sourceSelection: sourceSelection,
                selectedProjectionMode: selectedMode,
                preferences: AirAndSpacePreferences(
                    mapViewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
                    mapCenters: MapCenterPreferences(profiles: mapCenters.map { try $0.value() }),
                    skyViewport: SkyViewport(
                        minimumElevation: ElevationAngle(degrees: skyMinimumElevation),
                    ),
                    flightsEnabled: flightsEnabled,
                    airlineAccentsEnabled: airlineAccentsEnabled ?? true,
                    geography: geography?.value() ?? .defaultValue,
                    labelMode: labelMode,
                    includeGroundAircraft: includeGroundAircraft,
                    markSizePercent: markSizePercent,
                ),
            )
        }
    }

    private struct TransitStorage: Codable {
        let configuredCityID: String?
        let mapLatitude: Double
        let mapLongitude: Double
        let mapRadius: Double
        let labelMode: String
        let geography: GeographyStorage
        let markSizePercent: Double
        let networkIntensityPercent: Double

        init(_ preferences: TransitPreferences) {
            configuredCityID = preferences.configuration.cityID?.rawValue
            mapLatitude = preferences.mapCenter.latitude
            mapLongitude = preferences.mapCenter.longitude
            mapRadius = preferences.mapViewport.radius.value
            labelMode = preferences.labelMode.rawValue
            geography = GeographyStorage(preferences.geography)
            markSizePercent = preferences.markSizePercent
            networkIntensityPercent = preferences.networkIntensityPercent
        }

        func value() throws -> TransitPreferences {
            try value(
                mapViewport: TransitMapViewport(radius: NauticalMiles(value: mapRadius)),
            )
        }

        /// Version three allowed only five-NM steps from 5 through 50 NM.
        func versionThreeValue() throws -> TransitPreferences {
            guard (5.0 ... 50.0).contains(mapRadius),
                  mapRadius.truncatingRemainder(dividingBy: 5) == 0
            else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            return try value(mapViewport: .defaultValue)
        }

        private func value(mapViewport: TransitMapViewport) throws -> TransitPreferences {
            let configuration: TransitConfiguration
            if let configuredCityID {
                guard let cityID = TransitCityID(rawValue: configuredCityID) else {
                    throw ThrowPreferenceStoreError.invalidPayload
                }
                configuration = .configured(cityID: cityID)
            } else {
                configuration = .unconfigured
            }
            guard let labelMode = TransitLabelMode(rawValue: labelMode) else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            return try TransitPreferences(
                configuration: configuration,
                mapCenter: GeoCoordinate(latitude: mapLatitude, longitude: mapLongitude),
                mapViewport: mapViewport,
                labelMode: labelMode,
                geography: geography.value(),
                markSizePercent: markSizePercent,
                networkIntensityPercent: networkIntensityPercent,
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
            configuredExperienceIDs: Set<RunnableProjectionExperienceID>,
        ) throws -> ProjectionPlaylist {
            let selectedID: RunnableProjectionExperienceID?
            if let selectedExperienceID {
                guard let decodedID = ProjectionExperienceID(rawValue: selectedExperienceID)
                else {
                    throw ThrowPreferenceStoreError.invalidPayload
                }
                guard let runnableID = ProjectionExperienceCatalog.standard
                    .runnableExperienceID(for: decodedID)
                else {
                    throw ProjectionPlaylistError.unavailableExperience
                }
                selectedID = runnableID
            } else {
                selectedID = nil
            }
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
            guard let experienceID = ProjectionExperienceID(rawValue: experienceID) else {
                throw ThrowPreferenceStoreError.invalidPayload
            }
            guard let runnableID = ProjectionExperienceCatalog.standard
                .runnableExperienceID(for: experienceID)
            else {
                throw ProjectionPlaylistError.unavailableExperience
            }
            return try ProjectionPlaylistEntry(
                runnableExperienceID: runnableID,
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
                    credentialID = AircraftCredentialID.rapidAPI.rawValue
                case let .flightradar24(configuration):
                    kind = AircraftSourceKind.flightradar24.rawValue
                    readsbURL = nil
                    cadenceSeconds = configuration.pollingInterval.seconds
                    credentialID = AircraftCredentialID.flightradar24.rawValue
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
                    guard readsbURL == nil,
                          let cadenceSeconds,
                          credentialID == AircraftCredentialID.rapidAPI.rawValue
                    else {
                        throw ThrowPreferenceStoreError.invalidPayload
                    }
                    return try .adsbExchangeRapidAPI(
                        ADSBExchangeConfiguration(
                            pollingInterval: PollingInterval(seconds: cadenceSeconds),
                        ),
                    )
                case .flightradar24:
                    guard readsbURL == nil,
                          let cadenceSeconds,
                          credentialID == AircraftCredentialID.flightradar24.rawValue
                    else {
                        throw ThrowPreferenceStoreError.invalidPayload
                    }
                    return try .flightradar24(
                        Flightradar24Configuration(
                            pollingInterval: PollingInterval(seconds: cadenceSeconds),
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
