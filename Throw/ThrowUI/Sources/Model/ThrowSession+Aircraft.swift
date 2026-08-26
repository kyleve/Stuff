import Foundation
import SwiftUI
import ThrowCore

extension ThrowSession {
    var sourceChoice: AircraftSourceChoice {
        guard let kind = selectedSourceConfiguration?.kind else { return .adsbLol }
        switch kind {
            case .adsbLol: return .adsbLol
            case .readsb: return .readsb
            case .adsbExchangeRapidAPI: return .adsbExchange
            case .flightradar24: return .flightradar24
        }
    }

    public var readsbURL: String {
        if case let .readsb(configuration) = selectedSourceConfiguration {
            configuration.aircraftJSONURL.absoluteString
        } else {
            "http://readsb.local/tar1090/data/aircraft.json"
        }
    }

    public var pollingIntervalSeconds: Int {
        switch selectedSourceConfiguration {
            case let .adsbExchangeRapidAPI(configuration): configuration.pollingInterval.seconds
            case let .flightradar24(configuration): configuration.pollingInterval.seconds
            case .adsbLol, .readsb, nil: PollingInterval.defaultValue.seconds
        }
    }

    public var sourceDisplayName: String {
        switch selectedSourceConfiguration?.kind {
            case .adsbLol: String(localized: .sourceAdsbLol)
            case .readsb: String(localized: .sourceReadsb)
            case .adsbExchangeRapidAPI: String(localized: .sourceAdsbExchange)
            case .flightradar24: String(localized: .sourceFlightradar24)
            case nil: String(localized: .statusDisconnected)
        }
    }

    public var quietScheduleIsValid: Bool {
        guard quietHoursEnabled else { return true }
        let start = calendar.dateComponents([.hour, .minute], from: quietStart)
        let end = calendar.dateComponents([.hour, .minute], from: quietEnd)
        return start.hour != end.hour || start.minute != end.minute
    }

    func adsbExchangeUsageEstimate(intervalSeconds: Int) -> ADSBExchangeUsageEstimate {
        do {
            let schedule = quietScheduleIsValid ? try quietSchedule() : .disabled
            return try ADSBExchangeUsageEstimator.estimate(
                pollingInterval: PollingInterval(seconds: intervalSeconds),
                quietSchedule: schedule,
            )
        } catch {
            assertionFailure("Validated settings must produce a usage estimate: \(error)")
            return ADSBExchangeUsageEstimator.estimate(
                pollingInterval: .defaultValue,
                quietSchedule: .disabled,
            )
        }
    }

    func flightradar24CreditEstimate(
        report: Flightradar24UsageReport,
        intervalSeconds: Int,
    ) -> Flightradar24CreditEstimate? {
        do {
            let schedule = quietScheduleIsValid ? try quietSchedule() : .disabled
            return try Flightradar24CreditEstimator.estimate(
                report: report,
                pollingInterval: PollingInterval(seconds: intervalSeconds),
                quietSchedule: schedule,
                requestMultiplicity: Flightradar24RequestMultiplicity.livePosition(
                    for: aircraftQuery(),
                ),
            )
        } catch {
            assertionFailure("Validated settings must produce a credit estimate: \(error)")
            return nil
        }
    }

    func loadFlightradar24Usage() async throws -> Flightradar24UsageReport {
        let now = dateProvider.now()
        if let cachedFlightradar24Usage,
           now.timeIntervalSince(cachedFlightradar24Usage.fetchedAt) < 60
        {
            return cachedFlightradar24Usage.report
        }
        if let lastFlightradar24UsageRequestAt {
            let elapsed = max(0, now.timeIntervalSince(lastFlightradar24UsageRequestAt))
            guard elapsed >= 60 else {
                throw Flightradar24UsageError.rateLimited(
                    retryAfterSeconds: 60 - elapsed,
                )
            }
        }

        flightradar24UsageGeneration &+= 1
        let generation = flightradar24UsageGeneration
        lastFlightradar24UsageRequestAt = now
        let report = try await sourceService.flightradar24Usage(period: .last24Hours)
        try Task.checkCancellation()
        guard generation == flightradar24UsageGeneration else { throw CancellationError() }
        cachedFlightradar24Usage = CachedFlightradar24Usage(
            report: report,
            fetchedAt: dateProvider.now(),
        )
        return report
    }

