import LifecycleKit
import Observation
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

/// Drives a presentation-visibility input from hosted tests without depending
/// on the test host application's real scene lifecycle.
@MainActor @Observable
final class PresentationVisibilityFixture {
    var isVisible: Bool

    init(_ isVisible: Bool) {
        self.isVisible = isVisible
    }
}

struct PresentationVisibilityOverride<Content: View>: View {
    let fixture: PresentationVisibilityFixture
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(fixture.isVisible)
    }
}

/// A configurable typed step for container tests: identity, mode gating, and
/// a closure body (mirrors the fixture in LifecycleKit's own bundle).
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

/// A configurable gate for container tests, mirroring `FixtureStep`.
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
