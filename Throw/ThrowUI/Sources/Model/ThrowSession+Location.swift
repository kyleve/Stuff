import Foundation
import ThrowCore

/// The GPS readiness of the current projection session. A saved position does
/// not make a new session ready until its foreground acquisition has settled.
enum ProjectionSessionLocationGate {
    case required
    case acquiring(previousHealth: LocationHealth)
    case ready
}

extension ThrowSession {
    public var observerLocationMode: ObserverLocationMode {
        locationMode
    }

    public var observerLatitude: Double {
        confirmedLocation?.position.coordinate.latitude ?? 0
    }

    public var observerLongitude: Double {
        confirmedLocation?.position.coordinate.longitude ?? 0
    }

    public var observerAltitudeFeet: Double {
        confirmedLocation?.position.altitude.feet ?? 0
    }

    func prepareProjectionSessionGPSLocation() async {
        guard locationMode == .gps else { return }
        switch projectionSessionLocationGate {
            case .ready:
                return
            case .required:
                projectionSessionLocationGeneration &+= 1
                let generation = projectionSessionLocationGeneration
                let predecessor = locationTask
                projectionSessionLocationGate = .acquiring(previousHealth: locationHealth)
                let acquisition = Task(name: "Throw projection-session GPS acquisition") {
                    [weak self] in
                    await predecessor?.value
                    guard Task.isCancelled == false, let self,
                          generation == projectionSessionLocationGeneration
                    else { return }
                    await refreshLocation()
                    finishProjectionSessionLocationAcquisition(generation: generation)
                }
                locationTask = acquisition
            case .acquiring:
                break
        }
        await locationTask?.value
    }