    func invalidateFlightradar24Usage() {
        flightradar24UsageGeneration &+= 1
        cachedFlightradar24Usage = nil
        lastFlightradar24UsageRequestAt = nil
    }

    func testSource(
        choice: AircraftSourceChoice,
        readsbURL: String,
        rapidAPIKey: String,
        pollingIntervalSeconds: Int,
    ) async -> AircraftSourceValidationOutcome {
        let configuration: AircraftSourceConfiguration
        do {
            configuration = try sourceConfiguration(
                choice: choice,
                readsbURL: readsbURL,
                pollingIntervalSeconds: pollingIntervalSeconds,
            )
            let query = try validationQuery()
            let replacementCredential: AircraftCredential? = if choice == .adsbExchange || choice ==
                .flightradar24,
                rapidAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            {
                try AircraftCredential(secret: rapidAPIKey)
            } else {
                nil
            }
            _ = try await sourceService.testConnection(
                configuration: configuration,
                query: query,
                replacementCredential: replacementCredential,
            )
            try Task.checkCancellation()
            return .succeeded(
                ValidatedAircraftSourceDraft(
                    configuration: configuration,
                    replacementCredential: replacementCredential,
                ),
            )
        } catch is CancellationError {
            return .cancelled
        } catch let failure as AircraftSourceFailure {
            return .failed(failure.presentationCategory)
        } catch {
            return .failed(.sourceNotValidated)
        }
    }

    @discardableResult
    func useSource(_ draft: ValidatedAircraftSourceDraft) async -> Bool {
        guard sourceMutationInProgress == false else { return false }
        sourceMutationInProgress = true
        defer { finishSourceMutation() }

        let pendingSave = preferenceSaveTask
        preferenceSaveTask = nil
        pendingSave?.cancel()
        await pendingSave?.value

        let replacementSetupState = setupState.replacingSource(draft.configuration)
        let preferences: ThrowPreferences
        var replacedCredentialID: AircraftCredentialID?
        var previousCredential: AircraftCredential?
        var credentialMutationAttempted = false
        do {
            preferences = try makePreferences(setupState: replacementSetupState)
            if let replacementCredential = draft.replacementCredential {
                let credentialID: AircraftCredentialID
                switch draft.configuration.kind {
                    case .adsbExchangeRapidAPI:
                        credentialID = .rapidAPI
                    case .flightradar24:
                        credentialID = .flightradar24
                    case .adsbLol, .readsb:
                        assertionFailure("A credential-free source supplied a credential")
                        throw AircraftSourceFailure.invalidConfiguration
                }
                replacedCredentialID = credentialID
                previousCredential = try await credentialStore.credential(for: credentialID)
                try Task.checkCancellation()
                credentialMutationAttempted = true
                try await credentialStore.save(replacementCredential, for: credentialID)
                try Task.checkCancellation()
            }
            try await preferenceStore.save(preferences)
        } catch {
            let rollbackFailure: String? = if credentialMutationAttempted,
                                              let replacedCredentialID
            {
                await restoreCredential(previousCredential, for: replacedCredentialID)
            } else {
                nil
            }
            if error is CancellationError, rollbackFailure == nil {
                return false
            }
            settingsFailure = rollbackFailure ?? error.localizedDescription
            return false
        }

        await airAndSpaceRuntime.deactivate(reporting: .idle)
        activePollingSignature = nil
        setupState = replacementSetupState
        projectionPlaylist = preferences.playlist
        await configureExperienceCoordinator(with: projectionPlaylist)

        if let replacementCredential = draft.replacementCredential {
            switch draft.configuration.kind {
                case .adsbExchangeRapidAPI:
                    rapidAPICredentialState = .saved(lastFour: replacementCredential.lastFour)
                case .flightradar24:
                    invalidateFlightradar24Usage()
                    flightradar24CredentialState = .saved(
                        lastFour: replacementCredential.lastFour,
                    )
                case .adsbLol, .readsb:
                    break
            }
        }

        settingsFailure = nil
        do {
            try await discardOldFrame()
        } catch is CancellationError {
            await clearProjectionState(restartsGeography: true)
        } catch {
            settingsFailure = error.localizedDescription
            await clearProjectionState(restartsGeography: true)
        }
        scheduleDemandReconciliation()
        return true
    }

