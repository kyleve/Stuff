import Foundation
import PortholeCore
@testable import PortholeRemote
import Testing

struct PortholeRemoteDispatcherTests {
    @Test(arguments: [
        PortholeEffect.mutation,
        .unknown,
    ]) func returnsExactPendingProposal(effect: PortholeEffect) async {
        let executor = PortholeRemoteTestExecutor(effect: effect)
        let dispatcher = PortholeRemoteTestSupport.dispatcher(executor: executor)
        let invocation = PortholeRemoteTestSupport.invocation()
        let request = PortholeRemoteRequest(requestID: UUID(), operation: .invoke(invocation))
        let response = await dispatcher.respond(to: request)
        #expect(response.requestID == request.requestID)
        guard case let .approvalRequired(proposal) = response.result
        else { Issue.record("Expected approval proposal"); return }
        #expect(proposal.invocation == invocation)
        #expect(proposal.capability.effect == effect)
    }

    @Test func preservesStaleGenerationFailure() async {
        let executor = PortholeRemoteTestExecutor(effect: .read)
        await executor.invalidate()
        let response = await PortholeRemoteTestSupport.dispatcher(executor: executor)
            .respond(to: .init(
                requestID: UUID(),
                operation: .capabilities(
                    scope: PortholeRemoteTestSupport.scope,
                    offset: 0,
                    limit: 200,
                ),
            ))
        guard case let .failure(code, _) = response.result
        else { Issue.record("Expected stale scope"); return }
        #expect(code == "stale_scope")
    }
}
