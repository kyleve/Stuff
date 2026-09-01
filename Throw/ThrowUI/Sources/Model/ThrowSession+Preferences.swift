import Foundation
import ThrowCore

extension ThrowSession {
    func apply(_ preferences: ThrowPreferences) {
        isApplyingPreferences = true
        defer { isApplyingPreferences = false }
        setupState = preferences.setupState
        projectionPlaylist = preferences.playlist
        activeExperienceID = preferences.playlist.selectedExperienceID
        nextExperienceID = activeExperienceID.flatMap(preferences.playlist.experience(after:))
        projectionMode = preferences.selectedProjectionMode ?? .map
        mapRadius = preferences.mapViewport.radius.value
        mapCenters = preferences.mapCenters
        minimumElevation = preferences.skyViewport.minimumElevation.degrees
        flightsEnabled = preferences.flightsEnabled
        airlineAccentsEnabled = preferences.airlineAccentsEnabled
        geographyEnabled = preferences.geography.isEnabled
        labelMode = preferences.labelMode
        includeGroundAircraft = preferences.includeGroundAircraft
        markSizePercent = preferences.markSizePercent
        intensityPercent = preferences.intensityPercent
        geographyIntensityPercent = preferences.geography.intensityPercent
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
        locationHealth = Self.locationHealth(
            for: preferences.confirmedLocation,
            now: dateProvider.now(),
        )
        mayApplyTrueHeadingHint = preferences.setupCompleted == false
            && preferences.calibration == .defaultValue
        projectionFrame = ProjectionFrame(
            mode: projectionMode,
            generatedAt: dateProvider.now(),
            geography: nil,
            geographyOpacity: 1,
            marks: [],
        )
    }

    func settingsChanged(reconcilesDemand: Bool) {
        schedulePreferencesSave()
        if reconcilesDemand {
            scheduleDemandReconciliation()
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
        guard sourceMutationInProgress == false else {
            sourceMutationNeedsPreferenceSave = true
            return
        }
        let preferences: ThrowPreferences
        do {
            preferences = try makePreferences()
        } catch {
            settingsFailure = error.localizedDescription
            return
        }
        preferenceSaveTask?.cancel()
        preferenceSaveTask = Task(name: "Throw save preferences") { [weak self, preferenceStore] in
            do {
                try await Task.sleep(for: .milliseconds(150))
                try Task.checkCancellation()
                try await preferenceStore.save(preferences)
                guard Task.isCancelled == false else { return }
                self?.settingsFailure = nil
            } catch is CancellationError {
                return
            } catch {
                self?.settingsFailure = error.localizedDescription
            }
        }
    }

    func savePreferencesImmediately() async throws {
        let preferences = try makePreferences()
        try await persistPreferencesImmediately(preferences)
        projectionPlaylist = preferences.playlist
        await configureExperienceCoordinator(with: projectionPlaylist)
        settingsFailure = nil
    }

    func persistPreferencesImmediately(_ preferences: ThrowPreferences) async throws {
        let pendingSave = preferenceSaveTask
        preferenceSaveTask = nil
        pendingSave?.cancel()
        await pendingSave?.value
        try await preferenceStore.save(preferences)
    }

    func makePreferences() throws -> ThrowPreferences {
        try makePreferences(setupState: setupState)
    }

    func makePreferences(
        setupState: ThrowSetupState,
    ) throws -> ThrowPreferences {
        let global = try ThrowGlobalPreferences(
            calibration: projectionCalibration(),
            intensityPercent: intensityPercent,
            quietSchedule: quietSchedule(),
        )
        let airAndSpace = try AirAndSpacePreferences(
            mapViewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
            mapCenters: mapCenters,
            skyViewport: SkyViewport(
                minimumElevation: ElevationAngle(degrees: minimumElevation),
            ),
            flightsEnabled: flightsEnabled,
            airlineAccentsEnabled: airlineAccentsEnabled,
            geography: GeographyPreferences(
                isEnabled: geographyEnabled,
                intensityPercent: geographyIntensityPercent,
            ),
            labelMode: labelMode,
            includeGroundAircraft: includeGroundAircraft,
            markSizePercent: markSizePercent,
        )
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
            global: global,
            playlist: playlist,
            airAndSpace: airAndSpace,
        )
    }

    func quietSchedule() throws -> QuietSchedule {
        guard quietHoursEnabled else { return .disabled }
        let startComponents = calendar.dateComponents([.hour, .minute], from: quietStart)
        let endComponents = calendar.dateComponents([.hour, .minute], from: quietEnd)
        guard let startHour = startComponents.hour,
              let startMinute = startComponents.minute,
              let endHour = endComponents.hour,
              let endMinute = endComponents.minute
        else {
            throw ThrowValidationError.invalidQuietInterval
        }
        return try QuietSchedule(
            start: LocalTime(hour: startHour, minute: startMinute),
            end: LocalTime(hour: endHour, minute: endMinute),
        )
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