    @discardableResult
    public func deleteRapidAPICredential() async -> Bool {
        guard sourceMutationInProgress == false else { return false }
        sourceMutationInProgress = true
        defer { finishSourceMutation() }

        let deletesActiveSource = selectedSourceConfiguration?.kind == .adsbExchangeRapidAPI
        do {
            try await credentialStore.delete(.rapidAPI)
        } catch is CancellationError {
            return false
        } catch {
            settingsFailure = error.localizedDescription
            return false
        }
        rapidAPICredentialState = .missing
        if deletesActiveSource {
            await airAndSpaceRuntime.deactivate(reporting: .failed(.missingCredential))
            activePollingSignature = nil
            await clearProjectionState(restartsGeography: true)
            feedHealth = .failed(.missingCredential)
        }
        settingsFailure = nil
        return true
    }

    @discardableResult
    public func deleteFlightradar24Credential() async -> Bool {
        guard sourceMutationInProgress == false else { return false }
        sourceMutationInProgress = true
        defer { finishSourceMutation() }

        let deletesActiveSource = selectedSourceConfiguration?.kind == .flightradar24
        do {
            try await credentialStore.delete(.flightradar24)
        } catch is CancellationError {
            return false
        } catch {
            settingsFailure = error.localizedDescription
            return false
        }
        invalidateFlightradar24Usage()
        flightradar24CredentialState = .missing
        if deletesActiveSource {
            await airAndSpaceRuntime.deactivate(reporting: .failed(.missingCredential))
            activePollingSignature = nil
            await clearProjectionState(restartsGeography: true)
            feedHealth = .failed(.missingCredential)
        }
        settingsFailure = nil
        return true
    }

