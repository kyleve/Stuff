import LifecycleKit
import SwiftUI
import Testing

private struct WaitTimeoutError: Error {}

/// Polls `condition` on the main actor until it holds or the timeout elapses.
/// Sleeping yields to the runner's drive task between checks.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline {
            throw WaitTimeoutError()
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// A leaf view that runs `mark` when the host lays it out, so a test can
/// detect whether the container actually chose (and rendered) the branch it
/// sits in. Each test owns the `Bool`s `mark` flips, so there are no shared
/// fixtures.
struct ProbeView: View {
    let mark: () -> Void

    var body: some View {
        mark()
        return Color.clear.frame(width: 1, height: 1)
    }
}

/// A configurable typed step for container tests: identity, mode gating, and
/// a closure body (mirrors the fixture in LifecycleKit's own bundle).
struct FixtureStep<Input: Sendable, Output: Sendable>: LifecycleStep {
    let id: AnyHashable
    var modes: LifecycleModeSet = .all
    let body: @MainActor (Input, LifecycleStepContext) async throws -> Output

    init(
        _ id: AnyHashable,
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

/// A configurable gate for container tests, mirroring `FixtureStep`.
struct FixtureGate<Value: Sendable>: LifecycleGate {
    let id: AnyHashable
    var modes: LifecycleModeSet = .foreground
    var needed: @MainActor (Value) async -> Bool

    init(
        _ id: AnyHashable,
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
