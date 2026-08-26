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
        let configuration = AircraftSourceConfiguration.flightradar24(
            Flightradar24Configuration(
                pollingInterval: .defaultValue,
                credentialID: .flightradar24,
            ),
        )
        let configured = try await sourceFactory.makeSource(configuration: configuration)
        guard let source = configured.source as? Flightradar24Source else {
            throw AircraftSourceFailure.invalidConfiguration
        }
        let report = try await source.usage(period: .last24Hours)
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
            let replacementCredential: AircraftCredential?
            if choice == .adsbExchange || choice == .flightradar24,
               rapidAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            {
                let credential = try AircraftCredential(secret: rapidAPIKey)
                if choice == .adsbExchange {
                    let source = ADSBExchangeRapidAPISource(
                        transport: cloudTransport,
                        decoder: ADSBExchangeV2Decoder(),
                        credential: credential,
                        dateProvider: dateProvider,
                    )
                    _ = try await source.credentialTestSnapshot(observer: query.observer)
                } else {
                    let source = Flightradar24Source(
                        transport: cloudTransport,
                        decoder: Flightradar24Decoder(),
                        credential: credential,
                        dateProvider: dateProvider,
                    )
                    _ = try await source.credentialTestSnapshot(observer: query.observer)
                }
                replacementCredential = credential
            } else {
                let configured = try await sourceFactory.makeSource(configuration: configuration)
                if let rapidAPISource = configured.source as? ADSBExchangeRapidAPISource {
                    _ = try await rapidAPISource.credentialTestSnapshot(observer: query.observer)
                } else if let flightradar24Source = configured.source as? Flightradar24Source {
                    _ = try await flightradar24Source.credentialTestSnapshot(
                        observer: query.observer,
                    )
                } else {
                    _ = try await configured.source.snapshot(for: query)
                }
                replacementCredential = nil
            }
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
        do {
            await pollingCoordinator.deactivate()
            activePollingSignature = nil
            try await discardOldFrame()

            if let replacementCredential = draft.replacementCredential {
                switch draft.configuration.kind {
                    case .adsbExchangeRapidAPI:
                        try await credentialStore.save(replacementCredential, for: .rapidAPI)
                        rapidAPICredentialState = .saved(lastFour: replacementCredential.lastFour)
                    case .flightradar24:
                        invalidateFlightradar24Usage()
                        try await credentialStore.save(replacementCredential, for: .flightradar24)
                        flightradar24CredentialState = .saved(
                            lastFour: replacementCredential.lastFour,
                        )
                    case .adsbLol, .readsb:
                        assertionFailure("A credential-free source supplied a credential")
                }
            }

            selectedSourceConfiguration = draft.configuration
            validatedSourceConfiguration = draft.configuration
            try await savePreferencesImmediately()
            settingsFailure = nil
            scheduleDemandReconciliation()
            return true
        } catch is CancellationError {
            return false
        } catch let failure as AircraftSourceFailure {
            feedHealth = .failed(failure.presentationCategory)
            return false
        } catch {
            settingsFailure = error.localizedDescription
            feedHealth = .failed(.sourceNotValidated)
            return false
        }
    }

    public func deleteRapidAPICredential() async {
        let deletesActiveSource = selectedSourceConfiguration?.kind == .adsbExchangeRapidAPI
        if deletesActiveSource {
            await pollingCoordinator.deactivate()
            activePollingSignature = nil
            await clearProjectionState(restartsGeography: true)
        }
        do {
            try await credentialStore.delete(.rapidAPI)
            rapidAPICredentialState = .missing
            if deletesActiveSource {
                feedHealth = .failed(.missingCredential)
            }
        } catch is CancellationError {
            return
        } catch {
            settingsFailure = error.localizedDescription
        }
    }

    public func deleteFlightradar24Credential() async {
        let deletesActiveSource = selectedSourceConfiguration?.kind == .flightradar24
        if deletesActiveSource {
            await pollingCoordinator.deactivate()
            activePollingSignature = nil
            await clearProjectionState(restartsGeography: true)
        }
        do {
            invalidateFlightradar24Usage()
            try await credentialStore.delete(.flightradar24)
            flightradar24CredentialState = .missing
            if deletesActiveSource { feedHealth = .failed(.missingCredential) }
        } catch is CancellationError {
            return
        } catch {
            settingsFailure = error.localizedDescription
        }
    }

    func applyPollingState(_ state: AircraftPollingState) async {
        pollingStateGeneration &+= 1
        let generation = pollingStateGeneration
        switch state {
            case .idle:
                guard activePollingSignature == nil else { return }
                feedHealth = .idle
            case .loading:
                feedHealth = .loading
            case let .healthy(snapshot, _):
                currentSnapshot = snapshot
                currentMarkAvailability = .current
                do {
                    let layer = try await makeLayerFrame(snapshot)
                    guard generation == pollingStateGeneration else { return }
                    currentLayerFrame = layer
                    feedHealth = .healthy(
                        lastUpdate: snapshot.fetchedAt,
                        visibleAircraft: projectionFrame.visibleAircraftCount,
                    )
                    restartRenderer()
                    scheduleRouteEnrichment(for: snapshot)
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == pollingStateGeneration else { return }
                    feedHealth = .failed(.decoding)
                    await clearProjectionState(restartsGeography: true)
                }
            case let .retrying(lastGoodSnapshot, failure, failureStartedAt, nextRetryAt):
                currentSnapshot = lastGoodSnapshot
                currentMarkAvailability = .retrying(since: failureStartedAt)
                if let lastGoodSnapshot {
                    do {
                        let layer = try await makeLayerFrame(lastGoodSnapshot)
                        guard generation == pollingStateGeneration else { return }
                        currentLayerFrame = layer
                        feedHealth = .retrying(
                            lastUpdate: lastGoodSnapshot.fetchedAt,
                            nextRetry: nextRetryAt,
                            failure: failure.presentationCategory,
                            visibleAircraft: projectionFrame.visibleAircraftCount,
                        )
                        restartRenderer()
                        scheduleRouteEnrichment(for: lastGoodSnapshot)
                    } catch is CancellationError {
                        return
                    } catch {
                        guard generation == pollingStateGeneration else { return }
                        feedHealth = .failed(.decoding)
                        await clearProjectionState(restartsGeography: true)
                    }
                } else {
                    await clearProjectionState(restartsGeography: true)
                    guard generation == pollingStateGeneration else { return }
                    feedHealth = .retrying(
                        lastUpdate: nil,
                        nextRetry: nextRetryAt,
                        failure: failure.presentationCategory,
                        visibleAircraft: 0,
                    )
                }
            case let .failed(failure):
                await clearProjectionState(restartsGeography: true)
                guard generation == pollingStateGeneration else { return }
                feedHealth = .failed(failure.presentationCategory)
            case .quiet:
                await clearProjectionState(restartsGeography: true)
                guard generation == pollingStateGeneration else { return }
                feedHealth = .quiet
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
        guard generation == demandGeneration else { return }
        expireTemporaryWakeIfNeeded()
        scheduleQuietBoundary()
        let quiet = isQuietNow
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
            await pollingCoordinator.deactivate()
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
                await pollingCoordinator.deactivate()
                guard generation == demandGeneration else { return }
                await clearProjectionState(restartsGeography: true)
                guard generation == demandGeneration else { return }
                feedHealth = .failed(.locationUnavailable)
                return
            }
        }

        guard flightsEnabled else {
            activePollingSignature = nil
            await pollingCoordinator.deactivate()
            guard generation == demandGeneration else { return }
            currentSnapshot = nil
            currentLayerFrame = nil
            currentMarkAvailability = .current
            feedHealth = .idle
            restartRenderer()
            return
        }

        guard let configuration = selectedSourceConfiguration,
              configuration == validatedSourceConfiguration
        else {
            activePollingSignature = nil
            await pollingCoordinator.deactivate()
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.sourceNotValidated)
            return
        }
        if configuration.kind == .adsbExchangeRapidAPI, rapidAPICredentialState == .missing {
            activePollingSignature = nil
            await pollingCoordinator.deactivate()
            guard generation == demandGeneration else { return }
            await clearProjectionState(restartsGeography: true)
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.missingCredential)
            return
        }
        if configuration.kind == .flightradar24, flightradar24CredentialState == .missing {
            activePollingSignature = nil
            await pollingCoordinator.deactivate()
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
            await pollingCoordinator.deactivate()
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
        await pollingCoordinator.activate(configuration: configuration, query: query, quiet: false)
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
              let confirmedLocation
        else {
            return
        }
        renderTask = Task(name: "Throw projection 30Hz") { [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                do {
                    let output = try await projectionWorker.frame(
                        layerFrame: flightsEnabled ? currentLayerFrame : nil,
                        geographyEnabled: geographyEnabled,
                        observer: confirmedLocation.position,
                        mapCenter: activeMapCenter,
                        viewport: projectionViewport(),
                        calibration: projectionCalibration(),
                        generatedAt: dateProvider.now(),
                        reduceMotion: reduceMotion,
                    )
                    try Task.checkCancellation()
                    guard generation == renderGeneration else { return }
                    projectionFrame = output.frame
                    projectionMarkEffects = output.effects
                    observerMapPoint = output.observerPoint
                    geographyLayerHealth = output.geographyHealth
                    updateVisibleCount(output.frame.visibleAircraftCount)
                    if currentLayerFrame == nil {
                        renderTask = nil
                        return
                    }
                    try await Task.sleep(for: .seconds(1.0 / 30.0))
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

    func stopRenderer() {
        renderGeneration &+= 1
        renderTask?.cancel()
        renderTask = nil
    }

    func clearProjectionState(restartsGeography: Bool) async {
        cancelRouteEnrichment()
        currentSnapshot = nil
        currentLayerFrame = nil
        currentMarkAvailability = .current
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
        pollingStateGeneration &+= 1
        let generation = pollingStateGeneration
        Task(name: "Throw rebuild flight labels") { [weak self] in
            guard let self else { return }
            do {
                let layer = try await makeLayerFrame(currentSnapshot)
                guard generation == pollingStateGeneration else { return }
                currentLayerFrame = layer
                restartRenderer()
            } catch is CancellationError {
                return
            } catch {
                guard generation == pollingStateGeneration else { return }
                feedHealth = .failed(.decoding)
                await clearProjectionState(restartsGeography: true)
            }
        }
    }

    func makeLayerFrame(_ snapshot: AircraftSnapshot) async throws -> LayerFrame {
        guard let confirmedLocation else { throw ThrowValidationError.invalidPreferencePayload }
        let routeResults: [FlightCallsign: FlightRouteResult] = if snapshot.source ==
            .flightradar24
        {
            [:]
        } else {
            await routeResolver.cachedResults(
                for: snapshot.observations,
                at: dateProvider.now(),
            )
        }
        return try await projectionWorker.layerFrame(
            snapshot: snapshot,
            observer: confirmedLocation.position,
            labelMode: labelMode,
            routeResults: routeResults,
            availability: currentMarkAvailability,
        )
    }

    func scheduleRouteEnrichment(for snapshot: AircraftSnapshot) {
        guard snapshot.source != .flightradar24 else {
            cancelRouteEnrichment()
            return
        }
        guard routeTask == nil else { return }
        routeGeneration &+= 1
        let generation = routeGeneration
        routeTask = Task(name: "Throw resolve flight routes") { [weak self] in
            guard let self else { return }
            do {
                let result = try await routeResolver.resolveMissing(
                    for: snapshot.observations,
                    at: dateProvider.now(),
                )
                try Task.checkCancellation()
                guard generation == routeGeneration else { return }
                routeTask = nil
                let continuesEnrichment: Bool
                switch result {
                    case .noRequestNeeded, .coolingDown:
                        continuesEnrichment = false
                    case let .completed(_, hasMoreRequests):
                        routeLogger.record(FlightRouteLogEvent(outcome: .succeeded))
                        rebuildCurrentLayerFrame()
                        continuesEnrichment = hasMoreRequests
                }
                if let currentSnapshot,
                   continuesEnrichment || currentSnapshot.fetchedAt != snapshot.fetchedAt
                {
                    scheduleRouteEnrichment(for: currentSnapshot)
                }
            } catch is CancellationError {
                guard generation == routeGeneration else { return }
                routeTask = nil
            } catch let error as FlightRouteLookupError {
                guard generation == routeGeneration else { return }
                routeTask = nil
                routeLogger.record(FlightRouteLogEvent(outcome: routeOutcome(for: error)))
                if let currentSnapshot, currentSnapshot.fetchedAt != snapshot.fetchedAt {
                    scheduleRouteEnrichment(for: currentSnapshot)
                }
            } catch {
                guard generation == routeGeneration else { return }
                routeTask = nil
                routeLogger.record(FlightRouteLogEvent(outcome: .decodingFailed))
            }
        }
    }

    func cancelRouteEnrichment() {
        routeGeneration &+= 1
        routeTask?.cancel()
        routeTask = nil
    }

    private func routeOutcome(for error: FlightRouteLookupError) -> FlightRouteLogEvent.Outcome {
        switch error {
            case .provider: .providerFailed
            case .transport: .transportFailed
            case .decoding: .decodingFailed
        }
    }

    func updateVisibleCount(_ count: Int) {
        switch feedHealth {
            case let .healthy(lastUpdate, oldCount) where oldCount != count:
                feedHealth = .healthy(lastUpdate: lastUpdate, visibleAircraft: count)
            case let .retrying(lastUpdate, nextRetry, failure, oldCount) where oldCount != count:
                feedHealth = .retrying(
                    lastUpdate: lastUpdate,
                    nextRetry: nextRetry,
                    failure: failure,
                    visibleAircraft: count,
                )
            case .idle, .loading, .healthy, .retrying, .failed, .quiet:
                break
        }
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
                        credentialID: .rapidAPI,
                    ),
                )
            case .flightradar24:
                return try .flightradar24(
                    Flightradar24Configuration(
                        pollingInterval: PollingInterval(seconds: pollingIntervalSeconds),
                        credentialID: .flightradar24,
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
            mode: projectionMode,
            generatedAt: dateProvider.now(),
            geography: nil,
            geographyOpacity: 1,
            marks: [],
        )
    }

    func projectionFrameWithoutMarks() -> ProjectionFrame {
        ProjectionFrame(
            mode: projectionFrame.mode,
            generatedAt: dateProvider.now(),
            geography: projectionFrame.geography,
            geographyOpacity: projectionFrame.geographyOpacity,
            marks: [],
        )
    }

    func discardOldFrame() async throws {
        currentSnapshot = nil
        currentLayerFrame = nil
        currentMarkAvailability = .current
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