    private func restoreCredential(
        _ credential: AircraftCredential?,
        for id: AircraftCredentialID,
    ) async -> String? {
        do {
            if let credential {
                try await credentialStore.save(credential, for: id)
            } else {
                try await credentialStore.delete(id)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func finishSourceMutation() {
        sourceMutationInProgress = false
        guard sourceMutationNeedsPreferenceSave else { return }
        sourceMutationNeedsPreferenceSave = false
        schedulePreferencesSave()
    }

    func applyAirAndSpaceUpdate(_ update: AirAndSpaceRuntimeUpdate) async {
        guard update.activationGeneration == airAndSpaceActivationGeneration else { return }
        semanticFramesByExperience[.airAndSpace] = update.experienceFrame
        activePollingSignature = update.activePollingSignature
        await experienceCoordinator.reportRuntimeUpdate(
            id: .airAndSpace,
            generation: update.activationGeneration,
            successfulGeneration: update.successfulActivationGeneration,
            health: update.health,
        )
        let activationGeneration = update.activationGeneration
        let semanticFrame = update.experienceFrame
        let awaitsPreparation = await experienceCoordinator.isAwaitingPreparation(
            id: .airAndSpace,
            generation: activationGeneration,
        )
        let preparesHiddenExperience = update.successfulActivationGeneration ==
            activationGeneration && awaitsPreparation
        if preparesHiddenExperience {
            do {
                let output = try await projectedOutput(
                    for: semanticFrame,
                    generatedAt: dateProvider.now(),
                )
                guard airAndSpaceActivationGeneration == activationGeneration,
                      semanticFramesByExperience[.airAndSpace] == semanticFrame,
                      await experienceCoordinator.isAwaitingPreparation(
                          id: .airAndSpace,
                          generation: activationGeneration,
                      )
                else { return }
                preparedOutputsByExperience[.airAndSpace] = PreparedProjectionExperience(
                    experienceID: .airAndSpace,
                    activationGeneration: activationGeneration,
                    semanticFrame: semanticFrame,
                    output: output,
                )
                let accepted = await experienceCoordinator.reportRuntimePrepared(
                    id: .airAndSpace,
                    generation: activationGeneration,
                )
                if accepted == false,
                   preparedOutputsByExperience[.airAndSpace]?.activationGeneration ==
                   activationGeneration
                {
                    preparedOutputsByExperience.removeValue(forKey: .airAndSpace)
                }
            } catch is CancellationError {
                return
            } catch {
                await experienceCoordinator.reportRuntimeUpdate(
                    id: .airAndSpace,
                    generation: update.activationGeneration,
                    successfulGeneration: nil,
                    health: .failed(.decoding),
                )
                return
            }
        }
        guard activeExperienceID == .airAndSpace else { return }
        let previousLayer = currentLayerFrame
        currentSnapshot = update.snapshot
        currentLayerFrame = update.layerFrame
        currentExperienceFrame = update.experienceFrame
        feedHealth = update.health

        if update.layerFrame != nil {
            restartRenderer()
        } else if previousLayer != nil || update.health.visibleContentCount == 0 {
            await clearProjectionState(restartsGeography: true)
            feedHealth = update.health
        }
    }

    func scheduleDemandReconciliation() {
        demandGeneration &+= 1
        let generation = demandGeneration
        demandTask?.cancel()
        demandTask = Task(name: "Throw reconcile output demand") { [weak self] in
            guard let self else { return }
            await reconcileDemand(generation: generation)
        }
    }

    func reconcileDemand(generation: UInt64) async {
        isReconcilingDemand = true
        defer { isReconcilingDemand = false }
        guard generation == demandGeneration else { return }
        expireTemporaryWakeIfNeeded()
        scheduleQuietBoundary()
        let quiet = isQuietNow
        await reconcileExperienceDemand(isQuiet: quiet)
        guard generation == demandGeneration else { return }
        let hasEnabledLayer = flightsEnabled || (geographyEnabled && projectionMode == .map)
        guard hasStarted,
              isForeground,
              outputDemands.isEmpty == false,
              isCalibrating == false,
              hasEnabledLayer,
              quiet == false
        else {
            cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: true)
            activePollingSignature = nil
            await airAndSpaceRuntime.deactivate(reporting: quiet ? .quiet : .idle)
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = quiet ? .quiet : .idle
            return
        }

        if locationMode == .gps {
            await prepareProjectionSessionGPSLocation()
            guard generation == demandGeneration else { return }
            guard case .ready = projectionSessionLocationGate else {
                activePollingSignature = nil
                await airAndSpaceRuntime.deactivate(reporting: .failed(.locationUnavailable))
                guard generation == demandGeneration else { return }
                await clearProjectionState(restartsGeography: true)
                guard generation == demandGeneration else { return }
                feedHealth = .failed(.locationUnavailable)
                return
            }
        }

        guard flightsEnabled else {
            activePollingSignature = nil
            await airAndSpaceRuntime.deactivate(reporting: .idle)
            guard generation == demandGeneration else { return }
            currentSnapshot = nil
            currentLayerFrame = nil
            currentExperienceFrame = .airAndSpace(.empty)
            feedHealth = .idle
            restartRenderer()
            return
        }

        guard let configuration = aircraftSourceSelection.configuredSource else {
            activePollingSignature = nil
            await airAndSpaceRuntime.deactivate(reporting: .failed(.sourceNotValidated))
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.sourceNotValidated)
            return
        }
        if configuration.kind == .adsbExchangeRapidAPI, rapidAPICredentialState == .missing {
            activePollingSignature = nil
            await airAndSpaceRuntime.deactivate(reporting: .failed(.missingCredential))
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.missingCredential)
            return
        }
        if configuration.kind == .flightradar24, flightradar24CredentialState == .missing {
            activePollingSignature = nil
            await airAndSpaceRuntime.deactivate(reporting: .failed(.missingCredential))
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.missingCredential)
            return
        }

