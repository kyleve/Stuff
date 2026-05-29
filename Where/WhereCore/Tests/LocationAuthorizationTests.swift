import Foundation
import Testing
import WhereCore

struct LocationAuthorizationTests {
    private func makeController(
        status: LocationAuthorizationStatus,
    ) throws -> (WhereController, ScriptedLocationSource) {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: status)
        return (WhereController(store: store, locationSource: source), source)
    }

    @Test func authorizationStatusReflectsSource() async throws {
        let (controller, _) = try makeController(status: .whenInUse)
        #expect(await controller.authorizationStatus() == .whenInUse)
    }

    @Test func authorizationUpdatesYieldChanges() async throws {
        let (controller, source) = try makeController(status: .notDetermined)
        let updates = await controller.authorizationUpdates()
        source.emitAuthorization(.always)

        var received: LocationAuthorizationStatus?
        for await status in updates {
            received = status
            break
        }
        #expect(received == .always)
    }

    @Test func allowsBackgroundTrackingOnlyForAlways() {
        #expect(LocationAuthorizationStatus.always.allowsBackgroundTracking)
        #expect(!LocationAuthorizationStatus.whenInUse.allowsBackgroundTracking)
        #expect(!LocationAuthorizationStatus.notDetermined.allowsBackgroundTracking)
        #expect(!LocationAuthorizationStatus.denied.allowsBackgroundTracking)
    }

    @Test func isDeniedCoversDeniedAndRestricted() {
        #expect(LocationAuthorizationStatus.denied.isDenied)
        #expect(LocationAuthorizationStatus.restricted.isDenied)
        #expect(!LocationAuthorizationStatus.whenInUse.isDenied)
        #expect(!LocationAuthorizationStatus.notDetermined.isDenied)
    }
}
