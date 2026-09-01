import Foundation
import ThrowCore

extension ThrowSession {
    func completeOnboarding(
        locationMode: LocationSelectionMode,
        latitude: Double,
        longitude: Double,
        observerAltitudeFeet: Double,
        validatedSourceDraft: ValidatedAircraftSourceDraft,
        mode: ProjectionMode,
        mapRadius: Double,
        minimumElevation: Double,
        screenTopBearing: Double,
        rotation: ScreenRotation,
        flipsHorizontally: Bool,
        flipsVertically: Bool,
        safeInsetPercent: Double,
        calibrationVerified: Bool,
        quietSchedule: QuietSchedule,
    ) async {
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

        isApplyingPreferences = true
        projectionMode = mode
        self.mapRadius = mapRadius
        self.minimumElevation = minimumElevation
        self.screenTopBearing = screenTopBearing
        screenRotation = rotation
        flipHorizontal = flipsHorizontally
        flipVertical = flipsVertically
        self.safeInsetPercent = safeInsetPercent
        self.calibrationVerified = calibrationVerified
        self.quietSchedule = quietSchedule
        let incompleteSetup = setupState
        guard let completedSetup = setupState.completing(projectionMode: mode) else {
            assertionFailure("Onboarding completion requires validated setup inputs")
            isApplyingPreferences = false
            return
        }
        setupState = completedSetup
        isApplyingPreferences = false
        do {
            try await savePreferencesImmediately()
            scheduleDemandReconciliation()
        } catch is CancellationError {
            return
        } catch {
            setupState = incompleteSetup
            settingsFailure = error.localizedDescription
        }
    }

    func previewCalibration(
        screenTopBearing: Double,
        rotation: ScreenRotation,
        flipsHorizontally: Bool,
        flipsVertically: Bool,
        safeInsetPercent: Double,
        calibrationVerified: Bool,
    ) {
        let bearingChanged = self.screenTopBearing != screenTopBearing
        isApplyingPreferences = true
        self.screenTopBearing = screenTopBearing
        screenRotation = rotation
        flipHorizontal = flipsHorizontally
        flipVertical = flipsVertically
        self.safeInsetPercent = safeInsetPercent
        self.calibrationVerified = calibrationVerified
        isApplyingPreferences = false
        if bearingChanged {
            mayApplyTrueHeadingHint = false
        }
    }
}
