import Foundation
import Observation
import ThrowCore

/// Session-scoped draft for the required setup flow.
@MainActor
@Observable
final class OnboardingFlowModel {
    private let session: ThrowSession
    private let outputs: ControllerProjectionOutputs

    var step: OnboardingStep = .welcome
    var locationMode: LocationSelectionMode = .gps
    var latitude = 0.0
    var longitude = 0.0
    var observerAltitudeFeet = 0.0
    var airAndSpaceDraft = AirAndSpaceSetupDraft()
    var sourceChoice: AircraftSourceChoice? {
        get { airAndSpaceDraft.sourceChoice }
        set {
            guard airAndSpaceDraft.sourceChoice != newValue else { return }
            airAndSpaceDraft.sourceChoice = newValue
            invalidateTestedSource()
        }
    }

    var readsbURL: String {
        get { airAndSpaceDraft.readsbURL }
        set {
            guard airAndSpaceDraft.readsbURL != newValue else { return }
            airAndSpaceDraft.readsbURL = newValue
            invalidateTestedSource()
        }
    }

    var rapidAPIKey: String {
        get { airAndSpaceDraft.rapidAPIKey }
        set {
            let oldValue = airAndSpaceDraft.rapidAPIKey
            airAndSpaceDraft.rapidAPIKey = newValue
            guard oldValue != newValue, newValue.isEmpty == false else { return }
            invalidateTestedSource()
        }
    }

    var pollingIntervalSeconds: Double {
        get { airAndSpaceDraft.pollingIntervalSeconds }
        set {
            guard airAndSpaceDraft.pollingIntervalSeconds != newValue else { return }
            airAndSpaceDraft.pollingIntervalSeconds = newValue
            invalidateTestedSource()
        }
    }

    var sourceValidation: SourceValidationState {
        get { airAndSpaceDraft.sourceValidation }
        set { airAndSpaceDraft.sourceValidation = newValue }
    }

    var selectedMode: ProjectionMode? {
        get { airAndSpaceDraft.selectedMode }
        set { airAndSpaceDraft.selectedMode = newValue }
    }

    var mapRadius: Double {
        get { airAndSpaceDraft.mapRadius }
        set { airAndSpaceDraft.mapRadius = newValue }
    }

    var minimumElevation: Double {
        get { airAndSpaceDraft.minimumElevation }
        set { airAndSpaceDraft.minimumElevation = newValue }
    }

    var screenTopBearing = ProjectionCalibration.defaultValue.screenTopBearing.degrees {
        didSet {
            guard oldValue != screenTopBearing else { return }
            synchronizeCalibrationDraft()
        }
    }

    var rotation = ProjectionCalibration.defaultValue.rotation {
        didSet {
            guard oldValue != rotation else { return }
            synchronizeCalibrationDraft()
        }
    }

    var flipsHorizontally = ProjectionCalibration.defaultValue.flipHorizontal {
        didSet {
            guard oldValue != flipsHorizontally else { return }
            synchronizeCalibrationDraft()
        }
    }

    var flipsVertically = ProjectionCalibration.defaultValue.flipVertical {
        didSet {
            guard oldValue != flipsVertically else { return }
            synchronizeCalibrationDraft()
        }
    }

    var safeInsetPercent = ProjectionCalibration.defaultValue.safeInsetFraction * 100 {
        didSet {
            guard oldValue != safeInsetPercent else { return }
            synchronizeCalibrationDraft()
        }
    }

    var calibrationVerified = false {
        didSet {
            guard oldValue != calibrationVerified else { return }
            synchronizeCalibrationDraft()
        }
    }

    var calibrationOutputChoice: OnboardingCalibrationOutputChoice? {
        didSet {
            guard oldValue != calibrationOutputChoice else { return }
            didPresentFullScreenPreview = false
            if calibrationOutputChoice != .externalDisplay {
                calibrationVerified = false
            }
        }
    }

    var quietEnabled = false
    var quietStart: Date
    var quietEnd: Date

    private var sourceTestGeneration: UInt64 = 0
    private var calibrationDemandIsActive = false
    private var didPresentFullScreenPreview = false

