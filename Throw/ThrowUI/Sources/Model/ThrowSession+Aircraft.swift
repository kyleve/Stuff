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
        if case let .adsbExchangeRapidAPI(configuration) = selectedSourceConfiguration {
            configuration.pollingInterval.seconds
        } else {
            PollingInterval.defaultValue.seconds
        }
    }

    public var sourceDisplayName: String {
        switch selectedSourceConfiguration?.kind {
            case .adsbLol: String(localized: .sourceAdsbLol)
            case .readsb: String(localized: .sourceReadsb)
            case .adsbExchangeRapidAPI: String(localized: .sourceAdsbExchange)
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
            if choice == .adsbExchange,
               rapidAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            {
                let credential = try AircraftCredential(secret: rapidAPIKey)
                let source = ADSBExchangeRapidAPISource(
                    transport: cloudTransport,
                    decoder: ADSBExchangeV2Decoder(),
                    credential: credential,
                    dateProvider: dateProvider,
                )
                _ = try await source.credentialTestSnapshot(observer: query.observer)
                replacementCredential = credential
            } else {
                let configured = try await sourceFactory.makeSource(configuration: configuration)
                if let rapidAPISource = configured.source as? ADSBExchangeRapidAPISource {
                    _ = try await rapidAPISource.credentialTestSnapshot(observer: query.observer)
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
                try await credentialStore.save(replacementCredential, for: .rapidAPI)
                rapidAPICredentialState = .saved(lastFour: replacementCredential.lastFour)
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
            await clearProjectionState()
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
                do {
                    let layer = try await makeLayerFrame(snapshot)
                    guard generation == pollingStateGeneration else { return }
                    currentLayerFrame = layer
                    feedHealth = .healthy(
                        lastUpdate: snapshot.fetchedAt,
                        visibleAircraft: projectionFrame.visibleAircraftCount,
                    )
                    restartRenderer()
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == pollingStateGeneration else { return }
                    feedHealth = .failed(.decoding)
                    await clearProjectionState()
                }
            case let .retrying(lastGoodSnapshot, failure, nextRetryAt):
                currentSnapshot = lastGoodSnapshot
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
                    } catch is CancellationError {
                        return
                    } catch {
                        guard generation == pollingStateGeneration else { return }
                        feedHealth = .failed(.decoding)
                        await clearProjectionState()
                    }
                } else {
                    await clearProjectionState()
                    guard generation == pollingStateGeneration else { return }
                    feedHealth = .retrying(
                        lastUpdate: nil,
                        nextRetry: nextRetryAt,
                        failure: failure.presentationCategory,
                        visibleAircraft: 0,
                    )
                }
            case let .failed(failure):
                await clearProjectionState()
                guard generation == pollingStateGeneration else { return }
                feedHealth = .failed(failure.presentationCategory)
            case .quiet:
                await clearProjectionState()
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
        guard hasStarted,
              isForeground,
              outputDemands.isEmpty == false,
              isCalibrating == false,
              flightsEnabled,
              quiet == false
        else {
            cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: true)
            activePollingSignature = nil
            await pollingCoordinator.deactivate()
            guard generation == demandGeneration else { return }
            await clearProjectionState()
            guard generation == demandGeneration else { return }
            feedHealth = quiet ? .quiet : .idle
            return
        }

        guard let configuration = selectedSourceConfiguration,
              configuration == validatedSourceConfiguration
        else {
            activePollingSignature = nil
            await pollingCoordinator.deactivate()
            guard generation == demandGeneration else { return }
            await clearProjectionState()
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.sourceNotValidated)
            return
        }
        if configuration.kind == .adsbExchangeRapidAPI, rapidAPICredentialState == .missing {
            activePollingSignature = nil
            await pollingCoordinator.deactivate()
            guard generation == demandGeneration else { return }
            await clearProjectionState()
            guard generation == demandGeneration else { return }
            feedHealth = .failed(.missingCredential)
            return
        }

        if locationMode == .gps {
            await prepareProjectionSessionGPSLocation()
            guard generation == demandGeneration else { return }
            guard case .ready = projectionSessionLocationGate else {
                activePollingSignature = nil
                await pollingCoordinator.deactivate()
                guard generation == demandGeneration else { return }
                await clearProjectionState()
                guard generation == demandGeneration else { return }
                feedHealth = .failed(.locationUnavailable)
                return
            }
        }

        let query: AircraftQuery
        do {
            query = try aircraftQuery()
        } catch {
            activePollingSignature = nil
            await pollingCoordinator.deactivate()
            guard generation == demandGeneration else { return }
            await clearProjectionState()
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
    }

    func restartRenderer() {
        renderGeneration &+= 1
        let generation = renderGeneration
        renderTask?.cancel()
        guard outputDemands.isEmpty == false,
              isForeground,
              isCalibrating == false,
              isQuietNow == false,
              let currentLayerFrame,
              let confirmedLocation
        else {
            return
        }
        renderTask = Task(name: "Throw projection 30Hz") { [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                do {
                    let frame = try await projectionWorker.frame(
                        layerFrame: currentLayerFrame,
                        observer: confirmedLocation.position,
                        viewport: projectionViewport(),
                        calibration: projectionCalibration(),
                        generatedAt: dateProvider.now(),
                        reduceMotion: reduceMotion,
                    )
                    try Task.checkCancellation()
                    guard generation == renderGeneration else { return }
                    projectionFrame = frame
                    updateVisibleCount(frame.visibleAircraftCount)
                    try await Task.sleep(for: .seconds(1.0 / 30.0))
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == renderGeneration else { return }
                    feedHealth = .failed(.decoding)
                    await clearProjectionState()
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

    func clearProjectionState() async {
        currentSnapshot = nil
        currentLayerFrame = nil
        stopRenderer()
        projectionFrame = emptyProjectionFrame()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            projectionContentOpacity = 1
        }
        await projectionWorker.reset()
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
                await clearProjectionState()
            }
        }
    }

    func makeLayerFrame(_ snapshot: AircraftSnapshot) async throws -> LayerFrame {
        guard let confirmedLocation else { throw ThrowValidationError.invalidPreferencePayload }
        return try await projectionWorker.layerFrame(
            snapshot: snapshot,
            observer: confirmedLocation.position,
            labelMode: labelMode,
        )
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
        }
    }

    func validationQuery() throws -> AircraftQuery {
        guard let confirmedLocation else { throw AircraftSourceFailure.invalidConfiguration }
        return try AircraftQuery(
            observer: confirmedLocation.position,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 5))),
            includeGroundAircraft: false,
        )
    }

    func aircraftQuery() throws -> AircraftQuery {
        guard let confirmedLocation else { throw AircraftSourceFailure.invalidConfiguration }
        return try AircraftQuery(
            observer: confirmedLocation.position,
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
        ProjectionFrame(mode: projectionMode, generatedAt: dateProvider.now(), marks: [])
    }

    func discardOldFrame() async throws {
        currentSnapshot = nil
        currentLayerFrame = nil
        stopRenderer()
        let empty = emptyProjectionFrame()
        if reduceMotion {
            projectionFrame = empty
            await projectionWorker.reset()
        } else {
            withAnimation(.linear(duration: 0.25)) {
                projectionContentOpacity = 0
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch is CancellationError {
                projectionFrame = empty
                projectionContentOpacity = 1
                await projectionWorker.reset()
                throw CancellationError()
            } catch {
                projectionFrame = empty
                projectionContentOpacity = 1
                await projectionWorker.reset()
                throw error
            }
            projectionFrame = empty
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                projectionContentOpacity = 1
            }
            await projectionWorker.reset()
        }
    }
}
