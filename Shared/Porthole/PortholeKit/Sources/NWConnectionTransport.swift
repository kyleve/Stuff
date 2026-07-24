import Foundation
import Network
import PortholeCore

/// A ``PortholeTransport`` over an `NWConnection`. It applies the length-prefix
/// framing on the way out and reassembles whole frames on the way in, so the
/// layers above it (handshake, secure channel, router) speak only in frames.
///
/// Deliberately thin: all protocol logic lives above it and is tested over
/// `LoopbackTransport`, so this adapter is exercised only in real end-to-end use.
final class NWConnectionTransport: PortholeTransport, @unchecked Sendable {
    let incoming: AsyncThrowingStream<Data, Error>

    private let connection: NWConnection
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let framerLock = NSLock()
    private var framer = PortholeFramer()

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        (incoming, continuation) = AsyncThrowingStream.makeStream()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
                case let .failed(error):
                    self?.continuation.finish(throwing: error)
                case .cancelled:
                    self?.continuation.finish()
                default:
                    break
            }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    private func receiveNext() {
        connection
            .receive(
                minimumIncompleteLength: 1,
                maximumLength: 65536,
            ) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data, !data.isEmpty {
                    do {
                        let frames = try framerLock.withLock { try framer.ingest(data) }
                        for frame in frames {
                            continuation.yield(frame)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                        connection.cancel()
                        return
                    }
                }
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                if isComplete {
                    continuation.finish()
                    return
                }
                receiveNext()
            }
    }

    func send(_ frame: Data) async throws {
        let framed = try PortholeFraming.encode(frame)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            Void,
            Error
        >) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func close() async {
        connection.cancel()
    }
}
