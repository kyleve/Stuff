import CreditKit
import Foundation
import ThrowCore

extension ThrowSession {
    /// Builds the live session once at the app composition root.
    public static func live() -> ThrowSession {
        let dateProvider = SystemDateProvider()
        let cloudTransport = URLSessionHTTPTransport.makeCloud()
        let localTransport = URLSessionHTTPTransport.makeLocal()
        let credentialStore = KeychainAircraftCredentialStore(
            service: "com.stuff.throw",
            accountPrefix: "aircraft-source",
        )
        let sourceFactory = AircraftSourceFactory(
            cloudTransport: cloudTransport,
            localTransport: localTransport,
            credentialStore: credentialStore,
            dateProvider: dateProvider,
        )
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: sourceFactory,
            clock: SystemAircraftPollingClock(),
            logger: PeriscopeAircraftPollingLogger(log: ThrowLog.aircraft),
        )
        let sourceService = AircraftSourceService(
            sourceFactory: sourceFactory,
            cloudTransport: cloudTransport,
            credentialStore: credentialStore,
            dateProvider: dateProvider,
        )
        let credits: [SoftwareCredit]
        let creditFailure: String?
        do {
            credits = try AttributionManifest.load(
                from: .main,
                resource: "attribution",
            ).credits
            creditFailure = nil
        } catch {
            credits = []
            creditFailure = String(localized: .aboutCreditsUnavailable)
        }
        let session = ThrowSession(
            preferences: .defaultValue,
            preferenceStore: UserDefaultsThrowPreferenceStore(userDefaults: .standard),
            credentialStore: credentialStore,
            sourceService: sourceService,
            pollingCoordinator: coordinator,
            dateProvider: dateProvider,
            locationSource: CoreLocationThrowSource(),
            calendar: .autoupdatingCurrent,
            layerCatalog: .standard,
            geographyLogger: PeriscopeGeographyLogger(log: ThrowLog.geography),
            motionLogger: PeriscopeProjectionMotionLogger(log: ThrowLog.projectionMotion),
            routeResolver: FlightRouteResolver(
                source: ADSBDBFlightRouteSource(transport: cloudTransport),
            ),
            routeLogger: PeriscopeFlightRouteLogger(log: ThrowLog.flightRoutes),
            rotationClock: SystemProjectionRotationClock(),
            softwareCredits: credits,
            initiallyHasForegroundControllerScene: false,
            initialLaunchState: .loading,
        )
        session.settingsFailure = creditFailure
        return session
    }
}

