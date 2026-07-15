import Foundation
import Testing
import WhereCore

struct LocationAuthorizationTests {
    private func makeServices(
        status: LocationAuthorizationStatus,
    ) throws -> (WhereServices, ScriptedLocationSource) {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: status)
        return (WhereServices(store: store, locationSource: source), source)
    }

    @Test func authorizationStatusReflectsSource() async throws {
        let (services, _) = try makeServices(status: .whenInUse)
        #expect(await services.ingestor.authorizationStatus() == .whenInUse)
    }

    @Test func authorizationUpdatesYieldChanges() async throws {
        let (services, source) = try makeServices(status: .notDetermined)
        let updates = await services.ingestor.authorizationUpdates()
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

    @Test func allowsForegroundFixForAnyGrantedStatus() {
        #expect(LocationAuthorizationStatus.always.allowsForegroundFix)
        #expect(LocationAuthorizationStatus.whenInUse.allowsForegroundFix)
        #expect(!LocationAuthorizationStatus.notDetermined.allowsForegroundFix)
        #expect(!LocationAuthorizationStatus.denied.allowsForegroundFix)
        #expect(!LocationAuthorizationStatus.restricted.allowsForegroundFix)
    }

    @Test func isDeniedCoversDeniedAndRestricted() {
        #expect(LocationAuthorizationStatus.denied.isDenied)
        #expect(LocationAuthorizationStatus.restricted.isDenied)
        #expect(!LocationAuthorizationStatus.whenInUse.isDenied)
        #expect(!LocationAuthorizationStatus.notDetermined.isDenied)
    }
}
