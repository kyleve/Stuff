@testable import LifecycleKit

/// A configurable typed step for engine/plan tests: identity, mode gating,
/// and a closure body, so each test declares exactly the behavior it needs
/// without minting a one-off conforming type.
struct FixtureStep<Input: Sendable, Output: Sendable>: LifecycleStep {
    let id: String
    var modes: LifecycleModeSet = .all
    let body: @MainActor (Input, LifecycleStepContext) async throws -> Output

    init(
        _ id: String,
        modes: LifecycleModeSet = .all,
        body: @escaping @MainActor (Input, LifecycleStepContext) async throws -> Output,
    ) {
        self.id = id
        self.modes = modes
        self.body = body
    }

    func run(_ input: Input, _ context: LifecycleStepContext) async throws -> Output {
        try await body(input, context)
    }
}

/// A configurable gate for engine/plan tests, mirroring `FixtureStep`.
struct FixtureGate<Value: Sendable>: LifecycleGate {
    let id: String
    var modes: LifecycleModeSet = .foreground
    var needed: @MainActor (Value) async -> Bool

    init(
        _ id: String,
        modes: LifecycleModeSet = .foreground,
        needed: @escaping @MainActor (Value) async -> Bool = { _ in true },
    ) {
        self.id = id
        self.modes = modes
        self.needed = needed
    }

    func isNeeded(_ value: Value) async -> Bool {
        await needed(value)
    }
}
