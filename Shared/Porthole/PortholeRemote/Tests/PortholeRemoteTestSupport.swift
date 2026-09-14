import Foundation
import os
import PortholeCore
@testable import PortholeRemote

enum PortholeRemoteTestSupport {
    static let scope = PortholeScopeToken(id: .init(rawValue: "test"), generation: UUID())
    static func capability(effect: PortholeEffect) -> PortholeCapability {
        PortholeCapability(
            id: .init(rawValue: "test.operation"),
            module: .init(rawValue: "Test"),
            name: "Operation",
            summary: "Test operation",
            parameters: [],
            result: .string,
            effect: effect,
            source: nil,
            ownership: .adapter,
            availability: .callable,
        )
    }

    static func invocation() -> PortholeInvocation {
        PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "test.operation"),
            receiver: nil,
            arguments: .object([:]),
        )
    }

    static func dispatcher(executor: any PortholeExecuting) -> PortholeRemoteDispatcher {
        PortholeRemoteDispatcher(executor: executor) { PortholeRemoteApplication(
            applicationID: UUID(),
            name: "Test",
            scopes: [scope],
        ) }
    }
}

actor PortholeRemoteTestExecutor: PortholeExecuting {
    let effect: PortholeEffect
    var received: [PortholeInvocation] = []
    var stale = false
    var catalog: [PortholeCapability]?
    func setCatalog(_ capabilities: [PortholeCapability]) {
        catalog = capabilities
    }

    init(effect: PortholeEffect) {
        self.effect = effect
    }

    func invalidate() {
        stale = true
    }

    func capabilities(in _: PortholeScopeToken) throws -> [PortholeCapability] {
        guard !stale else { throw PortholeError.staleScope }
        return catalog ?? [PortholeRemoteTestSupport.capability(effect: effect)]
    }

    func invoke(_ invocation: PortholeInvocation) throws -> PortholeValue {
        guard !stale else { throw PortholeError.staleScope }
        received.append(invocation)
        if effect.requiresApproval { throw PortholeError.approvalRequired(.init(
            invocation: invocation,
            capability: PortholeRemoteTestSupport.capability(effect: effect),
        )) }
        return .string("result")
    }
}

actor PortholeRemoteTestTransport: PortholeRemoteTransport {
    let session: PortholeRemoteSession
    var isClosed = false
    var requests = 0
    var corruptRequestID = false
    var failAfterDispatch = false
    init(dispatcher: PortholeRemoteDispatcher) {
        session = dispatcher.makeSession()
    }

    func corruptResponses() {
        corruptRequestID = true
    }

    func loseReplies() {
        failAfterDispatch = true
    }

    func exchange(_ data: Data) async throws -> Data {
        guard !isClosed else { throw PortholeRemoteError.disconnected }
        requests += 1
        let request = try JSONDecoder().decode(PortholeRemoteRequest.self, from: data)
        let response = await session.respond(to: request)
        if failAfterDispatch { await close(); throw PortholeRemoteError.disconnected }
        guard !isClosed else { throw PortholeRemoteError.disconnected }
        return try JSONEncoder().encode(corruptRequestID ? PortholeRemoteResponse(
            requestID: UUID(),
            result: response.result,
        ) : response)
    }

    func close() async {
        isClosed = true
        await session.close()
    }
}

final class PortholeRemoteTestCounter: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)
    func increment() {
        value.withLock { $0 += 1 }
    }

    var count: Int {
        value.withLock { $0 }
    }
}
