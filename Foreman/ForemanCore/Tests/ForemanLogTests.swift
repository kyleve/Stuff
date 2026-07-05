import ForemanCore
import Foundation
import LogKit
import Testing

struct ForemanLogTests {
    @Test func channelRoutesToSharedStoreWithTypedCategory() {
        let message = "ForemanLogTests probe \(UUID().uuidString)"
        ForemanLog.channel(.workerSupervisor).info(message)

        let entry = ForemanLog.store.snapshot().last { $0.message == message }
        #expect(entry?.subsystem == ForemanLog.subsystem)
        #expect(entry?.category == ForemanLog.Category.workerSupervisor.rawValue)
        #expect(entry?.level == .info)
    }
}
