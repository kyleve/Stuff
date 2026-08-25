import CreditKit
import Observation
import SwiftUI
import ThrowCore

/// The single main-actor presentation session shared by every Throw scene.
@MainActor
@Observable
public final class ThrowSession {
    public internal(set) var setupCompleted: Bool
    public internal(set) var feedHealth: FeedHealth = .idle
    public internal(set) var locationHealth: LocationHealth = .missing
    public internal(set) var projectionFrame: ProjectionFrame
    public internal(set) var projectionContentOpacity = 1.0
    public internal(set) var projectionOutputCount = 0
    public internal(set) var rapidAPICredentialState: CredentialState = .missing
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
    let pollingCoordinator: AircraftPollingCoordinator
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
    @ObservationIgnored var currentSnapshot: AircraftSnapshot?
    @ObservationIgnored var outputDemands: Set<ProjectionOutput> = []
    @ObservationIgnored var temporaryWakeUntil: Date?
    @ObservationIgnored var activePollingSignature: PollingSignature?
    @ObservationIgnored var demandGeneration: UInt64 = 0
    @ObservationIgnored var pollingStateGeneration: UInt64 = 0
    @ObservationIgnored var renderGeneration: UInt64 = 0
    @ObservationIgnored var locationGeneration: UInt64 = 0
    @ObservationIgnored var projectionSessionLocationGeneration: UInt64 = 0
    @ObservationIgnored var projectionSessionLocationGate: ProjectionSessionLocationGate = .required
    @ObservationIgnored var updateTask: Task<Void, Never>?
    @ObservationIgnored var demandTask: Task<Void, Never>?
    @ObservationIgnored var renderTask: Task<Void, Never>?
    @ObservationIgnored var preferenceSaveTask: Task<Void, Never>?
    @ObservationIgnored var locationTask: Task<Void, Never>?
    @ObservationIgnored var quietBoundaryTask: Task<Void, Never>?
    @ObservationIgnored var timeChangeTasks: [Task<Void, Never>] = []

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
        softwareCredits: [SoftwareCredit],
    ) {
        setupCompleted = preferences.setupCompleted
        projectionMode = preferences.selectedProjectionMode ?? .map
        mapRadius = preferences.mapViewport.radius.value
        minimumElevation = preferences.skyViewport.minimumElevation.degrees
        flightsEnabled = preferences.flightsEnabled
        labelMode = preferences.labelMode
        includeGroundAircraft = preferences.includeGroundAircraft
        markSizePercent = preferences.markSizePercent
        intensityPercent = preferences.intensityPercent
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
            marks: [],
        )
        self.preferenceStore = preferenceStore
        self.credentialStore = credentialStore
        self.sourceFactory = sourceFactory
        self.pollingCoordinator = pollingCoordinator
        self.cloudTransport = cloudTransport
        self.dateProvider = dateProvider
        self.locationSource = locationSource
        self.calendar = calendar
        self.layerCatalog = layerCatalog
        projectionWorker = ProjectionFrameWorker(
            flightsRuntime: layerCatalog.flights.runtimeFactory(),
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

    public var lastUpdate: Date? {
        switch feedHealth {
            case let .healthy(lastUpdate, _): lastUpdate
            case let .retrying(lastUpdate, _, _, _): lastUpdate
            case .idle, .loading, .failed, .quiet: nil
        }
    }

    public var nextRetry: Date? {
        if case let .retrying(_, nextRetry, _, _) = feedHealth { nextRetry } else { nil }
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
        let count = projectionFrame.visibleAircraftCount.formatted(.number)
        return "\(String(localized: .projectionPreviewSummary)), \(count) \(String(localized: .dashboardAircraftVisible)), \(feedHealth.accessibilityDescription)"
    }

    public func start() async {
        guard hasStarted == false else { return }
        hasStarted = true
        do {
            let preferences = try await preferenceStore.load()
            apply(preferences)
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
        } catch is CancellationError {
            hasStarted = false
            return
        } catch {
            rapidAPICredentialState = .missing
            settingsFailure = error.localizedDescription
        }

        let updates = await pollingCoordinator.stateUpdates()
        updateTask?.cancel()
        updateTask = Task(name: "Throw observe aircraft polling") { [weak self] in
            for await state in updates {
                guard Task.isCancelled == false else { return }
                await self?.applyPollingState(state)
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
        updateTask?.cancel()
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
