import Foundation
import PortholeCore

enum PortholeCoverageTestSupport {
    static func scope() -> PortholeScopeToken {
        .init(id: .init(rawValue: "coverage"), generation: UUID())
    }

    static func declaration() -> PortholeDeclarationCoverage {
        .init(
            id: .init(rawValue: "Fixture:read"),
            name: "read",
            kind: .function,
            signature: "() -> Int",
            source: .init(path: "Fixture.swift", line: 2),
            sourceSHA256: String(repeating: "a", count: 64),
            conditions: ["DEBUG"],
            plannedAvailability: .callable,
            origin: .generated,
        )
    }

    static func entry() -> PortholeCoverageEntry {
        .init(
            module: .init(rawValue: "Fixture"),
            declaration: declaration(),
            state: .inactive,
            installedCapabilityID: nil,
        )
    }
}

actor PortholeCoverageRecordingExecutor: PortholeExecuting {
    private(set) var invocations: [PortholeInvocation] = []
    let result: PortholeValue

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
