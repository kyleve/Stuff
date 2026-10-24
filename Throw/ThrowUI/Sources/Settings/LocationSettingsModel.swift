import Observation
import ThrowCore

@MainActor
@Observable
final class LocationSettingsModel {
    private let session: ThrowSession

    var mode: ObserverLocationMode
    var latitude: Double
    var longitude: Double
    var altitudeFeet: Double
    var isSaving = false

    init(session: ThrowSession) {
        self.session = session
        mode = session.observerLocationMode
        latitude = session.observerLatitude
        longitude = session.observerLongitude
        altitudeFeet = session.observerAltitudeFeet
    }

    var health: LocationHealth {
        session.locationHealth
    }

    var postLaunchFailures: [ThrowPostLaunchFailure] {
        session.postLaunchFailures(for: .location)
    }

    func refresh() async {
        await session.refreshLocation()
        synchronizeAcceptedLocation()
    }

    func acceptBest() async {
        await session.acceptOfferedLocation()
        synchronizeAcceptedLocation()
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        _ = await session.saveObserverLocation(
            mode: mode,
            latitude: latitude,
            longitude: longitude,
            altitudeFeet: altitudeFeet,
        )
    }

    private func synchronizeAcceptedLocation() {
        mode = session.observerLocationMode
        latitude = session.observerLatitude
        longitude = session.observerLongitude
        altitudeFeet = session.observerAltitudeFeet
    }
}