#if DEBUG
    enum ExperienceDashboardSnapshotState {
        case rotating
        case paused
        case prewarming
        case failedSelection
    }

    extension ThrowSession {
        @_spi(Testing) public static func fixture() -> ThrowSession {
            makeFixture(
                setupCompleted: true,
                quiet: false,
                transport: FixtureHTTPTransport(),
            )
        }

        @_spi(Testing) public static func fixture(
            cloudTransport: any HTTPTransport,
        ) -> ThrowSession {
            makeFixture(
                setupCompleted: true,
                quiet: false,
                transport: cloudTransport,
            )
        }

        @_spi(Testing) public static func fixture(
            locationSource: any ThrowLocationSource,
        ) -> ThrowSession {
            makeFixture(
                setupCompleted: true,
                quiet: false,
                transport: FixtureHTTPTransport(),
                locationSource: locationSource,
            )
        }

        @_spi(Testing) public static func fixture(
            preferenceStore: any ThrowPreferenceStore,
            credentialStore: any AircraftCredentialStore,
        ) -> ThrowSession {
            makeFixture(
                setupCompleted: true,
                quiet: false,
                transport: FixtureHTTPTransport(),
                preferenceStoreOverride: preferenceStore,
                credentialStoreOverride: credentialStore,
            )
        }

        @_spi(Testing) public static func launchFixture(
            setupCompleted: Bool,
            preferenceStore: any ThrowPreferenceStore,
            credentialStore: any AircraftCredentialStore,
        ) -> ThrowSession {
            makeFixture(
                setupCompleted: setupCompleted,
                quiet: false,
                transport: FixtureHTTPTransport(),
                preferenceStoreOverride: preferenceStore,
                credentialStoreOverride: credentialStore,
                initialLaunchStateOverride: .loading,
            )
        }

        static func onboardingFixture() -> ThrowSession {
            makeFixture(
                setupCompleted: false,
                quiet: false,
                transport: FixtureHTTPTransport(),
            )
        }

        static func loadingRootSnapshotFixture() -> ThrowSession {
            let session = onboardingFixture()
            session.launchState = .loading
            return session
        }

        static func failedRootSnapshotFixture() -> ThrowSession {
            let session = onboardingFixture()
            session.launchState = .failed(.preferences(
                detail: ThrowPreferenceStoreError.invalidPayload.localizedDescription,
            ))
            return session
        }

        static func quietFixture() -> ThrowSession {
            makeFixture(
                setupCompleted: true,
                quiet: true,
                transport: FixtureHTTPTransport(),
            )
        }

        static func trueSkySnapshotFixture() -> ThrowSession {
            let session = fixture()
            session.isApplyingPreferences = true
            session.projectionMode = .trueSky
            session.minimumElevation = 10
            session.isApplyingPreferences = false
            session.projectionFrame = fixtureTrueSkyProjectionFrame(
                at: session.projectionFrame.generatedAt,
            )
            session.feedHealth = .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: session.projectionFrame.visibleAircraftCount,
            )
            return session
        }

        static func retryingSnapshotFixture() -> ThrowSession {
            let session = fixture()
            let now = session.dateProvider.now()
            session.projectionFrame = fixtureProjectionFrame(
                at: session.projectionFrame.generatedAt,
                opacity: 0.55,
            )
            session.feedHealth = .retrying(
                lastUpdate: now,
                nextRetry: now.addingTimeInterval(3600),
                failure: .transport,
                visibleContentCount: session.projectionFrame.visibleAircraftCount,
            )
            return session
        }

        static func failedSnapshotFixture() -> ThrowSession {
            let session = fixture()
            session.projectionFrame = emptyProjectionFrame(
                mode: session.projectionMode,
                at: session.projectionFrame.generatedAt,
            )
            session.feedHealth = .failed(.missingCredential)
            return session
        }

        static func marksOnlySnapshotFixture() -> ThrowSession {
            let session = fixture()
            session.isApplyingPreferences = true
            session.labelMode = .marksOnly
            session.isApplyingPreferences = false
            session.projectionFrame = mapLabels(in: session.projectionFrame) { _ in nil }
            return session
        }

        static func callsignsSnapshotFixture() -> ThrowSession {
            let session = fixture()
            session.isApplyingPreferences = true
            session.labelMode = .callsigns
            session.isApplyingPreferences = false
            return session
        }

        static func denseAdaptiveSnapshotFixture() -> ThrowSession {
            let session = fixture()
            let values = (0 ..< 28).map { index in
                let column = index % 7
                let row = index / 7
                return SnapshotAircraft(
                    rawID: "dense-\(index)",
                    x: 0.20 + Double(column) * 0.095,
                    y: 0.32 + Double(row) * 0.12,
                    callsign: index.isMultiple(of: 3) ? "FLT\(100 + index)" : nil,
                    altitude: index.isMultiple(of: 9) ? "12,000 ft" : nil,
                    orientation: Double((index * 37) % 360),
                    range: Double(index + 3),
                )
            }
            session.projectionFrame = fixtureProjectionFrame(
                mode: .map,
                at: session.projectionFrame.generatedAt,
                aircraft: values,
                opacity: 1,
            )
            session.feedHealth = .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: session.projectionFrame.visibleAircraftCount,
            )
            return session
        }

        static func activitySnapshotFixture(mode: ProjectionMode) -> ThrowSession {
            let session = fixture()
            let airport = try! AirportRecord(
                id: AirportID(rawValue: 99),
                coordinate: GeoCoordinate(latitude: 37.62, longitude: -122.38),
                elevation: Altitude(feet: 13),
                codes: [AirportCode(rawValue: "SFO")!],
                runways: [RunwayRecord(
                    id: 990,
                    lengthFeet: 11870,
                    lowEnd: GeoCoordinate(latitude: 37.61, longitude: -122.40),
                    highEnd: GeoCoordinate(latitude: 37.63, longitude: -122.36),
                )],
            )
            let activities: [FlightActivity] = [
                .arrival(
                    AirportActivityContext(
                        airport: airport,
                        aircraftDistance: try! NauticalMiles(value: 18),
                    ),
                    .inbound,
                    .confirmed,
                ),
                .arrival(
                    AirportActivityContext(
                        airport: airport,
                        aircraftDistance: try! NauticalMiles(value: 6),
                    ),
                    .approach,
                    .confirmed,
                ),
                .departure(
                    AirportActivityContext(
                        airport: airport,
                        aircraftDistance: try! NauticalMiles(value: 14),
                    ),
                    .outbound,
                    .inferred,
                ),
                .departure(
                    AirportActivityContext(
                        airport: airport,
                        aircraftDistance: try! NauticalMiles(value: 4),
                    ),
                    .initialClimb,
                    .confirmed,
                ),
            ]
            let points = [(0.30, 0.38), (0.45, 0.58), (0.67, 0.36), (0.62, 0.68)]
            let aircraft = activities.enumerated().map { index, activity in
                ProjectedMark(
                    id: fixtureAircraftMarkID(rawValue: "activity-\(index)"),
                    point: ProjectionPoint(x: points[index].0, y: points[index].1),
                    range: try! NauticalMiles(value: Double(5 + index * 8)),
                    glyph: .aircraft(AircraftGlyphDescriptor(
                        family: index.isMultiple(of: 2) ? .airliner : .regionalBusinessJet,
                        brand: index.isMultiple(of: 2) ? .united : .southwest,
                        isGrounded: false,
                        activity: activity,
                    )),
                    label: ProjectionLabel(
                        primary: index < 2 ? "LAX→SFO" : "SFO→SAN",
                        primaryRole: .headline,
                        secondary: "FLT\(210 + index)",
                    ),
                    secondaryProminence: 0,
                    orientationDegrees: [45, 135, 250, 325][index],
                    opacity: 1,
                    labelOpacity: 1,
                    altitudeIsApproximate: false,
                )
            }
            let airportMark = ProjectedMark(
                id: airport.id.layerMarkID,
                point: ProjectionPoint(x: 0.5, y: 0.5),
                range: try! NauticalMiles(value: 12),
                glyph: .airport(AirportGlyphDescriptor(
                    airportID: airport.id,
                    code: airport.displayCode,
                    runwayBearing: try! Bearing(degrees: 100),
                    certainty: .confirmed,
                )),
                label: ProjectionLabel(
                    primary: "SFO",
                    primaryRole: .headline,
                    secondary: nil,
                ),
                secondaryProminence: 0,
                orientationDegrees: 100,
                opacity: 1,
                labelOpacity: 1,
                altitudeIsApproximate: false,
            )
            session.projectionFrame = ProjectionFrame(
                mode: mode,
                generatedAt: session.dateProvider.now(),
                geography: mode == .map
                    ? ProjectedGeography(
                        id: GeographyProjectionID(rawValue: 1),
                        segments: fixtureGeographySegments(),
                    )
                    : nil,
                geographyOpacity: 1,
                marks: aircraft + (mode == .map ? [airportMark] : []),
            )
            return session
        }

        static func calibrationSnapshotFixture() -> ThrowSession {
            let session = fixture()
            session.previewCalibration(
                screenTopBearing: 287,
                rotation: .degrees90,
                flipsHorizontally: true,
                flipsVertically: false,
                safeInsetPercent: 12,
                calibrationVerified: false,
            )
            session.projectionOutputConnected(
                .calibration(ProjectionOutputID(rawValue: "snapshot-calibration")),
            )
            return session
        }

        static func flightradar24SourceSettingsSnapshotFixture() -> ThrowSession {
            let credential: AircraftCredential
            do {
                credential = try AircraftCredential(secret: "fixture-fr24-token")
            } catch {
                preconditionFailure("Snapshot credential must be valid: \(error)")
            }
            let pollingInterval: PollingInterval
            do {
                pollingInterval = try PollingInterval(seconds: 300)
            } catch {
                preconditionFailure("Snapshot polling interval must be valid: \(error)")
            }
            let session = makeFixture(
                setupCompleted: true,
                quiet: false,
                transport: FixtureHTTPTransport(),
                credentials: [.flightradar24: credential],
            )
            let configuration = AircraftSourceConfiguration.flightradar24(
                Flightradar24Configuration(
                    pollingInterval: pollingInterval,
                ),
            )
            session.setupState = session.setupState.replacingSource(configuration)
            session.flightradar24CredentialState = .saved(lastFour: credential.lastFour)
            return session
        }

        static func healthyDashboardSnapshotFixture() -> ThrowSession {
            let session = fixture()
            prepareDashboardSnapshot(session)
            session.feedHealth = .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: session.projectionFrame.visibleAircraftCount,
            )
            return session
        }

        static func rootDashboardSnapshotFixture() -> ThrowSession {
            let session = fixture()
            session.locationHealth = .missing
            session.projectionFrame = emptyProjectionFrame(
                mode: session.projectionMode,
                at: session.projectionFrame.generatedAt,
            )
            session.feedHealth = .loading
            return session
        }

        static func retryingDashboardSnapshotFixture() -> ThrowSession {
            let session = retryingSnapshotFixture()
            prepareDashboardSnapshot(session)
            return session
        }

        static func quietDashboardSnapshotFixture() -> ThrowSession {
            let session = quietFixture()
            prepareDashboardSnapshot(session)
            return session
        }

        static func adsbExchangeMissingCredentialSnapshotFixture() -> ThrowSession {
            let session = adsbExchangeSnapshotFixture(intervalSeconds: 300)
            session.rapidAPICredentialState = .missing
            session.feedHealth = .failed(.missingCredential)
            return session
        }

        static func adsbExchangeQuotaSnapshotFixture() -> ThrowSession {
            let session = adsbExchangeSnapshotFixture(intervalSeconds: 10)
            session.rapidAPICredentialState = .saved(lastFour: "4242")
            session.feedHealth = .failed(.quota)
            return session
        }

        static func adsbExchangeFastCadenceSnapshotFixture() -> ThrowSession {
            let session = adsbExchangeSnapshotFixture(intervalSeconds: 5)
            session.rapidAPICredentialState = .saved(lastFour: "4242")
            session.feedHealth = .healthy(
                lastUpdate: session.dateProvider.now(),
                visibleContentCount: 0,
            )
            return session
        }

        static func experienceDashboardSnapshotFixture(
            _ state: ExperienceDashboardSnapshotState,
        ) -> ThrowSession {
            let session = healthyDashboardSnapshotFixture()
            do {
                let dwell = try ProjectionDwellDuration(seconds: 120)
                session.projectionPlaylist = try ProjectionPlaylist(
                    entries: [
                        ProjectionPlaylistEntry(
                            experienceID: .airAndSpace,
                            dwellDuration: dwell,
                        ),
                        ProjectionPlaylistEntry(
                            experienceID: .transit,
                            dwellDuration: dwell,
                        ),
                    ],
                    automaticRotationEnabled: true,
                    selectedExperienceID: .airAndSpace,
                    configuredExperienceIDs: [.airAndSpace, .transit],
                    catalog: enabledExperienceSnapshotCatalog,
                )
            } catch {
                preconditionFailure("Snapshot View playlist must be valid: \(error)")
            }

            let now = session.dateProvider.now()
            var requestedExperienceID: ProjectionExperienceID?
            var prewarmingExperienceID: ProjectionExperienceID?
            var isPaused = false
            var dwellEndsAt: Date? = now.addingTimeInterval(75)
            var healthByExperience: [ProjectionExperienceID: FeedHealth] = [
                .airAndSpace: session.feedHealth,
                .transit: .idle,
            ]
            var manualSelectionFailure: ThrowFailureCategory?

            switch state {
                case .rotating:
                    break
                case .paused:
                    isPaused = true
                    dwellEndsAt = nil
                case .prewarming:
                    requestedExperienceID = .transit
                    prewarmingExperienceID = .transit
                    dwellEndsAt = now.addingTimeInterval(15)
                    healthByExperience[.transit] = .loading
                case .failedSelection:
                    manualSelectionFailure = .transport
                    healthByExperience[.transit] = .failed(.transport)
            }
            session.experienceCoordinatorState = ProjectionExperienceCoordinatorState(
                activeExperienceID: .airAndSpace,
                requestedExperienceID: requestedExperienceID,
                prewarmingExperienceID: prewarmingExperienceID,
                isPaused: isPaused,
                dwellEndsAt: dwellEndsAt,
                nextExperienceID: .transit,
                healthByExperience: healthByExperience,
                manualSelectionFailure: manualSelectionFailure,
            )
            return session
        }

        private static func makeFixture(
            setupCompleted: Bool,
            quiet: Bool,
            transport: any HTTPTransport,
            locationSource: (any ThrowLocationSource)? = nil,
            credentials: [AircraftCredentialID: AircraftCredential] = [:],
            preferenceStoreOverride: (any ThrowPreferenceStore)? = nil,
            credentialStoreOverride: (any AircraftCredentialStore)? = nil,
            initialLaunchStateOverride: ThrowSessionLaunchState? = nil,
        ) -> ThrowSession {
            do {
                let now = Date(timeIntervalSince1970: 1_787_594_400)
                let position = try ObserverPosition(
                    coordinate: GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
                    altitude: Altitude(feet: 52),
                )
                let confirmed = try ConfirmedObserverLocation(
                    position: position,
                    horizontalAccuracyMeters: 18,
                    confirmedAt: now,
                )
                let source: AircraftSourceConfiguration = .adsbLol
                let setupState: ThrowSetupState = if setupCompleted {
                    .configured(
                        ThrowConfiguredSetup(
                            source: source,
                            locationMode: .gps,
                            confirmedLocation: confirmed,
                            projectionMode: .map,
                        ),
                    )
                } else {
                    .onboarding(
                        ThrowOnboardingSetup(
                            sourceSelection: .unconfigured,
                            location: .confirmed(mode: .gps, location: confirmed),
                            projection: .unselected,
                        ),
                    )
                }
                let global = try ThrowGlobalPreferences(
                    calibration: .defaultValue,
                    intensityPercent: 80,
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
                    entries: setupCompleted
                        ? [
                            ProjectionPlaylistEntry(
                                experienceID: .airAndSpace,
                                dwellDuration: .defaultValue,
                            ),
                        ]
                        : [],
                    automaticRotationEnabled: false,
                    selectedExperienceID: setupCompleted ? .airAndSpace : nil,
                    configuredExperienceIDs: setupState.configuredExperienceIDs,
                    catalog: .standard,
                )
                let preferences = try ThrowPreferences(
                    setupState: setupState,
                    global: global,
                    playlist: playlist,
                    airAndSpace: airAndSpace,
                )
                let preferenceStore: any ThrowPreferenceStore = if let preferenceStoreOverride {
                    preferenceStoreOverride
                } else {
                    try MemoryThrowPreferenceStore(initialValue: preferences)
                }
                let credentialStore: any AircraftCredentialStore = if let credentialStoreOverride {
                    credentialStoreOverride
                } else {
                    MemoryAircraftCredentialStore(credentials: credentials)
                }
                let dateProvider = FixtureDateProvider(date: now)
                let sourceFactory = AircraftSourceFactory(
                    cloudTransport: transport,
                    localTransport: transport,
                    credentialStore: credentialStore,
                    dateProvider: dateProvider,
                )
                let coordinator = AircraftPollingCoordinator(
                    sourceFactory: sourceFactory,
                    clock: SystemAircraftPollingClock(),
                    logger: DiscardingAircraftPollingLogger(),
                )
                let sourceService = AircraftSourceService(
                    sourceFactory: sourceFactory,
                    cloudTransport: transport,
                    credentialStore: credentialStore,
                    dateProvider: dateProvider,
                )
                let fix = try LocationFix(
                    position: position,
                    horizontalAccuracyMeters: 18,
                    observedAt: now,
                )
                let resolvedLocationSource: any ThrowLocationSource = if let locationSource {
                    locationSource
                } else {
                    FixtureLocationSource(fix: fix)
                }
                let session = ThrowSession(
                    preferences: preferences,
                    preferenceStore: preferenceStore,
                    credentialStore: credentialStore,
                    sourceService: sourceService,
                    pollingCoordinator: coordinator,
                    dateProvider: dateProvider,
                    locationSource: resolvedLocationSource,
                    calendar: Calendar(identifier: .gregorian),
                    layerCatalog: .standard,
                    geographyLogger: DiscardingGeographyLogger(),
                    motionLogger: DiscardingProjectionMotionLogger(),
                    routeResolver: FlightRouteResolver(
                        source: EmptyFlightRouteSource(),
                    ),
                    routeLogger: DiscardingFlightRouteLogger(),
                    rotationClock: SystemProjectionRotationClock(),
                    softwareCredits: [],
                    initiallyHasForegroundControllerScene: true,
                    initialLaunchState: initialLaunchStateOverride ?? .loaded(setupState),
                )
                session.projectionFrame = quiet
                    ? emptyProjectionFrame(mode: .map, at: now)
                    : fixtureProjectionFrame(at: now, opacity: 1)
                session.feedHealth = quiet
                    ? .quiet
                    : .healthy(
                        lastUpdate: now,
                        visibleContentCount: session.projectionFrame.visibleAircraftCount,
                    )
                return session
            } catch {
                preconditionFailure("Throw fixture must be valid: \(error)")
            }
        }

        private struct EmptyFlightRouteSource: FlightRouteSource {
            func routes(
                for _: [FlightRouteQuery],
            ) async throws -> [FlightCallsign: FlightRoute] {
                [:]
            }
        }

        private static func adsbExchangeSnapshotFixture(intervalSeconds: Int) -> ThrowSession {
            let session = fixture()
            let pollingInterval: PollingInterval
            do {
                pollingInterval = try PollingInterval(seconds: intervalSeconds)
            } catch {
                preconditionFailure("Snapshot polling interval must be valid: \(error)")
            }
            let configuration = AircraftSourceConfiguration.adsbExchangeRapidAPI(
                ADSBExchangeConfiguration(
                    pollingInterval: pollingInterval,
                ),
            )
            prepareDashboardSnapshot(session)
            session.setupState = session.setupState.replacingSource(configuration)
            session.projectionFrame = emptyProjectionFrame(
                mode: session.projectionMode,
                at: session.projectionFrame.generatedAt,
            )
            return session
        }

        private static func prepareDashboardSnapshot(_ session: ThrowSession) {
            session.locationHealth = .confirmed(
                accuracyMeters: 18,
                acceptedAt: session.dateProvider.now(),
            )
        }

        private static var enabledExperienceSnapshotCatalog: ProjectionExperienceCatalog {
            let descriptors = ProjectionExperienceCatalog.standard.descriptors.map { descriptor in
                guard descriptor.id == .transit else { return descriptor }
                return ProjectionExperienceDescriptor(
                    id: descriptor.id,
                    availability: .enabled,
                    supportedModes: descriptor.supportedModes,
                    layerIDs: descriptor.layerIDs,
                    visibleContentKind: descriptor.visibleContentKind,
                    zOrder: descriptor.zOrder,
                )
            }
            return ProjectionExperienceCatalog(
                descriptors: descriptors,
                layerCatalog: .standard,
            )
        }

        private static func emptyProjectionFrame(
            mode: ProjectionMode,
            at date: Date,
        ) -> ProjectionFrame {
            ProjectionFrame(
                mode: mode,
                generatedAt: date,
                geography: nil,
                geographyOpacity: 1,
                marks: [],
            )
        }

        private static func fixtureProjectionFrame(
            at date: Date,
            opacity: Double,
        ) -> ProjectionFrame {
            let values = [
                SnapshotAircraft(
                    rawID: "fixture-one",
                    x: 0.46,
                    y: 0.32,
                    callsign: "UAL123",
                    altitude: nil,
                    orientation: 35,
                    range: 9.22,
                    family: .airliner,
                    brand: .united,
                ),
                SnapshotAircraft(
                    rawID: "fixture-two",
                    x: 0.68,
                    y: 0.54,
                    callsign: "SWA42",
                    altitude: nil,
                    orientation: 35,
                    range: 9.22,
                    family: .airliner,
                    brand: .southwest,
                ),
                SnapshotAircraft(
                    rawID: "fixture-three",
                    x: 0.31,
                    y: 0.70,
                    callsign: "ASA8",
                    altitude: nil,
                    orientation: 35,
                    range: 13.79,
                    family: .regionalBusinessJet,
                    brand: .alaska,
                ),
            ]
            return fixtureProjectionFrame(
                mode: .map,
                at: date,
                aircraft: values,
                opacity: opacity,
            )
        }

        private static func fixtureTrueSkyProjectionFrame(at date: Date) -> ProjectionFrame {
            let values = [
                SnapshotAircraft(
                    rawID: "fixture-overhead",
                    x: 0.50,
                    y: 0.50,
                    callsign: "SKY1",
                    altitude: "8,000 ft",
                    orientation: nil,
                    range: 8,
                    family: .helicopter,
                    brand: nil,
                ),
                SnapshotAircraft(
                    rawID: "fixture-northeast",
                    x: 0.69,
                    y: 0.29,
                    callsign: "DAL308",
                    altitude: nil,
                    orientation: 130,
                    range: 34,
                    family: .airliner,
                    brand: .delta,
                ),
                SnapshotAircraft(
                    rawID: "fixture-south",
                    x: 0.47,
                    y: 0.82,
                    callsign: "NKS72",
                    altitude: "21,400 ft",
                    orientation: 8,
                    range: 76,
                    family: .regionalBusinessJet,
                    brand: .spirit,
                ),
                SnapshotAircraft(
                    rawID: "fixture-west",
                    x: 0.18,
                    y: 0.52,
                    callsign: "JBU6",
                    altitude: nil,
                    orientation: 272,
                    range: 101,
                    family: .heavyJet,
                    brand: .jetBlue,
                ),
            ]
            return fixtureProjectionFrame(
                mode: .trueSky,
                at: date,
                aircraft: values,
                opacity: 1,
            )
        }

        private static func fixtureProjectionFrame(
            mode: ProjectionMode,
            at date: Date,
            aircraft: [SnapshotAircraft],
            opacity: Double,
        ) -> ProjectionFrame {
            ProjectionFrame(
                mode: mode,
                generatedAt: date,
                geography: mode == .map
                    ? ProjectedGeography(
                        id: GeographyProjectionID(rawValue: 1),
                        segments: fixtureGeographySegments(),
                    )
                    : nil,
                geographyOpacity: 1,
                marks: aircraft.map { value in
                    ProjectedMark(
                        id: fixtureAircraftMarkID(rawValue: value.rawID),
                        point: ProjectionPoint(x: value.x, y: value.y),
                        range: fixtureRange(value.range),
                        glyph: .aircraft(AircraftGlyphDescriptor(
                            family: value.family,
                            brand: value.brand,
                            isGrounded: false,
                            activity: .overflight,
                        )),
                        label: fixtureLabel(for: value),
                        secondaryProminence: fixtureRoute(for: value) == nil ? 1 : 0,
                        orientationDegrees: value.orientation,
                        opacity: opacity,
                        labelOpacity: 1,
                        altitudeIsApproximate: value.altitude != nil,
                    )
                },
            )
        }

        private static func fixtureLabel(for aircraft: SnapshotAircraft) -> ProjectionLabel? {
            guard let callsign = aircraft.callsign else { return nil }
            if let route = fixtureRoute(for: aircraft) {
                return ProjectionLabel(
                    primary: route,
                    primaryRole: .headline,
                    secondary: callsign,
                )
            }
            return ProjectionLabel(
                primary: callsign,
                primaryRole: .detail,
                secondary: nil,
            )
        }

        private static func fixtureRoute(for aircraft: SnapshotAircraft) -> String? {
            switch aircraft.callsign {
                case "UAL123": "JFK→SFO"
                case "SWA42": "OAK→SAN"
                case "ASA8": "SEA→SJC"
                case "DAL308": "LAX→JFK"
                case "NKS72": "LAS→BUR"
                case "JBU6": "BOS→LAX"
                default: nil
            }
        }

        private static func mapLabels(
            in frame: ProjectionFrame,
            transform: (ProjectionLabel?) -> ProjectionLabel?,
        ) -> ProjectionFrame {
            ProjectionFrame(
                mode: frame.mode,
                generatedAt: frame.generatedAt,
                geography: frame.geography,
                geographyOpacity: frame.geographyOpacity,
                marks: frame.marks.map { mark in
                    ProjectedMark(
                        id: mark.id,
                        point: mark.point,
                        range: mark.range,
                        glyph: mark.glyph,
                        label: transform(mark.label),
                        secondaryProminence: mark.secondaryProminence,
                        orientationDegrees: mark.orientationDegrees,
                        opacity: mark.opacity,
                        labelOpacity: mark.labelOpacity,
                        altitudeIsApproximate: mark.altitudeIsApproximate,
                    )
                },
            )
        }

        private static func fixtureGeographySegments() -> [ProjectedGeographySegment] {
            func segment(
                _ kind: GeographyLineKind,
                _ startX: Double,
                _ startY: Double,
                _ endX: Double,
                _ endY: Double,
                _ startsNewSubpath: Bool,
            ) -> ProjectedGeographySegment {
                ProjectedGeographySegment(
                    kind: kind,
                    start: ProjectionPoint(x: startX, y: startY),
                    end: ProjectionPoint(x: endX, y: endY),
                    startsNewSubpath: startsNewSubpath,
                )
            }
            return [
                segment(.coastline, 0.18, 0.22, 0.34, 0.42, true),
                segment(.coastline, 0.34, 0.42, 0.29, 0.76, false),
                segment(.lake, 0.58, 0.27, 0.63, 0.38, true),
                segment(.river, 0.72, 0.18, 0.61, 0.66, true),
                segment(.nationalBoundary, 0.23, 0.62, 0.77, 0.71, true),
                segment(.disputedBoundary, 0.22, 0.52, 0.43, 0.58, true),
                segment(.regionalBoundary, 0.42, 0.14, 0.50, 0.85, true),
                segment(.countyBoundary, 0.54, 0.20, 0.56, 0.80, true),
                segment(.primaryRoad, 0.20, 0.78, 0.78, 0.30, true),
            ]
        }

        private static func fixtureRange(_ value: Double) -> NauticalMiles {
            do {
                return try NauticalMiles(value: value)
            } catch {
                preconditionFailure("Snapshot range must be valid: \(error)")
            }
        }

        private static func fixtureAircraftMarkID(rawValue: String) -> LayerMarkID {
            guard let id = AircraftID(kind: .icao, rawValue: rawValue) else {
                preconditionFailure("A fixture aircraft ID must be valid")
            }
            return id.layerMarkID
        }

        private struct SnapshotAircraft {
            let rawID: String
            let x: Double
            let y: Double
            let callsign: String?
            let altitude: String?
            let orientation: Double?
            let range: Double
            var family: AircraftVisualFamily = .unknown
            var brand: AirlineBrand?
        }
    }
#endif
