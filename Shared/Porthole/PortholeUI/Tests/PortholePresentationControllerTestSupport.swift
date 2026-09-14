import Foundation
@_spi(Testing) @testable import PortholeUI

@MainActor
final class PortholePresentationObserverTestProbe: PortholePresentationObserving {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func portholePresentationDidChange() {
        onChange()
    }
}

/// Suspends one owned refresh independently of the attachment task's cancellation.
@MainActor
final class PortholeScopeRefreshTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isSuspended: Bool {
        continuation != nil
    }

    func suspend() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }

    static func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        return predicate()
    }
}
