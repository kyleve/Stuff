import Foundation
import Network
import os

/// Bounded frames over one TLS connection. Owners serialize requests; cancellation closes the
/// transport.
final class PortholeConnection: PortholeRemoteRequestReceiving {
    private enum StartState {
        case idle
        case waiting(CheckedContinuation<Void, any Error>)
        case finished(Result<Void, any Error>)
    }

    let network: NWConnection
    private let startState = OSAllocatedUnfairLock(initialState: StartState.idle)

    init(_ connection: NWConnection) {
        network = connection
    }

    func start() async throws {
        try await bounded { [self] in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                Void,
                any Error
            >) in
                let shouldStart = self.startState.withLock { state in
                    switch state {
                        case .idle: state = .waiting(continuation); return true
                        case .waiting:
                            continuation.resume(throwing: PortholeRemoteError.invalidMessage)
                            return false
                        case let .finished(result):
                            continuation.resume(with: result); return false
                    }
                }
                guard shouldStart else { return }
                self.network.stateUpdateHandler = { [weak self] state in
                    let result: Result<Void, any Error>? = switch state {
                        case .ready: .success(())
                        case let .failed(error): .failure(error)
                        case .cancelled: .failure(PortholeRemoteError.disconnected)
                        case .setup, .preparing, .waiting: nil
                        @unknown default: .failure(PortholeRemoteError.disconnected)
                    }
                    if let result { self?.finishStarting(result) }
                }
                self.network.start(queue: PortholeTLS.queue)
            }
        }
    }

    func cancel() {
        finishStarting(.failure(PortholeRemoteError.disconnected))
        network.cancel()
    }

    private func finishStarting(_ result: Result<Void, any Error>) {
        let continuation = startState.withLock { state -> CheckedContinuation<Void, any Error>? in
            switch state {
                case .idle: state = .finished(result); return nil
                case let .waiting(continuation): state = .finished(result); return continuation
                case .finished: return nil
            }
        }
        continuation?.resume(with: result)
    }

    func send(_ data: Data) async throws {
        let frame = try PortholeRemoteFraming.frame(data)
        try await bounded {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                Void,
                any Error
            >) in
                self.network.send(content: frame, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
        }
    }

    func receive() async throws -> Data {
        try await bounded {
            let header = try await self.read(count: 4)
            return try await self.read(count: PortholeRemoteFraming.size(header))
        }
    }

    /// An authenticated client can remain idle. Once its header arrives, the body still has a
    /// deadline.
    func receiveRequest() async throws -> Data {
        try await withTaskCancellationHandler {
            let header = try await read(count: 4)
            let count = try PortholeRemoteFraming.size(header)
            return try await bounded { try await self.read(count: count) }
        } onCancel: { self.cancel() }
    }

    private func read(count: Int) async throws -> Data {
        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            let remaining = count - result.count
            let chunk =
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                    Data,
                    any Error
                >) in
                    network
                        .receive(
                            minimumIncompleteLength: 1,
                            maximumLength: remaining,
                        ) { data, _, complete, error in
                            if let error { continuation.resume(throwing: error) }
                            else if let data, !data.isEmpty { continuation.resume(returning: data) }
                            else if complete {
                                continuation.resume(throwing: PortholeRemoteError.disconnected)
                            } else {
                                continuation.resume(throwing: PortholeRemoteError.invalidMessage)
                            }
                        }
                }
            result.append(chunk)
        }
        return result
    }

    private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async throws
        -> T) async throws -> T
    {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask(operation: operation)
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
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
