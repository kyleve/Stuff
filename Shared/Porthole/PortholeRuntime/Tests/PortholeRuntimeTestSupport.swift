import Foundation
import PortholeRuntime

@MainActor
protocol PortholeActorValue: AnyObject {
    var count: Int { get set }
}

@MainActor
final class PortholeActorValueImplementation: PortholeActorValue {
    var count = 0
}

enum PortholeRuntimeTestSupport {
    static func makeRegistry() async -> PortholeRegistry {
        let registry = PortholeRegistry(
            journal: PortholeOperationJournal(url: nil),
            objectLimit: 20,
        )
        await registry.setEnabled(true)
        return registry
    }

    static func capability(effect: PortholeEffect) -> PortholeCapability {
        PortholeCapability(
            id: .init(rawValue: "test.operation"),
            module: .init(rawValue: "Test"),
            name: "Operation",
            summary: "Test operation",
            parameters: [],
            result: .any,
            effect: effect,
            source: nil,
            ownership: .adapter,
            availability: .callable,
        )
    }

    static func invocation(scope: PortholeScopeToken) -> PortholeInvocation {
        PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "test.operation"),
            receiver: nil,
            arguments: .object([:]),
        )
    }
}

actor PortholeTestGate {
    private var entered = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func enter() async {
        entered = true
        for waiter in arrivalWaiters {
            waiter.resume()
        }
        arrivalWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitForArrival() async {
        if entered { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

actor PortholeTestCounter {
    private(set) var count = 0
    func increment() -> Int {
        count += 1; return count
    }
}
