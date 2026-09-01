import Foundation
@_spi(Testing) import PeriscopeCore
import Testing
@_spi(Testing) @testable import ThrowCore

struct ThrowDurableLoggingTests {
    @Test func starterAttachesBeforeItReportsReadyAndPrunesHistory() async throws {
        let now = Date(timeIntervalSince1970: 1_787_594_400)
        let system = Periscope(
            configuration: .init(
                recentBufferCapacity: 20,
                pendingBufferCapacity: 20,
                liveBufferCapacity: 20,
                flushThreshold: .error,
                redact: nil,
            ),
            sinks: [],
        )
        let starter = PeriscopeThrowDurableLoggingStarter(
            system: system,
            storage: .inMemory,
            now: { now },
        )

        let loggingSession = try await starter.start()
        await system.flush()
        #expect(sessionEvents(in: system) == [.durableLoggingReady])

        await loggingSession.pruneHistory()
        await system.flush()
        #expect(sessionEvents(in: system) == [
            .durableLoggingReady,
            .durableLoggingHistoryPruned(
                expiredEventCount: 0,
                overflowEventCount: 0,
            ),
        ])
    }

    private func sessionEvents(in system: Periscope) -> [ThrowSessionLogEvent] {
        system.recentRecords().compactMap { $0.event as? ThrowSessionLogEvent }
    }
}
