import Foundation
import Testing
import WhereCore
import WhereUI

/// Covers the launch-time reconciliation that fixes the "toggle is always off"
/// and "Grant does nothing" bugs: tracking and the authorization indicator must
/// reflect real authorization + persisted intent, not just the last tap.
@MainActor
struct WhereModelTrackingTests {
    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.WhereModelTracking.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeModel(
        status: LocationAuthorizationStatus,
        defaults: UserDefaults,
    ) throws -> (WhereModel, ScriptedLocationSource) {
        let source = ScriptedLocationSource(authorizationStatus: status)
        let controller = try WhereController(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
        )
        let model = WhereModel(controller: controller, defaults: defaults)
        return (model, source)
    }

    @Test func launchWithAlwaysResumesTracking() async throws {
        let (model, _) = try makeModel(status: .always, defaults: ephemeralDefaults())
        await model.start()
        #expect(model.authorizationStatus == .always)
        #expect(model.isTracking)
        #expect(!model.permissionDenied)
    }

    @Test func launchWithWhenInUseDoesNotTrack() async throws {
        let (model, _) = try makeModel(status: .whenInUse, defaults: ephemeralDefaults())
        await model.start()
        #expect(model.authorizationStatus == .whenInUse)
        #expect(!model.isTracking)
    }

    @Test func launchWithDeniedDoesNotTrackOrAlert() async throws {
        let (model, _) = try makeModel(status: .denied, defaults: ephemeralDefaults())
        await model.start()
        #expect(model.authorizationStatus == .denied)
        #expect(!model.isTracking)
        // Launch must not pop the Settings alert; that's reserved for taps.
        #expect(!model.permissionDenied)
    }

    @Test func stoppingTrackingPersistsAcrossLaunches() async throws {
        let defaults = ephemeralDefaults()
        let (model, _) = try makeModel(status: .always, defaults: defaults)
        await model.start()
        #expect(model.isTracking)

        await model.stopTracking()
        #expect(!model.isTracking)

        // A fresh model sharing the same defaults should stay paused even
        // though authorization is still Always.
        let (relaunched, _) = try makeModel(status: .always, defaults: defaults)
        await relaunched.start()
        #expect(!relaunched.isTracking)
    }

    @Test func grantingLaterStartsTrackingViaLiveUpdates() async throws {
        let (model, source) = try makeModel(status: .notDetermined, defaults: ephemeralDefaults())
        await model.start()
        #expect(!model.isTracking)

        // Simulate the user granting Always in the system prompt / Settings.
        source.emitAuthorization(.always)

        await waitUntil { model.isTracking }
        #expect(model.authorizationStatus == .always)
        #expect(model.isTracking)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: () -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate(), "condition was not met before timeout")
    }
}
