import Observation
import SwiftUI
import ThrowCore

/// Controller-visible availability of Throw's bundled Geography layer.
public enum GeographyLayerHealth: Equatable, Sendable {
    case idle
    case available
    case unavailable
}

/// Holds later runtime output until one prepared experience frame finishes its black exchange.
enum ProjectionPresentationTransition {
    case fadingOut(
        targetLease: ProjectionActivationLease,
        bufferedTargetUpdate: AirAndSpaceRuntimeUpdate?,
    )
    case fadingIn(
        targetLease: ProjectionActivationLease,
        bufferedTargetUpdate: AirAndSpaceRuntimeUpdate?,
    )

    var targetLease: ProjectionActivationLease {
        switch self {
            case let .fadingOut(targetLease, _), let .fadingIn(targetLease, _):
                targetLease
        }
    }

    var bufferedTargetUpdate: AirAndSpaceRuntimeUpdate? {
        switch self {
            case let .fadingOut(_, update), let .fadingIn(_, update):
                update
        }
    }

    func buffering(_ update: AirAndSpaceRuntimeUpdate) -> Self {
        guard targetLease.experienceID == .airAndSpace,
              update.activationLease == targetLease
        else { return self }
        switch self {
            case let .fadingOut(targetLease, _):
                return .fadingOut(
                    targetLease: targetLease,
                    bufferedTargetUpdate: update,
                )
            case let .fadingIn(targetLease, _):
                return .fadingIn(
                    targetLease: targetLease,
                    bufferedTargetUpdate: update,
                )
        }
    }

    func advancingToFadeIn() -> Self {
        .fadingIn(
            targetLease: targetLease,
            bufferedTargetUpdate: bufferedTargetUpdate,
        )
    }
}

/// The single main-actor presentation session shared by every Throw scene.
@MainActor
@Observable
public final class ThrowSession {
    public internal(set) var setupState: ThrowSetupState {
        didSet {
            guard oldValue != setupState else { return }
            launchState = launchState.replacingLoadedSetup(with: setupState)
        }
    }

    public internal(set) var launchState: ThrowSessionLaunchState
    public internal(set) var durableLoggingState: ThrowDurableLoggingState
    var projectionPresentationState: ProjectionPresentationState

    var experienceCoordinatorState: ProjectionExperienceCoordinatorState {
        projectionPresentationState.coordinator
    }

    var visibleProjection: VisibleProjection {
        projectionPresentationState.visible
    }

    /// Compatibility access for Air & Space callers while health remains keyed by experience.
    public internal(set) var feedHealth: FeedHealth {
        get { experienceHealth[.airAndSpace] ?? .idle }
        set {
            let coordinator = experienceCoordinatorState.updatingHealth(
                newValue,
                for: .airAndSpace,
            )
            guard let presentation = projectionPresentationState.updatingCoordinator(coordinator)
            else {
                assertionFailure("Health metadata must not change the visible identity")
                return
            }
            projectionPresentationState = presentation
        }
    }

    public internal(set) var projectionPlaylist: ProjectionPlaylist
    public var activeExperienceID: ProjectionExperienceID? {
        experienceCoordinatorState.activeExperienceID
    }

    public var requestedExperienceID: ProjectionExperienceID? {
        experienceCoordinatorState.requestedExperienceID
    }

    public var nextExperienceID: ProjectionExperienceID? {
        experienceCoordinatorState.nextExperienceID
    }

    public var prewarmingExperienceID: ProjectionExperienceID? {
        experienceCoordinatorState.prewarmingExperienceID
    }

    public var experienceDwellEndsAt: Date? {
        experienceCoordinatorState.dwellEndsAt
    }

    public var isExperienceRotationPaused: Bool {
        experienceCoordinatorState.isPaused
    }

    public var experienceHealth: [ProjectionExperienceID: FeedHealth] {
        experienceCoordinatorState.healthByExperience
    }

