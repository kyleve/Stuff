import Foundation
import ThrowCore

extension ThrowSession {
    func apply(_ preferences: ThrowPreferences) {
        setupState = preferences.setupState
        projectionPlaylist = preferences.playlist
        let coordinator = ProjectionExperienceCoordinatorState(
            playlist: preferences.playlist,
        )
        globalPreferences = preferences.global
        airAndSpacePreferences = preferences.airAndSpace
        calibrationPreview = nil
        locationHealth = Self.locationHealth(
            for: preferences.confirmedLocation,
            now: dateProvider.now(),
        )
        mayApplyTrueHeadingHint = preferences.setupCompleted == false
            && preferences.calibration == .defaultValue
        pendingAirAndSpaceFrame = .empty
        preparedProjection = nil
        projectionInputRevision = projectionInputRevision.successor()
        projectionPresentationState = .initial(
            coordinator: coordinator,
            preferredExperienceID: preferences.playlist.selectedExperienceID ?? .airAndSpace,
            mode: projectionMode,
            generatedAt: dateProvider.now(),
        )
    }

    public func updateProjectionMode(_ projectionMode: ProjectionMode) {
        guard self.projectionMode != projectionMode else { return }
        setupState = setupState.updatingProjectionMode(projectionMode)
        projectionInputsChanged(restartsPolling: true)
    }

    public func updateGlobalPreferences(_ preferences: ThrowGlobalPreferences) {
        let previous = globalPreferences
        guard previous != preferences else { return }

        let calibrationChanged = previous.calibration != preferences.calibration
        let quietScheduleChanged = previous.quietSchedule != preferences.quietSchedule
        globalPreferences = preferences
        calibrationPreview = nil
        if calibrationChanged,
           previous.calibration.screenTopBearing != preferences.calibration.screenTopBearing
        {
            mayApplyTrueHeadingHint = false
        }

        schedulePreferencesSave(failure: .preferencePersistence)
        if calibrationChanged {
            rebuildCurrentLayerFrame()
            restartRenderer()
        }
        if quietScheduleChanged {
            scheduleDemandReconciliation()
        }
    }

    public func updateAirAndSpacePreferences(_ preferences: AirAndSpacePreferences) {
        let previous = airAndSpacePreferences
        guard previous != preferences else { return }

        let queryInputsChanged = previous.mapViewport != preferences.mapViewport
            || previous.mapCenters != preferences.mapCenters
            || previous.skyViewport != preferences.skyViewport
            || previous.flightsEnabled != preferences.flightsEnabled
            || previous.includeGroundAircraft != preferences.includeGroundAircraft
        let labelModeChanged = previous.labelMode != preferences.labelMode
        let geographyVisibilityChanged = previous.geography.isEnabled
            != preferences.geography.isEnabled
        airAndSpacePreferences = preferences

        if previous.geography.isEnabled, preferences.geography.isEnabled == false {
            removeVisibleGeography()
        }

        schedulePreferencesSave(failure: .preferencePersistence)
        if labelModeChanged {
            rebuildCurrentLayerFrame()
        }
        if queryInputsChanged ||
            (geographyVisibilityChanged && preferences.flightsEnabled == false)
        {
            scheduleDemandReconciliation()
        } else if labelModeChanged || geographyVisibilityChanged {
            restartRenderer()
        }
    }

    func projectionInputsChanged(restartsPolling: Bool) {
        schedulePreferencesSave(failure: .preferencePersistence)
        if restartsPolling {
            scheduleDemandReconciliation()
        } else {
            rebuildCurrentLayerFrame()
            restartRenderer()
        }
    }

    private func removeVisibleGeography() {
        let visible = visibleProjection.removingGeography()
        guard let presentation = projectionPresentationState.replacingVisible(visible) else {
            assertionFailure("Removing geography must preserve the visible View")
            return
        }
        projectionPresentationState = presentation
    }

    func schedulePreferencesSave(failure: ThrowPostLaunchFailure) {
        guard preferenceMutationInProgress == false else {
            deferredPreferenceSaveFailures = deferredPreferenceSaveFailures.recording(failure)
            return
        }
        let preferences: ThrowPreferences
        do {
            preferences = try makePreferences()
        } catch {
            recordPostLaunchFailure(failure, error: error)
            return
        }
        if preferenceSaveQueue.last?.isCoalescible == true {
            let index = preferenceSaveQueue.index(before: preferenceSaveQueue.endIndex)
            preferenceSaveQueue[index] = preferenceSaveQueue[index].coalescing(
                preferences,
                failure: failure,
            )
        } else {
            preferenceSaveQueue.append(
                .coalesced(
                    preferences,
                    failureLedger: ThrowPostLaunchFailureLedger().recording(failure),
                ),
            )
        }
        startPreferenceSaveWorkerIfNeeded()
    }

