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

    public var activeMapCenter: GeoCoordinate {
        guard let observer = confirmedLocation?.position.coordinate else {
            preconditionFailure("A Map center requires a confirmed observer location")
        }
        return mapCenters.center(for: observer)
    }

    public var mapCenterEastOffset: Double {
        get { mapCenterOffset.east }
        set { setMapCenterOffset(east: newValue, north: mapCenterOffset.north) }
    }

    public var mapCenterNorthOffset: Double {
        get { mapCenterOffset.north }
        set { setMapCenterOffset(east: mapCenterOffset.east, north: newValue) }
    }

    public var hasCustomMapCenter: Bool {
        guard let observer = confirmedLocation?.position.coordinate else { return false }
        return activeMapCenter != observer
    }

    public func resetMapCenter() {
        guard let observer = confirmedLocation?.position.coordinate else { return }
        mapCenters = mapCenters.resetting(for: observer)
        projectionInputsChanged(restartsPolling: true)
    }

    private var mapCenterOffset: MapCenterOffset {
        guard let observer = confirmedLocation?.position.coordinate,
              let position = try? ProjectionEngine().greatCirclePosition(
                  from: observer,
                  to: activeMapCenter,
              )
        else { return MapCenterOffset(east: 0, north: 0) }
        let bearing = position.initialBearing.degrees * .pi / 180
        return MapCenterOffset(
            east: position.distance.value * sin(bearing),
            north: position.distance.value * cos(bearing),
        )
    }

    private func setMapCenterOffset(east: Double, north: Double) {
        guard let observer = confirmedLocation?.position.coordinate else { return }
        do {
            let distance = try NauticalMiles(value: hypot(east, north))
            let bearing = try Bearing(degrees: atan2(east, north) * 180 / .pi)
            let center = try ProjectionEngine().destination(
                from: observer,
                bearing: bearing,
                distance: distance,
            )
            mapCenters = mapCenters.setting(center: center, for: observer)
            projectionInputsChanged(restartsPolling: true)
        } catch {
            settingsFailure = error.localizedDescription
        }
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
        let accumulated = await accumulator.result()
        #if DEBUG
            beforeApplyingLocationResolutionForTesting?()
        #endif
        guard generation == locationGeneration, Task.isCancelled == false else { return }
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
        guard beginPreferenceMutation() else { return false }
        defer { finishPreferenceMutation() }
        do {
            let replacement: ObserverLocationReplacement
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
                    let replacementHealth: LocationHealth = switch locationHealth {
                        case .confirmed:
                            .confirmed(
                                accuracyMeters: confirmed.horizontalAccuracyMeters ?? 0,
                                acceptedAt: confirmed.confirmedAt,
                            )
                        case .stale:
                            .stale(
                                accuracyMeters: confirmed.horizontalAccuracyMeters ?? 0,
                                acceptedAt: confirmed.confirmedAt,
                            )
                        case .missing, .locating, .offeredBest, .failed:
                            locationHealth
                    }
                    replacement = ObserverLocationReplacement(
                        setupState: setupState.updatingLocation(
                            mode: .gps,
                            confirmedLocation: confirmed,
                        ),
                        health: replacementHealth,
                        acquisitionDisposition: .preserve,
                    )
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
                    replacement = ObserverLocationReplacement(
                        setupState: setupState.updatingLocation(
                            mode: .manual,
                            confirmedLocation: confirmed,
                        ),
                        health: .confirmed(
                            accuracyMeters: 0,
                            acceptedAt: confirmed.confirmedAt,
                        ),
                        acquisitionDisposition: .cancelAndClearPendingFix,
                    )
            }
            try await commitObserverLocation(replacement)
            return true
        } catch is CancellationError {
            return false
        } catch {
            settingsFailure = error.localizedDescription
            return false
        }
    }

    private func accept(_ fix: LocationFix, mode: ObserverLocationMode) async {
        guard beginPreferenceMutation() else { return }
        defer { finishPreferenceMutation() }
        do {
            let confirmed = try ConfirmedObserverLocation(
                position: fix.position,
                horizontalAccuracyMeters: fix.horizontalAccuracyMeters,
                confirmedAt: dateProvider.now(),
            )
            let replacement = ObserverLocationReplacement(
                setupState: setupState.updatingLocation(
                    mode: mode,
                    confirmedLocation: confirmed,
                ),
                health: .confirmed(
                    accuracyMeters: fix.horizontalAccuracyMeters,
                    acceptedAt: confirmed.confirmedAt,
                ),
                acquisitionDisposition: .clearPendingFix,
            )
            try await commitObserverLocation(replacement)
        } catch is CancellationError {
            return
        } catch {
            settingsFailure = error.localizedDescription
        }
    }

    private func commitObserverLocation(_ replacement: ObserverLocationReplacement) async throws {
        let preferences = try makePreferences(setupState: replacement.setupState)
        try await persistPreferencesImmediately(preferences)

        await airAndSpaceRuntime.deactivate(reporting: .idle)
        activePollingSignature = nil
        await clearProjectionState(restartsGeography: false)
        switch replacement.acquisitionDisposition {
            case .preserve:
                break
            case .clearPendingFix:
                pendingLocationFix = nil
            case .cancelAndClearPendingFix:
                cancelProjectionSessionLocationAcquisition(restoringPreviousHealth: false)
                pendingLocationFix = nil
        }
        setupState = replacement.setupState
        projectionSessionLocationGate = .ready
        locationHealth = replacement.health
        projectionPlaylist = preferences.playlist
        settingsFailure = nil
        await configureExperienceCoordinator(with: projectionPlaylist)
        scheduleDemandReconciliation()
    }
}

private struct ObserverLocationReplacement {
    enum AcquisitionDisposition {
        case preserve
        case clearPendingFix
        case cancelAndClearPendingFix
    }

    let setupState: ThrowSetupState
    let health: LocationHealth
    let acquisitionDisposition: AcquisitionDisposition
}

private struct MapCenterOffset {
    let east: Double
    let north: Double
}
