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
        quietEnabled: Bool,
        quietStart: Date,
        quietEnd: Date,
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
        quietHoursEnabled = quietEnabled
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        setupCompleted = true
        isApplyingPreferences = false
        do {
            try await savePreferencesImmediately()
            scheduleDemandReconciliation()
        } catch is CancellationError {
            return
        } catch {
            setupCompleted = false
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