    func savePreferencesImmediately() async throws {
        let preferences = try makePreferences()
        try await persistPreferencesImmediately(
            preferences,
            failure: .preferencePersistence,
        )
        projectionPlaylist = preferences.playlist
        await configureExperienceCoordinator(with: projectionPlaylist)
    }

    func persistPreferencesImmediately(
        _ preferences: ThrowPreferences,
        failure: ThrowPostLaunchFailure,
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            preferenceSaveQueue.append(
                .immediate(preferences, failure: failure, continuation),
            )
            startPreferenceSaveWorkerIfNeeded()
        }
    }

    func flushPreferencesSave() async {
        while let preferenceSaveTask {
            await preferenceSaveTask.value
        }
    }

    func beginPreferenceMutation() -> Bool {
        guard preferenceMutationInProgress == false else { return false }
        preferenceMutationInProgress = true
        return true
    }

    func finishPreferenceMutation() {
        preferenceMutationInProgress = false
        let failures = deferredPreferenceSaveFailures.failures
        deferredPreferenceSaveFailures = ThrowPostLaunchFailureLedger()
        for failure in failures {
            schedulePreferencesSave(failure: failure)
        }
    }

    /// Persists a mutation against the latest complete preference snapshot.
    /// Publication cannot suspend after the snapshot comparison succeeds.
    func persistReconciledPreferenceMutation<Publication, Preparation>(
        failure: ThrowPostLaunchFailure,
        makeMutation: (ThrowPreferenceSnapshot) throws
            -> ThrowPreferenceMutation<Publication>,
        prepareForPublication: () -> Preparation,
        publish: (Publication) -> Void,
    ) async throws -> Preparation {
        while true {
            let base = preferenceSnapshot
            let candidate: ThrowPreferenceMutation<Publication>
            let preferences: ThrowPreferences
            do {
                candidate = try makeMutation(base)
                preferences = try makePreferences(
                    setupState: candidate.snapshot.setupState,
                    globalPreferences: candidate.snapshot.globalPreferences,
                    airAndSpacePreferences: candidate.snapshot.airAndSpacePreferences,
                    projectionPlaylist: candidate.snapshot.projectionPlaylist,
                )
            } catch {
                recordPostLaunchFailure(failure, error: error)
                throw error
            }
            try await persistPreferencesImmediately(
                preferences,
                failure: failure,
            )
            guard base == preferenceSnapshot else { continue }

            let preparation = prepareForPublication()
            publishPreferenceSnapshot(ThrowPreferenceSnapshot(preferences))
            publish(candidate.publication)
            resolveDeferredPreferenceFailuresAfterReconciledWrite()
            return preparation
        }
    }

    var preferenceSnapshot: ThrowPreferenceSnapshot {
        ThrowPreferenceSnapshot(
            setupState: setupState,
            globalPreferences: globalPreferences,
            airAndSpacePreferences: airAndSpacePreferences,
            projectionPlaylist: projectionPlaylist,
        )
    }

    func resolveDeferredPreferenceFailuresAfterReconciledWrite() {
        let failures = deferredPreferenceSaveFailures.failures
        deferredPreferenceSaveFailures = ThrowPostLaunchFailureLedger()
        for failure in failures {
            resolvePostLaunchFailure(failure.owner)
        }
    }

    private func publishPreferenceSnapshot(_ snapshot: ThrowPreferenceSnapshot) {
        setupState = snapshot.setupState
        globalPreferences = snapshot.globalPreferences
        airAndSpacePreferences = snapshot.airAndSpacePreferences
        projectionPlaylist = snapshot.projectionPlaylist
    }

    private func startPreferenceSaveWorkerIfNeeded() {
        guard preferenceSaveTask == nil else { return }
        preferenceSaveTask = Task(name: "Throw save preferences") { [self] in
            await drainPreferenceSaveQueue()
        }
    }

    private func drainPreferenceSaveQueue() async {
        while preferenceSaveQueue.isEmpty == false {
            let request = preferenceSaveQueue.removeFirst()
            do {
                try await preferenceStore.save(request.preferences)
                for failure in request.failures {
                    resolvePostLaunchFailure(failure.owner)
                }
                request.resume()
            } catch let error as CancellationError {
                request.resume(throwing: error)
            } catch {
                for failure in request.failures {
                    recordPostLaunchFailure(failure, error: error)
                }
                request.resume(throwing: error)
            }
        }
        preferenceSaveTask = nil
    }

    func makePreferences() throws -> ThrowPreferences {
        try makePreferences(setupState: setupState)
    }

    func makePreferences(
        setupState: ThrowSetupState,
    ) throws -> ThrowPreferences {
        try makePreferences(
            setupState: setupState,
            globalPreferences: globalPreferences,
            airAndSpacePreferences: airAndSpacePreferences,
        )
    }

    func makePreferences(
        setupState: ThrowSetupState,
        globalPreferences: ThrowGlobalPreferences,
        airAndSpacePreferences: AirAndSpacePreferences,
    ) throws -> ThrowPreferences {
        try makePreferences(
            setupState: setupState,
            globalPreferences: globalPreferences,
            airAndSpacePreferences: airAndSpacePreferences,
            projectionPlaylist: projectionPlaylist,
        )
    }

    func makePreferences(
        setupState: ThrowSetupState,
        globalPreferences: ThrowGlobalPreferences,
        airAndSpacePreferences: AirAndSpacePreferences,
        projectionPlaylist: ProjectionPlaylist,
    ) throws -> ThrowPreferences {
        let playlist: ProjectionPlaylist = if setupState.configuredExperienceIDs
            .contains(.airAndSpace),
            projectionPlaylist.entry(for: .airAndSpace) == nil
        {
            try ProjectionPlaylist(
                entries: [
                    ProjectionPlaylistEntry(
                        experienceID: .airAndSpace,
                        dwellDuration: .defaultValue,
                    ),
                ],
                automaticRotationEnabled: false,
                selectedExperienceID: .airAndSpace,
                configuredExperienceIDs: [.airAndSpace],
                catalog: .standard,
            )
        } else {
            projectionPlaylist
        }
        return try ThrowPreferences(
            setupState: setupState,
            global: globalPreferences,
            playlist: playlist,
            airAndSpace: airAndSpacePreferences,
        )
    }

    func updateQuietSchedule(_ schedule: QuietSchedule) {
        updateGlobalPreferences(globalPreferences.replacingQuietSchedule(schedule))
    }
}

