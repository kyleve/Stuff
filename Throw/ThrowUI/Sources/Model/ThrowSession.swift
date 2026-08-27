import CreditKit
import Observation
import SwiftUI
import ThrowCore

/// Controller-visible availability of Throw's bundled Geography layer.
public enum GeographyLayerHealth: Equatable, Sendable {
    case idle
    case available
    case unavailable
}

/// The single main-actor presentation session shared by every Throw scene.
@MainActor
@Observable
public final class ThrowSession {
    public internal(set) var setupCompleted: Bool
    /// Compatibility access for Air & Space callers while health remains keyed by experience.
    public internal(set) var feedHealth: FeedHealth {
        get { experienceHealth[.airAndSpace] ?? .idle }
        set { experienceHealth[.airAndSpace] = newValue }
    }

    public internal(set) var projectionPlaylist: ProjectionPlaylist
    public internal(set) var activeExperienceID: ProjectionExperienceID?
    public internal(set) var requestedExperienceID: ProjectionExperienceID?
    public internal(set) var nextExperienceID: ProjectionExperienceID?
    public internal(set) var prewarmingExperienceID: ProjectionExperienceID?
    public internal(set) var experienceDwellEndsAt: Date?
    public internal(set) var isExperienceRotationPaused = false
    public internal(set) var experienceHealth: [ProjectionExperienceID: FeedHealth] = [:]
    public internal(set) var experienceSelectionFailure: ThrowFailureCategory?
    public internal(set) var locationHealth: LocationHealth = .missing
    public internal(set) var projectionFrame: ProjectionFrame
    public internal(set) var observerMapPoint: ProjectionPoint?
    var projectionMarkEffects: [LayerMarkID: ProjectionMarkEffect] = [:]
    public internal(set) var projectionMarkOpacity = 1.0
    public internal(set) var projectionSurfaceOpacity = 1.0
    public internal(set) var geographyLayerHealth: GeographyLayerHealth = .idle
    public internal(set) var projectionOutputCount = 0
    public internal(set) var rapidAPICredentialState: CredentialState = .missing
    public internal(set) var flightradar24CredentialState: CredentialState = .missing
    public internal(set) var softwareCredits: [SoftwareCredit]
    public internal(set) var settingsFailure: String?