    public var experienceSelectionFailure: ThrowFailureCategory? {
        experienceCoordinatorState.manualSelectionFailure
    }

    public internal(set) var locationHealth: LocationHealth = .missing
    public var projectionFrame: ProjectionFrame {
        visibleProjection.frame
    }

    public var observerMapPoint: ProjectionPoint? {
        visibleProjection.observerPoint
    }

    var projectionMarkEffects: [LayerMarkID: ProjectionMarkEffect] {
        visibleProjection.effects
    }

    public internal(set) var projectionMarkOpacity = 1.0
    public internal(set) var projectionSurfaceOpacity = 1.0
    public var geographyLayerHealth: GeographyLayerHealth {
        visibleProjection.geographyHealth
    }

    public var projectionOutputCount: Int {
        outputDemands.count
    }

    public internal(set) var rapidAPICredentialState: CredentialState = .missing
    public internal(set) var flightradar24CredentialState: CredentialState = .missing
    public let softwareCreditsState: SoftwareCreditsLoadState
    private(set) var postLaunchFailureLedger = ThrowPostLaunchFailureLedger()

    public internal(set) var globalPreferences: ThrowGlobalPreferences
    public internal(set) var airAndSpacePreferences: AirAndSpacePreferences
    var calibrationPreview: ProjectionCalibration?

    public var projectionMode: ProjectionMode {
        setupState.selectedProjectionMode ?? .map
    }

    public var mapRadius: Double {
        airAndSpacePreferences.mapViewport.radius.value
    }

    public var mapCenters: MapCenterPreferences {
        airAndSpacePreferences.mapCenters
    }

    public var minimumElevation: Double {
        airAndSpacePreferences.skyViewport.minimumElevation.degrees
    }

    public var flightsEnabled: Bool {
        airAndSpacePreferences.flightsEnabled
    }

    public var airlineAccentsEnabled: Bool {
        airAndSpacePreferences.airlineAccentsEnabled
    }

    public var geographyEnabled: Bool {
        airAndSpacePreferences.geography.isEnabled
    }

    public var labelMode: FlightLabelMode {
        airAndSpacePreferences.labelMode
    }

    public var includeGroundAircraft: Bool {
        airAndSpacePreferences.includeGroundAircraft
    }

    public var markSizePercent: Double {
        airAndSpacePreferences.markSizePercent
    }

    public var intensityPercent: Double {
        globalPreferences.intensityPercent
    }

    public var geographyIntensityPercent: Double {
        airAndSpacePreferences.geography.intensityPercent
    }

    public var projectionCalibration: ProjectionCalibration {
        calibrationPreview ?? globalPreferences.calibration
    }

    public var screenTopBearing: Double {
        projectionCalibration.screenTopBearing.degrees
    }

    public var screenRotation: ScreenRotation {
        projectionCalibration.rotation
    }

    public var flipHorizontal: Bool {
        projectionCalibration.flipHorizontal
    }

    public var flipVertical: Bool {
        projectionCalibration.flipVertical
    }

    public var safeInsetPercent: Double {
        projectionCalibration.safeInsetFraction * 100
    }

    public var calibrationVerified: Bool {
        projectionCalibration.verifiedOnExternalDisplay
    }

    public var quietSchedule: QuietSchedule {
        globalPreferences.quietSchedule
    }

    public var quietHoursEnabled: Bool {
        quietSchedule.interval != nil
    }

    public var quietStart: Date {
        Self.date(for: quietSchedule.interval?.start, fallbackHour: 22, calendar: calendar)
    }

    public var quietEnd: Date {
        Self.date(for: quietSchedule.interval?.end, fallbackHour: 7, calendar: calendar)
    }

    public private(set) var isCalibrating = false
    public private(set) var controllerColorScheme: ColorScheme?
    public private(set) var reduceMotion = false

