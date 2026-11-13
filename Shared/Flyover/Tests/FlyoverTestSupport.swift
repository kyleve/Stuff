import Foundation
import Testing

private struct FlyoverWaitTimeout: Error {
    let sourceLocation: SourceLocation
}

/// Holds the production settling boundary while a hosted test changes the viewport.
@MainActor
final class FlyoverSettlingGate {
    var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard isHeld else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isHeld = false
        let pending = waiters
        waiters.removeAll()
        // Release stale requests after newer ones to exercise supersession.
        for waiter in pending.reversed() {
            waiter.resume()
        }
    }
}

@MainActor
func waitForFlyover(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while condition() == false {
        guard ContinuousClock.now < deadline else {
            throw FlyoverWaitTimeout(sourceLocation: sourceLocation)
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}