/// All preference-backed session values captured in one comparable revision.
struct ThrowPreferenceSnapshot: Equatable {
    let setupState: ThrowSetupState
    let globalPreferences: ThrowGlobalPreferences
    let airAndSpacePreferences: AirAndSpacePreferences
    let projectionPlaylist: ProjectionPlaylist

    init(
        setupState: ThrowSetupState,
        globalPreferences: ThrowGlobalPreferences,
        airAndSpacePreferences: AirAndSpacePreferences,
        projectionPlaylist: ProjectionPlaylist,
    ) {
        self.setupState = setupState
        self.globalPreferences = globalPreferences
        self.airAndSpacePreferences = airAndSpacePreferences
        self.projectionPlaylist = projectionPlaylist
    }

    init(_ preferences: ThrowPreferences) {
        self.init(
            setupState: preferences.setupState,
            globalPreferences: preferences.global,
            airAndSpacePreferences: preferences.airAndSpace,
            projectionPlaylist: preferences.playlist,
        )
    }

    func replacingSetupState(_ setupState: ThrowSetupState) -> Self {
        Self(
            setupState: setupState,
            globalPreferences: globalPreferences,
            airAndSpacePreferences: airAndSpacePreferences,
            projectionPlaylist: projectionPlaylist,
        )
    }
}

/// A candidate snapshot and the non-persistent state published with it.
struct ThrowPreferenceMutation<Publication> {
    let snapshot: ThrowPreferenceSnapshot
    let publication: Publication
}

enum PreferenceSaveRequest {
    case coalesced(
        ThrowPreferences,
        failureLedger: ThrowPostLaunchFailureLedger,
    )
    case immediate(
        ThrowPreferences,
        failure: ThrowPostLaunchFailure,
        CheckedContinuation<Void, any Error>,
    )

    var preferences: ThrowPreferences {
        switch self {
            case let .coalesced(preferences, _), let .immediate(preferences, _, _):
                preferences
        }
    }

    var failures: [ThrowPostLaunchFailure] {
        switch self {
            case let .coalesced(_, failureLedger):
                failureLedger.failures
            case let .immediate(_, failure, _):
                [failure]
        }
    }

