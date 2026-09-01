import Foundation
import ThrowCore

extension ThrowSession {
    func apply(_ preferences: ThrowPreferences) {
        setupState = preferences.setupState
        projectionPlaylist = preferences.playlist
        experienceCoordinatorState = ProjectionExperienceCoordinatorState(
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
        projectionFrame = .emptyAirAndSpace(
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

        schedulePreferencesSave()
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
            geographyLayerHealth = .idle
            projectionFrame = projectionFrame.removingGeography()
        }

        schedulePreferencesSave()
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
        schedulePreferencesSave()
        if restartsPolling {
            scheduleDemandReconciliation()
        } else {
            rebuildCurrentLayerFrame()
            restartRenderer()
        }
    }

    func schedulePreferencesSave() {
        guard preferenceMutationInProgress == false else {
            preferenceMutationNeedsSave = true
            return
        }
        let preferences: ThrowPreferences
        do {
            preferences = try makePreferences()
        } catch {
            settingsFailure = error.localizedDescription
            return
        }
        if preferenceSaveQueue.last?.isCoalescible == true {
            preferenceSaveQueue[preferenceSaveQueue.index(before: preferenceSaveQueue.endIndex)] =
                .coalesced(preferences)
        } else {
            preferenceSaveQueue.append(.coalesced(preferences))
        }
        startPreferenceSaveWorkerIfNeeded()
    }

    func savePreferencesImmediately() async throws {
        let preferences = try makePreferences()
        try await persistPreferencesImmediately(preferences)
        projectionPlaylist = preferences.playlist
        await configureExperienceCoordinator(with: projectionPlaylist)
        settingsFailure = nil
    }

    func persistPreferencesImmediately(_ preferences: ThrowPreferences) async throws {
        try await withCheckedThrowingContinuation { continuation in
            preferenceSaveQueue.append(.immediate(preferences, continuation))
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
        guard preferenceMutationNeedsSave else { return }
        preferenceMutationNeedsSave = false
        schedulePreferencesSave()
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
                settingsFailure = nil
                request.resume()
            } catch {
                settingsFailure = error.localizedDescription
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

enum PreferenceSaveRequest {
    case coalesced(ThrowPreferences)
    case immediate(ThrowPreferences, CheckedContinuation<Void, any Error>)

    var preferences: ThrowPreferences {
        switch self {
            case let .coalesced(preferences), let .immediate(preferences, _):
                preferences
        }
    }

    var isCoalescible: Bool {
        if case .coalesced = self { true } else { false }
    }

    var isImmediate: Bool {
        if case .immediate = self { true } else { false }
    }

    func resume() {
        if case let .immediate(_, continuation) = self {
            continuation.resume()
        }
    }

    func resume(throwing error: any Error) {
        if case let .immediate(_, continuation) = self {
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
