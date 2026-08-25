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

public struct ThrowPreferences: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public static var defaultValue: ThrowPreferences {
        do {
            return try ThrowPreferences(
                setupCompleted: false,
                selectedSource: nil,
                validatedSource: nil,
                locationMode: .gps,
                confirmedLocation: nil,
                calibration: .defaultValue,
                mapViewport: .defaultValue,
                skyViewport: .defaultValue,
                selectedProjectionMode: nil,
                flightsEnabled: true,
                geography: .defaultValue,
                labelMode: .adaptive,
                includeGroundAircraft: false,
                markSizePercent: 100,
                intensityPercent: 100,
                quietSchedule: .disabled,
            )
        } catch {
            preconditionFailure("Throw's default preferences must be valid: \(error)")
        }
    }

    public let setupCompleted: Bool
    public let selectedSource: AircraftSourceConfiguration?
    public let validatedSource: AircraftSourceConfiguration?
    public let locationMode: ObserverLocationMode
    public let confirmedLocation: ConfirmedObserverLocation?
    public let calibration: ProjectionCalibration
    public let mapViewport: MapViewport
    public let skyViewport: SkyViewport
    public let selectedProjectionMode: ProjectionMode?
    public let flightsEnabled: Bool
    public let geography: GeographyPreferences
    public let labelMode: FlightLabelMode
    public let includeGroundAircraft: Bool
    public let markSizePercent: Double
    public let intensityPercent: Double
    public let quietSchedule: QuietSchedule

    public init(
        setupCompleted: Bool,
        selectedSource: AircraftSourceConfiguration?,
        validatedSource: AircraftSourceConfiguration?,
        locationMode: ObserverLocationMode,
        confirmedLocation: ConfirmedObserverLocation?,
        calibration: ProjectionCalibration,
        mapViewport: MapViewport,
        skyViewport: SkyViewport,
        selectedProjectionMode: ProjectionMode?,
        flightsEnabled: Bool,
        geography: GeographyPreferences,
        labelMode: FlightLabelMode,
        includeGroundAircraft: Bool,
        markSizePercent: Double,
        intensityPercent: Double,
        quietSchedule: QuietSchedule,
    ) throws {
        guard markSizePercent.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "markSize")
        }
        guard intensityPercent.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "intensity")
        }
        guard (50.0 ... 200.0).contains(markSizePercent) else {
            throw ThrowValidationError.outOfRange(field: "markSize", closedRange: 50 ... 200)
        }
        guard (20.0 ... 100.0).contains(intensityPercent) else {
            throw ThrowValidationError.outOfRange(field: "intensity", closedRange: 20 ... 100)
        }
        if setupCompleted {
            guard let selectedSource,
                  validatedSource == selectedSource,
                  confirmedLocation != nil,
                  selectedProjectionMode != nil
            else {
                throw ThrowValidationError.invalidPreferencePayload
            }
        }
        self.setupCompleted = setupCompleted
        self.selectedSource = selectedSource
        self.validatedSource = validatedSource
        self.locationMode = locationMode
        self.confirmedLocation = confirmedLocation
        self.calibration = calibration
        self.mapViewport = mapViewport
        self.skyViewport = skyViewport
        self.selectedProjectionMode = selectedProjectionMode
        self.flightsEnabled = flightsEnabled
        self.geography = geography
        self.labelMode = labelMode
        self.includeGroundAircraft = includeGroundAircraft
        self.markSizePercent = markSizePercent
        self.intensityPercent = intensityPercent
        self.quietSchedule = quietSchedule
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
        let selectedSource: SourceStorage?
        let validatedSource: SourceStorage?
        let locationMode: String
        let confirmedLocation: LocationStorage?
        let calibration: CalibrationStorage
        let mapRadius: Double
        let skyMinimumElevation: Double
        let selectedProjectionMode: String?
        let flightsEnabled: Bool
        let geography: GeographyStorage?
        let labelMode: String
        let includeGroundAircraft: Bool
        let markSizePercent: Double
        let intensityPercent: Double
        let quietInterval: QuietStorage?

        init(_ preferences: ThrowPreferences) {
            version = 1
            setupCompleted = preferences.setupCompleted
            selectedSource = preferences.selectedSource.map(SourceStorage.init)
            validatedSource = preferences.validatedSource.map(SourceStorage.init)
            locationMode = preferences.locationMode.rawValue
            confirmedLocation = preferences.confirmedLocation.map(LocationStorage.init)
            calibration = CalibrationStorage(preferences.calibration)
            mapRadius = preferences.mapViewport.radius.value
            skyMinimumElevation = preferences.skyViewport.minimumElevation.degrees
            selectedProjectionMode = preferences.selectedProjectionMode?.rawValue
            flightsEnabled = preferences.flightsEnabled
            geography = GeographyStorage(preferences.geography)
            labelMode = preferences.labelMode.rawValue
            includeGroundAircraft = preferences.includeGroundAircraft
            markSizePercent = preferences.markSizePercent
            intensityPercent = preferences.intensityPercent
            quietInterval = preferences.quietSchedule.interval.map(QuietStorage.init)
        }

        func preferences() throws -> ThrowPreferences {
            guard version == 1,
                  let locationMode = ObserverLocationMode(rawValue: locationMode),
                  let labelMode = FlightLabelMode(rawValue: labelMode)
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
            return try ThrowPreferences(
                setupCompleted: setupCompleted,
                selectedSource: selectedSource?.configuration(),
                validatedSource: validatedSource?.configuration(),
                locationMode: locationMode,
                confirmedLocation: confirmedLocation?.location(),
                calibration: calibration.value(),
                mapViewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
                skyViewport: SkyViewport(
                    minimumElevation: ElevationAngle(degrees: skyMinimumElevation),
                ),
                selectedProjectionMode: selectedMode,
                flightsEnabled: flightsEnabled,
                geography: geography?.value() ?? .defaultValue,
                labelMode: labelMode,
                includeGroundAircraft: includeGroundAircraft,
                markSizePercent: markSizePercent,
                intensityPercent: intensityPercent,
                quietSchedule: schedule,
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
