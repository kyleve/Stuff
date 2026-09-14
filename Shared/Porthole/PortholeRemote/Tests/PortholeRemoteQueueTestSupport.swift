import Foundation
import PortholeCore
@testable import PortholeRemote

/// Holds one transport exchange so tests can fill and close the client's request queue.
actor PortholeRemoteQueueTestTransport: PortholeRemoteTransport {
    var requests: [Data] = []
    private var pending: CheckedContinuation<Data, any Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var closed = false

    func exchange(_ request: Data) async throws -> Data {
        guard !closed else { throw PortholeRemoteError.disconnected }
        guard pending == nil else { throw PortholeRemoteError.connectionBusy }
        requests.append(request)
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func waitForRequest() async {
        if !requests.isEmpty { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func reply(_ value: Data) {
        pending?.resume(returning: value)
        pending = nil
    }

    func close() {
        closed = true
        pending?.resume(throwing: PortholeRemoteError.disconnected)
        pending = nil
    }
}