    let preferenceStore: any ThrowPreferenceStore
    let credentialStore: any AircraftCredentialStore
    let sourceService: any AircraftSourceOperationServing
    let airAndSpaceRuntime: AirAndSpaceRuntime
    let experienceCoordinator: ProjectionExperienceCoordinator
    let dateProvider: any DateProvider
    let locationSource: any ThrowLocationSource
    let calendar: Calendar
    let layerCatalog: LayerCatalog
    let projectionWorker: ProjectionFrameWorker
    let durableLoggingStarter: (any ThrowDurableLoggingStarting)?

    var sessionFailureLogger: any ThrowSessionFailureLogging {
        if let durableLoggingStarter {
            durableLoggingStarter
        } else {
            DiscardingThrowSessionFailureLogger()
        }
    }

    @ObservationIgnored var hasForegroundControllerScene: Bool
    #if DEBUG
        @_spi(Testing) public var hasForegroundControllerSceneForTesting: Bool {
            hasForegroundControllerScene
        }
    #endif
    var aircraftSourceSelection: AircraftSourceSelection {
        setupState.sourceSelection
    }

    var selectedSourceConfiguration: AircraftSourceConfiguration? {
        setupState.selectedSource
    }

    var validatedSourceConfiguration: AircraftSourceConfiguration? {
        setupState.validatedSource
    }

    var confirmedLocation: ConfirmedObserverLocation? {
        setupState.confirmedLocation
    }

    var locationMode: ObserverLocationMode {
        setupState.locationMode
    }

    #if DEBUG
        @_spi(Testing) public func replaceSourceSelectionForTesting(
            _ selection: AircraftSourceSelection,
        ) {
            setupState = setupState.updatingSourceSelection(selection)
        }

        @_spi(Testing) public func replaceConfirmedLocationForTesting(
            _ location: ConfirmedObserverLocation?,
        ) {
            setupState = setupState.updatingLocation(
                mode: setupState.locationMode,
                confirmedLocation: location,
            )
        }

        @_spi(Testing) public func replaceLocationModeForTesting(
            _ mode: ObserverLocationMode,
        ) {
            setupState = setupState.updatingLocation(
                mode: mode,
                confirmedLocation: setupState.confirmedLocation,
            )
        }
    #endif

    @ObservationIgnored var pendingLocationFix: LocationFix?
    @ObservationIgnored var mayApplyTrueHeadingHint = true
    @ObservationIgnored var pendingAirAndSpaceFrame = AirAndSpaceExperienceFrame.empty
    @ObservationIgnored var projectionPresentationTransition: ProjectionPresentationTransition?
    @ObservationIgnored var preparedProjection: VisibleProjection?
    @ObservationIgnored var currentSnapshot: AircraftSnapshot?
    var outputDemands: Set<ProjectionOutput> = []
    @ObservationIgnored var temporaryWakeUntil: Date?
    @ObservationIgnored var activePollingSignature: PollingSignature?
    @ObservationIgnored var demandGeneration: UInt64 = 0
    @ObservationIgnored var renderGeneration: UInt64 = 0
    @ObservationIgnored var projectionInputRevision = ProjectionFrameRequest.Revision.initial
    @ObservationIgnored var locationGeneration: UInt64 = 0
    @ObservationIgnored var projectionSessionLocationGeneration: UInt64 = 0
    @ObservationIgnored var projectionSessionLocationGate: ProjectionSessionLocationGate = .required
    @ObservationIgnored var airAndSpaceUpdateTask: Task<Void, Never>?
    @ObservationIgnored var launchTask: Task<Void, Never>?
    @ObservationIgnored var durableLoggingTask: Task<Void, Never>?
    @ObservationIgnored var durableLoggingSession: (any ThrowDurableLoggingSession)?
    @ObservationIgnored var runtimeObserversInstalled = false
    @ObservationIgnored var experienceStateTask: Task<Void, Never>?
    @ObservationIgnored var experienceActionTask: Task<Void, Never>?
    @ObservationIgnored var playlistConfigurationTask: Task<Void, Never>?
    @ObservationIgnored var playlistConfigurationRevision =
        ProjectionPlaylistConfiguration.Revision.initial
    @ObservationIgnored var airAndSpaceActivation = ProjectionActivationLeaseTracker(
        experienceID: .airAndSpace,
    )
    @ObservationIgnored var demandTask: Task<Void, Never>?
    @ObservationIgnored var isReconcilingDemand = false
    @ObservationIgnored var renderTask: Task<Void, Never>?
    @ObservationIgnored var preferenceSaveTask: Task<Void, Never>?
    @ObservationIgnored var preferenceSaveQueue: [PreferenceSaveRequest] = []
    @ObservationIgnored var locationTask: Task<Void, Never>?
    @ObservationIgnored var quietBoundaryTask: Task<Void, Never>?
    @ObservationIgnored var timeChangeTasks: [Task<Void, Never>] = []
    @ObservationIgnored var cachedFlightradar24Usage: CachedFlightradar24Usage?
    @ObservationIgnored var lastFlightradar24UsageRequestAt: Date?
    @ObservationIgnored var flightradar24UsageGeneration: UInt64 = 0
    @ObservationIgnored var preferenceMutationInProgress = false
    @ObservationIgnored var deferredPreferenceSaveFailures = ThrowPostLaunchFailureLedger()
    @ObservationIgnored var onboardingCompletionInProgress = false
    #if DEBUG
        @ObservationIgnored @_spi(Testing) public var
            beforeApplyingLocationResolutionForTesting: (() -> Void)?
        @ObservationIgnored @_spi(Testing) public var
            beforePublishingProjectionForTesting: (@MainActor @Sendable () async -> Void)?
    #endif

