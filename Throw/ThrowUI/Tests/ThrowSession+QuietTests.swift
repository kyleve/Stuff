import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionQuietTests {
    @Test(arguments: TemporaryQuietWake.allCases)
    func temporaryWakeUsesTheTypedDuration(_ wake: TemporaryQuietWake) {
        let session = ThrowSession.fixture()
        let expectedExpiration = session.dateProvider.now().addingTimeInterval(wake.timeInterval)

        session.wakeQuietly(for: wake)

        #expect(session.temporaryWakeUntil == expectedExpiration)
    }
}
