import Foundation
import Network
@testable import PortholeRemote
import Testing

struct PortholeConnectionTests {
    @Test(.timeLimit(
        .minutes(1),
    )) func cancellationBeforeStartCompletesWithoutWaitingForHandshake() async {
        let connection = PortholeConnection(NWConnection(host: "127.0.0.1", port: 9, using: .tcp))
        connection.cancel()
        await #expect(throws: (any Error).self) { try await connection.start() }
    }
}
