import Foundation
@testable import PortholeRuntime

struct PortholeRuntimeObservationFixture {
    let registry: PortholeRegistry
    let scope: PortholeScopeToken

    static func make(
        effect: PortholeEffect,
        handler: @escaping PortholeRegistry.Handler,
    ) async throws -> Self {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "observations"))
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: effect),
            in: scope,
            handler: handler,
        )
        return Self(registry: registry, scope: scope)
    }

    func request(receiver: PortholeObjectReference?) -> PortholeObservationRequest {
        .init(
            id: .init(rawValue: UUID()),
            invocation: .init(
                id: UUID(),
                scope: scope,
                capabilityID: .init(rawValue: "test.operation"),
                receiver: receiver,
                arguments: .object([:]),
            ),
            intervalMilliseconds: 1000,
        )
    }
}

actor PortholeObservationInvocationCounter {
    private(set) var invocations: [UUID] = []

    func sample(_ invocation: PortholeInvocation) -> PortholeValue {
        invocations.append(invocation.id)
        return .integer(Int64(invocations.count))
    }
}

enum PortholeObservationStoreTestSupport {
    static func request() -> PortholeObservationRequest {
        .init(
            id: .init(rawValue: UUID()),
            invocation: PortholeRuntimeTestSupport.invocation(scope: .init(
                id: .init(rawValue: "store"),
                generation: UUID(),
            )),
            intervalMilliseconds: 1000,
        )
    }

    static func start(
        _ request: PortholeObservationRequest,
        in store: inout PortholeObservationStore,
        generation: UUID,
        leaseID: UUID,
    ) throws {
        try store.validateStart(request, owner: nil)
        store.start(
            request,
            generation: generation,
            owner: nil,
            leaseID: leaseID,
            execute: { _ in .null },
            report: { _ in false },
        )
    }
}