    func cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: Bool) {
        guard case let .acquiring(previousHealth) = projectionSessionLocationGate else {
            return
        }
        projectionSessionLocationGeneration &+= 1
        locationGeneration &+= 1
        locationTask?.cancel()
        locationSource.stopUpdates()
        projectionSessionLocationGate = .required
        if restoringPreviousHealth {
            locationHealth = previousHealth
        }
    }

    func endProjectionSessionLocationGate() {
        cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: true)
        projectionSessionLocationGate = .required
    }

    private func finishProjectionSessionLocationAcquisition(generation: UInt64) {
        guard generation == projectionSessionLocationGeneration else { return }
        locationTask = nil
        guard case .acquiring = projectionSessionLocationGate else { return }
        switch locationHealth {
            case .confirmed, .stale:
                projectionSessionLocationGate = .ready
            case .missing, .locating, .offeredBest, .failed:
                projectionSessionLocationGate = .required
        }
    }

    public func refreshLocation() async {
        guard locationHealth != .locating else { return }
        locationGeneration &+= 1
        let generation = locationGeneration
        locationHealth = .locating
        let events = locationSource.events
        locationSource.requestWhenInUseAuthorization()
        locationSource.startUpdates()
        defer { locationSource.stopUpdates() }

        let accumulator = LocationFixAccumulator()
        let dateProvider = dateProvider
        let resolution = await withTaskGroup(of: LocationResolution.self) { group in
            group.addTask {
                for await event in events {
                    guard Task.isCancelled == false else { return .failed }
                    switch event {
                        case let .fix(fix):
                            guard LocationFixEvaluator.isValid(fix, at: dateProvider.now()) else {
                                continue
                            }
                            await accumulator.consider(fix)
                            if fix.horizontalAccuracyMeters <= LocationFixEvaluator
                                .targetAccuracyMeters
                            {
                                return .target(fix)
                            }
                        case let .trueHeadingHint(heading):
                            await accumulator.record(heading)
                        case let .authorization(authorization):
                            if authorization == .denied || authorization == .restricted {
                                return .failed
                            }
                            continue
                        case .failed:
                            return .failed
                        case .invalidSample:
                            continue
                    }
                }
                return .failed
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(LocationFixEvaluator.maximumWait))
                    return .timedOut
                } catch {
                    return .failed
                }
            }
            let first = await group.next() ?? .failed
            group.cancelAll()
            return first
        }
        guard generation == locationGeneration, Task.isCancelled == false else { return }
        let accumulated = await accumulator.result()
        if mayApplyTrueHeadingHint, let heading = accumulated.heading {
            mayApplyTrueHeadingHint = false
            screenTopBearing = heading.degrees
        }
        switch resolution {
            case let .target(fix):
                if locationMode == .gps {
                    await accept(fix, mode: .gps)
                } else {
                    pendingLocationFix = fix
                    locationHealth = .offeredBest(
                        accuracyMeters: fix.horizontalAccuracyMeters,
                        observedAt: fix.observedAt,
                        hasStaleConfirmedLocation: confirmedLocation != nil,
                    )
                }
            case .timedOut:
                if let fix = accumulated.fix,
                   LocationFixEvaluator.isValid(fix, at: dateProvider.now())
                {
                    pendingLocationFix = fix
                    locationHealth = .offeredBest(
                        accuracyMeters: fix.horizontalAccuracyMeters,
                        observedAt: fix.observedAt,
                        hasStaleConfirmedLocation: confirmedLocation != nil,
                    )
                } else if let confirmedLocation {
                    locationHealth = .stale(
                        accuracyMeters: confirmedLocation.horizontalAccuracyMeters ?? 0,
                        acceptedAt: confirmedLocation.confirmedAt,
                    )
                } else {
                    locationHealth = .failed
                }
            case .failed:
                if let confirmedLocation {
                    locationHealth = .stale(
                        accuracyMeters: confirmedLocation.horizontalAccuracyMeters ?? 0,
                        acceptedAt: confirmedLocation.confirmedAt,
                    )
                } else {
                    locationHealth = .failed
                }
        }
    }

    public func acceptOfferedLocation() async {
        guard let pendingLocationFix else { return }
        await accept(pendingLocationFix, mode: .gps)
    }

    @discardableResult
    public func saveObserverLocation(
        mode: ObserverLocationMode,
        latitude: Double,
        longitude: Double,
        altitudeFeet: Double,
    ) async -> Bool {
        do {
            switch mode {
                case .gps:
                    guard locationMode == .gps, let acceptedGPSLocation = confirmedLocation else {
                        settingsFailure = String(localized: .locationGpsFixRequired)
                        return false
                    }
                    let position = try ObserverPosition(
                        coordinate: acceptedGPSLocation.position.coordinate,
                        altitude: Altitude(feet: altitudeFeet),
                    )
                    let confirmed = try ConfirmedObserverLocation(
                        position: position,
                        horizontalAccuracyMeters: acceptedGPSLocation.horizontalAccuracyMeters,
                        confirmedAt: acceptedGPSLocation.confirmedAt,
                    )
                    confirmedLocation = confirmed
                    projectionSessionLocationGate = .ready
                    switch locationHealth {
                        case .confirmed:
                            locationHealth = .confirmed(
                                accuracyMeters: confirmed.horizontalAccuracyMeters ?? 0,
                                acceptedAt: confirmed.confirmedAt,
                            )
                        case .stale:
                            locationHealth = .stale(
                                accuracyMeters: confirmed.horizontalAccuracyMeters ?? 0,
                                acceptedAt: confirmed.confirmedAt,
                            )
                        case .missing, .locating, .offeredBest, .failed:
                            break
                    }
                case .manual:
                    let position = try ObserverPosition(
                        coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                        altitude: Altitude(feet: altitudeFeet),
                    )
                    let confirmed = try ConfirmedObserverLocation(
                        position: position,
                        horizontalAccuracyMeters: nil,
                        confirmedAt: dateProvider.now(),
                    )
                    cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: false)
                    confirmedLocation = confirmed
                    locationMode = .manual
                    projectionSessionLocationGate = .ready
                    pendingLocationFix = nil
                    locationHealth = .confirmed(
                        accuracyMeters: 0,
                        acceptedAt: confirmed.confirmedAt,
                    )
            }
            try await savePreferencesImmediately()
            scheduleDemandReconciliation()
            return true
        } catch is CancellationError {
            return false
        } catch {
            settingsFailure = error.localizedDescription
            return false
        }
    }

    private func accept(_ fix: LocationFix, mode: ObserverLocationMode) async {
        do {
            let confirmed = try ConfirmedObserverLocation(
                position: fix.position,
                horizontalAccuracyMeters: fix.horizontalAccuracyMeters,
                confirmedAt: dateProvider.now(),
            )
            confirmedLocation = confirmed
            locationMode = mode
            projectionSessionLocationGate = .ready
            pendingLocationFix = nil
            locationHealth = .confirmed(
                accuracyMeters: fix.horizontalAccuracyMeters,
                acceptedAt: confirmed.confirmedAt,
            )
            try await savePreferencesImmediately()
            scheduleDemandReconciliation()
        } catch is CancellationError {
            return
        } catch {
            settingsFailure = error.localizedDescription
            locationHealth = .failed
        }
    }
}
