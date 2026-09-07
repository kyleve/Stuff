import Observation
import ThrowCore

/// Keeps raw projection-control values outside the validated session preferences.
@MainActor
@Observable
final class ProjectionViewportSettingsModel {
    private let session: ThrowSession
    private(set) var mapViewportIsValid = true
    private(set) var skyViewportIsValid = true

    var projectionMode: ProjectionMode {
        didSet {
            guard oldValue != projectionMode else { return }
            session.updateProjectionMode(projectionMode)
        }
    }

    var mapRadius: Double {
        didSet {
            guard oldValue != mapRadius else { return }
            publishMapViewport()
        }
    }

    var minimumElevation: Double {
        didSet {
            guard oldValue != minimumElevation else { return }
            publishSkyViewport()
        }
    }

    init(session: ThrowSession) {
        self.session = session
        projectionMode = session.projectionMode
        mapRadius = session.mapRadius
        minimumElevation = session.minimumElevation
    }

    private func publishMapViewport() {
        do {
            let viewport = try MapViewport(radius: NauticalMiles(value: mapRadius))
            mapViewportIsValid = true
            let preferences = session.airAndSpacePreferences.replacingMapViewport(viewport)
            session.updateAirAndSpacePreferences(preferences)
        } catch is ThrowValidationError {
            mapViewportIsValid = false
        } catch {
            assertionFailure("Map viewport validation produced an unexpected error: \(error)")
            mapViewportIsValid = false
        }
    }

    private func publishSkyViewport() {
        do {
            let viewport = try SkyViewport(
                minimumElevation: ElevationAngle(degrees: minimumElevation),
            )
            skyViewportIsValid = true
            let preferences = session.airAndSpacePreferences.replacingSkyViewport(viewport)
            session.updateAirAndSpacePreferences(preferences)
        } catch is ThrowValidationError {
            skyViewportIsValid = false
        } catch {
            assertionFailure("Sky viewport validation produced an unexpected error: \(error)")
            skyViewportIsValid = false
        }
    }
}