    init(
        preferences: ThrowPreferences,
        preferenceStore: any ThrowPreferenceStore,
        credentialStore: any AircraftCredentialStore,
        sourceService: any AircraftSourceOperationServing,
        pollingCoordinator: AircraftPollingCoordinator,
        dateProvider: any DateProvider,
        locationSource: any ThrowLocationSource,
        calendar: Calendar,
        layerCatalog: LayerCatalog,
        geographyLogger: any GeographyLogging,
        motionLogger: any ProjectionMotionLogging,
        routeResolver: FlightRouteResolver,
        routeLogger: any FlightRouteLogging,
        rotationClock: any ProjectionRotationClock,
        softwareCreditsState: SoftwareCreditsLoadState,
        durableLoggingStarter: (any ThrowDurableLoggingStarting)?,
        initiallyHasForegroundControllerScene: Bool,
        initialLaunchState: ThrowSessionLaunchState,
    ) {
        hasForegroundControllerScene = initiallyHasForegroundControllerScene
        setupState = preferences.setupState
        launchState = initialLaunchState
        durableLoggingState = .unavailable
        projectionPlaylist = preferences.playlist
        let initialCoordinator = ProjectionExperienceCoordinatorState(
            playlist: preferences.playlist,
        )
        globalPreferences = preferences.global
        airAndSpacePreferences = preferences.airAndSpace
        projectionPresentationState = .initial(
            coordinator: initialCoordinator,
            preferredExperienceID: preferences.playlist.selectedExperienceID ?? .airAndSpace,
            mode: preferences.selectedProjectionMode ?? .map,
            generatedAt: dateProvider.now(),
        )
        self.preferenceStore = preferenceStore
        self.credentialStore = credentialStore
        self.sourceService = sourceService
        self.dateProvider = dateProvider
        self.locationSource = locationSource
        self.calendar = calendar
        self.layerCatalog = layerCatalog
        let sessionFailureLogger: any ThrowSessionFailureLogging = if let durableLoggingStarter {
            durableLoggingStarter
        } else {
            DiscardingThrowSessionFailureLogger()
        }
        let flightsRuntime = layerCatalog.flights.runtimeFactory()
        airAndSpaceRuntime = AirAndSpaceRuntime(
            pollingCoordinator: pollingCoordinator,
            flightsRuntime: flightsRuntime,
            routeResolver: routeResolver,
            routeLogger: routeLogger,
            dateProvider: dateProvider,
            sessionFailureLogger: sessionFailureLogger,
        )
        experienceCoordinator = ProjectionExperienceCoordinator(
            playlist: preferences.playlist,
            clock: rotationClock,
        )
        projectionWorker = ProjectionFrameWorker(
            geographyRuntime: layerCatalog.geography.runtimeFactory(),
            geographyLogger: geographyLogger,
            motionLogger: motionLogger,
            sessionFailureLogger: sessionFailureLogger,
        )
        self.softwareCreditsState = softwareCreditsState
        self.durableLoggingStarter = durableLoggingStarter
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

    func postLaunchFailures(
        for surface: ThrowPostLaunchFailure.PresentationSurface,
    ) -> [ThrowPostLaunchFailure] {
        postLaunchFailureLedger.failures.filter { $0.isRelevant(to: surface) }
    }

    func publishPostLaunchFailure(_ failure: ThrowPostLaunchFailure) {
        postLaunchFailureLedger = postLaunchFailureLedger.recording(failure)
    }

    func recordPostLaunchFailure(
        _ failure: ThrowPostLaunchFailure,
        error: any Error,
    ) {
        publishPostLaunchFailure(failure)
        logPostLaunchFailure(at: failure.owner, error: error)
    }

    func resolvePostLaunchFailure(_ owner: ThrowPostLaunchFailure.Owner) {
        postLaunchFailureLedger = postLaunchFailureLedger.resolving(owner)
    }

    func logPostLaunchFailure(
        at owner: ThrowPostLaunchFailure.Owner,
        error: any Error,
    ) {
        let operation: ThrowSessionLogEvent.PostLaunchOperation = switch owner {
            case .preferencePersistence: .preferencePersistence
            case .aircraftSource: .aircraftSource
            case .rapidAPICredential: .rapidAPICredential
            case .flightradar24Credential: .flightradar24Credential
            case .location: .location
            case .playlist: .playlist
            case .onboarding: .onboarding
            case .projectionPreparation: .projectionPreparation
            case .projectionRendering: .projectionRendering
        }
        sessionFailureLogger.recordPostLaunchFailure(at: operation, error: error)
    }

    public var setupCompleted: Bool {
        setupState.setupCompleted
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

    /// Starts the process-owned launch task. Repeated calls join the same launch.
    public func startLaunch() {
        startDurableLogging()
        guard launchTask == nil else { return }

        if launchState.isOperational {
            guard runtimeObserversInstalled == false else { return }
            launchTask = Task(name: "Throw install runtime observers") { [self] in
                await configureExperienceCoordinator(with: projectionPlaylist)
                await installRuntimeObservers()
                scheduleDemandReconciliation()
                launchTask = nil
            }
            return
        }

        launchState = .loading
        launchTask = Task(name: "Throw cold launch") { [self] in
            await performColdLaunch()
            launchTask = nil
        }
    }

    public func start() async {
        startLaunch()
        await launchTask?.value
    }

    #if DEBUG
        @_spi(Testing) public func waitForLaunchForTesting() async {
            await launchTask?.value
        }

        @_spi(Testing) public func replaceProjectionFrameForTesting(
            _ frame: ProjectionFrame,
        ) {
            guard let visible = visibleProjection.replacingFrameForTesting(frame),
                  let presentation = projectionPresentationState.replacingVisible(visible)
            else {
                assertionFailure("A test frame must match the active projection View")
                return
            }
            projectionPresentationState = presentation
        }

        @_spi(Testing) public func replaceProjectionMetadataForTesting(
            observerPoint: ProjectionPoint?,
            geographyHealth: GeographyLayerHealth,
        ) {
            let visible = visibleProjection.replacingMetadataForTesting(
                observerPoint: observerPoint,
                geographyHealth: geographyHealth,
            )
            guard let presentation = projectionPresentationState.replacingVisible(visible) else {
                assertionFailure("Test metadata must preserve the active projection View")
                return
            }
            projectionPresentationState = presentation
        }

        @_spi(Testing) public func replacePendingAirAndSpaceFrameForTesting(
            _ frame: AirAndSpaceExperienceFrame,
        ) {
            replacePendingAirAndSpaceFrame(frame)
        }

    #endif

    private func performColdLaunch() async {
        do {
            let preferences = try await loadPreferencesForLaunch()
            let credentialStates = try await loadCredentialStatesForLaunch()
            apply(preferences)
            await configureExperienceCoordinator(with: preferences.playlist)
            rapidAPICredentialState = credentialStates.rapidAPI
            flightradar24CredentialState = credentialStates.flightradar24
            await installRuntimeObservers()
            launchState = .loaded(preferences.setupState)
            scheduleDemandReconciliation()
        } catch let failure as ThrowSessionLaunchFailure {
            launchState = .failed(failure)
        } catch {
            assertionFailure("Throw launch produced an unclassified error: \(error)")
            sessionFailureLogger.recordColdLaunchFailure(at: .unexpected, error: error)
            launchState = .failed(.preferences)
        }
    }

    private func loadPreferencesForLaunch() async throws -> ThrowPreferences {
        do {
            return try await preferenceStore.load()
        } catch {
            sessionFailureLogger.recordColdLaunchFailure(at: .preferences, error: error)
            throw ThrowSessionLaunchFailure.preferences
        }
    }

    private func loadCredentialStatesForLaunch() async throws -> LoadedAircraftCredentialStates {
        let rapidAPI = try await loadCredentialStateForLaunch(for: .rapidAPI)
        let flightradar24 = try await loadCredentialStateForLaunch(for: .flightradar24)
        return LoadedAircraftCredentialStates(
            rapidAPI: rapidAPI,
            flightradar24: flightradar24,
        )
    }

    private func loadCredentialStateForLaunch(
        for id: AircraftCredentialID,
    ) async throws -> CredentialState {
        do {
            return try await credentialStore.state(for: id)
        } catch {
            sessionFailureLogger.recordColdLaunchFailure(at: .credential, error: error)
            throw ThrowSessionLaunchFailure.credential(id: id)
        }
    }

    private func installRuntimeObservers() async {
        guard runtimeObserversInstalled == false else { return }

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
        runtimeObserversInstalled = true
    }

    public func projectionOutputConnected(_ output: ProjectionOutput) {
        let startsProjectionSession = outputDemands.isEmpty
        let inserted = outputDemands.insert(output).inserted
        guard inserted else { return }
        if startsProjectionSession {
            projectionSessionLocationGate = .required
        }
        updateCalibrationState()
        scheduleDemandReconciliation()
    }

    public func projectionOutputDisconnected(_ output: ProjectionOutput) {
        guard outputDemands.remove(output) != nil else { return }
        if outputDemands.isEmpty {
            endProjectionSessionLocationGate()
        }
        updateCalibrationState()
        scheduleDemandReconciliation()
    }

    public func controllerForegroundPresenceDidChange(_ hasForegroundControllerScene: Bool) {
        guard self.hasForegroundControllerScene != hasForegroundControllerScene else { return }
        self.hasForegroundControllerScene = hasForegroundControllerScene
        if hasForegroundControllerScene {
            expireTemporaryWakeIfNeeded()
        } else {
            cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: true)
            Task(name: "Throw flush preferences in background") { [self] in
                await flushPreferencesSave()
            }
        }
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
        launchTask?.cancel()
        durableLoggingTask?.cancel()
        airAndSpaceUpdateTask?.cancel()
        experienceStateTask?.cancel()
        experienceActionTask?.cancel()
        playlistConfigurationTask?.cancel()
        demandTask?.cancel()
        renderTask?.cancel()
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
