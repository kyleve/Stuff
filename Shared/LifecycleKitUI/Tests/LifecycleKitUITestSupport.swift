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

/// A configurable gate for container tests: identity, mode gating, and a
/// phantom `Value` (mirrors the fixture in LifecycleKit's own bundle). Steps
/// need no fixture in the function style — they're closures at the call site.
struct FixtureGate<Value: Sendable>: LifecycleGate {
    let id: AnyHashable
    var modes: LifecycleModeSet = .foreground

    init(_ id: AnyHashable, modes: LifecycleModeSet = .foreground) {
        self.id = id
        self.modes = modes
    }
}