        let query: AircraftQuery
        do {
            query = try aircraftQuery()
        } catch {
            activePollingSignature = nil
            await airAndSpaceRuntime.deactivate(reporting: .failed(.locationUnavailable))
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.locationUnavailable)
            return
        }
        let signature = PollingSignature(configuration: configuration, query: query)
        if activePollingSignature == signature {
            restartRenderer()
            return
        }
        activePollingSignature = signature
        await airAndSpaceRuntime.activate(
            configuration: configuration,
            query: query,
            labelMode: labelMode,
            activationGeneration: airAndSpaceActivationGeneration,
        )
        guard generation == demandGeneration else { return }
        restartRenderer()
    }

    func restartRenderer() {
        renderGeneration &+= 1
        let generation = renderGeneration
        renderTask?.cancel()
        guard outputDemands.isEmpty == false,
              isForeground,
              isCalibrating == false,
              isQuietNow == false,
              currentLayerFrame != nil || (geographyEnabled && projectionMode == .map),
              confirmedLocation != nil
        else {
            return
        }
        renderTask = Task(name: "Throw projection 30Hz") { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var schedule = ProjectionFrameSchedule(startingAt: clock.now)
            while Task.isCancelled == false {
                do {
                    let activationGeneration = airAndSpaceActivationGeneration
                    let experienceFrame = currentExperienceFrame
                    let output = try await projectedOutput(
                        for: experienceFrame,
                        generatedAt: dateProvider.now(),
                    )
                    try Task.checkCancellation()
                    guard generation == renderGeneration else { return }
                    projectionFrame = output.frame
                    projectionMarkEffects = output.effects
                    observerMapPoint = output.observerPoint
                    geographyLayerHealth = output.geographyHealth
                    await updateVisibleCount(
                        output.frame.visibleAircraftCount,
                        experienceID: output.frame.experienceID,
                        activationGeneration: activationGeneration,
                    )
                    guard generation == renderGeneration else { return }
                    if currentLayerFrame == nil {
                        renderTask = nil
                        return
                    }
                    let deadline = schedule.advance(past: clock.now)
                    try await clock.sleep(until: deadline)
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == renderGeneration else { return }
                    feedHealth = .failed(.decoding)
                    await clearProjectionState(restartsGeography: false)
                    return
                }
            }
        }
    }

    func projectedOutput(
        for experienceFrame: ProjectionExperienceFrame,
        generatedAt: Date,
    ) async throws -> ProjectionFrameWorkerOutput {
        guard let confirmedLocation else {
            throw ThrowValidationError.invalidPreferencePayload
        }
        let input = try projectionInput(for: experienceFrame)
        return try await projectionWorker.frame(
            input: input,
            observer: confirmedLocation.position,
            mapCenter: activeMapCenter,
            calibration: projectionCalibration(),
            generatedAt: generatedAt,
            reduceMotion: reduceMotion,
        )
    }

    private func projectionInput(
        for experienceFrame: ProjectionExperienceFrame,
    ) throws -> ProjectionExperienceInput {
        switch experienceFrame {
            case let .airAndSpace(frame):
                let enabledFrame = AirAndSpaceExperienceFrame(
                    geography: projectionMode == .map && geographyEnabled
                        ? frame.geography
                        : nil,
                    flights: flightsEnabled ? frame.flights : nil,
                    stars: frame.stars,
                    satellites: frame.satellites,
                )
                let viewport: AirAndSpaceProjectionViewport = switch projectionMode {
                    case .map:
                        try .map(
                            viewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
                            geography: geographyEnabled ? .visible : .hidden,
                        )
                    case .trueSky:
                        try .trueSky(viewport: SkyViewport(
                            minimumElevation: ElevationAngle(degrees: minimumElevation),
                        ))
                }
                return .airAndSpace(frame: enabledFrame, viewport: viewport)
            case let .transit(frame):
                let enabledFrame = TransitExperienceFrame(
                    geography: geographyEnabled ? frame.geography : nil,
                    network: frame.network,
                    vehicles: frame.vehicles,
                )
                return try .transit(
                    frame: enabledFrame,
                    viewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
                    geography: geographyEnabled ? .visible : .hidden,
                )
        }
    }

    func stopRenderer() {
        renderGeneration &+= 1
        renderTask?.cancel()
        renderTask = nil
    }

    func clearProjectionState(restartsGeography: Bool) async {
        currentSnapshot = nil
        currentLayerFrame = nil
        observerMapPoint = nil
        currentExperienceFrame = .empty(for: activeExperienceID ?? .airAndSpace)
        stopRenderer()
        projectionFrame = emptyProjectionFrame()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            projectionMarkOpacity = 1
        }
        await projectionWorker.reset()
        if restartsGeography, geographyEnabled, projectionMode == .map {
            restartRenderer()
        }
    }

    func rebuildCurrentLayerFrame() {
        guard let currentSnapshot else { return }
        Task(name: "Throw rebuild flight labels") { [weak self] in
            guard let self else { return }
            await airAndSpaceRuntime.refreshPresentation(labelMode: labelMode)
        }
    }

    func updateVisibleCount(
        _ count: Int,
        experienceID: ProjectionExperienceID,
        activationGeneration: UInt64,
    ) async {
        guard experienceID == .airAndSpace else { return }
        await airAndSpaceRuntime.updateVisibleContentCount(
            count,
            activationGeneration: activationGeneration,
        )
    }

    func sourceConfiguration(
        choice: AircraftSourceChoice,
        readsbURL: String,
        pollingIntervalSeconds: Int,
    ) throws -> AircraftSourceConfiguration {
        switch choice {
            case .adsbLol:
                return .adsbLol
            case .readsb:
                guard let url = URL(string: readsbURL) else {
                    throw AircraftSourceFailure.invalidConfiguration
                }
                return try .readsb(ReadsbConfiguration(aircraftJSONURL: url))
            case .adsbExchange:
                return try .adsbExchangeRapidAPI(
                    ADSBExchangeConfiguration(
                        pollingInterval: PollingInterval(seconds: pollingIntervalSeconds),
                    ),
                )
            case .flightradar24:
                return try .flightradar24(
                    Flightradar24Configuration(
                        pollingInterval: PollingInterval(seconds: pollingIntervalSeconds),
                    ),
                )
        }
    }

    func validationQuery() throws -> AircraftQuery {
        guard let confirmedLocation else { throw AircraftSourceFailure.invalidConfiguration }
        return try AircraftQuery(
            observer: confirmedLocation.position,
            center: confirmedLocation.position.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 5))),
            includeGroundAircraft: false,
        )
    }

    func aircraftQuery() throws -> AircraftQuery {
        guard let confirmedLocation else { throw AircraftSourceFailure.invalidConfiguration }
        return try AircraftQuery(
            observer: confirmedLocation.position,
            center: projectionMode == .map
                ? activeMapCenter
                : confirmedLocation.position.coordinate,
            viewport: projectionViewport(),
            includeGroundAircraft: projectionMode == .map && includeGroundAircraft,
        )
    }

    func projectionViewport() throws -> ProjectionViewport {
        switch projectionMode {
            case .map:
                try .map(MapViewport(radius: NauticalMiles(value: mapRadius)))
            case .trueSky:
                try .trueSky(
                    SkyViewport(
                        minimumElevation: ElevationAngle(degrees: minimumElevation),
                    ),
                )
        }
    }

    func projectionCalibration() throws -> ProjectionCalibration {
        try ProjectionCalibration(
            screenTopBearing: Bearing(degrees: screenTopBearing),
            rotation: screenRotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            safeInsetFraction: safeInsetPercent / 100,
            verifiedOnExternalDisplay: calibrationVerified,
        )
    }

    func emptyProjectionFrame() -> ProjectionFrame {
        ProjectionFrame(
            experienceID: activeExperienceID ?? .airAndSpace,
            mode: projectionMode,
            generatedAt: dateProvider.now(),
            layers: [],
        )
    }

    func projectionFrameWithoutMarks() -> ProjectionFrame {
        let withoutMarks = projectionFrame.replacingMarks([])
        return ProjectionFrame(
            experienceID: projectionFrame.experienceID,
            mode: projectionFrame.mode,
            generatedAt: dateProvider.now(),
            layers: withoutMarks.layers,
        )
    }

    func discardOldFrame() async throws {
        currentSnapshot = nil
        currentLayerFrame = nil
        currentExperienceFrame = .empty(for: activeExperienceID ?? .airAndSpace)
        stopRenderer()
        let empty = projectionFrameWithoutMarks()
        if reduceMotion {
            projectionFrame = empty
            await projectionWorker.reset()
        } else {
            withAnimation(.linear(duration: 0.25)) {
                projectionMarkOpacity = 0
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch is CancellationError {
                projectionFrame = empty
                projectionMarkOpacity = 1
                await projectionWorker.reset()
                throw CancellationError()
            } catch {
                projectionFrame = empty
                projectionMarkOpacity = 1
                await projectionWorker.reset()
                throw error
            }
            projectionFrame = empty
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                projectionMarkOpacity = 1
            }
            await projectionWorker.reset()
        }
    }
}
