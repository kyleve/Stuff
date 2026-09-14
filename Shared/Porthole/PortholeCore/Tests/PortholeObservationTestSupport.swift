import Foundation
import PortholeCore

enum PortholeObservationTestSupport {
    static func request() -> PortholeObservationRequest {
        .init(
            id: .init(rawValue: UUID()),
            invocation: .init(
                id: UUID(),
                scope: .init(id: .init(rawValue: "test"), generation: UUID()),
                capabilityID: .init(rawValue: "value.read"),
                receiver: nil,
                arguments: .object(["number": .integer(Int64.max)]),
            ),
            intervalMilliseconds: 1000,
        )
    }
}

actor PortholeObservationRecordingExecutor: PortholeExecuting {
    let result: PortholeValue
    private(set) var invocations: [PortholeInvocation] = []

    init(result: PortholeValue) {
        self.result = result
    }

    func capabilities(in _: PortholeScopeToken) -> [PortholeCapability] {
        []
    }

    func invoke(_ invocation: PortholeInvocation) -> PortholeValue {
        invocations.append(invocation)
        return result
    }
}
