import Foundation
import Network
import os
@testable import PortholeRemote

final class PortholeNetworkTestListener: Sendable {
    private struct State {
        var cancelled = false
        var startWaiter: CheckedContinuation<Void, any Error>?
        var accepted: NWConnection?
        var waiter: CheckedContinuation<NWConnection, any Error>?
    }

    let listener: NWListener
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(parameters: NWParameters) throws {
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws {
        listener.newConnectionHandler = { [state] connection in
            state.withLock { state in
                guard !state.cancelled else { connection.cancel(); return }
                if let waiter = state
                    .waiter { state.waiter = nil; waiter.resume(returning: connection) }
                else { state.accepted = connection }
            }
        }
        try await bounded { [self] in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                Void,
                any Error
            >) in
                let shouldStart = state.withLock { state in
                    if state.cancelled {
                        continuation.resume(throwing: PortholeRemoteError.disconnected)
                        return false
                    }
                    state.startWaiter = continuation
                    return true
                }
                guard shouldStart else { return }
                listener.stateUpdateHandler = { [state] update in
                    let result: Result<Void, any Error>? = switch update {
                        case .ready: .success(())
                        case let .failed(error): .failure(error)
                        case .cancelled: .failure(PortholeRemoteError.disconnected)
                        case .setup, .waiting: nil
                        @unknown default: .failure(PortholeRemoteError.disconnected)
                    }
                    if let result { state.withLock { value in
                        value.startWaiter?.resume(with: result); value.startWaiter = nil
                    } }
                }
                listener.start(queue: PortholeTLS.queue)
            }
        }
    }

    func accept() async throws -> PortholeConnection {
        try await bounded { [self] in
            let connection =
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                    NWConnection,
                    any Error
                >) in
                    state.withLock { state in
                        guard !state.cancelled else {
                            continuation.resume(throwing: PortholeRemoteError.disconnected)
                            return
                        }
                        if let connection = state
                            .accepted
                        {
                            state.accepted = nil; continuation.resume(returning: connection)
                        } else { state.waiter = continuation }
                    }
                }
            return PortholeConnection(connection)
        }
    }

    func cancel() {
        listener.cancel()
        state.withLock { state in
            state.cancelled = true
            state.startWaiter?.resume(throwing: PortholeRemoteError.disconnected)
            state.startWaiter = nil
            state.accepted?.cancel(); state.accepted = nil
            state.waiter?.resume(throwing: PortholeRemoteError.disconnected); state.waiter = nil
        }
    }

    private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async throws
        -> T) async throws -> T
    {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask(operation: operation)
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    self.cancel()
                    throw PortholeRemoteError.timedOut
                }
                defer { group.cancelAll() }
                guard let value = try await group.next()
                else { throw PortholeRemoteError.disconnected }
                return value
            }
        } onCancel: { self.cancel() }
    }
}
