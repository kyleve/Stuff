import Foundation
import Testing
import WhereCore

/// `IdleLocationSource` is deliberately inert — the App Intents stack uses it so
/// resolving an intent never starts GPS. These pin that it yields nothing and
/// reports "no fix / not determined" rather than doing any work.
struct IdleLocationSourceTests {
    @Test func reportsNoAuthorizationAndNoFix() async {
        let source = IdleLocationSource()
        #expect(await source.currentAuthorization() == .notDetermined)
        #expect(await source.requestCurrentLocation() == nil)
    }

    @Test func requestPermissionIsANoOpAndDoesNotThrow() async throws {
        try await IdleLocationSource().requestPermission()
    }

    @Test func sampleStreamFinishesWithoutYielding() async {
        let source = IdleLocationSource()
        var count = 0
        for await _ in source.sampleStream {
            count += 1
        }
        #expect(count == 0)
    }

    @Test func authorizationUpdatesFinishWithoutYielding() async {
        let source = IdleLocationSource()
        var count = 0
        for await _ in source.authorizationUpdates {
            count += 1
        }
        #expect(count == 0)
    }
}
