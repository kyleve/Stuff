import Foundation
import os
@testable import PortholeRemote

/// Controlled frame delivery and EOF use the same receive seam as the TLS channel.
final class PortholeRemoteRequestReaderTestSource: PortholeRemoteRequestReceiving {
    private struct ProgressWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var frames: [Data]
        var pending: CheckedContinuation<Data, any Error>?
        var readWaiters: [ProgressWaiter] = []
        var readCount = 0
        var ended = false
    }

    private let state: OSAllocatedUnfairLock<State>

    init(frames: [Data]) {
        state = OSAllocatedUnfairLock(initialState: State(frames: frames))
    }

    var readCount: Int {
        state.withLock { $0.readCount }
    }

    var hasEnded: Bool {
        state.withLock { $0.ended }
    }

    func receiveRequest() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock { state in
                state.readCount += 1
                let ready = state.readWaiters.filter { $0.count <= state.readCount }
                state.readWaiters.removeAll { $0.count <= state.readCount }
                for waiter in ready {
                    waiter.continuation.resume()
                }
                if state.ended {
                    continuation.resume(throwing: PortholeRemoteError.disconnected)
                } else if !state.frames.isEmpty {
                    continuation.resume(returning: state.frames.removeFirst())
                } else {
                    precondition(state.pending == nil, "Only one reader can receive frames.")
                    state.pending = continuation
                }
            }
        }
    }

    func waitForReads(_ count: Int) async {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                if state.readCount >= count { continuation.resume() }
                else { state.readWaiters.append(ProgressWaiter(
                    count: count,
                    continuation: continuation,
                )) }
            }
        }
    }

    func finish() {
        state.withLock { state in
            guard !state.ended else { return }
            state.ended = true
            let pending = state.pending
            state.pending = nil
            pending?.resume(throwing: PortholeRemoteError.disconnected)
        }
    }

    func cancel() {
        finish()
    }
}
