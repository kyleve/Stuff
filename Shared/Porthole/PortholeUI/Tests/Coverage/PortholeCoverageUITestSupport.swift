import Foundation
import PortholeCore

@MainActor
final class PortholeCoverageUITestExecutor: PortholeExecuting {
    enum Reply {
        case value(PortholeValue), fail, suspend
    }

    var replies: [Reply]
    private(set) var invocations: [PortholeInvocation] = []
    private var continuation: CheckedContinuation<PortholeValue, Error>?

    init(replies: [Reply]) {
        self.replies = replies
    }

    func capabilities(in _: PortholeScopeToken) async throws -> [PortholeCapability] {
        []
    }

    func invoke(_ invocation: PortholeInvocation) async throws -> PortholeValue {
        invocations.append(invocation)
        guard !replies.isEmpty
        else { throw PortholeError.invalidArguments("No scripted coverage reply") }
        switch replies.removeFirst() {
            case let .value(value): return value
            case .fail: throw PortholeError.operationFailed("Coverage source is unavailable")
            case .suspend:
                return try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }

    func waitForSuspendedRead() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while continuation == nil {
            guard ContinuousClock.now < deadline
            else { throw PortholeError.operationFailed("Read did not suspend") }
            await Task.yield()
        }
    }

    func finish(_ value: PortholeValue) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: value)
    }
}
