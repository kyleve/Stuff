import Foundation
import ThrowCore

extension ThrowSession {
    enum AircraftSourcePreferenceSelection {
        case unconfigured
        case awaitingValidation(AircraftSourceConfiguration)
        case configured(AircraftSourceConfiguration)

        init(
            selected: AircraftSourceConfiguration?,
            validated: AircraftSourceConfiguration?,
        ) throws {
            switch (selected, validated) {
                case (nil, nil):
                    self = .unconfigured
                case let (selected?, nil):
                    self = .awaitingValidation(selected)
                case let (selected?, validated?) where selected == validated:
                    self = .configured(selected)
                case (nil, .some), (.some, .some):
                    throw ThrowValidationError.invalidPreferencePayload
            }
        }

        var selected: AircraftSourceConfiguration? {
            switch self {
                case .unconfigured:
                    nil
                case let .awaitingValidation(configuration),
                     let .configured(configuration):
                    configuration
            }
        }

        var validated: AircraftSourceConfiguration? {
            switch self {
                case .unconfigured, .awaitingValidation:
                    nil
                case let .configured(configuration):
                    configuration
            }
        }
    }

    func apply(_ preferences: ThrowPreferences) {
        isApplyingPreferences = true
        defer { isApplyingPreferences = false }
        setupCompleted = preferences.setupCompleted
        projectionPlaylist = preferences.playlist
        activeExperienceID = preferences.playlist.selectedExperienceID
        nextExperienceID = activeExperienceID.flatMap(preferences.playlist.experience(after:))
        selectedSourceConfiguration = preferences.selectedSource
        validatedSourceConfiguration = preferences.validatedSource
        locationMode = preferences.locationMode
        confirmedLocation = preferences.confirmedLocation
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
            preferences = try makePreferences(setupCompleted: setupCompleted)
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
        let pendingSave = preferenceSaveTask
        preferenceSaveTask = nil
        pendingSave?.cancel()
        await pendingSave?.value
        let preferences = try makePreferences(setupCompleted: setupCompleted)
        try await preferenceStore.save(preferences)
        projectionPlaylist = preferences.playlist
        await configureExperienceCoordinator(with: projectionPlaylist)
        settingsFailure = nil
    }

    func makePreferences(setupCompleted: Bool) throws -> ThrowPreferences {
        let sourceSelection = try AircraftSourcePreferenceSelection(
            selected: selectedSourceConfiguration,
            validated: validatedSourceConfiguration,
        )
        return try makePreferences(
            setupCompleted: setupCompleted,
            sourceSelection: sourceSelection,
        )
    }

    func makePreferences(
        setupCompleted: Bool,
        sourceSelection: AircraftSourcePreferenceSelection,
    ) throws -> ThrowPreferences {
        let global = try ThrowGlobalPreferences(
            locationMode: locationMode,
            confirmedLocation: confirmedLocation,
            calibration: projectionCalibration(),
            intensityPercent: intensityPercent,
            quietSchedule: quietSchedule(),
        )
        let airAndSpace = try AirAndSpacePreferences(
            selectedSource: sourceSelection.selected,
            validatedSource: sourceSelection.validated,
            mapViewport: MapViewport(radius: NauticalMiles(value: mapRadius)),
            mapCenters: mapCenters,
            skyViewport: SkyViewport(
                minimumElevation: ElevationAngle(degrees: minimumElevation),
            ),
            selectedProjectionMode: projectionMode,
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
        let playlist: ProjectionPlaylist = if airAndSpace.isConfigured,
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
            setupCompleted: setupCompleted,
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