    func coalescing(
        _ preferences: ThrowPreferences,
        failure: ThrowPostLaunchFailure,
    ) -> Self {
        guard case let .coalesced(_, failureLedger) = self else { return self }
        return .coalesced(
            preferences,
            failureLedger: failureLedger.recording(failure),
        )
    }

    var isCoalescible: Bool {
        if case .coalesced = self { true } else { false }
    }

    var isImmediate: Bool {
        if case .immediate = self { true } else { false }
    }

    func resume() {
        if case let .immediate(_, _, continuation) = self {
            continuation.resume()
        }
    }

    func resume(throwing error: any Error) {
        if case let .immediate(_, _, continuation) = self {
            continuation.resume(throwing: error)
        }
    }
}

extension ThrowSetupState {
    func updatingSourceSelection(_ sourceSelection: AircraftSourceSelection) -> Self {
        switch self {
            case let .onboarding(setup):
                return .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: sourceSelection,
                        location: setup.location,
                        projection: setup.projection,
                    ),
                )
            case let .configured(setup):
                if case let .configured(source) = sourceSelection,
                   source == setup.source
                {
                    return self
                }
                return .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: sourceSelection,
                        location: .confirmed(
                            mode: setup.locationMode,
                            location: setup.confirmedLocation,
                        ),
                        projection: .selected(setup.projectionMode),
                    ),
                )
        }
    }

    func selectingSource(_ source: AircraftSourceConfiguration?) -> Self {
        if source == selectedSource { return self }
        let sourceSelection = source.map(AircraftSourceSelection.awaitingValidation)
            ?? .unconfigured
        return updatingSourceSelection(sourceSelection)
    }

    func validatingSource(_ source: AircraftSourceConfiguration?) -> Self {
        guard let source else {
            let sourceSelection = selectedSource.map(AircraftSourceSelection.awaitingValidation)
                ?? .unconfigured
            return updatingSourceSelection(sourceSelection)
        }
        guard selectedSource == source else { return self }
        return updatingSourceSelection(.configured(source))
    }

    func replacingSource(_ source: AircraftSourceConfiguration) -> Self {
        switch self {
            case let .onboarding(setup):
                .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: .configured(source),
                        location: setup.location,
                        projection: setup.projection,
                    ),
                )
            case let .configured(setup):
                .configured(
                    ThrowConfiguredSetup(
                        source: source,
                        locationMode: setup.locationMode,
                        confirmedLocation: setup.confirmedLocation,
                        projectionMode: setup.projectionMode,
                    ),
                )
        }
    }

    func updatingLocation(
        mode: ObserverLocationMode,
        confirmedLocation: ConfirmedObserverLocation?,
    ) -> Self {
        let locationState: ObserverLocationSetupState = if let confirmedLocation {
            .confirmed(mode: mode, location: confirmedLocation)
        } else {
            .unconfirmed(mode: mode)
        }
        switch self {
            case let .onboarding(setup):
                return .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: setup.sourceSelection,
                        location: locationState,
                        projection: setup.projection,
                    ),
                )
            case let .configured(setup):
                guard let confirmedLocation else {
                    return .onboarding(
                        ThrowOnboardingSetup(
                            sourceSelection: .configured(setup.source),
                            location: locationState,
                            projection: .selected(setup.projectionMode),
                        ),
                    )
                }
                return .configured(
                    ThrowConfiguredSetup(
                        source: setup.source,
                        locationMode: mode,
                        confirmedLocation: confirmedLocation,
                        projectionMode: setup.projectionMode,
                    ),
                )
        }
    }

    func updatingProjectionMode(_ projectionMode: ProjectionMode) -> Self {
        switch self {
            case let .onboarding(setup):
                .onboarding(
                    ThrowOnboardingSetup(
                        sourceSelection: setup.sourceSelection,
                        location: setup.location,
                        projection: .selected(projectionMode),
                    ),
                )
            case let .configured(setup):
                .configured(
                    ThrowConfiguredSetup(
                        source: setup.source,
                        locationMode: setup.locationMode,
                        confirmedLocation: setup.confirmedLocation,
                        projectionMode: projectionMode,
                    ),
                )
        }
    }

    func completing(projectionMode: ProjectionMode) -> Self? {
        guard case let .onboarding(setup) = self,
              case let .configured(source) = setup.sourceSelection,
              case let .confirmed(locationMode, confirmedLocation) = setup.location
        else { return nil }
        return .configured(
            ThrowConfiguredSetup(
                source: source,
                locationMode: locationMode,
                confirmedLocation: confirmedLocation,
                projectionMode: projectionMode,
            ),
        )
    }
}