    init(session: ThrowSession, outputs: ControllerProjectionOutputs) {
        self.session = session
        self.outputs = outputs
        switch session.observerLocationMode {
            case .gps: locationMode = .gps
            case .manual: locationMode = .manual
        }
        latitude = session.observerLatitude
        longitude = session.observerLongitude
        observerAltitudeFeet = session.observerAltitudeFeet
        screenTopBearing = session.screenTopBearing
        rotation = session.screenRotation
        flipsHorizontally = session.flipHorizontal
        flipsVertically = session.flipVertical
        safeInsetPercent = session.safeInsetPercent
        calibrationVerified = session.calibrationVerified
        quietEnabled = session.quietHoursEnabled
        quietStart = session.quietStart
        quietEnd = session.quietEnd
    }

    var canContinue: Bool {
        switch step {
            case .welcome, .ready:
                true
            case .location:
                switch locationMode {
                    case .gps:
                        session.locationHealth.isAcceptable
                    case .manual:
                        (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
                }
            case .source:
                sourceChoice != nil && sourceValidation.isSuccessful
                    && validatedSourceDraft != nil
            case .projection:
                selectedMode != nil
            case .calibration:
                (0 ... 20).contains(safeInsetPercent) && calibrationOutputIsReady
            case .appearance:
                quietEnabled == false || quietScheduleIsValid
        }
    }

    private var validatedSourceDraft: ValidatedAircraftSourceDraft? {
        get { airAndSpaceDraft.validatedSource }
        set { airAndSpaceDraft.validatedSource = newValue }
    }

    var locationHealth: LocationHealth {
        session.locationHealth
    }

    var progress: Double {
        Double(step.rawValue + 1) / Double(OnboardingStep.allCases.count)
    }

    var settingsFailure: String? {
        session.settingsFailure
    }

    var hasConnectedExternalDisplay: Bool {
        session.hasExternalDisplayOutput
    }

    var fullScreenOutputID: ProjectionOutputID {
        outputs.fullScreen
    }

    var sessionForProjection: ThrowSession {
        session
    }

    var rapidAPICredentialState: CredentialState {
        if let replacementCredential = validatedSourceDraft?.replacementCredential {
            return .saved(lastFour: replacementCredential.lastFour)
        }
        switch sourceChoice {
            case .flightradar24: return session.flightradar24CredentialState
            case .adsbExchange, .adsbLol, .readsb, nil: return session.rapidAPICredentialState
        }
    }

    var hasStagedRapidAPICredential: Bool {
        validatedSourceDraft?.replacementCredential != nil
    }

    var quietScheduleIsValid: Bool {
        quietEnabled == false || quietStartMinutes != quietEndMinutes
    }

    var usageEstimate: ADSBExchangeUsageEstimate {
        do {
            return try ADSBExchangeUsageEstimator.estimate(
                pollingInterval: PollingInterval(seconds: Int(pollingIntervalSeconds)),
                quietSchedule: draftQuietSchedule(),
            )
        } catch {
            assertionFailure("Validated onboarding usage inputs must produce an estimate: \(error)")
            return ADSBExchangeUsageEstimator.estimate(
                pollingInterval: .defaultValue,
                quietSchedule: .disabled,
            )
        }
    }

    var didVerifyFullScreenPreview: Bool {
        didPresentFullScreenPreview
    }

    func advance() async {
        guard canContinue else { return }
        if step == .location {
            let saved = await session.saveObserverLocation(
                mode: locationMode == .gps ? .gps : .manual,
                latitude: latitude,
                longitude: longitude,
                altitudeFeet: observerAltitudeFeet,
            )
            guard saved else { return }
        }
        if step == .ready {
            await complete()
            return
        }
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func moveBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func locate() async {
        await session.refreshLocation()
        latitude = session.observerLatitude
        longitude = session.observerLongitude
        observerAltitudeFeet = session.observerAltitudeFeet
        screenTopBearing = session.screenTopBearing
    }

    func acceptOfferedLocation() async {
        await session.acceptOfferedLocation()
        latitude = session.observerLatitude
        longitude = session.observerLongitude
        observerAltitudeFeet = session.observerAltitudeFeet
        screenTopBearing = session.screenTopBearing
    }

    func beginCalibration() {
        guard calibrationDemandIsActive == false else { return }
        calibrationDemandIsActive = true
        synchronizeCalibrationDraft()
        session.projectionOutputConnected(.calibration(outputs.calibration))
    }

    func endCalibration() {
        guard calibrationDemandIsActive else { return }
        calibrationDemandIsActive = false
        session.projectionOutputDisconnected(.calibration(outputs.calibration))
    }

    func markFullScreenPreviewPresented() {
        didPresentFullScreenPreview = true
    }

    #if DEBUG
        func seedValidatedSourceForSnapshot(_ configuration: AircraftSourceConfiguration) {
            validatedSourceDraft = ValidatedAircraftSourceDraft(
                source: AircraftSourceValidationDraft(configuration: configuration),
            )
            sourceValidation = .succeeded
        }
    #endif

    func testSource() async {
        guard let sourceChoice else { return }
        sourceTestGeneration &+= 1
        let generation = sourceTestGeneration
        validatedSourceDraft = nil
        sourceValidation = .testing
        let outcome = await session.testSource(
            choice: sourceChoice,
            readsbURL: readsbURL,
            rapidAPIKey: rapidAPIKey,
            pollingIntervalSeconds: Int(pollingIntervalSeconds),
        )
        guard generation == sourceTestGeneration else { return }
        switch outcome {
            case let .succeeded(draft):
                validatedSourceDraft = draft
                sourceValidation = .succeeded
                rapidAPIKey = ""
            case let .failed(failure):
                sourceValidation = .failed(failure)
            case .cancelled:
                sourceValidation = .untested
        }
    }

    private func complete() async {
        guard let selectedMode, let validatedSourceDraft else { return }
        await session.completeOnboarding(
            locationMode: locationMode,
            latitude: latitude,
            longitude: longitude,
            observerAltitudeFeet: observerAltitudeFeet,
            validatedSourceDraft: validatedSourceDraft,
            mode: selectedMode,
            mapRadius: mapRadius,
            minimumElevation: minimumElevation,
            screenTopBearing: screenTopBearing,
            rotation: rotation,
            flipsHorizontally: flipsHorizontally,
            flipsVertically: flipsVertically,
            safeInsetPercent: safeInsetPercent,
            calibrationVerified: calibrationVerified,
            quietEnabled: quietEnabled,
            quietStart: quietStart,
            quietEnd: quietEnd,
        )
    }

    private func invalidateTestedSource() {
        sourceTestGeneration &+= 1
        validatedSourceDraft = nil
        sourceValidation = .untested
    }

    private var calibrationOutputIsReady: Bool {
        switch calibrationOutputChoice {
            case .externalDisplay:
                hasConnectedExternalDisplay
            case .fullScreenPreview:
                true
            case nil:
                false
        }
    }

    private var quietStartMinutes: Int {
        let components = session.calendar.dateComponents([.hour, .minute], from: quietStart)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private var quietEndMinutes: Int {
        let components = session.calendar.dateComponents([.hour, .minute], from: quietEnd)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func synchronizeCalibrationDraft() {
        guard calibrationDemandIsActive else { return }
        session.previewCalibration(
            screenTopBearing: screenTopBearing,
            rotation: rotation,
            flipsHorizontally: flipsHorizontally,
            flipsVertically: flipsVertically,
            safeInsetPercent: safeInsetPercent,
            calibrationVerified: calibrationVerified,
        )
    }

    private func draftQuietSchedule() throws -> QuietSchedule {
        guard quietEnabled else { return .disabled }
        return try QuietSchedule(
            start: LocalTime(
                hour: quietStartMinutes / 60,
                minute: quietStartMinutes % 60,
            ),
            end: LocalTime(
                hour: quietEndMinutes / 60,
                minute: quietEndMinutes % 60,
            ),
        )
    }
}