    public var projectionMode: ProjectionMode {
        didSet {
            guard oldValue != projectionMode, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: true)
        }
    }

    public var mapRadius: Double {
        didSet {
            guard oldValue != mapRadius, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: true)
        }
    }

    public internal(set) var mapCenters: MapCenterPreferences

    public var minimumElevation: Double {
        didSet {
            guard oldValue != minimumElevation, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: true)
        }
    }

    public var flightsEnabled: Bool {
        didSet {
            guard oldValue != flightsEnabled, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: true)
        }
    }

    public var airlineAccentsEnabled: Bool {
        didSet {
            guard oldValue != airlineAccentsEnabled, isApplyingPreferences == false else { return }
            settingsChanged(reconcilesDemand: false)
        }
    }

    public var geographyEnabled: Bool {
        didSet {
            guard oldValue != geographyEnabled, isApplyingPreferences == false else { return }
            if geographyEnabled == false {
                geographyLayerHealth = .idle
                projectionFrame = ProjectionFrame(
                    mode: projectionFrame.mode,
                    generatedAt: projectionFrame.generatedAt,
                    geography: nil,
                    geographyOpacity: 1,
                    marks: projectionFrame.marks,
                )
            }
            settingsChanged(reconcilesDemand: false)
            if flightsEnabled {
                restartRenderer()
            } else {
                scheduleDemandReconciliation()
            }
        }
    }

    public var labelMode: FlightLabelMode {
        didSet {
            guard oldValue != labelMode, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: false)
        }
    }

    public var includeGroundAircraft: Bool {
        didSet {
            guard oldValue != includeGroundAircraft, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: true)
        }
    }

    public var markSizePercent: Double {
        didSet {
            guard oldValue != markSizePercent, isApplyingPreferences == false else { return }
            settingsChanged(reconcilesDemand: false)
        }
    }

    public var intensityPercent: Double {
        didSet {
            guard oldValue != intensityPercent, isApplyingPreferences == false else { return }
            settingsChanged(reconcilesDemand: false)
        }
    }

    public var geographyIntensityPercent: Double {
        didSet {
            guard oldValue != geographyIntensityPercent,
                  isApplyingPreferences == false
            else { return }
            settingsChanged(reconcilesDemand: false)
        }
    }

    public var screenTopBearing: Double {
        didSet {
            guard oldValue != screenTopBearing, isApplyingPreferences == false else { return }
            mayApplyTrueHeadingHint = false
            projectionInputsChanged(restartsPolling: false)
        }
    }

    public var screenRotation: ScreenRotation {
        didSet {
            guard oldValue != screenRotation, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: false)
        }
    }

    public var flipHorizontal: Bool {
        didSet {
            guard oldValue != flipHorizontal, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: false)
        }
    }

    public var flipVertical: Bool {
        didSet {
            guard oldValue != flipVertical, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: false)
        }
    }

    public var safeInsetPercent: Double {
        didSet {
            guard oldValue != safeInsetPercent, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: false)
        }
    }

    public var calibrationVerified: Bool {
        didSet {
            guard oldValue != calibrationVerified, isApplyingPreferences == false else { return }
            projectionInputsChanged(restartsPolling: false)
        }
    }

    public var quietHoursEnabled: Bool {
        didSet {
            guard oldValue != quietHoursEnabled, isApplyingPreferences == false else { return }
            settingsChanged(reconcilesDemand: true)
        }
    }

    public var quietStart: Date {
        didSet {
            guard oldValue != quietStart, isApplyingPreferences == false else { return }
            settingsChanged(reconcilesDemand: true)
        }
    }

    public var quietEnd: Date {
        didSet {
            guard oldValue != quietEnd, isApplyingPreferences == false else { return }
            settingsChanged(reconcilesDemand: true)
        }
    }

    public private(set) var isCalibrating = false
    public private(set) var controllerColorScheme: ColorScheme?
    public private(set) var reduceMotion = false

    let preferenceStore: any ThrowPreferenceStore
    let credentialStore: any AircraftCredentialStore
    let sourceFactory: any AircraftSourceProducing
    let airAndSpaceRuntime: AirAndSpaceRuntime
    let experienceCoordinator: ProjectionExperienceCoordinator
    let cloudTransport: any HTTPTransport
    let dateProvider: any DateProvider
    let locationSource: any ThrowLocationSource
    let calendar: Calendar
    let layerCatalog: LayerCatalog
    let projectionWorker: ProjectionFrameWorker

    @ObservationIgnored var isApplyingPreferences = false
    @ObservationIgnored var hasStarted = false
    @ObservationIgnored var isForeground = true
    @ObservationIgnored var selectedSourceConfiguration: AircraftSourceConfiguration?
    @ObservationIgnored var validatedSourceConfiguration: AircraftSourceConfiguration?
    @ObservationIgnored var confirmedLocation: ConfirmedObserverLocation?
    @ObservationIgnored var locationMode: ObserverLocationMode = .gps
    @ObservationIgnored var pendingLocationFix: LocationFix?
    @ObservationIgnored var mayApplyTrueHeadingHint = true
    @ObservationIgnored var currentLayerFrame: LayerFrame?
    @ObservationIgnored var currentExperienceFrame: ProjectionExperienceFrame
    @ObservationIgnored var semanticFramesByExperience: [
        ProjectionExperienceID: ProjectionExperienceFrame
    ] = [:]
    @ObservationIgnored var preparedOutputsByExperience: [
        ProjectionExperienceID: ProjectionFrameWorkerOutput
    ] = [:]
    @ObservationIgnored var currentSnapshot: AircraftSnapshot?
    @ObservationIgnored var outputDemands: Set<ProjectionOutput> = []
    @ObservationIgnored var temporaryWakeUntil: Date?
    @ObservationIgnored var activePollingSignature: PollingSignature?
    @ObservationIgnored var demandGeneration: UInt64 = 0
    @ObservationIgnored var renderGeneration: UInt64 = 0
    @ObservationIgnored var locationGeneration: UInt64 = 0
    @ObservationIgnored var projectionSessionLocationGeneration: UInt64 = 0
    @ObservationIgnored var projectionSessionLocationGate: ProjectionSessionLocationGate = .required
    @ObservationIgnored var airAndSpaceUpdateTask: Task<Void, Never>?
    @ObservationIgnored var experienceStateTask: Task<Void, Never>?
    @ObservationIgnored var experienceActionTask: Task<Void, Never>?
    @ObservationIgnored var airAndSpaceActivationGeneration: UInt64 = 0
    @ObservationIgnored var demandTask: Task<Void, Never>?
    @ObservationIgnored var isReconcilingDemand = false
    @ObservationIgnored var renderTask: Task<Void, Never>?
    @ObservationIgnored var preferenceSaveTask: Task<Void, Never>?
    @ObservationIgnored var locationTask: Task<Void, Never>?
    @ObservationIgnored var quietBoundaryTask: Task<Void, Never>?
    @ObservationIgnored var timeChangeTasks: [Task<Void, Never>] = []
    @ObservationIgnored var cachedFlightradar24Usage: CachedFlightradar24Usage?
    @ObservationIgnored var lastFlightradar24UsageRequestAt: Date?
    @ObservationIgnored var flightradar24UsageGeneration: UInt64 = 0
    @ObservationIgnored var sourceMutationInProgress = false
    @ObservationIgnored var sourceMutationNeedsPreferenceSave = false

    public init(
        preferences: ThrowPreferences,
        preferenceStore: any ThrowPreferenceStore,
        credentialStore: any AircraftCredentialStore,
        sourceFactory: any AircraftSourceProducing,
        pollingCoordinator: AircraftPollingCoordinator,
        cloudTransport: any HTTPTransport,
        dateProvider: any DateProvider,
        locationSource: any ThrowLocationSource,
        calendar: Calendar,
        layerCatalog: LayerCatalog,
        geographyLogger: any GeographyLogging,
        motionLogger: any ProjectionMotionLogging,
        routeResolver: FlightRouteResolver,
        routeLogger: any FlightRouteLogging,
        rotationClock: any ProjectionRotationClock,
        softwareCredits: [SoftwareCredit],
    ) {
        setupCompleted = preferences.setupCompleted
        projectionPlaylist = preferences.playlist
        activeExperienceID = preferences.playlist.selectedExperienceID
        requestedExperienceID = nil
        nextExperienceID = preferences.playlist.selectedExperienceID.flatMap(
            preferences.playlist.experience(after:),
        )
        prewarmingExperienceID = nil
        experienceDwellEndsAt = nil
        experienceSelectionFailure = nil
        projectionMode = preferences.selectedProjectionMode ?? .map
        mapRadius = preferences.mapViewport.radius.value
        mapCenters = preferences.mapCenters
        minimumElevation = preferences.skyViewport.minimumElevation.degrees
        flightsEnabled = preferences.flightsEnabled
        airlineAccentsEnabled = preferences.airlineAccentsEnabled
        geographyEnabled = preferences.geography.isEnabled
        labelMode = preferences.labelMode
        includeGroundAircraft = preferences.includeGroundAircraft
        markSizePercent = preferences.markSizePercent
        intensityPercent = preferences.intensityPercent
        geographyIntensityPercent = preferences.geography.intensityPercent
        screenTopBearing = preferences.calibration.screenTopBearing.degrees
        screenRotation = preferences.calibration.rotation
        flipHorizontal = preferences.calibration.flipHorizontal
        flipVertical = preferences.calibration.flipVertical
        safeInsetPercent = preferences.calibration.safeInsetFraction * 100
        calibrationVerified = preferences.calibration.verifiedOnExternalDisplay
        quietHoursEnabled = preferences.quietSchedule.interval != nil
        quietStart = Self.date(
            for: preferences.quietSchedule.interval?.start,
            fallbackHour: 22,
            calendar: calendar,
        )
        quietEnd = Self.date(
            for: preferences.quietSchedule.interval?.end,
            fallbackHour: 7,
            calendar: calendar,
        )
        projectionFrame = ProjectionFrame(
            mode: preferences.selectedProjectionMode ?? .map,
            generatedAt: dateProvider.now(),
            geography: nil,
            geographyOpacity: 1,
            marks: [],
        )
        observerMapPoint = nil
        currentExperienceFrame = .airAndSpace(.empty)
        semanticFramesByExperience[.airAndSpace] = currentExperienceFrame
        self.preferenceStore = preferenceStore
        self.credentialStore = credentialStore
        self.sourceFactory = sourceFactory
        self.cloudTransport = cloudTransport
        self.dateProvider = dateProvider
        self.locationSource = locationSource
        self.calendar = calendar
        self.layerCatalog = layerCatalog
        let flightsRuntime = layerCatalog.flights.runtimeFactory()
        airAndSpaceRuntime = AirAndSpaceRuntime(
            pollingCoordinator: pollingCoordinator,
            flightsRuntime: flightsRuntime,
            routeResolver: routeResolver,
            routeLogger: routeLogger,
            dateProvider: dateProvider,
        )
        experienceCoordinator = ProjectionExperienceCoordinator(
            playlist: preferences.playlist,
            clock: rotationClock,
        )
        projectionWorker = ProjectionFrameWorker(
            geographyRuntime: layerCatalog.geography.runtimeFactory(),
            geographyLogger: geographyLogger,
            motionLogger: motionLogger,
        )
        self.softwareCredits = softwareCredits
        selectedSourceConfiguration = preferences.selectedSource
        validatedSourceConfiguration = preferences.validatedSource
        confirmedLocation = preferences.confirmedLocation
        locationMode = preferences.locationMode
        locationHealth = Self.locationHealth(
            for: preferences.confirmedLocation,
            now: dateProvider.now(),
        )
        mayApplyTrueHeadingHint = preferences.setupCompleted == false
            && preferences.calibration == .defaultValue
    }

    public var hasProjectionOutputDemand: Bool {
        projectionOutputCount > 0
    }

    public var hasExternalDisplayOutput: Bool {
        guard projectionOutputCount > 0 else { return false }
        return outputDemands.contains { output in
            if case .externalDisplay = output { true } else { false }
        }
    }

    public var markSizeMultiplier: Double {
        markSizePercent / 100
    }

    public var intensityMultiplier: Double {
        intensityPercent / 100
    }

    public var geographyIntensityMultiplier: Double {
        geographyIntensityPercent / 100
    }

    public var lastUpdate: Date? {
        switch activeExperienceHealth {
            case let .healthy(lastUpdate, _): lastUpdate
            case let .retrying(lastUpdate, _, _, _): lastUpdate
            case .idle, .loading, .failed, .quiet: nil
        }
    }

    public var nextRetry: Date? {
        if case let .retrying(_, nextRetry, _, _) = activeExperienceHealth {
            nextRetry
        } else {
            nil
        }
    }

    public var outputHealth: OutputHealth {
        if outputDemands.isEmpty { return .disconnected }
        if outputDemands.count > 1 { return .multiple(outputDemands.count) }
        guard let output = outputDemands.first else { return .disconnected }
        switch output {
            case .externalDisplay: return .externalDisplay
            case .fullScreen: return .fullScreen
            case .preview, .calibration: return .preview
        }
    }

    public var projectionAccessibilitySummary: String {
        let presentation = ProjectionExperiencePresentation(
            id: activeExperienceID ?? projectionFrame.experienceID,
        )
        let count = activeExperienceHealth.visibleContentCount.formatted(.number)
        var summary = "\(presentation.name), \(String(localized: .projectionPreviewSummary)), \(count) \(presentation.visibleContentLabel), \(activeExperienceHealth.accessibilityDescription)"
        if geographyLayerHealth == .unavailable {
            summary += ", \(String(localized: .layerGeographyUnavailableHint))"
        }
        return summary
    }

    public func start() async {
        guard hasStarted == false else { return }
        hasStarted = true
        do {
            let preferences = try await preferenceStore.load()
            apply(preferences)
            await experienceCoordinator.configure(preferences.playlist)
        } catch is CancellationError {
            hasStarted = false
            return
        } catch {
            settingsFailure = error.localizedDescription
            setupCompleted = false
            feedHealth = .failed(.unknown)
        }

        do {
            rapidAPICredentialState = try await credentialStore.state(for: .rapidAPI)
            flightradar24CredentialState = try await credentialStore.state(for: .flightradar24)
        } catch is CancellationError {
            hasStarted = false
            return
        } catch {
            rapidAPICredentialState = .missing
            flightradar24CredentialState = .missing
            settingsFailure = error.localizedDescription
        }

        let experienceStates = await experienceCoordinator.stateUpdates()
        experienceStateTask?.cancel()
        experienceStateTask = Task(name: "Throw observe projection experience state") {
            [weak self] in
            for await state in experienceStates {
                guard Task.isCancelled == false else { return }
                self?.applyExperienceCoordinatorState(state)
            }
        }
        let experienceActions = await experienceCoordinator.actions()
        experienceActionTask?.cancel()
        experienceActionTask = Task(name: "Throw perform projection experience actions") {
            [weak self] in
            for await action in experienceActions {
                guard Task.isCancelled == false, let self else { return }
                await applyExperienceCoordinatorAction(action)
            }
        }

        let updates = await airAndSpaceRuntime.stateUpdates()
        airAndSpaceUpdateTask?.cancel()
        airAndSpaceUpdateTask = Task(name: "Throw observe Air & Space runtime") {
            [weak self] in
            for await update in updates {
                guard Task.isCancelled == false else { return }
                await self?.applyAirAndSpaceUpdate(update)
            }
        }
        installTimeChangeObservers()
        scheduleDemandReconciliation()
    }

    public func projectionOutputConnected(_ output: ProjectionOutput) {
        let startsProjectionSession = outputDemands.isEmpty
        let inserted = outputDemands.insert(output).inserted
        guard inserted else { return }
        if startsProjectionSession {
            projectionSessionLocationGate = .required
        }
        projectionOutputCount = outputDemands.count
        updateCalibrationState()
        scheduleDemandReconciliation()
    }

    public func projectionOutputDisconnected(_ output: ProjectionOutput) {
        guard outputDemands.remove(output) != nil else { return }
        projectionOutputCount = outputDemands.count
        if outputDemands.isEmpty {
            endProjectionSessionLocationGate()
        }
        updateCalibrationState()
        scheduleDemandReconciliation()
    }

    public func applicationDidEnterBackground() {
        guard isForeground else { return }
        isForeground = false
        cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: true)
        scheduleDemandReconciliation()
    }

    public func applicationWillEnterForeground() {
        guard isForeground == false else { return }
        isForeground = true
        expireTemporaryWakeIfNeeded()
        scheduleDemandReconciliation()
    }

    public func updateControllerColorScheme(_ colorScheme: ColorScheme) {
        guard controllerColorScheme != colorScheme else { return }
        controllerColorScheme = colorScheme
    }

    public func updateReduceMotion(_ isEnabled: Bool) {
        guard reduceMotion != isEnabled else { return }
        reduceMotion = isEnabled
        restartRenderer()
    }

    isolated deinit {
        airAndSpaceUpdateTask?.cancel()
        experienceStateTask?.cancel()
        experienceActionTask?.cancel()
        demandTask?.cancel()
        renderTask?.cancel()
        preferenceSaveTask?.cancel()
        locationTask?.cancel()
        quietBoundaryTask?.cancel()
        timeChangeTasks.forEach { $0.cancel() }
        locationSource.stopUpdates()
    }

    private func updateCalibrationState() {
        let newValue = outputDemands.contains { output in
            if case .calibration = output { true } else { false }
        }
        guard newValue != isCalibrating else { return }
        isCalibrating = newValue
    }

    static func date(for time: LocalTime?, fallbackHour: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = time?.hour ?? fallbackHour
        components.minute = time?.minute ?? 0
        guard let date = calendar.date(from: components) else {
            assertionFailure("The current calendar could not make a quiet-hours date")
            return .now
        }
        return date
    }

    static func locationHealth(
        for location: ConfirmedObserverLocation?,
        now: Date,
    ) -> LocationHealth {
        guard let location else { return .missing }
        let accuracy = location.horizontalAccuracyMeters ?? 0
        if now.timeIntervalSince(location.confirmedAt) > 24 * 60 * 60 {
            return .stale(accuracyMeters: accuracy, acceptedAt: location.confirmedAt)
        }
        return .confirmed(accuracyMeters: accuracy, acceptedAt: location.confirmedAt)
    }
}
