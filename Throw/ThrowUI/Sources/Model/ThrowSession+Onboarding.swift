import Foundation
import ThrowCore

extension ThrowSession {
    func completeOnboarding(
        locationMode: LocationSelectionMode,
        latitude: Double,
        longitude: Double,
        observerAltitudeFeet: Double,
        validatedSourceDraft: ValidatedAircraftSourceDraft,
        projectionMode: ProjectionMode,
        calibration: ProjectionCalibration,
        quietSchedule: QuietSchedule,
        mapViewport: MapViewport,
        skyViewport: SkyViewport,
    ) async {
        guard onboardingCompletionInProgress == false else { return }
        onboardingCompletionInProgress = true
        defer { onboardingCompletionInProgress = false }

        if locationMode == .manual {
            guard await saveObserverLocation(
                mode: .manual,
                latitude: latitude,
                longitude: longitude,
                altitudeFeet: observerAltitudeFeet,
            ) else { return }
        } else {
            guard confirmedLocation != nil else {
                locationHealth = .missing
                return
            }
        }

        guard await useSource(validatedSourceDraft) else { return }

        guard beginPreferenceMutation() else { return }
        defer { finishPreferenceMutation() }

        let publication: OnboardingPreferencePublication
        while true {
            let candidate: OnboardingPreferencePublication
            do {
                guard let value = try onboardingPreferencePublication(
                    projectionMode: projectionMode,
                    calibration: calibration,
                    quietSchedule: quietSchedule,
                    mapViewport: mapViewport,
                    skyViewport: skyViewport,
                ) else {
                    assertionFailure("Onboarding completion requires validated setup inputs")
                    return
                }
                candidate = value
            } catch {
                recordPostLaunchFailure(.onboarding, error: error)
                return
            }
            do {
                try await persistPreferencesImmediately(
                    candidate.preferences,
                    failure: .onboarding,
                )
            } catch is CancellationError {
                return
            } catch {
                // The preference worker recorded this operation error.
                return
            }
            guard candidate.base == preferenceSnapshot else { continue }
            publication = candidate
            break
        }

        globalPreferences = publication.globalPreferences
        airAndSpacePreferences = publication.airAndSpacePreferences
        calibrationPreview = nil
        projectionPlaylist = publication.preferences.playlist
        applyExperienceCoordinatorState(ProjectionExperienceCoordinatorState(
            playlist: publication.preferences.playlist,
        ))
        setupState = publication.setupState
        resolveDeferredPreferenceFailuresAfterReconciledWrite()
        await configureExperienceCoordinator(with: projectionPlaylist)
        scheduleDemandReconciliation()
    }

    func previewCalibration(_ calibration: ProjectionCalibration) {
        guard projectionCalibration != calibration else { return }
        let bearingChanged = projectionCalibration.screenTopBearing
            != calibration.screenTopBearing
        calibrationPreview = calibration
        if bearingChanged {
            mayApplyTrueHeadingHint = false
        }
        restartRenderer()
    }

    func endCalibrationPreview() {
        guard calibrationPreview != nil else { return }
        calibrationPreview = nil
        restartRenderer()
    }

    private func onboardingPreferencePublication(
        projectionMode: ProjectionMode,
        calibration: ProjectionCalibration,
        quietSchedule: QuietSchedule,
        mapViewport: MapViewport,
        skyViewport: SkyViewport,
    ) throws -> OnboardingPreferencePublication? {
        let base = preferenceSnapshot
        guard let completedSetup = base.setupState.completing(
            projectionMode: projectionMode,
        ) else { return nil }
        let completedGlobalPreferences = base.globalPreferences
            .replacingCalibration(calibration)
            .replacingQuietSchedule(quietSchedule)
        let completedAirAndSpacePreferences = base.airAndSpacePreferences
            .replacingMapViewport(mapViewport)
            .replacingSkyViewport(skyViewport)
        let preferences = try makePreferences(
            setupState: completedSetup,
            globalPreferences: completedGlobalPreferences,
            airAndSpacePreferences: completedAirAndSpacePreferences,
            projectionPlaylist: base.projectionPlaylist,
        )
        return OnboardingPreferencePublication(
            base: base,
            setupState: completedSetup,
            globalPreferences: completedGlobalPreferences,
            airAndSpacePreferences: completedAirAndSpacePreferences,
            preferences: preferences,
        )
    }
}

/// A persisted onboarding candidate paired with the session values it was built from.
private struct OnboardingPreferencePublication {
    let base: ThrowPreferenceSnapshot
    let setupState: ThrowSetupState
    let globalPreferences: ThrowGlobalPreferences
    let airAndSpacePreferences: AirAndSpacePreferences
    let preferences: ThrowPreferences
}
