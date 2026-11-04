import Testing
@testable import WhereCore

@MainActor
struct DataCompatibilityOutputQueueTests {
    @Test func withdrawalWaitsForSubmittedWorkEvenWhenItsCallerCancels() async throws {
        let access = try CompatibilityOutputTestSupport.access()
        let queue = DataCompatibilityOutputQueue(access: access)
        let gate = CompatibilityTestGate()
        let trace = CompatibilityOutputTrace()
        let publication = Task {
            await queue.publish {
                await gate.suspend()
                await trace.append(.published)
            }
        }
        await gate.waitUntilEntered()
        let retirement = Task {
            await queue.retire { await trace.append(.withdrawn) }
        }
        try await DataCompatibilityTestSupport.waitUntil { access.isRevoked }
        publication.cancel()
        await queue.publish { await trace.append(.unexpected) }
        #expect(await trace.events.isEmpty)
        await gate.resume()
        await publication.value
        await retirement.value
        await queue.retire { await trace.append(.unexpected) }
        #expect(await trace.events == [.published, .withdrawn])
    }

    @Test func revocationDropsWorkBeforeTheOwnerStartsWithdrawal() async throws {
        let access = try CompatibilityOutputTestSupport.access()
        let queue = DataCompatibilityOutputQueue(access: access)
        let trace = CompatibilityOutputTrace()
        access.revoke()
        await queue.publish { await trace.append(.unexpected) }
        await queue.retire { await trace.append(.withdrawn) }
        #expect(await trace.events == [.withdrawn])
    }
}
