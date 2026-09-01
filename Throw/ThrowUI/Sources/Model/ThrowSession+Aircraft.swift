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

    func adsbExchangeUsageEstimate(intervalSeconds: Int) -> ADSBExchangeUsageEstimate {
        do {
            return try ADSBExchangeUsageEstimator.estimate(
                pollingInterval: PollingInterval(seconds: intervalSeconds),
                quietSchedule: quietSchedule,
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
            return try Flightradar24CreditEstimator.estimate(
                report: report,
                pollingInterval: PollingInterval(seconds: intervalSeconds),
                quietSchedule: quietSchedule,
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
        let report: Flightradar24UsageReport
        do {
            report = try await sourceService.flightradar24Usage(period: .last24Hours)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logPostLaunchFailure(at: .aircraftSource, error: error)
            throw error
        }
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
        do {
            let draft = try sourceValidationDraft(
                choice: choice,
                readsbURL: readsbURL,
                rapidAPIKey: rapidAPIKey,
                pollingIntervalSeconds: pollingIntervalSeconds,
            )
            return await testSource(draft)
        } catch is CancellationError {
            return .cancelled
        } catch let failure as AircraftSourceFailure {
            logPostLaunchFailure(at: .aircraftSource, error: failure)
            return .failed(failure.presentationCategory)
        } catch {
            logPostLaunchFailure(at: .aircraftSource, error: error)
            return .failed(.sourceNotValidated)
        }
    }

    func testSource(
        _ draft: AircraftSourceValidationDraft,
    ) async -> AircraftSourceValidationOutcome {
        do {
            let query = try validationQuery()
            _ = try await sourceService.testConnection(
                request: AircraftSourceValidationRequest(draft: draft, query: query),
            )
            try Task.checkCancellation()
            return .succeeded(ValidatedAircraftSourceDraft(source: draft))
        } catch is CancellationError {
            return .cancelled
        } catch let failure as AircraftSourceFailure {
            logPostLaunchFailure(at: .aircraftSource, error: failure)
            return .failed(failure.presentationCategory)
        } catch {
            logPostLaunchFailure(at: .aircraftSource, error: error)
            return .failed(.sourceNotValidated)
        }
    }

    @discardableResult
    func useSource(_ draft: ValidatedAircraftSourceDraft) async -> Bool {
        guard beginPreferenceMutation() else { return false }
        defer { finishPreferenceMutation() }

        await flushPreferencesSave()

        do {
            let base = preferenceSnapshot
            _ = try makePreferences(
                setupState: base.setupState.replacingSource(draft.configuration),
                globalPreferences: base.globalPreferences,
                airAndSpacePreferences: base.airAndSpacePreferences,
                projectionPlaylist: base.projectionPlaylist,
            )
        } catch {
            recordPostLaunchFailure(.aircraftSource, error: error)
            return false
        }

        let credentialReplacement = draft.credentialReplacement
        var previousCredential: AircraftCredential?
        var credentialMutationAttempted = false
        if let replacement = credentialReplacement {
            do {
                previousCredential = try await credentialStore.credential(for: replacement.id)
                try Task.checkCancellation()
                credentialMutationAttempted = true
                try await credentialStore.save(replacement.credential, for: replacement.id)
                try Task.checkCancellation()
            } catch is CancellationError {
                if credentialMutationAttempted {
                    await restoreCredentialAfterFailedSourceChange(
                        previousCredential,
                        for: replacement.id,
                    )
                }
                return false
            } catch {
                recordPostLaunchFailure(credentialFailure(for: replacement.id), error: error)
                if credentialMutationAttempted {
                    await restoreCredentialAfterFailedSourceChange(
                        previousCredential,
                        for: replacement.id,
                    )
                }
                return false
            }
        }

        let persistence = await persistReconciledPreferenceMutation(
            failure: .aircraftSource,
            makeMutation: { base in
                ThrowPreferenceMutation(
                    snapshot: base.replacingSetupState(
                        base.setupState.replacingSource(draft.configuration),
                    ),
                    publication: credentialReplacement,
                )
            },
            prepareForPublication: {
                self.prepareProjectionPreferencePublication(.aircraftSource)
            },
            publish: { replacement in
                guard let replacement else { return }
                switch replacement.id {
                    case .rapidAPI:
                        self.rapidAPICredentialState = .saved(
                            lastFour: replacement.credential.lastFour,
                        )
                    case .flightradar24:
                        self.invalidateFlightradar24Usage()
                        self.flightradar24CredentialState = .saved(
                            lastFour: replacement.credential.lastFour,
                        )
                }
                self.resolvePostLaunchFailure(
                    self.credentialFailure(for: replacement.id).owner,
                )
            },
        )
        let invalidation: ProjectionPreferenceInvalidation
        switch persistence {
            case .notCommitted:
                if credentialMutationAttempted, let replacement = credentialReplacement {
                    await restoreCredentialAfterFailedSourceChange(
                        previousCredential,
                        for: replacement.id,
                    )
                }
                return false
            case let .committed(committedInvalidation):
                invalidation = committedInvalidation
        }

        await finishProjectionPreferenceInvalidation(invalidation)
        await configureExperienceCoordinator(with: projectionPlaylist)

        do {
            try await discardOldFrame()
        } catch is CancellationError {
            await clearProjectionState(restartsGeography: true)
        } catch {
            recordPostLaunchFailure(.projectionRendering, error: error)
            await clearProjectionState(restartsGeography: true)
        }
        completeProjectionPreferenceInvalidation(invalidation)
        scheduleDemandReconciliation()
        return true
    }

    @discardableResult
    public func deleteRapidAPICredential() async -> Bool {
        guard beginPreferenceMutation() else { return false }
        defer { finishPreferenceMutation() }

        let deletesActiveSource = selectedSourceConfiguration?.kind == .adsbExchangeRapidAPI
        do {
            try await credentialStore.delete(.rapidAPI)
        } catch is CancellationError {
            return false
        } catch {
            recordPostLaunchFailure(.rapidAPICredential, error: error)
            return false
        }
        rapidAPICredentialState = .missing
        if deletesActiveSource {
            await deactivateAirAndSpace(reporting: .failed(.missingCredential))
            activePollingSignature = nil
            await clearProjectionState(restartsGeography: true)
            feedHealth = .failed(.missingCredential)
        }
        resolvePostLaunchFailure(.rapidAPICredential)
        return true
    }

    @discardableResult
    public func deleteFlightradar24Credential() async -> Bool {
        guard beginPreferenceMutation() else { return false }
        defer { finishPreferenceMutation() }

        let deletesActiveSource = selectedSourceConfiguration?.kind == .flightradar24
        do {
            try await credentialStore.delete(.flightradar24)
        } catch is CancellationError {
            return false
        } catch {
            recordPostLaunchFailure(.flightradar24Credential, error: error)
            return false
        }
        invalidateFlightradar24Usage()
        flightradar24CredentialState = .missing
        if deletesActiveSource {
            await deactivateAirAndSpace(reporting: .failed(.missingCredential))
            activePollingSignature = nil
            await clearProjectionState(restartsGeography: true)
            feedHealth = .failed(.missingCredential)
        }
        resolvePostLaunchFailure(.flightradar24Credential)
        return true
    }

    private func restoreCredentialAfterFailedSourceChange(
        _ credential: AircraftCredential?,
        for id: AircraftCredentialID,
    ) async {
        do {
            if let credential {
                try await credentialStore.save(credential, for: id)
            } else {
                try await credentialStore.delete(id)
            }
        } catch {
            recordPostLaunchFailure(credentialFailure(for: id), error: error)
        }
    }

    func applyAirAndSpaceUpdate(_ update: AirAndSpaceRuntimeUpdate) async {
        guard update.activationLease == airAndSpaceActivation.activeLease else { return }
        switch update.semanticPreparationState {
            case .ready:
                break
            case .failed:
                publishPostLaunchFailure(.projectionPreparation)
        }
        var preparationSucceeded = update.semanticPreparationState == .ready
        guard case let .airAndSpace(airAndSpaceFrame) = update.experienceFrame else {
            assertionFailure("The Air & Space runtime produced a different View")
            return
        }
        replacePendingAirAndSpaceFrame(airAndSpaceFrame)
        activePollingSignature = update.activePollingSignature
        let semanticFrame = ProjectionExperienceFrame.airAndSpace(airAndSpaceFrame)
        if let activationLease = update.activationLease {
            await experienceCoordinator.reportRuntimeUpdate(
                lease: activationLease,
                successfulLease: update.successfulActivationLease,
                health: update.health,
            )
            let awaitsPreparation = await experienceCoordinator.isAwaitingPreparation(
                activationLease,
            )
            let preparesHiddenExperience = update.successfulActivationLease ==
                activationLease && awaitsPreparation
            if preparesHiddenExperience {
                do {
                    let output = try await projectedOutput(
                        for: semanticFrame,
                        generatedAt: dateProvider.now(),
                        revision: projectionInputRevision,
                        loggingOperation: .projectionPreparation,
                    )
                    guard let currentRequest = try? projectionRequest(
                        for: .airAndSpace(pendingAirAndSpaceFrame),
                        generatedAt: output.request.generatedAt,
                        revision: projectionInputRevision,
                        loggingOperation: .projectionPreparation,
                    ) else { return }
                    guard airAndSpaceActivation.activeLease == activationLease,
                          output.request == currentRequest,
                          await experienceCoordinator.isAwaitingPreparation(activationLease)
                    else { return }
                    guard let prepared = VisibleProjection.rendered(
                        activationLease: activationLease,
                        output: output,
                    ) else {
                        assertionFailure("A worker output must match its activation lease")
                        return
                    }
                    preparedProjection = prepared
                    let accepted = await experienceCoordinator.reportRuntimePrepared(
                        activationLease,
                    )
                    if accepted == false,
                       preparedProjection?.activationLease == activationLease
                    {
                        preparedProjection = nil
                    }
                    preparationSucceeded = preparationSucceeded && accepted
                } catch is CancellationError {
                    return
                } catch {
                    recordPostLaunchFailure(.projectionPreparation, error: error)
                    await experienceCoordinator.reportRuntimeUpdate(
                        lease: activationLease,
                        successfulLease: nil,
                        health: .failed(.decoding),
                    )
                    return
                }
            }
        }
        if preparationSucceeded {
            resolvePostLaunchFailure(.projectionPreparation)
        }
        if let transition = projectionPresentationTransition {
            projectionPresentationTransition = transition.buffering(update)
            return
        }
        await publishVisibleAirAndSpaceUpdate(update)
    }

    func publishVisibleAirAndSpaceUpdate(_ update: AirAndSpaceRuntimeUpdate) async {
        guard update.activationLease == airAndSpaceActivation.activeLease,
              activeExperienceID == .airAndSpace
        else { return }
        let previousLayer: ProjectionLayerFrame<FlightsLayerKind>? = switch visibleProjection
            .semanticFrame
        {
            case let .airAndSpace(frame): frame.flights
            case .transit, nil: nil
        }
        currentSnapshot = update.snapshot
        feedHealth = update.health

        if update.flightsFrame != nil {
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
        guard projectionPreferenceInvalidation == nil else {
            demandTask = nil
            return
        }
        demandTask = Task(name: "Throw reconcile output demand") { [weak self] in
            guard let self else { return }
            await reconcileDemand(generation: generation)
        }
    }

    func prepareProjectionPreferencePublication(
        _ change: ProjectionPreferenceChange,
    ) -> ProjectionPreferenceInvalidation {
        precondition(
            projectionPreferenceInvalidation == nil,
            "A projection preference invalidation is already active",
        )
        demandGeneration &+= 1
        demandTask?.cancel()
        let activationLease = airAndSpaceActivation.activeLease
        let invalidation = ProjectionPreferenceInvalidation(
            change: change,
            activationLease: activationLease,
        )
        projectionPreferenceInvalidation = invalidation
        if let activationLease {
            _ = airAndSpaceActivation.deactivate(activationLease)
        }
        activePollingSignature = nil
        if change == .observerLocation {
            clearProjectionStateSynchronously()
        } else {
            stopRenderer()
        }
        return invalidation
    }

    func finishProjectionPreferenceInvalidation(
        _ invalidation: ProjectionPreferenceInvalidation,
    ) async {
        if let activationLease = invalidation.activationLease {
            #if DEBUG
                await beforeProjectionPreferenceRuntimeDeactivationForTesting?()
            #endif
            await airAndSpaceRuntime.deactivate(
                lease: activationLease,
                reporting: .idle,
            )
        }
        if invalidation.change == .observerLocation {
            await projectionWorker.reset()
        }
    }

    func completeProjectionPreferenceInvalidation(
        _ invalidation: ProjectionPreferenceInvalidation,
    ) {
        guard projectionPreferenceInvalidation == invalidation else {
            assertionFailure("A projection preference invalidation completed out of order")
            return
        }
        projectionPreferenceInvalidation = nil
    }

    func deactivateAirAndSpace(reporting health: FeedHealth) async {
        guard let activationLease = airAndSpaceActivation.activeLease else { return }
        await airAndSpaceRuntime.deactivate(lease: activationLease, reporting: health)
    }

    func reconcileDemand(generation: UInt64) async {
        isReconcilingDemand = true
        defer { isReconcilingDemand = false }
        guard generation == demandGeneration,
              projectionPreferenceInvalidation == nil
        else { return }
        expireTemporaryWakeIfNeeded()
        scheduleQuietBoundary()
        let quiet = isQuietNow
        await reconcileExperienceDemand(isQuiet: quiet)
        guard generation == demandGeneration else { return }
        let hasEnabledLayer = flightsEnabled || (geographyEnabled && projectionMode == .map)
        guard launchState.isOperational,
              hasForegroundControllerScene,
              outputDemands.isEmpty == false,
              isCalibrating == false,
              hasEnabledLayer,
              quiet == false
        else {
            cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: true)
            activePollingSignature = nil
            await deactivateAirAndSpace(reporting: quiet ? .quiet : .idle)
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
                await deactivateAirAndSpace(reporting: .failed(.locationUnavailable))
                guard generation == demandGeneration else { return }
                await clearProjectionState(restartsGeography: true)
                guard generation == demandGeneration else { return }
                feedHealth = .failed(.locationUnavailable)
                return
            }
        }

        guard flightsEnabled else {
            activePollingSignature = nil
            await deactivateAirAndSpace(reporting: .idle)
            guard generation == demandGeneration else { return }
            currentSnapshot = nil
            replacePendingAirAndSpaceFrame(.empty)
            feedHealth = .idle
            restartRenderer()
            return
        }

        guard let configuration = aircraftSourceSelection.configuredSource else {
            activePollingSignature = nil
            await deactivateAirAndSpace(reporting: .failed(.sourceNotValidated))
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.sourceNotValidated)
            return
        }
        if configuration.kind == .adsbExchangeRapidAPI, rapidAPICredentialState == .missing {
            activePollingSignature = nil
            await deactivateAirAndSpace(reporting: .failed(.missingCredential))
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.missingCredential)
            return
        }
        if configuration.kind == .flightradar24, flightradar24CredentialState == .missing {
            activePollingSignature = nil
            await deactivateAirAndSpace(reporting: .failed(.missingCredential))
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
            logPostLaunchFailure(at: .location, error: error)
            activePollingSignature = nil
            await deactivateAirAndSpace(reporting: .failed(.locationUnavailable))
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
        guard let activationLease = airAndSpaceActivation.activeLease else {
            assertionFailure("Air & Space demand reconciled without a coordinator lease")
            activePollingSignature = nil
            return
        }
        await airAndSpaceRuntime.activate(
            configuration: configuration,
            query: query,
            labelMode: labelMode,
            lease: activationLease,
        )
        guard generation == demandGeneration else { return }
        restartRenderer()
    }

    func restartRenderer() {
        projectionInputRevision = projectionInputRevision.successor()
        renderGeneration &+= 1
        let generation = renderGeneration
        renderTask?.cancel()
        guard projectionPresentationTransition == nil,
              projectionPreferenceInvalidation == nil,
              activeExperienceID == .airAndSpace,
              outputDemands.isEmpty == false,
              hasForegroundControllerScene,
              isCalibrating == false,
              isQuietNow == false,
              pendingAirAndSpaceFrame.flights != nil ||
              (geographyEnabled && projectionMode == .map),
              confirmedLocation != nil,
              let activationLease = airAndSpaceActivation.activeLease
        else {
            return
        }
        renderTask = Task(name: "Throw projection 30Hz") { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var schedule = ProjectionFrameSchedule(startingAt: clock.now)
            while Task.isCancelled == false {
                do {
                    let experienceFrame = ProjectionExperienceFrame.airAndSpace(
                        pendingAirAndSpaceFrame,
                    )
                    let output = try await projectedOutput(
                        for: experienceFrame,
                        generatedAt: dateProvider.now(),
                        revision: projectionInputRevision,
                        loggingOperation: .projectionRendering,
                    )
                    try Task.checkCancellation()
                    #if DEBUG
                        await beforePublishingProjectionForTesting?()
                    #endif
                    guard generation == renderGeneration else { return }
                    guard publishCurrentAirAndSpaceOutput(
                        output,
                        activationLease: activationLease,
                    ) else {
                        return
                    }
                    resolvePostLaunchFailure(.projectionRendering)
                    await updateVisibleCount(
                        output.frame.visibleAircraftCount,
                        experienceID: output.frame.experienceID,
                        activationLease: activationLease,
                    )
                    guard generation == renderGeneration else { return }
                    if pendingAirAndSpaceFrame.flights == nil {
                        renderTask = nil
                        return
                    }
                    let deadline = schedule.advance(past: clock.now)
                    try await clock.sleep(until: deadline)
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == renderGeneration else { return }
                    recordPostLaunchFailure(.projectionRendering, error: error)
                    feedHealth = .failed(.decoding)
                    renderTask = nil
                    return
                }
            }
        }
    }

    func projectedOutput(
        for experienceFrame: ProjectionExperienceFrame,
        generatedAt: Date,
        revision: ProjectionFrameRequest.Revision,
        loggingOperation: ThrowSessionLogEvent.PostLaunchOperation,
    ) async throws -> ProjectionFrameWorkerOutput {
        let request = try projectionRequest(
            for: experienceFrame,
            generatedAt: generatedAt,
            revision: revision,
            loggingOperation: loggingOperation,
        )
        return try await projectionWorker.frame(request: request)
    }

    func projectionRequest(
        for experienceFrame: ProjectionExperienceFrame,
        generatedAt: Date,
        revision: ProjectionFrameRequest.Revision,
        loggingOperation: ThrowSessionLogEvent.PostLaunchOperation,
    ) throws -> ProjectionFrameRequest {
        guard let confirmedLocation else {
            throw ThrowValidationError.invalidPreferencePayload
        }
        let context = ProjectionFrameRequest.Context(
            observer: confirmedLocation.position,
            mapCenter: activeMapCenter,
            calibration: projectionCalibration,
            reduceMotion: reduceMotion,
            loggingOperation: loggingOperation,
        )
        switch try projectionInput(for: experienceFrame) {
            case let .airAndSpace(input):
                return .airAndSpace(.init(
                    input: input,
                    context: context,
                    generatedAt: generatedAt,
                    revision: revision,
                ))
            case let .transit(input):
                return .transit(.init(
                    input: input,
                    context: context,
                    generatedAt: generatedAt,
                    revision: revision,
                ))
        }
    }

    @discardableResult
    private func publishCurrentAirAndSpaceOutput(
        _ output: ProjectionFrameWorkerOutput,
        activationLease: ProjectionActivationLease,
    ) -> Bool {
        guard case .airAndSpace = output,
              activationLease == airAndSpaceActivation.activeLease,
              let currentRequest = try? projectionRequest(
                  for: .airAndSpace(pendingAirAndSpaceFrame),
                  generatedAt: output.request.generatedAt,
                  revision: projectionInputRevision,
                  loggingOperation: .projectionRendering,
              ), output.request == currentRequest
        else { return false }
        guard let visible = VisibleProjection.rendered(
            activationLease: activationLease,
            output: output,
        ), let presentation = projectionPresentationState.replacingVisible(visible)
        else {
            assertionFailure("A renderer publication must match the active View")
            return false
        }
        projectionPresentationState = presentation
        return true
    }

    func replacePendingAirAndSpaceFrame(_ frame: AirAndSpaceExperienceFrame) {
        guard pendingAirAndSpaceFrame != frame else { return }
        pendingAirAndSpaceFrame = frame
        projectionInputRevision = projectionInputRevision.successor()
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
                        .map(
                            viewport: airAndSpacePreferences.mapViewport,
                            geography: geographyEnabled ? .visible : .hidden,
                        )
                    case .trueSky:
                        .trueSky(viewport: airAndSpacePreferences.skyViewport)
                }
                return .airAndSpace(AirAndSpaceProjectionInput(
                    frame: enabledFrame,
                    viewport: viewport,
                ))
            case let .transit(frame):
                let enabledFrame = TransitExperienceFrame(
                    geography: geographyEnabled ? frame.geography : nil,
                    network: frame.network,
                    vehicles: frame.vehicles,
                )
                return .transit(TransitProjectionInput(
                    frame: enabledFrame,
                    viewport: airAndSpacePreferences.mapViewport,
                    geography: geographyEnabled ? .visible : .hidden,
                ))
        }
    }

    func stopRenderer() {
        renderGeneration &+= 1
        renderTask?.cancel()
        renderTask = nil
    }

    func clearProjectionState(restartsGeography: Bool) async {
        clearProjectionStateSynchronously()
        await projectionWorker.reset()
        if restartsGeography, geographyEnabled, projectionMode == .map {
            restartRenderer()
        }
    }

    private func clearProjectionStateSynchronously() {
        currentSnapshot = nil
        replacePendingAirAndSpaceFrame(.empty)
        stopRenderer()
        let visible = visibleProjection.cleared(
            mode: projectionMode,
            generatedAt: dateProvider.now(),
        )
        guard let presentation = projectionPresentationState.replacingVisible(visible) else {
            assertionFailure("Clearing a projection must preserve its visible identity")
            return
        }
        projectionPresentationState = presentation
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            projectionMarkOpacity = 1
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
        activationLease: ProjectionActivationLease,
    ) async {
        guard experienceID == activationLease.experienceID else { return }
        await airAndSpaceRuntime.updateVisibleContentCount(
            count,
            lease: activationLease,
        )
    }

    func sourceValidationDraft(
        choice: AircraftSourceChoice,
        readsbURL: String,
        rapidAPIKey: String,
        pollingIntervalSeconds: Int,
    ) throws -> AircraftSourceValidationDraft {
        func replacementCredential() throws -> AircraftCredential? {
            if rapidAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nil
            } else {
                try AircraftCredential(secret: rapidAPIKey)
            }
        }
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
                    replacementCredential: replacementCredential(),
                )
            case .flightradar24:
                return try .flightradar24(
                    Flightradar24Configuration(
                        pollingInterval: PollingInterval(seconds: pollingIntervalSeconds),
                    ),
                    replacementCredential: replacementCredential(),
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

    func projectionViewport() -> ProjectionViewport {
        switch projectionMode {
            case .map:
                .map(airAndSpacePreferences.mapViewport)
            case .trueSky:
                .trueSky(airAndSpacePreferences.skyViewport)
        }
    }

    private func credentialFailure(
        for id: AircraftCredentialID,
    ) -> ThrowPostLaunchFailure {
        switch id {
            case .rapidAPI: .rapidAPICredential
            case .flightradar24: .flightradar24Credential
        }
    }

    func discardOldFrame() async throws {
        currentSnapshot = nil
        replacePendingAirAndSpaceFrame(.empty)
        stopRenderer()
        let empty = visibleProjection.withoutMarks(generatedAt: dateProvider.now())
        if reduceMotion {
            replaceVisibleProjection(empty)
            await projectionWorker.reset()
        } else {
            withAnimation(.linear(duration: 0.25)) {
                projectionMarkOpacity = 0
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch is CancellationError {
                replaceVisibleProjection(empty)
                projectionMarkOpacity = 1
                await projectionWorker.reset()
                throw CancellationError()
            } catch {
                replaceVisibleProjection(empty)
                projectionMarkOpacity = 1
                await projectionWorker.reset()
                throw error
            }
            replaceVisibleProjection(empty)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                projectionMarkOpacity = 1
            }
            await projectionWorker.reset()
        }
    }

    private func replaceVisibleProjection(_ visible: VisibleProjection) {
        guard let presentation = projectionPresentationState.replacingVisible(visible) else {
            assertionFailure("A visible projection replacement must preserve its identity")
            return
        }
        projectionPresentationState = presentation
    }
}

enum ProjectionPreferenceChange: Equatable {
    case observerLocation
    case aircraftSource
}

/// The runtime work that finishes after a preference-backed context publishes.
struct ProjectionPreferenceInvalidation: Equatable {
    let change: ProjectionPreferenceChange
    let activationLease: ProjectionActivationLease?
}
